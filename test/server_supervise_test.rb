# frozen_string_literal: true

require_relative 'test_helper'
require 'ostruct'

# Behaviour test for the watcher-supervision helper added in review
# item #23. Before the fix, an exception inside `start_poll_watcher`
# (or the Listen callback) would silently kill the watcher thread —
# the dev server kept serving stale `_site/` content with no hot-
# reload and the operator had no obvious signal. After the fix, the
# `supervise(kind) { … }` wrapper logs each crash and restarts the
# body, giving up only after `MAX_RESTARTS` failures in
# `RESTART_WINDOW` seconds.
class ServerSuperviseTest < Minitest::Test
  def setup
    site = TestHelpers.built_site
    @server = Abqari::Server.new(site)
    # Shrink the inter-restart sleep so the give-up test completes in
    # tens of milliseconds rather than 5+ seconds. Production code
    # uses the 1s default; the env-var override exists for exactly
    # this — see Server#watcher_restart_backoff. Saved + restored
    # in teardown so concurrent specs don't inherit the override.
    @prev_backoff = ENV['ABQARI_WATCHER_RESTART_BACKOFF']
    ENV['ABQARI_WATCHER_RESTART_BACKOFF'] = '0.01'
  end

  def teardown
    ENV['ABQARI_WATCHER_RESTART_BACKOFF'] = @prev_backoff
  end

  def test_supervise_restarts_after_failure
    # Use a counter to throw on the first iteration and succeed on
    # the second. The supervise loop should call the block twice
    # and exit cleanly when the second call returns.
    #
    # `capture_io` swallows the deliberate `[error]` stderr line the
    # supervisor logs on the first failure — keeps test output clean
    # without weakening the assertion (we verify behaviour via the
    # `calls` counter, not stderr scraping).
    calls = 0
    thread = nil
    capture_io do
      thread = @server.send(:supervise, :test) do
        calls += 1
        raise 'boom on first attempt' if calls == 1

        # exit cleanly on the second call
      end

      # Backoff is 10ms in tests (see setup); 2s is plenty of headroom
      # for thread scheduling jitter even on a loaded CI runner.
      thread.join(2)
    end

    assert_equal 2, calls,
                 'supervise should restart the watcher body after a crash'
    refute thread.alive?, 'supervise should exit once the body returns cleanly'
  end

  def test_supervise_gives_up_after_too_many_restarts
    # Always raise. The supervisor logs each crash and restarts up to
    # MAX_RESTARTS times in RESTART_WINDOW seconds; after that it gives
    # up. The thread should exit (not loop forever).
    calls = 0
    thread = nil
    finished = nil
    capture_io do
      thread = @server.send(:supervise, :test) do
        calls += 1
        raise 'always broken'
      end

      # With backoff = 10ms (see setup), 5 retries take ~50ms. 2s
      # cap leaves room for thread scheduling jitter on slow CI.
      finished = thread.join(2)
    end

    refute_nil finished, 'supervise must eventually give up, not spin forever'
    assert calls >= Abqari::Server::MAX_RESTARTS + 1,
           "supervise should retry at least #{Abqari::Server::MAX_RESTARTS} times before giving up (got #{calls})"
  end
end

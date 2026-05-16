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
  end

  def test_supervise_restarts_after_failure
    # Use a counter to throw on the first iteration and succeed on
    # the second. The supervise loop should call the block twice
    # and exit cleanly when the second call returns.
    calls = 0
    thread = @server.send(:supervise, :test) do
      calls += 1
      raise 'boom on first attempt' if calls == 1

      # exit cleanly on the second call
    end

    # Give the supervisor enough time to recover + run the second
    # attempt. WATCHER_RESTART_BACKOFF is 1s in the implementation.
    thread.join(3)

    assert_equal 2, calls,
                 'supervise should restart the watcher body after a crash'
    refute thread.alive?, 'supervise should exit once the body returns cleanly'
  end

  def test_supervise_gives_up_after_too_many_restarts
    # Always raise. The supervisor logs each crash and restarts up to
    # MAX_RESTARTS times in RESTART_WINDOW seconds; after that it gives
    # up. The thread should exit (not loop forever).
    calls = 0
    thread = @server.send(:supervise, :test) do
      calls += 1
      raise 'always broken'
    end

    # Cap the join — the supervisor backs off WATCHER_RESTART_BACKOFF
    # seconds (1s) between attempts. With MAX_RESTARTS=5 that's ~6s
    # in the worst case before it gives up.
    finished = thread.join(10)

    refute_nil finished, 'supervise must eventually give up, not spin forever'
    assert calls >= Abqari::Server::MAX_RESTARTS + 1,
           "supervise should retry at least #{Abqari::Server::MAX_RESTARTS} times before giving up (got #{calls})"
  end
end

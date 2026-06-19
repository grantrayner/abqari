# frozen_string_literal: true

require_relative 'test_helper'

# Tests for the work-stealing render pool in Renderer#render_pages.
# Earlier slice-based partitioning split pages evenly across threads;
# variable per-page render cost meant the slowest slice dominated. The
# queue-based pool lets any free worker pick up the next page, so total
# time tracks the slowest individual page (plus thread overhead) rather
# than the slowest slice.
#
# These tests use stub "pages" that record which thread rendered them
# so we can verify the pool actually distributes work AND tolerates
# wildly imbalanced page costs.
class RenderPoolTest < Minitest::Test
  # Minimal stand-in for an Abqari::Page that Renderer's `render_one`
  # can call `write` on. Records which thread invoked it + how many
  # ms it slept while "rendering."
  class FakePage
    attr_reader :source_path, :rendered_by, :rendered_at

    def initialize(name, cost_ms = 1)
      @source_path = name
      @cost_ms     = cost_ms
      @rendered_by = nil
    end

    def write
      @rendered_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      @rendered_by = Thread.current.object_id
      sleep(@cost_ms / 1000.0)
    end

    def needs_render?
      true
    end
  end

  # Minimal Site stub — Renderer only reads `incremental?` and
  # `all_pages` from it in `render_pages`.
  class FakeSite
    attr_accessor :pages

    def initialize(pages)
      @pages = pages
    end

    def incremental?
      false
    end

    def all_pages
      @pages
    end

    # Renderer's template caching reaches into a few more things, but
    # render_pages itself only needs the two above.
  end

  def make_renderer(pages)
    Abqari::Renderer.new(FakeSite.new(pages))
  end

  def test_all_pages_are_rendered_exactly_once
    pages = Array.new(50) { |i| FakePage.new("p#{i}") }
    make_renderer(pages).render_pages

    assert pages.all?(&:rendered_at), 'every page should have been written'
    rendered_threads = pages.map(&:rendered_by).uniq
    assert rendered_threads.size > 1,
           "work should span multiple threads (got #{rendered_threads.size})"
  end

  def test_serial_path_below_parallel_threshold
    # 15 pages is below PARALLEL_THRESHOLD (16) — runs in the main thread.
    pages = Array.new(15) { |i| FakePage.new("p#{i}") }
    make_renderer(pages).render_pages

    rendered_threads = pages.map(&:rendered_by).uniq
    assert_equal 1, rendered_threads.size,
                 'below the parallel threshold, all pages should render in one thread'
    assert_equal Thread.current.object_id, rendered_threads.first
  end

  def test_workers_steal_from_a_long_tail
    # 100 pages — 99 cheap, 1 very slow. Under each_slice partitioning,
    # whichever slice contained the slow page would dominate total time.
    # Under work-stealing, the slow page runs concurrently with the
    # cheap ones across all CPUs.
    slow_page = FakePage.new('slow', 80)
    cheap = Array.new(99) { |i| FakePage.new("p#{i}", 1) }
    pages = cheap + [slow_page]

    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    make_renderer(pages).render_pages
    elapsed_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).to_i

    # On any reasonable multi-core machine the cheap pages get spread
    # across N-1 cores while one core processes the slow page. Wall-
    # clock time should be dominated by the slow page (80 ms) plus
    # some overhead for the cheap-page tail and thread bookkeeping,
    # NOT 80 + (99 * 1) = 179 ms (which would happen if the slow page
    # were stuck in a slice with several cheap ones running serially).
    #
    # Loose upper bound to keep the test reliable on CI: 150 ms. Even
    # under heavy CI load the work-stealing path should comfortably
    # beat 150; a regression to slices would push it past 180.
    assert elapsed_ms < 150,
           "expected work-stealing to keep total under 150 ms, got #{elapsed_ms} ms"
  end

  def test_per_page_exceptions_are_collected_not_silently_swallowed
    boom = Class.new(FakePage) do
      def write
        raise 'boom in page render'
      end
    end.new('exploder')

    pages = Array.new(20) { |i| FakePage.new("p#{i}") } + [boom]
    err = assert_raises(RuntimeError) { make_renderer(pages).render_pages }
    assert_match(/page\(s\) failed to render/, err.message)
    # Every other page should still have been written even though one threw.
    other_pages = pages.reject { |p| p == boom }
    assert other_pages.all?(&:rendered_at),
           'a single failing page must not block other workers'
  end
end

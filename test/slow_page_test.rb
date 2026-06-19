# frozen_string_literal: true

require_relative 'test_helper'
require 'fileutils'
require 'tmpdir'

# Slow-page detection in Renderer#render_one.
#
# Each `page.write` is timed; pages that cross `SLOW_PAGE_THRESHOLD_MS`
# produce a warning during render and a summary at end-of-build. This
# test exercises both halves via small in-memory stubs + log capture.
class SlowPageTest < Minitest::Test
  # Fake page whose `write` deliberately sleeps for `cost_ms` so we
  # can drive the slow path without needing a real ERB render.
  class FakePage
    attr_reader :source_path, :output_path

    def initialize(name, cost_ms:, html: '', url: nil)
      @source_path = name
      @url         = url || "/#{name}/"
      @cost_ms     = cost_ms
      @html        = html
      @tmpdir      = Dir.mktmpdir('abqari-slow-test')
      @output_path = File.join(@tmpdir, 'index.html')
    end

    def write
      sleep(@cost_ms / 1000.0) if @cost_ms.positive?
      File.write(@output_path, @html)
    end

    def url
      @url
    end

    def needs_render?
      true
    end

    def cleanup
      FileUtils.rm_rf(@tmpdir)
    end
  end

  class FakeSite
    def initialize(pages)
      @pages = pages
    end

    def incremental?
      false
    end

    def all_pages
      @pages
    end
  end

  def with_threshold(ms)
    original = Abqari::Renderer::SLOW_PAGE_THRESHOLD_MS
    Abqari::Renderer.send(:remove_const, :SLOW_PAGE_THRESHOLD_MS)
    Abqari::Renderer.const_set(:SLOW_PAGE_THRESHOLD_MS, ms)
    yield
  ensure
    Abqari::Renderer.send(:remove_const, :SLOW_PAGE_THRESHOLD_MS)
    Abqari::Renderer.const_set(:SLOW_PAGE_THRESHOLD_MS, original)
  end

  # Capture Log output for the duration of the block, then restore the
  # original streams. Log writes warnings to stderr and info to stdout.
  def capture_log
    out, err = StringIO.new, StringIO.new
    original_out = $stdout
    original_err = $stderr
    $stdout = out
    $stderr = err
    yield
    [out.string, err.string]
  ensure
    $stdout = original_out
    $stderr = original_err
  end

  # --- Threshold semantics --------------------------------------------

  def test_fast_pages_produce_no_slow_warning
    pages = Array.new(5) { |i| FakePage.new("fast#{i}", cost_ms: 0) }
    _, err = with_threshold(500) do
      capture_log { Abqari::Renderer.new(FakeSite.new(pages)).render_pages }
    end

    refute_match(/Slow page/, err, 'no warning for sub-threshold pages')
  ensure
    pages.each(&:cleanup)
  end

  def test_slow_page_emits_warning_with_url_and_time
    # 250 ms cost, 100 ms threshold → fires.
    pages = [FakePage.new('slow-one', cost_ms: 250, url: '/guides/slow-one/')]
    _, err = with_threshold(100) do
      capture_log { Abqari::Renderer.new(FakeSite.new(pages)).render_pages }
    end

    assert_match(%r{Slow page: /guides/slow-one/ took \d+ms}, err)
  ensure
    pages.each(&:cleanup)
  end

  def test_zero_threshold_disables_detection
    # 200 ms cost would normally trigger, but threshold of 0 = off.
    pages = [FakePage.new('would-be-slow', cost_ms: 200)]
    _, err = with_threshold(0) do
      capture_log { Abqari::Renderer.new(FakeSite.new(pages)).render_pages }
    end

    refute_match(/Slow page/, err, 'threshold=0 should suppress slow-page warnings entirely')
  ensure
    pages.each(&:cleanup)
  end

  # --- Cause inference ------------------------------------------------

  def test_cause_hint_for_image_heavy_page
    # Page with 25 <img> tags + 250 ms cost.
    html = "<html><body>#{'<img src="x.jpg">' * 25}</body></html>"
    pages = [FakePage.new('img-heavy', cost_ms: 250, html: html)]
    _, err = with_threshold(100) do
      capture_log { Abqari::Renderer.new(FakeSite.new(pages)).render_pages }
    end

    assert_match(/25 inline images/, err, 'should report image count as a likely cause')
  ensure
    pages.each(&:cleanup)
  end

  def test_cause_hint_for_code_heavy_page
    # Page with 12 <pre> blocks + 250 ms cost.
    html = "<html><body>#{'<pre><code>x</code></pre>' * 12}</body></html>"
    pages = [FakePage.new('code-heavy', cost_ms: 250, html: html)]
    _, err = with_threshold(100) do
      capture_log { Abqari::Renderer.new(FakeSite.new(pages)).render_pages }
    end

    assert_match(/12 code blocks/, err, 'should report code-block count')
  ensure
    pages.each(&:cleanup)
  end

  def test_cause_hint_for_toc_page
    html = '<html><body><nav class="toc">…</nav></body></html>'
    pages = [FakePage.new('toc-page', cost_ms: 250, html: html)]
    _, err = with_threshold(100) do
      capture_log { Abqari::Renderer.new(FakeSite.new(pages)).render_pages }
    end

    assert_match(/TOC/, err, 'should flag TOC presence')
  ensure
    pages.each(&:cleanup)
  end

  def test_cause_hint_for_large_output
    # ~250 KB of output to clear the 200 KB threshold.
    html = 'x' * (250 * 1024)
    pages = [FakePage.new('big', cost_ms: 250, html: html)]
    _, err = with_threshold(100) do
      capture_log { Abqari::Renderer.new(FakeSite.new(pages)).render_pages }
    end

    assert_match(/\d+ KB output/, err)
  ensure
    pages.each(&:cleanup)
  end

  # --- End-of-build summary -------------------------------------------

  def test_summary_lists_slowest_first
    # Three slow pages, varying cost. Summary should sort newest-first
    # by time. Use serial path (<16 pages) for deterministic ordering.
    pages = [
      FakePage.new('a', cost_ms: 150, url: '/a/'),
      FakePage.new('b', cost_ms: 300, url: '/b/'),
      FakePage.new('c', cost_ms: 200, url: '/c/')
    ]
    out, _ = with_threshold(100) do
      capture_log { Abqari::Renderer.new(FakeSite.new(pages)).render_pages }
    end

    assert_match(/Slow pages \(>100ms\): 3/, out)
    # Slowest (300ms /b/) listed first in the summary.
    summary_section = out[/Slow pages.*\z/m]
    refute_nil summary_section
    b_idx = summary_section.index('/b/')
    a_idx = summary_section.index('/a/')
    c_idx = summary_section.index('/c/')
    refute_nil b_idx
    assert b_idx < c_idx, '/b/ (300ms) should precede /c/ (200ms) in summary'
    assert c_idx < a_idx, '/c/ (200ms) should precede /a/ (150ms) in summary'
  ensure
    pages.each(&:cleanup)
  end

  def test_summary_is_silent_when_no_slow_pages
    pages = Array.new(3) { |i| FakePage.new("fast#{i}", cost_ms: 0) }
    out, _ = with_threshold(500) do
      capture_log { Abqari::Renderer.new(FakeSite.new(pages)).render_pages }
    end

    refute_match(/Slow pages/, out, 'no summary line when nothing crossed the threshold')
  ensure
    pages.each(&:cleanup)
  end

  # --- "What this means and what to try" explanation block ----------

  def test_summary_explains_each_triggered_cause_once
    # Two pages, three distinct cause types between them. The summary
    # should print one impact + advice block per cause TYPE — not per
    # occurrence — so the operator reads each explanation once even
    # when multiple pages share a cause.
    img_html  = '<html><body>' + ('<img src="x.jpg">' * 25) + '</body></html>'
    code_html = '<html><body>' + ('<pre><code>x</code></pre>' * 12) + '</body></html>'
    pages = [
      FakePage.new('img-a',  cost_ms: 150, html: img_html),
      FakePage.new('img-b',  cost_ms: 150, html: img_html),  # same cause as img-a
      FakePage.new('codey',  cost_ms: 150, html: code_html)
    ]
    out, _ = with_threshold(100) do
      capture_log { Abqari::Renderer.new(FakeSite.new(pages)).render_pages }
    end

    # Header section present.
    assert_match(/What this means and what to try:/, out)
    # Each unique cause type appears exactly once in the explanation
    # block (deduped — img-a and img-b share `many_images`).
    explanation_section = out[/What this means and what to try:.*\z/m]
    assert_equal 1, explanation_section.scan(/^\s+many_images:/).size,
                 'many_images explanation should appear exactly once even when shared by multiple pages'
    assert_equal 1, explanation_section.scan(/^\s+many_code_blocks:/).size
    # Each block carries both the impact sentence and the "Try:" advice.
    assert_match(/^\s+Try:/, explanation_section)
  ensure
    pages.each(&:cleanup)
  end

  def test_summary_explanations_silent_when_no_causes_inferred
    # A page slow for unknown reasons (no images, no code blocks, no
    # TOC, small output) — should still get a per-page warning but
    # no "What this means" block (nothing to explain).
    pages = [FakePage.new('mystery', cost_ms: 250, html: '<p>just a tiny page</p>')]
    Abqari::Hooks.clear!  # ensure no plugin-filter cause fires
    out, err = with_threshold(100) do
      capture_log { Abqari::Renderer.new(FakeSite.new(pages)).render_pages }
    end

    assert_match(%r{Slow page: /mystery/}, err, 'still emit per-page warning')
    refute_match(/What this means/, out, 'no explanations section when no causes inferred')
  ensure
    pages.each(&:cleanup)
  end
end

# frozen_string_literal: true

require_relative 'test_helper'
require 'fileutils'
require 'tmpdir'

# Spends `ms` of the calling thread's CPU — the clock slow-page
# detection reads. A `sleep` would register nothing.
module BurnCpu
  def self.call(ms)
    clock = Abqari::Renderer::PAGE_CLOCK
    stop = Process.clock_gettime(clock, :millisecond) + ms
    nil while Process.clock_gettime(clock, :millisecond) < stop
  end
end

# Slow-page detection in Renderer#render_one.
#
# Each `page.write` is timed; pages that cross `SLOW_PAGE_THRESHOLD_MS`
# produce a warning during render and a summary at end-of-build. This
# test exercises both halves via small in-memory stubs + log capture.
class SlowPageTest < Minitest::Test
  # Fake page whose `write` burns `cost_ms` of CPU so we can drive the
  # slow path without needing a real ERB render. `wait_ms` sleeps:
  # time passing with no work done.
  class FakePage
    attr_reader :source_path, :output_path, :writer

    def initialize(name, cost_ms:, wait_ms: 0, html: '', url: nil)
      @source_path = name
      @url         = url || "/#{name}/"
      @cost_ms     = cost_ms
      @wait_ms     = wait_ms
      @html        = html
      @tmpdir      = Dir.mktmpdir('abqari-slow-test')
      @output_path = File.join(@tmpdir, 'index.html')
    end

    def write
      @writer = Thread.current
      BurnCpu.call(@cost_ms) if @cost_ms.positive?
      sleep(@wait_ms / 1000.0) if @wait_ms.positive?
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

  def with_nprocessors(count)
    original = Etc.method(:nprocessors)
    Etc.singleton_class.send(:define_method, :nprocessors) { count }
    yield
  ensure
    Etc.singleton_class.send(:define_method, :nprocessors, original)
  end

  def with_cgroup(files)
    Dir.mktmpdir('abqari-cgroup') do |root|
      files.each do |rel, body|
        FileUtils.mkdir_p(File.dirname(File.join(root, rel)))
        File.write(File.join(root, rel), "#{body}\n")
      end
      yield root
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

    assert_match(%r{Slow page: /guides/slow-one/ took \d+ms of CPU}, err)
  ensure
    pages.each(&:cleanup)
  end

  # The Render false positives: a page that spends its time waiting
  # (for the GVL behind other render threads, or on a throttled
  # container) did almost no work and must not be reported slow.
  def test_time_spent_waiting_is_not_slow
    pages = [FakePage.new('waits', cost_ms: 0, wait_ms: 250)]
    _, err = with_threshold(100) do
      capture_log { Abqari::Renderer.new(FakeSite.new(pages)).render_pages }
    end

    refute_match(/Slow page/, err)
  ensure
    pages.each(&:cleanup)
  end

  # --- Thread pool ----------------------------------------------------

  # `Etc.nprocessors` is the host's count inside a container. Ruby
  # threads share one GVL, so a pool sized to a 64-CPU host only makes
  # every page wait longer for its turn.
  def test_pool_is_capped_whatever_the_host_reports
    pages = Array.new(40) { |i| FakePage.new("p#{i}", cost_ms: 0, wait_ms: 20) }
    with_nprocessors(64) do
      capture_log { Abqari::Renderer.new(FakeSite.new(pages)).render_pages }
    end

    assert_operator pages.map(&:writer).uniq.size, :<=, Abqari::Renderer::MAX_RENDER_THREADS
  ensure
    pages.each(&:cleanup)
  end

  def test_cgroup_v2_quota_limits_available_cpus
    with_cgroup('cpu.max' => '150000 100000') do |root|
      assert_equal [Etc.nprocessors, 2].min, Abqari::Renderer.available_cpus(cgroup_root: root)
    end
  end

  def test_cgroup_v2_without_quota_uses_nprocessors
    with_cgroup('cpu.max' => 'max 100000') do |root|
      assert_equal Etc.nprocessors, Abqari::Renderer.available_cpus(cgroup_root: root)
    end
  end

  def test_cgroup_v1_quota_limits_available_cpus
    with_cgroup('cpu/cpu.cfs_quota_us' => '50000', 'cpu/cpu.cfs_period_us' => '100000') do |root|
      assert_equal 1, Abqari::Renderer.available_cpus(cgroup_root: root)
    end
  end

  def test_no_cgroup_uses_nprocessors
    with_cgroup({}) do |root|
      assert_equal Etc.nprocessors, Abqari::Renderer.available_cpus(cgroup_root: root)
    end
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

    assert_match(/Slow pages \(>100ms CPU\): 3/, out)
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

# The plugin-filter cause against a real build, where filters run
# inside the renderer's post-processing. It used to be attached to
# every slow page whenever any `:post_process` hook was registered —
# 45 pages on one Render build — without the filter being timed.
class SlowPagePluginFilterTest < Minitest::Test
  def setup
    Abqari::Hooks.clear!
    @root = Dir.mktmpdir('abqari-slow-plugin')
    FileUtils.mkdir_p(File.join(@root, 'config'))
    File.write(File.join(@root, 'config', 'site.yml'), <<~YAML)
      title: Slow Plugin
      url: https://example.com
      indexable: true
      block_ai_scraping: false
    YAML
    FileUtils.mkdir_p(File.join(@root, 'content'))
    File.write(File.join(@root, 'content', 'index.md'), "---\ntitle: Home\n---\n\nHello.\n")
  end

  def teardown
    Abqari::Hooks.clear!
    FileUtils.rm_rf(@root)
  end

  def test_cheap_plugin_filter_is_not_named
    Abqari::Hooks.register(:post_process) { |html, _site, _page| html }
    burn_in_page_template(80)

    err = build_with_threshold(40)

    assert_match(/Slow page/, err, 'the page itself should still be reported')
    refute_match(/plugin filter/, err)
  end

  def test_expensive_plugin_filter_is_named_with_its_time
    Abqari::Hooks.register(:post_process) do |html, _site, _page|
      BurnCpu.call(80)
      html
    end

    err = build_with_threshold(40)

    assert_match(/Slow page: .* — plugin filter \d+ms/, err)
  end

  private

  # A layout that burns CPU through an ERB call, so the page is slow
  # for a reason that has nothing to do with the plugin.
  def burn_in_page_template(ms)
    FileUtils.mkdir_p(File.join(@root, 'app', 'views', 'layouts'))
    File.write(File.join(@root, 'app', 'views', 'layouts', 'busy.html.erb'),
               "<% BurnCpu.call(#{ms}) %><main><%= page.title %></main>\n")
    File.write(File.join(@root, 'content', 'index.md'), "---\ntitle: Home\nlayout: busy\n---\n\nHello.\n")
  end

  def build_with_threshold(ms)
    original = Abqari::Renderer::SLOW_PAGE_THRESHOLD_MS
    Abqari::Renderer.send(:remove_const, :SLOW_PAGE_THRESHOLD_MS)
    Abqari::Renderer.const_set(:SLOW_PAGE_THRESHOLD_MS, ms)
    prev = ENV.to_h.slice('ABQARI_SITE_ROOT', 'ABQARI_OUTPUT_DIR')
    ENV['ABQARI_SITE_ROOT']  = @root
    ENV['ABQARI_OUTPUT_DIR'] = File.join(@root, '_site')
    _out, err = capture_io { Abqari::Site.new.build }
    err
  ensure
    %w[ABQARI_SITE_ROOT ABQARI_OUTPUT_DIR].each { |k| ENV[k] = prev[k] } if prev
    Abqari::Renderer.send(:remove_const, :SLOW_PAGE_THRESHOLD_MS)
    Abqari::Renderer.const_set(:SLOW_PAGE_THRESHOLD_MS, original)
  end
end

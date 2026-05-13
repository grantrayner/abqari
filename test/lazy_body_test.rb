# frozen_string_literal: true

require_relative 'test_helper'
require 'tmpdir'

# Tests for Page#body lazy reload + forget_body!. The contract:
#
#   1. First read: served from the initial `parse` (no extra I/O).
#   2. After forget_body!: @body is nil, @content is nil; frontmatter
#      stays. A subsequent #body call re-reads the file.
#   3. Page#write calls forget_body! after writing — so a page that has
#      finished rendering frees its body. A later request for the same
#      page's description (which falls back to first_paragraph_text →
#      raw_body) lazily re-reads.
#   4. Concurrent reload is benign-racy: two threads can both miss the
#      cache, both re-read, both assign — same content, no corruption.
class LazyBodyTest < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir('abqari-lazy-body')
    @site   = build_site_stub(@tmpdir)
    @path   = File.join(@tmpdir, 'page.md')
    File.write(@path, <<~MD)
      ---
      title: Hello
      ---
      First paragraph here.

      Second paragraph.
    MD
  end

  def teardown
    FileUtils.rm_rf(@tmpdir)
  end

  def build_site_stub(root)
    site = Object.new
    site.define_singleton_method(:site_root) { root }
    site.define_singleton_method(:collections) { {} }
    site.define_singleton_method(:config) { {} }
    site
  end

  def test_body_is_available_after_parse
    page = Abqari::Page.new(@path, @site)
    assert_match(/First paragraph here\./, page.body)
  end

  def test_body_persists_in_memory_until_explicitly_forgotten
    page = Abqari::Page.new(@path, @site)
    page.body
    # Sneak a peek at the ivar — we want to confirm it's actually cached
    # rather than relying on lazy reload.
    assert page.instance_variable_get(:@body), 'expected @body to be cached after first read'
  end

  def test_forget_body_clears_body_and_content_but_keeps_frontmatter
    page = Abqari::Page.new(@path, @site)
    page.body          # populate @body
    page.content       # populate @content
    refute_nil page.instance_variable_get(:@body)
    refute_nil page.instance_variable_get(:@content)

    page.forget_body!
    assert_nil page.instance_variable_get(:@body)
    assert_nil page.instance_variable_get(:@content)
    # Frontmatter stays — it's used by taxonomy / sitemap / feed.
    assert_equal 'Hello', page.frontmatter['title']
  end

  def test_body_lazily_reloads_after_forget
    page = Abqari::Page.new(@path, @site)
    original = page.body.dup
    page.forget_body!

    # Re-read should hit disk again and return the same content.
    assert_equal original, page.body
    refute_nil page.instance_variable_get(:@body)
  end

  def test_body_reload_picks_up_disk_changes
    # Documents the lazy-reload semantic: if the file changed between
    # forget and the next read, the new content is served. This isn't
    # a feature we rely on in normal builds (the build doesn't mutate
    # content/ files), but it's the correct behaviour and worth pinning.
    page = Abqari::Page.new(@path, @site)
    page.body
    page.forget_body!

    File.write(@path, <<~MD)
      ---
      title: Hello
      ---
      Replaced body content.
    MD

    assert_match(/Replaced body content\./, page.body)
  end

  def test_raw_body_routes_through_body
    page = Abqari::Page.new(@path, @site)
    assert_equal page.body, page.raw_body
  end

  def test_first_paragraph_description_works_after_forget
    # Reproduces the cross-page interaction: post1 has been written and
    # forgotten; posts_index then asks for post1.description which falls
    # back to first_paragraph_text → raw_body → body (lazy reload).
    page = Abqari::Page.new(@path, @site)
    page.forget_body!
    assert_match(/First paragraph here\./, page.description)
  end

  def test_concurrent_reload_is_safe
    # Twenty threads simultaneously read body after forget. None should
    # raise; all should see the same content.
    page = Abqari::Page.new(@path, @site)
    page.forget_body!

    results = []
    mutex = Mutex.new
    threads = Array.new(20) do
      Thread.new do
        b = page.body
        mutex.synchronize { results << b }
      end
    end
    threads.each(&:join)
    assert_equal 20, results.size
    assert_equal 1, results.uniq.size, 'all threads should see identical body content'
  end
end

# frozen_string_literal: true

require_relative 'test_helper'
require 'ostruct'
require 'tmpdir'

# Regression tests for the second (Medium/Low) hardening pass: audit
# link-resolution accuracy, security.txt Contact normalisation, manifest
# icon existence, syntax-highlighter idempotency, redirect stub hardening,
# reserved render-locals, HttpSafe HTTPS/SSRF guards, and cover-key
# disambiguation.

class AuditLinkResolutionTest < Minitest::Test
  def links_rule
    site = OpenStruct.new(output_dir: '/site/_site')
    site.define_singleton_method(:config) { { 'url' => 'https://example.com' } }
    Abqari::Audit::Links.new(site, [])
  end

  def test_relative_link_resolves_against_directory_url
    # A bundle asset `hero.jpg` on `/posts/foo/` must resolve to
    # `/posts/foo/hero.jpg`, NOT `/posts/hero.jpg` (the old File.dirname bug).
    r = links_rule
    assert_equal '/posts/foo/hero.jpg', r.send(:resolve_target, 'hero.jpg', '/posts/foo/')
  end

  def test_relative_link_from_flat_page
    r = links_rule
    assert_equal '/sibling.html', r.send(:resolve_target, 'sibling.html', '/about.html')
  end

  def test_dotdot_segments_collapse
    r = links_rule
    assert_equal '/posts/other/', r.send(:resolve_target, '../other/', '/posts/foo/')
  end

  def test_root_relative_link_is_normalised
    r = links_rule
    assert_equal '/assets/x.css', r.send(:resolve_target, '/assets/x.css', '/posts/foo/')
  end

  def test_references_include_src_and_srcset
    r = links_rule
    html = '<img src="/a.jpg" srcset="/b.avif 1x, /c.webp 2x"><a href="/d/">x</a>'
    refs = r.send(:references, html)
    assert_includes refs, '/a.jpg'
    assert_includes refs, '/b.avif'
    assert_includes refs, '/c.webp'
    assert_includes refs, '/d/'
  end
end

class SecurityTxtContactTest < Minitest::Test
  def build(contact)
    site = OpenStruct.new
    site.define_singleton_method(:config) { { 'security_contact' => contact, 'locale' => 'en' } }
    Abqari::SecurityTxt.new(site).send(:build, contact)
  end

  def test_bare_email_gets_mailto_scheme
    assert_includes build('sec@example.com'), 'Contact: mailto:sec@example.com'
  end

  def test_existing_scheme_is_preserved
    assert_includes build('https://example.com/security'), 'Contact: https://example.com/security'
    assert_includes build('mailto:sec@example.com'), 'Contact: mailto:sec@example.com'
  end
end

class ManifestIconExistenceTest < Minitest::Test
  def setup
    @root = Dir.mktmpdir('abqari-manifest')
    FileUtils.mkdir_p(File.join(@root, 'public'))
    @site = OpenStruct.new(site_root: @root)
    @site.define_singleton_method(:config) { { 'title' => 'T' } }
  end

  def teardown
    FileUtils.rm_rf(@root)
  end

  def payload
    Abqari::Manifest.new(@site).send(:payload)
  end

  def test_omits_default_icons_when_files_absent
    refute payload.key?('icons'), 'should not advertise icons that were never generated'
  end

  def test_includes_default_icons_that_exist
    File.write(File.join(@root, 'public', 'icon-192.png'), 'x')
    icons = payload['icons']
    assert icons
    assert_equal ['/icon-192.png'], icons.map { |i| i['src'] }
  end
end

class SyntaxHighlighterDecodeTest < Minitest::Test
  def test_process_is_idempotent
    html = %(<pre><code class="language-ruby">x = 1 &amp;&amp; 2</code></pre>)
    once  = Abqari::SyntaxHighlighter.process(html)
    twice = Abqari::SyntaxHighlighter.process(once)
    assert_equal once, twice, 'already-highlighted blocks must not be reprocessed'
    assert_includes once, 'class="highlight"'
  end
end

class RedirectStubHardeningTest < Minitest::Test
  RPage = Struct.new(:source_path, :url, :frontmatter) do
    def respond_to?(m, *)
      %i[source_path url frontmatter].include?(m) || super
    end
  end

  def test_whitespace_in_from_is_rejected
    dir = Dir.mktmpdir('abqari-redir-hard')
    site = OpenStruct.new(output_dir: dir)
    pages = [RPage.new('a.md', '/new/', { 'redirect_from' => ['/old page/'] })]
    site.define_singleton_method(:all_pages) { pages }
    site.define_singleton_method(:config) { {} }
    err = assert_raises(RuntimeError) { Abqari::Redirects.new(site).send(:collect) }
    assert_includes err.message, 'whitespace'
  ensure
    FileUtils.rm_rf(dir)
  end

  def test_stub_carries_noindex_and_pagefind_ignore
    dir = Dir.mktmpdir('abqari-redir-stub')
    site = OpenStruct.new(output_dir: dir)
    site.define_singleton_method(:config) { { 'url' => 'https://example.com' } }
    Abqari::Redirects.new(site).send(:write_stub, '/old/', '/new/')
    html = File.read(File.join(dir, 'old', 'index.html'))
    assert_includes html, '<meta name="robots" content="noindex">'
    assert_includes html, 'data-pagefind-ignore'
  ensure
    FileUtils.rm_rf(dir)
  end

  def test_extension_bearing_from_writes_at_that_path
    dir = Dir.mktmpdir('abqari-redir-ext')
    site = OpenStruct.new(output_dir: dir)
    site.define_singleton_method(:config) { { 'url' => 'https://example.com' } }
    Abqari::Redirects.new(site).send(:write_stub, '/old-page.html', '/new/')
    assert File.exist?(File.join(dir, 'old-page.html')), 'stub should be the file itself, not old-page.html/index.html'
    refute File.exist?(File.join(dir, 'old-page.html', 'index.html'))
  ensure
    FileUtils.rm_rf(dir)
  end
end

class ReservedLocalsTest < Minitest::Test
  def test_shadowing_h_raises
    site = TestHelpers.built_site
    err = assert_raises(ArgumentError) do
      Abqari::RenderContext.new(site.pages.first, site, h: 'nope')
    end
    assert_includes err.message, 'shadow'
  end

  def test_page_local_is_allowed
    site = TestHelpers.built_site
    # `page:` rebinding + arbitrary partial locals are supported — no raise.
    Abqari::RenderContext.new(site.pages.first, site, pub: { 'title' => 'x' })
  end
end

class HttpSafeGuardsTest < Minitest::Test
  def test_authorization_over_http_raises
    err = assert_raises(ArgumentError) do
      Abqari::HttpSafe.request(:get, 'http://example.com',
                               headers: { 'Authorization' => 'Bearer x' })
    end
    assert_includes err.message, 'cleartext'
  end

  def test_block_private_rejects_loopback
    assert_raises(Abqari::HttpSafe::BlockedHostError) do
      Abqari::HttpSafe.send(:assert_public_host!, URI('http://127.0.0.1/x'))
    end
  end

  def test_block_private_rejects_link_local_metadata
    assert_raises(Abqari::HttpSafe::BlockedHostError) do
      Abqari::HttpSafe.send(:assert_public_host!, URI('http://169.254.169.254/latest/'))
    end
  end

  def test_block_private_rejects_rfc1918
    assert_raises(Abqari::HttpSafe::BlockedHostError) do
      Abqari::HttpSafe.send(:assert_public_host!, URI('http://10.0.0.5/x'))
    end
  end

  def test_public_ip_passes
    # 8.8.8.8 is public — no raise (pure IP classification, no network call).
    Abqari::HttpSafe.send(:assert_public_host!, URI('http://8.8.8.8/'))
  end
end

class CoverImagePathTest < Minitest::Test
  include Abqari::RenderContext::CoverHelpers

  def page_with(cover)
    OpenStruct.new(frontmatter: { 'cover' => cover })
  end

  def test_mode_values_are_not_image_paths
    %w[svg none photo photo_or_svg].each do |mode|
      assert_nil cover_image_path(page_with(mode)), "#{mode} is a mode, not a path"
    end
  end

  def test_boolean_is_not_an_image_path
    assert_nil cover_image_path(page_with(false))
  end

  def test_real_path_is_returned
    assert_equal '/covers/x.jpg', cover_image_path(page_with('/covers/x.jpg'))
  end
end

class SitemapNoindexTest < Minitest::Test
  def sitemap
    Abqari::Sitemap.new(OpenStruct.new(config: {}))
  end

  def test_noindex_pages_are_skipped
    page = OpenStruct.new(url: '/secret/', frontmatter: { 'robots' => 'noindex, nofollow' })
    assert sitemap.send(:skip?, page)
  end

  def test_normal_pages_are_not_skipped
    page = OpenStruct.new(url: '/public/', frontmatter: {})
    refute sitemap.send(:skip?, page)
  end
end

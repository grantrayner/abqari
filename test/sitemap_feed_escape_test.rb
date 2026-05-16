# frozen_string_literal: true

require_relative 'test_helper'
require 'ostruct'
require 'rexml/document'

# Sitemap + RSS XML-escape tests. The review §6 finding: a stray `&` in
# `config['url']` or in a frontmatter image path produced invalid XML
# because URLs were interpolated raw into `<loc>` / `<link>` /
# `<image:loc>` / `<atom:link href=>`. These tests pin every emitter
# to a single contract: every interpolated value is CGI-escaped, and
# the emitted document parses as well-formed XML even when the input
# contains ampersands.
class SitemapFeedEscapeTest < Minitest::Test
  # --- Sitemap ----------------------------------------------------------

  def make_sitemap_site(url, pages)
    site = OpenStruct.new(
      output_dir: '/tmp/__abqari_sitemap_test',
      site_root: '/tmp/__abqari_sitemap_test',
      all_pages: pages
    )
    def site.config; @cfg ||= {}; end
    site.instance_variable_set(:@cfg, 'url' => url)
    site
  end

  def make_page(url:, lastmod: Time.now, bundle_images: [])
    OpenStruct.new(url: url, lastmod: lastmod, bundle_images: bundle_images, frontmatter: {})
  end

  def test_sitemap_escapes_ampersand_in_url
    page = make_page(url: '/q?a=1&b=2/') # constructed to test escape behaviour
    sitemap = Abqari::Sitemap.new(make_sitemap_site('https://example.com/', [page]))
    xml = sitemap.send(:build, 'https://example.com')

    refute_includes xml, 'a=1&b=2'             # raw ampersand would be there if unescaped
    assert_includes xml, 'a=1&amp;b=2'
    REXML::Document.new(xml)                    # parses without raising
  end

  def test_sitemap_escapes_image_loc
    page = make_page(url: '/post/', bundle_images: ['/img/hero&dark.jpg'])
    sitemap = Abqari::Sitemap.new(make_sitemap_site('https://example.com', [page]))
    xml = sitemap.send(:build, 'https://example.com')

    assert_includes xml, '<image:loc>https://example.com/img/hero&amp;dark.jpg</image:loc>'
    REXML::Document.new(xml)
  end

  # --- RSS feed ---------------------------------------------------------

  def make_feed_site
    site = OpenStruct.new(
      output_dir: '/tmp/__abqari_feed_test',
      collections: { 'posts' => { 'enabled' => true } }
    )
    def site.config
      @cfg ||= { 'url' => 'https://example.com', 'title' => 'T & T', 'description' => 'D&D' }
    end
    def site.collection_config(_)
      { 'slug' => '' }
    end
    def site.collection(_)
      @pages || []
    end
    site
  end

  def test_feed_escapes_channel_metadata
    site = make_feed_site
    post = OpenStruct.new(
      title: 'Post & Co',
      url: '/posts/post-co/',
      date: Time.utc(2026, 5, 16),
      description: 'A & B'
    )
    site.instance_variable_set(:@pages, [post])

    rss = Abqari::Feed.new(site, 'posts').send(:rss)

    # Channel title escaped
    assert_includes rss, '<title>T &amp; T</title>'
    # Item title escaped
    assert_includes rss, '<title>Post &amp; Co</title>'
    # Channel link escaped (the `/` itself doesn't need escape, but the
    # ampersand from a future config change would; description does)
    assert_includes rss, '<description>D&amp;D</description>'
    # The whole document should parse as valid XML
    REXML::Document.new(rss)
  end

  def test_feed_escapes_item_url
    site = make_feed_site
    # Construct a URL with `&` (a paginated archive shard could in theory
    # carry one if the permalink template is ever loosened).
    post = OpenStruct.new(
      title: 'X',
      url: '/posts/x?ref=feed&utm_source=rss/',
      date: Time.utc(2026, 5, 16),
      description: 'd'
    )
    site.instance_variable_set(:@pages, [post])

    rss = Abqari::Feed.new(site, 'posts').send(:rss)

    refute_includes rss, 'ref=feed&utm_source'   # would only appear unescaped
    assert_includes rss, 'ref=feed&amp;utm_source'
    REXML::Document.new(rss)
  end
end

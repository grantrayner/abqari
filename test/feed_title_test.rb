# frozen_string_literal: true

require_relative 'test_helper'
require 'ostruct'

# Feed <title> must match the `<link rel="alternate" title="…">` the
# head partial advertises. The head builds its label from the EFFECTIVE
# collection name (slug when aliased), so the feed must too — a
# `posts → stories` site's feed reads "Site — Stories", not "Site".
class FeedTitleTest < Minitest::Test
  def make_site(slug: '')
    site = OpenStruct.new(
      output_dir: '/tmp/__abqari_feed_title_test',
      collections: { 'posts' => { 'enabled' => true } }
    )
    def site.config
      @cfg ||= { 'url' => 'https://example.com', 'title' => 'T' }
    end
    site.define_singleton_method(:collection_config) { |_| { 'slug' => slug } }
    def site.collection(_)
      []
    end
    site
  end

  def test_unaliased_posts_feed_uses_bare_site_title
    rss = Abqari::Feed.new(make_site, 'posts').send(:rss)
    assert_includes rss, '<title>T</title>'
  end

  def test_slug_aliased_posts_feed_carries_the_alias
    rss = Abqari::Feed.new(make_site(slug: 'stories'), 'posts').send(:rss)
    assert_includes rss, '<title>T — Stories</title>'
  end

  def test_fixture_guides_feed_title_matches_head_autodiscovery
    # The engine fixture aliases posts to /guides/ — the built feed and
    # every page's autodiscovery <link> must agree on the label.
    feed = TestHelpers.read_output('guides/feed.xml')
    assert_includes feed, '<title>Abqari — Guides</title>'

    home = TestHelpers.read_output('index.html')
    assert_match(/rel="alternate"[^>]*title="Abqari — Guides"/, home)
  end
end

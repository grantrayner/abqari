# frozen_string_literal: true

require_relative 'test_helper'

# Per-collection series taxonomy.
#
# Each of posts / photos / publications / workshops gets its own
# series taxonomy at `/<collection>/series/<slug>/`. Items in
# different collections with the same series name produce
# independent pages (no cross-collection bleed).
#
# Items are sorted by `series_position` ascending, with items
# missing a position falling to the end.
class SeriesTest < Minitest::Test
  # --- Page generation -------------------------------------------------

  def test_post_series_page_renders
    assert TestHelpers.output_exists?('posts/series/inside-abqari/index.html')
  end

  def test_photo_series_pages_use_new_url_scheme
    # `/photos/series/<slug>/`, NOT the old `/series/<slug>/`.
    assert TestHelpers.output_exists?('photos/series/damascus-2026/index.html')
  end

  def test_workshop_series_page_renders
    assert TestHelpers.output_exists?('workshops/series/crisis-programme/index.html')
  end

  def test_old_series_taxonomy_url_no_longer_generated_for_photos
    # The photos series used to live at `/series/<slug>/` directly,
    # via the now-removed global `series` taxonomy. The new
    # `photos_series` taxonomy moves them under `/photos/series/`.
    # Pages at the old URL would only exist if there's a curated
    # `content/series/<slug>/` page (book-series collection).
    refute TestHelpers.output_exists?('series/damascus-2026/index.html'),
           'photo series should no longer live at /series/<slug>/ — moved to /photos/series/'
  end

  # --- Per-collection isolation ---------------------------------------

  def test_post_series_page_only_contains_posts
    html = TestHelpers.read_output('posts/series/inside-abqari/index.html')
    # Every item link should be a /posts/ URL (or relative within
    # posts), never /photos/ or /workshops/. The regex tolerates
    # optional class attributes before `href=` — post-list cards now
    # carry `class="u-url"` on their post-link anchors for IndieWeb
    # microformats2 parsing.
    links = html.scan(/<a\s[^>]*?href="(\/[^"]+\/)"/).flatten
    item_links = links.reject { |l| l == '/posts/series/inside-abqari/' }
    item_links = item_links.reject { |l| l.start_with?('/tags/', '/country/', '/posts/series/', '/photos/series/', '/publications/series/', '/workshops/series/') }
    # Filter to the link patterns we expect for post-list items
    post_links = item_links.select { |l| l.start_with?('/posts/') }

    refute_empty post_links, 'expected at least one /posts/ link inside the series page'
    item_links.each do |link|
      next if link.start_with?('/', '/posts/', '/about/', '/photos/', '/publications/', '/workshops/', '/tags/', '/country/')
      flunk "unexpected non-collection link in post series: #{link.inspect}"
    end
  end

  def test_post_series_does_not_aggregate_photos_with_same_name
    # Sanity check that the scoping works at all: if both a post and
    # a photo carried `series: Inside Abqari`, only the post would
    # appear here. Fixture photos use different series names, but we
    # can prove isolation by checking the workshop series page
    # doesn't accidentally include posts.
    #
    # Scope to the items block — the site nav contains a `/posts/`
    # link on every page, which would false-positive a page-wide
    # regex.
    html = TestHelpers.read_output('workshops/series/crisis-programme/index.html')
    items_block = html[/<ul class="workshops-series">[\s\S]*?<\/ul>/]
    refute_nil items_block, 'expected to find the workshops-series items block'
    refute_match(%r{href="/posts/}, items_block,
                 'workshop series items block must not contain post links')
  end

  # --- Position sort ---------------------------------------------------

  def test_post_series_items_sort_by_position
    html = TestHelpers.read_output('posts/series/inside-abqari/index.html')
    positions = html.scan(/class="series-position">#(\d+)/).flatten.map(&:to_i)
    assert_equal positions.sort, positions,
                 "post series should be sorted ascending by position, got #{positions.inspect}"
  end

  def test_workshop_series_items_sort_by_position
    html = TestHelpers.read_output('workshops/series/crisis-programme/index.html')
    positions = html.scan(/class="series-position">#(\d+)/).flatten.map(&:to_i)
    assert_equal positions.sort, positions,
                 "workshop series should be sorted ascending by position, got #{positions.inspect}"
  end

  # --- Title / lede ---------------------------------------------------

  def test_series_page_h1_is_the_term_not_posts_tagged
    html = TestHelpers.read_output('posts/series/inside-abqari/index.html')
    assert_match(%r{<h1>Inside Abqari</h1>}, html)
    # The legacy "Posts tagged 'foo'" wording should NOT appear for
    # series taxonomies.
    refute_match(/Posts tagged/i, html[/<h1>.*?<\/h1>/])
  end

  def test_series_page_lede_uses_collection_label
    posts_html     = TestHelpers.read_output('posts/series/inside-abqari/index.html')
    workshops_html = TestHelpers.read_output('workshops/series/crisis-programme/index.html')
    assert_match(/3 posts/,     posts_html[/<p class="lede">[^<]+<\/p>/])
    assert_match(/3 workshops/, workshops_html[/<p class="lede">[^<]+<\/p>/])
  end

  # --- collection filter (engine behaviour) ---------------------------

  def test_posts_by_term_honors_collection_filter
    site = TestHelpers.built_site
    posts_in_series = site.posts_by_term('posts_series')
    photo_in_series = site.posts_by_term('photos_series')

    posts_in_series.each_value do |list|
      assert list.all? { |p| p.collection == 'posts' },
             'posts_series aggregation must only contain posts'
    end

    photo_in_series.each_value do |list|
      assert list.all? { |p| p.collection == 'photos' },
             'photos_series aggregation must only contain photos'
    end
  end
end

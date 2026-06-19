# frozen_string_literal: true

require_relative 'test_helper'

# Photos landing page (`photos_index.html.erb`). Section toggles in
# `collections.photos.index` are independent; each `*.enabled` flag
# turns its section on or off without affecting the others.
#
# Uses the canonical fixture build — TestHelpers.built_site has all
# four sections enabled by default, so each assertion below targets
# the expected output of the engine's own demo config.
class PhotosIndexTest < Minitest::Test
  def html
    @html ||= TestHelpers.read_output('photos/index.html')
  end

  # --- Page structure ---------------------------------------------------

  def test_landing_renders_at_photos_index
    assert TestHelpers.output_exists?('photos/index.html')
  end

  def test_page_title_in_h1
    assert_match(%r{<h1>Photos</h1>}, html)
  end

  # --- Sections ---------------------------------------------------------

  def test_showcase_section_renders_when_a_photo_is_flagged
    # The fixture has display_showcase: true in config and at least one
    # photo with `showcase: true` in frontmatter — confirm both gates
    # are read correctly.
    assert_includes html, 'class="photo-showcase"'
    assert_match(/class="photo-showcase__eyebrow">Featured/, html)
  end

  def test_latest_photos_section_renders
    assert_match(/<section class="photos-section" aria-label="Latest photos">/, html)
    # Section header reuses the home-module pattern so heading + "View
    # all" sit on one row, matching the home page's photo modules.
    assert_match(%r{<header class="home-module__header">[\s\S]*<h2 class="home-module__heading">Latest photos</h2>[\s\S]*View all &rarr;}, html)
  end

  def test_latest_count_matches_config
    site = TestHelpers.built_site
    expected = site.collection_config('photos').dig('index', 'latest', 'count').to_i
    latest_block = html[/<section class="photos-section"[\s\S]*?<\/section>/]
    refute_nil latest_block
    actual = latest_block.scan(/<li>/).size
    assert_equal expected, actual,
                 "expected #{expected} latest-photo tiles (per config), got #{actual}"
  end

  def test_series_row_renders
    assert_match(/<section class="taxonomy-row" aria-label="Series">/, html)
    assert_match(%r{<h2 class="home-module__heading">Series</h2>}, html)
  end

  def test_countries_row_renders
    assert_match(/<section class="taxonomy-row" aria-label="Countries">/, html)
    assert_match(%r{<h2 class="home-module__heading">Countries</h2>}, html)
  end

  def test_archive_footer_link_renders_with_total_count
    assert_match(/View all \d+ photos &rarr;/, html)
    assert_includes html, 'href="/photos/archive/"'
  end

  def test_showcase_photo_excluded_from_latest_row
    # The first photo in latest should not be the showcased one.
    site = TestHelpers.built_site
    showcase = site.collection('photos').find { |p| p.frontmatter['showcase'] == true }
    refute_nil showcase, 'fixture should have at least one showcase photo'

    latest_block = html[/<section class="photos-section"[\s\S]*?<\/section>/]
    latest_titles = latest_block.scan(/<span class="gallery-index__title">([^<]+)/).flatten
    refute_includes latest_titles, showcase.title,
                    'showcase photo must not appear in the latest row (would be a duplicate)'
  end

  # --- Archive page -----------------------------------------------------

  def test_archive_page_renders
    assert TestHelpers.output_exists?('photos/archive/index.html')
    archive_html = TestHelpers.read_output('photos/archive/index.html')
    assert_match(%r{<h1>Photos archive</h1>}, archive_html)
  end

  def test_archive_first_page_respects_paginate_setting
    archive_html = TestHelpers.read_output('photos/archive/index.html')
    # `paginate: 12` in content/photos-archive.md
    tiles = archive_html.scan(/<li>/).size
    assert tiles <= 12, "page 1 should have at most 12 tiles, got #{tiles}"
  end

  def test_archive_paginates_when_more_than_one_page_of_photos
    assert TestHelpers.output_exists?('photos/archive/page/2/index.html'),
           'archive should generate page 2 when total photos > paginate setting'
  end
end

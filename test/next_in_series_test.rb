# frozen_string_literal: true

require_relative 'test_helper'

# Post show-view series navigation. Three states drive different
# output below the article + testimonials section:
#
#   1. In a series with a later position    →  "Next in the series"
#      card (replaces the chronological "Up next").
#   2. Last post in a series                →  end-of-series note
#      followed by the chronological "Up next" card.
#   3. Not in a series                      →  chronological "Up next"
#      only (the historical default — unchanged).
#
# Plus a series breadcrumb (`#N in the <linked-series> series`)
# appended to the meta line when both `series:` and `series_position:`
# are set.
class NextInSeriesTest < Minitest::Test
  # Fixture: the "Inside Abqari" post series has three posts at
  # positions 1, 2, 3 (themes / photos / bundles). "Hello from the
  # blog" is a fixture post NOT in any series.

  def html_for(slug)
    TestHelpers.read_output("posts/#{slug}/index.html")
  end

  # --- Meta line breadcrumb -------------------------------------------

  def test_meta_line_shows_series_breadcrumb_when_both_fields_set
    html = html_for('themes-an-overview')
    meta = html[/<p class="post__meta">[\s\S]*?<\/p>/]
    assert_match(/#1 in the/, meta)
    # Series name links to the per-collection series taxonomy page.
    assert_match(%r{<a href="/posts/series/inside-abqari/">Inside Abqari</a>}, meta)
    assert_match(/series\s*<\/p>/, meta, 'meta line should end with "series"')
  end

  def test_meta_line_omits_breadcrumb_when_not_in_series
    html = html_for('hello-from-the-blog')
    meta = html[/<p class="post__meta">[\s\S]*?<\/p>/]
    refute_match(/ in the .* series/, meta)
  end

  # --- Branch 1: in series with a later position ----------------------

  def test_post_with_later_series_position_shows_next_in_the_series
    html = html_for('themes-an-overview') # pos 1
    assert_match(/<h2[^>]*>Next in the series<\/h2>/, html)
    # The next-in-series card points at the pos-2 post.
    next_section = html[/<section class="next-item next-item--series"[\s\S]*?<\/section>/]
    refute_nil next_section, 'expected next-item--series section'
    assert_match(%r{href="/posts/photos-and-galleries/"}, next_section)
  end

  def test_next_in_series_replaces_chronological_up_next_for_non_last_posts
    html = html_for('themes-an-overview') # pos 1, not last
    # The "Up next" heading must NOT appear — this post is in the
    # middle of a series, so it gets "Next in the series" only.
    refute_match(/<h2[^>]*>Up next<\/h2>/, html)
  end

  # --- Branch 2: last in series ---------------------------------------

  def test_last_post_in_series_shows_end_of_series_note
    html = html_for('bundles-and-series') # pos 3, last
    note = html[/<aside class="series-end"[\s\S]*?<\/aside>/]
    refute_nil note, 'expected series-end aside on the final post'
    assert_match(/last post in the/, note)
    # The series name in the note links to the series page.
    assert_match(%r{href="/posts/series/inside-abqari/"}, note)
  end

  def test_last_post_in_series_falls_through_to_chronological_up_next
    html = html_for('bundles-and-series') # pos 3, last
    # End-of-series note PLUS Up next.
    assert_match(/<aside class="series-end"/, html)
    assert_match(/<h2[^>]*>Up next<\/h2>/, html)
    # No "Next in the series" card — there isn't one.
    refute_match(/Next in the series/, html)
  end

  # --- Branch 3: not in any series ------------------------------------

  def test_post_not_in_series_shows_only_chronological_up_next
    html = html_for('hello-from-the-blog')
    refute_match(/Next in the series/, html)
    refute_match(/<aside class="series-end"/, html)
    assert_match(/<h2[^>]*>Up next<\/h2>/, html)
  end

  # --- Site#next_in_series semantics ----------------------------------

  def test_next_in_series_returns_next_position
    site = TestHelpers.built_site
    page = site.collection('posts').find { |p| p.slug == 'themes-an-overview' }
    refute_nil page, 'fixture post must be in the collection'

    nxt = site.next_in_series(page)
    refute_nil nxt
    assert_equal 'photos-and-galleries', nxt.slug
  end

  def test_next_in_series_returns_nil_for_last_in_series
    site = TestHelpers.built_site
    page = site.collection('posts').find { |p| p.slug == 'bundles-and-series' }
    assert_nil site.next_in_series(page)
  end

  def test_next_in_series_returns_nil_for_post_with_no_series
    site = TestHelpers.built_site
    page = site.collection('posts').find { |p| p.slug == 'hello-from-the-blog' }
    assert_nil site.next_in_series(page)
  end

  def test_next_in_series_returns_nil_when_series_position_is_missing
    site = TestHelpers.built_site
    page = site.collection('posts').first
    # Synthesise a frontmatter mutation: series but no position
    page.frontmatter['series'] = 'Fake'
    page.frontmatter.delete('series_position')
    assert_nil site.next_in_series(page)
  ensure
    page&.frontmatter&.delete('series')
  end
end

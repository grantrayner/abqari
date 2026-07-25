# frozen_string_literal: true

require_relative 'test_helper'

# Bidirectional series navigation: `Site#prev_in_series`, the
# `_series_pager` partial that pairs it with `next_in_series`, and the
# per-collection series-taxonomy resolution both depend on.
#
# `next_in_series` has its own spec in next_in_series_test.rb — this
# file covers the backwards direction and the pager, and asserts the
# two methods stay symmetric (a refactor that changes one comparison
# without the other is the failure mode the shared `series_sibling`
# helper exists to prevent).
#
# Fixture: the posts collection's "Inside Abqari" series runs
# themes-an-overview (1) → photos-and-galleries (2) →
# bundles-and-series (3). "hello-from-the-blog" is in no series.
class SeriesPagerTest < Minitest::Test
  def setup
    @site = TestHelpers.built_site
  end

  def post(slug)
    page = @site.collection('posts').find { |p| p.slug == slug }
    refute_nil page, "fixture post #{slug} must be in the collection"
    page
  end

  def pager_for(slug)
    Abqari::RenderContext.new(post(slug), @site).render('partials/series_pager')
  end

  # --- Site#prev_in_series --------------------------------------------

  def test_prev_in_series_returns_previous_position
    assert_equal 'themes-an-overview', @site.prev_in_series(post('photos-and-galleries')).slug
  end

  def test_prev_in_series_returns_nil_for_first_in_series
    assert_nil @site.prev_in_series(post('themes-an-overview'))
  end

  def test_prev_in_series_returns_nil_for_post_with_no_series
    assert_nil @site.prev_in_series(post('hello-from-the-blog'))
  end

  def test_prev_in_series_skips_the_gap_to_the_nearest_lower_position
    # From position 3 the previous is 2, not 1 — `max_by`, not `min_by`.
    assert_equal 'photos-and-galleries', @site.prev_in_series(post('bundles-and-series')).slug
  end

  def test_prev_and_next_are_inverses
    middle = post('photos-and-galleries')
    forward = @site.next_in_series(middle)
    assert_equal middle.slug, @site.prev_in_series(forward).slug
  end

  def test_prev_in_series_returns_nil_when_series_position_is_missing
    page = post('hello-from-the-blog')
    page.frontmatter['series'] = 'Inside Abqari'
    page.frontmatter.delete('series_position')
    assert_nil @site.prev_in_series(page)
  ensure
    page&.frontmatter&.delete('series')
  end

  def test_prev_in_series_ignores_non_integer_positions
    # A quoted YAML position is invisible to the chain — the audit flags
    # it (see audit_rules_test.rb) precisely because navigation can't.
    page = post('hello-from-the-blog')
    page.frontmatter['series'] = 'Inside Abqari'
    page.frontmatter['series_position'] = '99'
    # Position "99".to_i == 99, so every real member sits below it; the
    # nearest lower is position 3. The mistyped page is still findable
    # FROM, it just can't be found BY the others.
    assert_equal 'bundles-and-series', @site.prev_in_series(page).slug
    assert_nil @site.next_in_series(post('bundles-and-series'))
  ensure
    page&.frontmatter&.delete('series')
    page&.frontmatter&.delete('series_position')
  end

  # --- _series_pager partial ------------------------------------------

  def test_pager_renders_both_directions_in_the_middle_of_a_series
    html = pager_for('photos-and-galleries')
    assert_match(/<nav class="series-pager"/, html)
    assert_match(%r{rel="prev" href="/guides/themes-an-overview/"}, html)
    assert_match(%r{rel="next" href="/guides/bundles-and-series/"}, html)
  end

  def test_pager_omits_prev_link_on_the_first_item
    html = pager_for('themes-an-overview')
    refute_match(/rel="prev"/, html)
    assert_match(/rel="next"/, html)
    # Empty slot keeps `next` in the second column rather than letting
    # it slide left into the vacant prev position.
    assert_match(/series-pager__slot-empty/, html)
  end

  def test_pager_omits_next_link_on_the_last_item
    html = pager_for('bundles-and-series')
    assert_match(/rel="prev"/, html)
    refute_match(/rel="next"/, html)
  end

  def test_pager_renders_nothing_outside_a_series
    # The partial's leading `<!-- … -->` doc block is always emitted
    # (same convention as `_next_item`; the minifier strips it in
    # production) — "renders nothing" means no markup, not no bytes.
    html = pager_for('hello-from-the-blog')
    refute_match(/<nav/, html)
    refute_match(/series-pager__link/, html)
  end

  def test_pager_escapes_neighbour_titles
    page = post('photos-and-galleries')
    neighbour = @site.prev_in_series(page)
    original = neighbour.frontmatter['title']
    neighbour.frontmatter['title'] = '<script>x</script>'
    html = Abqari::RenderContext.new(page, @site).render('partials/series_pager')
    refute_match(/<script>x<\/script>/, html)
    assert_match(/&lt;script&gt;/, html)
  ensure
    neighbour.frontmatter['title'] = original
  end

  # --- Series taxonomy resolution -------------------------------------

  def test_series_taxonomy_for_resolves_per_collection
    assert_equal 'posts_series',        @site.series_taxonomy_for('posts')
    assert_equal 'photos_series',       @site.series_taxonomy_for('photos')
    assert_equal 'workshops_series',    @site.series_taxonomy_for('workshops')
    assert_equal 'publications_series', @site.series_taxonomy_for('publications')
  end

  def test_series_taxonomy_for_returns_nil_without_a_series_taxonomy
    # `cookbook` reuses `layout: post` but defines no series taxonomy.
    # Before this resolution existed the post layout hardcoded
    # `posts_series`, so a cookbook entry with `series:` linked its
    # breadcrumb into the posts series index — a page about a different
    # collection entirely.
    assert_nil @site.series_taxonomy_for('cookbook')
  end

  def test_series_taxonomy_for_returns_nil_for_blank_collection
    assert_nil @site.series_taxonomy_for(nil)
    assert_nil @site.series_taxonomy_for('')
  end

  def test_series_url_follows_the_collections_own_taxonomy
    ctx = Abqari::RenderContext.new(post('themes-an-overview'), @site)
    assert_equal '/guides/series/inside-abqari/', ctx.series_url('Inside Abqari')

    workshop = @site.collection('workshops').find { |p| p.frontmatter['series'] }
    assert_equal '/workshops/series/crisis-programme/',
                 ctx.series_url('Crisis programme', workshop)
  end

  def test_series_url_is_nil_when_the_collection_has_no_series_taxonomy
    recipe = @site.collection('cookbook').first
    refute_nil recipe, 'fixture cookbook collection must have an entry'
    ctx = Abqari::RenderContext.new(recipe, @site)
    assert_nil ctx.series_url('Anything')
  end
end

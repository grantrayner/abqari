# frozen_string_literal: true

require_relative 'test_helper'

# Publications landing (`publications_index.html.erb`) — mirrors the
# posts/photos pattern: a curated front page with `latest_count` cards
# plus a "View all N publications →" link to the archive when there
# are more publications than fit on the landing. Showcase + bundles +
# series sections retain their existing behaviour.
class PublicationsIndexTest < Minitest::Test
  def landing_html
    @landing_html ||= TestHelpers.read_output('publications/index.html')
  end

  def archive_html
    @archive_html ||= TestHelpers.read_output('publications/archive/index.html')
  end

  # --- Landing ---------------------------------------------------------

  def test_landing_renders_at_publications_index
    assert TestHelpers.output_exists?('publications/index.html')
  end

  def test_landing_shows_showcase_when_a_publication_is_flagged
    assert_includes landing_html, 'class="publication-showcase"'
  end

  def test_landing_catalogue_slices_to_latest_count
    site = TestHelpers.built_site
    latest_count = site.collection_config('publications').dig('index', 'latest_count').to_i
    catalogue_count = landing_html.scan(/<li class="publications-index__item">/).size
    assert catalogue_count <= latest_count,
           "expected at most #{latest_count} cards (latest_count), got #{catalogue_count}"
  end

  def test_view_all_link_renders_when_archive_total_exceeds_visible
    # The fixture has 5 manual publications. After the showcase is
    # extracted, the catalogue has 4 cards — fewer than the archive's
    # 5 — so the "View all" link must appear.
    assert_match(/View all \d+ publications &rarr;/, landing_html)
    assert_includes landing_html, 'href="/publications/archive/"'
  end

  def test_view_all_count_matches_archive_content
    site = TestHelpers.built_site
    archive_size = site.collection('publications')
                       .reject { |p| p.url.end_with?('/publications/') }
                       .size
    match = landing_html.match(/View all (\d+) publications/)
    assert_equal archive_size, match[1].to_i,
                 'link count should match what the archive actually shows'
  end

  # --- Archive ---------------------------------------------------------

  def test_archive_renders
    assert TestHelpers.output_exists?('publications/archive/index.html')
    assert_match(%r{<h1>Publications archive</h1>}, archive_html)
  end

  def test_archive_lists_every_manual_publication
    site = TestHelpers.built_site
    expected = site.collection('publications')
                   .reject { |p| p.url.end_with?('/publications/') }
                   .size
    actual = archive_html.scan(/<li class="publications-index__item">/).size
    # All publications fit on page 1 (fixture has 5 < per_page 12).
    assert_equal expected, actual,
                 'archive should show every manual publication on page 1'
  end

  def test_archive_uses_publication_card_styling
    # Reuses the shared `_publication_card` partial so the archive
    # visually matches the landing's cards.
    assert_match(/<li class="publications-index__item">/, archive_html)
    assert_match(/<h2 class="publications-index__title">/, archive_html)
  end
end

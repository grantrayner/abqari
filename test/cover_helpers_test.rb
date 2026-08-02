# frozen_string_literal: true

require_relative 'test_helper'
require 'ostruct'

# CoverHelpers — the `cover:` enum resolution and the decorative
# title-card SVG generator. Covers:
#
#   1. Mode resolution chain (frontmatter > collection config > default).
#   2. `cover_choice_for` → :photo / :placeholder / :svg / :none.
#   3. `cover_svg_for` markup invariants (renders the title text —
#      word-wrapped for long titles, escaped — and embeds a
#      deterministic gradient id).
class CoverHelpersTest < Minitest::Test
  def setup
    @site = TestHelpers.built_site
    # A real post page from the fixture — needed because RenderContext
    # holds onto `site` for `site.collection_config` lookups.
    any_post = @site.posts.first
    @ctx     = Abqari::RenderContext.new(any_post, @site)
  end

  # --- Mode resolution -----------------------------------------------

  def test_default_mode_is_photo
    # Page with no `cover:` frontmatter, collection has no override.
    page = stub_page(collection: nil)
    assert_equal 'photo', @ctx.cover_mode_for(page, context: :index)
  end

  def test_frontmatter_boolean_false_means_none
    page = stub_page(frontmatter: { 'cover' => false })
    assert_equal 'none', @ctx.cover_mode_for(page, context: :index)
  end

  def test_frontmatter_string_value_wins_over_collection
    # Pretend the posts collection has `cover: photo` (default), but
    # the page overrides to `svg`.
    page = stub_page(collection: 'posts', frontmatter: { 'cover' => 'svg' })
    assert_equal 'svg', @ctx.cover_mode_for(page, context: :index)
  end

  def test_unknown_frontmatter_value_falls_through_to_collection_default
    # Garbage in frontmatter → ignored; collection default wins.
    page = stub_page(collection: 'posts', frontmatter: { 'cover' => 'banana' })
    # The fixture's posts.index.cover is 'photo' (the engine default).
    assert_equal 'photo', @ctx.cover_mode_for(page, context: :index)
  end

  # --- Choice (mode + image presence → render hint) -------------------

  def test_choice_photo_mode_with_image_returns_photo
    page = stub_page(frontmatter: { 'cover' => 'photo', 'image' => 'hero.jpg' })
    assert_equal :photo, @ctx.cover_choice_for(page)
  end

  def test_choice_photo_mode_without_image_returns_placeholder
    page = stub_page(frontmatter: { 'cover' => 'photo' })
    assert_equal :placeholder, @ctx.cover_choice_for(page)
  end

  def test_choice_photo_or_svg_mode_with_image_returns_photo
    page = stub_page(frontmatter: { 'cover' => 'photo_or_svg', 'image' => 'hero.jpg' })
    assert_equal :photo, @ctx.cover_choice_for(page)
  end

  def test_choice_photo_or_svg_mode_without_image_returns_svg
    page = stub_page(frontmatter: { 'cover' => 'photo_or_svg' })
    assert_equal :svg, @ctx.cover_choice_for(page)
  end

  def test_choice_svg_mode_ignores_image
    page = stub_page(frontmatter: { 'cover' => 'svg', 'image' => 'hero.jpg' })
    assert_equal :svg, @ctx.cover_choice_for(page)
  end

  def test_choice_none_returns_none
    page = stub_page(frontmatter: { 'cover' => 'none' })
    assert_equal :none, @ctx.cover_choice_for(page)
  end

  def test_choice_frontmatter_false_returns_none
    page = stub_page(frontmatter: { 'cover' => false, 'image' => 'hero.jpg' })
    assert_equal :none, @ctx.cover_choice_for(page)
  end

  # --- SVG generation -------------------------------------------------

  def test_svg_renders_short_title_on_a_single_line
    page = stub_page(title: 'Aleppo', slug: 'aleppo')
    svg  = @ctx.cover_svg_for(page)
    # One <text> element, containing the full title.
    assert_equal 1, svg.scan(/<text\b/).size, 'short title should be one line'
    assert_match(%r{<text[^>]*>Aleppo</text>}, svg)
  end

  def test_svg_word_wraps_longer_titles_across_multiple_lines
    # 20 chars, 3 words → two-line wrap.
    page = stub_page(title: 'Building with Abqari', slug: 'b-w-a')
    svg  = @ctx.cover_svg_for(page)
    assert_equal 2, svg.scan(/<text\b/).size, 'medium title should wrap to two lines'
    # Both words from the original should appear across the two lines.
    assert_match(/Building/, svg)
    assert_match(/Abqari/,   svg)
  end

  def test_svg_wraps_very_long_titles_into_three_lines
    page = stub_page(title: 'A long workshop title that needs three lines',
                     slug: 'long-one')
    svg  = @ctx.cover_svg_for(page)
    assert_equal 3, svg.scan(/<text\b/).size, 'long title should wrap to three lines'
  end

  def test_svg_escapes_title_text
    # `<`, `>`, `&` etc. in the title must round-trip through h() so
    # they don't break the SVG (or open XSS).
    page = stub_page(title: 'Tom & Jerry', slug: 't-j')
    svg  = @ctx.cover_svg_for(page)
    assert_match(/Tom &amp; Jerry/, svg)
    refute_match(/Tom & Jerry/, svg, 'raw ampersand must be escaped')
  end

  def test_svg_includes_a_linear_gradient_with_unique_id
    page = stub_page(title: 'Test', slug: 'test-post-1')
    svg  = @ctx.cover_svg_for(page)
    assert_match(/<linearGradient id="cover-grad-[a-z0-9]+"/, svg)
    assert_match(/fill="url\(#cover-grad-[a-z0-9]+\)"/, svg)
  end

  def test_svg_is_deterministic_per_slug
    # CRC32 is stable across processes (unlike Object#hash) — same slug
    # should produce the same gradient id and palette on every build.
    a = stub_page(title: 'Whatever', slug: 'fixed-slug')
    b = stub_page(title: 'Different', slug: 'fixed-slug') # same slug
    assert_equal @ctx.cover_svg_for(a).scan(/cover-grad-[a-z0-9]+/),
                 @ctx.cover_svg_for(b).scan(/cover-grad-[a-z0-9]+/),
                 'gradient id should depend only on slug, not title'
  end

  def test_svg_falls_back_to_question_mark_for_empty_title
    page = stub_page(title: '', slug: 'empty')
    svg  = @ctx.cover_svg_for(page)
    assert_match(%r{<text[^>]*>\?</text>}, svg)
  end

  def test_svg_includes_decorative_squares
    # The hand-authored hero.svg pattern uses two clusters of three
    # faint white squares (top-left + bottom-right). The generator
    # should mirror that motif.
    page = stub_page(title: 'Test', slug: 'test')
    svg  = @ctx.cover_svg_for(page)
    rect_count = svg.scan(/<rect\b/).size
    # 1 background rect + 6 decorative squares.
    assert_equal 7, rect_count, "expected 7 <rect> elements, got #{rect_count}"
  end

  # --- Theme-aware palettes --------------------------------------------

  def test_default_theme_uses_the_neutral_palette
    # Fixture theme is `minimal` — no entry in THEME_COVER_PALETTES.
    assert_equal Abqari::RenderContext::CoverHelpers::COVER_PALETTES,
                 @ctx.cover_palette
  end

  def test_warm_theme_tiles_draw_from_that_themes_palette
    with_theme('notebook') do
      allowed = Abqari::RenderContext::CoverHelpers::THEME_COVER_PALETTES['notebook'].flatten
      svg     = @ctx.cover_svg_for(stub_page(title: 'Test', slug: 'test'))
      stops   = svg.scan(/stop-color="(#[0-9a-f]{6})"/i).flatten
      assert_equal 2, stops.size
      stops.each { |hex| assert_includes allowed, hex }
    end
  end

  def test_every_shipped_theme_palette_is_two_tone_hex_pairs
    Abqari::RenderContext::CoverHelpers::THEME_COVER_PALETTES.each do |theme, palette|
      palette.each do |pair|
        assert_equal 2, pair.size, "#{theme} palette entry should be a two-tone pair"
        pair.each { |hex| assert_match(/\A#[0-9a-f]{6}\z/i, hex, "#{theme} palette colour #{hex}") }
      end
    end
  end

  private

  # Temporarily point the shared fixture site at another theme.
  # `cover_palette` only reads `config['theme']`, so a config swap is
  # enough — no rebuild needed.
  def with_theme(name)
    previous = @site.config['theme']
    @site.config['theme'] = name
    yield
  ensure
    @site.config['theme'] = previous
  end

  # Minimal page-like stub. Defaults match a top-level page (no
  # collection); pass `collection:` to opt into collection-config
  # lookups. Frontmatter is merged into defaults so each test only
  # specifies the keys it cares about.
  def stub_page(title: 'Some title', slug: 'some-slug', collection: nil, frontmatter: {})
    fm = { 'title' => title }.merge(frontmatter)
    OpenStruct.new(title: title, slug: slug, collection: collection, frontmatter: fm)
  end
end

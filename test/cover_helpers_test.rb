# frozen_string_literal: true

require_relative 'test_helper'
require 'ostruct'

# CoverHelpers — the `cover:` enum resolution and the decorative
# initial-tile SVG generator. Covers:
#
#   1. Mode resolution chain (frontmatter > collection config > default).
#   2. `cover_choice_for` → :photo / :placeholder / :svg / :none.
#   3. `cover_svg_for` markup invariants (escapes title, picks an
#      initial, embeds a deterministic gradient id).
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

  def test_svg_uses_first_alphanumeric_letter_of_title_uppercase
    page = stub_page(title: '!! my post', slug: 'my-post')
    svg  = @ctx.cover_svg_for(page)
    # The text element contains the initial. (We don't assert the
    # whole element shape — just that 'M' appears as the text content
    # of a <text> tag inside the SVG.)
    assert_match(%r{<text[^>]*>M</text>}, svg)
  end

  def test_svg_escapes_title_initial
    # Defence in depth — if the initial were ever a `<`, `>`, `&`,
    # `"`, or `'` (it shouldn't, but…), it'd round-trip through h().
    page = stub_page(title: '<>script', slug: 'x')
    svg  = @ctx.cover_svg_for(page)
    # '<' is non-alphanumeric → stripped. Next char is '>' → also stripped.
    # 's' is the initial → uppercased to 'S'.
    assert_match(%r{<text[^>]*>S</text>}, svg)
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

  private

  # Minimal page-like stub. Defaults match a top-level page (no
  # collection); pass `collection:` to opt into collection-config
  # lookups. Frontmatter is merged into defaults so each test only
  # specifies the keys it cares about.
  def stub_page(title: 'Some title', slug: 'some-slug', collection: nil, frontmatter: {})
    fm = { 'title' => title }.merge(frontmatter)
    OpenStruct.new(title: title, slug: slug, collection: collection, frontmatter: fm)
  end
end

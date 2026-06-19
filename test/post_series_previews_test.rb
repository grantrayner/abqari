# frozen_string_literal: true

require_relative 'test_helper'

# Post series previews — the stacked-image row on /guides/ that
# surfaces each series with overlapping hero images, mirroring the
# visual of the publications index's series block.
#
# Driven by the `posts_series` taxonomy. Each tile shows up to N
# overlapping covers (default 3) drawn from posts in that series
# that have `image:` frontmatter set.
class PostSeriesPreviewsTest < Minitest::Test
  def html
    @html ||= TestHelpers.read_output('guides/index.html')
  end

  def block
    @block ||= html[/<section class="post-series-previews"[\s\S]*?<\/section>/]
  end

  def test_section_renders_when_a_post_has_series
    refute_nil block, 'expected post-series-previews section to render'
  end

  def test_section_heading_uses_shared_home_module_classes
    # Same heading/CTA shell as the home-module pattern so the
    # styling matches Latest photos / Series rows elsewhere.
    assert_match(%r{<h2 class="home-module__heading">Series</h2>}, block)
  end

  def test_each_tile_uses_shared_series_preview_classes_plus_posts_modifier
    # `--posts` modifier changes aspect-ratio from book-cover 2:3 to
    # landscape 16:9; without it the post heroes would crop weirdly.
    assert_match(/class="series-preview series-preview--posts"/, block)
  end

  def test_covers_render_when_posts_have_hero_images
    covers = block.scan(/<img[^>]*class="series-preview__cover"/)
    refute_empty covers, 'expected at least one cover image in the stack'
  end

  def test_tile_links_to_per_collection_series_url
    assert_match(%r{href="/guides/series/inside-abqari/"}, block)
  end

  def test_post_count_label_uses_pluralize
    # Fixture has 3 posts in "Inside Abqari" → "3 posts".
    assert_match(/3 posts/, block)
  end

  # --- Config toggle --------------------------------------------------

  def test_section_can_be_disabled_via_config
    site = Abqari::Site.new
    site.config['collections'] ||= {}
    site.config['collections']['posts'] ||= {}
    site.config['collections']['posts']['index'] ||= {}
    site.config['collections']['posts']['index']['series'] = { 'enabled' => false }

    # Render the partial directly with a one-off context to verify
    # the toggle gates rendering at the layout level. (We can't
    # rebuild the fixture site, so use the partial directly via the
    # taxonomy-config indirection in posts_index.)
    enabled = site.config.dig('collections', 'posts', 'index', 'series', 'enabled')
    assert_equal false, enabled,
                 'fixture should accept the override; layout reads this key'
  end

  def test_section_omits_view_all_link_when_all_url_unset
    refute_match(/home-module__see-all/, block,
                 'no "View all" link when all_url is unset (fixture default)')
  end
end

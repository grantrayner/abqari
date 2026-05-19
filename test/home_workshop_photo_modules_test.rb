# frozen_string_literal: true

require_relative 'test_helper'

# Home modules — next_workshop / latest_photo / random_photo.
#
# Same shape as `HomePublicationModulesTest`: the granular hash
# config in `config/site.yml` exposes per-field show_* toggles.
# Cover image and title are fixed (always rendered when present);
# the other fields are opt-in. Defaults:
#
#   next_workshop:
#     show_dates       true
#     show_description true
#     show_location    true
#     show_format      false
#     show_price       false
#     show_tags        false
#
#   latest_photo + random_photo (identical field surface):
#     show_caption     true
#     show_date        true
#     show_city        true
#     show_country     true
#     show_camera      false
#     show_type        false
#     show_series      false
#     show_tags        false
class HomeWorkshopPhotoModulesTest < Minitest::Test
  def setup
    @site = TestHelpers.built_site
    @home_page = @site.pages.find { |p| p.url == '/' }
    refute_nil @home_page, 'fixture home page must exist at /'
    @original_home = @site.config['home']&.dup
  end

  def teardown
    @site.config['home'] = @original_home
  end

  def render_module(module_name, module_cfg)
    @site.config['home'] = (@site.config['home'] || {}).merge(module_name => module_cfg)
    ctx = Abqari::RenderContext.new(@home_page, @site)
    html = ctx.render("partials/home/#{module_name}")
    # Strip HTML comments before assertions. The partials carry
    # explanatory comments at the top (documenting toggle values like
    # "Leica", "digital", "In-person") that would otherwise trip
    # `refute_match` checks for the rendered absence of those words.
    html.gsub(/<!--[\s\S]*?-->/, '')
  end

  # ============================================================
  # next_workshop
  # ============================================================

  def test_next_workshop_fixed_fields_always_render
    html = render_module('next_workshop', true)
    assert_match(/<a class="home-module__cover"/, html)
    assert_match(%r{<h3 class="home-module__title">},  html)
  end

  def test_next_workshop_default_renders_dates_description_location
    html = render_module('next_workshop', true)
    assert_match(%r{<p class="home-module__meta">},        html, 'meta line present by default (dates/location)')
    assert_match(%r{<p class="home-module__description">}, html, 'description present by default')
    assert_match(/<time datetime=/,                        html, 'date rendered as <time>')
  end

  def test_next_workshop_format_off_by_default
    html = render_module('next_workshop', true)
    # The fixture workshops have format "In-person" — should not appear
    # in default render.
    refute_match(/In-person/, html, 'format should not render with default config')
  end

  def test_next_workshop_show_format_enables_format_meta
    html = render_module('next_workshop', 'show_format' => true)
    assert_match(/In-person|Remote|Hybrid/, html, 'format should appear when toggled on')
  end

  def test_next_workshop_show_price_enables_price_meta
    html = render_module('next_workshop', 'show_price' => true)
    assert_match(/\$\d/, html, 'price should appear when toggled on')
  end

  def test_next_workshop_show_tags_renders_tags_block
    html = render_module('next_workshop', 'show_tags' => true)
    assert_match(%r{<p class="home-module__tags">}, html)
    assert_match(%r{<a class="home-module__tag" href="/tags/}, html)
  end

  def test_next_workshop_show_description_false_hides_description
    html = render_module('next_workshop', 'show_description' => false)
    refute_match(%r{<p class="home-module__description">}, html)
  end

  def test_next_workshop_show_dates_false_drops_dates_from_meta
    html = render_module('next_workshop',
                         'show_dates'    => false,
                         'show_location' => false)
    refute_match(/<time datetime=/, html, 'no <time> when dates off')
    # With location also off and dates off and format/price/tags
    # default-off, the meta block should disappear entirely.
    refute_match(%r{<p class="home-module__meta">}, html)
  end

  # ============================================================
  # latest_photo
  # ============================================================

  def test_latest_photo_fixed_fields_always_render
    html = render_module('latest_photo', true)
    assert_match(/<a class="home-module__cover"/, html)
    assert_match(%r{<h3 class="home-module__title">}, html)
  end

  def test_latest_photo_defaults
    html = render_module('latest_photo', true)
    assert_match(%r{<p class="home-module__meta">},        html, 'meta line present (date + city/country)')
    assert_match(%r{<p class="home-module__description">}, html, 'caption present')
    # Photo fixtures include `camera: Leica Q2`, `type: digital`,
    # `series: …` — defaults should hide all three.
    refute_match(/Leica/,  html, 'camera off by default')
    refute_match(/digital/, html, 'type off by default')
  end

  def test_latest_photo_city_and_country_combine_into_one_meta_entry
    html = render_module('latest_photo',
                         'show_date'    => false,
                         'show_camera'  => false,
                         'show_type'    => false,
                         'show_series'  => false,
                         'show_city'    => true,
                         'show_country' => true)
    meta = html[/<p class="home-module__meta">[\s\S]*?<\/p>/]
    refute_nil meta, 'meta line should render with city + country'
    # Expect "City, Country" — one entry, comma-joined, NOT split
    # by the bullet that separates distinct meta facts.
    assert_match(/,\s*\w/, meta, 'city + country should combine with a comma')
    refute_match(/&middot;/, meta, 'only one fact in the line → no bullet')
  end

  def test_latest_photo_show_city_only_drops_country
    html = render_module('latest_photo',
                         'show_date'    => false,
                         'show_city'    => true,
                         'show_country' => false,
                         'show_camera'  => false,
                         'show_type'    => false,
                         'show_series'  => false)
    # Find any photo with a country and confirm it's not surfaced.
    countries = @site.collection('photos').map { |p| p.frontmatter['country'] }.compact.uniq
    countries.each { |c| refute_match(/\b#{Regexp.escape(c)}\b/, html, "country `#{c}` should not appear") }
  end

  def test_latest_photo_show_camera_renders_camera
    html = render_module('latest_photo', 'show_camera' => true)
    assert_match(/Leica|Fuji|Sony|Canon|Nikon|Pentax/, html, 'camera should render when toggled on')
  end

  def test_latest_photo_show_tags_renders_tags_block
    html = render_module('latest_photo', 'show_tags' => true)
    assert_match(%r{<p class="home-module__tags">}, html)
  end

  def test_latest_photo_show_caption_false_hides_caption
    html = render_module('latest_photo', 'show_caption' => false)
    refute_match(%r{<p class="home-module__description">}, html)
  end

  # ============================================================
  # random_photo (same field surface; applied per-card in the pool)
  # ============================================================

  def test_random_photo_pool_has_multiple_cards
    html = render_module('random_photo', true)
    # 12 candidates (pool_cap in the partial). Don't try to isolate
    # the pool with a regex — the pool's `</div>` is preceded by
    # nested `<div class="home-module__body">` closers, so a
    # non-greedy match stops at the first one. Just count the
    # `<article>` cards across the whole partial output — this is
    # the only place they appear in this render.
    refute_nil html[%r{<div class="home-module__pool"}], 'pool wrapper should exist'
    item_count = html.scan(/<article class="home-module__item"/).size
    assert item_count > 1, "pool should hold multiple cards (got #{item_count})"
  end

  def test_random_photo_defaults_match_latest_photo
    html = render_module('random_photo', true)
    assert_match(%r{<p class="home-module__meta">},        html)
    assert_match(%r{<p class="home-module__description">}, html)
    refute_match(/Leica|digital\b/, html, 'camera + type off by default')
  end

  def test_random_photo_show_camera_applies_to_every_card
    html = render_module('random_photo', 'show_camera' => true)
    # Every fixture photo carries a camera value — every card should
    # surface it. Count cards vs camera mentions across the whole
    # partial output (see the `_pool_has_multiple_cards` test for why
    # we don't try to isolate the pool with a regex).
    card_count   = html.scan(/<article class="home-module__item"/).size
    camera_count = html.scan(/Leica|Fuji|Sony|Canon|Nikon|Pentax/).size
    assert camera_count >= card_count,
           "every card should surface its camera (got #{camera_count} camera mentions across #{card_count} cards)"
  end

  def test_random_photo_show_tags_renders_tags_on_each_card
    html = render_module('random_photo', 'show_tags' => true)
    tag_blocks = html.scan(%r{<p class="home-module__tags">})
    assert tag_blocks.size > 1, "tags should render on every card when on (got #{tag_blocks.size})"
  end
end

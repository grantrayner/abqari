# frozen_string_literal: true

require_relative 'test_helper'

# Home modules — featured / latest publication card.
#
# Cover image, title, and tagline are always rendered (card identity).
# Excerpt, price, and published_at are configurable via the granular
# `home.featured_publication` / `home.latest_publication` hash in
# `config/site.yml`:
#
#     featured_publication:
#       enabled: true
#       show_excerpt: true
#       show_price: false
#       show_published_at: false
#
# Defaults: excerpt on, price off, published_at off (preserves the
# pre-feature render shape so existing sites are unchanged).
class HomePublicationModulesTest < Minitest::Test
  def setup
    @site = TestHelpers.built_site
    @home_page = @site.pages.find { |p| p.url == '/' }
    refute_nil @home_page, 'fixture home page must exist at /'

    # Snapshot the original `home:` config so each test can mutate
    # freely and we reset in teardown.
    @original_home = @site.config['home']&.dup
  end

  def teardown
    @site.config['home'] = @original_home
  end

  # Render one of the two partials directly, with `site.config['home']`
  # mutated to whatever shape the test wants. Returns the rendered
  # HTML for assertions.
  def render_module(module_name, module_cfg)
    @site.config['home'] = (@site.config['home'] || {}).merge(module_name => module_cfg)
    ctx = Abqari::RenderContext.new(@home_page, @site)
    ctx.render("partials/home/#{module_name}")
  end

  # --- Fixed fields — always rendered -----------------------------------

  def test_featured_publication_always_renders_cover_title_tagline
    # Fixture has a publication with `showcase: true` (`first-light` /
    # `the-field-guide` depending on order). Default render: cover +
    # title + tagline all present.
    html = render_module('featured_publication', true)
    assert_match(/<a class="home-module__cover"/, html)
    assert_match(/<img src=/, html)
    assert_match(%r{<h3 class="home-module__title">}, html)
    assert_match(%r{<p class="home-module__tagline">}, html)
  end

  def test_latest_publication_always_renders_cover_title_tagline
    html = render_module('latest_publication', true)
    assert_match(/<a class="home-module__cover"/, html)
    assert_match(/<img src=/, html)
    assert_match(%r{<h3 class="home-module__title">}, html)
    assert_match(%r{<p class="home-module__tagline">}, html)
  end

  # --- Defaults — excerpt on, price off, published_at off ---------------

  def test_defaults_render_excerpt_but_not_price_or_published_at
    html = render_module('featured_publication', true)
    assert_match(%r{<p class="home-module__description">}, html, 'excerpt should render by default')
    refute_match(%r{<p class="home-module__meta">}, html, 'no meta line by default (price + date off)')
  end

  def test_simple_true_form_matches_explicit_defaults_hash
    # `featured_publication: true` (boolean) and the equivalent hash
    # form (explicit defaults) should produce identical output.
    plain = render_module('featured_publication', true)
    hashed = render_module('featured_publication',
                           'enabled' => true,
                           'show_excerpt' => true,
                           'show_price' => false,
                           'show_published_at' => false)
    assert_equal plain.gsub(/\s+/, ' '), hashed.gsub(/\s+/, ' '),
                 'simple true and explicit-defaults hash should render identically'
  end

  # --- show_excerpt -----------------------------------------------------

  def test_show_excerpt_false_hides_the_description
    html = render_module('featured_publication', 'show_excerpt' => false)
    refute_match(%r{<p class="home-module__description">}, html)
    # Title + tagline still present — those are fixed.
    assert_match(%r{<h3 class="home-module__title">}, html)
    assert_match(%r{<p class="home-module__tagline">}, html)
  end

  # --- show_price -------------------------------------------------------

  def test_show_price_renders_price_when_set_on_publication
    # The fixture publication's `price:` is a string-shorthand that the
    # PublicationNormaliser expands to the canonical
    # `{cents, currency, formatted}` hash; the partial reads
    # `price.formatted`. Match any "$X.XX" — the showcased publication
    # changes between fixture revisions; what matters is that SOME
    # canonical-formatted price made it into the meta line.
    html = render_module('featured_publication', 'show_price' => true)
    assert_match(%r{<p class="home-module__meta">}, html, 'meta line should render when price is on')
    assert_match(/\$\d+\.\d{2}/, html, 'rendered price should be the canonical formatted value')
  end

  def test_show_price_off_hides_the_meta_line_when_published_at_also_off
    html = render_module('featured_publication', 'show_price' => false)
    refute_match(%r{home-module__meta}, html)
  end

  # --- show_published_at -----------------------------------------------

  def test_show_published_at_renders_time_element
    html = render_module('featured_publication', 'show_published_at' => true)
    assert_match(%r{<p class="home-module__meta">}, html)
    assert_match(/<time datetime=/, html, 'published_at should render in a <time> element')
  end

  # --- Combined ---------------------------------------------------------

  def test_both_price_and_published_at_share_a_single_meta_line
    html = render_module('featured_publication',
                         'show_price' => true,
                         'show_published_at' => true)
    # One meta line carries both, joined by a bullet.
    meta_blocks = html.scan(%r{<p class="home-module__meta">[\s\S]*?</p>})
    assert_equal 1, meta_blocks.size, 'price and published_at should share one meta paragraph'
    assert_match(/&middot;|·/, meta_blocks.first, 'bullet should separate the two facts')
    assert_match(/<time datetime=/, meta_blocks.first)
    assert_match(/\$\d+\.\d{2}/,        meta_blocks.first)
  end

  # --- Latest publication mirrors featured_publication ------------------

  def test_latest_publication_supports_the_same_field_toggles
    html = render_module('latest_publication',
                         'show_price' => true,
                         'show_published_at' => true)
    assert_match(%r{<p class="home-module__meta">}, html)
    assert_match(/\$\d+\.\d{2}/,         html)
    assert_match(/<time datetime=/,  html)
  end
end

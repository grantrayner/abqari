# frozen_string_literal: true

require_relative 'test_helper'
require 'ostruct'

# Tests for the canonical publications schema (see
# docs/publications.md). Four things to lock in:
#
#   1. PublicationNormaliser expands `price` shorthand correctly for
#      publications / bundles / series; leaves other collections
#      alone.
#   2. PublisherShowPage joins `site.collection('publications' /
#      'bundles' / 'series')` so templates see ONE merged list per
#      collection.
#   3. Manual override wins on slug collision (an override page at
#      `content/publications/<slug>/index.md` suppresses the auto-
#      generated externally-sourced entry for the same slug).
#   4. Generic `buy_button` / `cart_button` helpers render whenever
#      the canonical URL field is set, regardless of source.

class PublicationNormaliserTest < Minitest::Test
  N = Abqari::PublicationNormaliser

  def test_expands_dollar_price_string
    fm = N.call({ 'price' => '$16.00' }, 'publications')
    assert_equal({ 'cents' => 1600, 'currency' => 'USD', 'formatted' => '$16.00' }, fm['price'])
  end

  def test_expands_pound_price_string
    fm = N.call({ 'price' => '£9.99' }, 'publications')
    assert_equal 999, fm['price']['cents']
    assert_equal 'GBP', fm['price']['currency']
  end

  def test_expands_sgd_price_string
    fm = N.call({ 'price' => 'S$22.50' }, 'publications')
    assert_equal 2250, fm['price']['cents']
    assert_equal 'SGD', fm['price']['currency']
  end

  def test_bare_number_assumes_usd_and_formats_with_dollar_symbol
    fm = N.call({ 'price' => '12' }, 'publications')
    assert_equal 1200, fm['price']['cents']
    assert_equal 'USD', fm['price']['currency']
    assert_equal '$12.00', fm['price']['formatted']
  end

  def test_passes_through_canonical_hash_shape_unchanged
    canonical = { 'cents' => 1600, 'currency' => 'USD', 'formatted' => '$16.00' }
    fm = N.call({ 'price' => canonical }, 'publications')
    assert_equal canonical, fm['price']
  end

  def test_applies_to_bundles
    fm = N.call({ 'price' => '$28.00' }, 'bundles')
    assert_kind_of Hash, fm['price']
    assert_equal 2800, fm['price']['cents']
  end

  def test_applies_to_series
    # Folio currently doesn't supply prices on series, but native
    # authors can — the normaliser handles them the same way.
    fm = N.call({ 'price' => '$10.00' }, 'series')
    assert_kind_of Hash, fm['price']
  end

  def test_leaves_other_collections_alone
    fm = N.call({ 'price' => '$16.00', 'title' => 'A post' }, 'posts')
    assert_equal '$16.00', fm['price']
  end

  def test_unparseable_price_left_as_string
    fm = N.call({ 'price' => 'on request' }, 'publications')
    assert_equal 'on request', fm['price']
  end

  def test_returns_input_unchanged_for_non_hash
    assert_nil N.call(nil, 'publications')
    assert_equal 'not a hash', N.call('not a hash', 'publications')
  end
end

class PublisherShowPageTest < Minitest::Test
  # Use the built fixture site. Its content has no publisher config,
  # so we construct PublisherShowPages directly and add them via
  # `add_generated_page` to verify the collection merge.

  def setup
    @site = TestHelpers.built_site
  end

  def test_publisher_show_page_reports_its_collection
    pub_page    = Abqari::PublisherShowPage.new(@site, kind: 'publication', slug: 'x', data: { 'title' => 'X' }, layout: 'publication', url: '/publications/x/')
    bundle_page = Abqari::PublisherShowPage.new(@site, kind: 'bundle',      slug: 'y', data: { 'name' => 'Y' },  layout: 'bundle',      url: '/bundles/y/')
    series_page = Abqari::PublisherShowPage.new(@site, kind: 'series',      slug: 'z', data: { 'name' => 'Z' },  layout: 'series',      url: '/series/z/')

    assert_equal 'publications', pub_page.collection
    assert_equal 'bundles',      bundle_page.collection
    assert_equal 'series',       series_page.collection
  end

  def test_publisher_show_page_frontmatter_carries_canonical_data
    page = Abqari::PublisherShowPage.new(@site,
                                         kind: 'publication',
                                         slug: 'foo',
                                         data: { 'title' => 'Foo', 'excerpt' => 'A book' },
                                         layout: 'publication',
                                         url: '/publications/foo/')
    fm = page.frontmatter
    # Canonical fields are accessible via frontmatter — no
    # source-aware branching needed in templates. The payload IS
    # the frontmatter; no engine-only bookkeeping keys are injected.
    assert_equal 'Foo', fm['title']
    assert_equal 'A book', fm['excerpt']
    refute fm.key?('folio_kind'), 'frontmatter should not carry engine-only bookkeeping keys'
    refute fm.key?('folio_slug'), 'frontmatter should not carry engine-only bookkeeping keys'
  end

  def test_bundle_and_series_use_name_as_title
    bundle = Abqari::PublisherShowPage.new(@site, kind: 'bundle', slug: 'b', data: { 'name' => 'My Bundle' }, layout: 'bundle', url: '/bundles/b/')
    series = Abqari::PublisherShowPage.new(@site, kind: 'series', slug: 's', data: { 'name' => 'My Series' }, layout: 'series', url: '/series/s/')

    assert_equal 'My Bundle', bundle.title
    assert_equal 'My Series', series.title
  end

  def test_publication_description_uses_tagline_then_excerpt
    with_tagline = Abqari::PublisherShowPage.new(@site, kind: 'publication', slug: 't', data: { 'title' => 'T', 'tagline' => 'One-liner', 'excerpt' => 'Longer prose' }, layout: 'publication', url: '/publications/t/')
    without_tagline = Abqari::PublisherShowPage.new(@site, kind: 'publication', slug: 'u', data: { 'title' => 'U', 'excerpt' => 'Just an excerpt' }, layout: 'publication', url: '/publications/u/')

    assert_equal 'One-liner', with_tagline.description
    assert_equal 'Just an excerpt', without_tagline.description
  end
end

class CollectionMergeTest < Minitest::Test
  # Verify that `Site#collection(name)` returns BOTH manual pages and
  # PublisherShowPage entries. We can't easily simulate publisher
  # fetches in tests; instead, construct a PublisherShowPage by hand
  # and use `add_generated_page` to inject it.

  def setup
    @site = TestHelpers.built_site
    # Snapshot the shared site's generated-page list so teardown can
    # restore it EXACTLY — these tests inject pages into the shared
    # instance, and a partial cleanup leaks them into later tests.
    @generated_snapshot = @site.instance_variable_get(:@generated_pages).dup
    @baseline = @site.collection('publications').map(&:slug)
  end

  def teardown
    # Restore the exact generated-page list, then drop the memoised
    # collection caches. The caches live in the private `@memos` hash
    # under `:collection_cache` / `:collection_url_index_cache` — the
    # old teardown set phantom `@collection_cache` ivars that never
    # existed, so a stale collection (with our injected page still in
    # it) leaked into later tests (e.g. PublicationsIndexTest saw an
    # extra publication and failed nondeterministically by order).
    @site.instance_variable_set(:@generated_pages, @generated_snapshot)
    memos = @site.instance_variable_get(:@memos)
    if memos
      memos.delete(:collection_cache)
      memos.delete(:collection_url_index_cache)
    end
  end

  def test_collection_includes_publisher_show_page
    injected = Abqari::PublisherShowPage.new(@site,
                                             kind: 'publication',
                                             slug: 'injected-publisher-pub',
                                             data: { 'title' => 'Injected', 'excerpt' => 'From a publisher.' },
                                             layout: 'publication',
                                             url: '/publications/injected-publisher-pub/')
    @site.add_generated_page(injected)

    slugs = @site.collection('publications').map(&:slug)
    assert_includes slugs, 'injected-publisher-pub',
                    'collection should include PublisherShowPage entries'
  end

  def test_manual_override_suppresses_publisher_entry_for_same_slug
    # Pick a manual publication slug from the fixture (e.g. the-field-guide).
    manual_slug = @baseline.first
    skip 'fixture has no manual publications' unless manual_slug

    # Add a PublisherShowPage with the same slug.
    injected = Abqari::PublisherShowPage.new(@site,
                                             kind: 'publication',
                                             slug: manual_slug,
                                             data: { 'title' => 'Publisher-version', 'excerpt' => 'Should be suppressed.' },
                                             layout: 'publication',
                                             url: "/publications/#{manual_slug}/")
    @site.add_generated_page(injected)

    matches = @site.collection('publications').select { |p| p.slug == manual_slug }
    assert_equal 1, matches.size, 'manual page should suppress the publisher entry for the same slug'
    # The surviving page is the manual one — recognise by it being a Page (not a PublisherShowPage).
    assert_instance_of Abqari::Page, matches.first
  end
end

class BuyButtonHelpersTest < Minitest::Test
  # `buy_button` / `cart_button` are publisher-agnostic — they render
  # whenever the canonical URL field is set on the given
  # frontmatter. Native users with a `buy_now_url:` in frontmatter
  # get a button without any publisher integration configured.

  def setup
    @site = TestHelpers.built_site
    @ctx  = Abqari::RenderContext.new(@site.posts.first, @site)
  end

  def test_buy_button_renders_when_buy_now_url_is_set
    fm = { 'buy_now_url' => 'https://example.com/buy/x' }
    out = @ctx.buy_button(fm)
    assert_match %r{<a class="folio-button folio-button--buy" href="https://example.com/buy/x"}, out
    assert_includes out, 'Buy now'
  end

  def test_buy_button_renders_nothing_when_url_missing
    assert_equal '', @ctx.buy_button({})
    assert_equal '', @ctx.buy_button({ 'buy_now_url' => nil })
    assert_equal '', @ctx.buy_button({ 'buy_now_url' => '' })
  end

  def test_cart_button_renders_for_add_to_cart_url
    fm = { 'add_to_cart_url' => 'https://example.com/cart/add/x' }
    out = @ctx.cart_button(fm)
    assert_match %r{folio-button--cart}, out
    assert_includes out, 'Add to cart'
  end

  def test_buy_button_blocks_javascript_url
    # `sanitized_url` rejects javascript: schemes — the button
    # silently emits nothing rather than a clickable XSS.
    fm = { 'buy_now_url' => 'javascript:alert(1)' }
    assert_equal '', @ctx.buy_button(fm)
  end

  def test_buy_button_accepts_a_page_like_object
    page = OpenStruct.new(frontmatter: { 'buy_now_url' => 'https://x.example/buy' })
    out  = @ctx.buy_button(page)
    assert_match %r{href="https://x\.example/buy"}, out
  end

  def test_buy_button_accepts_a_slug_string_and_resolves_via_collection
    # Pick a manual publication that has a buy_now_url in its
    # canonical frontmatter. Pass the slug string; helper should
    # look it up in `site.collection('publications')`.
    pub_with_buy = @site.collection('publications').find { |p| p.frontmatter['buy_now_url'] }
    skip 'fixture has no publication with buy_now_url' unless pub_with_buy

    out = @ctx.buy_button(pub_with_buy.slug)
    assert_match %r{href="#{Regexp.escape(pub_with_buy.frontmatter['buy_now_url'])}"}, out
  end

end

# frozen_string_literal: true

require_relative 'test_helper'

# Generation runs in two phases: CONTRIBUTE (generators that add pages
# joining a collection) then DERIVE (generators that read collections and
# freeze what they find).
#
# The ordering is load-bearing and used to be wrong. `Renderer#generate_all`
# ran pagination BEFORE publisher pages, and pagination slices a collection
# into `Paginator` objects at generation time — so on a Folio site with more
# manual publications than `per_page`, every Folio-sourced publication was
# silently absent from the archive and all its shards. No warning, no error,
# just missing entries: the worst shape of bug this codebase can produce,
# because a green build tells you nothing is wrong.
#
# Reordering fixes today's instance. The barrier is what stops the next
# generator from re-creating it.
class CollectionPhaseTest < Minitest::Test
  def setup
    @site = TestHelpers.built_site
    @was_final = @site.collections_final?
  end

  def teardown
    @site.instance_variable_set(:@collections_final, @was_final)
  end

  def publisher_page(slug: 'phase-test-pub')
    Abqari::PublisherShowPage.new(@site,
                                  kind: 'publication',
                                  slug: slug,
                                  data: { 'title' => 'Phase Test' },
                                  layout: 'publication',
                                  url: "/publications/#{slug}/")
  end

  # --- The barrier ----------------------------------------------------

  def test_a_completed_build_has_finalised_collections
    assert @site.collections_final?,
           'generate_all should close the contribute phase'
  end

  def test_joining_a_collection_after_the_barrier_raises
    @site.instance_variable_set(:@collections_final, true)

    err = assert_raises(RuntimeError) { @site.add_generated_page(publisher_page) }

    assert_match(/joins the 'publications' collection/, err.message)
    assert_match(%r{/publications/phase-test-pub/}, err.message,
                 'the error names the offending page')
    assert_match(/contribute\s+phase/, err.message,
                 'and says what to do about it')
  end

  # Everything the DERIVE phase itself produces belongs to no collection,
  # so the guard must not obstruct normal generation.
  def test_non_collection_pages_still_add_after_the_barrier
    @site.instance_variable_set(:@collections_final, true)
    before = @site.all_pages.size

    tag_page = Abqari::TaxonomyPage.new('tags', 'phase-test-term', [], @site)
    @site.add_generated_page(tag_page)

    assert_equal before + 1, @site.all_pages.size
  ensure
    generated = @site.instance_variable_get(:@generated_pages)
    generated.reject! { |p| p.respond_to?(:url) && p.url.to_s.include?('phase-test-term') }
    @site.instance_variable_get(:@memos)&.delete(:collection_cache)
  end

  def test_contributing_before_the_barrier_is_allowed
    @site.instance_variable_set(:@collections_final, false)
    before = @site.all_pages.size

    @site.add_generated_page(publisher_page(slug: 'phase-test-allowed'))

    assert_equal before + 1, @site.all_pages.size
  ensure
    generated = @site.instance_variable_get(:@generated_pages)
    generated.reject! { |p| p.respond_to?(:slug) && p.slug.to_s.start_with?('phase-test-') }
    memos = @site.instance_variable_get(:@memos)
    memos&.delete(:collection_cache)
    memos&.delete(:collection_url_index_cache)
  end

  # The dev server rebuilds in-process. If the flag survived a rebuild,
  # the SECOND build would raise on the first publisher page it made —
  # turning a fixed bug into a crash loop.
  def test_rebuild_reopens_the_contribute_phase
    # `reset_state_for_rebuild!` clears the shared fixture's generated
    # pages and memos. The fixture is a singleton and won't rebuild while
    # its sentinel exists, so leaving it emptied would break every later
    # test that reads a generated page. Snapshot and restore both.
    generated_snapshot = @site.instance_variable_get(:@generated_pages).dup
    memo_snapshot      = @site.instance_variable_get(:@memos).dup

    @site.instance_variable_set(:@collections_final, true)
    @site.send(:reset_state_for_rebuild!)

    refute @site.collections_final?,
           'reset_state_for_rebuild! must reopen the contribute phase'
  ensure
    @site.instance_variable_set(:@generated_pages, generated_snapshot)
    @site.instance_variable_set(:@memos, memo_snapshot)
  end
end

# The ordering itself, asserted against the source rather than a Folio
# fixture: pagination must not run before publisher pages.
class GenerateAllOrderingTest < Minitest::Test
  def test_publisher_pages_are_generated_before_pagination
    source = File.read(File.join(Abqari::ROOT, 'lib', 'abqari', 'renderer.rb'),
                       encoding: 'UTF-8')
    body = source[/def generate_all\n(.*?)\n    end/m, 1]
    refute_nil body, 'generate_all should be findable'

    order = body.scan(/^\s*(generate_\w+|@site\.finalise_collections!)/).flatten

    contribute = order.index('generate_publisher_pages')
    barrier    = order.index('@site.finalise_collections!')
    paginate   = order.index('generate_paginated_pages')

    refute_nil contribute, 'publisher pages should be generated in generate_all'
    refute_nil barrier,    'generate_all should close the contribute phase'
    refute_nil paginate,   'pagination should be generated in generate_all'

    assert contribute < barrier,
           'publisher pages must be contributed before collections are finalised'
    assert barrier < paginate,
           'pagination reads collections — it must run after the barrier'
  end
end

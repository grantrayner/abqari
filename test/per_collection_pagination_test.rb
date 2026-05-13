# frozen_string_literal: true

require_relative 'test_helper'
require 'ostruct'

# Per-collection pagination — `collections.<name>.pagination.per_page`
# overrides the site-wide `pagination.per_page` default when a page
# uses `paginate: true` to opt into pagination.
#
# Priority order under `paginate: true`:
#   1. collections.<coll_name>.pagination.per_page
#   2. pagination.per_page (site-wide)
#   3. PAGINATION_DEFAULT (10)
#
# Page frontmatter `paginate: <Integer>` always wins regardless of
# collection config — that path is covered in site_test.rb's
# resolve_per_page tests.
class PerCollectionPaginationTest < Minitest::Test
  def setup
    @site = Abqari::Site.new
    @renderer = @site.renderer
  end

  def page_with(frontmatter)
    OpenStruct.new(frontmatter: frontmatter)
  end

  # --- Per-collection overrides ----------------------------------------

  def test_photos_collection_override_used_under_paginate_true
    @site.config['collections'] = {
      'photos' => { 'pagination' => { 'per_page' => 12 } }
    }
    page = page_with('paginate' => true)
    assert_equal 12, @renderer.send(:resolve_per_page, page, 'photos')
  end

  def test_each_collection_resolves_independently
    @site.config['collections'] = {
      'posts'        => { 'pagination' => { 'per_page' => 10 } },
      'photos'       => { 'pagination' => { 'per_page' => 12 } },
      'publications' => { 'pagination' => { 'per_page' => 16 } },
      'workshops'    => { 'pagination' => { 'per_page' => 6 } }
    }
    page = page_with('paginate' => true)

    assert_equal 10, @renderer.send(:resolve_per_page, page, 'posts')
    assert_equal 12, @renderer.send(:resolve_per_page, page, 'photos')
    assert_equal 16, @renderer.send(:resolve_per_page, page, 'publications')
    assert_equal 6,  @renderer.send(:resolve_per_page, page, 'workshops')
  end

  # --- Fallback chain ---------------------------------------------------

  def test_falls_back_to_site_wide_default_when_collection_unset
    @site.config['pagination']   = { 'per_page' => 7 }
    @site.config['collections']  = {} # no per-collection blocks
    page = page_with('paginate' => true)

    assert_equal 7, @renderer.send(:resolve_per_page, page, 'photos')
  end

  def test_falls_back_to_engine_default_when_nothing_configured
    @site.config['pagination']  = nil
    @site.config['collections'] = nil
    page = page_with('paginate' => true)

    assert_equal Abqari::Renderer::PAGINATION_DEFAULT,
                 @renderer.send(:resolve_per_page, page, 'photos')
  end

  def test_falls_back_when_collection_has_no_pagination_block
    @site.config['collections'] = { 'photos' => { 'enabled' => true } } # no pagination key
    @site.config['pagination']  = { 'per_page' => 9 }
    page = page_with('paginate' => true)

    assert_equal 9, @renderer.send(:resolve_per_page, page, 'photos')
  end

  def test_invalid_per_collection_value_falls_through
    # Strings, zero, negative — all invalid; fall back to site-wide.
    @site.config['collections'] = {
      'photos' => { 'pagination' => { 'per_page' => 'twelve' } }
    }
    @site.config['pagination'] = { 'per_page' => 9 }
    page = page_with('paginate' => true)

    assert_equal 9, @renderer.send(:resolve_per_page, page, 'photos')
  end

  # --- Page-level integer override --------------------------------------

  def test_explicit_integer_in_frontmatter_wins_over_collection_default
    @site.config['collections'] = {
      'photos' => { 'pagination' => { 'per_page' => 12 } }
    }
    page = page_with('paginate' => 25)
    assert_equal 25, @renderer.send(:resolve_per_page, page, 'photos')
  end

  # --- Backwards compatibility (legacy single-arg form) -----------------

  def test_resolve_per_page_without_coll_name_uses_global_default
    # Existing call sites in site_test.rb pass only `page`; ensure
    # they keep their pre-refactor semantics.
    @site.config['collections'] = {
      'photos' => { 'pagination' => { 'per_page' => 12 } }
    }
    @site.config['pagination'] = { 'per_page' => 9 }
    page = page_with('paginate' => true)

    # No coll_name → ignores per-collection override.
    assert_equal 9, @renderer.send(:resolve_per_page, page)
  end
end

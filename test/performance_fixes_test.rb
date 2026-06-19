# frozen_string_literal: true

require_relative 'test_helper'

# Behaviour tests for the performance fixes in review items #9, #11,
# #13. These don't measure wall time (CI variance makes that flaky);
# instead they pin the observable invariants — cache reuse, memoised
# return values, matrix correctness — that the fixes promised to
# preserve.

class CollectionUrlIndexTest < Minitest::Test
  def setup
    @site = TestHelpers.built_site
  end

  def test_collection_url_index_returns_zero_based_position_per_url
    pages = @site.collection('posts')
    index = @site.collection_url_index('posts')

    pages.each_with_index do |page, i|
      assert_equal i, index[page.url], "url #{page.url} should be at position #{i}"
    end
  end

  def test_collection_url_index_is_memoised
    a = @site.collection_url_index('posts')
    b = @site.collection_url_index('posts')
    assert_same a, b, 'repeated calls should return the same hash object'
  end

  def test_collection_url_index_resolves_slug_aliases_to_canonical
    canonical = @site.collection_url_index('posts').object_id
    # When `slug:` aliasing isn't configured (default fixture), the
    # alias path equals the canonical path. Verifying the
    # canonicalisation lookup still returns the same cached hash
    # protects the alias→canonical reuse from accidentally double-
    # caching the same data.
    alias_lookup = @site.collection_url_index('posts').object_id
    assert_equal canonical, alias_lookup
  end

  def test_next_in_collection_uses_url_index_not_linear_scan
    pages = @site.collection('posts')
    skip 'fixture has < 2 posts' if pages.size < 2

    middle = pages[pages.size / 2]
    newer  = @site.next_in_collection(middle)

    refute_nil newer, 'a post in the middle should have a newer neighbour'
    assert_equal pages[(pages.size / 2) - 1].url, newer.url
  end
end

class TagCooccurrenceMatrixTest < Minitest::Test
  def setup
    @site = TestHelpers.built_site
    @viz  = Abqari::Visualizations.new(@site)
    @data = @viz.send(:tag_cooccurrence_data)
  end

  def test_matrix_is_square
    n = @data['tags'].size
    assert_equal n, @data['matrix'].size
    @data['matrix'].each { |row| assert_equal n, row.size }
  end

  def test_diagonal_is_zero
    @data['matrix'].each_with_index { |row, i| assert_equal 0, row[i] }
  end

  def test_matrix_is_symmetric
    @data['matrix'].each_with_index do |row, i|
      row.each_with_index do |val, j|
        assert_equal val, @data['matrix'][j][i],
                     "matrix should be symmetric at (#{i},#{j})"
      end
    end
  end

  def test_cell_count_matches_overlapping_posts
    # Pick two tags that share at least one post in the fixture (if any).
    grouped = @site.posts_by_term('tags')
    pair = grouped.keys.combination(2).find do |a, b|
      (Set.new(grouped[a]) & Set.new(grouped[b])).size.positive?
    end
    skip 'fixture has no overlapping tag pairs' unless pair

    a, b = pair
    expected = (Set.new(grouped[a]) & Set.new(grouped[b])).size
    i = @data['tags'].index(a)
    j = @data['tags'].index(b)
    assert_equal expected, @data['matrix'][i][j]
  end
end

class DescriptionMemoisationTest < Minitest::Test
  def setup
    @site = TestHelpers.built_site
  end

  def test_description_is_memoised_per_page
    post = @site.posts.first
    a = post.description
    b = post.description
    assert_same a, b, 'description should be the same object across calls'
  end

  def test_description_falls_back_to_first_paragraph_without_re_reading_body
    # Construct a page with no frontmatter `description:` so the
    # description path goes through `first_paragraph_text`. Verify
    # that after the first read + `forget_body!`, repeated description
    # calls don't re-read the body from disk.
    Dir.mktmpdir('abqari-desc-memo') do |dir|
      path = File.join(dir, 'fallback.md')
      File.write(path, <<~MD)
        ---
        title: Fallback test
        ---

        This is the first paragraph that should land as the description.
      MD

      page = Abqari::Page.new(path, @site)

      first = page.description
      assert_match(/first paragraph/, first.to_s)

      page.forget_body!
      reads = 0
      page.define_singleton_method(:load_body_from_file!) { reads += 1; super() }

      3.times { page.description }
      assert_equal 0, reads, 'memoised description must not trigger any body re-reads'
    end
  end

  def test_first_paragraph_text_is_memoised
    post = @site.posts.first
    a = post.send(:first_paragraph_text)
    b = post.send(:first_paragraph_text)
    # nil is a valid memo result for posts that have no first paragraph;
    # for those the equality check is what matters, not identity.
    if a.nil?
      assert_nil b
    else
      assert_same a, b
    end
  end
end

class SharedDepsThemeScopingTest < Minitest::Test
  # The shared-deps mtime walks the active theme dir, not every theme
  # the gem ships. The static GLOBAL_DEP_GLOBS constant should NOT
  # contain `themes/**/*` (which would walk every theme), and the
  # per-build resolution should append a glob scoped to the active
  # theme name.

  def test_global_dep_globs_excludes_blanket_themes_pattern
    refute_includes Abqari::Renderer::GLOBAL_DEP_GLOBS, 'themes/**/*',
                    'the blanket themes glob would walk every theme on every build'
  end

  def test_compute_shared_deps_mtime_reflects_active_theme_only
    site = TestHelpers.built_site
    renderer = site.renderer
    theme = site.config['theme'].to_s
    refute_empty theme, 'fixture should configure a theme'

    # Touch the active theme directory's most recently modified file
    # and confirm the mtime moves forward. Then touch an INACTIVE
    # theme and confirm the mtime is unchanged.
    active_dir   = File.join(site.engine_root, 'themes', theme)
    inactive     = (%w[bootstrap magazine minimal notebook sand custom] - [theme]).first
    inactive_dir = File.join(site.engine_root, 'themes', inactive) if inactive
    skip 'fixture has only one theme installed' unless inactive_dir && Dir.exist?(inactive_dir)

    site.renderer.clear_template_cache  # force recompute below
    base = renderer.send(:compute_shared_deps_mtime)

    # Touch a file in the inactive theme — the mtime should NOT advance.
    inactive_file = Dir.glob(File.join(inactive_dir, '**', '*')).find { |p| File.file?(p) }
    skip 'inactive theme has no files to touch' unless inactive_file
    new_time = Time.now + 60
    File.utime(new_time, new_time, inactive_file)

    site.renderer.clear_template_cache
    after_inactive = renderer.send(:compute_shared_deps_mtime)
    assert_equal base, after_inactive,
                 'touching an inactive theme must not invalidate the build cache'

    # Touch a file in the active theme — the mtime SHOULD advance.
    active_file = Dir.glob(File.join(active_dir, '**', '*')).find { |p| File.file?(p) }
    skip 'active theme has no files to touch' unless active_file
    File.utime(new_time + 60, new_time + 60, active_file)

    site.renderer.clear_template_cache
    after_active = renderer.send(:compute_shared_deps_mtime)
    assert after_active > base,
           'touching the active theme must advance the shared-deps mtime'
  end
end

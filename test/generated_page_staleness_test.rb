# frozen_string_literal: true

require_relative 'test_helper'
require 'tmpdir'

# Incremental rebuilds and generated pages.
#
# Layouts are deliberately kept OUT of `Renderer::GLOBAL_DEP_GLOBS` and
# tracked per-page via `layout_deps_mtime`, so editing one layout doesn't
# invalidate every page. But only `Page` ever consulted it — every
# generated page (tag pages, pagination shards, publisher pages,
# visualizations) checked `shared_deps_mtime` and its items' mtimes and
# nothing else. Editing `taxonomy.html.erb` with the dev server running
# rebuilt nothing, and the browser reloaded to stale HTML.
#
# `layout_name` is now shared between `render` and `needs_render?` on
# each of these classes, so the staleness check can't drift from the
# layout actually rendered.
class GeneratedPageStalenessTest < Minitest::Test
  GENERATED_PAGE_CLASSES = {
    'TaxonomyPage'       => 'lib/abqari/taxonomy_page.rb',
    'PaginatedShard'     => 'lib/abqari/paginated_shard.rb',
    'PublisherIndexPage' => 'lib/abqari/publisher_pages.rb',
    'PublisherShowPage'  => 'lib/abqari/publisher_pages.rb',
    'VisualizationPage'  => 'lib/abqari/visualizations.rb'
  }.freeze

  def source_for(path)
    File.read(File.join(Abqari::ROOT, path), encoding: 'UTF-8')
  end

  def test_every_generated_page_class_consults_layout_deps_mtime
    GENERATED_PAGE_CLASSES.each_value.uniq.each do |path|
      body = source_for(path)
      # Each `needs_render?` in the file must reference layout_deps_mtime.
      needs_render_bodies = body.scan(/def needs_render\?(.*?)\n    end/m).flatten
      refute_empty needs_render_bodies, "#{path} should define needs_render?"

      needs_render_bodies.each do |nr|
        assert_match(/layout_deps_mtime/, nr,
                     "a needs_render? in #{path} ignores layout changes — " \
                     'editing its layout would leave output stale')
      end
    end
  end

  def test_render_and_needs_render_share_one_layout_definition
    # The drift guard: if `render` hardcodes a layout string instead of
    # calling `layout_name`, the staleness check watches one layout while
    # a different one is rendered.
    GENERATED_PAGE_CLASSES.each_value.uniq.each do |path|
      body = source_for(path)
      renders = body.scan(/def render\b(.*?)\n    end/m).flatten

      renders.each do |r|
        next unless r.include?('render_layout')

        assert_match(/render_layout\(layout_name\)/, r,
                     "a render in #{path} should call render_layout(layout_name) " \
                     'so needs_render? watches the same layout')
      end
    end
  end

  def test_generated_page_classes_expose_layout_name
    GENERATED_PAGE_CLASSES.each do |klass, path|
      body = source_for(path)
      assert_match(/def layout_name/, body,
                   "#{klass} (#{path}) should expose layout_name")
    end
  end
end

# Site#output_dir must be absolute — Page#url derives every internal URL
# by stripping it off an absolute output path.
class OutputDirNormalisationTest < Minitest::Test
  def setup
    @prev_root = ENV['ABQARI_SITE_ROOT']
    @prev_out  = ENV['ABQARI_OUTPUT_DIR']
    @tmpdir = Dir.mktmpdir('abqari-output-dir')
    ENV['ABQARI_SITE_ROOT'] = @tmpdir
    FileUtils.mkdir_p(File.join(@tmpdir, 'config'))
    File.write(File.join(@tmpdir, 'config/site.yml'), "title: T\n")
  end

  def teardown
    ENV['ABQARI_SITE_ROOT'] = @prev_root
    ENV['ABQARI_OUTPUT_DIR'] = @prev_out
    FileUtils.rm_rf(@tmpdir)
  end

  def site_with(output_dir)
    ENV['ABQARI_OUTPUT_DIR'] = output_dir
    Abqari::Site.new
  end

  def test_default_output_dir_is_absolute
    ENV.delete('ABQARI_OUTPUT_DIR')
    assert_equal File.join(@tmpdir, '_site'), Abqari::Site.new.output_dir
  end

  # The bug: a relative value stripped nothing, so every href, sitemap
  # <loc> and feed link carried the developer's absolute filesystem path
  # — published, with the build reporting success.
  def test_relative_output_dir_is_expanded_against_site_root
    assert_equal File.join(@tmpdir, '_out'), site_with('_out').output_dir
  end

  def test_trailing_slash_is_normalised
    # A trailing slash consumed the leading `/` of every URL.
    assert_equal File.join(@tmpdir, '_out'), site_with("#{@tmpdir}/_out/").output_dir
  end

  def test_absolute_output_dir_is_left_alone
    assert_equal '/tmp/abqari-explicit', site_with('/tmp/abqari-explicit').output_dir
  end

  def test_blank_output_dir_falls_back_to_the_default
    assert_equal File.join(@tmpdir, '_site'), site_with('   ').output_dir
  end
end

# The Folio cache basename is derived from KIND_TO_COLLECTION, not by
# pluralising `kind` — `"#{kind}s.yml"` produced `seriess.yml`.
class FolioCachePathTest < Minitest::Test
  def setup
    @site = TestHelpers.built_site
  end

  def show_page(kind, slug)
    Abqari::PublisherShowPage.new(@site,
                                  kind: kind,
                                  slug: slug,
                                  data: { 'title' => 'X' },
                                  layout: 'publication',
                                  url: "/#{kind}s/#{slug}/")
  end

  def test_cache_basenames_match_the_files_folio_actually_writes
    expected = {
      'publication' => 'publications.yml',
      'bundle'      => 'bundles.yml',
      'series'      => 'series.yml' # not seriess.yml
    }

    expected.each do |kind, basename|
      path = show_page(kind, 'x').folio_cache_path
      assert_equal basename, File.basename(path),
                   "#{kind} should read vendor/folio/#{basename}"
    end
  end

  def test_every_folio_endpoint_has_a_reachable_cache_path
    # Folio writes one cache file per endpoint; every kind the publisher
    # pages know about must point at one of them.
    written = Abqari::Folio::ENDPOINTS.values.map { |v| "#{v}.yml" }.to_set

    Abqari::PublisherShowPage::KIND_TO_COLLECTION.each_key do |kind|
      basename = File.basename(show_page(kind, 'x').folio_cache_path)
      assert_includes written, basename,
                      "#{kind} reads #{basename}, which Folio never writes"
    end
  end
end

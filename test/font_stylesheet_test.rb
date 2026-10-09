# frozen_string_literal: true

require_relative 'test_helper'
require 'ostruct'
require 'tmpdir'

# The `bin/fetch-fonts` stylesheet ships under a content-hashed URL.
# It used to be linked at a fixed `/assets/fonts/fonts.css`, which the
# generated `_headers` serves `immutable` for a year along with the rest
# of `/assets/*` — so after a site changed `fonts:` and re-fetched,
# returning visitors kept the old `@font-face` rules and the new
# families never loaded. Same bug `syntax.css` had before the CSS
# bundle (see css_bundle_test.rb).
class FontStylesheetTest < Minitest::Test
  FINGERPRINTED = %r{\A/assets/fonts/fonts\.[0-9a-f]{10}\.css\z}.freeze

  def setup
    @site = TestHelpers.built_site
  end

  def fonts_href
    @site.assets.path_for('fonts/fonts.css')
  end

  def test_head_links_the_fingerprinted_font_stylesheet
    html = TestHelpers.read_output('index.html')
    assert_match FINGERPRINTED, fonts_href
    assert_includes html, %(href="#{fonts_href}")
    refute_includes html, 'href="/assets/fonts/fonts.css"'
  end

  def test_fingerprinted_stylesheet_keeps_every_font_face
    # It's minified in production, and the minifier has deleted content
    # before. Every face and every woff2 reference must survive.
    source  = File.read(File.join(@site.site_root, 'vendor', 'fonts', 'fonts.css'), encoding: 'UTF-8')
    shipped = TestHelpers.read_output(fonts_href.delete_prefix('/'))
    assert_equal source.scan('@font-face').size, shipped.scan('@font-face').size
    assert_equal source.scan(%r{url\(/assets/fonts/[^)]+\.woff2\)}),
                 shipped.scan(%r{url\(/assets/fonts/[^)]+\.woff2\)})
  end

  def test_unversioned_copy_still_ships_for_overridden_heads
    assert TestHelpers.output_exists?('assets/fonts/fonts.css')
  end
end

class FontStylesheetPipelineTest < Minitest::Test
  ENGINE_ROOT = File.expand_path('..', __dir__)

  def setup
    @tmpdir = Dir.mktmpdir('abqari-font-css-test')
    @site_root = File.join(@tmpdir, 'site')
    @output    = File.join(@tmpdir, 'out')
    FileUtils.mkdir_p(File.join(@site_root, 'vendor', 'fonts'))
  end

  def teardown
    FileUtils.rm_rf(@tmpdir)
  end

  def processed_pipeline
    site = OpenStruct.new(env: :production, site_root: @site_root,
                          engine_root: ENGINE_ROOT, output_dir: @output)
    site.define_singleton_method(:config) { { 'theme' => 'minimal' } }
    site.define_singleton_method(:external_symlink?) { |_p| false }
    Abqari::AssetPipeline.new(site).tap(&:process)
  end

  def write_fonts_css(css)
    File.write(File.join(@site_root, 'vendor', 'fonts', 'fonts.css'), css)
  end

  def test_refetched_fonts_get_a_new_url
    write_fonts_css("@font-face { font-family: 'Inter'; src: url(/assets/fonts/a.woff2) format('woff2'); }")
    before = processed_pipeline.path_for('fonts/fonts.css')

    write_fonts_css("@font-face { font-family: 'Fraunces'; src: url(/assets/fonts/b.woff2) format('woff2'); }")
    after = processed_pipeline.path_for('fonts/fonts.css')

    refute_equal before, after, 'new font content must change the stylesheet URL'
  end

  def test_no_font_stylesheet_asset_before_fonts_are_fetched
    FileUtils.rm_rf(File.join(@site_root, 'vendor', 'fonts'))
    assert_raises(ArgumentError) { processed_pipeline.path_for('fonts/fonts.css') }
  end
end

# Incremental (dev-server) rebuilds skip pages whose dependencies are
# unchanged. The font stylesheet's URL is now baked into every page, so
# a re-fetch has to invalidate them all or the dev site keeps linking
# the old hash.
class FontStylesheetDepsTest < Minitest::Test
  def setup
    @prev_root = ENV['ABQARI_SITE_ROOT']
    @tmpdir = Dir.mktmpdir('abqari-font-deps')
    ENV['ABQARI_SITE_ROOT'] = @tmpdir
    FileUtils.mkdir_p(File.join(@tmpdir, 'config'))
    FileUtils.mkdir_p(File.join(@tmpdir, 'vendor', 'fonts'))
    File.write(File.join(@tmpdir, 'config/site.yml'), "title: T\n")
  end

  def teardown
    ENV['ABQARI_SITE_ROOT'] = @prev_root
    FileUtils.rm_rf(@tmpdir)
  end

  def test_refetching_fonts_invalidates_cached_renders
    fonts_css = File.join(@tmpdir, 'vendor', 'fonts', 'fonts.css')
    File.write(fonts_css, '@font-face {}')
    future = Time.now + 3600
    File.utime(future, future, fonts_css)

    mtime = Abqari::Site.new.renderer.send(:compute_shared_deps_mtime)
    assert mtime >= future, 'vendor/fonts/fonts.css must be a shared render dependency'
  end
end

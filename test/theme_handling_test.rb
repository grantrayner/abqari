# frozen_string_literal: true

require_relative 'test_helper'
require 'ostruct'
require 'tmpdir'

# Theme resolution edge cases. Historically none of these were guarded:
# a typo'd `theme:` produced N opaque per-page render failures, a
# traversal-shaped name (`theme: ../app`) walked and published whatever
# it resolved to, `theme: bootstrap` fingerprinted ~700 KB of dead
# copies of the vendored dist into `_site/assets/public/`, and a
# site-local `themes/<name>/public/` silently shadowed the engine's
# entire public tree instead of merging with it.
class ThemeHandlingTest < Minitest::Test
  ENGINE_ROOT = File.expand_path('..', __dir__)

  def setup
    @tmpdir = Dir.mktmpdir('abqari-theme-test')
    @site_root = File.join(@tmpdir, 'site')
    @output    = File.join(@tmpdir, 'out')
    FileUtils.mkdir_p(@site_root)
  end

  def teardown
    FileUtils.rm_rf(@tmpdir)
  end

  def stub_site(config)
    site = OpenStruct.new(env: :production, site_root: @site_root,
                          engine_root: ENGINE_ROOT, output_dir: @output)
    site.define_singleton_method(:config) { config }
    site.define_singleton_method(:external_symlink?) { |_p| false }
    site
  end

  def pipeline(config)
    Abqari::AssetPipeline.new(stub_site(config))
  end

  # --- validate_theme! -------------------------------------------------

  def test_unknown_theme_raises_with_available_names
    error = assert_raises(RuntimeError) { pipeline('theme' => 'minimlal').validate_theme! }
    assert_includes error.message, 'minimlal'
    assert_includes error.message, 'minimal',   'error should list the valid themes'
    assert_includes error.message, "'none'"
  end

  def test_traversal_shaped_theme_name_raises_path_safe_error
    ['../app', '../../etc', 'a/b', "themes\n../x", 'UPPER'].each do |name|
      assert_raises(Abqari::PathSafe::Error, "expected #{name.inspect} to be rejected") do
        pipeline('theme' => name).validate_theme!
      end
    end
  end

  def test_none_theme_is_valid_without_any_css
    assert_nil pipeline('theme' => 'none').validate_theme!
  end

  def test_engine_themes_are_valid
    %w[minimal magazine notebook sand custom bootstrap].each do |name|
      assert_nil pipeline('theme' => name).validate_theme!
    end
  end

  def test_site_local_theme_with_app_css_is_valid
    FileUtils.mkdir_p(File.join(@site_root, 'themes', 'mytheme', 'css'))
    File.write(File.join(@site_root, 'themes', 'mytheme', 'css', 'app.css'), ':root {}')
    assert_nil pipeline('theme' => 'mytheme').validate_theme!
  end

  def test_site_local_theme_without_app_css_raises_anchor_message
    FileUtils.mkdir_p(File.join(@site_root, 'themes', 'bare'))
    error = assert_raises(RuntimeError) { pipeline('theme' => 'bare').validate_theme! }
    assert_includes error.message, 'css/app.css'
  end

  def test_missing_theme_key_defaults_to_minimal_everywhere
    # The default lives in SiteConfig::DEFAULTS so every reader of
    # config['theme'] agrees — when it was pipeline-local, the
    # renderer's theme-mtime scoping read '' and hot reload went stale.
    assert_equal 'minimal', Abqari::SiteConfig::DEFAULTS['theme']
    assert_equal 'minimal', pipeline({}).theme_name
  end

  # --- theme public/ handling ------------------------------------------

  def test_theme_public_tree_is_not_fingerprinted_into_assets
    pl = pipeline('theme' => 'bootstrap', 'minify' => false)
    pl.process

    dead = Dir.glob(File.join(@output, 'assets', 'public', '**', '*'))
    assert_empty dead, 'theme public/ must ship via copy_public, not the asset pipeline'
    # The theme's real asset (css/app.css) still processes.
    assert_match %r{\A/assets/css/app\.[0-9a-f]{10}\.css\z}, pl.path_for('css/app.css')
  end

  def test_site_theme_public_merges_with_engine_theme_public
    # One site-local extra file must not stop the engine's vendored
    # dist from shipping (the old find_in_paths picked ONE dir).
    FileUtils.mkdir_p(File.join(@site_root, 'themes', 'bootstrap', 'public'))
    File.write(File.join(@site_root, 'themes', 'bootstrap', 'public', 'extra.css'), '.x{}')

    Abqari::ArtifactWriter.new(stub_site('theme' => 'bootstrap')).copy_public

    assert File.exist?(File.join(@output, 'css', 'bootstrap.min.css')),
           "site-local theme public/ must MERGE with the engine's, not shadow it"
    assert File.exist?(File.join(@output, 'extra.css'))
  end

  def test_site_theme_public_file_wins_over_engine_copy
    FileUtils.mkdir_p(File.join(@site_root, 'themes', 'bootstrap', 'public', 'css'))
    File.write(File.join(@site_root, 'themes', 'bootstrap', 'public', 'css', 'bootstrap.min.css'),
               '/* site override */')

    Abqari::ArtifactWriter.new(stub_site('theme' => 'bootstrap')).copy_public

    shipped = File.read(File.join(@output, 'css', 'bootstrap.min.css'), encoding: 'UTF-8')
    assert_includes shipped, 'site override'
  end
end

# frozen_string_literal: true

require_relative 'test_helper'
require 'abqari/cli'
require 'tmpdir'
require 'fileutils'

# `abqari new <projectname>` — bootstrap a fresh Abqari site by recursive-
# copying the skeleton template with ERB token substitution.
#
# These tests cover the scaffolding mechanics. The end-to-end build of
# a scaffolded site (does it actually run?) is verified manually via
# the bin/build smoke test described in CHANGELOG.
class CliNewTest < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir('abqari-cli-new-test')
    @original_pwd = Dir.pwd
    Dir.chdir(@tmpdir)
  end

  def teardown
    Dir.chdir(@original_pwd)
    FileUtils.rm_rf(@tmpdir)
  end

  # Tiny helper — runs the CLI's `new` subcommand with `--skip-bundle`
  # so the test doesn't try to fetch gems. Captures stdout/stderr so
  # the success-message noise doesn't pollute the test runner output.
  def run_new(*args)
    out, _err = capture_io do
      @result = Abqari::CLI::New.run(args + ['--skip-bundle'])
    end
    @stdout = out
    @result
  end

  # --- Happy path ----------------------------------------------------

  def test_creates_target_directory_with_skeleton
    assert run_new('mysite')
    assert Dir.exist?('mysite')
    assert File.exist?('mysite/Gemfile')
    assert File.exist?('mysite/config/site.yml')
    assert File.exist?('mysite/content/index.md')
    assert File.exist?('mysite/content/about.md')
    assert File.exist?('mysite/content/posts/index.md')
    assert File.exist?('mysite/app/assets/css/site.css')
    assert File.exist?('mysite/bin/build')
    assert File.exist?('mysite/bin/serve')
    assert File.exist?('mysite/.gitignore')
    assert File.exist?('mysite/README.md')
  end

  def test_bin_scripts_are_executable
    run_new('mysite')
    %w[build serve audit new].each do |script|
      assert File.executable?("mysite/bin/#{script}"), "bin/#{script} should be executable"
    end
  end

  def test_no_template_suffix_in_output
    # `.tt` files in the skeleton are ERB; output should land at the
    # path without the suffix.
    run_new('mysite')
    refute Dir.glob('mysite/**/*.tt').any?, 'no .tt files should survive in the scaffolded site'
  end

  # --- Token substitution --------------------------------------------

  def test_substitutes_projectname_into_title_by_default
    run_new('the-cool-site')
    config = File.read('the-cool-site/config/site.yml', encoding: 'UTF-8')
    # Default title is the projectname title-cased.
    assert_match(/^title: The Cool Site$/, config)
  end

  def test_name_flag_overrides_titleized_default
    run_new('mysite', '--name', 'My Custom Title')
    config = File.read('mysite/config/site.yml', encoding: 'UTF-8')
    assert_match(/^title: My Custom Title$/, config)
  end

  def test_substitutes_description_author_theme_locale
    run_new('mysite',
            '--description', 'A neat little blog',
            '--author',      'Jane Smith',
            '--theme',       'magazine',
            '--locale',      'fr')
    config = File.read('mysite/config/site.yml', encoding: 'UTF-8')
    assert_match(/^description: A neat little blog$/, config)
    assert_match(/^author: Jane Smith$/, config)
    assert_match(/^theme: magazine$/, config)
    assert_match(/^locale: fr$/, config)
  end

  def test_gemfile_uses_git_source_by_default
    run_new('mysite')
    gemfile = File.read('mysite/Gemfile')
    assert_match(/gem 'abqari', git:/, gemfile)
    refute_match(/gem 'abqari', path:/, gemfile)
  end

  def test_engine_path_writes_path_source_in_gemfile
    run_new('mysite', '--engine', 'path')
    gemfile = File.read('mysite/Gemfile')
    assert_match(%r{gem 'abqari', path: '../abqari'}, gemfile)
    refute_match(/git:/, gemfile)
  end

  # --- Validation + safety -------------------------------------------

  def test_unknown_theme_is_rejected
    refute run_new('mysite', '--theme', 'banana')
    refute Dir.exist?('mysite'), 'should bail before creating the dir'
  end

  def test_unknown_engine_is_rejected
    refute run_new('mysite', '--engine', 'rubygems')   # not yet supported
    refute Dir.exist?('mysite')
  end

  def test_refuses_to_overwrite_non_empty_target
    FileUtils.mkdir_p('existing/some-dir')
    File.write('existing/some-dir/file.txt', 'hands off')

    refute run_new('existing'), 'should refuse to overwrite without --force'
    assert File.exist?('existing/some-dir/file.txt'), 'existing files should be untouched'
  end

  def test_force_flag_overwrites_existing_target
    FileUtils.mkdir_p('existing')
    File.write('existing/old.txt', 'stale')

    assert run_new('existing', '--force')
    # The skeleton has been copied in alongside the existing file.
    assert File.exist?('existing/Gemfile')
    assert File.exist?('existing/old.txt'), '--force overlays; it does not wipe'
  end

  def test_requires_a_projectname
    refute run_new, 'should error when no projectname is given'
  end

  # --- Example post is scaffolded for first-run ergonomics -----------

  def test_includes_an_example_post
    run_new('mysite')
    post_paths = Dir.glob('mysite/content/posts/*/index.md')
    refute_empty post_paths, 'expected at least one example post'
    body = File.read(post_paths.first, encoding: 'UTF-8')
    assert_match(/^title:/, body, 'example post should have frontmatter')
    assert_match(/^published: true$/, body)
  end

  # --- Blank mode --------------------------------------------------

  def test_blank_mode_skips_example_post
    run_new('mysite', '--blank')
    # The welcome example post directory should NOT exist.
    refute Dir.exist?('mysite/content/posts/welcome'), 'example post should be skipped in blank mode'
    # But the posts collection's index page DOES still exist — empty
    # is a legitimate state.
    assert File.exist?('mysite/content/posts/index.md')
  end

  def test_blank_mode_uses_terse_home_page
    run_new('mysite', '--blank')
    home = File.read('mysite/content/index.md', encoding: 'UTF-8')
    # The blank variant just says "Welcome." — no tutorial body.
    refute_match(/Where to next/, home, 'blank home should not carry the tutorial body')
    assert_match(/^Welcome\.\s*$/, home, 'blank home should be a single-line welcome')
  end

  def test_blank_mode_uses_terse_about_page
    run_new('mysite', '--blank')
    about = File.read('mysite/content/about.md', encoding: 'UTF-8')
    refute_match(/sits at .\/about\/./, about, 'blank about should not carry the explanatory body')
    assert_match(/^A short bio\.\s*$/, about, 'blank about should be a single-line stub')
  end

  def test_blank_mode_uses_terse_config
    run_new('mysite', '--blank')
    config = File.read('mysite/config/site.yml', encoding: 'UTF-8')
    # The full config has long ─── separator comments; the blank
    # variant doesn't.
    refute_match(/────────/, config, 'blank config should not carry the documentation banners')
    # Yet the config IS still a valid, working file — keys are present.
    assert_match(/^title:/, config)
    assert_match(/^collections:/, config)
    assert_match(/^environments:/, config)
  end

  def test_blank_mode_does_not_emit_dual_files
    # Both `.blank.<ext>.tt` and `.<ext>.tt` exist in the skeleton
    # tree; only ONE should land in the output (no `.blank.` files
    # surviving, no double-write to the same path).
    run_new('mysite', '--blank')
    refute Dir.glob('mysite/**/*.blank.*').any?,
           'no .blank.* sentinel files should survive in the scaffolded site'
  end

  def test_default_mode_uses_full_variants
    # Sanity check the inverse: without --blank, the populated home
    # page DOES carry the tutorial body, and the example post IS
    # present.
    run_new('mysite')
    home = File.read('mysite/content/index.md', encoding: 'UTF-8')
    assert_match(/Where to next/, home)
    assert Dir.exist?('mysite/content/posts/welcome')
  end
end

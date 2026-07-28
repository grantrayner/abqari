# frozen_string_literal: true

require_relative 'test_helper'
require 'abqari/cli'
require 'tmpdir'
require 'fileutils'

# `abqari theme eject <name>` — copies an engine theme's app.css into
# the site's themes/ dir, where the asset pipeline's site-over-engine
# precedence makes it the live copy. Exists because a gem-installed
# site can't sensibly edit files inside the gem.
class CliThemeTest < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir('abqari-cli-theme-test')
    @original_pwd = Dir.pwd
    Dir.chdir(@tmpdir)
    # Minimal site root — the command requires config/site.yml.
    FileUtils.mkdir_p('config')
    File.write('config/site.yml', "title: T\ntheme: minimal\n")
  end

  def teardown
    Dir.chdir(@original_pwd)
    FileUtils.rm_rf(@tmpdir)
  end

  def run_theme(*args)
    out, err = capture_io { @result = Abqari::CLI::Theme.run(args) }
    @stdout = out
    @stderr = err
    @result
  end

  def test_eject_copies_engine_theme_into_site
    assert run_theme('eject', 'minimal')
    assert File.file?('themes/minimal/css/app.css')
    engine_copy = File.read(File.join(Abqari::ROOT, 'themes', 'minimal', 'css', 'app.css'))
    assert_equal engine_copy, File.read('themes/minimal/css/app.css')
    # Same name — config already points at it; no rewrite needed.
    assert_includes File.read('config/site.yml'), 'theme: minimal'
  end

  def test_eject_as_renames_and_updates_config
    assert run_theme('eject', 'sand', '--as', 'mytheme')
    assert File.file?('themes/mytheme/css/app.css')
    assert_includes File.read('config/site.yml'), 'theme: mytheme'
  end

  def test_eject_refuses_overwrite_without_force
    FileUtils.mkdir_p('themes/minimal/css')
    File.write('themes/minimal/css/app.css', '/* mine */')
    refute run_theme('eject', 'minimal')
    assert_equal '/* mine */', File.read('themes/minimal/css/app.css')
    assert_match(/--force/, @stderr)
  end

  def test_eject_force_overwrites
    FileUtils.mkdir_p('themes/minimal/css')
    File.write('themes/minimal/css/app.css', '/* mine */')
    assert run_theme('eject', 'minimal', '--force')
    refute_equal '/* mine */', File.read('themes/minimal/css/app.css')
  end

  def test_unknown_theme_lists_available
    refute run_theme('eject', 'nope')
    assert_match(/minimal/, @stderr)
  end

  def test_invalid_name_rejected
    refute run_theme('eject', '../evil')
    refute run_theme('eject', 'minimal', '--as', '../evil')
    refute Dir.exist?('themes')
  end

  def test_bootstrap_cannot_be_renamed
    refute run_theme('eject', 'bootstrap', '--as', 'mybs')
    assert_match(/bootstrap/, @stderr)
    refute Dir.exist?('themes')
  end

  def test_bootstrap_can_shadow_in_place
    assert run_theme('eject', 'bootstrap')
    assert File.file?('themes/bootstrap/css/app.css')
  end

  def test_requires_site_root
    Dir.chdir(Dir.mktmpdir('abqari-not-a-site')) do
      refute Abqari::CLI::Theme.run(['eject', 'minimal'])
    end
  end

  def test_bare_invocation_prints_usage
    refute run_theme
    assert_match(/eject/, @stderr)
  end
end

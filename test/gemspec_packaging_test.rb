# frozen_string_literal: true

require_relative 'test_helper'
require 'open3'

# The gemspec's `spec.files` globs decide what actually ships in the
# published gem. `Dir.glob` skips dotfiles by default, which once
# silently dropped the skeleton's `.gitignore` and `vendor/*/.gitkeep`
# from the built gem — `abqari new` then scaffolded sites with no
# `.gitignore` at all. These tests evaluate the real gemspec and pin
# the packaging contract so a glob regression fails CI instead of
# shipping.
class GemspecPackagingTest < Minitest::Test
  ENGINE_ROOT = File.expand_path('..', __dir__)

  def self.spec_files
    @spec_files ||= Dir.chdir(ENGINE_ROOT) do
      Gem::Specification.load('abqari.gemspec').files
    end
  end

  def spec_files
    self.class.spec_files
  end

  def test_every_skeleton_file_on_disk_ships_in_the_gem
    skeleton_on_disk = Dir.chdir(ENGINE_ROOT) do
      Dir.glob('lib/abqari/templates/site_skeleton/**/*', File::FNM_DOTMATCH)
         .select { |f| File.file?(f) }
    end

    refute_empty skeleton_on_disk, 'skeleton tree should exist'
    missing = skeleton_on_disk - spec_files
    assert_empty missing,
                 "skeleton files present on disk but not packaged: #{missing.join(', ')}"
  end

  def test_skeleton_dotfiles_ship
    %w[
      lib/abqari/templates/site_skeleton/.gitignore
      lib/abqari/templates/site_skeleton/vendor/folio/.gitkeep
      lib/abqari/templates/site_skeleton/vendor/fonts/.gitkeep
      lib/abqari/templates/site_skeleton/.github/workflows/deploy-cloudflare.yml
    ].each do |path|
      assert_includes spec_files, path
    end
  end

  def test_no_directories_in_spec_files
    dirs = Dir.chdir(ENGINE_ROOT) { spec_files.reject { |f| File.file?(f) } }
    assert_empty dirs, "spec.files should list only files, got: #{dirs.join(', ')}"
  end

  def test_engine_assets_ship
    %w[
      exe/abqari
      lib/abqari.rb
      app/views/layouts/application.html.erb
      app/assets/css/_common.css
      themes/minimal/css/app.css
      vendor/d3/d3.v7.min.js
      LICENSE
      CHANGELOG.md
      README.md
    ].each do |path|
      assert_includes spec_files, path
    end
  end

  # Evaluating the gemspec must NOT load the engine, because Bundler
  # evaluates it before installing dependencies whenever the gem is
  # consumed from a git or path source. It once did
  # `require_relative 'lib/abqari'` to read VERSION, which dragged in
  # erubi/commonmarker/rouge/webrick and broke every clean-builder
  # deploy with "cannot load such file -- erubi". Locally it passed,
  # because those gems were already installed — so this check has to
  # run in a subprocess with a clean $LOADED_FEATURES.
  def test_evaluating_the_gemspec_does_not_load_runtime_dependencies
    script = <<~RUBY
      spec = Gem::Specification.load('abqari.gemspec')
      leaked = $LOADED_FEATURES.grep(/erubi|commonmarker|rouge|webrick|vips|reverse_markdown/)
      puts spec.version
      puts leaked.map { |f| File.basename(f) }.uniq.join(',')
    RUBY

    out, status = Open3.capture2e(RbConfig.ruby, '-e', script, chdir: ENGINE_ROOT)
    assert status.success?, "gemspec failed to evaluate:\n#{out}"

    version, leaked = out.lines.map(&:strip)
    assert_equal Abqari::VERSION, version
    assert_empty leaked.to_s,
                 "gemspec loaded runtime deps (#{leaked}) — it must only read " \
                 'lib/abqari/version.rb, or git/path installs break'
  end

  def test_version_file_is_dependency_free
    src = File.read(File.join(ENGINE_ROOT, 'lib', 'abqari', 'version.rb'), encoding: 'UTF-8')
    refute_match(/^\s*require/, src,
                 'lib/abqari/version.rb must not require anything')
    assert_includes GemspecPackagingTest.spec_files, 'lib/abqari/version.rb'
  end

  def test_site_specific_trees_do_not_ship
    leaked = spec_files.select do |f|
      f.start_with?('content/', 'config/', 'data/', 'bin/', 'docs/', 'audit/',
                    'vendor/folio/', 'vendor/fonts/', 'test/', '_site/')
    end
    assert_empty leaked, "site-specific files leaked into the gem: #{leaked.join(', ')}"
  end
end

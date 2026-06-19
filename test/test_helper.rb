# frozen_string_literal: true

# Bootstraps the Abqari test suite. Pure stdlib — uses Minitest, no extra gems.

$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))

# Opt-in coverage measurement: `COVERAGE=1 bin/test` writes a report
# to `coverage/`. The CI workflow exports COVERAGE=1 and fails the
# job when coverage on the audited files drops below the threshold.
# Without the env var, SimpleCov isn't loaded — keeps `bin/test` fast
# and stdlib-only in normal use.
if ENV['COVERAGE']
  require 'simplecov'
  require 'json'

  # Files where coverage matters most — review §9 called these out as
  # the high-value targets. Each is enforced at ≥85% individually
  # (looser than 100% so refactors don't have to add tests in
  # lockstep; tight enough that a regression that drops a class
  # entirely fires immediately).
  KEY_COVERAGE_FILES = %w[
    lib/abqari/page.rb
    lib/abqari/page/parser.rb
    lib/abqari/page/path.rb
    lib/abqari/page/bundle.rb
    lib/abqari/render_context.rb
    lib/abqari/audit.rb
    lib/abqari/site.rb
    lib/abqari/renderer.rb
    lib/abqari/path_safe.rb
    lib/abqari/http_safe.rb
    lib/abqari/site_config.rb
  ].freeze
  KEY_COVERAGE_THRESHOLD = 85.0

  SimpleCov.start do
    add_filter '/test/'
    add_filter '/vendor/'
    add_group 'Core',         'lib/abqari/site.rb'
    add_group 'Pages',        'lib/abqari/page.rb'
    add_group 'Rendering',    %w[lib/abqari/render_context lib/abqari/renderer.rb
                                 lib/abqari/erbi_template.rb]
    add_group 'Audit',        'lib/abqari/audit'
    add_group 'Safety',       %w[lib/abqari/path_safe.rb lib/abqari/http_safe.rb
                                 lib/abqari/site_config.rb]
    add_group 'Pipelines',    %w[lib/abqari/asset_pipeline.rb lib/abqari/image_pipeline.rb
                                 lib/abqari/font_pipeline.rb lib/abqari/bundle_assets.rb]
    add_group 'Artifacts',    %w[lib/abqari/sitemap.rb lib/abqari/feed.rb lib/abqari/robots.rb
                                 lib/abqari/headers_file.rb lib/abqari/manifest.rb
                                 lib/abqari/llms_txt.rb lib/abqari/og_image_generator.rb
                                 lib/abqari/security_txt.rb lib/abqari/redirects.rb
                                 lib/abqari/artifact_writer.rb]

    # Suite-wide floor: catches a regression that drops a large file.
    minimum_coverage 75
  end

  # Per-key-file gate. SimpleCov doesn't ship a per-file-pattern
  # threshold, so do it ourselves after the run.
  SimpleCov.at_exit do
    SimpleCov.result.format!
    failures = []
    SimpleCov.result.files.each do |file|
      rel = file.filename.sub("#{SimpleCov.root}/", '')
      next unless KEY_COVERAGE_FILES.include?(rel)

      pct = file.covered_percent
      failures << [rel, pct] if pct < KEY_COVERAGE_THRESHOLD
    end

    unless failures.empty?
      $stderr.puts "\nKEY-FILE COVERAGE FAILED (threshold: #{KEY_COVERAGE_THRESHOLD}%)"
      failures.each do |rel, pct|
        $stderr.puts "  #{format('%.1f', pct)}%  #{rel}"
      end
      Kernel.exit(1) if ENV['COVERAGE_FAIL_UNDER'] != 'false'
    end
  end
end

require 'fileutils'
require 'tmpdir'
require 'abqari'
require 'minitest/autorun'

# Production config so we exercise the real env (canonical URL, indexable, etc.).
ENV['ABQARI_ENV'] ||= 'production'

# Build to a temp dir so tests don't clobber the user's _site/.
# The tmpdir is intentionally outside site_root, so opt into the
# external-output escape hatch that Site#reset_output requires.
ENV['ABQARI_OUTPUT_DIR'] = File.join(Dir.tmpdir, 'abqari-test-site')
ENV['ABQARI_ALLOW_EXTERNAL_OUTPUT'] = 'true'

module TestHelpers
  # Build the canonical fixture site once per test run. The
  # `Abqari::BUILD_OK_SENTINEL` file is written by `Site#build`
  # only on a fully successful build — if it's absent, either the
  # fixture has never been built or a sibling test trampled
  # `_site/`. Either way, rebuild. The sentinel guarantees that
  # when it's present, `@pages` is populated and every artifact
  # is on disk, so no additional integrity checks are needed.
  def self.built_site
    @built_site ||= Abqari::Site.new
    sentinel = File.join(@built_site.output_dir, Abqari::BUILD_OK_SENTINEL)
    @built_site.build unless File.exist?(sentinel)
    @built_site
  end

  def self.read_output(relative_path)
    File.read(File.join(built_site.output_dir, relative_path), encoding: 'UTF-8')
  end

  def self.output_exists?(relative_path)
    File.exist?(File.join(built_site.output_dir, relative_path))
  end
end

# Eagerly warm the shared fixture before any test setup runs.
# `Site#site_root` memoises `ENV['ABQARI_SITE_ROOT']` on first
# read; if the first test to call `TestHelpers.built_site` happens
# to have mutated that env var in its `setup` (e.g. EnvOverrideTest,
# LayoutDepsMtimeTest), the fixture Site gets anchored to a tmpdir
# that lacks the engine's `app/assets/`. By touching `built_site`
# at suite-load time we lock in the canonical site_root before any
# test gets a chance to interfere.
TestHelpers.built_site

Minitest.after_run do
  FileUtils.rm_rf(ENV['ABQARI_OUTPUT_DIR']) if ENV['ABQARI_OUTPUT_DIR']&.start_with?(Dir.tmpdir)
end

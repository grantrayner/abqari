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

# Drop Ruby warnings raised from inside INSTALLED GEMS, before anything
# is required.
#
# Ruby 3.4+ warns on every mutation of a "chilled" string literal — a
# file with no `frozen_string_literal` comment. `reverse_markdown` has
# several, and it's called in a loop by the importer tests, so a clean
# run buried its own result under ~400 identical lines of
# "literal string will be frozen in the future".
#
# The filter is deliberately narrow: only warnings whose text points
# into a gem path are dropped. A warning from `lib/` or `test/` — ours
# to fix — still prints. `VERBOSE_WARNINGS=1` restores everything, for
# when you're auditing a dependency rather than reading a test run.
unless ENV['VERBOSE_WARNINGS']
  module GemWarningFilter
    GEM_PATH_RE = %r{/gems/[^/]+/(lib|ext)/}

    def warn(message, category: nil, **kwargs)
      return if message.to_s.match?(GEM_PATH_RE)

      super
    end
  end
  Warning.extend(GemWarningFilter)
end

require 'abqari'
require 'minitest/autorun'

# Quiet the engine's own logger by default.
#
# The suite deliberately exercises paths that log: builds, missing
# config, syndication, webmention fetches, plugin loading. At `info`
# that's several hundred lines of "Built 1 page(s)" and "Missing `url`"
# interleaved with the progress dots, which makes a failure genuinely
# hard to find. `error` keeps the loud things loud — including the
# deliberate crash fixtures, which SHOULD be visible — and drops the
# routine chatter.
#
# Set ABQARI_LOG to see everything for a debugging run:
#   ABQARI_LOG=info bin/test
unless ENV['ABQARI_LOG']
  REAL_STDOUT = $stdout
  REAL_STDERR = $stderr

  # Suppress info/warn when nobody is listening — but never when a test
  # is capturing.
  #
  # Gating on the log LEVEL would have been simpler and wrong: a test
  # that captures output is a test that asserts on it, so a quiet level
  # empties the very string under assertion. And the suite captures
  # three different ways (`capture_io`, a local `capture_stderr` helper,
  # and hand-rolled `$stderr = StringIO.new`), so wrapping any one of
  # them misses the others — and the next idiom someone invents.
  #
  # Checking whether the stream has been swapped covers all three and
  # anything future, because every capture technique works by replacing
  # `$stdout`/`$stderr`. Captured output is therefore byte-identical to
  # what it was before this filter existed.
  #
  # `error` is never suppressed: the suite exercises real failure paths
  # (plugin crashes, render errors) and those staying loud is the point.
  module QuietUnlessCaptured
    def info(msg)  = capturing? ? super : nil
    def warn(msg)  = capturing? ? super : nil
    def debug(msg) = capturing? ? super : nil

    private

    def capturing?
      !$stdout.equal?(REAL_STDOUT) || !$stderr.equal?(REAL_STDERR)
    end
  end
  Abqari::Log.singleton_class.prepend(QuietUnlessCaptured)
end

# Production config so we exercise the real env (canonical URL, indexable, etc.).
ENV['ABQARI_ENV'] ||= 'production'

# Build to a temp dir so tests don't clobber the user's _site/.
# The tmpdir is intentionally outside site_root, so opt into the
# external-output escape hatch that Site#reset_output requires.
#
# CANONICAL_OUTPUT_DIR is the shared fixture's fixed home. The shared
# site is pinned to it regardless of what any sibling test does to
# ENV['ABQARI_OUTPUT_DIR'] — see TestHelpers.built_site. Without the
# pin, a rebuild triggered mid-suite (sentinel missing) could target
# another test's tmpdir, which may already be torn down (the source of
# the historical order-dependent flake).
CANONICAL_OUTPUT_DIR = File.join(Dir.tmpdir, 'abqari-test-site')
ENV['ABQARI_OUTPUT_DIR'] = CANONICAL_OUTPUT_DIR
ENV['ABQARI_ALLOW_EXTERNAL_OUTPUT'] = 'true'

module TestHelpers
  CANONICAL_OUTPUT_DIR = ::CANONICAL_OUTPUT_DIR

  # Build the canonical fixture site once per test run. The
  # `Abqari::BUILD_OK_SENTINEL` file is written by `Site#build`
  # only on a fully successful build — if it's absent, either the
  # fixture has never been built or a sibling test trampled
  # `_site/`. Either way, rebuild. The sentinel guarantees that
  # when it's present, `@pages` is populated and every artifact
  # is on disk, so no additional integrity checks are needed.
  #
  # ENV['ABQARI_OUTPUT_DIR'] is force-restored to CANONICAL_OUTPUT_DIR
  # for the duration of the build so a sibling test that left it
  # pointing at its own (possibly deleted) tmpdir can't redirect the
  # shared fixture's output. It's restored afterward so the calling
  # test's environment is untouched.
  def self.built_site
    prev_out = ENV['ABQARI_OUTPUT_DIR']
    ENV['ABQARI_OUTPUT_DIR'] = CANONICAL_OUTPUT_DIR
    @built_site ||= Abqari::Site.new
    sentinel = File.join(CANONICAL_OUTPUT_DIR, Abqari::BUILD_OK_SENTINEL)
    @built_site.build unless File.exist?(sentinel)
    @built_site
  ensure
    ENV['ABQARI_OUTPUT_DIR'] = prev_out
  end

  # Read/exist checks target CANONICAL_OUTPUT_DIR directly rather than
  # `built_site.output_dir` (which floats with ENV) so they're immune
  # to a sibling test's env mutation.
  def self.read_output(relative_path)
    built_site
    File.read(File.join(CANONICAL_OUTPUT_DIR, relative_path), encoding: 'UTF-8')
  end

  def self.output_exists?(relative_path)
    built_site
    File.exist?(File.join(CANONICAL_OUTPUT_DIR, relative_path))
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

# Global test isolation for the process-wide `Abqari::Hooks` registry.
# Plugin-loading tests write plugin files that register lifecycle hooks
# (`:before_build`, `:after_generate`, `:post_process`, …) into the
# global registry via `PluginLoader`. If a test leaks those, they fire
# during any LATER build — including the shared fixture's rebuild in
# AuditTest — corrupting its output (doubled taxonomy pages, mutated
# HTML) nondeterministically. Individual test classes clear in their own
# teardown, but a single missed path is enough; clearing here after
# EVERY test guarantees no build ever inherits another test's hooks.
module Minitest
  class Test
    def after_teardown
      super
      Abqari::Hooks.clear!
    end
  end
end

Minitest.after_run do
  FileUtils.rm_rf(CANONICAL_OUTPUT_DIR) if CANONICAL_OUTPUT_DIR.start_with?(Dir.tmpdir)
end

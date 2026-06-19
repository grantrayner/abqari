# frozen_string_literal: true

require_relative '../test_helper'
require 'abqari/importers'
require 'abqari/importers/cli'
require 'tmpdir'
require 'stringio'

# CLI — covers argv parsing, platform dispatch, and the trailing-flag
# regression that `OptionParser#order` introduced (options after the
# positional source path were silently dropped). The CLI's behaviour
# is exercised by running it against the fixture sites the per-importer
# tests already use.
class ImporterCliTest < Minitest::Test
  CLI = Abqari::Importers::CLI

  def setup
    @site_root = Dir.mktmpdir('abqari-cli-test-')
    FileUtils.mkdir_p(File.join(@site_root, 'content', 'posts'))
  end

  def teardown
    FileUtils.rm_rf(@site_root)
  end

  def with_captured_stdout
    orig = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = orig
  end

  def imported_files
    Dir.glob(File.join(@site_root, 'content', 'posts', '**', 'index.md'))
  end

  def fixture
    File.expand_path('fixtures/substack-sample', __dir__)
  end

  def test_help_lists_all_registered_platforms
    out = with_captured_stdout { CLI.run(['--help'], site_root: @site_root) }
    assert_match(/substack/, out)
    assert_match(/ghost/,    out)
    assert_match(/jekyll/,   out)
  end

  def test_unknown_platform_warns_and_fails
    orig_err = $stderr
    $stderr  = StringIO.new
    ok = nil
    with_captured_stdout do
      ok = CLI.run(['fakeplatform', 'foo'], site_root: @site_root)
    end
    refute ok, 'CLI should return false for an unknown platform'
    assert_match(/Unknown importer/, $stderr.string)
  ensure
    $stderr = orig_err
  end

  def test_flag_after_source_path_is_honored
    # Regression: `OptionParser#order` (the default for parse) stops
    # at the first non-option argument, which silently dropped flags
    # like `--keep-remote` when they came after the positional source
    # path. We use `permute` instead so flag position is irrelevant.
    with_captured_stdout do
      CLI.run(['substack', fixture, '--keep-remote'], site_root: @site_root)
    end
    # If --keep-remote were dropped, the first post's body would be
    # rewritten to a local image filename (and an HTTP warning logged).
    # With the fix, the remote URL stays in place.
    first = imported_files.find { |p| p.include?('first-post/') && !p.include?('first-post-2') }
    refute_nil first
    assert_match(%r{https://substackcdn.com/image/fetch/abcdef/hero\.jpg},
                 File.read(first), 'remote URL should remain when --keep-remote is set')
  end

  def test_into_flag_routes_to_alternate_collection
    FileUtils.mkdir_p(File.join(@site_root, 'content', 'archive'))
    with_captured_stdout do
      CLI.run(['substack', fixture, '--into', 'archive', '--keep-remote'],
              site_root: @site_root)
    end
    archived = Dir.glob(File.join(@site_root, 'content', 'archive', '**', 'index.md'))
    assert_equal 4, archived.size
  end

  def test_dry_run_writes_no_files
    with_captured_stdout do
      CLI.run(['substack', fixture, '--dry-run'], site_root: @site_root)
    end
    assert_empty imported_files
    refute File.exist?(File.join(@site_root, '_import_report.md')),
           'dry-run should not write the report'
  end
end

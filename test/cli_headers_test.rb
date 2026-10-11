# frozen_string_literal: true

require_relative 'test_helper'
require 'abqari/cli'
require 'yaml'
require 'tmpdir'
require 'fileutils'

# `abqari headers` — the built `_headers` as Render rules. Render static
# sites ignore `_headers`, so these get pasted into the dashboard or
# render.yaml; a value that doesn't survive the paste byte-for-byte is
# a CSP that blocks the site's own scripts.
class CliHeadersTest < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir('abqari-cli-headers-test')
  end

  def teardown
    FileUtils.rm_rf(@tmpdir)
  end

  def test_built_headers_round_trip_through_the_yaml_exactly
    TestHelpers.built_site
    source = File.join(TestHelpers::CANONICAL_OUTPUT_DIR, '_headers')

    out, = capture_io { assert Abqari::CLI::Headers.run([source]) }
    rules = YAML.safe_load(out)['headers']

    expected = Abqari::CLI::Headers.new.parse(File.read(source, encoding: 'UTF-8'))
    assert_equal expected, rules
    csp = rules.find { |r| r['name'] == 'Content-Security-Policy' }
    assert_includes File.read(source, encoding: 'UTF-8'), "Content-Security-Policy: #{csp['value']}\n"
    assert_includes rules, { 'path' => '/assets/*', 'name' => 'Cache-Control',
                             'value' => 'public, max-age=31536000, immutable' }
  end

  def test_accepts_an_output_directory
    FileUtils.mkdir_p(File.join(@tmpdir, '_site'))
    File.write(File.join(@tmpdir, '_site', '_headers'), "/*\n  X-Content-Type-Options: nosniff\n")

    out, = capture_io { assert Abqari::CLI::Headers.run([File.join(@tmpdir, '_site')]) }

    assert_equal [{ 'path' => '/*', 'name' => 'X-Content-Type-Options', 'value' => 'nosniff' }],
                 YAML.safe_load(out)['headers']
  end

  def test_missing_headers_file_says_to_build_first
    _, err = capture_io { refute Abqari::CLI::Headers.run([File.join(@tmpdir, 'nope')]) }
    assert_match(%r{Run `bin/build` first}, err)
  end

  def test_dispatcher_knows_the_command
    _, err = capture_io { refute Abqari::CLI.run(['headers', File.join(@tmpdir, 'nope')]) }
    refute_match(/Unknown command/, err)
  end
end

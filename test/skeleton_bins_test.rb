# frozen_string_literal: true

require_relative 'test_helper'
require 'abqari/cli'
require 'open3'
require 'socket'
require 'net/http'

# The scaffolded site's bin/* scripts are copied from the skeleton, not
# generated from engine code — so they can silently drift from the APIs
# they call (bin/serve once called `Abqari::Server.new` without the
# required site argument; bin/audit once called a nonexistent
# `error_count`). These tests scaffold a real site and EXECUTE the
# scripts as subprocesses, resolving the engine via this checkout's
# Gemfile, so a signature drift fails the suite instead of the first
# `abqari new` user's first command.
class SkeletonBinsTest < Minitest::Test
  ENGINE_ROOT = File.expand_path('..', __dir__)
  SERVE_PORT  = 4000   # skeleton bin/serve hardcodes the engine default

  def setup
    @tmpdir   = Dir.mktmpdir('abqari-skeleton-bins')
    @site_dir = File.join(@tmpdir, 'site')
    capture_io do
      Dir.chdir(@tmpdir) { assert Abqari::CLI::New.run(['site', '--skip-bundle']) }
    end
  end

  def teardown
    FileUtils.rm_rf(@tmpdir)
  end

  def bin_env
    # Resolve the engine from this checkout, and clear every ABQARI_*
    # var the test harness exports (test_helper sets ABQARI_OUTPUT_DIR
    # and friends) — the scripts must see the environment a real user's
    # shell would provide, i.e. nothing.
    env = { 'BUNDLE_GEMFILE' => File.join(ENGINE_ROOT, 'Gemfile') }
    ENV.keys.grep(/\AABQARI_/).each { |k| env[k] = nil }
    env
  end

  def run_bin(script, *args)
    out, status = Open3.capture2e(bin_env, RbConfig.ruby, File.join(@site_dir, 'bin', script), *args)
    [out.force_encoding('UTF-8'), status]
  end

  def test_every_bin_script_parses
    scripts = Dir.glob(File.join(@site_dir, 'bin', '*'))
    refute_empty scripts
    scripts.each do |script|
      out, status = Open3.capture2e(RbConfig.ruby, '-c', script)
      assert status.success?, "#{File.basename(script)} has a syntax error:\n#{out}"
    end
  end

  def test_bin_build_builds_the_site
    out, status = run_bin('build')
    assert status.success?, "bin/build failed:\n#{out}"
    assert File.exist?(File.join(@site_dir, '_site', 'index.html'))
    assert File.exist?(File.join(@site_dir, '_site', Abqari::BUILD_OK_SENTINEL))
  end

  def test_with_collections_site_builds_including_empty_collection_indexes
    with_dir = File.join(@tmpdir, 'withsite')
    capture_io do
      Dir.chdir(@tmpdir) do
        assert Abqari::CLI::New.run(['withsite', '--skip-bundle',
                                     '--with', 'photos,publications,workshops'])
      end
    end

    out, status = Open3.capture2e(bin_env, RbConfig.ruby, File.join(with_dir, 'bin', 'build'))
    assert status.success?, "bin/build failed on a --with site:\n#{out}"
    %w[photos publications workshops].each do |collection|
      index = File.join(with_dir, '_site', collection, 'index.html')
      assert File.exist?(index), "expected /#{collection}/ index page for an empty collection"
    end
    nav = File.read(File.join(with_dir, '_site', 'index.html'), encoding: 'UTF-8')
    assert_includes nav, 'href="/photos/"'
    assert_includes nav, 'href="/workshops/"'
  end

  def test_bin_serve_boots_and_serves_http
    skip "port #{SERVE_PORT} in use" unless port_free?(SERVE_PORT)

    pid = Process.spawn(bin_env, RbConfig.ruby, File.join(@site_dir, 'bin', 'serve'),
                        %i[out err] => File::NULL)
    response = poll_http("http://127.0.0.1:#{SERVE_PORT}/", timeout: 15)
    assert response, 'bin/serve did not answer HTTP within 15s'
    assert_equal '200', response.code
    assert_includes response.body, '<title>'
  ensure
    if pid
      Process.kill('INT', pid) rescue nil
      _, status = Process.wait2(pid) rescue nil
      Process.kill('KILL', pid) if status.nil? rescue nil
    end
  end

  def test_bin_fetch_folio_reports_unconfigured_folio
    out, status = run_bin('fetch-folio')
    assert_equal 1, status.exitstatus, "expected configured-check exit 1, got:\n#{out}"
    assert_match(/not configured/, out)
  end

  def test_bin_index_requires_a_build_first
    out, status = run_bin('index')
    refute status.success?
    assert_match(/run `bin\/build` first/, out)
  end

  def test_bin_audit_only_calls_methods_the_audit_api_has
    src = File.read(File.join(@site_dir, 'bin', 'audit'), encoding: 'UTF-8')
    called = src.scan(/\baudit\.(\w+)/).flatten.uniq
    refute_empty called
    called.each do |method|
      assert Abqari::Audit.method_defined?(method),
             "bin/audit calls audit.#{method}, which Abqari::Audit doesn't define"
    end
  end

  private

  def port_free?(port)
    server = TCPServer.new('127.0.0.1', port)
    server.close
    true
  rescue Errno::EADDRINUSE, Errno::EACCES
    false
  end

  def poll_http(url, timeout:)
    uri = URI(url)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
    while Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline
      begin
        return Net::HTTP.get_response(uri)
      rescue Errno::ECONNREFUSED, Errno::ECONNRESET, EOFError
        sleep 0.25
      end
    end
    nil
  end
end

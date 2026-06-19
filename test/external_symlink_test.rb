# frozen_string_literal: true

require_relative 'test_helper'
require 'tmpdir'
require 'stringio'

# Tests for Site#external_symlink? — the guard that keeps `Dir.glob` from
# pulling files into the build via a symlink that points outside the site
# tree.
class ExternalSymlinkTest < Minitest::Test
  def setup
    @prev_root  = ENV['ABQARI_SITE_ROOT']
    @prev_allow = ENV['ABQARI_ALLOW_EXTERNAL_SYMLINKS']
    @tmpdir = Dir.mktmpdir('abqari-symlink-test')
    ENV['ABQARI_SITE_ROOT'] = @tmpdir
    @site = Abqari::Site.allocate
    @site.instance_variable_set(:@site_root, @tmpdir)
  end

  def teardown
    ENV['ABQARI_SITE_ROOT']            = @prev_root
    ENV['ABQARI_ALLOW_EXTERNAL_SYMLINKS'] = @prev_allow
    FileUtils.rm_rf(@tmpdir)
    FileUtils.rm_rf(@external) if @external && Dir.exist?(@external)
  end

  def test_regular_file_is_not_flagged
    path = File.join(@tmpdir, 'real.md')
    File.write(path, 'hello')
    refute @site.external_symlink?(path)
  end

  def test_in_tree_symlink_is_not_flagged
    target = File.join(@tmpdir, 'real.md')
    File.write(target, 'hello')
    link = File.join(@tmpdir, 'link.md')
    File.symlink(target, link)
    refute @site.external_symlink?(link)
  end

  def test_symlink_pointing_outside_site_root_is_flagged
    @external = Dir.mktmpdir('abqari-evil-source')
    secret = File.join(@external, 'secrets.md')
    File.write(secret, 'hostile content')
    link = File.join(@tmpdir, 'innocent.md')
    File.symlink(secret, link)
    assert @site.external_symlink?(link)
  end

  def test_escape_hatch_allows_external_symlink
    @external = Dir.mktmpdir('abqari-allowed-source')
    File.write(File.join(@external, 's.md'), 'x')
    link = File.join(@tmpdir, 'link.md')
    File.symlink(File.join(@external, 's.md'), link)
    ENV['ABQARI_ALLOW_EXTERNAL_SYMLINKS'] = 'true'
    refute @site.external_symlink?(link)
  end

  def test_dangling_symlink_is_skipped
    link = File.join(@tmpdir, 'broken.md')
    File.symlink(File.join(@tmpdir, 'does-not-exist.md'), link)
    # Swallow the `warn` so test output stays clean.
    capture_io { assert @site.external_symlink?(link) }
  end

  private

  # Minimal stderr capture for the dangling-symlink case. Avoids pulling in
  # stringio just for one assertion.
  def capture_io
    original = $stderr
    $stderr = StringIO.new
    yield
  ensure
    $stderr = original
  end
end

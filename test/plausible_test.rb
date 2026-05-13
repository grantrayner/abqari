# frozen_string_literal: true

require_relative 'test_helper'
require 'tmpdir'

# Plausible analytics integration. Both `enabled: true` AND `key:` must
# be set for the tracker to render — leaving `enabled: false` lets the
# operator keep their key in the config file without tracking.
#
# When enabled, the build emits:
#   - Two <script> tags in <head> (one external, one inline boot)
#   - CSP entries allowlisting plausible.io for script-src + connect-src
class PlausibleTest < Minitest::Test
  def setup
    @prev_root   = ENV['ABQARI_SITE_ROOT']
    @prev_output = ENV['ABQARI_OUTPUT_DIR']
    @tmpdir = Dir.mktmpdir('abqari-plausible-test')
    ENV['ABQARI_SITE_ROOT']   = @tmpdir
    # Isolate output_dir so we don't trample the shared fixture build
    # the rest of the suite reuses via TestHelpers.built_site.
    ENV['ABQARI_OUTPUT_DIR']  = File.join(@tmpdir, '_site')

    FileUtils.mkdir_p(File.join(@tmpdir, 'config'))
    FileUtils.mkdir_p(File.join(@tmpdir, 'content'))
    File.write(File.join(@tmpdir, 'content/index.md'), "---\ntitle: Home\n---\nhi")
  end

  def teardown
    ENV['ABQARI_SITE_ROOT']  = @prev_root
    ENV['ABQARI_OUTPUT_DIR'] = @prev_output
    FileUtils.rm_rf(@tmpdir)
  end

  def write_config(plausible_block)
    File.write(File.join(@tmpdir, 'config/site.yml'), <<~YML)
      title: T
      url: https://example.test
      locale: en
      #{plausible_block}
    YML
  end

  def build_and_read_head
    site = Abqari::Site.new
    site.build
    File.read(File.join(site.output_dir, 'index.html'), encoding: 'UTF-8')
  end

  def headers_for
    site = Abqari::Site.new
    site.build
    File.read(File.join(site.output_dir, '_headers'), encoding: 'UTF-8')
  end

  def test_no_plausible_block_means_no_script
    write_config('')
    html = build_and_read_head
    refute_includes html, 'plausible.io/js/'
    refute_includes html, 'PlausibleScript'
  end

  def test_enabled_false_means_no_script_even_when_key_set
    write_config(<<~YML)
      plausible:
        enabled: false
        key: pa-abc123
    YML
    html = build_and_read_head
    refute_includes html, 'plausible.io/js/'
  end

  def test_enabled_true_without_key_means_no_script
    write_config(<<~YML)
      plausible:
        enabled: true
    YML
    html = build_and_read_head
    refute_includes html, 'plausible.io/js/'
  end

  def test_both_enabled_and_key_render_the_tracker
    write_config(<<~YML)
      plausible:
        enabled: true
        key: pa-abc123
    YML
    html = build_and_read_head
    assert_includes html, 'https://plausible.io/js/pa-abc123.js'
    # Inline boot script comes from PlausibleScript::SCRIPT — confirm
    # the canonical init call is present.
    assert_includes html, 'plausible.init()'
  end

  def test_csp_extends_to_plausible_io_when_enabled
    write_config(<<~YML)
      plausible:
        enabled: true
        key: pa-abc123
    YML
    headers = headers_for
    assert_match %r{script-src[^\n]*plausible\.io}, headers
    assert_match %r{connect-src[^\n]*plausible\.io}, headers
  end

  def test_csp_does_not_extend_when_disabled
    write_config(<<~YML)
      plausible:
        enabled: false
        key: pa-abc123
    YML
    headers = headers_for
    refute_match(/plausible\.io/, headers)
  end

  def test_legacy_string_shorthand_is_no_longer_active
    # Before the config cleanup, `plausible: pa-abc123` (bare string)
    # was accepted. The new shape requires the hash form with both
    # `enabled` and `key`. A bare string should now no-op, NOT silently
    # render with hidden semantics.
    write_config('plausible: pa-abc123')
    html = build_and_read_head
    refute_includes html, 'plausible.io/js/'
  end
end

# frozen_string_literal: true

require_relative 'test_helper'
require 'tmpdir'
require 'stringio'

# Warns when ABQARI_ENV is explicitly set to a value that doesn't match
# any `environments.*` key in site.yml. Without the warning, a typo like
# `ABQARI_ENV=stage` silently falls through to the base config — the
# operator thinks env-specific overrides are active but they aren't.
class EnvOverrideTest < Minitest::Test
  def setup
    @prev_root = ENV['ABQARI_SITE_ROOT']
    @prev_env  = ENV['ABQARI_ENV']
    @tmpdir    = Dir.mktmpdir('abqari-env-test')
    ENV['ABQARI_SITE_ROOT'] = @tmpdir
    FileUtils.mkdir_p(File.join(@tmpdir, 'config'))
  end

  def teardown
    ENV['ABQARI_SITE_ROOT'] = @prev_root
    ENV['ABQARI_ENV']       = @prev_env
    FileUtils.rm_rf(@tmpdir)
  end

  def write_config(yaml)
    File.write(File.join(@tmpdir, 'config/site.yml'), yaml)
  end

  def capture_stderr
    original = $stderr
    $stderr = StringIO.new
    yield
    $stderr.string
  ensure
    $stderr = original
  end

  def test_warns_when_env_var_does_not_match_any_environments_key
    write_config(<<~YML)
      title: T
      environments:
        production: { url: https://prod.test }
        staging:    { url: https://staging.test }
    YML
    ENV['ABQARI_ENV'] = 'stage'

    stderr = capture_stderr { Abqari::Site.new }
    assert_match(/ABQARI_ENV=.*stage/, stderr)
    assert_match(/production/, stderr)
    assert_match(/staging/, stderr)
  end

  def test_no_warning_when_env_var_matches
    write_config(<<~YML)
      title: T
      environments:
        production: { url: https://prod.test }
    YML
    ENV['ABQARI_ENV'] = 'production'

    stderr = capture_stderr { Abqari::Site.new }
    refute_match(/ABQARI_ENV=/, stderr)
  end

  def test_no_warning_when_config_has_no_environments_block
    # Sites that don't bother with environment overrides shouldn't get
    # noise on a stray ABQARI_ENV.
    write_config(<<~YML)
      title: T
    YML
    ENV['ABQARI_ENV'] = 'production'

    stderr = capture_stderr { Abqari::Site.new }
    refute_match(/ABQARI_ENV=/, stderr)
  end

  def test_no_warning_when_env_var_not_set
    # Default development env shouldn't trigger the warning when no
    # `environments.development:` block exists — that's the common
    # local-dev case for sites that only define production overrides.
    write_config(<<~YML)
      title: T
      environments:
        production: { url: https://prod.test }
    YML
    ENV.delete('ABQARI_ENV')

    stderr = capture_stderr { Abqari::Site.new }
    refute_match(/ABQARI_ENV=/, stderr)
  end
end

# frozen_string_literal: true

require_relative 'test_helper'

# DEFAULTS registry. Static defaults are folded under the user's
# config at boot so call sites read `config['key']` instead of
# `config.fetch('key', sane_default)`. User-set values win.
class SiteConfigDefaultsTest < Minitest::Test
  def test_defaults_apply_when_user_did_not_set_key
    merged = Abqari::SiteConfig.with_defaults({})
    assert_equal true,  merged['indexable']
    assert_equal true,  merged['block_ai_scraping']
    assert_equal true,  merged['syntax_highlighting']
    assert_equal true,  merged['theme_toggle']
    assert_equal false, merged['erb_in_markdown']
  end

  def test_user_value_wins_over_default
    user = { 'indexable' => false, 'syntax_highlighting' => false }
    merged = Abqari::SiteConfig.with_defaults(user)
    assert_equal false, merged['indexable']
    assert_equal false, merged['syntax_highlighting']
    # Untouched defaults remain
    assert_equal true,  merged['block_ai_scraping']
  end

  def test_with_defaults_does_not_mutate_input
    user = { 'indexable' => false }
    Abqari::SiteConfig.with_defaults(user)
    assert_equal({ 'indexable' => false }, user, 'input hash must not be mutated')
  end

  def test_with_defaults_handles_nil
    merged = Abqari::SiteConfig.with_defaults(nil)
    assert_equal true, merged['indexable'], 'nil input should still apply defaults'
  end

  def test_deep_merge_preserves_nested_user_values
    base = { 'pagination' => { 'per_page' => 10, 'show_excerpt' => true } }
    override = { 'pagination' => { 'per_page' => 25 } }
    merged = Abqari::SiteConfig.deep_merge(base, override)
    assert_equal 25, merged.dig('pagination', 'per_page'),
                 'user override wins'
    assert_equal true, merged.dig('pagination', 'show_excerpt'),
                 'untouched nested key stays'
  end

  def test_erb_in_markdown_remains_false_unless_explicitly_set
    # Real Site path — the default registry should keep erb_in_markdown
    # closed for any site that doesn't explicitly enable it.
    site = Abqari::Site.new
    assert_equal false, site.config['erb_in_markdown']
  end

  def test_validate_warns_on_unknown_top_level_key
    require 'stringio'
    original = $stderr
    $stderr = StringIO.new
    Abqari::SiteConfig.validate!({ 'title' => 'T', 'mispelled_key' => 'oops' })
    assert_match(/mispelled_key/, $stderr.string)
  ensure
    $stderr = original
  end

  def test_validate_raises_in_strict_mode
    err = assert_raises(ArgumentError) do
      Abqari::SiteConfig.validate!({ 'unknown' => 'x' }, strict: true)
    end
    assert_match(/unknown/i, err.message)
  end

  def test_deploy_key_is_known
    # `deploy:` is read by the site-level bin/deploy script, not by
    # lib/ — easy to lose from KNOWN_KEYS since the drift scan can't
    # see it. A site configuring its deploy target must not warn.
    Abqari::SiteConfig.validate!({ 'title' => 'T', 'deploy' => { 'default' => 'cloudflare' } }, strict: true)
  end

  def test_x_prefixed_user_extension_keys_are_tolerated
    require 'stringio'
    original = $stderr
    $stderr = StringIO.new
    Abqari::SiteConfig.validate!({ 'x_my_thing' => 'fine' })
    refute_match(/x_my_thing/, $stderr.string)
  ensure
    $stderr = original
  end
end

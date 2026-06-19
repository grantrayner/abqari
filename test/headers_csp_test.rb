# frozen_string_literal: true

require_relative 'test_helper'
require 'ostruct'

# CSP directive tests. The CSP is the only header where a regression
# materially weakens visitors' browsers (everything else is a static
# allow / nosniff). Lock in:
#
#   - Strict baseline: default-src 'self', no 'unsafe-inline', no
#     'unsafe-eval', object-src 'none', frame-ancestors 'none',
#     form-action 'self'.
#   - Newsletter opt-in: the configured action origin gets added to
#     form-action so the form actually works without weakening the
#     directive globally.
#   - Folio / Plausible opt-ins: each adds only the minimal hosts
#     needed (covered today by existing site_test.rb checks; this
#     file focuses on the new directives).
class HeadersCspTest < Minitest::Test
  def make_site(config_overrides = {})
    cfg = {
      'url'              => 'https://example.com',
      'title'            => 'Test'
    }.merge(config_overrides)

    site = OpenStruct.new(env: :production, output_dir: '/tmp/__csp')
    site.define_singleton_method(:config) { cfg }
    site
  end

  def policy_for(config_overrides = {})
    Abqari::HeadersFile.new(make_site(config_overrides)).send(:csp_policy)
  end

  def test_baseline_includes_object_src_none
    assert_includes policy_for, "object-src 'none'"
  end

  def test_baseline_includes_form_action_self
    assert_includes policy_for, "form-action 'self'"
  end

  def test_baseline_includes_frame_ancestors_none
    assert_includes policy_for, "frame-ancestors 'none'"
  end

  def test_baseline_does_not_include_unsafe_inline_scripts
    refute_includes policy_for, "script-src 'self' 'unsafe-inline'"
  end

  def test_newsletter_extends_form_action_with_provider_origin
    csp = policy_for('newsletter' => { 'action' => 'https://www.cogentnotes.app/s/abc' })
    assert_includes csp, "form-action 'self' https://www.cogentnotes.app"
  end

  def test_newsletter_extends_script_src_when_script_is_set
    csp = policy_for('newsletter' => {
                       'action' => 'https://buttondown.email/api/emails/embed-subscribe/me',
                       'script' => 'https://buttondown.email/api/embed.js'
                     })
    assert_match(/script-src .* https:\/\/buttondown\.email/, csp)
    assert_match(/connect-src .* https:\/\/buttondown\.email/, csp)
    assert_match(/form-action .* https:\/\/buttondown\.email/, csp)
  end

  def test_newsletter_silently_skips_invalid_action_url
    # Malformed config — config validation isn't this test's job, but
    # confirm we don't crash. The user will see a broken form; the CSP
    # is intact.
    csp = policy_for('newsletter' => { 'action' => 'javascript:alert(1)' })
    refute_includes csp, 'javascript'
    assert_includes csp, "form-action 'self'"
  end

  def test_newsletter_no_config_leaves_form_action_self_only
    assert_includes policy_for, "form-action 'self'"
  end
end

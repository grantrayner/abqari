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

  def test_search_adds_wasm_unsafe_eval
    # Pagefind compiles a WebAssembly module; WASM compilation is
    # governed by script-src regardless of origin.
    assert_includes policy_for('search' => true), "'wasm-unsafe-eval'"
  end

  def test_no_search_no_wasm_unsafe_eval
    refute_includes policy_for('search' => false), "'wasm-unsafe-eval'"
    refute_includes policy_for, "'wasm-unsafe-eval'"
  end

  def test_speculation_rules_on_by_default_adds_keyword
    # The inline <script type="speculationrules"> block needs the
    # 'inline-speculation-rules' script-src keyword.
    assert_includes policy_for, "'inline-speculation-rules'"
  end

  def test_speculation_rules_disabled_omits_keyword
    csp = policy_for('speculation_rules' => { 'enabled' => false })
    refute_includes csp, "'inline-speculation-rules'"
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

  # --- Folio cover host ----------------------------------------------

  def folio_config(extra = {})
    { 'folio' => { 'base_url' => 'https://foliobooks.app',
                   'author_slug' => 'me' }.merge(extra) }
  end

  def test_folio_extends_img_src_with_default_covers_host
    csp = policy_for(folio_config)
    assert_match(%r{img-src [^;]*https://covers\.foliobooks\.app}, csp)
  end

  def test_folio_covers_host_is_configurable
    csp = policy_for(folio_config('covers_host' => 'https://covers.my-folio.example'))
    assert_match(%r{img-src [^;]*https://covers\.my-folio\.example}, csp)
    refute_includes csp, 'covers.foliobooks.app'
  end

  def test_folio_covers_host_normalises_to_origin
    # A full URL (path and all) still lands in the CSP as a bare origin.
    csp = policy_for(folio_config('covers_host' => 'https://covers.my-folio.example/some/path'))
    assert_match(%r{img-src [^;]*https://covers\.my-folio\.example( |;|\z)}, csp)
    refute_includes csp, '/some/path'
  end

  def test_no_folio_no_covers_host
    refute_includes policy_for, 'covers.foliobooks.app'
  end

  # --- media: off-origin audio / video --------------------------------
  #
  # Colocated bundle audio needs nothing: with no `media-src` declared
  # it inherits `default-src 'self'`. The directive appears only when a
  # host is configured, so existing sites see no header change.

  def test_no_media_config_declares_no_media_src
    refute_includes policy_for, 'media-src'
  end

  def test_media_host_adds_media_src_and_keeps_self
    csp = policy_for('media' => { 'host' => 'https://media.example.com' })
    assert_includes csp, "media-src 'self' https://media.example.com"
  end

  def test_media_host_accepts_a_list
    csp = policy_for('media' => {
                       'host' => ['https://audio.example.com', 'https://video.example.com']
                     })
    assert_match(%r{media-src 'self' https://audio\.example\.com https://video\.example\.com}, csp)
  end

  def test_media_host_normalises_to_origin
    csp = policy_for('media' => { 'host' => 'https://media.example.com/lessons/01.mp3' })
    assert_includes csp, "media-src 'self' https://media.example.com"
    refute_includes csp, '/lessons/01.mp3'
  end

  # --- csp: operator-declared origins ---------------------------------
  #
  # Additive by contract: the whole reason the key exists is that
  # `headers:` replaces the computed policy and silently drops the
  # pinned inline-script hashes with it.

  def test_csp_extension_appends_to_an_existing_directive
    csp = policy_for('csp' => { 'img-src' => ['https://cdn.example.com'] })
    assert_includes csp, "img-src 'self' data: https://cdn.example.com"
  end

  def test_csp_extension_creates_a_directive_seeded_with_self
    csp = policy_for('csp' => { 'media-src' => ['https://media.example.com'] })
    assert_includes csp, "media-src 'self' https://media.example.com"
  end

  def test_csp_extension_accepts_a_bare_string
    csp = policy_for('csp' => { 'connect-src' => 'https://api.example.com' })
    assert_includes csp, "connect-src 'self' https://api.example.com"
  end

  def test_csp_extension_preserves_pinned_script_hashes
    csp = policy_for('csp' => { 'script-src' => ['https://cdn.example.com'] })
    assert_includes csp, "'#{Abqari::ThemeBootstrap::SHA256}'"
    assert_includes csp, 'https://cdn.example.com'
  end

  def test_csp_extension_preserves_feature_derived_origins
    csp = policy_for(
      'plausible' => { 'enabled' => true, 'key' => 'example.com' },
      'csp'       => { 'connect-src' => ['https://api.example.com'] }
    )
    assert_includes csp, 'https://plausible.io'
    assert_includes csp, 'https://api.example.com'
  end

  def test_csp_rejects_non_extendable_hardening_directives
    %w[object-src frame-ancestors base-uri default-src].each do |directive|
      error = assert_raises(ArgumentError) do
        policy_for('csp' => { directive => ['https://cdn.example.com'] })
      end
      assert_match(/not an extendable directive/, error.message)
      assert_match(/headers:/, error.message, 'error should point at the real escape hatch')
    end
  end

  def test_csp_rejects_an_unknown_directive
    error = assert_raises(ArgumentError) do
      policy_for('csp' => { 'imgsrc' => ['https://cdn.example.com'] })
    end
    assert_match(/"imgsrc"/, error.message)
  end

  def test_csp_rejects_wildcards_and_keywords_and_non_http_schemes
    ['*', "'unsafe-inline'", "'unsafe-eval'", 'data:', 'blob:', "'self'",
     'javascript:alert(1)', 'cdn.example.com'].each do |value|
      error = assert_raises(ArgumentError, "#{value.inspect} must be rejected") do
        policy_for('csp' => { 'img-src' => [value] })
      end
      assert_match(/is not an http\(s\) origin/, error.message)
    end
  end

  def test_csp_rejection_fails_the_build_rather_than_shipping_a_stale_policy
    # A malformed CSP fails open in the browser, so a silent skip would
    # ship a policy the operator believes is enforced. `#write` must
    # propagate rather than swallow.
    site = make_site('csp' => { 'img-src' => ['*'] })
    assert_raises(ArgumentError) { Abqari::HeadersFile.new(site).send(:build) }
  end
end

# frozen_string_literal: true

require_relative '../test_helper'

# Bridgy — head-link generator for IndieWeb discovery (webmention.io
# endpoint + Bridgy Fed actor advertisement). Pure markup, no I/O —
# these tests exercise the generator directly with a stub site so we
# can verify each config combination without booting the fixture site.
class BridgyTest < Minitest::Test
  Bridgy = Abqari::Indieweb::Bridgy

  def stub_site(indieweb:)
    # Explicit braces around the hash so Ruby doesn't interpret
    # `'indieweb' => indieweb` as keyword arguments to Struct#new.
    Struct.new(:config).new({ 'indieweb' => indieweb })
  end

  def test_returns_empty_when_indieweb_disabled
    site = stub_site(indieweb: { 'enabled' => false, 'domain' => 'example.com' })
    assert_empty Bridgy.head_links(site)
  end

  def test_returns_empty_when_no_domain_set
    site = stub_site(indieweb: { 'enabled' => true })
    assert_empty Bridgy.head_links(site)
  end

  def test_emits_webmention_endpoint_when_enabled
    site = stub_site(indieweb: { 'enabled' => true, 'domain' => 'example.com' })
    links = Bridgy.head_links(site)
    assert links.any? { |l| l.include?('rel="webmention"') }, "expected webmention link tag"
    assert links.any? { |l| l.include?('webmention.io/example.com/webmention') }
  end

  def test_emits_pingback_alongside_webmention
    site = stub_site(indieweb: { 'enabled' => true, 'domain' => 'example.com' })
    links = Bridgy.head_links(site)
    # Pingback exists for legacy interop — webmention.io accepts both.
    assert links.any? { |l| l.include?('rel="pingback"') }
  end

  def test_bridgy_fed_links_only_emit_when_opted_in
    off = stub_site(indieweb: { 'enabled' => true, 'domain' => 'example.com' })
    assert off.config['indieweb']['bridgy_fed'].nil?
    refute Bridgy.head_links(off).any? { |l| l.include?('fed.brid.gy') },
           'Bridgy Fed links must be opt-in'

    on = stub_site(indieweb: { 'enabled' => true, 'domain' => 'example.com',
                                'bridgy_fed' => true })
    links = Bridgy.head_links(on)
    assert links.any? { |l| l.include?('fed.brid.gy/r/https://example.com/') },
           "expected Bridgy Fed actor URL with site domain"
    assert links.any? { |l| l.include?('application/activity+json') },
           'expected ActivityPub alternate link'
  end

  def test_endpoint_helper_returns_nil_without_domain
    site = stub_site(indieweb: {})
    assert_nil Abqari::Indieweb.webmention_endpoint(site)
  end
end

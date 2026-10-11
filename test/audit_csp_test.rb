# frozen_string_literal: true

require_relative 'test_helper'
require 'tmpdir'
require 'digest'
require 'base64'

# Audit::Csp — inline code the built `_headers` CSP would block.
#
# The generated policy has `style-src 'self'` and pins scripts by hash,
# so a template that adds `style="…"`, an `onclick=`, or an unhashed
# `<script>` renders fine everywhere the CSP isn't enforced (the dev
# server, local builds) and breaks only on the host. A site shipped 52
# inline style attributes this way, and the engine's own
# speculation-rules block went out in 1.1.x allowed by nothing but a
# keyword Chrome ignores once hashes are present.
class AuditCspTest < Minitest::Test
  BASE_CSP = "default-src 'self'; style-src 'self'; script-src 'self'"

  def setup
    @tmpdir   = Dir.mktmpdir('abqari-audit-csp')
    @findings = []
    site = Object.new
    dir = @tmpdir
    site.define_singleton_method(:output_dir) { dir }
    site.define_singleton_method(:config) { { 'url' => 'https://example.test' } }
    @site = site
  end

  def teardown
    FileUtils.rm_rf(@tmpdir)
  end

  # --- style attributes ---------------------------------------------

  def test_style_attribute_under_strict_style_src_is_an_error
    headers(BASE_CSP)
    page('about/index.html', '<div style="--ratio: 3 / 2">a</div><p style="margin:0">b</p>')

    finding = run_audit.first
    assert_equal 'error', finding[:severity]
    assert_equal 'security', finding[:category]
    assert_equal '/about/', finding[:location]
    assert_match(/2 style attributes blocked by the CSP \(style-src 'self'\)/, finding[:message])
    assert_includes finding[:message], 'style="--ratio: 3 / 2"'
  end

  def test_unsafe_inline_allows_style_attributes
    headers("default-src 'self'; style-src 'self' 'unsafe-inline'")
    page('index.html', '<div style="color:red">a</div>')

    assert_empty run_audit
  end

  def test_a_hash_switches_unsafe_inline_off
    headers("default-src 'self'; style-src 'self' 'unsafe-inline' #{sha('h1{}')}")
    page('index.html', '<div style="color:red">a</div>')

    assert_equal 1, run_audit.size
  end

  def test_attribute_hashes_need_unsafe_hashes
    headers("default-src 'self'; style-src 'self' #{sha('color:red')}")
    page('index.html', '<div style="color:red">a</div>')
    assert_equal 1, run_audit.size

    @findings.clear
    headers("default-src 'self'; style-src 'self' 'unsafe-hashes' #{sha('color:red')}")
    assert_empty run_audit
  end

  def test_style_src_attr_is_more_specific_than_style_src
    headers("default-src 'self'; style-src 'self'; style-src-attr 'unsafe-inline'")
    page('index.html', '<div style="color:red">a</div>')

    assert_empty run_audit
  end

  def test_default_src_governs_when_style_src_is_absent
    headers("default-src 'self'")
    page('index.html', '<div style="color:red">a</div>')

    assert_match(/\(default-src 'self'\)/, run_audit.first[:message])
  end

  def test_markup_inside_a_script_string_is_not_an_attribute
    js = %(document.body.insertAdjacentHTML('beforeend', '<b style="x">'))
    headers("default-src 'self'; style-src 'self'; script-src 'self' #{sha(js)}")
    page('index.html', "<script>#{js}</script>")

    assert_empty run_audit
  end

  # --- style blocks, handlers ----------------------------------------

  def test_style_block_needs_its_hash
    headers(BASE_CSP)
    page('index.html', '<style>h1{color:red}</style>')
    assert_match(/1 <style> block blocked/, run_audit.first[:message])

    @findings.clear
    headers("#{BASE_CSP.sub("style-src 'self'", "style-src 'self' #{sha('h1{color:red}')}")}")
    assert_empty run_audit
  end

  def test_event_handler_is_an_error
    headers(BASE_CSP)
    page('index.html', '<button onclick="go()">Go</button>')

    assert_match(/1 inline event handler blocked by the CSP \(script-src 'self'\)/, run_audit.first[:message])
  end

  # --- scripts ----------------------------------------------------------

  def test_inline_script_is_allowed_by_its_hash_and_only_by_its_hash
    headers("default-src 'self'; script-src 'self' #{sha('ok()')}")
    page('index.html', '<script>ok()</script><script>other()</script>')

    findings = run_audit
    assert_equal 1, findings.size
    assert_match(/1 inline <script> blocked.*`other\(\)`/, findings.first[:message])
  end

  # The 1.1.x bug: hashes for the other inline scripts, the keyword for
  # the rules block, and Chrome blocking it anyway.
  def test_speculation_rules_keyword_is_not_enough_once_hashes_are_present
    rules = '{ "prerender": [] }'
    page('index.html', %(<script type="speculationrules">#{rules}</script>))

    headers("default-src 'self'; script-src 'self' #{sha('x')} 'inline-speculation-rules'")
    assert_equal 1, run_audit.size

    @findings.clear
    headers("default-src 'self'; script-src 'self' 'inline-speculation-rules'")
    assert_empty run_audit, 'the keyword alone is honoured when nothing switches inline handling to hashes'

    @findings.clear
    headers("default-src 'self'; script-src 'self' #{sha('x')} #{sha(rules)} 'inline-speculation-rules'")
    assert_empty run_audit
  end

  def test_data_blocks_and_external_scripts_are_not_inline_code
    headers(BASE_CSP)
    page('index.html', '<script type="application/ld+json">{"@type":"Article"}</script>' \
                       '<script src="/assets/app.js"></script>')

    assert_empty run_audit
  end

  # --- which policy applies -----------------------------------------

  def test_no_headers_file_or_no_csp_means_nothing_to_check
    page('index.html', '<div style="color:red">a</div>')
    assert_empty run_audit

    File.write(File.join(@tmpdir, '_headers'), "/*\n  X-Content-Type-Options: nosniff\n")
    assert_empty run_audit
  end

  def test_policy_applies_by_path
    File.write(File.join(@tmpdir, '_headers'), "/blog/*\n  Content-Security-Policy: #{BASE_CSP}\n")
    page('about/index.html', '<div style="color:red">a</div>')
    page('blog/post/index.html', '<div style="color:red">a</div>')

    assert_equal ['/blog/post/'], run_audit.map { |f| f[:location] }
  end

  # The engine's own pages must pass the engine's own policy.
  def test_the_engine_fixture_passes_its_own_csp
    findings = []
    Abqari::Audit::Csp.new(TestHelpers.built_site, findings).run

    assert_empty findings, findings.map { |f| "#{f[:location]}: #{f[:message]}" }.join("\n")
  end

  private

  def headers(csp)
    File.write(File.join(@tmpdir, '_headers'), "/*\n  Content-Security-Policy: #{csp}\n")
  end

  def page(rel, body)
    path = File.join(@tmpdir, rel)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, "<!doctype html><html><head><title>t</title></head><body>#{body}</body></html>")
  end

  def sha(content)
    "'sha256-#{Base64.strict_encode64(Digest::SHA256.digest(content))}'"
  end

  def run_audit
    Abqari::Audit::Csp.new(@site, @findings).run
    @findings
  end
end

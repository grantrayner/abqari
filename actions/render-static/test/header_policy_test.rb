# frozen_string_literal: true
require 'minitest/autorun'
require 'tmpdir'
require_relative '../header_policy'

class HeaderPolicyTest < Minitest::Test
  def headers
    { 'X-Content-Type-Options' => 'nosniff', 'Referrer-Policy' => 'strict-origin-when-cross-origin',
      'Permissions-Policy' => 'camera=(), microphone=(), geolocation=()',
      'Strict-Transport-Security' => 'max-age=31536000; includeSubDomains',
      'Content-Security-Policy' => "default-src 'self'; script-src 'self' 'sha256-current'" }.map { |name, value| { 'path' => '/*', 'name' => name, 'value' => value } }
  end
  def with_site
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        Dir.mkdir('_site'); File.write('_site/index.html', '<html><body>Example</body></html>')
        File.write('render.yaml', YAML.dump({ 'services' => [{ 'name' => 'site', 'headers' => headers }] }))
        yield({ 'service_name' => 'site', 'publish_path' => '_site', 'blueprint' => 'render.yaml' })
      end
    end
  end
  def test_missing_global_security_rule_is_rejected
    assert_raises(HeaderPolicy::Error) { HeaderPolicy.validate_headers(headers.reject { |r| r['name'] == 'Content-Security-Policy' }) }
  end
  def test_duplicate_rules_are_rejected_case_insensitively
    assert_raises(HeaderPolicy::Error) { HeaderPolicy.validate_headers(headers + [headers.first.merge('name' => 'x-content-type-options')]) }
  end
  def test_newlines_cannot_be_injected_into_a_header
    assert_raises(HeaderPolicy::Error) { HeaderPolicy.validate_headers(headers.map { |r| r.merge('value' => "#{r['value']}\r\nX-Injected: yes") }) }
  end
  def test_blueprint_must_identify_the_configured_service
    with_site { |config| assert_raises(HeaderPolicy::Error) { HeaderPolicy.plan(config.merge('service_name' => 'another-site')) } }
  end
  def test_generated_policy_replaces_stale_hashes_and_retains_extra_blueprint_rules
    with_site do |config|
      doc=YAML.load_file('render.yaml');doc['services'][0]['headers'] << { 'path' => '/*', 'name' => 'X-Frame-Options', 'value' => 'DENY' };File.write('render.yaml',YAML.dump(doc))
      File.write('_site/_headers', "/*\n  Content-Security-Policy: default-src 'self'; script-src 'self' 'sha256-generated'\n")
      result=HeaderPolicy.plan(config.merge('generated_headers' => '_site/_headers'))
      assert_includes result['desired'].find { |r| r['name'] == 'Content-Security-Policy' }['value'], 'sha256-generated'
      refute_includes result['desired'].find { |r| r['name'] == 'Content-Security-Policy' }['value'], 'sha256-current'
      assert_equal 'DENY',result['desired'].find { |r| r['name'] == 'X-Frame-Options' }['value']
      assert_equal false,result['render_mutations']
    end
  end
  def test_cache_probes_find_real_assets_and_report_empty_rule_paths
    with_site do |config|
      Dir.mkdir('_site/assets');Dir.mkdir('_site/assets/maplibre');File.write('_site/assets/maplibre/maplibre-gl.css','body {}')
      doc=YAML.load_file('render.yaml');doc['services'][0]['headers'] += [
        { 'path' => '/assets/maplibre/*', 'name' => 'Cache-Control', 'value' => 'public, max-age=31536000, immutable' },
        { 'path' => '/assets/pdf/*', 'name' => 'Cache-Control', 'value' => 'public, max-age=86400' }];File.write('render.yaml',YAML.dump(doc))
      result=HeaderPolicy.plan(config)
      assert_includes result['probes'], { 'pattern' => '/assets/maplibre/*', 'url' => '/assets/maplibre/maplibre-gl.css' }
      assert_equal ['/assets/pdf/*'],result['unprobed_paths']
    end
  end
  def test_wildcards_are_escaped_and_do_not_match_other_directories
    assert HeaderPolicy.matches_path?('/assets/*','/assets/fonts/font.woff2')
    refute HeaderPolicy.matches_path?('/assets/*','/lessons/example/')
    assert HeaderPolicy.matches_path?('/*.css','/app.css')
    refute HeaderPolicy.matches_path?('/*.css','/assets/app.css')
    refute HeaderPolicy.matches_path?('/news.xml','/news+xml')
  end
  def test_probe_selection_does_not_follow_symlinks_outside_the_build
    with_site do |config|
      File.symlink('../render.yaml','_site/leaked.yaml')
      doc=YAML.load_file('render.yaml');doc['services'][0]['headers'] << { 'path' => '/*.yaml', 'name' => 'Cache-Control', 'value' => 'no-store' };File.write('render.yaml',YAML.dump(doc))
      assert_includes HeaderPolicy.plan(config)['unprobed_paths'],'/*.yaml'
    end
  end
end

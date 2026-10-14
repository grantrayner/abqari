# frozen_string_literal: true

require 'minitest/autorun'
require 'minitest/mock'
require 'tmpdir'
require_relative '../render_static'

class RenderStaticTest < Minitest::Test
  def policy(hash)
    "default-src 'self'; script-src 'self' '#{hash}'; object-src 'none'; frame-ancestors 'none'; form-action 'self'; base-uri 'self'"
  end

  def headers(hash = 'sha256-old')
    { 'X-Content-Type-Options' => 'nosniff', 'Referrer-Policy' => 'strict-origin-when-cross-origin',
      'Permissions-Policy' => 'camera=(), microphone=(), geolocation=()',
      'Strict-Transport-Security' => 'max-age=31536000; includeSubDomains',
      'Content-Security-Policy' => policy(hash) }.map { |name, value| { 'path' => '/*', 'name' => name, 'value' => value } }
  end

  class FakeApi
    attr_accessor :current_headers, :repo, :live_commit, :failed, :newer_release, :publish_path
    attr_reader :writes, :gets
    def initialize(headers)
      @current_headers = headers; @writes = []; @gets = []; @repo = 'https://github.com/owner/site'
      @live_commit = 'previous'; @failed = false; @newer_release = false; @publish_path = '_site'
    end
    def headers(_id) = @current_headers
    def replace_headers(id, headers)
      @writes << [:headers, id, headers]
      @current_headers = headers
    end
    def list(_path, _wrapper)
      [{ 'name' => 'example.com', 'verificationStatus' => 'verified' }]
    end
    def deploys(_id)
      [{ 'id' => 'live', 'status' => 'live', 'commit' => { 'id' => @newer_release ? 'someone-else' : @live_commit } }]
    end
    def request(method, path, body = nil)
      @gets << path if method == :get
      if method == :post
        @writes << [:deploy, body]
        @pending_commit = body.fetch('commitId')
        return { 'id' => 'new', 'status' => 'build_in_progress' }
      end
      if path.include?('/deploys/')
        if @failed
          return { 'id' => 'new', 'status' => 'build_failed' }
        end
        @live_commit = @pending_commit
        return { 'id' => 'new', 'status' => 'live', 'commit' => { 'id' => @live_commit } }
      end
      { 'id' => 'srv-test', 'name' => 'site', 'type' => 'static_site', 'branch' => 'main', 'repo' => @repo,
        'serviceDetails' => { 'url' => 'https://site.onrender.com', 'publishPath' => @publish_path } }
    end
  end

  def with_release
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        File.write('render.yaml', YAML.dump({ 'services' => [{ 'name' => 'site', 'headers' => headers('sha256-new') }] }))
        config = { 'service_id' => 'srv-test', 'service_name' => 'site', 'branch' => 'main',
                   'origin' => 'https://example.com', 'publish_path' => '_site', 'blueprint' => 'render.yaml' }
        api = FakeApi.new(headers)
        release = RenderStatic::Release.new(config, api: api, commit: 'target', repository: 'owner/site', sleeper: ->(_) {})
        yield release, api, config
      end
    end
  end

  def test_hash_rollover_keeps_both_versions_valid
    value = RenderStatic.transition_csp(policy('sha256-old'), policy('sha256-new'))
    assert_includes value, "'sha256-old'"
    assert_includes value, "'sha256-new'"
    assert_includes value, "object-src 'none'"
  end

  def test_unsafe_inline_to_hash_cannot_silently_block_old_pages
    assert_raises(RenderStatic::Error) do
      RenderStatic.transition_csp("default-src 'self'; script-src 'self' 'unsafe-inline'", policy('sha256-new'))
    end
  end

  def test_new_directive_respects_old_default_fallback
    value = RenderStatic.transition_csp("default-src 'self'", "default-src 'self'; img-src 'self' https://cdn.example.com")
    assert_includes value, "img-src 'self' https://cdn.example.com"
  end

  def test_boolean_csp_directives_are_not_given_invalid_sources
    value = RenderStatic.transition_csp(policy('sha256-old'), policy('sha256-new') + '; upgrade-insecure-requests')
    assert value.end_with?('; upgrade-insecure-requests')
  end

  def test_duplicate_rules_are_rejected_case_insensitively
    rows = headers + [headers.first.merge('name' => 'x-content-type-options')]
    assert_raises(RenderStatic::Error) { RenderStatic.validate_headers(rows) }
  end

  def test_generated_policy_overlays_old_blueprint_hashes_and_keeps_extra_rule
    with_release do |_release, _api, config|
      document = YAML.load_file('render.yaml')
      document['services'][0]['headers'] << { 'path' => '/*', 'name' => 'X-Frame-Options', 'value' => 'DENY' }
      File.write('render.yaml', YAML.dump(document))
      File.write('_headers', "/*\n  Content-Security-Policy: #{policy('sha256-generated')}\n")
      config['generated_headers'] = '_headers'
      desired = RenderStatic.desired_headers(config)
      assert_includes desired.find { |r| r['name'] == 'Content-Security-Policy' }['value'], 'sha256-generated'
      refute_includes desired.find { |r| r['name'] == 'Content-Security-Policy' }['value'], 'sha256-new'
      assert_equal 'DENY', desired.find { |r| r['name'] == 'X-Frame-Options' }['value']
    end
  end

  def test_wrong_repository_cannot_modify_a_service
    with_release do |release, api, _config|
      api.repo = 'https://github.com/someone/else'
      assert_raises(RenderStatic::Error) { release.prepare }
      assert_empty api.writes
    end
  end

  def test_wrong_publish_directory_is_rejected
    with_release do |release, api, _config|
      api.publish_path = 'another-output'
      assert_raises(RenderStatic::Error) { release.prepare }
      assert_empty api.writes
    end
  end

  def test_new_deploy_uses_the_exact_built_commit_and_final_headers
    with_release do |release, api, _config|
      plan = release.prepare
      release.deploy(plan)
      assert_equal 'target', api.live_commit
      assert_equal RenderStatic.normalized(plan['desired']), RenderStatic.normalized(api.current_headers)
      assert_equal 'target', api.writes.find { |w| w.first == :deploy }[1]['commitId']
      assert File.exist?('deployment-evidence/sync.json')
    end
  end

  def test_failed_deploy_restores_the_previous_headers
    with_release do |release, api, _config|
      plan = release.prepare
      api.failed = true
      assert_raises(RenderStatic::Error) { release.deploy(plan) }
      assert_equal RenderStatic.normalized(plan['before']), RenderStatic.normalized(api.current_headers)
      assert_equal 'previous', api.live_commit
    end
  end

  def test_header_edits_during_preflight_are_not_overwritten
    with_release do |release, api, _config|
      plan = release.prepare
      api.current_headers = headers('sha256-operator-change')
      assert_raises(RenderStatic::Error) { release.deploy(plan) }
      assert_empty api.writes
      assert_includes api.current_headers.last['value'], 'operator-change'
    end
  end

  def test_invalid_plan_is_rejected_without_recovery_writes
    with_release do |release, api, _config|
      plan = release.prepare.merge('repository' => 'someone/else')
      assert_raises(RenderStatic::Error) { release.deploy(plan) }
      assert_empty api.writes
    end
  end

  def test_checkout_failure_recovery_restores_previous_commit_and_headers
    with_release do |release, api, _config|
      plan = release.prepare
      release.deploy(plan)
      release.rollback(plan)
      assert_equal 'previous', api.live_commit
      assert_equal RenderStatic.normalized(plan['before']), RenderStatic.normalized(api.current_headers)
      assert File.exist?('deployment-evidence/rollback.json')
    end
  end

  def test_recovery_refuses_to_replace_a_newer_live_release
    with_release do |release, api, _config|
      plan = release.prepare
      release.deploy(plan)
      count = api.writes.length
      api.newer_release = true
      assert_raises(RenderStatic::Error) { release.rollback(plan) }
      assert_equal count, api.writes.length
    end
  end

  def test_singular_header_wrapper_and_pagination_are_parsed
    api = RenderStatic::Api.new('example-key')
    responses = [Array.new(100) { |i| { 'header' => { 'path' => "/#{i}", 'name' => 'X-Test', 'value' => 'ok' }, 'cursor' => 'next' } },
                 [{ 'header' => { 'path' => '/last', 'name' => 'X-Test', 'value' => 'ok' } }]]
    calls = []
    api.define_singleton_method(:request) do |_method, path, _body = nil|
      calls << path
      responses.shift
    end
    result = api.headers('srv-test')
    assert_equal 101, result.length
    assert_includes calls.last, 'cursor=next'
    assert_equal '/last', result.last['path']
  end

  def test_bad_api_wrapper_fails_instead_of_becoming_empty_rules
    api = RenderStatic::Api.new('example-key')
    invalid = [{ 'headers' => headers.first }]
    api.define_singleton_method(:request) { |*_args| invalid }
    assert_raises(RenderStatic::Error) { api.headers('srv-test') }
  end

  def test_transport_parses_response_and_retries_rate_limit_without_leaking_key
    api = RenderStatic::Api.new('secret-example')
    retry_response = Net::HTTPTooManyRequests.new('1.1', '429', 'Slow down')
    success = Net::HTTPOK.new('1.1', '200', 'OK')
    success.define_singleton_method(:body) { '{"status":"live"}' }
    responses = [retry_response, success]
    requests = []
    http = Object.new
    %i[use_ssl= open_timeout= read_timeout=].each { |name| http.define_singleton_method(name) { |_value| } }
    http.define_singleton_method(:request) { |request| requests << request; responses.shift }
    api.define_singleton_method(:sleep) { |_seconds| }
    Net::HTTP.stub(:new, http) do
      assert_equal({ 'status' => 'live' }, api.request(:get, '/services/srv-test'))
    end
    assert_equal 2, requests.length
    assert_equal 'Bearer secret-example', requests.last['Authorization']
  end
end

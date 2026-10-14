# frozen_string_literal: true

require 'date'
require 'json'
require 'net/http'
require 'open3'
require 'pathname'
require 'time'
require 'uri'
require 'yaml'

module RenderStatic
  class Error < StandardError; end
  EVIDENCE = 'deployment-evidence'

  def self.normalized(rows)
    rows.map { |r| [r.fetch('path'), r.fetch('name').downcase, r.fetch('value').strip] }.sort
  end

  def self.validate_headers(rows)
    raise Error, 'No configured headers' if rows.empty?
    seen = {}
    rows.each do |row|
      raise Error, 'Invalid header rule' unless %w[path name value].all? { |k| row[k].is_a?(String) && !row[k].empty? && !row[k].match?(/[\r\n]/) }
      raise Error, 'Header paths must be relative to the site' unless row['path'].start_with?('/')
      key = [row['path'], row['name'].downcase]
      raise Error, "Duplicate header rule: #{key.join(' ')}" if seen[key]
      seen[key] = true
    end
    required = %w[X-Content-Type-Options Referrer-Policy Permissions-Policy Strict-Transport-Security Content-Security-Policy]
    required.each do |name|
      raise Error, "Missing global #{name}" unless rows.any? { |r| r['path'] == '/*' && r['name'].casecmp?(name) }
    end
    rows
  end

  def self.generated_headers(path)
    rules = []; current = nil
    File.foreach(path) do |line|
      next if line.strip.empty? || line.lstrip.start_with?('#')
      if line.match?(/\A\S/)
        current = line.strip
      else
        name, value = line.strip.split(/:\s*/, 2)
        raise Error, 'Malformed generated _headers file' unless current && value
        rules << { 'path' => current, 'name' => name, 'value' => value }
      end
    end
    rules
  end

  def self.desired_headers(config)
    rules = []
    if config['blueprint']
      document = YAML.safe_load(File.read(config['blueprint']), permitted_classes: [Date, Time], aliases: true)
      services = document.fetch('services')
      service = services.find { |s| s['name'] == config.fetch('service_name') }
      raise Error, 'render.yaml does not name the intended Render service' unless service
      rules = Array(service['headers']).map { |r| r.slice('path', 'name', 'value').transform_values(&:to_s) }
    end
    if config['generated_headers']
      raise Error, 'Build output is missing its generated _headers file' unless File.file?(config['generated_headers'])
      # Site config + the bundled engine determine Abqari's hashes and
      # feature origins. The Blueprint may add rules such as X-Frame-Options.
      by_key = rules.to_h { |r| [[r['path'], r['name'].downcase], r] }
      generated_headers(config['generated_headers']).each { |r| by_key[[r['path'], r['name'].downcase]] = r }
      rules = by_key.values
    end
    validate_headers(rules)
  end

  def self.csp(value)
    value.split(';').filter_map do |part|
      tokens = part.split
      [tokens.shift, tokens] unless tokens.empty?
    end.to_h
  end

  def self.effective(policy, directive)
    return policy[directive] if policy.key?(directive)
    return effective(policy, 'script-src') if directive.start_with?('script-src-')
    return effective(policy, 'style-src') if directive.start_with?('style-src-')
    return policy['child-src'] || policy['default-src'] || ['*'] if directive == 'frame-src'
    return ['*'] if %w[frame-ancestors form-action base-uri].include?(directive)
    policy['default-src'] || ['*']
  end

  def self.transition_csp(old_value, new_value)
    old_policy = csp(old_value); new_policy = csp(new_value)
    %w[script-src script-src-elem script-src-attr].each do |directive|
      before = effective(old_policy, directive); after = effective(new_policy, directive)
      has_hash = ->(tokens) { tokens.any? { |t| t.match?(/\A'(?:sha(?:256|384|512)-|nonce-)/) } }
      inline = ->(tokens) { tokens.include?("'unsafe-inline'") && !has_hash.call(tokens) }
      if (inline.call(before) && has_hash.call(after)) || (inline.call(after) && has_hash.call(before))
        raise Error, 'Changing between unsafe-inline and hashed scripts requires a staged template migration; no deployment started'
      end
    end
    (old_policy.keys | new_policy.keys).map do |directive|
      next directive if %w[upgrade-insecure-requests block-all-mixed-content].include?(directive)
      tokens = effective(old_policy, directive) | effective(new_policy, directive)
      tokens.delete("'none'") if tokens.length > 1
      "#{directive} #{tokens.join(' ')}"
    end.join('; ')
  end

  def self.transition_headers(before, desired)
    before.map do |rule|
      replacement = desired.find { |r| r['path'] == rule['path'] && r['name'].casecmp?(rule['name']) }
      if replacement && rule['name'].casecmp?('Content-Security-Policy') && rule['value'] != replacement['value']
        rule.merge('value' => transition_csp(rule['value'], replacement['value']))
      else
        rule.dup
      end
    end
  end

  class Api
    def initialize(key)
      raise Error, 'RENDER_API_KEY secret is not configured' if key.to_s.empty?
      @key = key
    end

    def request(method, path, body = nil)
      uri = URI("https://api.render.com/v1#{path}")
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true; http.open_timeout = 15; http.read_timeout = 30
      klass = { get: Net::HTTP::Get, put: Net::HTTP::Put, post: Net::HTTP::Post }.fetch(method)
      request = klass.new(uri)
      request['Authorization'] = "Bearer #{@key}"
      request['Accept'] = 'application/json'
      if body
        request['Content-Type'] = 'application/json'
        request.body = JSON.generate(body)
      end
      attempts = 0
      response = nil
      loop do
        response = http.request(request)
        retryable = response.code == '429' || (method != :post && %w[500 502 503 504].include?(response.code))
        if retryable && attempts < 3
          attempts += 1
          sleep [[response['Retry-After'].to_i, attempts * 2].max, 30].min
          next
        end
        break
      end
      raise Error, "Render API #{method.to_s.upcase} #{path.split('?').first}: HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)
      response.body.to_s.empty? ? nil : JSON.parse(response.body)
    end

    def list(path, wrapper)
      all = []; cursor = nil
      loop do
        separator = path.include?('?') ? '&' : '?'
        page = request(:get, "#{path}#{separator}limit=100#{cursor ? "&cursor=#{URI.encode_www_form_component(cursor)}" : ''}")
        raise Error, 'Unexpected Render list response' unless page.is_a?(Array)
        page.each do |row|
          object = row[wrapper]
          raise Error, "Missing Render #{wrapper} response wrapper" unless object.is_a?(Hash)
          all << object
        end
        break if page.length < 100
        next_cursor = page.last['cursor']
        raise Error, 'Invalid Render pagination cursor' if next_cursor.to_s.empty? || next_cursor == cursor
        cursor = next_cursor
      end
      all
    end

    def headers(id)
      list("/services/#{id}/headers", 'header').map { |r| r.slice('path', 'name', 'value') }
    end

    def replace_headers(id, rules)
      request(:put, "/services/#{id}/headers", rules)
      raise Error, 'Render header readback differs from the intended policy' unless RenderStatic.normalized(headers(id)) == RenderStatic.normalized(rules)
    end

    def deploys(id)
      page = request(:get, "/services/#{id}/deploys?limit=100")
      raise Error, 'Unexpected Render deploy response' unless page.is_a?(Array)
      page.map { |row| row.fetch('deploy') }
    end
  end

  class Release
    def initialize(config, api:, commit:, repository:, sleeper: ->(seconds) { sleep seconds }, deadline_seconds: 1200)
      @config = config; @api = api; @commit = commit; @repository = repository
      @sleeper = sleeper; @deadline_seconds = deadline_seconds
      @id = config.fetch('service_id')
    end

    def identity!
      service = @api.request(:get, "/services/#{@id}")
      expected_repo = "https://github.com/#{@repository}"
      raise Error, 'Render service repository mismatch' unless service['repo'].to_s.delete_suffix('.git') == expected_repo
      raise Error, 'Render service identity mismatch' unless service['type'] == 'static_site' && service['name'] == @config.fetch('service_name') && service['branch'] == @config.fetch('branch', 'main')
      actual_path = service.fetch('serviceDetails').fetch('publishPath').delete_prefix('./').delete_suffix('/')
      expected_path = @config.fetch('publish_path').delete_prefix('./').delete_suffix('/')
      raise Error, 'Configured publish directory differs from Render' unless actual_path == expected_path
      origin = URI(@config.fetch('origin'))
      raise Error, 'Production origin must be an HTTPS origin' unless origin.scheme == 'https' && origin.path.to_s.empty? && !origin.query && !origin.userinfo
      allowed = [URI(service.fetch('serviceDetails').fetch('url')).host]
      allowed += @api.list("/services/#{@id}/custom-domains", 'customDomain').select { |d| d['verificationStatus'] == 'verified' }.map { |d| d['name'] }
      raise Error, 'Configured origin is not attached to the Render service' unless allowed.include?(origin.host)
      service
    end

    def prepare
      identity!
      before = @api.headers(@id)
      desired = RenderStatic.desired_headers(@config)
      previous = @api.deploys(@id).find { |d| d['status'] == 'live' }
      raise Error, 'No live deployment available for recovery' unless previous && previous.dig('commit', 'id')
      plan = { 'service_id' => @id, 'repository' => @repository, 'commit' => @commit,
               'origin' => @config['origin'], 'publish_path' => @config['publish_path'],
               'before' => before, 'desired' => desired,
               'transition' => RenderStatic.transition_headers(before, desired),
               'previous_commit' => previous.dig('commit', 'id'), 'previous_deploy' => previous['id'] }
      write('plan.json', plan)
      puts "Prepared #{desired.length} header rules for #{@config['service_name']}"
      plan
    end

    def wait_live(deployment)
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + @deadline_seconds
      seen = nil
      loop do
        detail = @api.request(:get, "/services/#{@id}/deploys/#{deployment.fetch('id')}")
        puts "Render deployment: #{detail['status']}" if detail['status'] != seen
        seen = detail['status']
        return detail if seen == 'live'
        raise Error, "Render deployment failed: #{seen}" if %w[build_failed update_failed canceled pre_deploy_failed].include?(seen)
        raise Error, 'Render deployment timed out' if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
        @sleeper.call(10)
      end
    end

    def deploy(plan)
      mutated = false
      identity!
      raise Error, 'Deployment plan belongs to another revision or service' unless plan['commit'] == @commit && plan['repository'] == @repository && plan['service_id'] == @id
      raise Error, 'Header rules changed during preflight; refusing to overwrite' unless RenderStatic.normalized(@api.headers(@id)) == RenderStatic.normalized(plan['before'])
      current = @api.deploys(@id)
      match = current.find { |d| d.dig('commit', 'id') == @commit && %w[live created build_in_progress update_in_progress pre_deploy_in_progress queued].include?(d['status']) }
      if match && match['status'] == 'live'
        mutated = true
        @api.replace_headers(@id, plan['desired'])
      else
        # Keep old and new script hashes/origins valid while Render swaps
        # the HTML. Other headers retain their previous policy until live.
        mutated = true
        @api.replace_headers(@id, plan['transition']) unless plan['before'].empty?
        match ||= @api.request(:post, "/services/#{@id}/deploys", { 'commitId' => @commit, 'clearCache' => 'do_not_clear' })
        write('deploy.json', match.slice('id', 'status', 'commit'))
        wait_live(match)
        @api.replace_headers(@id, plan['desired'])
      end
      latest = @api.deploys(@id).find { |d| d['status'] == 'live' }
      raise Error, 'A different revision is live; final verification refused' unless latest&.dig('commit', 'id') == @commit
      write('sync.json', { 'status' => 'verified', 'commit' => @commit, 'headers' => @api.headers(@id) })
      puts 'Deployment is live and Render headers match the site configuration'
    rescue StandardError
      if mutated
        begin
          recover_headers(plan)
        rescue StandardError => recovery_error
          warn "Header recovery could not be confirmed: #{recovery_error.message}"
        end
      end
      raise
    end

    def recover_headers(plan)
      deployments = @api.deploys(@id)
      live = deployments.find { |d| d['status'] == 'live' }
      active = deployments.any? { |d| d.dig('commit', 'id') == @commit && %w[created build_in_progress update_in_progress pre_deploy_in_progress queued].include?(d['status']) }
      if active
        write('recovery.json', { 'status' => 'deployment still active; retained transitional CSP to keep both revisions valid' })
        return
      end
      return unless live&.dig('commit', 'id') == plan['previous_commit']
      current = @api.headers(@id)
      return unless [plan['transition'], plan['desired']].any? { |r| RenderStatic.normalized(r) == RenderStatic.normalized(current) }
      @api.replace_headers(@id, plan['before'])
      write('recovery.json', { 'restored_headers' => true })
    end

    def rollback(plan)
      identity!
      live = @api.deploys(@id).find { |d| d['status'] == 'live' }
      raise Error, 'A newer release is live; rollback refused' unless live&.dig('commit', 'id') == @commit
      current = @api.headers(@id)
      raise Error, 'Headers changed outside this release; rollback refused' unless RenderStatic.normalized(current) == RenderStatic.normalized(plan['desired'])
      if plan['previous_commit'] == @commit
        @api.replace_headers(@id, plan['before'])
      else
        @api.replace_headers(@id, RenderStatic.transition_headers(plan['desired'], plan['before']))
        deployment = @api.request(:post, "/services/#{@id}/deploys", { 'commitId' => plan['previous_commit'], 'clearCache' => 'do_not_clear' })
        wait_live(deployment)
        @api.replace_headers(@id, plan['before'])
      end
      write('rollback.json', { 'restored_commit' => plan['previous_commit'], 'restored_headers' => true })
      puts 'Restored the previous live revision and header snapshot'
    end

    def write(name, data)
      Dir.mkdir(EVIDENCE) unless Dir.exist?(EVIDENCE)
      File.write(File.join(EVIDENCE, name), JSON.pretty_generate(data))
    end
  end

  def self.git_revision!
    commit, success = Open3.capture2('git', 'rev-parse', 'HEAD')
    raise Error, 'Cannot resolve checked-out revision' unless success.success?
    branch = ENV.fetch('GITHUB_REF_NAME', 'main')
    remote, status = Open3.capture2('git', 'ls-remote', 'origin', "refs/heads/#{branch}")
    raise Error, 'Checked-out commit is no longer the production branch head' unless status.success? && remote.split.first == commit.strip
    commit.strip
  end
end

if $PROGRAM_NAME == __FILE__
  begin
    command = ARGV.fetch(0)
    config = JSON.parse(File.read(ENV.fetch('RENDER_DEPLOY_CONFIG', 'deploy/render.json')))
    api = RenderStatic::Api.new(ENV['RENDER_API_KEY'])
    repository = ENV.fetch('GITHUB_REPOSITORY')
    commit = command == 'rollback' ? JSON.parse(File.read('deployment-evidence/plan.json')).fetch('commit') : RenderStatic.git_revision!
    release = RenderStatic::Release.new(config, api: api, commit: commit, repository: repository)
    case command
    when 'prepare' then release.prepare
    when 'deploy' then release.deploy(JSON.parse(File.read('deployment-evidence/plan.json')))
    when 'rollback' then release.rollback(JSON.parse(File.read('deployment-evidence/plan.json')))
    else raise RenderStatic::Error, 'Unknown deployment command'
    end
  rescue StandardError => e
    warn "Render deployment failed: #{e.message}"
    exit 1
  end
end

# frozen_string_literal: true

require 'date'
require 'json'
require 'time'
require 'uri'
require 'yaml'

# Pure configuration parsing; this module has no network or Render API client.
module HeaderPolicy
  class Error < StandardError; end
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


  def self.matches_path?(pattern, path)
    return true if pattern == '/*'
    return path.start_with?(pattern.delete_suffix('*')) if pattern.end_with?('/*')
    expression = pattern.split('*', -1).map { |part| Regexp.escape(part) }.join('[^/]*')
    path.match?(Regexp.new("\\A#{expression}\\z"))
  end

  def self.plan(config)
    desired = desired_headers(config)
    root = File.realpath(config.fetch('publish_path'))
    files = Dir.glob(File.join(root, '**', '*')).select { |path| File.file?(path) && File.realpath(path).start_with?(root + '/') }.map { |path| path.delete_prefix(root) }.sort
    probes = []; unavailable = []
    desired.map { |rule| rule['path'] }.uniq.each do |pattern|
      if pattern == '/*'
        probes << { 'pattern' => pattern, 'url' => '/' }
        next
      end
      sample = files.find { |path| matches_path?(pattern, path) }
      if sample
        probes << { 'pattern' => pattern, 'url' => URI::DEFAULT_PARSER.escape(sample) }
      else
        unavailable << pattern
      end
    end
    { 'desired' => desired, 'probes' => probes, 'unprobed_paths' => unavailable, 'render_mutations' => false }
  end
end

if $PROGRAM_NAME == __FILE__
  begin
    config = JSON.parse(File.read(ARGV.fetch(0, 'deploy/render.json')))
    result = HeaderPolicy.plan(config)
    Dir.mkdir('deployment-evidence') unless Dir.exist?('deployment-evidence')
    File.write('deployment-evidence/plan.json', JSON.pretty_generate(result))
    puts "Prepared #{result['desired'].length} expected rules and #{result['probes'].length} HTTP probes; Render settings will not be changed"
  rescue StandardError => error
    warn "Header check preparation failed: #{error.message}"
    exit 1
  end
end

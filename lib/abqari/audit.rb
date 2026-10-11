# frozen_string_literal: true

require 'fileutils'
require 'uri'
require 'time'

require_relative 'audit/rule'
require_relative 'audit/links'
require_relative 'audit/seo'
require_relative 'audit/a11y'
require_relative 'audit/privacy'
require_relative 'audit/performance'
require_relative 'audit/dependencies'
require_relative 'audit/content'
require_relative 'audit/csp'

module Abqari
  # Site audit orchestrator. Each check lives in its own rule class
  # under `lib/abqari/audit/`; this file is responsible for:
  #
  #   - Rebuilding the site (so the audit reads fresh _site/ output).
  #   - Invoking every rule in `RULES` against shared findings list.
  #   - Writing the markdown report at `<site>/audit/<timestamp>.md`.
  #   - Exposing `findings` + `count(at_least:)` so `bin/audit --strict`
  #     can gate CI on severity.
  #
  # The split keeps the orchestrator under ~100 lines and lets each
  # rule grow independently. Adding a new category is: add a file
  # under audit/, add the class to RULES, add the category label to
  # CATEGORIES.
  class Audit
    SEVERITIES = %w[error warn info].freeze
    CATEGORIES = {
      'links'   => 'Links',
      'seo'     => 'SEO',
      'a11y'    => 'Accessibility',
      'privacy' => 'Privacy',
      'perf'    => 'Performance',
      'deps'    => 'Dependencies',
      'content' => 'Content',
      'security' => 'Security'
    }.freeze

    # Rule classes, in execution order. Order matters only for the
    # output report — findings are grouped by category, not insertion
    # order — but Links first keeps the report scan-friendly: errors
    # appear before warnings.
    RULES = [Links, SEO, A11y, Privacy, Performance, Dependencies, Content, Csp].freeze

    attr_reader :findings

    def initialize(site)
      @site = site
      @findings = []
    end

    def run
      # No syndication / webmention sending during an audit — auditing a
      # not-yet-deployed post must not broadcast it. See Site#build.
      @site.build(side_effects: false)
      RULES.each { |klass| klass.new(@site, @findings).run }
      write_report
      self
    end

    # Count findings at or above the given severity. Used by `bin/audit
    # --strict` to set the process exit code.
    def count(at_least: 'error')
      threshold = SEVERITIES.index(at_least.to_s) or
        raise ArgumentError, "unknown severity #{at_least.inspect}, expected one of #{SEVERITIES.inspect}"
      @findings.count { |f| (SEVERITIES.index(f[:severity]) || SEVERITIES.size) <= threshold }
    end

    private

    def write_report
      # Audit reports live in the consuming site's repo so they can be
      # committed alongside the content they audit.
      audit_dir = File.join(@site.site_root, 'audit')
      FileUtils.mkdir_p(audit_dir)
      filename = Time.now.strftime('%Y-%m-%d-%H%M.md')
      File.write(File.join(audit_dir, filename), build_report)

      counts = @findings.group_by { |f| f[:severity] }.transform_values(&:size)
      summary = SEVERITIES.map { |s| "#{counts[s] || 0} #{s}" }.join(', ')
      Log.info "Audit complete: audit/#{filename} (#{summary})"
    end

    def build_report
      lines = [
        '# Abqari site audit', '',
        "Generated: #{Time.now.iso8601}",
        "Environment: #{@site.env}", ''
      ]
      lines.concat(summary_table)
      lines << ''
      lines.concat(suggested_fixes_section)

      CATEGORIES.each do |key, name|
        category_findings = @findings.select { |f| f[:category] == key }
        next if category_findings.empty?

        lines << "## #{name}"
        lines << ''
        category_findings.each do |f|
          lines << "- **[#{f[:severity]}]** `#{f[:location]}` — #{f[:message]}"
          lines << "  - #{f[:suggestion]}" if f[:suggestion]
        end
        lines << ''
      end

      lines << '## All clear' if @findings.empty?
      "#{lines.join("\n")}\n"
    end

    def summary_table
      counts = @findings.group_by { |f| f[:category] }
                       .transform_values { |fs| fs.group_by { |f| f[:severity] }.transform_values(&:size) }

      lines = ['## Summary', '']
      lines << '| Category | Errors | Warnings | Info |'
      lines << '| --- | --- | --- | --- |'
      CATEGORIES.each do |key, name|
        c = counts[key] || {}
        lines << "| #{name} | #{c['error'] || 0} | #{c['warn'] || 0} | #{c['info'] || 0} |"
      end
      lines
    end

    # Surface `bundle update <gem>` commands from dependency findings at
    # the top of the report. Dependabot-adjacent: tells the reader the
    # exact commands to run before they scroll through advisories.
    def suggested_fixes_section
      commands = @findings
                 .select { |f| f[:category] == 'deps' && f[:suggestion]&.include?('bundle update') }
                 .map { |f| f[:suggestion][/`bundle update[^`]+`/, 0] }
                 .compact
                 .uniq
      return [] if commands.empty?

      [
        '## Suggested fixes', '',
        'Run these commands to resolve the dependency findings below:', '',
        '```bash',
        *commands.map { |c| c.delete('`') },
        '```', '',
        'Then re-run `bin/audit` to confirm.', ''
      ]
    end
  end
end

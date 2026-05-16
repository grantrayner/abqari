# frozen_string_literal: true

module Abqari
  class Audit
    # Dependency rule. Two sub-checks:
    #   - bundler-audit for known CVE advisories
    #   - `bundle outdated` for behind-latest gems
    #
    # Both run inside `Dir.chdir(@site.site_root)` so they target the
    # consuming site's Gemfile.lock when abqari is consumed as a gem.
    class Dependencies < Rule
      def run
        Dir.chdir(@site.site_root) do
          check_security_advisories
          check_outdated_gems
        end
      end

      private

      # Parses bundler-audit per-finding blocks: gem name, version,
      # advisory ID, criticality, title, recommended upgrade, ref URL.
      # Emits one finding per advisory plus a one-liner that updates
      # every vulnerable gem at once.
      def check_security_advisories
        unless command_available?('bundle-audit')
          add(category: 'deps', severity: 'info', location: 'system',
              message: 'CVE check skipped: bundler-audit not installed',
              suggestion: '`gem install bundler-audit` then re-run audit')
          return
        end

        output = `bundle-audit check --update 2>&1`
        return if output.include?('No vulnerabilities')

        vulnerable_gems = parse_bundler_audit_output(output)
        return if vulnerable_gems.empty?

        add(
          category: 'deps',
          severity: 'info',
          location: 'Gemfile.lock',
          message: "#{vulnerable_gems.uniq.size} gem(s) need security updates",
          suggestion: "Run `bundle update #{vulnerable_gems.uniq.join(' ')}` to address all listed advisories"
        )
      end

      def parse_bundler_audit_output(output)
        vulnerable_gems = []

        output.split(/\n\s*\n/).each do |block|
          next unless block =~ /^\s*Name:/

          fields = block.scan(/^\s*([A-Za-z]+):\s*(.+?)\s*$/).to_h
          name = fields['Name']
          next unless name

          vulnerable_gems << name
          emit_advisory_finding(name, fields)
        end

        vulnerable_gems
      end

      def emit_advisory_finding(name, fields)
        advisory    = fields['GHSA'] || fields['CVE'] || 'unknown'
        criticality = (fields['Criticality'] || 'unknown').downcase
        version     = fields['Version']
        title       = fields['Title']
        solution    = fields['Solution']
        url         = fields['URL']

        message_parts = ["#{name} #{version}".rstrip, "(#{advisory})"]
        message_parts << "[#{criticality}]" unless criticality == 'unknown'
        message_parts << "— #{title}" if title

        suggestion_parts = ["Run `bundle update #{name}`"]
        suggestion_parts << solution.sub(/\Aupgrade to /, '(target: ').concat(')') if solution
        suggestion_parts << url if url

        add(
          category: 'deps',
          severity: cve_severity(criticality),
          location: 'Gemfile.lock',
          message: message_parts.join(' '),
          suggestion: suggestion_parts.join(' · ')
        )
      end

      # `--parseable` for stable cross-version output; falls back to the
      # human-readable form so older Bundler still works.
      def check_outdated_gems
        output = `bundle outdated --strict --parseable 2>/dev/null`
        output = `bundle outdated --strict 2>/dev/null` if output.empty?

        output.lines.each do |line|
          match = line.match(/(\S+)\s+\(newest\s+(\S+),\s+installed\s+(\S+)/) ||
                  line.match(/^\s*\*\s+(\S+)\s+\(newest\s+(\S+),\s+installed\s+(\S+)/)
          next unless match

          name, newest, installed = match[1], match[2], match[3]
          add(category: 'deps', severity: 'info', location: 'Gemfile',
              message: "#{name} is outdated (installed #{installed}, latest #{newest})",
              suggestion: "Run `bundle update #{name}` to upgrade")
        end
      end

      def cve_severity(criticality)
        case criticality
        when 'critical', 'high' then 'error'
        when 'medium'           then 'warn'
        else                         'info'
        end
      end

      # PATH walk instead of `system("command -v #{cmd} ...")` so the
      # caller can't inadvertently introduce shell injection. Callers
      # are hardcoded today, but the argv-free form is the safer default
      # and matches Search#command_available?.
      def command_available?(cmd)
        ENV['PATH'].to_s.split(File::PATH_SEPARATOR).any? do |dir|
          File.executable?(File.join(dir, cmd))
        end
      end
    end
  end
end

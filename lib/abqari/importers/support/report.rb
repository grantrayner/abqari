# frozen_string_literal: true

module Abqari
  module Importers
    module Support
      # Accumulates per-post results during an import run and writes
      # a markdown report (`_import_report.md`) the operator can
      # spot-check in their editor. Gitignored — see
      # `lib/abqari/templates/site_skeleton/.gitignore`.
      #
      # Each entry has a status (`:imported`, `:skipped`, `:failed`)
      # plus a short reason. Warnings (e.g. image download failures
      # that didn't sink the post) live alongside the entry so the
      # operator can see exactly what went wrong with which post,
      # rather than a flat global warning log.
      class Report
        Entry = Struct.new(:slug, :title, :status, :reason, :warnings,
                           keyword_init: true)

        attr_reader :entries, :source, :importer

        def initialize(source:, importer:)
          @source   = source
          @importer = importer
          @entries  = []
          @started  = Time.now
        end

        def add(slug:, title:, status:, reason: nil, warnings: [])
          @entries << Entry.new(slug: slug, title: title, status: status,
                                reason: reason, warnings: Array(warnings))
        end

        def count(status)
          @entries.count { |e| e.status == status }
        end

        # Returns the formatted markdown for the run. The caller writes
        # it wherever it wants (we don't bake in a path so tests can
        # round-trip without touching disk).
        def to_markdown
          lines = []
          lines << "# Import report"
          lines << ''
          lines << "- **Importer:** `#{@importer}`"
          lines << "- **Source:** `#{@source}`"
          lines << "- **Started:** #{@started.utc.iso8601}"
          lines << "- **Imported:** #{count(:imported)}"
          lines << "- **Skipped:**  #{count(:skipped)}"
          lines << "- **Failed:**   #{count(:failed)}"
          lines << ''
          lines << '---'
          lines << ''

          if @entries.empty?
            lines << '_No posts were processed._'
          else
            @entries.each do |e|
              lines << "## #{e.title.to_s.empty? ? '(untitled)' : e.title}"
              lines << ''
              lines << "- Slug: `#{e.slug}`"
              lines << "- Status: **#{e.status}**"
              lines << "- Reason: #{e.reason}" if e.reason && !e.reason.empty?
              if e.warnings.any?
                lines << '- Warnings:'
                e.warnings.each { |w| lines << "  - #{w}" }
              end
              lines << ''
            end
          end

          lines.join("\n") + "\n"
        end

        # Compact one-line summary for stdout at the end of the run.
        def summary_line
          warns = @entries.sum { |e| e.warnings.size }
          parts = ["#{count(:imported)} imported"]
          parts << "#{count(:skipped)} skipped" if count(:skipped).positive?
          parts << "#{count(:failed)} failed"   if count(:failed).positive?
          parts << "#{warns} warnings"          if warns.positive?
          "✓ #{parts.join(', ')}."
        end
      end
    end
  end
end

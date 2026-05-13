# frozen_string_literal: true

module Abqari
  class Audit
    # Base class for audit rules. Each rule lives in its own file under
    # `lib/abqari/audit/<category>.rb`, inherits from this, and implements
    # `#run`. Shared helpers (`html_files`, `page_url`, `add`) live here
    # so individual rules stay focused on their domain logic.
    #
    # Rules are stateless across runs — instantiated by Audit#run with
    # the current site and findings list, then discarded. Caching that
    # makes sense for the duration of a single audit (e.g. memoised
    # `html_files`) lives on the instance.
    class Rule
      def initialize(site, findings)
        @site = site
        @findings = findings
      end

      # Subclasses override. The default raises so a half-finished rule
      # surfaces immediately in tests instead of silently no-opping.
      def run
        raise NotImplementedError, "#{self.class.name} must implement #run"
      end

      protected

      def add(category:, severity:, location:, message:, suggestion: nil)
        @findings << {
          category: category,
          severity: severity,
          location: location,
          message: message,
          suggestion: suggestion
        }
      end

      # Every rendered HTML file in the build output, sorted for stable
      # iteration. Memoised per rule instance (one audit run = one glob
      # per category, which is cheaper than chasing global state).
      def html_files
        @html_files ||= Dir.glob(File.join(@site.output_dir, '**', '*.html')).sort
      end

      def page_url(file)
        file.sub(@site.output_dir, '').sub(%r{/index\.html\z}, '/')
      end

      def host_for(url)
        URI(url).host
      rescue URI::InvalidURIError
        nil
      end
    end
  end
end

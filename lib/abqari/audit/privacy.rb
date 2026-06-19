# frozen_string_literal: true

require 'set'

module Abqari
  class Audit
    # Privacy rule. Surfaces every cross-origin resource referenced from
    # rendered HTML (`src`/`href` to a host other than the site's own).
    # Info-severity because external loads are a deliberate choice, not
    # always a bug — but each one is a third-party tracking vector worth
    # auditing.
    #
    # No-ops when `config.url` isn't set (we can't tell what "external"
    # means without knowing what's internal).
    class Privacy < Rule
      def run
        site_host = host_for(@site.config['url'])
        return unless site_host

        seen = Set.new

        html_files.each do |file|
          url  = page_url(file)
          html = File.read(file, encoding: 'UTF-8')

          html.scan(%r{(?:src|href)="(https?://[^"]+)"}).each do |(external_url)|
            ext_host = host_for(external_url)
            next if ext_host.nil? || ext_host == site_host

            key = "#{url}|#{external_url}"
            next if seen.include?(key)

            seen << key
            add(category: 'privacy', severity: 'info', location: url,
                message: "External resource loaded: #{external_url}",
                suggestion: 'Consider self-hosting to avoid third-party tracking')
          end
        end
      end
    end
  end
end

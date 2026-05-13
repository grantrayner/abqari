# frozen_string_literal: true

require 'set'

module Abqari
  class Audit
    # Broken internal-link detector. Walks every `href` in rendered HTML
    # and flags any that doesn't resolve to a file we actually emitted.
    # External (`http(s)://`) links are skipped here — Privacy covers
    # them — and so are anchors / mailto / tel / data / javascript.
    class Links < Rule
      def run
        output_paths = build_output_path_set
        site_host    = host_for(@site.config['url'])

        html_files.each do |file|
          url  = page_url(file)
          html = File.read(file, encoding: 'UTF-8')

          html.scan(/href="([^"#?]+)/).each do |(link)|
            next if link.empty?
            next if link.start_with?('mailto:', 'tel:', 'data:', 'javascript:', '#')

            if link.start_with?('http://', 'https://')
              link_host = host_for(link)
              next if site_host && link_host == site_host
              next # external — Privacy rule covers this
            end

            target = absolute_target(link, url)
            next if output_paths.include?(target) ||
                    output_paths.include?("#{target}index.html")

            add(category: 'links', severity: 'error', location: url,
                message: "Broken link: #{link}")
          end
        end
      end

      private

      def absolute_target(link, current_page_url)
        return link if link.start_with?('/')

        base_dir = File.dirname(current_page_url)
        File.join(base_dir, link).gsub(%r{/\./}, '/')
      end

      def build_output_path_set
        paths = Set.new
        # No `.sort` — populating a Set is order-invariant; the audit
        # only does membership checks against `paths`, never iterates.
        Dir.glob(File.join(@site.output_dir, '**', '*'), File::FNM_DOTMATCH).each do |entry|
          next if File.directory?(entry)

          rel = entry.sub(@site.output_dir, '')
          paths << rel
          paths << rel.sub(%r{/index\.html\z}, '/') if rel.end_with?('/index.html')
        end
        paths
      end
    end
  end
end

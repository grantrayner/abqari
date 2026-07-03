# frozen_string_literal: true

require 'set'

module Abqari
  class Audit
    # Broken internal-link / missing-asset detector. Walks every `href`,
    # `src`, and `srcset` in rendered HTML and flags any same-origin
    # reference that doesn't resolve to a file we actually emitted.
    # External (`http(s)://` to another host) references are skipped
    # here — Privacy covers them — as are anchors / mailto / tel / data.
    class Links < Rule
      def run
        output_paths = build_output_path_set
        site_host    = host_for(@site.config['url'])

        html_files.each do |file|
          url  = page_url(file)
          html = File.read(file, encoding: 'UTF-8')

          # Strip `<pre>…</pre>` and inline `<code>…</code>` blocks
          # before scanning. Rouge's HTML-lexer highlighting of an
          # ERB or HTML example wraps the attribute value in
          # `<span class="s">...</span>`, which a naive `href="…"`
          # regex picks up as a "broken link" pointing at
          # `</span><span class=` and similar fragments. Code
          # samples aren't navigation — skip them.
          scan_html = html.gsub(%r{<pre\b[^>]*>.*?</pre>}m, '')
                          .gsub(%r{<code\b[^>]*>.*?</code>}m, '')

          references(scan_html).each do |link|
            next if link.empty?
            next if link.start_with?('mailto:', 'tel:', 'data:', 'javascript:', '#')

            # Same-origin absolute URLs (`https://mysite/gone/`) are
            # checked like internal links; only cross-host ones are
            # skipped (Privacy covers those). Previously BOTH branches
            # fell through, so a broken absolute link to your own domain
            # was invisible to every rule.
            if link.start_with?('http://', 'https://')
              link_host = host_for(link)
              next unless site_host && link_host == site_host

              link = (URI(link).path.to_s.empty? ? '/' : URI(link).path)
            end

            target = resolve_target(link, url)
            next if output_paths.include?(target) ||
                    output_paths.include?("#{target}index.html")

            add(category: 'links', severity: 'error', location: url,
                message: "Broken link/asset: #{link}")
          end
        end
      end

      private

      # Every same-origin reference in the page: `href`, `src`, and each
      # candidate URL inside a `srcset` (comma-separated `url descriptor`
      # pairs). Query strings and fragments are trimmed off.
      def references(html)
        found = []
        html.scan(/(?:href|src)="([^"#?]+)/) { |(l)| found << l }
        html.scan(/srcset="([^"]+)"/) do |(set)|
          set.split(',').each do |candidate|
            u = candidate.strip.split(/\s+/).first.to_s.split(/[#?]/).first
            found << u unless u.to_s.empty?
          end
        end
        found
      end

      # Resolve a link to a root-relative path, honouring the browser's
      # base-URL rules and collapsing `.`/`..` segments.
      #
      # The base for a RELATIVE link is the current page's directory. For
      # a directory-style URL (`/posts/foo/`) that IS the URL itself —
      # `File.dirname` would wrongly drop `foo/` and resolve bundle
      # assets against `/posts/`, producing false "broken link" reports
      # for the engine's own primary asset pattern.
      def resolve_target(link, current_page_url)
        raw = if link.start_with?('/')
                link
              else
                base = current_page_url.end_with?('/') ? current_page_url : "#{File.dirname(current_page_url)}/"
                "#{base}#{link}"
              end
        normalize_path(raw)
      end

      def normalize_path(path)
        trailing = path.end_with?('/')
        segments = []
        path.split('/').each do |seg|
          next if seg.empty? || seg == '.'

          seg == '..' ? segments.pop : segments << seg
        end
        result = "/#{segments.join('/')}"
        result += '/' if trailing && result != '/'
        result
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

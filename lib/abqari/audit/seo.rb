# frozen_string_literal: true

module Abqari
  class Audit
    # SEO rule. Catches:
    #   - Missing meta descriptions
    #   - Title / description length problems
    #   - Duplicate titles across pages
    #   - Missing og:image (info — no social-share preview)
    #   - Workshops without Event JSON-LD
    #   - Publications without Book JSON-LD
    #
    # Redirect stubs (meta-refresh-only pages) are skipped — they're
    # not user-facing content, so SEO rules don't apply.
    class SEO < Rule
      TITLE_MAX_CHARS = 60
      DESC_MAX_CHARS  = 160

      def run
        titles = {}

        html_files.each do |file|
          url  = page_url(file)
          html = File.read(file, encoding: 'UTF-8')
          next if html.include?('http-equiv="refresh"')

          check_title(html, url, titles)
          check_description(html, url)
          check_og_image(html, url)
          check_workshop_event_jsonld(html, url)
          check_publication_book_jsonld(html, url)
        end

        flag_duplicate_titles(titles)
      end

      private

      def check_title(html, url, titles)
        title = html[%r{<title>(.*?)</title>}m, 1]
        return unless title

        (titles[title] ||= []) << url
        return unless title.length > TITLE_MAX_CHARS

        add(category: 'seo', severity: 'warn', location: url,
            message: "Title is #{title.length} chars",
            suggestion: "Aim for #{TITLE_MAX_CHARS} or fewer for search snippets")
      end

      def check_description(html, url)
        desc = html[/<meta name="description" content="([^"]*)"/, 1]

        if desc.nil? || desc.empty?
          add(category: 'seo', severity: 'warn', location: url,
              message: 'Missing meta description')
        elsif desc.length > DESC_MAX_CHARS
          add(category: 'seo', severity: 'warn', location: url,
              message: "Description is #{desc.length} chars",
              suggestion: "Aim for #{DESC_MAX_CHARS} or fewer")
        end
      end

      def check_og_image(html, url)
        og_image = html[/<meta property="og:image" content="[^"]*"/]
        return if og_image

        add(category: 'seo', severity: 'info', location: url,
            message: 'Missing og:image (no social-share preview)',
            suggestion: 'Set `image:` in frontmatter, or a site-wide `share_image:` in config')
      end

      def check_workshop_event_jsonld(html, url)
        return unless url.start_with?('/workshops/') && url != '/workshops/'
        return if url.include?('/page/')
        return if html.match?(/"@type"\s*:\s*"Event"/)

        add(category: 'seo', severity: 'warn', location: url,
            message: 'Workshop has no Event JSON-LD',
            suggestion: 'Workshop frontmatter needs `date_from:` (and ideally `date_to:`, `location:`, `price:`) for the Event partial to render')
      end

      def check_publication_book_jsonld(html, url)
        return unless url.start_with?('/publications/', '/books/')
        return if url.match?(%r{\A/(publications|books)/\z})
        return if url.include?('/page/')
        return if html.match?(/"@type"\s*:\s*"Book"/)

        add(category: 'seo', severity: 'warn', location: url,
            message: 'Publication has no Book JSON-LD',
            suggestion: 'Check that `_book_jsonld` is rendered from the publication layout and the page has a title')
      end

      def flag_duplicate_titles(titles)
        titles.each do |title, urls|
          next if urls.size <= 1

          add(category: 'seo', severity: 'warn',
              location: urls.join(', '),
              message: "Duplicate title: \"#{title}\"")
        end
      end
    end
  end
end

# frozen_string_literal: true

module Abqari
  class Audit
    # Accessibility rule. Catches structural issues that hurt
    # screen-reader / keyboard users:
    #   - <img> elements without alt attribute (error)
    #   - Multiple <h1> elements per page (warn)
    #   - Missing skip-to-content link (warn)
    #   - Missing <main id="main-content"> landmark (warn)
    #   - Multiple <nav>s without aria-label (warn)
    #
    # Redirect-stub pages (meta-refresh) are skipped — they have no
    # user-facing content, so landmark rules don't apply.
    class A11y < Rule
      def run
        html_files.each do |file|
          url  = page_url(file)
          html = File.read(file, encoding: 'UTF-8')
          next if html =~ /<meta\s+http-equiv=["']refresh/i

          check_img_alt(html, url)
          check_single_h1(html, url)
          check_skip_link(html, url)
          check_main_landmark(html, url)
          check_nav_labels(html, url)
        end
      end

      private

      def check_img_alt(html, url)
        html.scan(/<img\s+([^>]+?)>/).each do |(attrs)|
          next if attrs =~ /\balt\s*=/

          src = attrs[/src\s*=\s*"([^"]+)"/, 1] || '(unknown source)'
          add(category: 'a11y', severity: 'error', location: url,
              message: "Image without alt attribute: #{src}",
              suggestion: 'Add alt="" for decorative images, descriptive alt for content')
        end
      end

      def check_single_h1(html, url)
        h1_count = html.scan(/<h1\b/).size
        return unless h1_count > 1

        add(category: 'a11y', severity: 'warn', location: url,
            message: "#{h1_count} <h1> elements found",
            suggestion: 'Use exactly one <h1> per page; nest others as <h2>+')
      end

      def check_skip_link(html, url)
        return if html =~ /class="skip-link"|href="#main-content"/

        add(category: 'a11y', severity: 'warn', location: url,
            message: 'Missing skip-to-content link',
            suggestion: "Add <%= render 'partials/skip_link' %> as the first thing in <body>")
      end

      def check_main_landmark(html, url)
        return if html =~ /<main\b[^>]*\bid\s*=\s*"main-content"/

        add(category: 'a11y', severity: 'warn', location: url,
            message: 'Missing <main id="main-content"> landmark',
            suggestion: 'Wrap primary content in <main id="main-content" tabindex="-1">')
      end

      def check_nav_labels(html, url)
        unlabelled = html.scan(/<nav\b([^>]*)>/).reject do |(attrs)|
          attrs =~ /\baria-label(?:ledby)?\s*=/
        end
        return unless unlabelled.size.positive? && html.scan(/<nav\b/).size > 1

        add(category: 'a11y', severity: 'warn', location: url,
            message: "#{unlabelled.size} <nav> element(s) without aria-label",
            suggestion: 'Add aria-label="Primary" / "Pagination" / etc. to disambiguate')
      end
    end
  end
end

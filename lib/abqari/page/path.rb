# frozen_string_literal: true

module Abqari
  class Page
    # Output-path resolution. The review (§2 finding C1, §8) flagged
    # `output_path` as the security-critical method on Page — a
    # `permalink:` frontmatter typo or hostile sync source could otherwise
    # write outside `_site/`. Lifting it into its own module makes the
    # surface easy to audit: every filesystem-bound path computation
    # for a Page lives here, routed through `PathSafe.join_under` so
    # traversal is impossible by construction.
    #
    # Public surface: `output_path`, `url`, `layout_name`.
    # Helpers (`render_permalink`, `relative_*`, `index_page?`) are
    # private — internal to the path computation.
    module Path
      # Permitted characters in a frontmatter `permalink:` value. We
      # allow the usual URL-safe set plus `/` for nested directories.
      # Anything else (control chars, backslashes, `:`, `?`, `#`, …) is
      # rejected before we touch the filesystem — they're either
      # traversal vectors or just wrong for a URL.
      PERMALINK_ALLOWED = %r{\A[A-Za-z0-9_\-./]+\z}.freeze

      def url
        output_path
          .sub(site.output_dir, '')
          .sub(%r{/index\.html\z}, '/')
      end

      def output_path
        # Frontmatter override always wins — useful for /404.html,
        # /robots.txt-style files, a flat-collection index page, or
        # any page that needs a non-default URL.
        #
        # `permalink:` is user input. Run it through `PathSafe.join_under`
        # so a malicious or accidental `../../..` segment fails the
        # build rather than writing outside `output_dir`.
        if (custom = frontmatter['permalink'])
          cleaned = custom.to_s.sub(%r{\A/}, '')
          # `permalink: "/"` is the home page — cleaned becomes empty
          # after stripping the leading slash. That's a legitimate
          # value (a site setting an explicit home-page permalink for
          # documentation purposes); short-circuit to the output dir's
          # `index.html` before the regex check, which `+` won't
          # match against the empty string.
          return PathSafe.join_under(site.output_dir, 'index.html') if cleaned.empty?

          unless cleaned.match?(PERMALINK_ALLOWED)
            raise PathSafe::Error,
                  "invalid permalink #{custom.inspect} in #{source_path}: " \
                  'only A-Z, a-z, 0-9, `_`, `-`, `.`, `/` are allowed'
          end
          if cleaned.end_with?('/') || File.extname(cleaned).empty?
            PathSafe.join_under(site.output_dir, cleaned, 'index.html')
          else
            PathSafe.join_under(site.output_dir, cleaned)
          end
        elsif collection
          rendered = render_permalink(site.collection_config(collection)['permalink'])
          PathSafe.join_under(site.output_dir, rendered, 'index.html')
        elsif index_page?
          PathSafe.join_under(site.output_dir, relative_dir, 'index.html')
        else
          PathSafe.join_under(site.output_dir, relative_basename, 'index.html')
        end
      end

      def layout_name
        return frontmatter['layout'] if frontmatter['layout']
        return site.collection_config(collection)['layout'] if collection

        'application'
      end

      private

      def render_permalink(template)
        d = date || Time.now
        template
          .gsub(':slug',  slug)
          .gsub(':year',  d.strftime('%Y'))
          .gsub(':month', d.strftime('%m'))
          .gsub(':day',   d.strftime('%d'))
          .sub(%r{\A/}, '')
          .sub(%r{/?\z}, '')
      end

      # Source path with the leading `<site_root>/content/` stripped.
      # `content/posts/hello/index.md` → `posts/hello/index.md`.
      def relative_path
        source_path.sub("#{File.join(site.site_root, 'content')}/", '')
      end

      def index_page?
        File.basename(relative_path, '.md') == 'index'
      end

      def relative_dir
        dir = File.dirname(relative_path)
        dir == '.' ? '' : dir
      end

      def relative_basename
        relative_path.sub(/\.md\z/, '')
      end
    end
  end
end

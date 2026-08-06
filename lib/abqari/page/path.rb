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

      # Permitted `layout:` value. A layout name is resolved to a file
      # path (`app/views/layouts/<name>.html.erb`) via `find_in_paths`,
      # which is then `File.read` + ERB-`eval`'d — so a traversing value
      # (`../../../../etc/foo`) is a file-read + code-execution vector,
      # not just a bad URL. Frontmatter `layout:` can arrive from an
      # untrusted platform export (the Jekyll importer preserves it), so
      # allow only flat/nested layout identifiers: alphanumerics, `_`,
      # `-`, and `/` for subdirectories. No leading `/`, no `.` (so `..`
      # can't form), no backslash.
      LAYOUT_ALLOWED = %r{\A[A-Za-z0-9][A-Za-z0-9_\-/]*\z}.freeze

      # Site-relative URL for this page, derived by removing the output
      # root from the absolute output path.
      #
      # The strip is ANCHORED. An unanchored `sub` removes the first
      # occurrence anywhere in the string, so it silently did nothing
      # when `output_dir` wasn't a prefix (a relative
      # `ABQARI_OUTPUT_DIR`) and left an absolute filesystem path as the
      # "URL". `Site#output_dir` now guarantees an absolute path, so
      # that specific case can't recur — but anchoring makes the
      # assumption explicit rather than incidental, and a mismatch fails
      # loudly instead of shipping local paths to production.
      def url
        root = site.output_dir.chomp('/')
        unless output_path.start_with?("#{root}/")
          raise "output path #{output_path.inspect} is not under output_dir #{root.inspect}"
        end

        output_path
          .sub(/\A#{Regexp.escape(root)}/, '')
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
        if (custom = frontmatter['layout'])
          name = custom.to_s
          unless name.match?(LAYOUT_ALLOWED)
            raise PathSafe::Error,
                  "invalid layout #{custom.inspect} in #{source_path}: " \
                  'only A-Z, a-z, 0-9, `_`, `-`, `/` are allowed (no traversal)'
          end
          return name
        end
        return site.collection_config(collection)['layout'] if collection

        'application'
      end

      private

      def render_permalink(template)
        d = date || Time.now
        if template.include?(':slug') && slug.to_s.empty?
          # An empty slug collapses `/posts/:slug/` to `/posts/`, which
          # writes over the collection index. The usual cause is a title
          # with no ASCII characters — `slugify("مرحبا")` is "" — so the
          # message points at the fix.
          raise PathSafe::Error,
                "empty slug for #{source_path}: the source name produced no URL-safe " \
                'characters. Rename the directory/file or set an explicit `slug:`/`permalink:`.'
        end

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

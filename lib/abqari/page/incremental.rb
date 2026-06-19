# frozen_string_literal: true

module Abqari
  class Page
    # Incremental-render heuristics + memory management.
    #
    # `needs_render?` decides whether a page can be skipped during an
    # incremental rebuild by comparing the output file's mtime against
    # every input that affects its render. `lastmod` exposes the same
    # signals to the sitemap so search engines know when to recrawl.
    # `forget_body!` releases the in-memory body after a page's own
    # render completes, bounding the engine's memory footprint.
    module Incremental
      # Most recent of: publication date, source file mtime, and (for
      # bundles) any colocated asset mtime. Used by the sitemap so
      # search engines re-crawl when content or its assets change.
      def lastmod
        candidates = [File.mtime(source_path), date]
        candidates.concat(bundle_assets.map { |a| File.mtime(a) })
        candidates.compact.max
      end

      # Skip the render when the output is already up to date.
      # Considers:
      #
      #   - source file mtime (`source_path`)
      #   - bundle-asset mtimes (for posts)
      #   - site-wide "global" deps mtime (partials, helpers, config,
      #     themes, icons, assets, data) — any change invalidates every
      #     page
      #   - layout-chain deps mtime (`layouts/<name>.html.erb` and every
      #     ancestor `layout:` extends) — invalidates only pages using
      #     that chain. Editing `layouts/post.html.erb` no longer
      #     invalidates photo/publication/workshop pages.
      #
      # Always returns true when output is missing or in non-
      # incremental mode (Site#build wipes _site/ first, so output
      # never exists).
      def needs_render?
        return true unless File.exist?(output_path)

        output_mtime = File.mtime(output_path)
        return true if File.mtime(source_path) > output_mtime
        return true if post? && bundle_assets.any? { |a| File.mtime(a) > output_mtime }
        return true if site.shared_deps_mtime > output_mtime
        return true if site.layout_deps_mtime(layout_name) > output_mtime

        false
      end

      # Release the in-memory body + rendered content after this page
      # has been written to disk. Frontmatter stays — it's small and
      # accessed everywhere (taxonomy, sitemap, feed, related lookups).
      # Body is large (~10 KB per page typically) and only needed
      # during the page's own render; at 10k pages × 10 KB that's
      # ~100 MB of otherwise-retained memory.
      #
      # If a later request re-reads body (e.g. a posts-index page
      # rendering after this post and pulling its first-paragraph
      # description), `#body` lazily loads from disk. OS page cache
      # makes the re-read sub-millisecond.
      def forget_body!
        @body = nil
        @content = nil
      end
    end
  end
end

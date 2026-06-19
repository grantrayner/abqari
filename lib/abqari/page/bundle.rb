# frozen_string_literal: true

module Abqari
  class Page
    # Bundle-asset discovery. A "bundle" is a directory containing
    # `index.md` plus colocated assets (hero image, body figures, AVIF/
    # WebP variants, etc.). Bundles are the default layout for posts
    # and photos; flat collections (publications, workshops) use a
    # single `.md` file with assets in the collection root.
    #
    # External symlinks (real path escapes `site_root`) are filtered
    # via `Site#external_symlink?` so a hostile or accidental link
    # can't pull external files into the build.
    module Bundle
      IMAGE_EXTENSIONS = %w[.jpg .jpeg .png .gif .webp .avif .svg].freeze

      # Filesystem directory containing this page's bundle, or nil for
      # flat-collection pages and top-level pages (no bundle).
      def bundle_dir
        return nil unless collection

        cfg = site.collections[collection]
        cfg['bundle'] != false ? File.dirname(source_path) : nil
      end

      # Every non-hidden, non-index file in the bundle dir. Skips
      # directories, the index.md itself, dotfiles, and any symlink
      # that escapes `site_root`.
      def bundle_assets
        return [] unless bundle_dir

        # Sort for deterministic iteration order — without it, sitemap
        # image entries can shuffle between builds on the same machine
        # when the filesystem reorders inodes. Same content, different
        # bytes-on-disk → noisy diffs on every deploy.
        Dir.glob(File.join(bundle_dir, '*')).sort.reject do |entry|
          File.directory?(entry) ||
            File.basename(entry) == 'index.md' ||
            File.basename(entry).start_with?('.') ||
            site.external_symlink?(entry)
        end
      end

      # URL paths (not filesystem paths) for every image the sitemap
      # should advertise as belonging to this page. Two sources:
      #
      #   1. Files in the bundle dir matching IMAGE_EXTENSIONS — the
      #      common case (colocated hero + body figures). Converted
      #      from filesystem path to URL path: `<page.url><basename>`.
      #   2. Frontmatter `image:` / `cover:` / `cover_image:` values
      #      that point at absolute same-origin paths (e.g.
      #      `/assets/hero.jpg`). Bundle-relative values are skipped
      #      because they're already covered by source #1 above.
      #      External URLs (http/https) aren't claimed.
      #
      # Inline body images aren't extracted — parsing markdown is
      # expensive and the image sitemap is meant for primary content,
      # not embedded illustrations.
      def bundle_images
        results = []
        bundle_assets.each do |path|
          next unless IMAGE_EXTENSIONS.include?(File.extname(path).downcase)

          results << "#{url}#{File.basename(path)}"
        end
        %w[image cover cover_image].each do |key|
          raw = frontmatter[key].to_s
          next if raw.empty?
          next if raw.start_with?('http://', 'https://')
          next unless raw.start_with?('/')

          results << raw unless results.include?(raw)
        end
        results
      end
    end
  end
end

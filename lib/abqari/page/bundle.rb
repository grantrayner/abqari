# frozen_string_literal: true

require 'uri' # URI::DEFAULT_PARSER — percent-encoding bundle filenames

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

      # Extensions published from a bundle directory. An ALLOW-list, not
      # a deny-list, and that direction is the whole point.
      #
      # This used to publish everything that wasn't a directory, dotfile
      # or `index.md`. That shipped whatever an author happened to leave
      # in the folder — including a `notes.md` marked `published: false`,
      # which went to production verbatim, frontmatter and all, at a
      # guessable URL. `published: false` has to be a promise; a rule
      # that publishes the file anyway makes the flag lie.
      #
      # Excluding `.md` alone would fix that case and leave the class:
      # the next `.psd`, `.sketch`, `.docx` or `working-notes.rtf` would
      # ship the same way. A deny-list has to be extended forever and
      # fails open on everything nobody thought of; an allow-list fails
      # closed.
      #
      # Generous on purpose, and extensible — `bundle_assets.extensions:`
      # in site.yml adds to this list, so a site publishing `.gpx` or
      # `.stl` isn't stuck. Skipped files are WARNED about, never
      # silently dropped: silent omission is the failure mode this is
      # meant to end, and swapping one silence for another would miss
      # the point.
      #
      # Note `.md` is absent deliberately — markdown is content, never an
      # asset. `BundleAssets#copy_flat_collection_assets` has always
      # taken that line for flat collections; bundles simply never did,
      # and the inconsistency is what let the leak through.
      PUBLISHABLE_EXTENSIONS = %w[
        .jpg .jpeg .png .gif .webp .avif .svg .ico
        .mp4 .webm .mov .m4v
        .mp3 .m4a .oga .ogg .opus .wav .flac
        .vtt .srt
        .pdf .epub .zip
      ].freeze

      # Content, never assets — not publishable via `bundle_assets.extensions:`
      # either. Allowing markdown back in would republish exactly the
      # `published: false` sibling the allow-list exists to hold back, so
      # `Site#bundle_asset_extensions` filters these out of user config
      # rather than trusting nobody will try.
      CONTENT_EXTENSIONS = %w[.md .markdown].freeze

      # Filesystem directory containing this page's bundle, or nil for
      # flat-collection pages and top-level pages (no bundle).
      def bundle_dir
        return nil unless collection

        cfg = site.collections[collection]
        cfg['bundle'] != false ? File.dirname(source_path) : nil
      end

      # Files in the bundle dir that are published alongside the page —
      # those whose extension is in the site's publishable set.
      def bundle_assets
        bundle_entries.select { |entry| publishable_bundle_file?(entry) }
      end

      # The complement: bundle files that will NOT be published. The
      # caller (`BundleAssets#copy_bundle_assets`) warns about these once
      # per build so an author can see what was left behind and either
      # allow the extension or move the file out.
      def unpublishable_bundle_files
        bundle_entries.reject { |entry| publishable_bundle_file?(entry) }
      end

      # Candidate files in the bundle dir, before the extension filter.
      # Skips directories, the index.md itself, dotfiles, and any symlink
      # that escapes `site_root`.
      #
      # Dotfiles are the deliberate escape hatch for genuinely private
      # working files: `Dir.glob` skips them without `FNM_DOTMATCH`, so
      # a `.notes.md` is neither published as an asset nor loaded as a
      # page. That's what the skip warning points authors at.
      def bundle_entries
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

      def publishable_bundle_file?(path)
        site.bundle_asset_extensions.include?(File.extname(path).downcase)
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

          # Percent-encode the basename: it comes off the filesystem, so
          # it can contain spaces or non-ASCII, and a sitemap
          # `<image:loc>` with a literal space is invalid (XML-escaping
          # doesn't help — that's a different layer). Only the
          # filesystem-derived part is encoded; frontmatter values below
          # are author-written URLs and may already be encoded, so
          # touching them risks double-encoding.
          results << "#{url}#{URI::DEFAULT_PARSER.escape(File.basename(path))}"
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

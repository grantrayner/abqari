# frozen_string_literal: true

require 'digest'
require 'fileutils'
require 'uri'

module Abqari
  module Importers
    module Support
      # Downloads remote images into a post's bundle directory and
      # returns a map of `{original_url => local_filename}` so the
      # caller can rewrite references in the post body.
      #
      # Why download at all: source-platform CDN URLs (substackcdn.com,
      # ghost.io's blob storage, Medium's image proxy) get rotated
      # or revoked periodically. Sites that keep remote URLs look
      # fine immediately and then break six to twenty-four months
      # later when the source decides to expire the link. Downloading
      # at import-time is slower but durable — the image is now part
      # of the post's bundle and goes through Abqari's image pipeline
      # at build time (AVIF + WebP variants, metadata stripped,
      # responsive `<picture>` rewriting). The pipeline runs the same
      # way it does for a hand-authored bundle, so an imported post
      # ends up indistinguishable from one written natively.
      #
      # Failure handling: a download failure is reported as a warning
      # and the URL is left as-is in the body. We never abort the
      # whole post because of an image — most posts have many images
      # and one CDN hiccup shouldn't sink the whole import.
      class ImageDownloader
        # Extensions we recognise as images. Anything else is left
        # in place (svg passes through here because Abqari's image
        # pipeline preserves it; non-image extensions like `.pdf`
        # are intentionally ignored so we don't accidentally try
        # to "download an image" that's actually a document).
        IMAGE_EXTENSIONS = %w[.jpg .jpeg .png .gif .webp .avif .svg].freeze

        # 20 MB cap per image. Larger than the engine's default 8 MB
        # because some Substack hero images come through close to
        # 10–15 MB pre-optimisation. The build's image pipeline will
        # downsize them after import.
        MAX_IMAGE_BYTES = 20 * 1024 * 1024

        attr_reader :warnings

        def initialize(bundle_dir:, logger: nil)
          @bundle_dir = bundle_dir
          @logger     = logger
          @warnings   = []
          @cache      = {} # url → local filename, so repeated refs share a file
          @taken      = Set.new # local filenames already used in this bundle
        end

        # Resolve a remote image URL to a local filename. On success,
        # downloads the file into the bundle dir and returns the
        # local filename. On failure, records a warning and returns
        # nil (caller leaves the URL alone).
        def fetch(url)
          return nil if url.to_s.empty?
          return @cache[url] if @cache.key?(url)

          unless url.match?(%r{\Ahttps?://}i)
            # Not a remote URL — caller should leave it alone.
            return nil
          end

          local = download(url)
          @cache[url] = local
          local
        rescue StandardError => e
          warn("Failed to download #{url}: #{e.class}: #{e.message}")
          @cache[url] = nil
          nil
        end

        private

        require 'set'

        def download(url)
          uri = URI(url)
          ext = extension_for(uri)
          # Filename strategy: prefer the source's basename, fall
          # back to a short content hash if the URL doesn't carry
          # one (image-CDN URLs often look like `…/fetch/abcdef`
          # with no extension or filename in the path).
          base = base_for(uri)
          filename = unique_filename("#{base}#{ext}")

          res = Abqari::HttpSafe.get(uri, max_bytes: MAX_IMAGE_BYTES,
                                          headers: { 'User-Agent' => 'abqari-importer' })
          unless res.success?
            warn("HTTP #{res.code} for #{url}")
            return nil
          end

          FileUtils.mkdir_p(@bundle_dir)
          path = File.join(@bundle_dir, filename)
          File.binwrite(path, res.body)
          @logger&.call("    ↓ #{filename} (#{format_size(res.body.bytesize)})")
          filename
        end

        # Pick the best available filename base from the URL. In
        # priority order:
        #   1. The last path segment, stripped of its extension —
        #      gives us human-readable names where the source
        #      includes them (e.g. `…/hero-shot.jpg` → `hero-shot`).
        #   2. A short content hash of the URL — stable across
        #      runs so re-imports don't churn filenames.
        def base_for(uri)
          last = File.basename(uri.path.to_s)
          last = last.sub(/\.[a-z0-9]+\z/i, '') if last
          base = SlugNormalizer.normalize(last)
          base = "img-#{Digest::SHA1.hexdigest(uri.to_s)[0, 8]}" if base.empty?
          base
        end

        def extension_for(uri)
          ext = File.extname(uri.path.to_s).downcase
          # Substack image-fetch URLs often end with `/fetch/$$$EXT-jpeg/…`
          # or have no extension at all — default to `.jpg`. We
          # can't reliably sniff content-type without HEAD-requesting
          # first, and one extra round-trip per image is expensive.
          # `.jpg` is the safe default because the image pipeline
          # re-encodes everything to AVIF/WebP anyway.
          ext = '.jpg' unless IMAGE_EXTENSIONS.include?(ext)
          ext
        end

        def unique_filename(name)
          # Two-pass uniqueness: the bundle might already contain
          # a file with the same name from a previous post (rare —
          # bundles are per-post) or from the import's own previous
          # download (common — `hero.jpg` is a popular filename).
          base = File.basename(name, '.*')
          ext  = File.extname(name)
          candidate = name
          n = 2
          while @taken.include?(candidate) || File.exist?(File.join(@bundle_dir, candidate))
            candidate = "#{base}-#{n}#{ext}"
            n += 1
          end
          @taken << candidate
          candidate
        end

        def format_size(bytes)
          return "#{bytes}B" if bytes < 1024
          return "#{(bytes / 1024.0).round(1)}KB" if bytes < 1024 * 1024
          "#{(bytes / 1_048_576.0).round(2)}MB"
        end

        def warn(message)
          @warnings << message
          @logger&.call("    ⚠ #{message}")
        end
      end
    end
  end
end

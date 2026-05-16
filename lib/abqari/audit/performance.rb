# frozen_string_literal: true

module Abqari
  class Audit
    # Performance rule. Flags pages whose total image payload would
    # punish a mobile visitor — the most common cause of bad Lighthouse
    # scores on otherwise-clean static sites.
    #
    # Two thresholds, both per-page:
    #   - Total image bytes on a page (the page's complete image
    #     payload across all `<img>` and `<picture><source>` URLs
    #     pointing at same-origin paths). Warn over 1 MB, error over
    #     3 MB.
    #   - Single-image bytes. A 5 MB hero in an otherwise-light page
    #     defeats the whole pipeline. Warn at 500 KB, error at 1 MB.
    #
    # Skip pages with no images entirely. Redirect stubs are skipped.
    class Performance < Rule
      PAGE_TOTAL_WARN  = 1_000_000  # 1 MB
      PAGE_TOTAL_ERROR = 3_000_000  # 3 MB
      SINGLE_WARN      = 500_000    # 500 KB
      SINGLE_ERROR     = 1_000_000  # 1 MB

      def run
        html_files.each do |file|
          html = File.read(file, encoding: 'UTF-8')
          next if html =~ /<meta\s+http-equiv=["']refresh/i

          url = page_url(file)
          image_paths = extract_image_urls(html)
          next if image_paths.empty?

          sizes = image_paths.filter_map { |path| size_for(path) }
          flag_heavy_singles(url, sizes)
          flag_heavy_page_total(url, sizes)
        end
      end

      private

      # Pull every `src="…"` and `srcset="…, …, …"` reference that
      # looks like a same-origin image path (`/...` or relative). We
      # only stat same-origin assets — external CDN images aren't
      # something the audit can size locally.
      def extract_image_urls(html)
        urls = []

        html.scan(/<img\s+[^>]*?src="([^"]+)"/i) { urls << ::Regexp.last_match(1) }
        html.scan(/<source\s+[^>]*?srcset="([^"]+)"/i) do |srcset,|
          srcset[0].to_s.split(',').each do |entry|
            url, = entry.strip.split(/\s+/, 2)
            urls << url if url
          end
        end

        urls.uniq.reject { |u| u.empty? || u.start_with?('http://', 'https://', 'data:', '#') }
      end

      def size_for(url)
        path = File.join(@site.output_dir, url.sub(%r{\A/}, ''))
        return nil unless File.exist?(path) && File.file?(path)

        [url, File.size(path)]
      end

      def flag_heavy_singles(page_url, sizes)
        sizes.each do |url, bytes|
          severity = if bytes >= SINGLE_ERROR    then 'error'
                     elsif bytes >= SINGLE_WARN  then 'warn'
                     end
          next unless severity

          add(category: 'perf', severity: severity, location: page_url,
              message: "Image #{url} is #{format_kb(bytes)} (over the #{severity == 'error' ? '1 MB' : '500 KB'} threshold)",
              suggestion: "Enable `images.optimise: true` in config/site.yml and rebuild, " \
                          "or pre-compress this asset. AVIF at quality 50 typically saves 60–80% on photos.")
        end
      end

      def flag_heavy_page_total(page_url, sizes)
        # Sum the smallest variant per logical image — a `<picture>`
        # block typically lists multiple widths for the same image
        # under different filenames, but a visitor only fetches one
        # per breakpoint. Take the smallest per basename as a fair
        # proxy for "what the visitor actually downloads".
        per_basename = sizes.group_by { |url, _| basename_key(url) }
        effective = per_basename.values.map { |group| group.map { |_, b| b }.min || 0 }
        total = effective.sum

        severity = if total >= PAGE_TOTAL_ERROR  then 'error'
                   elsif total >= PAGE_TOTAL_WARN then 'warn'
                   end
        return unless severity

        threshold = severity == 'error' ? '3 MB' : '1 MB'
        add(category: 'perf', severity: severity, location: page_url,
            message: "Total image weight on this page is #{format_kb(total)} (over #{threshold})",
            suggestion: 'Reduce hero/figure count, or compress further. Consider lazy-loading below-fold images via `loading="lazy"` (already default on auto-optimised images).')
      end

      def basename_key(url)
        # Strip the `-<width>.<hash>` fingerprint suffix so variants of
        # the same source coalesce: hero-1200.abc123.jpg → hero.jpg
        # and hero-800.def456.avif → hero.avif both bucket under their
        # base filename.
        bn = File.basename(url)
        ext = File.extname(bn)
        bn.sub(/-\d+\.[0-9a-f]+#{Regexp.escape(ext)}\z/, ext)
      end

      def format_kb(bytes)
        if bytes >= 1_000_000
          format('%.1f MB', bytes / 1_000_000.0)
        else
          format('%d KB', bytes / 1_000.0)
        end
      end
    end
  end
end

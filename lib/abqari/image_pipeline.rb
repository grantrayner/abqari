# frozen_string_literal: true

require 'digest'
require 'fileutils'
require 'set'
require 'shellwords'

begin
  require 'vips'
rescue LoadError
  # ruby-vips not installed (or libvips missing). The pipeline detects
  # this in `detect_backend` and falls back to the shell processor.
end

module Abqari
  # Build-time image optimisation. The pipeline resizes raster images
  # into multiple widths, encodes them as AVIF + WebP + an optimised
  # original-format fallback, and rewrites `<img>` tags into
  # `<picture>` elements that serve the smallest variant the visitor's
  # browser can decode.
  #
  # Two source locations are covered:
  #
  #   1. `app/assets/images/` — site-wide imagery used from ERB via
  #      `picture_tag('hero.jpg', alt: '…')`. Variants land at
  #      `_site/assets/images/<basename>-<width>.<hash>.<fmt>` and are
  #      shared across pages.
  #
  #   2. Bundle directories (`content/posts/<slug>/`, etc.) — hero
  #      and body images that live next to a post's `index.md`.
  #      Variants land at `_site/<page.url>/<basename>-<width>.<hash>.<fmt>`
  #      and the post body's `<img src="hero.jpg">` is rewritten to a
  #      `<picture>` element automatically during `post_process_html`.
  #
  # Defaults are tuned for the publisher case (camera photos, prose
  # leds): AVIF first (~50% smaller than JPEG), WebP fallback (~30%
  # smaller), JPEG passthrough for browsers without modern format
  # support. Per-format quality lands at the standard perceptual-
  # equivalence points — AVIF 50, WebP 80, JPEG 85. Metadata stripped
  # by default (EXIF, GPS, embedded thumbnails — a 50–500 KB win and
  # a privacy bonus).
  #
  # Upscaling is skipped. A 600-pixel-wide source with
  # `widths: [400, 800, 1200]` produces variants at 400 and 600 (the
  # source's native width) — the 800 and 1200 entries are dropped
  # rather than emitted as upscaled-blurrier-and-larger files.
  class ImagePipeline
    # Raster sources the pipeline handles. SVG is excluded — vector,
    # nothing to thumbnail.
    IMAGE_EXTENSIONS = %w[.jpg .jpeg .png .gif .webp .avif].freeze

    DEFAULTS = {
      'optimise'          => true,
      'processor'         => 'auto', # auto | vips-native | vips | imagemagick
      # AVIF first so browsers pick it ahead of WebP — AVIF is 20–50%
      # smaller at equal quality and has universal modern-browser
      # support as of 2026 (Safari 16.4+, Chrome/Edge 85+, Firefox
      # 113+). Older browsers fall through to WebP, then the original.
      'formats'           => %w[avif webp],
      'widths'            => [400, 800, 1200],
      # Per-format quality. AVIF's quality scale is perceptually
      # different from JPEG/WebP — 50 produces files smaller than WebP
      # at 80 with comparable quality. Applying one number across all
      # formats (the legacy behaviour) made AVIF files LARGER than
      # WebP, defeating the format's purpose.
      'quality'           => { 'avif' => 50, 'webp' => 80, 'original' => 85 },
      'sizes'             => '(min-width: 768px) 50vw, 100vw',
      'source_dir'        => 'app/assets/images',
      # Strip EXIF, GPS, embedded thumbnails, ICC profiles. Photographers
      # who need to preserve metadata (portfolio sites that surface
      # camera info) can flip this off.
      'preserve_metadata' => false
    }.freeze

    HASH_LENGTH = 10

    def initialize(site)
      @site = site
      @config = merged_config(site.config['images'])
      @backend = nil
      @variants_cache = {}
      @cache_mutex = Mutex.new
      @registry = {}
      @registry_mutex = Mutex.new
      @url_to_bundle_dir = nil
      @config['formats'] = prune_unsupported_formats(@config['formats'])
    end

    def enabled?
      @config['optimise'] == true && backend
    end

    def backend
      @backend = detect_backend if @backend.nil? && !@backend_resolved
      @backend_resolved = true
      @backend
    end

    # Phase entry point — called from Site#build BEFORE render. Copies
    # `app/assets/images/` originals through (always — needed for the
    # passthrough case), then if optimisation is on, walks every known
    # image source and registers it in the URL → variants map so
    # `post_process_html` can rewrite `<img>` tags during render.
    def process
      copy_originals
      return unless enabled?

      build_url_to_bundle_dir_map
      register_known_sources
    end

    # Resolve a URL to its on-disk source path, or nil if we don't
    # recognise it. Used by post-processing to figure out which `<img
    # src=...>` tags to rewrite.
    def source_path_for(url)
      @registry_mutex.synchronize { @registry[url]&.dig(:source_path) }
    end

    # picture_tag — emits a `<picture>` block for an asset image. The
    # `source` argument is resolved under `app/assets/images/` (the
    # legacy ERB helper convention). For bundle images, prefer the
    # automatic rewrite in `post_process_html` or the
    # `bundle_picture_tag` helper.
    def picture_tag(source, alt: '', sizes: nil, widths: nil)
      sizes ||= @config['sizes']
      requested_widths = (widths || @config['widths']).sort

      source_path = absolute_source(source)
      unless File.exist?(source_path)
        # Source doesn't exist locally — emit a literal <img> with the
        # source value as-is (allows authors to use full URLs).
        return %(<img src="#{escape_attr(source)}" alt="#{escape_attr(alt)}" loading="lazy" decoding="async">)
      end

      unless enabled?
        copy_passthrough(source_path, '/assets/images/')
        dims = dimension_attrs(source_path)
        url = "/assets/images/#{File.basename(source_path)}"
        return %(<img src="#{escape_attr(url)}" alt="#{escape_attr(alt)}"#{dims} loading="lazy" decoding="async">)
      end

      url_prefix = '/assets/images/'
      target_dir = File.join(@site.output_dir, 'assets', 'images')
      register_source("#{url_prefix}#{File.basename(source_path)}", source_path, target_dir, url_prefix)
      render_picture("#{url_prefix}#{File.basename(source_path)}", alt, sizes, requested_widths)
    end

    # Emit a `<picture>` block for a URL that's been registered with
    # the pipeline (asset or bundle). Returns nil if the URL isn't
    # registered — callers fall back to whatever they were going to
    # do otherwise (a plain `<img>`, the legacy sibling-lookup, etc.).
    #
    # Used by `bundle_picture_tag` in render_context to opt explicit
    # layout-level uses into the pipeline.
    def picture_tag_for_url(url, alt:, sizes: nil, widths: nil, attrs: {})
      return nil unless enabled?
      return nil unless source_path_for(canonical_url(url))

      sizes ||= @config['sizes']
      widths = (widths || @config['widths']).sort
      render_picture(canonical_url(url), alt, sizes, widths, extra_attrs: attrs)
    end

    # Rewrite `<img>` tags whose `src` we know how to optimise. Asset
    # URLs and bundle URLs are both routed through the registry — any
    # `<img src=...>` that maps to a registered source gets replaced
    # with a `<picture>` element. Unknown images pass through
    # unchanged.
    #
    # `page:` is accepted for symmetry with other post-processors but
    # the registry lookup is URL-based (we already have a complete
    # map by `Site#build` time) so the page itself isn't needed here.
    def post_process_html(html, page: nil)
      return html unless enabled?

      html.gsub(/<img\s+([^>]*?)>/m) do |match|
        attrs = ::Regexp.last_match(1)
        src = attrs[/src="([^"]+)"/, 1]
        next match unless src

        registered_url = canonical_url(src)
        next match unless source_path_for(registered_url)

        alt = attrs[/alt="([^"]*)"/, 1] || ''
        render_picture(registered_url, alt, @config['sizes'], @config['widths'].sort)
      end
    end

    private

    # ----------------------------------------------------------------
    # Config + back-compat
    # ----------------------------------------------------------------

    # Apply DEFAULTS to user config, with care for the `quality` key —
    # which can be a scalar (legacy: applies to all formats) or a hash
    # (per-format). Scalar gets expanded to a per-format hash so call
    # sites can do a uniform lookup.
    def merged_config(user)
      user ||= {}
      result = DEFAULTS.merge(user)
      if user.key?('quality')
        q = user['quality']
        result['quality'] = if q.is_a?(Hash)
                              DEFAULTS['quality'].merge(q.transform_keys(&:to_s))
                            elsif q.is_a?(Numeric)
                              { 'avif' => q, 'webp' => q, 'original' => q }
                            else
                              DEFAULTS['quality']
                            end
      end
      result
    end

    def quality_for(format)
      @config['quality'][format.to_s] || @config['quality']['original'] || 80
    end

    # ----------------------------------------------------------------
    # Format capability pre-flight
    # ----------------------------------------------------------------

    # Probe each configured output format once per process. Drop the
    # ones the host environment can't actually write — typically AVIF
    # on stripped-down libvips builds that lack the libheif AV1 encoder
    # plugin (the `Vips::Error: heifsave: Unsupported compression`
    # symptom on Ubuntu 24.04 without `libheif-plugin-aomenc`).
    #
    # Without this guard, the pipeline raises mid-build for every
    # image, the rendered site is corrupted, and the build fails. With
    # it, we emit a one-line warning, drop the format from the formats
    # list, and the pipeline produces a `<picture>` element with the
    # remaining formats — site still ships, just without AVIF variants.
    #
    # Memoised at the class level so the actual probe runs at most
    # once per process even when many ImagePipeline instances are
    # created (e.g. across the test suite). The probe is cheap, but
    # cold-start codec init for HEIF/AVIF can take a second or two —
    # repeating it per-test would be slow.
    def prune_unsupported_formats(formats)
      return formats unless defined?(::Vips)
      formats.select do |fmt|
        if format_writable?(fmt)
          true
        else
          warn_unsupported_format(fmt)
          false
        end
      end
    end

    def format_writable?(format)
      return true if format == 'original'
      capability = ImagePipeline.format_capabilities[format.to_s]
      return capability unless capability.nil?
      ImagePipeline.format_capabilities[format.to_s] = probe_format(format)
    end

    # The actual probe — a tiny in-memory write. Run at most once per
    # format per process via the class-level memo above.
    def probe_format(format)
      probe = ::Vips::Image.black(2, 2)
      probe.write_to_buffer(".#{format}")
      true
    rescue ::Vips::Error
      false
    rescue StandardError
      # Any non-Vips failure (load error, FFI weirdness): bias toward
      # "yes, try it" — the real write will surface a clearer error
      # than swallowing the probe failure here.
      true
    end

    def warn_unsupported_format(format)
      return if ImagePipeline.warned_formats.include?(format.to_s)
      ImagePipeline.warned_formats << format.to_s
      Log.warn "Image pipeline: #{format.upcase} unsupported by this libvips " \
               "build (likely missing codec plugin) — skipping #{format.upcase} variants. " \
               "On Ubuntu 24.04 install `libheif1 libheif-plugin-aomenc` to enable AVIF."
    end

    # Class-level caches for probe results + already-warned formats.
    # Survives across ImagePipeline instances within a single Ruby
    # process.
    class << self
      def format_capabilities
        @format_capabilities ||= {}
      end

      def warned_formats
        @warned_formats ||= Set.new
      end
    end

    # ----------------------------------------------------------------
    # Backend detection
    # ----------------------------------------------------------------

    def detect_backend
      strip = !@config['preserve_metadata']
      requested = @config['processor'].to_s

      case requested
      when 'vips-native'
        return VipsBackend.new(strip: strip) if vips_loaded?

        Log.warn 'Abqari: images.processor=vips-native but ruby-vips not loaded. Falling back to auto-detect.'
      when 'vips'
        return ShellBackend.new('vips', strip: strip) if which('vips')

        Log.warn 'Abqari: images.processor=vips but vips CLI not on PATH. Falling back to auto-detect.'
      when 'imagemagick'
        return ShellBackend.new('magick', strip: strip) if which('magick')

        Log.warn 'Abqari: images.processor=imagemagick but magick CLI not on PATH. Falling back to auto-detect.'
      end

      # Auto-detect order: native ruby-vips > shell vips > shell magick.
      return VipsBackend.new(strip: strip)  if vips_loaded?
      return ShellBackend.new('vips', strip: strip) if which('vips')
      return ShellBackend.new('magick', strip: strip) if which('magick')

      Log.warn 'Abqari: images.optimise=true but no image processor available. ' \
               "Install libvips (`brew install vips` / `apt install libvips42`) " \
               "or imagemagick. Falling back to passthrough — originals only."
      nil
    end

    def vips_loaded?
      defined?(::Vips) && ::Vips.respond_to?(:version_string)
    end

    def which(cmd)
      ENV['PATH'].to_s.split(File::PATH_SEPARATOR).any? do |dir|
        File.executable?(File.join(dir, cmd))
      end
    end

    # ----------------------------------------------------------------
    # Source registration — populates the URL → source-path map so
    # post_process_html can look up image references during render.
    # ----------------------------------------------------------------

    def build_url_to_bundle_dir_map
      @url_to_bundle_dir = {}
      @site.all_pages.each do |page|
        next unless page.respond_to?(:bundle_dir) && page.bundle_dir
        next unless page.respond_to?(:url) && page.url

        @url_to_bundle_dir[page.url] = page.bundle_dir
      end
    end

    def register_known_sources
      register_dir(asset_source_dir, '/assets/images/',
                   File.join(@site.output_dir, 'assets', 'images'))

      @url_to_bundle_dir.each do |page_url, bundle_dir|
        target_dir = PathSafe.join_under(@site.output_dir, page_url.sub(%r{\A/}, '').chomp('/'))
        register_dir(bundle_dir, page_url, target_dir)
      end

      register_flat_collection_sources
    end

    def register_flat_collection_sources
      @site.collections.each do |_name, cfg|
        next if cfg['bundle'] != false
        next unless cfg.fetch('enabled', true)

        source_dir = File.join(@site.site_root, cfg['source'].to_s)
        next unless Dir.exist?(source_dir)

        url_prefix = "/#{cfg['permalink'].to_s.sub(/:slug.*/, '').sub(%r{\A/}, '').chomp('/')}/"
        next if url_prefix == '//'

        target_dir = PathSafe.join_under(@site.output_dir, url_prefix.sub(%r{\A/}, '').chomp('/'))
        register_dir(source_dir, url_prefix, target_dir)
      end
    end

    def register_dir(source_dir, url_prefix, target_dir)
      return unless Dir.exist?(source_dir)

      Dir.glob(File.join(source_dir, '*')).each do |entry|
        next if File.directory?(entry)
        next if File.basename(entry).start_with?('.')
        next unless IMAGE_EXTENSIONS.include?(File.extname(entry).downcase)
        next if @site.external_symlink?(entry)

        url = "#{url_prefix}#{File.basename(entry)}"
        register_source(url, entry, target_dir, url_prefix)
      end
    end

    def register_source(url, source_path, target_dir, url_prefix)
      @registry_mutex.synchronize do
        @registry[url] ||= {
          source_path: source_path,
          target_dir: target_dir,
          url_prefix: url_prefix,
          dimensions: nil
        }
      end
    end

    def asset_source_dir
      File.join(@site.site_root, @config['source_dir'])
    end

    def absolute_source(name)
      File.join(asset_source_dir, File.basename(name))
    end

    # Strip query/fragment + collapse internal `../` for lookup. URLs
    # in rendered HTML are absolute and already normalised, so this is
    # mainly a defensive trim.
    def canonical_url(url)
      url.split(/[?#]/, 2).first
    end

    # ----------------------------------------------------------------
    # Picture-element rendering
    # ----------------------------------------------------------------

    def render_picture(url, alt, sizes, widths, extra_attrs: {})
      entry = @registry_mutex.synchronize { @registry[url] }
      source_path = entry[:source_path]
      target_dir  = entry[:target_dir]
      url_prefix  = entry[:url_prefix]

      source_w, source_h = ensure_dimensions(url, source_path)
      effective_widths = compute_effective_widths(widths, source_w)
      return passthrough_img(url, alt, source_w, source_h, extra_attrs) if effective_widths.empty?

      formats_to_emit = @config['formats']
      source_tags = formats_to_emit.filter_map do |fmt|
        srcset = build_srcset(source_path, target_dir, url_prefix, fmt, effective_widths)
        next if srcset.empty?

        %(<source type="image/#{fmt}" srcset="#{srcset}" sizes="#{sizes}">)
      end

      fallback_width = effective_widths.max
      fallback_url   = variant_for(source_path, target_dir, url_prefix, fallback_width, 'original')
      width_attr     = fallback_width
      height_attr    = source_w.positive? ? (fallback_width * source_h / source_w.to_f).round : nil

      attrs = +%(src="#{escape_attr(fallback_url)}" alt="#{escape_attr(alt)}")
      attrs << %( width="#{width_attr}") if width_attr
      attrs << %( height="#{height_attr}") if height_attr
      # Caller-supplied attrs (class, loading="eager", fetchpriority, etc.)
      # are appended last so they win over defaults. `loading` and
      # `decoding` default below; pass them in extra_attrs to override.
      extra_attrs.each { |k, v| attrs << %( #{escape_attr(k.to_s)}="#{escape_attr(v.to_s)}") }
      attrs << %( loading="lazy") unless extra_attrs.key?(:loading) || extra_attrs.key?('loading')
      attrs << %( decoding="async") unless extra_attrs.key?(:decoding) || extra_attrs.key?('decoding')

      <<~HTML.chomp
        <picture>
          #{source_tags.join("\n  ")}
          <img #{attrs}>
        </picture>
      HTML
    end

    # Emit a plain `<img>` for the passthrough case (no optimisation,
    # or no widths survived the upscale guard).
    def passthrough_img(url, alt, source_w, source_h, extra_attrs = {})
      dims = source_w && source_h ? %( width="#{source_w}" height="#{source_h}") : ''
      attrs = +%(src="#{escape_attr(url)}" alt="#{escape_attr(alt)}"#{dims})
      extra_attrs.each { |k, v| attrs << %( #{escape_attr(k.to_s)}="#{escape_attr(v.to_s)}") }
      attrs << %( loading="lazy") unless extra_attrs.key?(:loading) || extra_attrs.key?('loading')
      attrs << %( decoding="async") unless extra_attrs.key?(:decoding) || extra_attrs.key?('decoding')
      %(<img #{attrs}>)
    end

    def build_srcset(source_path, target_dir, url_prefix, format, widths)
      widths.map do |w|
        "#{variant_for(source_path, target_dir, url_prefix, w, format)} #{w}w"
      end.join(', ')
    end

    # Skip-if-smaller logic. Drop any requested width that's >= source
    # width (no point upscaling — bigger file, blurrier output), and
    # add the source width itself so the largest variant is always
    # the original's native resolution.
    def compute_effective_widths(requested, source_w)
      return requested if source_w.nil? || source_w.zero?

      kept = requested.select { |w| w < source_w }
      kept << source_w
      kept.uniq.sort
    end

    # ----------------------------------------------------------------
    # Variant generation
    # ----------------------------------------------------------------

    def variant_for(source_path, target_dir, url_prefix, width, format)
      cache_key = [source_path, width, format].join('|')

      @cache_mutex.synchronize do
        return @variants_cache[cache_key] if @variants_cache[cache_key]
      end

      ext = format == 'original' ? File.extname(source_path).delete('.') : format
      hash = Digest::SHA1.hexdigest(
        "#{source_path}:#{width}:#{format}:#{quality_for(format)}:#{File.mtime(source_path).to_i}"
      )[0, HASH_LENGTH]

      basename = File.basename(source_path, File.extname(source_path))
      out_filename = "#{basename}-#{width}.#{hash}.#{ext}"
      FileUtils.mkdir_p(target_dir)
      out_path = File.join(target_dir, out_filename)

      unless File.exist?(out_path)
        backend.thumbnail(source_path, out_path, width, format, quality_for(format))
      end

      url = "#{url_prefix}#{out_filename}"
      @cache_mutex.synchronize { @variants_cache[cache_key] = url }
      url
    end

    def ensure_dimensions(url, source_path)
      entry = @registry_mutex.synchronize { @registry[url] }
      return entry[:dimensions] if entry[:dimensions]

      dims = backend ? backend.dimensions(source_path) : read_dimensions(source_path)
      dims ||= [0, 0]
      @registry_mutex.synchronize { @registry[url][:dimensions] = dims if @registry[url] }
      dims
    end

    # ----------------------------------------------------------------
    # Pure-Ruby dimension reader — used as a fallback when no backend
    # is available, and as the primary path for header-readable
    # formats (avoids spawning a process just to read width/height).
    # ----------------------------------------------------------------

    def read_dimensions(path)
      return nil unless File.exist?(path)

      case File.extname(path).downcase
      when '.png'          then read_png_dimensions(path)
      when '.jpg', '.jpeg' then read_jpeg_dimensions(path)
      when '.gif'          then read_gif_dimensions(path)
      end
    rescue StandardError
      nil
    end

    def read_png_dimensions(path)
      File.open(path, 'rb') do |f|
        f.read(16) # 8-byte signature + 4-byte length + 4-byte 'IHDR'
        f.read(8).unpack('NN') # width, height (4 bytes each, big-endian)
      end
    end

    def read_jpeg_dimensions(path)
      File.open(path, 'rb') do |f|
        f.read(2) # SOI marker FF D8
        loop do
          marker = f.read(2)&.unpack1('n')
          return nil unless marker

          # SOFn frame markers (excluding DHT, DAC, JPG).
          if (0xFFC0..0xFFCF).cover?(marker) && ![0xFFC4, 0xFFC8, 0xFFCC].include?(marker)
            f.read(3) # segment length (2) + sample precision (1)
            height, width = f.read(4).unpack('nn')
            return [width, height]
          end

          length = f.read(2)&.unpack1('n')
          return nil unless length

          f.read(length - 2)
        end
      end
    end

    def read_gif_dimensions(path)
      File.open(path, 'rb') do |f|
        f.read(6) # "GIF87a" or "GIF89a"
        f.read(4).unpack('vv') # width, height (2 bytes each, little-endian)
      end
    end

    # ----------------------------------------------------------------
    # Passthrough copy — for the no-optimisation case.
    # ----------------------------------------------------------------

    def copy_passthrough(source_path, _url_prefix)
      dest_dir = File.join(@site.output_dir, 'assets', 'images')
      FileUtils.mkdir_p(dest_dir)
      FileUtils.cp(source_path, File.join(dest_dir, File.basename(source_path)))
    end

    def copy_originals
      return unless Dir.exist?(asset_source_dir)

      dest_dir = File.join(@site.output_dir, 'assets', 'images')
      FileUtils.mkdir_p(dest_dir)
      Dir.glob(File.join(asset_source_dir, '*')).sort.each do |entry|
        next if File.directory?(entry) || File.basename(entry).start_with?('.')

        FileUtils.cp(entry, File.join(dest_dir, File.basename(entry)))
      end
    end

    def dimension_attrs(source_path)
      dims = read_dimensions(source_path) || (backend && backend.dimensions(source_path))
      return '' unless dims && dims[0]&.positive? && dims[1]&.positive?

      %( width="#{dims[0]}" height="#{dims[1]}")
    end

    def escape_attr(text)
      text.to_s.gsub('&', '&amp;').gsub('"', '&quot;').gsub('<', '&lt;')
    end
  end

  # ------------------------------------------------------------------
  # Backends — strategy pattern. Each implements `thumbnail` and
  # `dimensions`; ImagePipeline picks one in `detect_backend`.
  # ------------------------------------------------------------------

  class ImagePipeline
    # Native libvips via ruby-vips. Same operations as the shell
    # backend but no per-image process spawn — ~5–10× faster for
    # variant generation. Requires the `vips` gem AND the libvips C
    # library; if either is missing the pipeline falls back to the
    # shell backend automatically.
    class VipsBackend
      def initialize(strip:)
        @strip = strip
      end

      def name
        'vips-native'
      end

      def thumbnail(src, dest, width, format, quality)
        # `thumbnail` is libvips' high-level "load + resize + sharpen"
        # operation. It uses the demand-driven pipeline so memory is
        # bounded regardless of source resolution. EXIF / metadata
        # stripping is handled by the `strip:` flag on the writer —
        # no separate copy-and-clear pass needed.
        # `thumbnail` with width only preserves aspect ratio. No
        # height constraint needed; libvips computes the matching
        # height from the source.
        image = ::Vips::Image.thumbnail(src, width)

        case format
        when 'avif', 'webp'
          image.write_to_file(dest, Q: quality, strip: @strip)
        when 'original'
          ext = File.extname(dest).delete('.').downcase
          if %w[png gif].include?(ext)
            # PNG / GIF don't take a quality flag.
            image.write_to_file(dest, strip: @strip)
          else
            image.write_to_file(dest, Q: quality, strip: @strip)
          end
        else
          raise "Unknown format: #{format}"
        end
      end

      def dimensions(src)
        image = ::Vips::Image.new_from_file(src, access: :sequential)
        [image.width, image.height]
      rescue ::Vips::Error
        nil
      end
    end

    # Shell-out to `vips` or `magick` CLI. Used when ruby-vips isn't
    # available — slower per invocation (~150–300 ms each) but works
    # without the FFI dep.
    class ShellBackend
      def initialize(cli, strip:)
        @cli   = cli # 'vips' or 'magick'
        @strip = strip
      end

      def name
        "shell-#{@cli}"
      end

      def thumbnail(src, dest, width, format, quality)
        cmd = case @cli
              when 'vips'   then vips_cmd(src, dest, width, format, quality)
              when 'magick' then magick_cmd(src, dest, width, format, quality)
              end

        success = system(*cmd, out: File::NULL, err: File::NULL)
        raise "Image processing failed: #{cmd.shelljoin}" unless success
      end

      def dimensions(src)
        case @cli
        when 'vips'
          w = `vipsheader -f width #{src.shellescape} 2>/dev/null`.strip.to_i
          h = `vipsheader -f height #{src.shellescape} 2>/dev/null`.strip.to_i
          [w, h] if w.positive? && h.positive?
        when 'magick'
          out = `magick identify -format "%w %h" #{src.shellescape} 2>/dev/null`.strip
          dims = out.split.map(&:to_i)
          dims.size == 2 && dims.all?(&:positive?) ? dims : nil
        end
      end

      private

      def vips_cmd(src, dest, width, format, quality)
        # vips' load-option syntax accepts `[Q=…]` on the destination.
        # `-strip` would be `--strip-metadata` but that's been deprecated
        # in favour of explicit no-keep on the output writer; the
        # `[strip=true]` suffix is the supported form.
        opts = []
        opts << "Q=#{quality}" unless format == 'original' && %w[png gif].include?(File.extname(dest).delete('.'))
        opts << 'strip=true' if @strip
        output = opts.empty? ? dest : "#{dest}[#{opts.join(',')}]"
        ['vips', 'thumbnail', src, output, width.to_s]
      end

      def magick_cmd(src, dest, width, _format, quality)
        cmd = ['magick', src, '-resize', "#{width}x", '-quality', quality.to_s]
        cmd << '-strip' if @strip
        cmd << dest
        cmd
      end
    end
  end
end

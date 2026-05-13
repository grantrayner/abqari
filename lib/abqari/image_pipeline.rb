# frozen_string_literal: true

require 'digest'
require 'fileutils'
require 'shellwords'

module Abqari
  class ImagePipeline
    DEFAULTS = {
      'optimise' => false,
      'processor' => 'auto',          # auto | vips | imagemagick
      # AVIF first so browsers pick it ahead of WebP — AVIF is 20–50%
      # smaller at equal quality and has universal modern-browser
      # support as of 2026 (Safari 16.4+, Chrome/Edge 85+, Firefox
      # 113+). Older browsers fall through to WebP, then the original.
      'formats' => %w[avif webp],
      'widths' => [400, 800, 1200],
      'quality' => 80,
      'sizes' => '(min-width: 768px) 50vw, 100vw',
      'source_dir' => 'app/assets/images'
    }.freeze

    HASH_LENGTH = 10

    def initialize(site)
      @site = site
      @config = DEFAULTS.merge(site.config['images'] || {})
      @processor = nil
      @processed = {}
      @processed_mutex = Mutex.new
    end

    def enabled?
      @config['optimise'] == true && processor
    end

    def process
      copy_originals
    end

    def picture_tag(source, alt: '', sizes: nil, widths: nil)
      sizes ||= @config['sizes']
      widths = (widths || @config['widths']).sort

      if enabled? && local_source?(source)
        render_picture(source, alt, sizes, widths)
      else
        url = local_source?(source) ? "/#{@config['source_dir'].sub(%r{\Aapp/}, 'assets/')}/#{File.basename(source)}" : source
        copy_passthrough(source) if local_source?(source)
        dims = local_source?(source) ? dimension_attrs(source) : ''
        %(<img src="#{url}" alt="#{escape(alt)}"#{dims} loading="lazy" decoding="async">)
      end
    end

    def post_process_html(html)
      return html unless enabled?

      html.gsub(/<img\s+([^>]*?)>/) do |match|
        attrs = ::Regexp.last_match(1)
        src = attrs[/src="([^"]+)"/, 1]
        next match unless src && local_url?(src)

        alt = attrs[/alt="([^"]*)"/, 1] || ''
        picture_tag(rebase(src), alt: alt)
      end
    end

    def processor
      @processor ||= detect_processor
    end

    private

    def detect_processor
      requested = @config['processor']
      return requested if requested != 'auto' && which(requested == 'imagemagick' ? 'magick' : requested)

      return 'vips' if which('vips')
      return 'imagemagick' if which('magick')

      Log.warn 'Abqari: images.optimise=true but neither `vips` nor `magick` is on PATH. Falling back to passthrough.'
      nil
    end

    def which(cmd)
      ENV['PATH'].split(File::PATH_SEPARATOR).any? { |dir| File.executable?(File.join(dir, cmd)) }
    end

    def local_source?(name)
      File.exist?(absolute_source(name))
    end

    def absolute_source(name)
      # User images live in the site root (e.g. `app/assets/img/...`).
      File.join(@site.site_root, @config['source_dir'], File.basename(name))
    end

    def local_url?(url)
      return false unless url.start_with?('/') || !url.include?('://')

      basename = File.basename(url)
      File.exist?(absolute_source(basename))
    end

    def rebase(url)
      File.basename(url)
    end

    def render_picture(source, alt, sizes, widths)
      formats = @config['formats'] + ['original']
      sources_html = formats.map { |fmt| source_tag(source, fmt, widths, sizes) }.compact.join("\n  ")

      largest = widths.max
      fallback_url = process_variant(source, largest, 'original')
      orig_w, orig_h = read_dimensions(absolute_source(source))
      width_h_attrs = orig_w && orig_h ? %( width="#{largest}" height="#{(largest * orig_h / orig_w.to_f).round}") : ''

      <<~HTML.chomp
        <picture>
          #{sources_html}
          <img src="#{fallback_url}" alt="#{escape(alt)}"#{width_h_attrs} loading="lazy" decoding="async">
        </picture>
      HTML
    end

    def dimension_attrs(source)
      dims = read_dimensions(absolute_source(source))
      return '' unless dims

      width, height = dims
      %( width="#{width}" height="#{height}")
    end

    def source_tag(source, format, widths, sizes)
      type = format == 'original' ? mime_type(source) : "image/#{format}"
      return nil if format == 'original' # original goes in <img>, not a <source>

      srcset = widths.map { |w| "#{process_variant(source, w, format)} #{w}w" }.join(', ')
      %(<source type="#{type}" srcset="#{srcset}" sizes="#{sizes}">)
    end

    def process_variant(source, width, format)
      cache_key = [source, width, format].join('|')

      @processed_mutex.synchronize do
        return @processed[cache_key] if @processed[cache_key]
      end

      ext = format == 'original' ? File.extname(source).delete('.') : format
      hash = Digest::SHA1.hexdigest("#{source}:#{width}:#{format}:#{File.mtime(absolute_source(source)).to_i}")[0, HASH_LENGTH]
      basename = File.basename(source, File.extname(source))
      out_filename = "#{basename}-#{width}.#{hash}.#{ext}"
      out_dir = File.join(@site.output_dir, 'assets', 'images')
      FileUtils.mkdir_p(out_dir)
      out_path = File.join(out_dir, out_filename)

      run_processor(absolute_source(source), out_path, width, format) unless File.exist?(out_path)

      url = "/assets/images/#{out_filename}"
      @processed_mutex.synchronize { @processed[cache_key] = url }
      url
    end

    def run_processor(src, dest, width, format)
      cmd = case processor
            when 'vips'        then vips_cmd(src, dest, width, format)
            when 'imagemagick' then magick_cmd(src, dest, width, format)
            end

      success = system(*cmd, out: File::NULL, err: File::NULL)
      raise "Image processing failed: #{cmd.shelljoin}" unless success
    end

    def vips_cmd(src, dest, width, format)
      quality = @config['quality']
      output = format == 'original' ? dest : "#{dest}[Q=#{quality}]"
      ['vips', 'thumbnail', src, output, width.to_s]
    end

    def magick_cmd(src, dest, width, _format)
      ['magick', src, '-resize', "#{width}x", '-quality', @config['quality'].to_s, dest]
    end

    # Reads image dimensions in pure Ruby for the common formats — no processor
    # required. Falls back to vipsheader/identify for anything we don't parse.
    def read_dimensions(path)
      return nil unless File.exist?(path)

      case File.extname(path).downcase
      when '.png'          then read_png_dimensions(path)
      when '.jpg', '.jpeg' then read_jpeg_dimensions(path)
      when '.gif'          then read_gif_dimensions(path)
      else                      shell_dimensions(path)
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

          # SOFn frame markers (excluding DHT, DAC, JPG)
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

    def shell_dimensions(path)
      return nil unless processor

      case processor
      when 'vips'
        w = `vipsheader -f width #{path.shellescape} 2>/dev/null`.strip.to_i
        h = `vipsheader -f height #{path.shellescape} 2>/dev/null`.strip.to_i
        [w, h] if w.positive? && h.positive?
      when 'imagemagick'
        out = `magick identify -format "%w %h" #{path.shellescape} 2>/dev/null`.strip
        out.split.map(&:to_i)
      end
    end

    def copy_passthrough(source)
      src = absolute_source(source)
      return unless File.exist?(src)

      dest_dir = File.join(@site.output_dir, 'assets', 'images')
      FileUtils.mkdir_p(dest_dir)
      FileUtils.cp(src, File.join(dest_dir, File.basename(source)))
    end

    def copy_originals
      src_dir = File.join(@site.site_root, @config['source_dir'])
      return unless Dir.exist?(src_dir)

      dest_dir = File.join(@site.output_dir, 'assets', 'images')
      FileUtils.mkdir_p(dest_dir)
      Dir.glob(File.join(src_dir, '*')).sort.each do |entry|
        next if File.directory?(entry) || File.basename(entry).start_with?('.')

        FileUtils.cp(entry, File.join(dest_dir, File.basename(entry)))
      end
    end

    def mime_type(source)
      case File.extname(source).downcase
      when '.jpg', '.jpeg' then 'image/jpeg'
      when '.png'          then 'image/png'
      when '.gif'          then 'image/gif'
      when '.webp'         then 'image/webp'
      when '.avif'         then 'image/avif'
      else 'application/octet-stream'
      end
    end

    def escape(text)
      text.to_s.gsub('&', '&amp;').gsub('"', '&quot;').gsub('<', '&lt;')
    end
  end
end

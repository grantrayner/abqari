# frozen_string_literal: true

require 'digest'
require 'fileutils'

module Abqari
  class AssetPipeline
    OUTPUT_SUBDIR = 'assets'
    HASH_LENGTH = 10
    DEFAULT_THEME = 'minimal'
    BUNDLE_LOGICAL = 'css/bundle.css'
    # Extensions that get minified before fingerprinting (production
    # only — dev keeps sources readable for devtools).
    MINIFY_KINDS = { '.css' => :css, '.js' => :js }.freeze
    # Themes that bring their own structural CSS. Mirror of the
    # `_head.html.erb` conditional that skips `_common.css`.
    NO_COMMON_THEMES = %w[bootstrap none].freeze

    def initialize(site)
      @site = site
      @paths = {}
      @sources = {}
    end

    def process
      # Processing order matters — later passes overwrite earlier ones
      # on logical-path conflict (same filename).
      #
      # Within a category (theme vs app/assets), engine first, site
      # second — so a site can override a theme file or a structural
      # CSS asset just by dropping its own version at the same path.
      #
      # Between categories, themes lose to app/assets (preserving the
      # original semantic: `_common.css` and `site.css` win over
      # theme-bundled CSS on conflict). Hence the order:
      #   1. engine theme   →  2. site theme
      #   3. engine assets  →  4. site assets
      [engine_theme_dir, site_theme_dir, engine_app_assets, site_app_assets].uniq.each do |dir|
        process_dir(dir) if dir && Dir.exist?(dir)
      end
      build_css_bundle
    end

    def path_for(name)
      @paths[name] || raise(ArgumentError, "Unknown asset: #{name}. Add it to app/assets/ or themes/#{theme_name}/.")
    end

    def theme_name
      @site.config['theme'] || DEFAULT_THEME
    end

    private

    def engine_app_assets
      File.join(@site.engine_root, 'app', 'assets')
    end

    def site_app_assets
      File.join(@site.site_root, 'app', 'assets')
    end

    def engine_theme_dir
      return nil if theme_name.to_s == 'none'

      File.join(@site.engine_root, 'themes', theme_name)
    end

    def site_theme_dir
      return nil if theme_name.to_s == 'none'

      File.join(@site.site_root, 'themes', theme_name)
    end

    def process_dir(src)
      Dir.glob(File.join(src, '**', '*')).sort.each do |entry|
        next if File.directory?(entry)
        next if File.basename(entry).start_with?('.')
        next if entry.include?(File.join('assets', 'images') + File::SEPARATOR)
        # Symlink containment — same invariant `BundleAssets`,
        # `ImagePipeline`, and `SiteLoader` enforce. A theme or
        # `app/assets/` file that symlinks outside `site_root` (e.g.
        # `app/assets/css/main.css` → `/etc/passwd`) is skipped with
        # a warning rather than copied into `_site/`. Trust model
        # still treats `app/assets/` as author-controlled, but
        # consistency across walkers keeps future contributors from
        # assuming any one of them is sufficient on its own.
        next if @site.external_symlink?(entry)

        logical = entry.sub("#{src}/", '')
        write_asset(logical, processed_content(entry, logical))
        @sources[logical] = entry
      end
    end

    # Fingerprint + write one asset. The hash is computed over the
    # content actually shipped (post-minification), so the name stays
    # content-addressable: if the fingerprinted target already exists,
    # its content matches and the write is skipped.
    def write_asset(logical, content)
      fingerprinted = fingerprint(logical, content)
      dest = File.join(@site.output_dir, OUTPUT_SUBDIR, fingerprinted)

      unless File.exist?(dest)
        FileUtils.mkdir_p(File.dirname(dest))
        File.binwrite(dest, content)
      end

      @paths[logical] = "/#{OUTPUT_SUBDIR}/#{fingerprinted}"
    end

    def processed_content(entry, logical)
      raw = File.binread(entry)
      kind = MINIFY_KINDS[File.extname(logical)]
      return raw unless kind && minify?

      text = raw.dup.force_encoding('UTF-8')
      return raw unless text.valid_encoding?

      Minifier.public_send(kind, text)
    end

    # Concatenate the render-blocking stylesheets into ONE fingerprinted
    # file, in the same cascade order as the individual <link> tags it
    # replaces: syntax (Rouge theme), `_common.css`, theme `app.css`,
    # `site.css` override. `_head.html.erb` links only the bundle when
    # it exists; when it doesn't (a `none`-theme site without its own
    # app.css, or a site shipping a literal `bundle.css` of its own),
    # the partial falls back to the individual links so the behaviour
    # and error surface are unchanged.
    def build_css_bundle
      return unless @sources['css/app.css']

      if @sources[BUNDLE_LOGICAL]
        Log.warn "app/assets/css/bundle.css shadows the generated CSS bundle — " \
                 'falling back to individual stylesheet links.'
        return
      end

      pieces = []
      pieces << SyntaxHighlighter::Stylesheet.new(@site).css if @site.config['syntax_highlighting']
      unless NO_COMMON_THEMES.include?(theme_name.to_s)
        common = @sources['css/_common.css']
        pieces << File.read(common, encoding: 'UTF-8') if common
      end
      pieces << File.read(@sources['css/app.css'], encoding: 'UTF-8')
      site_css = @sources['css/site.css']
      pieces << File.read(site_css, encoding: 'UTF-8') if site_css

      content = pieces.join("\n")
      content = Minifier.css(content) if minify?
      write_asset(BUNDLE_LOGICAL, content)
    end

    # Assets ship minified whenever HTML does — one `minify:` switch
    # governs the whole output. Same logic as Renderer#minify_html?
    # (duplicated rather than delegated: the renderer memo may not
    # exist yet when assets process).
    def minify?
      return @site.config['minify'] if @site.config.key?('minify')

      @site.env == :production
    end

    def fingerprint(logical, content)
      hash = Digest::SHA1.hexdigest(content)[0, HASH_LENGTH]
      ext = File.extname(logical)
      base = logical[0...-ext.length]
      "#{base}.#{hash}#{ext}"
    end
  end
end

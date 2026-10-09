# frozen_string_literal: true

require 'digest'
require 'fileutils'

module Abqari
  class AssetPipeline
    OUTPUT_SUBDIR = 'assets'
    HASH_LENGTH = 10
    BUNDLE_LOGICAL = 'css/bundle.css'
    FONTS_LOGICAL = 'fonts/fonts.css'
    # A theme name is a directory name under themes/ and nothing more.
    # The strict pattern is load-bearing: the name is joined into
    # filesystem paths in several places (here, ArtifactWriter,
    # Renderer), so without it `theme: ../something` walks and
    # publishes arbitrary directories. Same containment class the
    # symlink guards enforce.
    THEME_NAME_RE = /\A[a-z0-9_-]+\z/.freeze
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
      validate_theme!

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
      #
      # A theme's `public/` subtree is NOT an asset source — it's the
      # verbatim passthrough tree ArtifactWriter#copy_public ships to
      # the site root (e.g. the vendored Bootstrap dist). Walking it
      # here used to fingerprint ~700 KB of dead, unreferenced copies
      # into `_site/assets/public/`.
      [engine_theme_dir, site_theme_dir].uniq.each do |dir|
        process_dir(dir, skip_public: true) if dir && Dir.exist?(dir)
      end
      [engine_app_assets, site_app_assets].uniq.each do |dir|
        process_dir(dir) if dir && Dir.exist?(dir)
      end
      process_font_stylesheet
      build_css_bundle
    end

    def path_for(name)
      @paths[name] || raise(ArgumentError, "Unknown asset: #{name}. Add it to app/assets/ or themes/#{theme_name}/.")
    end

    def theme_name
      @site.config['theme'] || SiteConfig::DEFAULTS['theme']
    end

    # Fail fast — called at the top of Site#build, BEFORE the output
    # dir is wiped, so a config typo aborts with one clear message
    # instead of N per-page "Unknown asset: css/app.css" failures (or,
    # for a traversal-shaped name, a walk of whatever the path
    # resolves to).
    def validate_theme!
      name = theme_name.to_s
      return if name == 'none'

      unless name.match?(THEME_NAME_RE)
        raise PathSafe::Error,
              "invalid theme name #{name.inspect}: must match #{THEME_NAME_RE.inspect} " \
              "(lowercase letters, digits, '-', '_'), or 'none'"
      end

      unless Dir.exist?(File.join(@site.engine_root, 'themes', name)) ||
             Dir.exist?(File.join(@site.site_root, 'themes', name))
        raise "unknown theme #{name.inspect} — no themes/#{name}/ in the site or the engine. " \
              "Available: #{available_theme_names.join(', ')}, or 'none'"
      end

      return if theme_app_css_candidates.any? { |f| File.file?(f) }

      raise "theme #{name.inspect} has no css/app.css — looked in " \
            "themes/#{name}/css/ (site and engine) and app/assets/css/ (site). " \
            'Every theme needs one, even if empty; it anchors the CSS bundle.'
    end

    private

    def available_theme_names
      names = Dir.children(File.join(@site.engine_root, 'themes')).sort
      site_themes = File.join(@site.site_root, 'themes')
      names |= Dir.children(site_themes).sort if Dir.exist?(site_themes)
      names.select { |n| n.match?(THEME_NAME_RE) }
    end

    # Everywhere a theme's `css/app.css` may legitimately live, in
    # override order. `app/assets/css/app.css` is the `theme: none`
    # convention ("bring your own CSS"), but it satisfies any theme.
    def theme_app_css_candidates
      [
        File.join(@site.site_root, 'app', 'assets', 'css', 'app.css'),
        File.join(@site.site_root, 'themes', theme_name.to_s, 'css', 'app.css'),
        File.join(@site.engine_root, 'themes', theme_name.to_s, 'css', 'app.css')
      ]
    end

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

    def process_dir(src, skip_public: false)
      Dir.glob(File.join(src, '**', '*')).sort.each do |entry|
        next if File.directory?(entry)
        next if File.basename(entry).start_with?('.')
        next if skip_public && entry.start_with?(File.join(src, 'public') + File::SEPARATOR)
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

    # The `bin/fetch-fonts` stylesheet gets a content hash like any
    # other asset. At its old fixed URL it sat under the `/assets/*
    # immutable` cache rule, so a site that changed `fonts:` and
    # re-fetched kept serving returning visitors the old `@font-face`
    # rules for a year. Its woff2 `url()`s are root-absolute, so the
    # renamed file still resolves them. ArtifactWriter#copy_fonts keeps
    # shipping the unhashed copy for sites that override the head.
    def process_font_stylesheet
      source = File.join(@site.site_root, 'vendor', 'fonts', 'fonts.css')
      return unless File.file?(source)
      return if @site.external_symlink?(source)

      write_asset(FONTS_LOGICAL, processed_content(source, FONTS_LOGICAL))
      @sources[FONTS_LOGICAL] = source
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

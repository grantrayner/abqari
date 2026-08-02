# frozen_string_literal: true

require 'uri'

module Abqari
  # Lightweight schema check for `config/site.yml`. The goal is not full
  # schema validation — yagni for a single-author tool — but to catch
  # the typo class of bug:
  #
  #   manifest:
  #     theme_colour: '#000'    # 🐛 should be `theme_color`
  #
  # …which silently no-ops and leaves the operator wondering why their
  # PWA install icon doesn't pick up the brand colour.
  #
  # Strategy: known top-level keys are allow-listed below. Unknown keys
  # warn by default (so existing sites don't break on upgrade), and
  # raise when `ABQARI_STRICT_CONFIG=true`. CI workflows that want the
  # gate enforced flip the env var. The plan is to flip the default to
  # raise once the warn-mode period has passed.
  #
  # Reserved keys we tolerate without warning:
  #   - `environments` is structural (per-env overrides).
  #   - Anything beginning with `x_` is treated as a user extension
  #     namespace, mirroring HTTP/MIME conventions. Lets a consuming
  #     site park its own metadata in the same file without false-
  #     positive warnings.
  module SiteConfig
    # Static defaults applied to every site. User values in
    # `config/site.yml` deep-merge over these — any user-set key wins.
    # Only static defaults belong here; dynamic ones (`minify` =
    # `env == :production`) stay in their callers.
    #
    # Adding a default here removes a `config.fetch('key', value)`
    # call elsewhere — one auditable place for the defaults the
    # engine assumes, instead of scattered ternaries.
    DEFAULTS = {
      'indexable'           => true,
      'block_ai_scraping'   => true,
      'syntax_highlighting' => true,
      'erb_in_markdown'     => false,
      'theme_toggle'        => true,
      # The default here (not buried in AssetPipeline) so EVERY reader
      # of config['theme'] agrees. When it lived pipeline-side, a site
      # with no `theme:` key built the minimal theme but the renderer's
      # theme-mtime scoping read '' — so theme CSS edits rebuilt assets
      # without re-rendering pages, and hot reload served stale hrefs.
      'theme'               => 'minimal'
    }.freeze

    # Every top-level key the engine reads anywhere (rb + erb). Keep
    # in lockstep with the readers — when adding a new top-level
    # config key, add it here too. CI's audit catches drift.
    KNOWN_KEYS = %w[
      author
      block_ai_scraping
      collections
      contact
      csp
      deploy
      description
      drafts
      environments
      erb_in_markdown
      folio
      fonts
      fonts_preload
      footer
      headers
      home
      icons
      images
      indexable
      indieweb
      llms
      locale
      manifest
      media
      minify
      nav
      newsletter
      og_images
      og_locale
      pagination
      plausible
      robots_disallow
      search
      security_contact
      share_image
      social
      speculation_rules
      syndication
      syntax_highlighting
      syntax_theme
      syntax_theme_dark
      taxonomies
      theme
      theme_toggle
      timezone
      title
      twitter
      url
      validate
      visualizations
    ].freeze

    module_function

    # Deep-merge DEFAULTS under the user's config. Returns a new hash;
    # the input isn't mutated. Use at boot to fold in static defaults
    # so call sites can do `config['key']` instead of
    # `config.fetch('key', sane_default)`.
    def with_defaults(config)
      deep_merge(DEFAULTS, config || {})
    end

    def deep_merge(base, override)
      base.merge(override) do |_, b, o|
        b.is_a?(Hash) && o.is_a?(Hash) ? deep_merge(b, o) : o
      end
    end

    def validate!(config, strict: nil, env: nil)
      strict = ENV['ABQARI_STRICT_CONFIG'] == 'true' if strict.nil?

      validate_required!(config, strict: strict, env: env)

      unknown = config.keys.map(&:to_s).reject do |key|
        KNOWN_KEYS.include?(key) || key.start_with?('x_')
      end

      return if unknown.empty?

      msg = "Unknown config key(s) in site.yml: #{unknown.sort.join(', ')}. " \
            'Typos silently no-op; add `x_` prefix for intentional user extensions, ' \
            "or set ABQARI_STRICT_CONFIG=true to make this a hard error."

      raise ArgumentError, msg if strict

      Log.warn msg
    end

    # Keys that must be present for a correct build. `title` feeds
    # <title>, RSS, OG; a blank one ships "Page · " everywhere. `url` is
    # the base for every absolute URL (canonical, sitemap, feed, JSON-LD)
    # — blank in production means no sitemap, no canonical, and invalid
    # feed URLs. Warn on a blank title always; escalate a blank `url` in
    # production (raise under strict, warn otherwise) since a live build
    # with no base URL is almost always a mistake.
    def validate_required!(config, strict:, env:)
      if config['title'].to_s.strip.empty?
        Log.warn 'Missing `title` in site.yml — pages will render with an empty <title>.'
      end

      if config['url'].to_s.strip.empty?
        url_msg = 'Missing `url` in site.yml — canonical URLs, sitemap, and feeds ' \
                  'need an absolute base URL. Set `url:` (per-environment under ' \
                  '`environments:` is fine).'
        if env.to_s == 'production'
          raise ArgumentError, url_msg if strict

          Log.warn url_msg
        end
        return
      end

      validate_url_has_no_path!(config['url'])
    end

    # Abqari emits root-relative asset and internal-link URLs (`/assets/…`,
    # `/posts/…`, `/feed.xml`), so a `url:` with a path component
    # (`https://user.github.io/repo`) produces a site whose every asset
    # and link 404s under the prefix. Subdirectory/base-path deployment
    # is not supported; fail loudly at config time instead of shipping a
    # broken site. A bare host or a lone `/` path is fine.
    def validate_url_has_no_path!(url)
      path = begin
        URI.parse(url.to_s).path.to_s
      rescue URI::InvalidURIError
        '' # a malformed URL is a separate problem; don't crash here
      end
      return if path.empty? || path == '/'

      raise ArgumentError,
            "`url` (#{url.inspect}) has a path component (#{path.inspect}). " \
            'Abqari does not support subdirectory/base-path deployment — every ' \
            'asset and internal link is root-relative and would 404 under a path ' \
            'prefix. Deploy at a domain root (a custom domain, or a `<user>.github.io` ' \
            'root repository).'
    end
  end
end

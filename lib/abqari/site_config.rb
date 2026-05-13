# frozen_string_literal: true

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
      'theme_toggle'        => true
    }.freeze

    # Every top-level key the engine reads anywhere (rb + erb). Keep
    # in lockstep with the readers — when adding a new top-level
    # config key, add it here too. CI's audit catches drift.
    KNOWN_KEYS = %w[
      author
      block_ai_scraping
      collections
      contact
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
      llms
      locale
      manifest
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
      syntax_highlighting
      syntax_theme
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

    def validate!(config, strict: nil)
      strict = ENV['ABQARI_STRICT_CONFIG'] == 'true' if strict.nil?

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
  end
end

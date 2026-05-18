# frozen_string_literal: true

require 'zlib'

module Abqari
  class RenderContext
    # Decorative cover-image generation for posts and other collections
    # that opt in via the `cover:` enum in config/site.yml. Produces
    # inline SVG "initial tiles" — a single letter (the first alphanumeric
    # character of the page title) on a slug-hashed two-tone gradient.
    # No file output; the SVG embeds directly in the partial's HTML.
    #
    # The four modes:
    #
    #   photo          — use the page's `image:` frontmatter if set;
    #                    otherwise the basic flat-tint placeholder
    #                    (`.post-list__cover-placeholder` etc.). The
    #                    historical default.
    #   photo_or_svg   — use the page's `image:` if set; otherwise
    #                    render a decorative initial-tile SVG. Gives
    #                    text-first authors a polished card without
    #                    sourcing imagery.
    #   svg            — always render the decorative SVG, even when
    #                    `image:` is set. Useful when you want every
    #                    card to read as a tile (uniform listing look)
    #                    rather than a mix of photos and tiles.
    #   none           — no cover slot at all (text-only cards). Same
    #                    effect as the legacy `show_image: false`.
    #
    # Frontmatter `cover:` on a single page overrides the collection
    # default — `cover: false` is a shortcut for `cover: none`.
    module CoverHelpers
      # Muted two-tone gradients. Slug-hashed so each post consistently
      # gets the same tile across builds, but adjacent posts in a
      # listing tend to draw different tones (8 palette entries × hash
      # distribution = reasonably even spread on any one page).
      COVER_PALETTES = [
        ['#1e3a5f', '#4a78a8'].freeze,  # deep blue → mid blue
        ['#5b3a8a', '#8a6abf'].freeze,  # violet
        ['#2d4a3d', '#5a8a6a'].freeze,  # forest
        ['#8a4a2a', '#bf7a4a'].freeze,  # rust
        ['#3a3a4a', '#6a6a8a'].freeze,  # slate
        ['#2a5a6a', '#5a8aa0'].freeze,  # teal
        ['#6a2a3a', '#a05a6a'].freeze,  # burgundy
        ['#5a5a3a', '#8a8a6a'].freeze   # olive
      ].freeze

      COVER_MODES = %w[photo photo_or_svg svg none].freeze
      DEFAULT_COVER_MODE = 'photo'

      # Resolve the effective cover mode for a page. Three layers,
      # frontmatter wins:
      #   1. Frontmatter `cover:` — explicit string value (one of
      #      `COVER_MODES`) is honoured directly. Boolean `false` is
      #      sugar for `'none'`.
      #   2. Collection config `<collection>.<context>.cover`.
      #   3. Default `'photo'` (the historical behaviour).
      #
      # `context:` is `:index` for listing partials, `:show` for the
      # detail page. Same enum on both sides, independent config.
      def cover_mode_for(page, context: :index)
        fm = page.respond_to?(:frontmatter) ? page.frontmatter['cover'] : nil
        return 'none'  if fm == false
        return fm.to_s if COVER_MODES.include?(fm.to_s)

        col = page.respond_to?(:collection) ? page.collection : nil
        return DEFAULT_COVER_MODE unless col

        (site.collection_config(col).dig(context.to_s, 'cover') || DEFAULT_COVER_MODE).to_s
      end

      # What to actually render for the cover slot, given the resolved
      # mode and whether the page has an `image:` set. Returns one of:
      #
      #   :photo       — render the page's `image:` as an <img>
      #   :placeholder — render the basic flat-tint SVG rect (the
      #                  existing `.post-list__cover-placeholder` shape)
      #   :svg         — render the decorative initial-tile SVG
      #                  (call `cover_svg_for(page)`)
      #   :none        — render nothing; caller skips the cover slot
      #
      # Centralising the branching here keeps the partials a flat
      # `case` over the four outcomes instead of repeating the
      # mode/image cross-product.
      def cover_choice_for(page, context: :index)
        mode = cover_mode_for(page, context: context)
        return :none if mode == 'none'

        has_image = page.respond_to?(:frontmatter) && page.frontmatter['image']
        case mode
        when 'photo'        then has_image ? :photo : :placeholder
        when 'photo_or_svg' then has_image ? :photo : :svg
        when 'svg'          then :svg
        end
      end

      # Inline SVG markup for the decorative initial-tile cover. Designed
      # for the 4:3 cover slot but `preserveAspectRatio="xMidYMid slice"`
      # makes it scale gracefully to wider/taller containers too —
      # safe to use for the larger show-view hero as well.
      #
      # The `<linearGradient>` id is suffixed with a slug-hash so
      # multiple cover SVGs on one page (a posts index card grid, the
      # home modules, etc.) don't collide on a shared id.
      def cover_svg_for(page)
        title   = page.respond_to?(:title) ? page.title.to_s : ''
        initial = title.gsub(/[^[:alnum:]]/, '').chars.first&.upcase || '?'

        # Slug-keyed where possible (deterministic per page across
        # builds); falls back to the title. `Zlib.crc32` is stable
        # across processes — `String#hash` is salted and would change
        # between builds, scrambling the tile colours each time.
        key      = page.respond_to?(:slug) && page.slug ? page.slug.to_s : title
        crc      = Zlib.crc32(key)
        bg_a, bg_b = COVER_PALETTES[crc % COVER_PALETTES.size]
        grad_id  = "cover-grad-#{crc.to_s(36)}"

        <<~SVG.gsub(/\n\s+/, ' ').strip
          <svg class="cover-svg" viewBox="0 0 400 300" preserveAspectRatio="xMidYMid slice" aria-hidden="true">
            <defs>
              <linearGradient id="#{grad_id}" x1="0" y1="0" x2="1" y2="1">
                <stop offset="0%" stop-color="#{bg_a}"/>
                <stop offset="100%" stop-color="#{bg_b}"/>
              </linearGradient>
            </defs>
            <rect width="400" height="300" fill="url(##{grad_id})"/>
            <text x="200" y="150" text-anchor="middle" dominant-baseline="central" font-family="Georgia, 'Times New Roman', serif" font-size="180" font-weight="700" fill="rgba(255,255,255,0.92)">#{h(initial)}</text>
          </svg>
        SVG
      end
    end
  end
end

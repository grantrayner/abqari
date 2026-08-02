# frozen_string_literal: true

require 'zlib'

module Abqari
  class RenderContext
    # Decorative cover-image generation for posts and other collections
    # that opt in via the `cover:` enum in config/site.yml. Produces
    # inline SVG title cards — the page title (word-wrapped to 1-3
    # lines) on a slug-hashed two-tone gradient, with a small cluster
    # of decorative squares at the corners (echoing the hand-authored
    # hero.svg pattern). No file output; the SVG embeds directly in
    # the partial's HTML.
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
      # listing tend to draw different tones (palette entries × hash
      # distribution = reasonably even spread on any one page).
      #
      # The default set is hue-neutral, tuned for `minimal` (and any
      # custom theme). The warm themes get their own sets in
      # `THEME_COVER_PALETTES` below — a slug-hashed teal or violet
      # tile on magazine's cream or notebook's paper page injects a
      # saturated hue the theme never uses anywhere else, so each
      # warm theme constrains its tiles to its own colour world.
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

      # Theme-keyed tile palettes for the shipped warm themes. Every
      # pair keeps the tile dark enough that the near-white title
      # text stays legible. Themes not listed (minimal, custom,
      # bootstrap, none) fall back to the neutral COVER_PALETTES.
      THEME_COVER_PALETTES = {
        # Cream, rust, editorial — warm browns and rusts, one muted
        # navy (the theme's info hue) so grids don't go monochrome.
        'magazine' => [
          ['#8a4a2a', '#bf7a4a'].freeze,  # rust
          ['#6a2a3a', '#a05a6a'].freeze,  # burgundy
          ['#4a3226', '#7a5a42'].freeze,  # deep umber
          ['#5a5a3a', '#8a8a6a'].freeze,  # olive
          ['#3a4a5f', '#68809a'].freeze,  # muted navy
          ['#9a5230', '#c07a50'].freeze   # terracotta
        ].freeze,
        # Paper + ochre + graphite — the ochre family carries the
        # signature, dusty navy echoes `--color-info`.
        'notebook' => [
          ['#8a5c14', '#c4811f'].freeze,  # ochre
          ['#33353a', '#5c6066'].freeze,  # graphite
          ['#2a5d8f', '#5580ab'].freeze,  # dusty navy
          ['#565046', '#847c6e'].freeze,  # warm grey
          ['#6e4a12', '#a06419'].freeze,  # deep ochre
          ['#4a5a3a', '#75866a'].freeze   # moss
        ].freeze,
        # Sun-bleached earth — brick, clay, olive; dusty blue echoes
        # `--color-info`.
        'sand' => [
          ['#7a2018', '#a84438'].freeze,  # brick
          ['#8a5138', '#b57952'].freeze,  # clay
          ['#4f5233', '#7a7d55'].freeze,  # olive
          ['#6e5a3a', '#9a825c'].freeze,  # sand brown
          ['#4a342a', '#755446'].freeze,  # deep umber
          ['#3f5a80', '#6d88a8'].freeze   # dusty blue
        ].freeze
      }.freeze

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

      # `cover:` is overloaded: it's usually a MODE enum (`svg`, `none`,
      # …) but a site can also point it at an image path. This returns
      # the value ONLY when it's an actual image path — a non-mode,
      # non-boolean string — so the head partial doesn't turn
      # `cover: svg` into an `og:image` of `/posts/foo/svg`. Returns nil
      # for modes, booleans, and blanks.
      def cover_image_path(page)
        fm = page.respond_to?(:frontmatter) ? page.frontmatter['cover'] : nil
        return nil unless fm.is_a?(String)
        return nil if fm.strip.empty? || COVER_MODES.include?(fm)

        fm
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

      # Inline SVG markup for the decorative title-card cover. Designed
      # for the 4:3 cover slot but `preserveAspectRatio="xMidYMid slice"`
      # makes it scale gracefully to wider/taller containers too —
      # safe to use for the larger show-view hero as well.
      #
      # Layout:
      #   * Slug-hashed two-tone gradient background.
      #   * Two clusters of three faint white squares (top-left + bottom-
      #     right) — same motif as the hand-authored hero.svg shipped
      #     with the fixture's "Building with Abqari" post.
      #   * Page title, centred, word-wrapped to 1-3 lines. Font size
      #     auto-scales based on the longest wrapped line so long titles
      #     stay inside the viewBox.
      #
      # The `<linearGradient>` id is suffixed with a slug-hash so
      # multiple cover SVGs on one page (a posts index card grid, the
      # home modules, etc.) don't collide on a shared id.
      def cover_svg_for(page)
        title         = page.respond_to?(:title) ? page.title.to_s.strip : ''
        display_title = title.empty? ? '?' : title

        # Slug-keyed where possible (deterministic per page across
        # builds); falls back to the title. `Zlib.crc32` is stable
        # across processes — `String#hash` is salted and would change
        # between builds, scrambling the tile colours each time.
        key      = page.respond_to?(:slug) && page.slug ? page.slug.to_s : title
        crc      = Zlib.crc32(key)
        palette  = cover_palette
        bg_a, bg_b = palette[crc % palette.size]
        grad_id  = "cover-grad-#{crc.to_s(36)}"

        lines       = svg_wrap_title(display_title)
        font_size   = svg_title_font_size(lines)
        line_height = (font_size * 1.15).round
        block_h     = line_height * lines.size
        # First baseline = top of text block + ~0.78 * font_size
        # (typical cap-height ratio for sans-serif).
        first_y     = (150 - block_h / 2.0 + font_size * 0.78).round

        text_block = lines.each_with_index.map do |line, i|
          y = first_y + (line_height * i)
          %(<text x="200" y="#{y}" text-anchor="middle" font-size="#{font_size}" font-weight="600" letter-spacing="-0.5" fill="rgba(255,255,255,0.96)">#{h(line)}</text>)
        end.join

        <<~SVG.gsub(/\n\s+/, ' ').strip
          <svg class="cover-svg" viewBox="0 0 400 300" preserveAspectRatio="xMidYMid slice" aria-hidden="true">
            <defs>
              <linearGradient id="#{grad_id}" x1="0" y1="0" x2="1" y2="1">
                <stop offset="0%" stop-color="#{bg_a}"/>
                <stop offset="100%" stop-color="#{bg_b}"/>
              </linearGradient>
            </defs>
            <rect width="400" height="300" fill="url(##{grad_id})"/>
            <g fill="#fff" opacity="0.10">
              <rect x="20"  y="20"  width="30" height="30" rx="3"/>
              <rect x="56"  y="20"  width="30" height="30" rx="3"/>
              <rect x="20"  y="56"  width="30" height="30" rx="3"/>
              <rect x="314" y="250" width="30" height="30" rx="3"/>
              <rect x="350" y="250" width="30" height="30" rx="3"/>
              <rect x="350" y="214" width="30" height="30" rx="3"/>
            </g>
            <g font-family="-apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif">
              #{text_block}
            </g>
          </svg>
        SVG
      end

      # The tile palette for the active theme — theme-keyed when the
      # theme ships one, the neutral default set otherwise.
      def cover_palette
        THEME_COVER_PALETTES.fetch(site.config['theme'].to_s, COVER_PALETTES)
      end

      # Word-wrap a title into 1-3 lines for the SVG title-card. SVG
      # `<text>` has no flow, so the layout has to be precomputed.
      # We pick a line count from the total title length, then pick
      # the most balanced partition of the words across those lines
      # — minimising the longest line so the font-size step
      # (`svg_title_font_size`) gets the best chance of staying
      # large. Greedy packing would orphan trailing long words onto
      # a short final line (e.g. "Crisis / Response Foundations");
      # the balanced search picks "Crisis Response / Foundations"
      # instead.
      #
      # Single-word titles return as-is — long single words just
      # shrink via the font-size fallback.
      #
      # Thresholds are tuned so the rendered text block sits well
      # inside the 400-wide viewBox — roughly 16% horizontal padding
      # at the largest font tier, more at smaller tiers. Tighter
      # thresholds than these and the text crowds the decorative
      # corner squares; looser and the title looks small in a
      # mostly-blank tile.
      def svg_wrap_title(title)
        words = title.split(/\s+/).reject(&:empty?)
        return [title] if words.size <= 1

        max_lines = if title.length <= 11
                      1
                    elsif title.length <= 26
                      2
                    else
                      3
                    end
        return [title] if max_lines == 1

        line_count = [max_lines, words.size].min
        balanced_word_partition(words, line_count)
      end

      # Try every contiguous partition of `words` into `line_count`
      # non-empty groups; return the one whose longest joined line is
      # shortest (ties broken by smallest length spread). 2-3 lines
      # over a typical title (<10 words) is a handful of splits —
      # cheap to enumerate.
      def balanced_word_partition(words, line_count)
        return [words.join(' ')] if line_count <= 1
        return words.dup          if words.size == line_count

        best        = nil
        best_score  = nil
        enumerate_splits(words.size, line_count).each do |sizes|
          lines   = partition_by_sizes(words, sizes)
          lengths = lines.map(&:length)
          score   = [lengths.max, lengths.max - lengths.min]
          # Arrays don't define `<`, only `<=>`. Lexicographic compare
          # gives the behaviour we want: first the smaller max-line
          # wins, then the smaller spread breaks ties.
          if best_score.nil? || (score <=> best_score) < 0
            best       = lines
            best_score = score
          end
        end
        best
      end

      # All compositions of `total` into `parts` positive integers,
      # e.g. enumerate_splits(3, 2) → [[1,2], [2,1]].
      def enumerate_splits(total, parts)
        return [[total]] if parts == 1

        out = []
        (1..(total - parts + 1)).each do |head|
          enumerate_splits(total - head, parts - 1).each do |rest|
            out << [head, *rest]
          end
        end
        out
      end

      # Split `words` into consecutive groups of the given `sizes`
      # and join each group with a single space.
      def partition_by_sizes(words, sizes)
        out = []
        i   = 0
        sizes.each do |sz|
          out << words[i, sz].join(' ')
          i += sz
        end
        out
      end

      # Pick a font size that fits the longest wrapped line into the
      # 400-wide viewBox with margins. Calibrated against the
      # sans-serif stack declared in `cover_svg_for`. The largest
      # tier is deliberately modest (36pt) so short titles like
      # "Upgrading Abqari" or "Quickstart" read as a comfortable
      # label rather than dominating the tile — title-card SVGs
      # are decoration, not a billboard.
      def svg_title_font_size(lines)
        longest = lines.map(&:length).max.to_i
        case longest
        when 0..10  then 36
        when 11..15 then 32
        when 16..22 then 28
        else             24
        end
      end
    end
  end
end

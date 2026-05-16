# frozen_string_literal: true

module Abqari
  # Normalises publication / bundle / series frontmatter into the
  # canonical Folio-aligned shape documented in `docs/publications.md`.
  # Runs once at frontmatter-parse time so the rest of the engine sees
  # one vocabulary.
  #
  # Today the normalisers do small, contained work:
  #
  #   - `PublicationNormaliser` expands `price: "$16.00"` shorthand
  #     into the canonical `{ cents:, currency:, formatted: }` Hash
  #     so authors can write the prettier form without losing the
  #     Folio-aligned shape downstream.
  #   - `BundleNormaliser` and `SeriesNormaliser` do the same price
  #     expansion. Bundle / series use `name` (not `title`); no
  #     translation needed — frontmatter already writes `name`.
  #
  # Adding a new shorthand later: each normaliser is a single function
  # that takes a hash and returns a hash. Keep them idempotent so a
  # frontmatter block already in canonical form passes through
  # unchanged.
  module PublicationNormaliser
    # Symbol → ISO currency code. Falls back to USD for unknown
    # symbols (matches Folio's serializer default).
    CURRENCY_SYMBOLS = {
      '$'  => 'USD',
      'A$' => 'AUD',
      'C$' => 'CAD',
      'NZ$' => 'NZD',
      'S$' => 'SGD',
      '£'  => 'GBP',
      '€'  => 'EUR',
      '¥'  => 'JPY'
    }.freeze
    # Order matters — longest symbols first so 'A$' / 'S$' / 'NZ$' /
    # 'C$' match before the bare '$'.
    SYMBOL_ORDER = CURRENCY_SYMBOLS.keys.sort_by { |s| -s.length }

    PRICE_RE = /\A\s*(?<symbol>#{SYMBOL_ORDER.map { |s| Regexp.escape(s) }.join('|')})?\s*(?<amount>\d+(?:\.\d+)?)\s*\z/

    module_function

    # Top-level entry point. Dispatches per collection. Returns the
    # frontmatter hash with shorthand fields expanded; original input
    # not mutated.
    #
    # Publications, bundles, AND series all get price normalisation.
    # Folio doesn't supply prices on series (series in Folio are pure
    # sequences, no commerce), but a native author CAN set
    # `price: "$28.00"` on a series to render a "buy the whole
    # series" button — and the rest of the engine reads
    # `fm.dig('price', 'formatted')`, so the shorthand needs to
    # expand here regardless of source.
    def call(frontmatter, collection)
      return frontmatter unless frontmatter.is_a?(Hash)

      case collection
      when 'publications', 'bundles', 'series' then normalise_with_price(frontmatter)
      else frontmatter
      end
    end

    def normalise_with_price(frontmatter)
      return frontmatter unless frontmatter['price']
      return frontmatter if frontmatter['price'].is_a?(Hash)

      expanded = expand_price(frontmatter['price'])
      return frontmatter unless expanded

      frontmatter.merge('price' => expanded)
    end

    # Expand a string price into the canonical Hash shape:
    #   "$16.00"  => { cents: 1600, currency: 'USD', formatted: '$16.00' }
    #   "12"      => { cents: 1200, currency: 'USD', formatted: '$12.00' }
    #   "£9.99"   => { cents: 999,  currency: 'GBP', formatted: '£9.99'  }
    #
    # Returns nil if the string doesn't parse (caller leaves the
    # frontmatter value as-is, so the operator sees their typo
    # surface downstream — e.g. JSON-LD will omit the offer).
    def expand_price(raw)
      return nil if raw.nil? || raw.to_s.strip.empty?

      raw_str = raw.to_s.strip
      match = PRICE_RE.match(raw_str)
      return nil unless match

      symbol = match[:symbol]
      currency = CURRENCY_SYMBOLS[symbol] || 'USD'
      amount = match[:amount].to_f
      cents  = (amount * 100).round
      # When the author wrote a bare number ("12"), supply a default
      # formatted form so display code doesn't see "12" with no
      # currency marker. The symbol is the canonical one for the
      # inferred currency.
      formatted = if symbol
                    raw_str
                  else
                    default_symbol = CURRENCY_SYMBOLS.invert[currency] || '$'
                    "#{default_symbol}#{format('%.2f', amount)}"
                  end

      {
        'cents'     => cents,
        'currency'  => currency,
        'formatted' => formatted
      }
    end
  end
end

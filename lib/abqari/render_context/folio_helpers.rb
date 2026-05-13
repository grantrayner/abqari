# frozen_string_literal: true

module Abqari
  class RenderContext
    # Folio integration helpers — accessors for cached Folio data plus
    # the buy/cart button renderers. Lifted out of RenderContext so the
    # main class can shrink to its templating responsibilities; the
    # behaviour is unchanged.
    #
    # All methods return nil / '' on missing data rather than raising,
    # so a missing slug or a failed Folio fetch doesn't break a build.
    # URLs flow through `sanitized_url` before being interpolated into
    # HTML to defend against `javascript:` and similar scheme attacks
    # in a hostile or compromised Folio response.
    module FolioHelpers
      # The current page's Folio payload, or `{}` if there isn't one.
      # Encapsulates the defensive `page.respond_to?(:data)` check that
      # bundle/series show-view layouts otherwise repeat inline. For
      # publications, see the `_publication_header` partial — it adds
      # slug-fallback lookup against `site.data` so manual override
      # pages still pick up Folio cover/price/ISBN data.
      def folio_data
        return page.data if page.respond_to?(:data) && page.data

        {}
      end

      # Resolve a publication slug to a card-ready hash, used by
      # `_publication_card`. Falls back through three sources:
      #
      #   1. `site.data['folio_publications'][slug]` — Folio cache.
      #      Carries title, cover_url, excerpt, price, isbn, pages,
      #      published_at as a flat hash.
      #   2. `site.collection('publications').find { … }` — a manual
      #      publication page at `content/publications/<slug>/index.md`.
      #      Reads from its frontmatter.
      #   3. Slug-only — `{ slug: 'foo', title: 'foo' }`.
      def publication_card_data(slug)
        slug = slug.to_s
        folio = (site.data['folio_publications'] || {})[slug] || {}
        manual = site.collection('publications').find do |p|
          p.respond_to?(:slug) && p.slug == slug
        end
        fm = manual ? manual.frontmatter : {}

        {
          slug:        slug,
          title:       folio['title']        || fm['title']        || slug,
          cover:       folio['cover_url']    || fm['cover']        || fm['cover_image'],
          description: folio['excerpt']      || fm['description'],
          price:       folio.dig('price', 'formatted') || fm['price'],
          isbn:        folio['isbn']         || fm['isbn'],
          pages:       folio['pages']        || fm['pages'],
          published:   folio['published_at'] || fm['published_at'] || fm['publish_date']
        }
      end

      # Folio entity accessors — return nil when the slug isn't found
      # so a missing bundle doesn't break a build.
      def folio_book(slug)
        site.data.dig('folio_publications', slug)
      end

      def folio_bundle(slug)
        site.data.dig('folio_bundles', slug)
      end

      def folio_series(slug)
        site.data.dig('folio_series', slug)
      end

      # Buy / cart buttons. Pulls URLs from the Folio payload — if the
      # entity isn't loaded (fetch failed, bad slug) we render nothing
      # rather than a broken link. URLs pass through `sanitized_url`
      # so a compromised or malformed Folio response can't inject
      # `javascript:` or other scheme-based XSS. `kind:` is :book
      # (default) or :bundle.
      #
      # Markup uses the `.folio-button .folio-button--buy` / `--cart`
      # class set — a Folio-compatible style family separate from the
      # engine's `.btn-*` system. Users embedding Folio HTML elsewhere
      # on their site (copied from the Folio storefront) use the same
      # class names and get a consistent look.
      def folio_buy_button(slug, kind: :book, label: 'Buy now')
        entity = kind == :bundle ? folio_bundle(slug) : folio_book(slug)
        url    = entity && sanitized_url(entity['buy_now_url'])
        return '' unless url

        %(<a class="folio-button folio-button--buy" href="#{url}" rel="noopener noreferrer">#{h(label)}</a>)
      end

      def folio_cart_button(slug, kind: :book, label: 'Add to cart')
        entity = kind == :bundle ? folio_bundle(slug) : folio_book(slug)
        url    = entity && sanitized_url(entity['add_to_cart_url'])
        return '' unless url

        %(<a class="folio-button folio-button--cart" href="#{url}" rel="noopener noreferrer">#{h(label)}</a>)
      end
    end
  end
end

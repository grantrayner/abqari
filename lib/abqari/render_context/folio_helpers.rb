# frozen_string_literal: true

module Abqari
  class RenderContext
    # Publication / bundle / series helpers. The module name is kept
    # ("Folio…") for back-compat, but the methods are now
    # publisher-agnostic — they read canonical fields from any
    # publication, bundle, or series (manual or Folio-sourced) per
    # the schema documented in docs/publications.md.
    #
    # All methods return nil / '' on missing data rather than raising,
    # so a missing slug or a failed Folio fetch doesn't break a build.
    # URLs flow through `sanitized_url` before being interpolated into
    # HTML to defend against `javascript:` and similar scheme attacks
    # in a hostile or compromised data source.
    module FolioHelpers
      # The current page's frontmatter — replaces the legacy
      # `folio_data` helper. Returns `{}` if the page somehow has no
      # frontmatter (e.g. a TaxonomyPage). Templates can call this
      # OR `page.frontmatter` directly — they're equivalent.
      def folio_data
        return page.frontmatter if page.respond_to?(:frontmatter) && page.frontmatter

        {}
      end

      # Resolve a publication slug to a card-ready hash. After the
      # canonical-schema migration (docs/publications.md) every
      # publication — manual or Folio — lives in
      # `site.collection('publications')` with frontmatter in
      # canonical Folio shape, so this is a single lookup against the
      # collection followed by a small field-mapping into the
      # `_publication_card` partial's expected key names.
      #
      # Returns `{slug:, title: slug}` if the slug isn't in the
      # collection — keeps the partial renderable without raising.
      def publication_card_data(slug)
        slug = slug.to_s
        pub = site.collection('publications').find do |p|
          p.respond_to?(:slug) && p.slug == slug
        end
        return { slug: slug, title: slug } unless pub

        fm = pub.frontmatter
        {
          slug:        slug,
          title:       pub.title,
          cover:       fm['cover_url'],
          description: fm['excerpt'] || fm['tagline'],
          tagline:     fm['tagline'],
          price:       fm.dig('price', 'formatted'),
          isbn:        fm['isbn'],
          pages:       fm['pages'],
          published:   fm['published_at']
        }
      end

      # Lookups against the merged collections (manual + Folio). Each
      # returns the canonical-shape frontmatter Hash for the matching
      # slug, or nil. Useful when a partial needs metadata about a
      # publication / bundle / series it didn't receive directly.
      def folio_book(slug)
        site.collection('publications').find { |p| p.respond_to?(:slug) && p.slug == slug }&.frontmatter
      end

      def folio_bundle(slug)
        site.collection('bundles').find { |b| b.respond_to?(:slug) && b.slug == slug }&.frontmatter
      end

      def folio_series(slug)
        site.collection('series').find { |s| s.respond_to?(:slug) && s.slug == slug }&.frontmatter
      end

      # Generic buy / cart buttons. Render whenever the corresponding
      # canonical URL field (`buy_now_url` / `add_to_cart_url`) is set
      # on the given publication / bundle / series frontmatter — works
      # equally for native authors who set the URL in frontmatter and
      # for Folio integrations that supply it via API.
      #
      # `subject` can be a frontmatter Hash, a Page-like object (with
      # `.frontmatter`), or a slug string (looked up in publications
      # for back-compat with the legacy folio_buy_button signature).
      #
      # Markup uses the `.folio-button .folio-button--buy` / `--cart`
      # class family — kept for visual continuity with sites running
      # earlier Abqari versions.
      def buy_button(subject, label: 'Buy now', class_: 'folio-button folio-button--buy')
        fm = resolve_frontmatter(subject)
        return '' unless fm

        url = sanitized_url(fm['buy_now_url'])
        return '' unless url

        %(<a class="#{h(class_)}" href="#{url}" rel="noopener noreferrer">#{h(label)}</a>)
      end

      def cart_button(subject, label: 'Add to cart', class_: 'folio-button folio-button--cart')
        fm = resolve_frontmatter(subject)
        return '' unless fm

        url = sanitized_url(fm['add_to_cart_url'])
        return '' unless url

        %(<a class="#{h(class_)}" href="#{url}" rel="noopener noreferrer">#{h(label)}</a>)
      end

      # Deprecated aliases — kept so layouts that haven't yet migrated
      # to `buy_button` / `cart_button` keep working. The `kind:` arg
      # picks which collection to look up; the canonical helpers don't
      # need it since the caller already has the frontmatter in hand.
      def folio_buy_button(slug, kind: :book, label: 'Buy now')
        fm = lookup_by_kind(slug, kind)
        buy_button(fm, label: label) if fm
      end

      def folio_cart_button(slug, kind: :book, label: 'Add to cart')
        fm = lookup_by_kind(slug, kind)
        cart_button(fm, label: label) if fm
      end

      private

      # Accept Hash, Page-like, or String (slug). Returns the
      # frontmatter Hash for the publication / bundle / series, or nil
      # if the input doesn't resolve. Used by buy_button / cart_button
      # so templates can pass `page.frontmatter`, a `pub` Hash, or a
      # bare slug interchangeably.
      def resolve_frontmatter(subject)
        case subject
        when Hash then subject
        when String, Symbol
          slug = subject.to_s
          folio_book(slug) || folio_bundle(slug) || folio_series(slug)
        else
          subject.respond_to?(:frontmatter) ? subject.frontmatter : nil
        end
      end

      def lookup_by_kind(slug, kind)
        case kind
        when :bundle then folio_bundle(slug)
        when :series then folio_series(slug)
        else folio_book(slug)
        end
      end
    end
  end
end

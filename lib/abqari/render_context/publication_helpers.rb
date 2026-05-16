# frozen_string_literal: true

module Abqari
  class RenderContext
    # Publication / bundle / series helpers. Publisher-agnostic — every
    # method reads canonical fields from a publication, bundle, or
    # series (manual or externally-sourced) per the schema documented
    # in docs/publications.md.
    #
    # All methods return nil / '' on missing data rather than raising,
    # so a missing slug or a failed publisher fetch doesn't break a
    # build. URLs flow through `sanitized_url` before being interpolated
    # into HTML to defend against `javascript:` and similar scheme
    # attacks in a hostile or compromised data source.
    module PublicationHelpers
      # Resolve a publication slug to a card-ready hash. Every
      # publication — manual or externally-sourced — lives in
      # `site.collection('publications')` with frontmatter in canonical
      # shape, so this is a single lookup against the collection
      # followed by a small field-mapping into the `_publication_card`
      # partial's expected key names.
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

      # Lookups against the merged collections (manual + externally-
      # sourced). Each returns the canonical-shape frontmatter Hash for
      # the matching slug, or nil. Useful when a partial needs metadata
      # about a publication / bundle / series it didn't receive
      # directly.
      def publication_for(slug)
        site.collection('publications').find { |p| p.respond_to?(:slug) && p.slug == slug }&.frontmatter
      end

      def bundle_for(slug)
        site.collection('bundles').find { |b| b.respond_to?(:slug) && b.slug == slug }&.frontmatter
      end

      def series_for(slug)
        site.collection('series').find { |s| s.respond_to?(:slug) && s.slug == slug }&.frontmatter
      end

      # Generic buy / cart buttons. Render whenever the corresponding
      # canonical URL field (`buy_now_url` / `add_to_cart_url`) is set
      # on the given publication / bundle / series frontmatter — works
      # equally for native authors who set the URL in frontmatter and
      # for external publisher integrations (Folio, Payhip, Gumroad,
      # Lulu Direct, etc.) that supply it via API.
      #
      # `subject` can be a frontmatter Hash, a Page-like object (with
      # `.frontmatter`), or a slug string (looked up in the
      # publication / bundle / series collections).
      #
      # Markup uses the `.folio-button .folio-button--buy` / `--cart`
      # class family — the visual treatment is kept for continuity with
      # Folio's storefront so sites mixing engine output with
      # Folio-embedded HTML get a consistent look. The class names are
      # a CSS convention, not an indication that the data must come
      # from Folio.
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

      private

      # Accept Hash, Page-like, or String (slug). Returns the
      # frontmatter Hash for the publication / bundle / series, or nil
      # if the input doesn't resolve. Used by `buy_button` /
      # `cart_button` so templates can pass `page.frontmatter`, a `pub`
      # Hash, or a bare slug interchangeably.
      def resolve_frontmatter(subject)
        case subject
        when Hash then subject
        when String, Symbol
          slug = subject.to_s
          publication_for(slug) || bundle_for(slug) || series_for(slug)
        else
          subject.respond_to?(:frontmatter) ? subject.frontmatter : nil
        end
      end

    end
  end
end

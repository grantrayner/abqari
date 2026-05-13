# frozen_string_literal: true

module Abqari
  class RenderContext
    # Image / icon / asset-path helpers. Lifted out of RenderContext so
    # the main class can stay focused on templating; the behaviour is
    # unchanged. Every method that emits markup returns already-safe
    # HTML — templates interpolate via `<%==`.
    module PictureHelpers
      HEROICON_VARIANTS = {
        outline: '24/outline',
        solid:   '24/solid',
        mini:    '20/solid',
        micro:   '16/solid'
      }.freeze

      def asset_path(name)
        site.assets.path_for(name)
      end

      # Like `asset_path`, but returns nil instead of raising when the
      # asset doesn't exist. Used to conditionally include opt-in site-
      # local assets like `app/assets/css/site.css` — sites declare one
      # when they want to add overrides on top of theme + _common.css;
      # most sites don't, so the link should silently disappear.
      def optional_asset_path(name)
        site.assets.path_for(name)
      rescue ArgumentError
        nil
      end

      def picture_tag(source, alt: '', sizes: nil, widths: nil)
        site.images.picture_tag(source, alt: alt, sizes: sizes, widths: widths)
      end

      # Site-local SVG icon. Hybrid path — a site can drop
      # `app/icons/<name>.svg` to override an engine-bundled icon or
      # add its own.
      def icon(name, **attrs)
        path = site.find_in_paths(File.join('app', 'icons', "#{name}.svg"))
        return '' unless File.exist?(path)

        svg = File.read(path, encoding: 'UTF-8')
        return svg if attrs.empty?

        attrs_str = attrs.map { |k, v| %(#{h(k.to_s)}="#{h(v.to_s)}") }.join(' ')
        svg.sub(/<svg([^>]*)>/) { "<svg#{::Regexp.last_match(1)} #{attrs_str}>" }
      end

      # Inline a Heroicon SVG. Reads from vendor/heroicons/<variant>/
      # <name>.svg at render time and inlines it directly — no extra
      # HTTP request, no webfont, no CSP changes (everything is same-
      # origin static markup). Color and size flow through CSS.
      #
      # Variants map to the Heroicons folder layout:
      #   :outline → 24/outline (24×24 stroke, default)
      #   :solid   → 24/solid   (24×24 filled)
      #   :mini    → 20/solid   (20×20 filled, smaller UI)
      #   :micro   → 16/solid   (16×16 filled, very small UI)
      #
      # Returns '' (renders nothing) when the icon name isn't found, so
      # a typo doesn't fail the build — just an empty span. List of
      # icon names: https://heroicons.com/
      def heroicon(name, variant: :outline, **attrs)
        subdir = HEROICON_VARIANTS[variant.to_sym] or return ''
        # Heroicons are engine-bundled — they ship in the gem.
        path = File.join(site.engine_root, 'vendor', 'heroicons', subdir, "#{name}.svg")
        return '' unless File.exist?(path)

        svg = File.read(path, encoding: 'UTF-8')
        return svg if attrs.empty?

        attrs_str = attrs.map { |k, v| %(#{h(k.to_s)}="#{h(v.to_s)}") }.join(' ')
        svg.sub(/<svg([^>]*)>/) { "<svg#{::Regexp.last_match(1)} #{attrs_str}>" }
      end

      # Resolve a relative bundle-asset filename to an absolute URL by
      # prepending the current page's URL. Passes through absolute
      # paths (`/foo`), full URLs (`https://…`), and anchors (`#foo`)
      # unchanged.
      #
      # Used in layouts to render frontmatter image fields that point
      # at colocated assets — e.g. `image: hero.jpg` in a post or
      # workshop frontmatter. Markdown body images get auto-rewritten
      # by the build's post-processor, but frontmatter values bypass
      # that pass; this helper closes the gap.
      #
      # Pair with `sanitized_url` for safe HTML output:
      #     <img src="<%= sanitized_url(bundle_asset_url(hero)) %>" …>
      def bundle_asset_url(path)
        bundle_asset_url_for(page, path)
      end

      # Like `bundle_asset_url`, but resolves relative paths against
      # the given `item`'s URL rather than the current `page`. Used by
      # listing partials (post list, related items, etc.) that render
      # image fields for many items while the active `page` is the
      # index.
      def bundle_asset_url_for(item, path)
        s = path.to_s
        return s if s.empty? || s.start_with?('/', 'http://', 'https://', '#')

        base = item.respond_to?(:url) ? item.url : item.to_s
        "#{base}#{s}"
      end

      # Bundle-aware <picture> renderer. Emits a multi-source picture
      # element when sibling AVIF or WebP files exist alongside the
      # given image in the page's bundle directory, falling back to a
      # plain <img> otherwise.
      #
      # Convention-over-configuration: the engine doesn't process
      # raster bundle assets at build time (that's image_pipeline's
      # job, and it currently only operates on `app/assets/images/`).
      # This helper checks the bundle dir for sibling files at
      # render time. To take advantage, generate `hero.avif` and
      # `hero.webp` next to your `hero.jpg`, e.g. via:
      #     vips webpsave hero.jpg hero.webp --Q 80
      #     vips avifsave hero.jpg hero.avif --Q 50
      # SVG sources skip picture entirely — they don't benefit from
      # format negotiation.
      def bundle_picture_tag(page, image, alt:, class_: nil, loading: 'eager', fetchpriority: 'high')
        img_url = sanitized_url(bundle_asset_url_for(page, image))
        attrs = []
        attrs << %(class="#{h(class_)}")            if class_
        attrs << %(src="#{img_url}")
        attrs << %(alt="#{h(alt)}")
        attrs << %(loading="#{loading}")
        attrs << %(fetchpriority="#{fetchpriority}") if fetchpriority
        attrs << 'decoding="async"'
        plain_img = "<img #{attrs.join(' ')}>"

        # SVG sources don't benefit from a picture wrapper.
        return plain_img if image.to_s.end_with?('.svg')

        # Look up bundle dir on disk to check for AVIF/WebP siblings.
        return plain_img unless page.respond_to?(:bundle_dir) && page.bundle_dir

        basename = File.basename(image.to_s, File.extname(image.to_s))
        avif_path = File.join(page.bundle_dir, "#{basename}.avif")
        webp_path = File.join(page.bundle_dir, "#{basename}.webp")
        avif_exists = File.exist?(avif_path)
        webp_exists = File.exist?(webp_path)

        return plain_img unless avif_exists || webp_exists

        sources = []
        if avif_exists
          avif_url = sanitized_url(bundle_asset_url_for(page, "#{basename}.avif"))
          sources << %(<source type="image/avif" srcset="#{avif_url}">)
        end
        if webp_exists
          webp_url = sanitized_url(bundle_asset_url_for(page, "#{basename}.webp"))
          sources << %(<source type="image/webp" srcset="#{webp_url}">)
        end

        "<picture>#{sources.join}#{plain_img}</picture>"
      end
    end
  end
end

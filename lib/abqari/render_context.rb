# frozen_string_literal: true

require 'yaml'
require_relative 'erbi_template'
require_relative 'helpers'
require_relative 'render_context/publication_helpers'
require_relative 'render_context/picture_helpers'
require_relative 'render_context/cover_helpers'

module Abqari
  # The binding ERB templates execute against. Holds references to
  # the current page and site, includes shared helper mixins.
  #
  # Decomposed for readability — the helpers split into:
  #
  #   - `Helpers`              : core scalar helpers (h, sanitized_url,
  #                               local_time, pluralize, truncate, link_to,
  #                               slugify, …). Engine-wide.
  #   - `PublicationHelpers`   : publication/bundle/series accessors,
  #                               buy/cart buttons. Publisher-agnostic —
  #                               see lib/abqari/render_context/
  #                               publication_helpers.rb.
  #   - `PictureHelpers`       : asset_path, icon, heroicon, picture_tag,
  #                               bundle_picture_tag, bundle_asset_url.
  #
  # Templating-specific surface (render, render_layout, render_string,
  # yield_content, get_binding) stays here.
  class RenderContext
    include Helpers
    include PublicationHelpers
    include PictureHelpers
    include CoverHelpers

    attr_reader :page, :site

    # Instance variables intentionally exposed to templates via the
    # `binding` ERB receives. Anything outside this set should use
    # the `@_` convention so a stray `<%= @foo %>` is clearly out-of-
    # contract. The audit test `RenderContextInternalIvarTest` reads
    # this list and fails if RenderContext grows an ivar that's
    # neither in the allow-list nor `@_`-prefixed.
    TEMPLATE_PUBLIC_IVARS = %i[@page @site].freeze

    # Local names that must never be shadowed by a `render(..., key: v)`
    # local — doing so would silently replace the escaping function or a
    # core API method for that partial. `page` is deliberately NOT here:
    # rebinding it (`render 'partials/card', page: item`) is a supported
    # pattern.
    RESERVED_LOCALS = %i[h sanitized_url site render render_layout render_string
                         script_safe_json get_binding yield_content].freeze

    def initialize(page, site, locals = {})
      @page = page
      @site = site
      locals.each do |key, value|
        if RESERVED_LOCALS.include?(key.to_sym)
          raise ArgumentError,
                "render local #{key.inspect} would shadow the core helper of the same name — rename it"
        end
        define_singleton_method(key) { value }
      end
    end

    def render(partial, **locals)
      context = RenderContext.new(page, site, locals)
      site.compiled_template(partial_path(partial)).result(context.get_binding)
    end

    # Render a layout, with optional chaining via the layout's own
    # frontmatter. A layout can declare `layout: <parent>` at the top
    # of its file (Jekyll-style); the engine renders the inner layout
    # first, then wraps the result in the parent layout, and so on
    # recursively until it reaches a layout with no parent.
    #
    # The wrapping layout reads the inner output via `<%== yield_content %>`
    # (raw — the inner layout's output is already escaped HTML, escaping
    # it again would render tags as text).
    #
    # Frontmatter on layouts:
    #   ---
    #   layout: application       # this layout extends application.html.erb
    #   ---
    def render_layout(name, seen = [])
      # Cycle guard. A layout chain that loops (`a` extends `b` extends
      # `a`, or a layout that extends itself) would recurse forever and
      # blow the stack with a `SystemStackError` — which isn't a
      # `StandardError`, so it escapes the renderer's per-page rescue
      # and crashes a worker thread with no layout name attached. Fail
      # with the actual cycle instead.
      if seen.include?(name)
        raise "layout cycle detected: #{(seen + [name]).join(' -> ')}"
      end
      seen = seen + [name]

      # Layouts are hybrid: site override wins, engine version is the
      # fallback. Users override a layout by dropping their own copy
      # at `app/views/layouts/<name>.html.erb` in the site root.
      path = site.find_in_paths(File.join('app', 'views', 'layouts', "#{name}.html.erb"))
      unless File.exist?(path)
        raise "layout #{name.inspect} not found (searched site root then engine root: " \
              "#{File.join('app', 'views', 'layouts', "#{name}.html.erb")})"
      end
      raw = File.read(path, encoding: 'UTF-8')

      layout_fm, body = parse_layout_frontmatter(raw)

      template = ErbiTemplate.new(body, path)
      inner    = template.result(get_binding)

      parent = layout_fm['layout']
      return inner unless parent

      @_yielded_content = inner
      render_layout(parent.to_s, seen)
    end

    # The output of the inner layout, available inside a wrapping layout
    # as `<%== yield_content %>`. Returns '' at the leaf level (the layout
    # being rendered direct from a page, with no inner layout wrapping it).
    #
    # The backing ivar is intentionally `@_yielded_content` (leading
    # underscore = "internal, don't touch"). ERB templates get the full
    # binding via `get_binding`, so every RenderContext ivar is one
    # `<%= @whatever %>` typo away from being usable. The underscore
    # convention plus the `RenderContextInternalIvarTest` audit pin
    # the contract: only `page` and `site` are intended template-
    # accessible state; helper method results carry the rest.
    def yield_content
      @_yielded_content.to_s
    end

    # The <title> text: "Page · Site", except when the two are the same
    # string — the home page usually titles itself after the site, and
    # "Mysite · Mysite" reads like a bug in the browser tab.
    def document_title
      page_title = page.title.to_s
      site_title = site.config['title'].to_s
      return site_title if page_title.empty? || page_title == site_title

      "#{page_title} · #{site_title}"
    end

    # Render an ERB string against this context. Used by Page#rendered_body
    # to support `erb: true` opt-in templating in markdown bodies. No
    # template caching — these strings are one-off per build.
    def render_string(template)
      label = page.respond_to?(:source_path) && page.source_path ? "#{page.source_path} (erb body)" : '(erb body)'
      ErbiTemplate.new(template, label).result(get_binding)
    end

    # Slug-aware "back to index" data for a show-view page. Returns the
    # URL of the page's collection index, honoring `slug:` aliasing —
    # e.g. a post in the `posts` collection with `slug: stories` returns
    # `/stories/`. Returns nil for pages outside any collection.
    def collection_index_url(target = page)
      # Accept either a Page (resolve via `effective_collection_name`)
      # or a collection name string directly — the latter is useful
      # from contexts that aren't in any collection (e.g. the home
      # page's photo modules linking to /photos/).
      name = target.is_a?(String) ? target : effective_collection_name(target)
      return nil unless name

      cfg = site.collection_config(name)
      slug = cfg['slug'].to_s
      "/#{slug.empty? ? name : slug}/"
    end

    # Display label for the collection index — slug if set, canonical
    # name otherwise.
    def collection_index_label(target = page)
      name = target.is_a?(String) ? target : effective_collection_name(target)
      return nil unless name

      cfg = site.collection_config(name)
      slug = cfg['slug'].to_s
      slug.empty? ? name : slug
    end

    # URL of a taxonomy term page, honouring the configured permalink
    # so slug-aliasing works. Replaces hardcoded patterns like
    # `"/tags/#{slugify(term)}/"` in show-view layouts.
    #   taxonomy_url('tags',      'fiction')   → "/tags/fiction/"
    #   taxonomy_url('countries', 'Syria')     → "/country/syria/"   (per config)
    def taxonomy_url(taxonomy_name, term)
      cfg = site.taxonomy_config(taxonomy_name.to_s)
      permalink = cfg['permalink'] || "/#{taxonomy_name}/:slug/"
      permalink.sub(':slug', slugify(term))
    end

    # URL of the series index that covers `target`'s collection.
    # Resolves the owning taxonomy first, so a layout shared between
    # collections links each one to its own series index:
    #
    #   series_url('Inside Abqari')            → "/guides/series/inside-abqari/"
    #   series_url('Module 1', lesson_page)    → "/lessons/module/module-1/"
    #
    # Returns nil when the page's collection has no series taxonomy
    # configured — callers render the series name as plain text rather
    # than linking it somewhere that was never built.
    def series_url(term, target = page)
      name = site.series_taxonomy_for(effective_collection_name(target))
      name && taxonomy_url(name, term)
    end

    def get_binding
      binding
    end

    private

    # Resolve a page to its collection name. Handles three shapes:
    #   - Content pages (Page#collection): direct lookup.
    #   - Externally-sourced pages (PublisherShowPage#kind): map kind
    #     to the canonical collection ('publication' → 'publications',
    #     'bundle' → 'bundles', 'series' → 'series').
    #   - Anything else (top-level pages, generated index pages): nil.
    KIND_TO_COLLECTION = {
      'publication' => 'publications',
      'bundle'      => 'bundles',
      'series'      => 'series'
    }.freeze

    def effective_collection_name(target_page)
      if target_page.respond_to?(:collection) && target_page.collection
        target_page.collection
      elsif target_page.respond_to?(:kind)
        KIND_TO_COLLECTION[target_page.kind.to_s]
      end
    end

    def partial_path(partial)
      parts = partial.split('/')
      filename = "_#{parts.pop}.html.erb"
      # Partials are hybrid like layouts — site override wins.
      site.find_in_paths(File.join('app', 'views', *parts, filename))
    end

    # Layout frontmatter — same `---` ... `---` pattern as content pages
    # (Abqari::FRONTMATTER_RE), but only `layout:` is honoured (used to
    # chain into a parent layout). Returns [parsed_hash,
    # body_after_frontmatter]. Returns [{}, raw] if no frontmatter is
    # present, so layouts without it work unchanged.
    def parse_layout_frontmatter(raw)
      if (match = raw.match(Abqari::FRONTMATTER_RE))
        [YAML.safe_load(match[1], permitted_classes: Abqari::YAML_PERMITTED_CLASSES) || {}, match[2]]
      else
        [{}, raw]
      end
    end
  end
end

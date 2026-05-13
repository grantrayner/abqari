# frozen_string_literal: true

require 'yaml'
require_relative 'erbi_template'
require_relative 'helpers'
require_relative 'render_context/folio_helpers'
require_relative 'render_context/picture_helpers'

module Abqari
  # The binding ERB templates execute against. Holds references to
  # the current page and site, includes shared helper mixins.
  #
  # Decomposed for readability — the helpers split into:
  #
  #   - `Helpers`         : core scalar helpers (h, sanitized_url,
  #                          local_time, pluralize, truncate, link_to,
  #                          slugify, …). Engine-wide.
  #   - `FolioHelpers`    : Folio data accessors, buy/cart buttons.
  #   - `PictureHelpers`  : asset_path, icon, heroicon, picture_tag,
  #                          bundle_picture_tag, bundle_asset_url.
  #
  # Templating-specific surface (render, render_layout, render_string,
  # yield_content, get_binding) stays here.
  class RenderContext
    include Helpers
    include FolioHelpers
    include PictureHelpers

    attr_reader :page, :site

    def initialize(page, site, locals = {})
      @page = page
      @site = site
      locals.each { |key, value| define_singleton_method(key) { value } }
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
    def render_layout(name)
      # Layouts are hybrid: site override wins, engine version is the
      # fallback. Users override a layout by dropping their own copy
      # at `app/views/layouts/<name>.html.erb` in the site root.
      path = site.find_in_paths(File.join('app', 'views', 'layouts', "#{name}.html.erb"))
      raw  = File.read(path, encoding: 'UTF-8')

      layout_fm, body = parse_layout_frontmatter(raw)

      template = ErbiTemplate.new(body)
      inner    = template.result(get_binding)

      parent = layout_fm['layout']
      return inner unless parent

      @yielded_content = inner
      render_layout(parent.to_s)
    end

    # The output of the inner layout, available inside a wrapping layout
    # as `<%== yield_content %>`. Returns '' at the leaf level (the layout
    # being rendered direct from a page, with no inner layout wrapping it).
    def yield_content
      @yielded_content.to_s
    end

    # Render an ERB string against this context. Used by Page#rendered_body
    # to support `erb: true` opt-in templating in markdown bodies. No
    # template caching — these strings are one-off per build.
    def render_string(template)
      ErbiTemplate.new(template).result(get_binding)
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

    def get_binding
      binding
    end

    private

    # Resolve a page to its collection name. Handles three shapes:
    #   - Content pages (Page#collection): direct lookup.
    #   - Folio auto-generated pages (FolioShowPage#kind): map kind to
    #     the canonical collection ('publication' → 'publications',
    #     'bundle' → 'bundles', 'series' → 'series').
    #   - Anything else (top-level pages, generated index pages): nil.
    FOLIO_KIND_TO_COLLECTION = {
      'publication' => 'publications',
      'bundle'      => 'bundles',
      'series'      => 'series'
    }.freeze

    def effective_collection_name(target_page)
      if target_page.respond_to?(:collection) && target_page.collection
        target_page.collection
      elsif target_page.respond_to?(:kind)
        FOLIO_KIND_TO_COLLECTION[target_page.kind.to_s]
      end
    end

    def partial_path(partial)
      parts = partial.split('/')
      filename = "_#{parts.pop}.html.erb"
      # Partials are hybrid like layouts — site override wins.
      site.find_in_paths(File.join('app', 'views', *parts, filename))
    end

    # Layout frontmatter — same `---` ... `---` pattern as content pages,
    # but only `layout:` is honoured (used to chain into a parent layout).
    # Returns [parsed_hash, body_after_frontmatter]. Returns [{}, raw] if
    # no frontmatter is present, so layouts without it work unchanged.
    LAYOUT_FRONTMATTER_RE = /\A---\s*\n(.*?\n)---\s*\n(.*)/m.freeze

    def parse_layout_frontmatter(raw)
      if (match = raw.match(LAYOUT_FRONTMATTER_RE))
        [YAML.safe_load(match[1]) || {}, match[2]]
      else
        [{}, raw]
      end
    end
  end
end

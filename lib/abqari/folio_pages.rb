# frozen_string_literal: true

require 'fileutils'

module Abqari
  # Auto-generates index + show pages for Folio publications, bundles, and
  # series. Runs only when `folio:` config is set. Each generated page can
  # be overridden by creating a markdown file at the matching path
  # (e.g. content/publications/<slug>/index.md) — abqari skips
  # auto-generation for any URL that already has a Page from content/.
  #
  # Folio publications populate the canonical `publications` collection.
  # No separate `books` collection — sites that want /books/ URLs set
  # `publications.slug: books` in config.
  #
  # Bundles and series are meta-collections (groups of publications) and
  # remain separate. Their URLs default to /bundles/ and /series/ but
  # also follow the `bundles.slug` / `series.slug` overrides if set.
  class FolioPages
    def initialize(site)
      @site = site
    end

    def enabled?
      @site.config['folio'].is_a?(Hash) && !@site.config['folio'].empty?
    end

    # Returns auto-generated pages: up to three index pages (publications
    # / bundles / series) and one show page per Folio publication, bundle,
    # and series.
    def pages
      return [] unless enabled?

      result = []
      result.concat(index_pages)
      result.concat(publication_pages)
      result.concat(bundle_pages)
      result.concat(series_pages)
      result
    end

    private

    def existing_urls
      @existing_urls ||= @site.pages.map(&:url).to_set
    end

    # The collection-permalink-derived index URL for a kind. Honors the
    # collection's `slug:` aliasing. Falls back to /<kind>/ when there's
    # no permalink defined (shouldn't happen for built-in kinds).
    def kind_url_prefix(collection_name, fallback)
      cfg = @site.collection_config(collection_name)
      slug = cfg['slug'].to_s
      return "/#{slug}/" unless slug.empty?
      perm = cfg['permalink'].to_s
      perm.empty? ? "/#{fallback}/" : perm.sub(':slug/', '').sub(':slug', '')
    end

    # Generate one index page per Folio kind (publications / bundles /
    # series). Skip when:
    #   - The user has a hand-written page at that URL (their override wins).
    #   - The underlying collection is empty — shipping a `/series/` index
    #     when Folio returned zero series produces a placeholder page that
    #     just says "Series" with no entries. Better to omit entirely; the
    #     URL becomes a 404, which is honest. The page reappears the
    #     moment Folio returns at least one item.
    def index_pages
      kinds = [
        { name: 'publications', layout: 'publications_index', data: 'folio_publications' },
        { name: 'bundles',      layout: 'bundles_index',      data: 'folio_bundles'      },
        { name: 'series',       layout: 'book_series_index',  data: 'folio_series'       }
      ]
      kinds.filter_map do |kind|
        url = kind_url_prefix(kind[:name], kind[:name])
        next if existing_urls.include?(url)
        next if (@site.data[kind[:data]] || {}).empty?

        FolioIndexPage.new(@site, kind[:name], kind[:layout], url)
      end
    end

    # Folio publications → pages in the `publications` collection. Layout
    # comes from the collection config so `publications.layout: book` (or
    # default `publication`) routes through the right template.
    def publication_pages
      cfg = @site.collection_config('publications')
      url_prefix = kind_url_prefix('publications', 'publications')
      layout = cfg['layout'] || 'publication'

      Array(@site.data['folio_publications']).filter_map do |slug, pub|
        url = "#{url_prefix}#{slug}/"
        next if existing_urls.include?(url)

        FolioShowPage.new(@site, kind: 'publication', slug: slug, data: pub, layout: layout, url: url)
      end
    end

    def bundle_pages
      cfg = @site.collection_config('bundles')
      url_prefix = kind_url_prefix('bundles', 'bundles')
      layout = cfg['layout'] || 'bundle'

      Array(@site.data['folio_bundles']).filter_map do |slug, bundle|
        url = "#{url_prefix}#{slug}/"
        next if existing_urls.include?(url)

        FolioShowPage.new(@site, kind: 'bundle', slug: slug, data: bundle, layout: layout, url: url)
      end
    end

    def series_pages
      cfg = @site.collection_config('series')
      url_prefix = kind_url_prefix('series', 'series')
      layout = cfg['layout'] || 'series'

      Array(@site.data['folio_series']).filter_map do |slug, series|
        url = "#{url_prefix}#{slug}/"
        next if existing_urls.include?(url)

        FolioShowPage.new(@site, kind: 'series', slug: slug, data: series, layout: layout, url: url)
      end
    end
  end

  # Index page for a kind (books/bundles/series). Renders the matching
  # _index layout, which iterates over site.data['folio_*'] internally.
  class FolioIndexPage
    attr_reader :site, :kind

    def initialize(site, kind, layout, url)
      @site   = site
      @kind   = kind
      @layout = layout
      @url    = url
    end

    def title
      @kind.capitalize
    end

    def description
      "All #{@kind}."
    end

    def content
      ''
    end

    def frontmatter
      {}
    end

    def url
      @url
    end

    # Folio is bounded-trust per docs/security.md §1, and the Folio
    # `slug` flows directly into this URL. Route through PathSafe so a
    # hostile or accidental `"slug": "../../etc"` in a Folio response
    # raises a build error instead of writing outside `_site/`.
    def output_path
      PathSafe.join_under(@site.output_dir, @url.sub(%r{\A/}, '').chomp('/'), 'index.html')
    end

    def write
      FileUtils.mkdir_p(File.dirname(output_path))
      File.write(output_path, @site.post_process(render, page: self))
    end

    def needs_render?
      return true unless File.exist?(output_path)

      File.mtime(output_path) < @site.shared_deps_mtime
    end

    def lastmod
      Time.now
    end

    def bundle_images
      []
    end

    private

    def render
      RenderContext.new(self, @site).render_layout(@layout)
    end
  end

  # Show page for a single publication / bundle / series. Looks like a
  # regular `Page` to the rest of the engine: same `frontmatter`,
  # `title`, `description`, `collection` interface, so templates
  # iterate `site.collection('publications')` and don't need to know
  # whether a particular entry came from `content/` or Folio.
  #
  # The Folio payload IS the frontmatter — the API returns canonical
  # field names (`title`, `excerpt`, `cover_url`, `price`,
  # `buy_now_url`, `in_series`, …) per docs/publications.md, so no
  # translation layer is needed.
  class FolioShowPage
    # Map `kind:` to the collection name `site.collection` exposes.
    # Folio's three kinds line up 1:1 with Abqari's three collections.
    KIND_TO_COLLECTION = {
      'publication' => 'publications',
      'bundle'      => 'bundles',
      'series'      => 'series'
    }.freeze

    attr_reader :site, :kind, :slug, :data

    def initialize(site, kind:, slug:, data:, layout:, url:)
      @site   = site
      @kind   = kind
      @slug   = slug
      @data   = data
      @layout = layout
      @url    = url
    end

    # Collection membership. Returns `'publications'` / `'bundles'` /
    # `'series'`, which lets `Site#collection(name)` include this page
    # in its iteration alongside manual Pages.
    def collection
      KIND_TO_COLLECTION[@kind.to_s]
    end

    # Publications use `title`; bundles + series use `name`. Falls
    # back to the slug so callers always get a string.
    def title
      @data['title'] || @data['name'] || @slug
    end

    # `description` is the page's short-summary text — used by
    # sitemap, RSS, OG, JSON-LD. Per docs/publications.md:
    # publications use `tagline` then `excerpt`; bundles + series use
    # `description`. The first line keeps it summary-shaped.
    def description
      raw = case collection
            when 'publications'
              @data['tagline'] || @data['excerpt']
            else
              @data['description']
            end
      raw.to_s.lines.first&.strip
    end

    def content
      ''
    end

    # Folio payload IS the frontmatter. Adds two engine-only
    # bookkeeping keys (`folio_kind`, `folio_slug`) for any partial
    # that needs to know this is a Folio-sourced entry — but
    # everything else lives under canonical names.
    def frontmatter
      @data.merge('folio_kind' => @kind, 'folio_slug' => @slug)
    end

    def url
      @url
    end

    # See FolioIndexPage#output_path — same trust boundary, same routing.
    def output_path
      PathSafe.join_under(@site.output_dir, @url.sub(%r{\A/}, '').chomp('/'), 'index.html')
    end

    def write
      FileUtils.mkdir_p(File.dirname(output_path))
      File.write(output_path, @site.post_process(render, page: self))
    end

    def needs_render?
      return true unless File.exist?(output_path)

      output_mtime = File.mtime(output_path)
      return true if @site.shared_deps_mtime > output_mtime

      # If the Folio cache is newer than this page's output, re-render —
      # the underlying data may have changed since last build.
      cache_path = File.join(@site.site_root, 'vendor', 'folio', "#{kind}s.yml")
      File.exist?(cache_path) && File.mtime(cache_path) > output_mtime
    end

    def lastmod
      cache_path = File.join(@site.site_root, 'vendor', 'folio', "#{kind}s.yml")
      File.exist?(cache_path) ? File.mtime(cache_path) : Time.now
    end

    def bundle_images
      []
    end

    private

    def render
      RenderContext.new(self, @site).render_layout(@layout)
    end
  end
end

# frozen_string_literal: true

require 'fileutils'

module Abqari
  # Auto-generates index + show pages for publications, bundles, and
  # series whose data comes from an external publisher integration
  # (currently Folio — `apps/folio` — with the door open for others
  # that emit canonical-shape data per docs/publications.md).
  #
  # Runs only when `folio:` config is set (today). Each generated page
  # can be overridden by creating a markdown file at the matching path
  # (e.g. `content/publications/<slug>/index.md`); the engine skips
  # auto-generation for any URL that already has a Page from
  # `content/`. The override page wins on slug collision.
  class PublisherPages
    def initialize(site)
      @site = site
    end

    def enabled?
      @site.config['folio'].is_a?(Hash) && !@site.config['folio'].empty?
    end

    # Returns auto-generated pages: up to three index pages (publications
    # / bundles / series) and one show page per externally-sourced
    # publication, bundle, and series.
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

    # Generate one index page per kind (publications / bundles /
    # series). Skip when:
    #   - The user has a hand-written page at that URL (their override wins).
    #   - The publisher returned zero items for the kind — auto-
    #     generating an empty `/series/` placeholder isn't useful.
    #     The page reappears the moment the publisher returns at
    #     least one item.
    #
    # Manual-only sites (no publisher configured) get no auto-index
    # here — but the bundles_index / book_series_index layouts read
    # from `site.collection(...)`, so a user who creates
    # `content/bundles/index.md` (or `content/series/index.md`) sees
    # their manual entries listed without any further wiring.
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

        PublisherIndexPage.new(@site, kind[:name], kind[:layout], url)
      end
    end

    # Externally-sourced publications → pages in the `publications`
    # collection. Layout comes from the collection config so
    # `publications.layout: book` (or default `publication`) routes
    # through the right template.
    def publication_pages
      cfg = @site.collection_config('publications')
      url_prefix = kind_url_prefix('publications', 'publications')
      layout = cfg['layout'] || 'publication'

      Array(@site.data['folio_publications']).filter_map do |slug, pub|
        url = "#{url_prefix}#{slug}/"
        next if existing_urls.include?(url)

        PublisherShowPage.new(@site, kind: 'publication', slug: slug, data: pub, layout: layout, url: url)
      end
    end

    def bundle_pages
      cfg = @site.collection_config('bundles')
      url_prefix = kind_url_prefix('bundles', 'bundles')
      layout = cfg['layout'] || 'bundle'

      Array(@site.data['folio_bundles']).filter_map do |slug, bundle|
        url = "#{url_prefix}#{slug}/"
        next if existing_urls.include?(url)

        PublisherShowPage.new(@site, kind: 'bundle', slug: slug, data: bundle, layout: layout, url: url)
      end
    end

    def series_pages
      cfg = @site.collection_config('series')
      url_prefix = kind_url_prefix('series', 'series')
      layout = cfg['layout'] || 'series'

      Array(@site.data['folio_series']).filter_map do |slug, series|
        url = "#{url_prefix}#{slug}/"
        next if existing_urls.include?(url)

        PublisherShowPage.new(@site, kind: 'series', slug: slug, data: series, layout: layout, url: url)
      end
    end
  end

  # Index page for a kind (publications / bundles / series). Renders
  # the matching collection-index layout, which iterates the merged
  # `site.collection(name)` (manual + externally-sourced).
  class PublisherIndexPage
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

    # Bounded-trust external data per docs/security.md §1. The `slug`
    # flows into this URL — route through `PathSafe` so a hostile or
    # accidental `"slug": "../../etc"` raises a build error instead
    # of writing outside `_site/`.
    def output_path
      PathSafe.join_under(@site.output_dir, @url.sub(%r{\A/}, '').chomp('/'), 'index.html')
    end

    def write
      FileUtils.mkdir_p(File.dirname(output_path))
      File.write(output_path, @site.post_process(render, page: self))
    end

    def layout_name
      @layout
    end

    def needs_render?
      return true unless File.exist?(output_path)

      output_mtime = File.mtime(output_path)
      return true if output_mtime < @site.shared_deps_mtime
      # Layouts are tracked per-page rather than in GLOBAL_DEP_GLOBS —
      # without this, editing `publications_index.html.erb` left the
      # index stale on the dev server.
      @site.layout_deps_mtime(layout_name) > output_mtime
    end

    def lastmod
      Time.now
    end

    def bundle_images
      []
    end

    private

    def render
      RenderContext.new(self, @site).render_layout(layout_name)
    end
  end

  # Show page for a single externally-sourced publication / bundle /
  # series. Looks like a regular `Page` to the rest of the engine —
  # same `frontmatter`, `title`, `description`, `collection` interface
  # — so templates iterate `site.collection('publications')` (etc.)
  # and don't need to know whether a particular entry came from
  # `content/` or an external publisher.
  #
  # The publisher's payload IS the frontmatter — the canonical schema
  # (docs/publications.md) lines up with what the publisher emits, so
  # no translation layer is needed.
  class PublisherShowPage
    # Map `kind:` to the collection name `site.collection` exposes.
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

    # Publications use `title`; bundles + series use `name` (matches
    # Folio's vocabulary — see docs/publications.md). Falls back to
    # the slug so callers always get a string.
    def title
      @data['title'] || @data['name'] || @slug
    end

    # Page short-summary text — used by sitemap, RSS, OG, JSON-LD.
    # Per docs/publications.md: publications use `tagline` then
    # `excerpt`; bundles + series use `description`. The first line
    # keeps it summary-shaped.
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

    # The data payload IS the frontmatter. No bookkeeping keys — the
    # canonical schema covers everything templates need to know;
    # templates can't and shouldn't care whether the data came from
    # an external publisher.
    def frontmatter
      @data
    end

    def url
      @url
    end

    # See PublisherIndexPage#output_path — same trust boundary, same routing.
    def output_path
      PathSafe.join_under(@site.output_dir, @url.sub(%r{\A/}, '').chomp('/'), 'index.html')
    end

    def write
      FileUtils.mkdir_p(File.dirname(output_path))
      File.write(output_path, @site.post_process(render, page: self))
    end

    def layout_name
      @layout
    end

    def needs_render?
      return true unless File.exist?(output_path)

      output_mtime = File.mtime(output_path)
      return true if @site.shared_deps_mtime > output_mtime
      # Layouts are tracked per-page rather than in GLOBAL_DEP_GLOBS —
      # without this, editing `publication.html.erb` left every show
      # page stale on the dev server.
      return true if @site.layout_deps_mtime(layout_name) > output_mtime

      # If the publisher cache is newer than this page's output, re-render —
      # the underlying data may have changed since last build.
      cache_path = folio_cache_path
      cache_path && File.exist?(cache_path) && File.mtime(cache_path) > output_mtime
    end

    def lastmod
      cache_path = folio_cache_path
      cache_path && File.exist?(cache_path) ? File.mtime(cache_path) : Time.now
    end

    # On-disk Folio cache backing this page's kind.
    #
    # Derived from KIND_TO_COLLECTION rather than pluralising `kind`.
    # `"#{kind}s.yml"` gets publications and bundles right and produces
    # `seriess.yml` for series — a file that never exists, so series
    # pages never noticed a stale cache (no re-render when Folio data
    # changed) and fell through to the `Time.now` lastmod, restamping
    # every series page's sitemap entry on every build. The determinism
    # test couldn't catch it: both builds run on the same day.
    #
    # The collection names ARE the cache basenames, so reusing the map
    # keeps the two from drifting again.
    def folio_cache_path
      basename = KIND_TO_COLLECTION[@kind.to_s]
      return nil unless basename

      File.join(@site.site_root, 'vendor', 'folio', "#{basename}.yml")
    end

    def bundle_images
      []
    end

    private

    def render
      RenderContext.new(self, @site).render_layout(layout_name)
    end
  end

end

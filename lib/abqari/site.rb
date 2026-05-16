# frozen_string_literal: true

require 'set'

require_relative 'site_loader'
require_relative 'renderer'
require_relative 'artifact_writer'

module Abqari
  # Site is the public façade and orchestrator. The heavy lifting lives
  # in three collaborators:
  #
  #   - SiteLoader    : config + pages + data ingestion, nav/footer cascade
  #   - Renderer      : page generators, parallel render, post-process,
  #                     template cache, shared-deps mtime
  #   - ArtifactWriter: output dir reset, public/ + fonts + d3 copying,
  #                     sitemap/feed/robots/etc.
  #
  # Site retains all read-mostly query helpers (collections, taxonomies,
  # related, featured, posts_by_term, …) and the lookup accessors used
  # from RenderContext and partials (assets, images, visualizations,
  # folio, data, nav_links, footer_links, social_links). The split is
  # internal — the public API is unchanged.
  class Site
    # Built-in collections. `bundles` and `series` are first-class meta-
    # collections — they group `publications` (or anything else the
    # consuming site decides to bundle) into retailable sets. They work
    # standalone (manual content at `content/bundles/<slug>/` and
    # `content/series/<slug>/`) and Folio populates them automatically
    # when configured — same collection name, same layout, same URL
    # pattern either way.
    DEFAULT_COLLECTIONS = {
      'posts' => {
        'source' => 'content/posts',
        'permalink' => '/posts/:slug/',
        'layout' => 'post'
      },
      'photos' => {
        'source' => 'content/photos',
        'permalink' => '/photos/:slug/',
        'layout' => 'photo'
      },
      'publications' => {
        'source' => 'content/publications',
        'permalink' => '/publications/:slug/',
        'layout' => 'publication',
        'bundle' => true
      },
      'bundles' => {
        'source' => 'content/bundles',
        'permalink' => '/bundles/:slug/',
        'layout' => 'bundle',
        'bundle' => true
      },
      'series' => {
        'source' => 'content/series',
        'permalink' => '/series/:slug/',
        'layout' => 'series',
        'bundle' => true
      },
      'workshops' => {
        'source' => 'content/workshops',
        'permalink' => '/workshops/:slug/',
        'layout' => 'workshop',
        'bundle' => true
      }
    }.freeze

    DEFAULT_TAXONOMIES = {
      'tags' => {
        'permalink' => '/tags/:slug/',
        'layout' => 'tag'
      }
    }.freeze

    attr_reader :config, :pages, :generated_pages, :env, :loader, :renderer, :artifacts

    def initialize
      @env = (ENV['ABQARI_ENV'] || 'development').to_sym
      @loader = SiteLoader.new(self)
      raw     = @loader.load_config
      SiteConfig.validate!(raw)
      # Fold static defaults under the user's config so call sites can
      # do `config['indexable']` instead of `config.fetch(..., true)`.
      # Dynamic defaults (minify, env-based) stay in their callers.
      @config = SiteConfig.with_defaults(raw)
      @pages           = []
      @generated_pages = []
      @renderer  = Renderer.new(self)
      @artifacts = ArtifactWriter.new(self)

      # Load site-local plugins (plugins/**/*.rb). Plugins register
      # themselves with `Abqari::Hooks.register(...)` at top level —
      # the registrations land in the global hook table and fire on
      # subsequent `Hooks.run` / `run_filter` calls during build.
      PluginLoader.load_from(site_root)
    end

    # ------------------------------------------------------------------
    # Orchestration
    # ------------------------------------------------------------------

    # build(incremental: false) wipes _site/ and rebuilds everything (default).
    # build(incremental: true) preserves _site/ and uses mtime-aware copying
    # so unchanged files are skipped — used by the dev-server watcher.
    #
    # `apply_timezone!` mutates `ENV['TZ']` so naked dates parse against
    # one consistent zone regardless of where the build runs. That's a
    # process-wide side effect, so we save the prior value and restore
    # it in `ensure` — host processes (test harnesses, dev-server
    # watchers calling `build` repeatedly, applications embedding the
    # gem) get TZ back at the value they had before the build, not
    # `'UTC'` (or whatever the site configured).
    def build(incremental: false)
      @incremental = incremental
      prev_tz = ENV['TZ']
      apply_timezone!

      Hooks.run(:before_build, self)

      @artifacts.reset_output unless incremental
      reset_state_for_rebuild!

      @pages = @loader.load_pages
      Hooks.run(:after_load_pages, self)

      Folio.new(self).fetch                 # publications + bundles, derives series
      @renderer.generate_all                # tag pages, paginated shards, viz, folio, related
      Hooks.run(:after_generate, self)

      assets.process
      images.process

      @artifacts.copy_fonts
      @artifacts.copy_d3
      @renderer.render_pages
      BundleAssets.new(self).copy
      @artifacts.copy_public
      @artifacts.write_deploy_artifacts
      visualizations.write_data
      Search.new(self).run

      Log.info "Built #{all_pages.size} page(s) in #{env}#{incremental ? ' (incremental)' : ''} → _site/"
    ensure
      Hooks.run(:after_build, self) if defined?(@incremental)
      ENV['TZ'] = prev_tz
    end

    def incremental?
      @incremental == true
    end

    # Internal — collaborators only. Generators push into the list with
    # `site.add_generated_page(page)` so the public API stays read-only.
    #
    # Adding a page invalidates the per-collection caches because
    # generated pages that implement `#collection` (FolioShowPage in
    # particular) join their collection — a memoised `collection(name)`
    # result from before this add is now stale. The pagination /
    # related generators call `site.collection` mid-`generate_all`, so
    # invalidating at every add keeps the memo honest without
    # requiring careful generator-ordering.
    def add_generated_page(page)
      @generated_pages << page
      @collection_cache = nil
      @collection_url_index_cache = nil
      @posts_cache = nil if page.respond_to?(:post?) && page.post?
    end

    # ------------------------------------------------------------------
    # Path resolution — two roots.
    #
    # `engine_root` is the abqari gem's location. Where the structural
    # assets live: `_common.css`, layouts/partials, built-in themes,
    # built-in icons, vendored 3rd-party assets (heroicons, d3).
    #
    # `site_root` is the consuming site's location. Where the site-
    # specific stuff lives: `config/site.yml`, `content/`, `data/`,
    # `vendor/folio/`, `public/`, `_site/` (the build output), `audit/`.
    # ------------------------------------------------------------------

    def engine_root
      Abqari::ROOT
    end

    def site_root
      @site_root ||= ENV['ABQARI_SITE_ROOT'] || Dir.pwd
    end

    # Resolve a relative path with site-first, engine-fallback semantics.
    # Returns the site path if a file/dir exists there, otherwise returns
    # the engine path (which may itself not exist — caller checks).
    def find_in_paths(rel)
      site_path = File.join(site_root, rel)
      return site_path if File.exist?(site_path)

      File.join(engine_root, rel)
    end

    def output_dir
      ENV['ABQARI_OUTPUT_DIR'] || File.join(site_root, '_site')
    end

    # ------------------------------------------------------------------
    # Collections
    # ------------------------------------------------------------------

    # Merged config for a single collection.
    #
    # Defaults come from DEFAULT_COLLECTIONS. User overrides under
    # `collections.<name>:` win.
    #
    # Slug aliasing: when the user sets `slug:` on a built-in collection,
    # the URL permalink and layout name derive from it. The source
    # directory always stays canonical so the on-disk content layout is
    # consistent across sites — only public-facing URLs and the layout
    # name change.
    def collection_config(name)
      defaults = DEFAULT_COLLECTIONS[name] || {}
      override = (config['collections'] || {})[name] || {}

      slug = override['slug'].to_s
      if !slug.empty?
        derived = {
          'permalink' => "/#{slug}/:slug/",
          'layout'    => singularize_slug(slug)
        }
        defaults.merge(derived).merge(override)
      else
        defaults.merge(override)
      end
    end

    # Naive singularizer for deriving a layout name from a plural slug.
    # Handles the cases collection slugs actually take:
    #   stories      → story     (ies → y)
    #   books        → book      (s → '')
    #   photos       → photo     (s → '')
    #   publications → publication
    #
    # English exceptions — words that look plural but aren't, or whose
    # singular form matches a different rule. Without the allow-list:
    #   news    → new   (wrong)
    #   series  → serie (wrong; the singular is also "series")
    #   lens    → len   (wrong)
    # Words ending in `ss` (boss, press) also stay as-is — covered by
    # the explicit guard so adding new exceptions only requires one
    # place to edit.
    #
    # The narrow scope is deliberate: collection slugs are usually
    # short English nouns, not arbitrary text. If a consuming site
    # picks a slug that doesn't singularize cleanly here, the docs
    # recommend setting `layout:` explicitly in the collection config.
    INVARIANT_SLUGS = %w[news series lens species means physics analytics].freeze

    def singularize_slug(word)
      return word if INVARIANT_SLUGS.include?(word)
      return word if word.end_with?('ss')

      word.sub(/ies$/, 'y').sub(/s$/, '')
    end

    # Resolve a name to its canonical collection name. Accepts the
    # canonical key ('posts') or the user-configured slug ('stories'
    # when posts has slug: stories) and returns the canonical key.
    def resolve_collection_name(name)
      collections.each do |canonical, cfg|
        return canonical if cfg['slug'].to_s == name.to_s
      end
      name.to_s
    end

    # All collections — built-ins plus any user-defined ones from
    # `collections:` in config/site.yml. Returns name => merged-config
    # hash. Page#collection iterates this to find which collection a
    # source file belongs to.
    def collections
      result = {}
      DEFAULT_COLLECTIONS.each_key { |name| result[name] = collection_config(name) }
      (config['collections'] || {}).each_key { |name| result[name] ||= collection_config(name) }
      result
    end

    # Resolve a page like `content/photos/index.md` to the collection
    # name (`photos`) it acts as the index for. Returns nil for pages
    # that aren't a collection index. Bundle-style collections like
    # `posts` and `photos` exclude their own index.md from
    # Page#collection, so this helper closes the gap for callers that
    # need "what collection does this index page represent?".
    def collection_index_name(page)
      # Generated pages (FolioShowPage, RelatedIndexPage, paginated
      # shards, etc.) don't have a real source_path — return nil.
      return nil unless page.respond_to?(:source_path) && page.source_path
      return nil unless File.basename(page.source_path) == 'index.md'

      collections.each do |name, cfg|
        source = File.join(site_root, cfg['source'])
        return name if page.source_path == File.join(source, 'index.md')
      end
      nil
    end

    # Pages in a named collection, sorted newest-first by date when
    # present. Accepts either the canonical collection name or its
    # slug alias — both return the same pages.
    #
    # Memoised per-canonical-name. Templates that render a collection
    # listing call this repeatedly across a build; the underlying
    # `@pages.select` is O(N), so without memoisation each render is
    # O(N) work × number of partial calls. Reset on `reset_state_for_rebuild!`.
    def collection(name)
      canonical = resolve_collection_name(name)
      @collection_cache ||= {}
      @collection_cache[canonical] ||= begin
        # Manual content pages (Page objects) AND generated pages that
        # opt in by exposing `#collection` returning the canonical
        # name. FolioShowPage is the primary example — Folio
        # publications, bundles, and series join their respective
        # collections so templates iterate one merged list.
        manual    = @pages.select { |p| p.collection == canonical }
        generated = @generated_pages.select do |p|
          p.respond_to?(:collection) && p.collection == canonical
        end
        # Manual wins on slug collision — an override page at
        # `content/publications/<slug>/index.md` suppresses the
        # auto-generated Folio entry for the same slug.
        manual_slugs = manual.map { |p| p.respond_to?(:slug) ? p.slug : nil }.compact.to_set
        generated.reject! { |p| p.respond_to?(:slug) && manual_slugs.include?(p.slug) }

        pages_in = manual + generated
        if pages_in.any? { |p| p.respond_to?(:date) && p.date }
          pages_in.sort_by { |p| (p.respond_to?(:date) && p.date) || Time.at(0) }.reverse
        else
          pages_in.sort_by { |p| p.title.to_s }
        end
      end
    end

    # url → index hash for `collection(name)`. Built once on first
    # access per collection and cached. Lets `next_in_collection` and
    # `related` answer "which slot is this page in?" in O(1) instead
    # of O(N) — and since both are called once per show-view render,
    # the total cost across a build is O(pages) instead of O(pages²).
    def collection_url_index(name)
      canonical = resolve_collection_name(name)
      @collection_url_index_cache ||= {}
      @collection_url_index_cache[canonical] ||= begin
        index = {}
        collection(canonical).each_with_index { |page, i| index[page.url] = i }
        index
      end
    end

    # Featured-item lookup. `site.featured('publications', 'the-field-guide')`
    # returns the matching page or nil — useful for "show this one item
    # prominently on the home page" patterns.
    def featured(collection_name, slug)
      return nil unless slug && !slug.to_s.empty?

      collection(collection_name).find do |p|
        p.slug == slug.to_s ||
          p.url.split('/').reject(&:empty?).last == slug.to_s
      end
    end

    # Related pages — candidates from the same collection, scored by
    # how many tags / series / countries / etc. they share with the
    # source page. By default returns ALL matches with positive
    # overlap, ranked highest-score first.
    #
    #   site.related(page)               # full ranked list
    #   site.related(page, limit: 3)     # top 3
    #   site.related(page, match_by: %w[tags series])
    def related(page, limit: nil, match_by: nil)
      return [] unless page.respond_to?(:collection) && page.collection

      cfg = collection_config(page.collection)['related'] || {}
      return [] if cfg['enabled'] == false

      effective_match_by = Array(match_by || cfg.fetch('match_by', 'tags'))

      # Use the url-index lookup to skip the source page in O(1); the
      # earlier `.reject { |p| p.url == page.url }` did an O(N) scan
      # per page rendered, which the related-list call sites repeat
      # across the whole collection.
      idx_map    = collection_url_index(page.collection)
      pages_in   = collection(page.collection)
      source_idx = idx_map[page.url]
      candidates = source_idx ? pages_in.reject.with_index { |_, i| i == source_idx } : pages_in

      # Earlier fields in match_by weight more — count them with a
      # multiplier so "matches series first, then country" comes out
      # as expected even when both share with the source.
      scored = candidates.map do |candidate|
        score = effective_match_by.each_with_index.sum do |field, idx|
          weight = effective_match_by.size - idx
          shared_term_count(page.frontmatter[field], candidate.frontmatter[field]) * weight
        end
        [score, candidate]
      end

      sorted = scored.select { |score, _| score.positive? }
                     .sort_by { |score, candidate| [-score, -(candidate.respond_to?(:date) && candidate.date ? candidate.date.to_i : 0)] }
                     .map(&:last)

      limit ? sorted.first(limit) : sorted
    end

    # The "next" page in a dated collection's chronological order. "Next"
    # means strictly newer — the post that came after this one in time.
    # Returns nil when the source is the newest in the collection, isn't
    # in the collection, or `next.enabled` is false.
    def next_in_collection(page)
      return nil unless page.respond_to?(:collection) && page.collection

      cfg = collection_config(page.collection)['next'] || {}
      return nil if cfg['enabled'] == false

      pages = collection(page.collection) # newest first
      idx   = collection_url_index(page.collection)[page.url]
      return nil unless idx

      # Newer neighbour sits at the smaller index. When idx is 0 we're
      # already at the newest — render nothing.
      idx.positive? ? pages[idx - 1] : nil
    end

    # The "next" page within the same series — the page with the
    # smallest `series_position` strictly greater than this page's.
    # Requires the page to have BOTH `series:` and `series_position:`
    # in frontmatter, and to belong to a collection (so the series is
    # scoped consistently with the per-collection series taxonomies).
    #
    # Returns nil when:
    #   - The page isn't in a series (no `series:` frontmatter).
    #   - The page has no `series_position:` (can't order it).
    #   - The page is the last position in the series.
    #   - The page is outside a collection.
    #
    # Used by the post show view to render a "Next in the series" card
    # in place of the chronological "Up next" card when a series
    # relationship exists. Generic across collections — works for
    # posts, photos, publications, workshops alike.
    def next_in_series(page)
      return nil unless page.respond_to?(:frontmatter)
      return nil unless page.respond_to?(:collection) && page.collection

      series_name = page.frontmatter['series'].to_s
      return nil if series_name.empty?

      current_pos = page.frontmatter['series_position']
      return nil if current_pos.nil?

      candidates = collection(page.collection).select do |p|
        p.frontmatter['series'].to_s == series_name &&
          p.frontmatter['series_position'].is_a?(Integer) &&
          p.frontmatter['series_position'] > current_pos.to_i
      end

      candidates.min_by { |p| p.frontmatter['series_position'].to_i }
    end

    # Shared-term count between two frontmatter values. Both can be
    # scalars (`country: Syria`) or arrays (`tags: [a, b]`); we use
    # `Array()` to normalise. Returns 0 when either side is missing.
    def shared_term_count(a, b)
      return 0 if a.nil? || b.nil?

      a_set = Array(a).map(&:to_s).to_set
      b_set = Array(b).map(&:to_s).to_set
      (a_set & b_set).size
    end

    # ------------------------------------------------------------------
    # Taxonomies
    # ------------------------------------------------------------------

    # User config and defaults are merged so the built-in `tags`
    # taxonomy stays available even when the user defines their own.
    def taxonomies
      user = config['taxonomies'] || {}
      DEFAULT_TAXONOMIES.merge(user)
    end

    def taxonomy_config(name)
      defaults = DEFAULT_TAXONOMIES[name] || {}
      override = taxonomies[name] || {}
      defaults.merge(override)
    end

    # Index dated pages by taxonomy term. Reads `frontmatter[field]`
    # where `field` defaults to the taxonomy name (overridable via
    # `field:` in config).
    #
    # When the taxonomy config sets `collection: <name>`, the
    # aggregation is scoped to that collection — items in other
    # collections with the same field value don't appear. Used by the
    # per-collection series taxonomies (`posts_series`, `photos_series`,
    # …) so a photo with `series: "Notes 2026"` and a post with
    # `series: "Notes 2026"` are independent series, not a shared one.
    #
    # No `collection:` in the config → cross-collection aggregation,
    # the historical behaviour. The default `tags` taxonomy keeps this
    # so a post and a photo both tagged `travel` land on /tags/travel/
    # together.
    def posts_by_term(taxonomy)
      cfg   = taxonomy_config(taxonomy)
      field = cfg['field'] || taxonomy
      scope = cfg['collection']

      result = Hash.new { |h, k| h[k] = [] }
      taxonomy_pages.each do |page|
        next if scope && page.collection != scope

        Array(page.frontmatter[field]).each { |term| result[term] << page }
      end
      result
    end

    # Pages that taxonomies index — every page in every collection.
    # Sorted newest-first; pages without a `date` (workshops have
    # `date_from`, not `date`; some collections may opt out of dating
    # entirely) sort to the end as Time.at(0). Memoised — same shape
    # as `posts`, called from every taxonomy partial.
    def taxonomy_pages
      @taxonomy_pages_cache ||= @pages.select(&:collection)
                                     .sort_by { |p| p.date || Time.at(0) }
                                     .reverse
    end

    # ------------------------------------------------------------------
    # Page accessors
    # ------------------------------------------------------------------

    def all_pages
      @pages + @generated_pages
    end

    # Memoised — `posts` is read by the posts index, every per-post
    # `next_in_collection`, the feed, the sitemap, the home page's
    # latest-post module, and several JSON-LD partials. Recomputing
    # on each call is O(N); cache once per build.
    def posts
      @posts_cache ||= @pages.select(&:post?).sort_by(&:date).reverse
    end

    def posts_by_tag
      @posts_by_tag_cache ||= begin
        result = Hash.new { |h, k| h[k] = [] }
        posts.each do |post|
          post.tags.each { |tag| result[tag] << post }
        end
        result
      end
    end

    # ------------------------------------------------------------------
    # Pipelines + data
    # ------------------------------------------------------------------

    def assets
      @assets ||= AssetPipeline.new(self)
    end

    def images
      @images ||= ImagePipeline.new(self)
    end

    def visualizations
      @visualizations ||= Visualizations.new(self)
    end

    def folio
      @folio ||= Folio.new(self)
    end

    def data
      @data ||= @loader.load_data
    end

    # ------------------------------------------------------------------
    # Nav / footer / social
    # ------------------------------------------------------------------

    def nav_links
      @loader.nav_links
    end

    def footer_links
      @loader.footer_links
    end

    # Social icons — emitted in the footer when `social:` is set in
    # site.yml. Each key must match an SVG filename in app/icons/<key>.svg.
    def social_links
      raw = config['social']
      return [] unless raw.is_a?(Hash)

      raw.map { |key, url| { 'icon' => key.to_s, 'url' => url, 'label' => key.to_s.capitalize } }
    end

    # ------------------------------------------------------------------
    # Renderer delegations
    # ------------------------------------------------------------------

    # Lazily compile and cache an ERB template. Safe to call from threads.
    def compiled_template(path)
      @renderer.compiled_template(path)
    end

    def shared_deps_mtime
      @renderer.shared_deps_mtime
    end

    # Per-layout mtime — used by Page#needs_render? to skip pages
    # whose layout chain hasn't been touched since their last build.
    def layout_deps_mtime(layout_name)
      @renderer.layout_deps_mtime(layout_name)
    end

    def post_process(html, page: nil)
      @renderer.post_process(html, page: page)
    end

    def minify_html?
      @renderer.minify_html?
    end

    # ------------------------------------------------------------------
    # External symlink check — public because Page#bundle_assets and
    # BundleAssets both call it during enumeration.
    # ------------------------------------------------------------------

    # True when `path` is a symlink whose target lives outside site_root.
    # In-tree symlinks (e.g. linking one bundle's asset into another) are
    # still allowed — that's a legitimate authoring pattern. Dangling /
    # looping symlinks are skipped with a warning rather than crashing
    # the build.
    #
    # Set `ABQARI_ALLOW_EXTERNAL_SYMLINKS=true` to bypass.
    def external_symlink?(path)
      return false if ENV['ABQARI_ALLOW_EXTERNAL_SYMLINKS'] == 'true'

      lstat = File.lstat(path)
      return false unless lstat.symlink?

      # realpath on both sides so platform path quirks (macOS resolves
      # /var → /private/var) don't make an in-tree symlink look external.
      target  = File.realpath(path)
      root    = File.realpath(site_root)
      escaped = !(target == root || target.start_with?(root + File::SEPARATOR))
      Log.warn "Skipping symlink that escapes site_root: #{path} -> #{target}" if escaped
      escaped
    rescue Errno::ENOENT, Errno::ELOOP => e
      # Dangling or looping symlink. Either way, skip and warn — don't
      # crash the build.
      Log.warn "Skipping unreadable symlink #{path}: #{e.class}: #{e.message}"
      true
    end

    private

    # Anchor every Time.parse call during a build to a single zone so
    # naked dates like "2026-06-15" mean the same moment regardless of
    # whether the build runs on a US laptop, a Singapore phone, or a
    # UTC CI runner. Without this, a future-dated post would publish
    # at different wall-clock times in different deploys.
    #
    # Dates with explicit offsets (e.g. "2026-06-15T08:00:00+08:00")
    # still honour their offset; this only affects naked dates and
    # `Time.now`.
    #
    # Called from `build` (not `initialize`) and paired with an
    # `ensure` block that restores the prior `ENV['TZ']`. Process-wide
    # side effects are scoped to the duration of a single build —
    # tests and host applications that share the Ruby process see
    # their TZ environment untouched outside of build calls.
    def apply_timezone!
      tz = (config['timezone'] || 'UTC').to_s.strip
      ENV['TZ'] = tz unless tz.empty?
    end

    # Reset between (re)builds so the dev-server's incremental rebuild
    # picks up generator + template changes correctly. Includes the
    # partition-view caches (posts, posts_by_tag, taxonomy_pages,
    # collection) so a content edit isn't masked by a stale memo.
    def reset_state_for_rebuild!
      @generated_pages           = []
      @assets                    = nil
      @images                    = nil
      @data                      = nil
      @posts_cache               = nil
      @posts_by_tag_cache        = nil
      @taxonomy_pages_cache      = nil
      @collection_cache          = nil
      @collection_url_index_cache = nil
      @renderer.clear_template_cache
    end

    def folio_enabled?
      cfg = config['folio'] || {}
      !cfg['base_url'].to_s.empty? && !cfg['author_slug'].to_s.empty?
    end
  end
end

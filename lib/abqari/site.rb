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
      SiteConfig.validate!(raw, env: @env)
      # Fold static defaults under the user's config so call sites can
      # do `config['indexable']` instead of `config.fetch(..., true)`.
      # Dynamic defaults (minify, env-based) stay in their callers.
      @config = SiteConfig.with_defaults(raw)
      @pages           = []
      @generated_pages = []
      # Contribute phase is open until Renderer#generate_all closes it.
      @collections_final = false
      # Per-build memo registry. All `||=` caches on Site route
      # through `memo(key) { … }` so a rebuild only has to clear one
      # hash; adding a new memo can never go out of sync with the
      # rebuild-reset code. See `reset_state_for_rebuild!`.
      @memos      = {}
      @memo_mutex = Mutex.new
      @renderer  = Renderer.new(self)
      @artifacts = ArtifactWriter.new(self)

      # Load site-local plugins (plugins/**/*.rb). Plugins register
      # themselves with `Abqari::Hooks.register(...)` at top level —
      # the registrations land in the global hook table and fire on
      # subsequent `Hooks.run` / `run_filter` calls during build.
      PluginLoader.load_from(site_root)
      # Taken after loading so it covers what the plugins required.
      @ruby_snapshot = PluginLoader.snapshot(site_root)
    end

    # Site Ruby (plugins/, and lib/ files they required) that changed on
    # disk after this Site loaded it. Ruby loads once per process, so a
    # long-lived Site — the dev server's — keeps running the old code.
    def stale_ruby_sources
      PluginLoader.changed_since(@ruby_snapshot, site_root)
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
    # `side_effects: false` skips the outbound network steps (POSSE
    # syndication, webmention sending). `bin/audit` builds in production
    # to exercise the real CSP/minify/fingerprint paths, but it must not
    # broadcast the posts it's auditing — an audit is a dry run, not a
    # publish.
    def build(incremental: false, side_effects: true)
      @incremental = incremental
      prev_tz = ENV['TZ']
      apply_timezone!

      Hooks.run(:before_build, self)

      # Theme config is validated before ANY filesystem effect — a
      # typo'd or traversal-shaped `theme:` must abort here, not after
      # the output dir is wiped or mid-render with per-page errors.
      assets.validate_theme!

      @artifacts.reset_output unless incremental
      reset_state_for_rebuild!

      @pages = @loader.load_pages
      Hooks.run(:after_load_pages, self)

      Folio.new(self).fetch                 # publications + bundles, derives series
      Indieweb::Fetcher.new(self).fetch     # webmentions (received via webmention.io)
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
      if side_effects
        Indieweb::Sender.new(self).send_all   # POST webmentions for new outbound links (opt-in)
        Syndication::Dispatcher.new(self).run # POSSE: crosspost to Mastodon/Bluesky (opt-in)
      end

      # Build-complete sentinel (`Abqari::BUILD_OK_SENTINEL`). Written
      # ONLY on the success path — if any step above raises, this line
      # never runs and the file stays absent. Deployers (bin/deploy,
      # CI pipelines that rsync/scp _site/) check for it before
      # publishing so a half-built _site/ from a crashed build can't
      # accidentally ship over a working site. Includes the build
      # timestamp + the gem version so a stale sentinel (older than
      # the source files under content/) is detectable.
      File.write(
        File.join(output_dir, Abqari::BUILD_OK_SENTINEL),
        "version: #{Abqari::VERSION}\nbuilt_at: #{Time.now.utc.iso8601}\n"
      )

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
    # generated pages that implement `#collection` (PublisherShowPage
    # in particular) join their collection — a memoised
    # `collection(name)` result from before this add is now stale.
    # The pagination / related generators call `site.collection`
    # mid-`generate_all`, so invalidating at every add keeps the memo
    # honest without requiring careful generator-ordering.
    def add_generated_page(page)
      assert_collection_open!(page)

      @generated_pages << page
      @memos.delete(:collection_cache)
      @memos.delete(:collection_url_index_cache)
      @memos.delete(:posts) if page.respond_to?(:post?) && page.post?
    end

    # Close the contribute phase. Called by `Renderer#generate_all` once
    # every generator that can add pages to a collection has run; from
    # here on, collections are what the deriving generators (pagination,
    # taxonomies, related indexes) will see.
    def finalise_collections!
      @collections_final = true
    end

    def collections_final?
      @collections_final == true
    end

    # Raise if a page tries to join a collection after the barrier.
    #
    # Pagination reads a collection and freezes the slices into
    # `Paginator` objects; anything added afterwards is silently missing
    # from the archive and every shard. That's the worst shape of bug
    # this codebase can produce — output that is quietly incomplete, with
    # a green build and nothing to investigate. Better a loud failure at
    # the moment the ordering is violated, naming the page.
    #
    # Only collection-joining pages are refused. Taxonomy pages,
    # paginated shards, visualizations and related indexes are all
    # produced BY the derive phase and belong to no collection, so they
    # add freely.
    def assert_collection_open!(page)
      return unless collections_final?
      return unless page.respond_to?(:collection) && page.collection

      raise <<~MSG
        #{page.class} joins the '#{page.collection}' collection but was added after
        collections were finalised (url: #{page.respond_to?(:url) ? page.url : '?'}).

        Pages that join a collection must be generated in the contribute
        phase of Renderer#generate_all, before Site#finalise_collections!.
        Adding one later means pagination has already sliced the
        collection without it, so it would be missing from the archive
        and its shards with no other symptom.
      MSG
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

    # Absolute, always. `Page#url` derives every internal URL by
    # stripping this prefix off the page's output path, and the output
    # path is absolute — so a relative `ABQARI_OUTPUT_DIR=_site` used to
    # strip nothing and leave the developer's full filesystem path
    # embedded in every href, `<loc>` and feed link:
    #
    #   <loc>https://example.com/Users/me/dev/mysite//about/</loc>
    #
    # Files still landed in the right place, so the build reported
    # success and shipped a sitemap advertising local paths to the world.
    # A trailing slash was the mirror-image bug: it consumed the leading
    # `/` and produced scheme-relative URLs. `expand_path` normalises
    # both, and matches what `ArtifactWriter#reset_output` already does
    # before it deletes anything — the two had drifted, which is how a
    # value safe enough to delete under could still corrupt every URL.
    def output_dir
      raw = ENV['ABQARI_OUTPUT_DIR']
      return File.join(site_root, '_site') if raw.nil? || raw.strip.empty?

      File.expand_path(raw, site_root)
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

    # Extensions published out of a bundle directory: the built-in
    # allow-list (`Page::Bundle::PUBLISHABLE_EXTENSIONS`) plus anything
    # the site adds via
    #
    #   bundle_assets:
    #     extensions: [.gpx, .stl]
    #
    # Additive rather than replacing, so a site that wants one extra
    # download type doesn't have to restate the media defaults (and
    # silently lose an image format when the defaults grow). Entries are
    # normalised to lower-case and dot-prefixed, so `GPX`, `.gpx` and
    # `gpx` all work.
    def bundle_asset_extensions
      memo(:bundle_asset_extensions) do
        extra = Array((config['bundle_assets'] || {})['extensions'])
                .map { |e| e.to_s.strip.downcase }
                .reject(&:empty?)
                .map { |e| e.start_with?('.') ? e : ".#{e}" }

        # Markdown can't be opted back in. It's content, and publishing
        # it as an asset is precisely the bug this allow-list closes —
        # a `published: false` sibling shipped verbatim to production.
        content, allowed = extra.partition { |e| Page::Bundle::CONTENT_EXTENSIONS.include?(e) }
        unless content.empty?
          Log.warn "Ignoring #{content.join(', ')} in `bundle_assets.extensions:` — " \
                   'markdown is content, not an asset, and publishing it would expose ' \
                   'files marked `published: false`. Move the file out of the bundle if ' \
                   'you want it published.'
        end

        (Page::Bundle::PUBLISHABLE_EXTENSIONS + allowed).to_set
      end
    end

    # Resolve a page like `content/photos/index.md` to the collection
    # name (`photos`) it acts as the index for. Returns nil for pages
    # that aren't a collection index. Bundle-style collections like
    # `posts` and `photos` exclude their own index.md from
    # Page#collection, so this helper closes the gap for callers that
    # need "what collection does this index page represent?".
    def collection_index_name(page)
      # Generated pages (PublisherShowPage, RelatedIndexPage, paginated
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
      cache = memo(:collection_cache) { {} }
      cache[canonical] ||= begin
        # Manual content pages (Page objects) AND generated pages that
        # opt in by exposing `#collection` returning the canonical
        # name. PublisherShowPage is the primary example —
        # externally-sourced publications, bundles, and series join
        # their respective collections so templates iterate one
        # merged list.
        manual    = @pages.select { |p| p.collection == canonical }
        generated = @generated_pages.select do |p|
          p.respond_to?(:collection) && p.collection == canonical
        end
        # Manual wins on slug collision — an override page at
        # `content/publications/<slug>/index.md` suppresses the
        # auto-generated externally-sourced entry for the same slug.
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
      cache = memo(:collection_url_index_cache) { {} }
      cache[canonical] ||= begin
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

      cfg = collection_config(page.collection).dig('show', 'related') || {}
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

      cfg = collection_config(page.collection).dig('show', 'next') || {}
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
      series_sibling(page, :forward)
    end

    # The "previous" page within the same series — the page with the
    # largest `series_position` strictly less than this page's. Exact
    # mirror of `next_in_series`: same guards, same nil semantics, same
    # per-collection scoping.
    #
    # Exists because course-shaped collections (a module of ordered
    # lessons) need to navigate backwards as well as forwards. The
    # `_series_pager` partial pairs the two into one prev/next nav;
    # `_next_in_series` remains the forward-only card.
    def prev_in_series(page)
      series_sibling(page, :back)
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

    # Which taxonomy owns the series index for `collection_name` — the
    # first taxonomy whose `field:` is `series` and whose `collection:`
    # scope matches. Returns the taxonomy name (e.g. `'posts_series'`)
    # or nil when the collection has no series taxonomy configured.
    #
    # Layouts must not hardcode `'posts_series'`: the `post` layout is
    # deliberately reusable (cookbook, glossary, lessons), and every
    # collection that reuses it has its own `<collection>_series`
    # taxonomy. A hardcoded name sends every series breadcrumb in every
    # reusing collection to the posts series index instead of its own.
    def series_taxonomy_for(collection_name)
      return nil if collection_name.to_s.empty?

      memo("series_taxonomy_#{collection_name}") do
        taxonomies.find do |_name, cfg|
          cfg['field'].to_s == 'series' &&
            cfg['collection'].to_s == collection_name.to_s
        end&.first
      end
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
      memo(:taxonomy_pages) do
        @pages.select(&:collection)
              .sort_by { |p| p.date || Time.at(0) }
              .reverse
      end
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
      # Guard the sort against a date-less post (no `date:` frontmatter
      # and no `YYYY-MM-DD-` dir prefix): `sort_by(&:date)` on a nil
      # raises `comparison of NilClass with Time failed`. Undated posts
      # sort to the end, matching `taxonomy_pages`.
      memo(:posts) { @pages.select(&:post?).sort_by { |p| p.date || Time.at(0) }.reverse }
    end

    def posts_by_tag
      memo(:posts_by_tag) do
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
      memo(:assets) { AssetPipeline.new(self) }
    end

    def images
      memo(:images) { ImagePipeline.new(self) }
    end

    def visualizations
      memo(:visualizations) { Visualizations.new(self) }
    end

    def folio
      memo(:folio) { Folio.new(self) }
    end

    def data
      memo(:data) { @loader.load_data }
    end

    # IndieWeb — webmentions received for a given page URL. Returns an
    # array of mention hashes (newest first) or `[]` when none are
    # cached for that URL. The mention shape mirrors webmention.io's
    # JF2 output: `{ 'wm-property' => 'in-reply-to' | 'like-of' | ...,
    # 'author' => { 'name' => ..., 'url' => ..., 'photo' => ... },
    # 'content' => { 'text' => ... }, 'published' => '2024-01-15T...',
    # 'url' => 'https://reply.example.com/post' }`.
    #
    # The lookup is path-normalised (trailing slash added) so
    # `/posts/foo/` matches whether the original mention pointed at
    # `https://example.com/posts/foo` or `https://example.com/posts/foo/`.
    def webmentions_for(url)
      return [] unless data['webmentions'].is_a?(Hash)
      path = url.to_s
      path = "#{path}/" unless path.end_with?('/')
      data['webmentions'][path] || []
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
    # picks up generator + template changes correctly. Clearing the
    # `@memos` hash drops every memoised value at once — partition
    # views (posts, posts_by_tag, taxonomy_pages, collection),
    # pipelines (assets, images, visualizations), Folio, loaded
    # data. Adding a new `memo(...)` accessor anywhere on Site is
    # automatically picked up here; the old per-field nil-list could
    # silently go out of sync.
    def reset_state_for_rebuild!
      @generated_pages = []
      # Reopen the contribute phase. Without this the dev server's
      # second incremental rebuild would raise on the first publisher
      # page it generated, because the flag survived the first build.
      @collections_final = false
      @memos.clear
      @renderer.clear_template_cache
    end

    # Shared scan behind `next_in_series` / `prev_in_series`. Direction
    # `:forward` takes the smallest position above the current one,
    # `:back` the largest position below it.
    #
    # A candidate's `series_position` must be a real Integer. A quoted
    # YAML value ("3") drops that page out of the chain with no other
    # symptom, which is why `bin/audit` flags the type — see
    # `Audit::Content#flag_series_position_problems`. The *current*
    # page's position is coerced with `to_i` so a page whose own value
    # is mistyped can still find its neighbours.
    #
    # Two pages sharing a position are invisible to each other in both
    # directions (the comparison is strict), so the chain silently
    # skips one. The audit flags duplicates for the same reason.
    def series_sibling(page, direction)
      return nil unless page.respond_to?(:frontmatter)
      return nil unless page.respond_to?(:collection) && page.collection

      series_name = page.frontmatter['series'].to_s
      return nil if series_name.empty?

      raw_pos = page.frontmatter['series_position']
      return nil if raw_pos.nil?

      current_pos = raw_pos.to_i
      candidates = collection(page.collection).select do |p|
        next false unless p.frontmatter['series'].to_s == series_name

        pos = p.frontmatter['series_position']
        next false unless pos.is_a?(Integer)

        direction == :forward ? pos > current_pos : pos < current_pos
      end

      positions = ->(p) { p.frontmatter['series_position'] }
      direction == :forward ? candidates.min_by(&positions) : candidates.max_by(&positions)
    end

    # Memoise the result of `block` under `key` for the lifetime of
    # this Site instance (or until `reset_state_for_rebuild!` runs).
    # Every cache on Site routes through here so there's a single
    # source of truth for what gets cleared between rebuilds.
    #
    # Mutex-guarded because templates call memoised accessors
    # (`site.collection`, `site.posts`, …) from the parallel render
    # pool. In practice most memos are warm before `render_pages`
    # starts, and on MRI the GVL makes a torn Hash unlikely — but
    # "unlikely on one implementation" isn't a guarantee, and
    # `Renderer` already takes exactly this precaution for its own
    # template and mtime caches. The lock is uncontended once a value
    # exists, so the steady-state cost is a single `Hash#key?`.
    #
    # Re-entrant by design: a memoised accessor whose block calls
    # another memoised accessor would deadlock on a plain Mutex, so the
    # fast path reads WITHOUT the lock and the block runs OUTSIDE it.
    # Two threads racing a cold key may both compute; they produce the
    # same value and the last write wins, which is the standard,
    # harmless memoisation race.
    def memo(key)
      return @memos[key] if @memos.key?(key)

      value = yield
      # `||=` rather than assuming the ivar: tests build sites with
      # `Site.allocate` and set only the ivars they need, and a
      # NoMethodError on nil there would be a baffling way to learn
      # about a lock. The real constructor always sets it, so the
      # lazy-init race is unreachable outside single-threaded test code.
      (@memo_mutex ||= Mutex.new).synchronize { @memos[key] = value }
      @memos[key]
    end

    def folio_enabled?
      cfg = config['folio'] || {}
      !cfg['base_url'].to_s.empty? && !cfg['author_slug'].to_s.empty?
    end
  end
end

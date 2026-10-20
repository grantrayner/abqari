# frozen_string_literal: true

require 'etc'

module Abqari
  # Page-rendering collaborator. Owns:
  #
  #   - Generators that produce virtual pages BEFORE render
  #     (tag pages, paginated shards, visualizations, Folio pages,
  #     related-index pages).
  #   - The render loop itself, with parallel execution and per-page
  #     error collection.
  #   - ERB template caching (shared across threads via a mutex).
  #   - The shared-deps mtime used by incremental rendering.
  #   - HTML post-processing (bundle-URL rewrite, syntax highlighting,
  #     responsive image rewrites, minification, livereload injection).
  class Renderer
    # Below this many pages, parallelism hurts more than it helps.
    PARALLEL_THRESHOLD = 16

    # Render threads can only overlap file I/O: ERB, markdown and the
    # post-processors are Ruby and hold the GVL. Past a handful they
    # add contention, not throughput — a 270-page site built in ~1.07s
    # on 1, 2, 4 or 8 threads, and 1.18s on 14.
    MAX_RENDER_THREADS = 4

    # Where a container's CPU quota is exposed. `Etc.nprocessors` reports
    # the host's CPUs (or the cpuset), not the quota, so a build
    # container on a large host would otherwise start dozens of threads
    # to share a fraction of one CPU.
    CGROUP_ROOT = '/sys/fs/cgroup'

    # Default page-size for `paginate: true`. Overridable per-site via
    # `pagination.per_page` config.
    PAGINATION_DEFAULT = 10

    # Slow-page detection. When a single page's `write` (render +
    # post-process + file write) uses more CPU than this, the renderer
    # logs a warning with the URL, the time, and a short list of
    # heuristic causes (output size, image count, code-block count,
    # TOC presence, a measured plugin filter). End-of-build summary
    # surfaces the slowest few.
    #
    # Default 500ms — high enough to ignore the normal per-page
    # baseline (~5–50ms), low enough to catch real outliers. Override
    # with `ABQARI_SLOW_PAGE_MS=N` (set to 0 to disable detection).
    SLOW_PAGE_THRESHOLD_MS = (ENV['ABQARI_SLOW_PAGE_MS'] || '500').to_i

    # Pages are timed by the CPU their own thread used, not wall-clock.
    # Wall-clock includes every other render thread's turn on the GVL
    # and any CPU throttling, so on a container with a small quota a
    # 5ms page read as 500ms+ and dozens of pages were reported slow.
    # The trade: time spent blocked on I/O no longer counts, which
    # suits a warning whose every listed cause is CPU work.
    PAGE_CLOCK = defined?(Process::CLOCK_THREAD_CPUTIME_ID) ? Process::CLOCK_THREAD_CPUTIME_ID : Process::CLOCK_MONOTONIC

    # A plugin filter is named as a cause only when it accounts for at
    # least this share of the slow page's time. It used to be named on
    # every slow page whenever any `:post_process` hook was registered.
    PLUGIN_FILTER_SHARE = 0.25
    PLUGIN_FILTER_MS = :abqari_plugin_filter_ms

    class << self
      def render_threads
        [available_cpus, MAX_RENDER_THREADS].min
      end

      def available_cpus(cgroup_root: CGROUP_ROOT)
        [Etc.nprocessors, cgroup_cpu_limit(cgroup_root)].compact.min
      end

      # CPUs granted by the cgroup quota, rounded up, or nil when there
      # is no quota (or no cgroup to read). v2 first, then v1.
      def cgroup_cpu_limit(root)
        v2 = read_cgroup(File.join(root, 'cpu.max'))
        quota, period = v2 ? v2.split : v1_quota(root)
        return nil if quota.nil? || quota == 'max' || quota.to_i <= 0 || period.to_i <= 0

        [(quota.to_f / period.to_i).ceil, 1].max
      end

      private

      def v1_quota(root)
        %w[cpu cpu,cpuacct].each do |dir|
          quota = read_cgroup(File.join(root, dir, 'cpu.cfs_quota_us'))
          return [quota, read_cgroup(File.join(root, dir, 'cpu.cfs_period_us'))] if quota
        end
        nil
      end

      def read_cgroup(path)
        File.read(path).strip
      rescue SystemCallError
        nil
      end
    end

    # Files whose mtime invalidates every cached page render.
    # `app/views/layouts/` is NOT here — layout files are handled
    # per-layout via `layout_deps_mtime(name)` so editing one layout
    # only invalidates the pages that use it.
    #
    # Partials stay in the global bucket: statically tracking which
    # partials each layout chain renders would require scanning ERB
    # source for `render '...'` calls and is more complexity than the
    # win is worth at the scale Abqari targets. Edits to a partial
    # therefore still invalidate every cached render.
    #
    # `themes/**/*` is NOT in this list — it's resolved per-site at
    # `compute_shared_deps_mtime` time so we only walk the active
    # theme's directory, not every theme that happens to ship with
    # the gem.
    #
    # `vendor/fonts/fonts.css` is here because every page's head links
    # it by content hash; a re-fetch must re-render them all.
    GLOBAL_DEP_GLOBS = [
      'app/views/partials/**/*',
      'app/icons/**/*',
      'app/assets/**/*',
      'lib/**/*',
      'config/**/*',
      'data/**/*',
      'vendor/fonts/fonts.css'
    ].freeze

    # The renderer only needs the frontmatter block (no body), but
    # reusing `Abqari::FRONTMATTER_RE` and discarding `match[2]` keeps
    # the three call sites in lockstep — the old duplicate-with-drift
    # was finding a `---` pair that the page parser wouldn't.
    LAYOUT_FRONTMATTER_RE = Abqari::FRONTMATTER_RE

    def initialize(site)
      @site = site
      @template_cache = {}
      @template_mutex = Mutex.new
      # Separate mutex for the mtime / layout-chain caches. Different
      # contention profile from the template cache (computed once per
      # layout name, then read-only for the rest of the build), and
      # keeping the mutex separate means a slow first-miss on the
      # mtime side doesn't block template compilation.
      @deps_mutex     = Mutex.new
      @layout_chains  = {}
      @layout_mtimes  = {}
    end

    # Reset between builds (incremental dev server keeps the Site
    # around across rebuilds; the template cache must clear so layout
    # edits take effect). Layout-chain caches are reset too — a new
    # layout file or a frontmatter `layout:` edit changes the chain.
    def clear_template_cache
      @template_mutex.synchronize { @template_cache = {} }
      @deps_mutex.synchronize do
        @shared_deps_mtime = nil
        @layout_chains     = {}
        @layout_mtimes     = {}
      end
    end

    # Lazily compile and cache a template. Safe to call from threads.
    # Uses Erubi with `escape: true` so every `<%= %>` interpolation is
    # auto-escaped; partials emit raw markup via `<%== %>`. See
    # ErbiTemplate for the rationale.
    def compiled_template(path)
      @template_mutex.synchronize do
        @template_cache[path] ||= ErbiTemplate.new(File.read(path, encoding: 'UTF-8'), path)
      end
    end

    # Most-recent mtime across the global dep set (everything except
    # layout files). When this is newer than a page's output, that
    # output is stale regardless of which layout the page uses.
    #
    # Mutex-protected. `Page#needs_render?` runs inside the parallel
    # render loop, so concurrent threads can race on the first miss —
    # without the mutex they'd each pay the (expensive) directory-
    # walk cost. With it, one thread computes, the rest wait.
    def shared_deps_mtime
      @deps_mutex.synchronize do
        @shared_deps_mtime ||= compute_shared_deps_mtime
      end
    end

    # Most-recent mtime across `layout_name`'s file plus every ancestor
    # in its `layout:` chain. Memoised per layout name. Page#needs_render?
    # combines this with `shared_deps_mtime` so editing `layouts/post.html.erb`
    # only invalidates pages that resolve to the `post` layout (or
    # something that extends it), not photo / publication / workshop
    # pages.
    #
    # Mutex-protected for the same reason as `shared_deps_mtime`:
    # called from the parallel render loop, and a torn write of the
    # underlying hash would be observable on Ruby implementations
    # without GIL serialisation (TruffleRuby, JRuby).
    def layout_deps_mtime(layout_name)
      key = layout_name.to_s
      @deps_mutex.synchronize do
        @layout_mtimes[key] ||= compute_layout_deps_mtime(key)
      end
    end

    # ----------------------------------------------------------------
    # Generators
    # ----------------------------------------------------------------

    # Two phases, and the order between them is load-bearing.
    #
    # CONTRIBUTE — generators that add pages which JOIN a collection.
    # `PublisherShowPage` is the case that exists today: Folio
    # publications, bundles and series expose `#collection`, so
    # `Site#collection` merges them with the manual content pages.
    #
    # DERIVE — generators that READ collections and freeze what they
    # find. Pagination slices a collection into `Paginator` objects at
    # generation time; whatever isn't in the collection when that runs
    # is absent from the archive and every shard, permanently.
    #
    # Pagination used to run before publisher pages, so on a Folio site
    # with more manual publications than `per_page`, every Folio-sourced
    # publication silently vanished from the archive — no warning, no
    # error, just missing entries. `Site#finalise_collections!` makes a
    # repeat of that a hard failure instead of a silent one: after the
    # barrier, adding a page that joins a collection raises.
    #
    # Tag pages sit in DERIVE for ordering hygiene, though they read
    # `@pages` (source pages only, see `Site#taxonomy_pages`) and so
    # were never affected by this.
    def generate_all
      generate_publisher_pages

      @site.finalise_collections!

      generate_tag_pages
      generate_paginated_pages
      generate_visualizations
      generate_related_pages
    end

    def generate_tag_pages
      @site.taxonomies.each_key do |name|
        @site.posts_by_term(name).each do |term, term_posts|
          @site.add_generated_page(TaxonomyPage.new(name, term, term_posts, @site))
        end
      end
    end

    def generate_visualizations
      @site.visualizations.pages.each { |page| @site.add_generated_page(page) }
    end

    # Auto-generate /books/, /bundles/, /series/ index + show pages
    # from an external publisher's data (currently Folio — see
    # `folio:` config). No-op when no publisher is configured. Pages
    # already defined via content/ markdown files take precedence.
    def generate_publisher_pages
      PublisherPages.new(@site).pages.each { |page| @site.add_generated_page(page) }
    end

    # Generate `/<source url>related/` index pages for any show-view page
    # whose related list is longer than its visible `limit`.
    def generate_related_pages
      @site.pages.select { |p| p.respond_to?(:collection) && p.collection }.each do |page|
        cfg = @site.collection_config(page.collection).dig('show', 'related') || {}
        next if cfg['enabled'] == false

        all = @site.related(page)
        visible_limit = cfg.fetch('limit', 3)
        next if all.size <= visible_limit

        @site.add_generated_page(RelatedIndexPage.new(page, @site, all))
      end
    end

    def generate_paginated_pages
      @site.pages.each do |page|
        # Skip cheaply BEFORE resolving the collection — pages with no
        # `paginate:` key (or `paginate: false`) don't paginate and
        # don't need the collection lookup.
        raw = page.frontmatter['paginate']
        next if raw.nil? || raw == false

        # Resolve which collection this page paginates. Four signals,
        # first match wins:
        #   1. Pages inside a collection paginate that collection.
        #   2. The index page OF a collection paginates its own collection.
        #   3. Frontmatter `paginate_collection:`.
        #   4. Final fallback: posts.
        coll_name = page.collection ||
                    @site.collection_index_name(page) ||
                    page.frontmatter['paginate_collection'] ||
                    'posts'

        # Now resolve per_page WITH the collection in scope so
        # `paginate: true` can pick up a per-collection default.
        per_page = resolve_per_page(page, coll_name)
        next unless per_page

        items = @site.collection(coll_name)

        slices = items.each_slice(per_page).to_a
        next if slices.size <= 1

        page.paginator = Paginator.new(
          posts: slices.first,
          page: 1,
          total_pages: slices.size,
          base_url: page.url
        )

        slices[1..].each_with_index do |slice, idx|
          shard_paginator = Paginator.new(
            posts: slice,
            page: idx + 2,
            total_pages: slices.size,
            base_url: page.url
          )
          @site.add_generated_page(PaginatedShard.new(page, shard_paginator))
        end
      end
    end

    # ----------------------------------------------------------------
    # Render
    # ----------------------------------------------------------------

    # Render pages in parallel across CPU cores. ERB rendering does
    # enough I/O (template reads, asset_path lookups, write to disk)
    # that threading helps despite the GIL. For tiny sites the
    # thread-spawn overhead exceeds the benefit, so fall through to a
    # serial loop below the threshold.
    #
    # In incremental mode, pages whose output is up to date are
    # skipped via Page#needs_render?.
    #
    # Scheduling: a `Thread::Queue` work-stealing pool. Earlier slices-
    # based partitioning evenly split the page list, but render cost
    # varies wildly (a post with a TOC, bundle picture, syntax
    # highlighting, and minified output costs far more than a flat tag
    # page) so the slowest slice dominated total time. With a queue,
    # whichever thread finishes its current page picks the next one up
    # immediately.
    def render_pages
      detect_output_collisions!

      pages = @site.incremental? ? @site.all_pages.select(&:needs_render?) : @site.all_pages
      return if pages.empty?

      errors = []
      errors_mutex = Mutex.new
      slow_pages = []
      slow_mutex = Mutex.new

      if pages.size < PARALLEL_THRESHOLD
        pages.each { |page| render_one(page, errors, errors_mutex, slow_pages, slow_mutex) }
        report_slow_pages!(slow_pages)
        return report_render_errors!(errors)
      end

      queue = Thread::Queue.new
      pages.each { |page| queue << page }

      thread_count = [self.class.render_threads, pages.size].min
      threads = Array.new(thread_count) do
        Thread.new do
          loop do
            # `pop(true)` is non-blocking — it raises ThreadError when the
            # queue is empty, which is the worker's signal to exit. This
            # is the work-stealing primitive: every worker keeps pulling
            # until there's nothing left, regardless of how many pages
            # other workers have already finished.
            page = begin
              queue.pop(true)
            rescue ThreadError
              break
            end
            render_one(page, errors, errors_mutex, slow_pages, slow_mutex)
          end
        end
      end
      threads.each(&:join)

      report_slow_pages!(slow_pages)
      report_render_errors!(errors)
    end

    # ----------------------------------------------------------------
    # Post-process
    # ----------------------------------------------------------------

    def post_process(html, page: nil)
      # `rewrite_bundle_urls` runs before `images.post_process_html` so
      # the latter sees absolute paths (`/posts/foo/hero.jpg`) and can
      # match them against the URL → source registry.
      html = rewrite_bundle_urls(html, page) if page&.respond_to?(:post?) && page.post?
      html = SyntaxHighlighter.process(html) if @site.config['syntax_highlighting']
      html = @site.images.post_process_html(html, page: page) if @site.images.enabled?
      # Plugin filter — runs after the engine's built-in post-processing
      # so plugin output sees the same shape browsers will. Runs BEFORE
      # livereload injection + minification so plugin transformations
      # are minified along with the rest of the page.
      html = run_plugin_filters(html, page)
      html = inject_livereload(html) if @site.env == :development
      html = Minifier.minify(html) if minify_html?
      html
    end

    # Minify rendered HTML in production by default; disable with
    # `minify: false` in site.yml. Off in development so livereload +
    # view-source stay readable.
    def minify_html?
      return @site.config['minify'] if @site.config.key?('minify')

      @site.env == :production
    end

    private

    # Plugin filters, timed on the page clock so the slow-page report
    # can say whether they mattered. Read back by `render_one`, which
    # zeroes the counter before each page.
    def run_plugin_filters(html, page)
      t0 = Process.clock_gettime(PAGE_CLOCK, :millisecond)
      Hooks.run_filter(:post_process, html, @site, page)
    ensure
      spent = Process.clock_gettime(PAGE_CLOCK, :millisecond) - t0
      Thread.current[PLUGIN_FILTER_MS] = (Thread.current[PLUGIN_FILTER_MS] || 0) + spent
    end

    # Fail the build when two pages resolve to the same output file.
    # Without this, whichever page the (parallel) render loop writes
    # last silently wins — nondeterministically build-to-build — and
    # the sitemap emits a duplicate <loc>. Common causes: two post
    # directories whose names differ only by the stripped `YYYY-MM-DD-`
    # date prefix, two pages sharing a `permalink:`, or two taxonomy
    # terms that slugify to the same value. Runs over the FULL page set
    # (not just `needs_render?`) so a collision is caught even on an
    # incremental rebuild that only touches one side of it.
    def detect_output_collisions!
      by_path = Hash.new { |h, k| h[k] = [] }
      @site.all_pages.each do |page|
        next unless page.respond_to?(:output_path)

        by_path[page.output_path] << page
      end

      collisions = by_path.select { |_, pages| pages.size > 1 }
      return if collisions.empty?

      details = collisions.map do |path, pages|
        sources = pages.map { |p| page_identifier(p) }.sort
        "  #{path}\n    <- #{sources.join("\n    <- ")}"
      end.join("\n")
      raise "output path collision: #{collisions.size} output file(s) claimed by more than " \
            "one page. Rename or re-slug the sources:\n#{details}"
    end

    def page_identifier(page)
      if page.respond_to?(:source_path) && page.source_path
        page.source_path
      elsif page.respond_to?(:url) && page.url
        page.url
      else
        page.class.name
      end
    end

    # Render a single page, collecting any exception into `errors` so a
    # failure in one page doesn't silently kill an entire slice. The
    # default Thread behaviour is to re-raise on join — but only for the
    # FIRST thread that raised; later threads' errors disappear.
    # Collecting explicitly gives us a full report at the end.
    #
    # Also times each render and surfaces a warning when it crosses
    # `SLOW_PAGE_THRESHOLD_MS`. Slow pages are collected for the
    # end-of-build summary.
    def render_one(page, errors, mutex, slow_pages = nil, slow_mutex = nil)
      Thread.current[PLUGIN_FILTER_MS] = 0
      t0 = Process.clock_gettime(PAGE_CLOCK, :millisecond)
      page.write
      elapsed_ms = Process.clock_gettime(PAGE_CLOCK, :millisecond) - t0

      return unless slow_page?(elapsed_ms) && slow_pages && slow_mutex

      causes = infer_slow_causes(page, elapsed_ms: elapsed_ms, plugin_ms: Thread.current[PLUGIN_FILTER_MS])
      Log.warn(slow_page_note(page, elapsed_ms, causes))
      slow_mutex.synchronize { slow_pages << { page: page, ms: elapsed_ms, causes: causes } }
    rescue StandardError, PathSafe::Error => e
      # Generated pages (TaxonomyPage, PaginatedShard, PublisherShowPage)
      # don't have a `source_path` — they synthesise URLs without a
      # backing markdown file. Fall back to the URL (or class name) so
      # the error report is still attributable.
      identifier = if page.respond_to?(:source_path) && page.source_path
                     page.source_path
                   elsif page.respond_to?(:url) && page.url
                     page.url
                   else
                     page.class.name
                   end
      mutex.synchronize { errors << [identifier, e] }
    end

    # Did this page cross the slow threshold? Disabled when the
    # threshold is set to 0 (operator opted out via env var).
    def slow_page?(elapsed_ms)
      SLOW_PAGE_THRESHOLD_MS.positive? && elapsed_ms >= SLOW_PAGE_THRESHOLD_MS
    end

    # Cause catalogue. Each entry has:
    #
    #   label:  short string for the inline warning + summary header
    #   impact: one-sentence explanation of WHY this signal causes
    #           slow renders — what work the engine does proportional
    #           to it.
    #   advice: one-sentence suggestion the operator can act on.
    #
    # The point is to turn a generic "your page is slow" into a
    # specific "here's why, and here's what to try." The summary at
    # end-of-build prints one impact + advice block per cause type
    # that fired across the slow page set (deduped, so the operator
    # reads each explanation once even if ten pages share the same
    # cause).
    SLOW_PAGE_CAUSES = {
      large_output: {
        label:  ->(meta) { "#{meta[:kb]} KB output" },
        impact: 'HTML minification and any plugin `:post_process` filters scan the whole document — cost scales with output size.',
        advice: 'Trim the body, split into multiple pages, or set `minify: false` if the site doesn\'t need minified output.'
      },
      many_images: {
        label:  ->(meta) { "#{meta[:count]} inline images" },
        impact: 'Every `<img>` is matched against the image-pipeline URL registry and rewritten to a responsive `<picture>` block. Per-tag cost is small; it adds up.',
        advice: 'Reduce images on this page, move large galleries to their own page, or set `images.optimise: false` site-wide if the pipeline isn\'t needed.'
      },
      many_code_blocks: {
        label:  ->(meta) { "#{meta[:count]} code blocks" },
        impact: 'Rouge tokenises every `<pre>` block separately — long examples and many small blocks both add measurable time.',
        advice: 'Shorten code examples, link to a gist for the long ones, or set `syntax_highlighting: false` site-wide if you don\'t need it.'
      },
      toc: {
        label:  ->(_)    { 'TOC' },
        impact: 'The TOC partial scans the rendered body for h2/h3 headings on every render. Small per page; meaningful when the body is long.',
        advice: 'Set `toc: false` in the page\'s frontmatter to skip the TOC for one page, or raise `posts.show.toc.min_headings` to skip shorter pages globally.'
      },
      plugin_filter: {
        label:  ->(meta) { "plugin filter #{meta[:ms]}ms" },
        impact: 'A plugin registered against the `:post_process` hook transforms the rendered HTML — the engine can\'t see inside the plugin code.',
        advice: 'Profile the offending plugin in `plugins/*.rb`, or temporarily disable it (rename to `*.rb.off`) to confirm it\'s the bottleneck.'
      }
    }.freeze

    # Human-readable slow-page warning emitted in real-time. Stays
    # one line so it scans cleanly in CI logs; the end-of-build
    # summary is where the rich impact + advice goes.
    def slow_page_note(page, elapsed_ms, causes)
      url       = page.respond_to?(:url) && page.url ? page.url : page.source_path.to_s
      cause_str = causes.empty? ? '' : " — #{causes.map { |c| c[:label] }.join(' · ')}"
      "Slow page: #{url} took #{format_ms(elapsed_ms)} of CPU#{cause_str}"
    end

    # Sample cheap heuristics that often correlate with slow renders.
    # Re-reads the just-written output once (only fires for pages
    # that already crossed the threshold, so cost is bounded by the
    # slow-page count, not the build size).
    #
    # Returns an array of `{type:, label:}` hashes — `type` is the
    # cause-catalogue key, `label` is the populated short string for
    # the inline warning. The summary uses `type` to look up the
    # full impact + advice from `SLOW_PAGE_CAUSES`.
    def infer_slow_causes(page, elapsed_ms: 0, plugin_ms: 0)
      causes = content_causes(page)
      if plugin_ms.to_i.positive? && plugin_ms >= elapsed_ms * PLUGIN_FILTER_SHARE
        causes << build_cause(:plugin_filter, ms: plugin_ms)
      end
      causes
    end

    def content_causes(page)
      causes = []
      return causes unless page.respond_to?(:output_path)
      path = page.output_path
      return causes unless File.exist?(path)

      size_kb = (File.size(path) / 1024.0).round
      causes << build_cause(:large_output, kb: size_kb) if size_kb >= 200

      html = File.read(path, encoding: 'UTF-8')
      img_count = html.scan(/<img\b/i).size
      causes << build_cause(:many_images, count: img_count) if img_count >= 20
      code_count = html.scan(/<pre\b/i).size
      causes << build_cause(:many_code_blocks, count: code_count) if code_count >= 10
      causes << build_cause(:toc) if html.include?('class="toc"') || html.include?("class='toc'")
      causes
    rescue StandardError
      # Cause inference is best-effort — never let a probe failure
      # mask the slow-page warning itself.
      causes
    end

    def build_cause(type, **meta)
      { type: type, label: SLOW_PAGE_CAUSES[type][:label].call(meta) }
    end

    # End-of-build slow-page summary. Three parts:
    #
    #   1. Header — count of slow pages and the threshold that fired.
    #   2. Per-page list (slowest first, top 5) — URL, time,
    #      cause labels.
    #   3. "What this means + what to try" block — one entry per
    #      unique cause type, deduped across all slow pages, so the
    #      operator sees each explanation once.
    #
    # Goal: when the operator reads the summary they know exactly
    # what's expensive on which pages AND what knob to turn.
    def report_slow_pages!(slow_pages)
      return if slow_pages.empty?

      slow_pages.sort_by! { |sp| -sp[:ms] }
      Log.info("Slow pages (>#{SLOW_PAGE_THRESHOLD_MS}ms CPU): #{slow_pages.size}")
      slow_pages.first(5).each do |sp|
        url       = sp[:page].respond_to?(:url) && sp[:page].url ? sp[:page].url : sp[:page].source_path
        cause_str = sp[:causes].empty? ? '' : "  (#{sp[:causes].map { |c| c[:label] }.join(' · ')})"
        Log.info("  #{format_ms(sp[:ms]).rjust(7)}  #{url}#{cause_str}")
      end

      report_slow_page_explanations!(slow_pages)
    end

    # Unique cause types across the slow set, each printed with its
    # impact + advice from SLOW_PAGE_CAUSES. Order follows
    # SLOW_PAGE_CAUSES declaration order (broadest causes first, then
    # narrower ones). Silent when no causes were inferred.
    def report_slow_page_explanations!(slow_pages)
      triggered_types = slow_pages.flat_map { |sp| sp[:causes].map { |c| c[:type] } }.uniq
      ordered_types   = SLOW_PAGE_CAUSES.keys & triggered_types
      return if ordered_types.empty?

      Log.info('')
      Log.info('What this means and what to try:')
      ordered_types.each do |type|
        entry = SLOW_PAGE_CAUSES[type]
        Log.info("  #{type}:")
        Log.info("    #{entry[:impact]}")
        Log.info("    Try: #{entry[:advice]}")
      end
    end

    # Compact ms / s formatter. `850ms`, `1.2s`, `12.4s`.
    def format_ms(ms)
      ms < 1000 ? "#{ms}ms" : format('%.1fs', ms / 1000.0)
    end

    def report_render_errors!(errors)
      return if errors.empty?

      errors.each do |path, e|
        Log.error "render failed: #{path} — #{e.class}: #{e.message}"
        e.backtrace&.first(5)&.each { |line| Log.error "  #{line}" }
      end
      raise "#{errors.size} page(s) failed to render"
    end

    def compute_shared_deps_mtime
      roots = [@site.site_root, @site.engine_root].uniq

      # Static globs (anchored, no per-site resolution).
      patterns = GLOBAL_DEP_GLOBS.dup

      # Active-theme glob — only walk the theme this site is actually
      # using. Without scoping, every build walks every theme the gem
      # ships (bootstrap, magazine, notebook, sand, …), most of which
      # have nothing to do with the current site's rendered output.
      theme = @site.config['theme'].to_s
      patterns << File.join('themes', theme, '**', '*') unless theme.empty? || theme == 'none'

      mtimes = patterns.flat_map do |pattern|
        roots.flat_map do |root|
          # No `.sort` — we feed every entry into `.max` below, which is
          # order-invariant. Sorting would just add overhead.
          Dir.glob(File.join(root, pattern)).map do |path|
            File.mtime(path)
          rescue StandardError
            Time.at(0)
          end
        end
      end
      mtimes.compact.max || Time.at(0)
    end

    # Most-recent mtime across the layout file plus every ancestor
    # layout it chains into. Returns Time.at(0) when the layout file
    # can't be found — Page#needs_render? then falls through to the
    # global mtime and source mtime checks.
    def compute_layout_deps_mtime(layout_name)
      chain = layout_chain(layout_name)
      return Time.at(0) if chain.empty?

      chain.map do |path|
        File.mtime(path)
      rescue StandardError
        Time.at(0)
      end.max
    end

    # Walk the `layout:` chain starting at `layout_name`, returning the
    # absolute paths of every layout file in the chain. Memoised per
    # name. Cycle-safe — a layout that (illegally) extends itself
    # transitively stops at the second visit.
    #
    # No internal locking — the only caller is
    # `compute_layout_deps_mtime`, which runs under `@deps_mutex` (see
    # `layout_deps_mtime`). Adding a lock here would deadlock.
    def layout_chain(layout_name)
      @layout_chains[layout_name] ||= build_layout_chain(layout_name)
    end

    def build_layout_chain(layout_name)
      chain = []
      current = layout_name
      seen = {}

      while current && !seen[current]
        seen[current] = true
        path = @site.find_in_paths(File.join('app', 'views', 'layouts', "#{current}.html.erb"))
        break unless File.exist?(path)

        chain << path
        current = parent_layout_of(path)
      end

      chain
    end

    # Read just the YAML frontmatter from a layout file (if any) and
    # return its `layout:` key — the parent in the chain — or nil.
    # Layouts without frontmatter, or with empty `layout:`, terminate
    # the chain.
    #
    # Failures are not silently swallowed. A YAML syntax error in a
    # layout's frontmatter used to be treated as "no parent" — the
    # page rendered against the wrong outer layout, and the operator
    # got no signal that the chain was broken. Re-raise so the build
    # fails loudly with a clear message; the layout path is wrapped
    # into the exception so the operator can find the offending file
    # without grepping.
    def parent_layout_of(path)
      raw = File.read(path, encoding: 'UTF-8')
      match = raw.match(LAYOUT_FRONTMATTER_RE)
      return nil unless match

      fm = YAML.safe_load(match[1], permitted_classes: Abqari::YAML_PERMITTED_CLASSES) || {}
      parent = fm['layout']
      parent && !parent.to_s.empty? ? parent.to_s : nil
    rescue Psych::SyntaxError => e
      raise "invalid YAML frontmatter in layout #{path}: #{e.message}"
    rescue StandardError => e
      raise "failed to read layout frontmatter in #{path}: #{e.class}: #{e.message}"
    end

    # Resolve the page-size for a paginating page, or nil for "don't paginate."
    #
    # Frontmatter:
    #   paginate: 25      → 25 posts per page (explicit override)
    #   paginate: true    → fall back through the config chain
    #   paginate: false   → no pagination (overrides any default)
    #   paginate: <0/nil> → no pagination
    #
    # Fallback chain when `paginate: true` (in priority order):
    #   1. `collections.<coll_name>.pagination.per_page` — per-collection
    #      override for the collection this page paginates. Lets a site
    #      use 12 photos per page but 10 posts without setting
    #      `paginate: N` on every archive file.
    #   2. `pagination.per_page` — site-wide global default.
    #   3. PAGINATION_DEFAULT (10) — engine fallback.
    #
    # `coll_name` is optional for back-compat — when omitted (or nil),
    # the lookup skips the per-collection layer and goes straight to
    # the global default. The build's main path
    # (`generate_paginated_pages`) always supplies it.
    def resolve_per_page(page, coll_name = nil)
      raw = page.frontmatter['paginate']
      return nil if raw == false
      return nil if raw.nil?

      if raw.is_a?(Integer)
        raw.positive? ? raw : nil
      elsif raw == true
        configured_per_page(coll_name)
      else
        # A quoted `paginate: "10"` (String) or any other non-Integer,
        # non-boolean value silently disabled pagination. Warn so the
        # typo is visible.
        src = page.respond_to?(:source_path) ? page.source_path : page
        Log.warn "Ignoring `paginate: #{raw.inspect}` in #{src} — expected true, false, or a positive integer."
        nil
      end
    end

    def configured_per_page(coll_name = nil)
      if coll_name
        per_coll = @site.config.dig('collections', coll_name, 'pagination', 'per_page')
        return per_coll if per_coll.is_a?(Integer) && per_coll.positive?
      end

      configured = @site.config.dig('pagination', 'per_page')
      configured.is_a?(Integer) && configured.positive? ? configured : PAGINATION_DEFAULT
    end

    # Rewrite relative <img>/<a> URLs in a post bundle to absolute paths
    # under the post's URL. So `<img src="hero.jpg">` in a bundle for
    # /posts/foo/ becomes `<img src="/posts/foo/hero.jpg">`.
    def rewrite_bundle_urls(html, page)
      base = page.url

      html.gsub(/(<(?:img|a)\s++[^>]*?(?:src|href)=")([^"]+)/) do
        prefix = ::Regexp.last_match(1)
        url    = ::Regexp.last_match(2)

        if url.start_with?('http://', 'https://', '/', '#', 'mailto:', 'tel:', 'data:')
          "#{prefix}#{url}"
        else
          "#{prefix}#{base}#{url}"
        end
      end
    end

    # Livereload client. Uses Server-Sent Events to receive rebuild
    # events from the dev server as they happen — sub-50 ms latency
    # vs the ~250 ms median of the old polling implementation. The
    # browser opens a single persistent EventSource connection per
    # tab; the server holds it open and pushes a `{version, scope}`
    # JSON payload on every rebuild.
    #
    # Reconnect logic is provided by EventSource itself — if the
    # server restarts the client auto-reconnects after a short delay.
    LIVERELOAD_SCRIPT = <<~SCRIPT
      <script>
      (function() {
        let firstVersion = null;
        async function swapCss() {
          const html = await fetch(location.pathname, { cache: 'no-store' }).then(r => r.text());
          const matches = [...html.matchAll(/<link\\s+rel="stylesheet"\\s+href="([^"]+)"/gi)].map(m => m[1]);
          document.querySelectorAll('link[rel="stylesheet"]').forEach((link, i) => {
            if (matches[i] && link.getAttribute('href') !== matches[i]) {
              link.setAttribute('href', matches[i]);
            }
          });
        }
        const sse = new EventSource('/__reload__');
        sse.onmessage = (e) => {
          try {
            const { version, scope } = JSON.parse(e.data);
            if (firstVersion === null) { firstVersion = version; return; }
            if (version === firstVersion) return;
            firstVersion = version;
            scope === 'css' ? swapCss() : location.reload();
          } catch (err) {}
        };
      })();
      </script>
    SCRIPT

    # Insert the livereload poller just before the closing body tag.
    # HTML is case-insensitive, so the match has to be too — a layout
    # that closes with `</Body>` is legal markup and should still
    # hot-reload in dev. The substitution preserves the original
    # casing of the matched tag.
    CLOSING_BODY_RE = %r{</body>}i.freeze

    def inject_livereload(html)
      return html unless html.match?(CLOSING_BODY_RE)

      html.sub(CLOSING_BODY_RE) { |match| "#{LIVERELOAD_SCRIPT}#{match}" }
    end
  end
end

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

    # Default page-size for `paginate: true`. Overridable per-site via
    # `pagination.per_page` config.
    PAGINATION_DEFAULT = 10

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
    GLOBAL_DEP_GLOBS = [
      'app/views/partials/**/*',
      'app/icons/**/*',
      'app/assets/**/*',
      'lib/**/*',
      'config/**/*',
      'data/**/*',
      'themes/**/*'
    ].freeze

    LAYOUT_FRONTMATTER_RE = /\A---\s*\n(.*?\n)---\s*\n/m.freeze

    def initialize(site)
      @site = site
      @template_cache = {}
      @template_mutex = Mutex.new
    end

    # Reset between builds (incremental dev server keeps the Site
    # around across rebuilds; the template cache must clear so layout
    # edits take effect). Layout-chain caches are reset too — a new
    # layout file or a frontmatter `layout:` edit changes the chain.
    def clear_template_cache
      @template_mutex.synchronize { @template_cache = {} }
      @shared_deps_mtime = nil
      @layout_chains    = nil
      @layout_mtimes    = nil
    end

    # Lazily compile and cache a template. Safe to call from threads.
    # Uses Erubi with `escape: true` so every `<%= %>` interpolation is
    # auto-escaped; partials emit raw markup via `<%== %>`. See
    # ErbiTemplate for the rationale.
    def compiled_template(path)
      @template_mutex.synchronize do
        @template_cache[path] ||= ErbiTemplate.new(File.read(path, encoding: 'UTF-8'))
      end
    end

    # Most-recent mtime across the global dep set (everything except
    # layout files). When this is newer than a page's output, that
    # output is stale regardless of which layout the page uses.
    def shared_deps_mtime
      @shared_deps_mtime ||= compute_shared_deps_mtime
    end

    # Most-recent mtime across `layout_name`'s file plus every ancestor
    # in its `layout:` chain. Memoised per layout name. Page#needs_render?
    # combines this with `shared_deps_mtime` so editing `layouts/post.html.erb`
    # only invalidates pages that resolve to the `post` layout (or
    # something that extends it), not photo / publication / workshop
    # pages.
    def layout_deps_mtime(layout_name)
      @layout_mtimes ||= {}
      @layout_mtimes[layout_name.to_s] ||= compute_layout_deps_mtime(layout_name.to_s)
    end

    # ----------------------------------------------------------------
    # Generators
    # ----------------------------------------------------------------

    def generate_all
      generate_tag_pages
      generate_paginated_pages
      generate_visualizations
      generate_folio_pages
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

    # Auto-generate /books/, /bundles/, /series/ index + show pages from
    # Folio data. No-op when `folio:` config is missing. Pages already
    # defined via content/ markdown files take precedence.
    def generate_folio_pages
      FolioPages.new(@site).pages.each { |page| @site.add_generated_page(page) }
    end

    # Generate `/<source url>related/` index pages for any show-view page
    # whose related list is longer than its visible `limit`.
    def generate_related_pages
      @site.pages.select { |p| p.respond_to?(:collection) && p.collection }.each do |page|
        cfg = @site.collection_config(page.collection)['related'] || {}
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
      pages = @site.incremental? ? @site.all_pages.select(&:needs_render?) : @site.all_pages
      return if pages.empty?

      errors = []
      errors_mutex = Mutex.new

      if pages.size < PARALLEL_THRESHOLD
        pages.each { |page| render_one(page, errors, errors_mutex) }
        return report_render_errors!(errors)
      end

      queue = Thread::Queue.new
      pages.each { |page| queue << page }

      thread_count = [Etc.nprocessors, pages.size].min
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
            render_one(page, errors, errors_mutex)
          end
        end
      end
      threads.each(&:join)

      report_render_errors!(errors)
    end

    # ----------------------------------------------------------------
    # Post-process
    # ----------------------------------------------------------------

    def post_process(html, page: nil)
      html = rewrite_bundle_urls(html, page) if page&.respond_to?(:post?) && page.post?
      html = SyntaxHighlighter.process(html) if @site.config['syntax_highlighting']
      html = @site.images.post_process_html(html) if @site.images.enabled?
      html = inject_livereload(html) if @site.env == :development
      html = Minifier.minify(html) if minify_html?
      html
    end

    # Minify rendered HTML in production by default; disable with
    # `minify: false` in site.yml. Off in development so livereload +
    # view-source stay readable.
    def minify_html?
      cfg = @site.config
      return cfg['minify'] if cfg.key?('minify')

      @site.env == :production
    end

    private

    # Render a single page, collecting any exception into `errors` so a
    # failure in one page doesn't silently kill an entire slice. The
    # default Thread behaviour is to re-raise on join — but only for the
    # FIRST thread that raised; later threads' errors disappear.
    # Collecting explicitly gives us a full report at the end.
    def render_one(page, errors, mutex)
      page.write
    rescue StandardError, PathSafe::Error => e
      mutex.synchronize { errors << [page.source_path, e] }
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
      mtimes = GLOBAL_DEP_GLOBS.flat_map do |pattern|
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
    def layout_chain(layout_name)
      @layout_chains ||= {}
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
    def parent_layout_of(path)
      raw = File.read(path, encoding: 'UTF-8')
      match = raw.match(LAYOUT_FRONTMATTER_RE)
      return nil unless match

      fm = YAML.safe_load(match[1]) || {}
      parent = fm['layout']
      parent && !parent.to_s.empty? ? parent.to_s : nil
    rescue StandardError
      nil
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

      html.gsub(/(<(?:img|a)\s+[^>]*?(?:src|href)=")([^"]+)/) do
        prefix = ::Regexp.last_match(1)
        url    = ::Regexp.last_match(2)

        if url.start_with?('http://', 'https://', '/', '#', 'mailto:', 'tel:', 'data:')
          "#{prefix}#{url}"
        else
          "#{prefix}#{base}#{url}"
        end
      end
    end

    LIVERELOAD_SCRIPT = <<~SCRIPT
      <script>
      (function() {
        let v = null;
        async function swapCss() {
          const html = await fetch(location.pathname, { cache: 'no-store' }).then(r => r.text());
          const matches = [...html.matchAll(/<link\\s+rel="stylesheet"\\s+href="([^"]+)"/gi)].map(m => m[1]);
          document.querySelectorAll('link[rel="stylesheet"]').forEach((link, i) => {
            if (matches[i] && link.getAttribute('href') !== matches[i]) {
              link.setAttribute('href', matches[i]);
            }
          });
        }
        setInterval(async () => {
          try {
            const { version, scope } = await (await fetch('/__reload__', { cache: 'no-store' })).json();
            if (v === null) { v = version; return; }
            if (v === version) return;
            v = version;
            scope === 'css' ? swapCss() : location.reload();
          } catch (e) {}
        }, 500);
      })();
      </script>
    SCRIPT

    def inject_livereload(html)
      return html unless html.include?('</body>')

      html.sub('</body>', "#{LIVERELOAD_SCRIPT}</body>")
    end
  end
end

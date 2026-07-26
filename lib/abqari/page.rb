# frozen_string_literal: true

require 'yaml'
require 'fileutils'
require 'commonmarker'

require_relative 'page/parser'
require_relative 'page/path'
require_relative 'page/bundle'
require_relative 'page/incremental'

module Abqari
  # A single `.md` page under `content/`. Pages parse their frontmatter
  # + body at construction, then expose:
  #
  #   - Identity:  `title`, `description`, `date`, `tags`, `slug`
  #   - Collection: `collection`, `post?`, `disabled?`, `draft?`, `future?`
  #   - Content:   `body`, `raw_body`, `content`
  #   - Render:    `render`, `write`
  #
  # Cross-cutting concerns live in mixin modules so the core class
  # stays focused. Each module operates on Page instance state (the
  # `@source_path`, `@site`, `@frontmatter`, `@body`, `@content`
  # ivars) — there's no separate "Page collaborator" object to keep
  # in sync.
  #
  #   - Page::Parser      : initial file read + frontmatter parsing +
  #                          lazy body reload (see `forget_body!`).
  #   - Page::Path        : `output_path`, `url`, `layout_name`,
  #                          render_permalink, relative_* helpers.
  #                          Routes user-input `permalink:` through
  #                          PathSafe.join_under so traversal is
  #                          impossible by construction.
  #   - Page::Bundle      : bundle directory discovery + asset
  #                          enumeration (with symlink filtering).
  #   - Page::Incremental : `needs_render?`, `lastmod`, `forget_body!`.
  class Page
    # Frontmatter parser — re-exposed here so existing call sites
    # (`page/parser.rb`) keep their `Page::FRONTMATTER_RE` reference.
    # The canonical definition lives in `Abqari::FRONTMATTER_RE`.
    FRONTMATTER_RE = Abqari::FRONTMATTER_RE
    DATE_PREFIX_RE = /\A(\d{4})-(\d{2})-(\d{2})-/.freeze

    # `render.unsafe: true` lets authors drop raw HTML directly into a
    # markdown body — `<mark>`, `<details>`/`<summary>`, custom `<div>`
    # wrappers, embeds, anything Markdown doesn't have a syntax for.
    # This is safe in Abqari because content is the author's own; we're
    # not rendering untrusted markdown from anonymous visitors. See
    # docs/security.md §1.
    MARKDOWN_OPTIONS = {
      extension: {
        table: true,
        strikethrough: true,
        autolink: true,
        tasklist: true,
        footnotes: true,
        header_ids: ''
      },
      render: {
        unsafe: true,
        # Explicit, not inherited: commonmarker 2.x defaults this to
        # TRUE, which turns every soft line break into a `<br />`.
        # Prose in this project (and most markdown) is hard-wrapped in
        # the source, so inheriting that default reflows every
        # paragraph into ragged lines. Pin it and the wrap stays a
        # source-formatting detail, invisible in the output.
        hardbreaks: false
      },
      plugins: {
        syntax_highlighter: nil # Rouge handles this in Site#post_process
      }
    }.freeze

    include Parser
    include Path
    include Bundle
    include Incremental

    attr_reader :source_path, :site, :frontmatter
    attr_accessor :paginator

    def initialize(source_path, site)
      @source_path = source_path
      @site = site
      @paginator = nil
      parse
    end

    # --------------------------------------------------------------
    # Identity
    # --------------------------------------------------------------

    # Title resolution: publications use `title`; bundles + series use
    # `name` (per the canonical schema in docs/publications.md). Posts,
    # photos, workshops, and untyped pages continue to use `title`.
    def title
      key = title_key_for_collection
      frontmatter[key] || frontmatter['title'] || derived_title
    end

    # Resolution chain:
    #   1. Frontmatter explicit value (per-collection key:
    #        - publications → `tagline` then `excerpt`
    #        - everything else → `description`)
    #   2. The page's first paragraph, with markdown stripped. Lets
    #      writers ship a post without setting `description:` and still
    #      get a useful meta description / lede for SEO and social
    #      cards. Matches Hugo / Eleventy `firstParagraph` behaviour.
    #   3. Site-wide `description:` from config — final fallback.
    #
    # The auto-derived path truncates to ~200 chars and trims trailing
    # punctuation so it reads as a complete sentence.
    #
    # Memoised — listing partials (`_post_list`, related-items, feeds,
    # sitemap) all call `description` on every page in their slice,
    # and the auto-derived path re-reads the body from disk if
    # `forget_body!` has already released it. Without memoisation a
    # 1000-post archive triggers 1000 cold-cache file reads when it
    # renders after the per-post pages. Memoised, the cost is one
    # read per page across the whole build.
    def description
      return @description if defined?(@description)

      explicit = explicit_description_value
      @description = if !explicit.to_s.strip.empty?
                       explicit
                     elsif !(auto = first_paragraph_text).to_s.strip.empty?
                       auto
                     else
                       site.config['description']
                     end
    end

    def date
      return @date if defined?(@date)

      source_for_date = bundle_dir ? File.basename(bundle_dir) : File.basename(source_path)
      prefix_match    = source_for_date.match(DATE_PREFIX_RE)

      @date = if frontmatter['date']
                fm_date = begin
                  Helpers.to_time(frontmatter['date'])
                rescue ArgumentError, TypeError => e
                  raise "invalid date #{frontmatter['date'].inspect} in #{source_path}: #{e.message}"
                end
                # Front matter wins over the filename prefix, but warn if
                # they disagree — a silent mismatch is a common "why is my
                # URL/order wrong?" gotcha.
                if prefix_match && fm_date.strftime('%Y-%m-%d') != prefix_match[0].chomp('-')
                  Log.warn "date mismatch in #{source_path}: frontmatter " \
                           "#{fm_date.strftime('%Y-%m-%d')} overrides filename prefix #{prefix_match[0].chomp('-')}"
                end
                fm_date
              elsif prefix_match
                Time.new(prefix_match[1].to_i, prefix_match[2].to_i, prefix_match[3].to_i)
              end
    end

    def tags
      Array(frontmatter['tags'])
    end

    # The collection-relative slug. Used externally by Site#featured and
    # by book/bundle layouts to look up publication data. For bundle-
    # style content (`content/<col>/<slug>/index.md`) this returns the
    # parent dir name; for flat content (`content/<col>/<slug>.md`) the
    # filename minus date prefix. Returns nil for top-level pages
    # outside any collection.
    def slug
      return nil unless collection

      base = bundle_dir ? File.basename(bundle_dir) : File.basename(source_path, '.md')
      Helpers.slugify(base.sub(DATE_PREFIX_RE, ''))
    end

    # --------------------------------------------------------------
    # Collection identity + status
    # --------------------------------------------------------------

    # Backwards-compatible "is this in the posts collection?" check.
    # Used throughout the engine to opt into post-specific behaviour:
    # bundle assets, paginated indexes, RSS, JSON-LD Article schema.
    def post?
      collection == 'posts'
    end

    # Which collection does this page belong to, or nil for top-level
    # pages like content/about.md. A collection is a config-defined
    # subdirectory of content/ — e.g. `content/posts/`,
    # `content/photos/`, `content/workshops/` — with its own permalink
    # pattern and default layout. Users declare additional ones in
    # `collections:` in config/site.yml.
    def collection
      return @collection if defined?(@collection)

      @collection = nil
      site.collections.each do |name, cfg|
        # Disabled collections are invisible — their files don't get
        # claimed as collection items, their permalinks don't apply,
        # and SiteLoader#load_pages skips them entirely.
        next unless cfg.fetch('enabled', true)

        source = File.join(site.site_root, cfg['source'])
        next unless source_path.start_with?(source + File::SEPARATOR)

        # Bundle-style: content/<name>/<slug>/index.md (default for posts).
        if cfg['bundle'] != false
          next unless File.basename(source_path) == 'index.md'

          relative = source_path.sub("#{source}/", '').split('/')
          @collection = name if relative.length == 2
        else
          # Flat: content/<name>/<slug>.md
          relative = source_path.sub("#{source}/", '').split('/')
          @collection = name if relative.length == 1
        end
        break if @collection
      end
      @collection
    end

    # Page-level on/off switch — `enabled: false` in frontmatter skips
    # the page entirely from the build (no HTML output, no nav entry,
    # no sitemap entry, no feed entry, no taxonomy contribution).
    # Distinct from `published: false` (drafts), which renders in
    # development with a banner so you can preview unpublished work.
    # `enabled: false` is hidden in BOTH dev and prod — "off," not "in
    # progress."
    def disabled?
      frontmatter['enabled'] == false
    end

    def draft?
      frontmatter['published'] == false || frontmatter['draft'] == true
    end

    def future?
      date && date > Time.now
    end

    # --------------------------------------------------------------
    # Body + content
    # --------------------------------------------------------------

    # Markdown body, lazily reloaded from disk if a previous write has
    # released it via `forget_body!`. The first read happens at parse
    # time so frontmatter is parsed in a single I/O — body is just the
    # remainder. After `write`, the body is dropped to free memory; if
    # another page later needs this page's description (which falls
    # back to its first paragraph), the file is re-read on demand.
    #
    # The reload is benign-racy under parallel rendering: concurrent
    # readers might both miss the cache and both re-read, but both end
    # up writing the same content. No mutex needed.
    def body
      return @body if @body

      load_body_from_file!
      @body
    end

    # Same content as `#body`; kept as a distinct method name because
    # callers (`first_paragraph_text`) want to be explicit they're
    # reading the un-rendered source markdown, not the ERB-evaluated
    # form that `rendered_body` would emit.
    #
    # IO failures are rescued so a transient miss (e.g. a source file
    # deleted mid-incremental-rebuild) doesn't crash a build that
    # only wanted a description fallback. The rescue is logged at
    # `warn` so the operator still sees the issue rather than
    # silently shipping the site-wide description fallback.
    def raw_body
      body
    rescue StandardError => e
      Log.warn "raw_body failed for #{source_path}: #{e.class}: #{e.message}"
      nil
    end

    # Rendered HTML for the page body.
    #
    # By default, the markdown body is passed straight through
    # commonmarker. Pages that need dynamic content opt in by setting
    # `erb: true` in their frontmatter; the body then runs through ERB
    # before commonmarker with the same RenderContext layouts use, so
    # `page`, `site`, partials, and helpers are all available.
    # Subject to the two-gate model — see `rendered_body` and
    # docs/security.md §3.
    def content
      @content ||= Commonmarker.to_html(rendered_body, options: MARKDOWN_OPTIONS)
    end

    # --------------------------------------------------------------
    # Render + write
    # --------------------------------------------------------------

    def write
      html = site.post_process(render, page: self)
      FileUtils.mkdir_p(File.dirname(output_path))
      File.write(output_path, html)
      forget_body!
    end

    private

    def render
      RenderContext.new(self, @site).render_layout(layout_name)
    end

    # Two-layer gate. ERB execution inside markdown bodies is the
    # strongest code-execution primitive in the engine — a post that
    # opts in can run arbitrary Ruby (file I/O, network, helper calls)
    # at build time. Per docs/security.md §3 this is acceptable under
    # the content-trusted model, but the site OWNER must enable it
    # site-wide before any individual page can use it:
    #
    #   1. Site:  `erb_in_markdown: true` in config/site.yml
    #   2. Page:  `erb: true` in frontmatter
    #
    # Both gates must be open for ERB to run. The default is closed at
    # both layers — turning on `erb: true` in a single post without
    # also flipping the site-wide flag is a no-op.
    def rendered_body
      return body unless frontmatter['erb']
      return body unless site.config['erb_in_markdown']

      RenderContext.new(self, @site).render_string(body)
    end

    def derived_title
      File.basename(source_path, '.md').sub(DATE_PREFIX_RE, '').tr('-_', ' ').capitalize
    end

    # Which frontmatter key carries the title for this collection.
    # `bundles` and `series` use `name` (see docs/publications.md);
    # everything else uses `title`. Falls back to `title` if the
    # collection isn't recognised.
    def title_key_for_collection
      case collection
      when 'bundles', 'series' then 'name'
      else 'title'
      end
    end

    # Per-collection description source. Publications use `tagline`
    # for the short marketing line, falling back to `excerpt` for the
    # long-form blurb. Bundles + series use `description`. Everything
    # else (posts, photos, workshops) uses `description` too. See
    # docs/publications.md for the canonical schema.
    def explicit_description_value
      case collection
      when 'publications'
        v = frontmatter['tagline']
        return v unless v.to_s.strip.empty?
        frontmatter['excerpt']
      else
        frontmatter['description']
      end
    end

    def first_paragraph_text
      return @first_paragraph_text if defined?(@first_paragraph_text)

      # Source: raw markdown body (everything after frontmatter). We
      # don't render to HTML first because we want plain text, not
      # markup, and rendering is comparatively expensive when this
      # runs once per page during head emission.
      #
      # Memoised because `description` falls back to this and is
      # called from listing partials AFTER `write` has already
      # released the body via `forget_body!`. Caching prevents the
      # cold re-read in the listing pass.
      body = raw_body.to_s
      return @first_paragraph_text = nil if body.empty?

      # First paragraph = first run of non-blank lines that isn't a
      # heading / list / blockquote / code fence / ERB tag. The naive
      # scan skips structural lines and joins what's left until the
      # next blank line.
      paragraph_lines = []
      body.each_line do |line|
        stripped = line.strip
        if stripped.empty?
          break unless paragraph_lines.empty?
          next
        end
        next if stripped.start_with?('#', '>', '```', '~~~', '|', '<%')
        next if stripped.match?(/\A[-*+]\s/)          # unordered list item (marker + space)
        next if stripped.match?(/\A\d+\.\s/)         # ordered list
        next if stripped.match?(/\A!\[/)              # image-only line
        next if stripped.match?(/\A\[.+\]:\s/)        # link reference

        paragraph_lines << stripped
      end
      return @first_paragraph_text = nil if paragraph_lines.empty?

      raw = paragraph_lines.join(' ')
      # Strip basic markdown decorations so the description reads as
      # prose, not source. Images first (`![alt](url)` → `alt`) so the
      # link pattern below doesn't consume `[alt](url)` and orphan the
      # leading `!`; then inline links, inline code, bold / italic.
      plain = raw.dup
      plain.gsub!(/!\[([^\]]*)\]\([^)]+\)/, '\1')
      plain.gsub!(/\[([^\]]+)\]\([^)]+\)/, '\1')
      plain.gsub!(/`([^`]+)`/, '\1')
      plain.gsub!(/\*\*([^*]+)\*\*/, '\1')
      plain.gsub!(/__([^_]+)__/, '\1')
      plain.gsub!(/(?<![\\*])\*([^*\n]+)\*/, '\1')
      plain.gsub!(/(?<![\\_])_([^_\n]+)_/, '\1')
      plain.gsub!(/\s+/, ' ')
      plain.strip!

      return @first_paragraph_text = nil if plain.empty?

      if plain.length > 200
        snippet = plain[0, 197]
        # Truncate at the last full word boundary to avoid breaking
        # mid-word, and append an ellipsis.
        snippet = snippet.sub(/\s\S*\z/, '')
        plain = "#{snippet}…"
      end
      @first_paragraph_text = plain
    end
  end
end

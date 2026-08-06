# frozen_string_literal: true

require 'date'
require 'fileutils'
require 'set'
require 'time'
require 'yaml'

module Abqari
  module Importers
    # Shared writer pipeline. Subclasses implement `each_post` (yielding
    # `ImportedPost` records); this base class handles HTML→Markdown
    # conversion, image download + rewriting, slug collision resolution,
    # frontmatter assembly, idempotency (skip if file exists), and
    # report accumulation.
    #
    # The base intentionally knows nothing about source formats — that
    # split keeps each importer small (just "parse this source into
    # records") and concentrates all the engine-specific behaviour
    # (bundle layout, frontmatter conventions, image pipeline interop)
    # in one place.
    class Base
      # In-memory record one importer hands to the base class per
      # source post. `body_html` is the raw HTML; the base class
      # runs it through `HtmlToMarkdown` after the importer hands
      # it over.
      ImportedPost = Struct.new(
        :title,             # String — post title
        :slug,              # String — proposed slug (will be normalised + de-duped)
        :date,              # Date or nil — post date (used in bundle dir name)
        :body_html,         # String — raw HTML body
        :tags,              # Array<String> — frontmatter tags (optional)
        :description,       # String — frontmatter description / subtitle (optional)
        :feature_image_url, # String — URL of a hero image to download (optional)
        :source_url,        # String — original URL for `canonical_url:` + redirect_from (optional)
        :source_slug,       # String — original slug at the source (for redirect_from) (optional)
        :extra_frontmatter, # Hash — anything else to add to YAML (importer-specific)
        keyword_init: true
      )

      # Options affecting the writer pipeline. Keep this struct lean —
      # CLI flags map directly onto it. Adding a knob here means
      # exposing it on the CLI too.
      Options = Struct.new(
        :site_root,       # absolute path to the destination Abqari site
        :collection,      # 'posts' / 'notes' / whatever — bundles live under content/<collection>/
        :download_images, # true to fetch remote images, false to leave URLs alone
        :flat,            # true for content/<collection>/<file>.md, false for bundle layout
        :force,           # true to overwrite existing files
        :dry_run,         # true to skip writes (still produces report)
        :write_canonical, # true to emit `canonical_url:` in frontmatter
        :strip_selectors, # Array<String> — extra selectors to strip from body before MD conversion
        :logger,          # callable taking a String — defaults to stdout-printer
        keyword_init: true
      )

      def initialize(source:, opts: nil)
        @source = source
        @opts   = opts || Options.new
        @logger = @opts.logger || ->(line) { puts line }
        @report = Support::Report.new(source: source, importer: self.class.short_name)
        @taken_slugs = Set.new
      end

      # Class-level name used in the report header ("substack", "ghost",
      # "jekyll"). Subclasses override if the constant doesn't follow
      # the convention.
      def self.short_name
        name.split('::').last.downcase
      end

      attr_reader :report

      # The whole show. Subclasses call `super` from their own `run!`
      # if they need pre/post hooks, but the default implementation is
      # enough for every importer we ship.
      def run!
        each_post do |post|
          process(post)
        end
        finalise
        @report
      end

      # Subclass-provided. Must `yield` `ImportedPost` records.
      def each_post
        raise NotImplementedError
      end

      private

      def process(post)
        slug = resolve_slug(post)
        title = post.title.to_s.strip
        title = '(untitled)' if title.empty?

        bundle_dir = bundle_dir_for(slug, post.date)
        index_path = index_path_for(bundle_dir, slug)

        if File.exist?(index_path) && !@opts.force
          @report.add(slug: slug, title: title, status: :skipped,
                      reason: "already exists at #{rel(index_path)}")
          @logger.call("  ⤼ skip: #{slug} (already exists)")
          return
        end

        @logger.call("  → #{slug}")
        warnings = []

        # Pull down the hero image (if any) first so the body conversion
        # can reference it. The image goes into the bundle dir alongside
        # `index.md`; the build's image pipeline picks it up at render
        # time without any extra config.
        downloader = Support::ImageDownloader.new(bundle_dir: bundle_dir,
                                                   logger: @opts.dry_run ? nil : @logger)

        feature_image = nil
        if post.feature_image_url && @opts.download_images && !@opts.dry_run
          feature_image = downloader.fetch(post.feature_image_url)
          warnings.concat(downloader.warnings)
          downloader.warnings.clear
        end

        # Body: convert HTML → MD, then rewrite remote image URLs to
        # local filenames. Order matters — we convert first so reverse_markdown
        # gets to see the raw HTML structure, then run a regex sweep
        # over the resulting markdown to swap URLs out. (Trying to
        # rewrite URLs in HTML pre-conversion is messier — relative
        # path resolution, attribute escaping, etc.)
        body_md = Support::HtmlToMarkdown.convert(
          post.body_html.to_s,
          strip_selectors: combined_strip_selectors
        )

        if @opts.download_images && !@opts.dry_run
          body_md = rewrite_image_urls(body_md, downloader)
          warnings.concat(downloader.warnings)
        end

        frontmatter = build_frontmatter(post, feature_image: feature_image)
        content     = format_yaml(frontmatter) + "\n" + body_md

        unless @opts.dry_run
          FileUtils.mkdir_p(bundle_dir) unless @opts.flat
          File.write(index_path, content)
        end

        @report.add(slug: slug, title: title, status: :imported,
                    reason: rel(index_path), warnings: warnings)
      rescue StandardError => e
        @report.add(slug: slug || '(unknown)', title: title || '(unknown)',
                    status: :failed,
                    reason: "#{e.class}: #{e.message}")
        @logger.call("  ✗ #{slug}: #{e.class}: #{e.message}")
      end

      def resolve_slug(post)
        base = Support::SlugNormalizer.normalize(post.slug.to_s)
        base = Support::SlugNormalizer.normalize(post.title.to_s) if base.empty?
        Support::SlugNormalizer.resolve(base, @taken_slugs)
      end

      def bundle_dir_for(slug, date)
        prefix = date ? "#{date.strftime('%Y-%m-%d')}-" : ''
        File.join(@opts.site_root, 'content', @opts.collection, "#{prefix}#{slug}")
      end

      def index_path_for(bundle_dir, slug)
        if @opts.flat
          # Flat layout: content/<collection>/<bundle-dir-basename>.md
          base = File.basename(bundle_dir)
          File.join(@opts.site_root, 'content', @opts.collection, "#{base}.md")
        else
          File.join(bundle_dir, 'index.md')
        end
      end

      def build_frontmatter(post, feature_image:)
        fm = {
          'title'     => post.title.to_s.strip,
          'published' => true,
          'date'      => (post.date&.strftime('%Y-%m-%d'))
        }
        fm['description'] = post.description.to_s if post.description && !post.description.to_s.empty?
        fm['tags']        = Array(post.tags).compact.uniq if Array(post.tags).any?
        fm['image']       = feature_image if feature_image
        if post.source_url && @opts.write_canonical
          fm['canonical_url'] = post.source_url
        end
        if post.source_slug && !post.source_slug.to_s.empty?
          fm['redirect_from'] = redirects_for(post.source_slug)
        end
        (post.extra_frontmatter || {}).each { |k, v| fm[k.to_s] ||= v }
        fm.compact
      end

      # Per-importer override. Defaults to nothing — Substack adds
      # `/p/<slug>/`, Ghost adds `/<slug>/`, etc.
      def redirects_for(_source_slug)
        nil
      end

      # Combine per-importer + caller-supplied strip selectors. The
      # importer knows about platform chrome; the caller can add
      # site-specific patterns via `--strip-selectors`.
      def combined_strip_selectors
        Array(self.class.strip_selectors) + Array(@opts.strip_selectors)
      end

      # Subclasses override this to declare platform-chrome selectors
      # that the base writer should pre-strip from every body before
      # markdown conversion.
      def self.strip_selectors
        []
      end

      # Find `![alt](http(s)://…)` references in the markdown and
      # swap each URL out for the locally-downloaded filename. Also
      # handles the bare-URL `<https://…>` pattern reverse_markdown
      # occasionally emits for images inside `<picture>` elements.
      IMG_MD_RE = /!\[([^\]]*)\]\((https?:[^)\s]+)(?:\s+"[^"]*")?\)/.freeze
      def rewrite_image_urls(markdown, downloader)
        markdown.gsub(IMG_MD_RE) do
          alt = Regexp.last_match(1)
          url = Regexp.last_match(2)
          local = downloader.fetch(url)
          local ? "![#{alt}](#{local})" : Regexp.last_match(0)
        end
      end

      # YAML front matter the engine accepts. We hand-render rather
      # than `YAML.dump`-ing the whole hash because Psych's default
      # output puts every value on its own line and quotes things we
      # don't need quoted, which makes the resulting files look unlike
      # everything else in the repo. The post-author convention is:
      #   title: Plain text
      #   tags: [a, b, c]
      def format_yaml(fm)
        lines = ['---']
        fm.each do |k, v|
          lines << format_kv(k, v)
        end
        lines << '---'
        lines.join("\n")
      end

      def format_kv(key, value)
        case value
        when nil          then "#{key}:"
        when true, false  then "#{key}: #{value}"
        when Date         then "#{key}: #{value.strftime('%Y-%m-%d')}"
        when Time         then "#{key}: #{value.utc.iso8601}"
        when Array
          if value.empty?
            "#{key}: []"
          else
            # Inline flow-style for short scalars; block style for long.
            inline = "#{key}: [#{value.map { |v| yaml_inline(v) }.join(', ')}]"
            inline.length <= 100 ? inline : block_array(key, value)
          end
        when Hash         then block_hash(key, value)
        else                   "#{key}: #{yaml_scalar(value.to_s)}"
        end
      end

      def yaml_inline(value)
        case value
        when nil          then '~'
        when Numeric      then value.to_s
        when true, false  then value.to_s
        else                   yaml_scalar(value.to_s)
        end
      end

      # Quote a string only when YAML would otherwise misinterpret it.
      # We're conservative — anything with a colon-space, leading
      # special characters, or surrounding whitespace gets quoted.
      def yaml_scalar(str)
        return '""' if str.empty?

        # Control characters — newlines above all — are handled FIRST and
        # separately, because they can't be fixed by wrapping in quotes:
        # a literal newline inside a double-quoted scalar still ends the
        # line. An imported title of "Hello\npermalink: /x" would have
        # been written straight through, turning one mapping entry into
        # two. Importer input is a third-party export, so this is
        # attacker-shaped. Escape them into their YAML forms instead.
        if str.match?(/[\x00-\x1F\x7F]/)
          return %("#{escape_yaml_double_quoted(str)}")
        end

        if str.match?(/[:#&*\[\]{}|>!%@`]|\A[\s"'-]|[\s"']\z|\A(true|false|yes|no|null|~)\z/i) ||
           str.include?(': ')
          %("#{escape_yaml_double_quoted(str)}")
        else
          str
        end
      end

      # Escape a string for a YAML double-quoted scalar: backslashes and
      # quotes, then the control characters that have named escapes,
      # then anything else remaining as \uXXXX.
      def escape_yaml_double_quoted(str)
        str
          .gsub('\\', '\\\\\\\\')
          .gsub('"', '\\"')
          .gsub("\n", '\\n')
          .gsub("\r", '\\r')
          .gsub("\t", '\\t')
          .gsub(/[\x00-\x1F\x7F]/) { |c| format('\\u%04X', c.ord) }
      end

      def block_array(key, items)
        out = ["#{key}:"]
        items.each { |v| out << "  - #{yaml_inline(v)}" }
        out.join("\n")
      end

      def block_hash(key, hash)
        out = ["#{key}:"]
        hash.each do |k, v|
          out << "  #{k}: #{yaml_inline(v)}"
        end
        out.join("\n")
      end

      def rel(path)
        rooted = path.sub(/\A#{Regexp.escape(@opts.site_root)}\/?/, '')
        rooted.empty? ? path : rooted
      end

      # Write the run's report to the site root.
      #
      # `_import_report.md` is overwritten each run, deliberately: it
      # describes the LAST import, and the skeleton's `.gitignore`
      # already excludes it. Say so when replacing an existing one so a
      # second import doesn't quietly discard the first report someone
      # was still reading.
      def finalise
        return if @opts.dry_run

        report_path = File.join(@opts.site_root, '_import_report.md')
        existed = File.exist?(report_path)
        File.write(report_path, @report.to_markdown)

        note = existed ? ' (replaced the previous one)' : ''
        @logger.call("\nReport: ./#{File.basename(report_path)}#{note}")
      end
    end
  end
end

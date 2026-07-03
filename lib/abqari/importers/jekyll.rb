# frozen_string_literal: true

require 'yaml'
require 'fileutils'

module Abqari
  module Importers
    # Jekyll site importer.
    #
    # Reads `_posts/YYYY-MM-DD-slug.md(.markdown|.html)` files. Each
    # file is already markdown + YAML frontmatter — the importer's
    # job is mostly translation:
    #
    #   * Move from Jekyll's flat `_posts/` to Abqari's bundle
    #     layout (`content/posts/<slug>/index.md` + colocated
    #     assets).
    #   * Map `categories:` → `tags:` (Jekyll has both; Abqari
    #     just uses tags).
    #   * Copy referenced images from `assets/posts/` (or
    #     wherever they live) alongside the new bundle.
    #   * Warn on Liquid template tags (`{% include %}`,
    #     `{% post_url %}`, `{% raw %}`) — those need manual
    #     attention.
    #
    # `.html` posts (Jekyll allows raw HTML) are converted via
    # `HtmlToMarkdown` like any other importer source. Pure-markdown
    # posts are passed through unchanged.
    class Jekyll < Base
      LIQUID_TAG_RE = /\{%\s*(?!comment|endcomment|raw|endraw)\w+/.freeze

      def self.strip_selectors
        [] # Jekyll authors control their own HTML; no platform chrome
      end

      def each_post
        posts_dir = File.join(@source, '_posts')
        raise "Jekyll source missing _posts/ at #{posts_dir}" unless File.directory?(posts_dir)

        Dir.glob(File.join(posts_dir, '*')).sort.each do |path|
          next unless File.file?(path)
          ext = File.extname(path).downcase
          next unless %w[.md .markdown .html].include?(ext)

          parsed = parse(path)
          next unless parsed

          fm   = parsed[:frontmatter]
          body = parsed[:body]

          # Convert body if the source is HTML; otherwise keep it
          # as markdown.
          if ext == '.html'
            body_html = body
          else
            # Wrap markdown in a single root so the base class's
            # HtmlToMarkdown pass doesn't try to parse it — we
            # pass the raw markdown through via `body_html` that
            # IS already markdown, which is harmless because the
            # base class re-runs HtmlToMarkdown over it. The
            # safer path: bypass conversion entirely for .md files.
            body_html = nil
          end

          yield Base::ImportedPost.new(
            title:             fm['title'] || derive_title_from_path(path),
            slug:              fm['slug'] || derive_slug_from_path(path),
            date:              fm['date'].is_a?(Date) ? fm['date'] : parse_date(fm['date']) || file_date(path),
            body_html:         body_html,
            tags:              merge_taxonomies(fm),
            description:       fm['description'] || fm['excerpt'],
            feature_image_url: nil, # local-only in Jekyll; handled via raw_body below
            source_url:        nil,
            source_slug:       File.basename(path, '.*').sub(/\A\d{4}-\d{2}-\d{2}-/, ''),
            extra_frontmatter: jekyll_extras(fm).merge('__raw_body' => body, '__source_path' => path)
          )
        end
      end

      # The base class's writer expects `body_html` to be HTML it
      # can convert. For pure-markdown Jekyll posts, we want to
      # skip conversion and write the body straight through. This
      # hook lets the importer override the body-write step on a
      # per-post basis without forking the base writer.
      #
      # The base writer doesn't currently call this — instead, we
      # use `extra_frontmatter['__raw_body']` as a sentinel that
      # the base writer ignores (it doesn't know about the key)
      # and then post-process in the importer's `run!` override.
      #
      # Cleaner: extend Base::Options with a `body_passthrough`
      # block. Future refactor.
      def run!
        @raw_bodies = {} # slug → raw markdown body, populated during each_post
        each_post do |post|
          if post.extra_frontmatter['__raw_body']
            @raw_bodies[post.slug] = post.extra_frontmatter['__raw_body']
            # Strip internal keys before they hit the writer.
            post.extra_frontmatter.delete('__raw_body')
            source_path = post.extra_frontmatter.delete('__source_path')
            post.extra_frontmatter['_source_file'] = File.basename(source_path) if source_path
          end
          process(post)
        end
        finalise
        @report
      end

      private

      # Override the base class's body conversion when we already
      # have markdown. Jekyll-specific behaviour, isolated here.
      def process(post)
        raw_md = @raw_bodies && @raw_bodies[post.slug]
        if raw_md
          process_markdown_post(post, raw_md)
        else
          super
        end
      end

      def process_markdown_post(post, raw_md)
        slug  = resolve_slug(post)
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

        if raw_md =~ LIQUID_TAG_RE
          warnings << "Liquid template tag detected — needs manual conversion to ERB or removal"
        end

        # Copy colocated assets from the source post bundle (if it's
        # already a Jekyll bundle layout) or from the conventional
        # `assets/<slug>/` directory.
        copy_colocated_assets(post, bundle_dir, warnings) unless @opts.dry_run

        frontmatter = build_frontmatter(post, feature_image: nil)
        content     = format_yaml(frontmatter) + "\n" + raw_md.sub(/\n*\z/, "\n")

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

      def copy_colocated_assets(post, bundle_dir, warnings)
        # Look in two conventional spots for image assets:
        #   1. assets/posts/<source_slug>/
        #   2. assets/<source_slug>/
        # Both patterns are common in Jekyll's wild.
        source_slug = post.source_slug.to_s
        return if source_slug.empty?

        candidates = [
          File.join(@source, 'assets', 'posts', source_slug),
          File.join(@source, 'assets', source_slug)
        ]
        src = candidates.find { |c| File.directory?(c) }
        return unless src

        FileUtils.mkdir_p(bundle_dir)
        Dir.glob(File.join(src, '*')).each do |file|
          next unless File.file?(file)
          FileUtils.cp(file, File.join(bundle_dir, File.basename(file)))
        end
      end

      def parse(path)
        raw = File.read(path, encoding: 'UTF-8')
        if (m = raw.match(Abqari::FRONTMATTER_RE))
          fm = YAML.safe_load(m[1], permitted_classes: Abqari::YAML_PERMITTED_CLASSES, aliases: true) || {}
          { frontmatter: fm, body: m[2] }
        else
          { frontmatter: {}, body: raw }
        end
      rescue Psych::Exception => e
        @report.add(slug: File.basename(path, '.*'), title: File.basename(path), status: :failed,
                    reason: "YAML error: #{e.message}")
        nil
      end

      def merge_taxonomies(fm)
        tags       = Array(fm['tags'])
        categories = Array(fm['categories'] || fm['category'])
        (tags + categories).map { |t| t.to_s.strip }.reject(&:empty?).uniq
      end

      def derive_title_from_path(path)
        base = File.basename(path, '.*').sub(/\A\d{4}-\d{2}-\d{2}-/, '')
        base.tr('-', ' ').capitalize
      end

      def derive_slug_from_path(path)
        File.basename(path, '.*').sub(/\A\d{4}-\d{2}-\d{2}-/, '')
      end

      def file_date(path)
        m = File.basename(path).match(/\A(\d{4})-(\d{2})-(\d{2})-/)
        return nil unless m
        Date.new(m[1].to_i, m[2].to_i, m[3].to_i)
      rescue ArgumentError
        nil
      end

      def parse_date(value)
        return nil if value.to_s.empty?
        return value if value.is_a?(Date)
        Date.parse(value.to_s)
      rescue ArgumentError
        nil
      end

      # Layout names imported from an untrusted export are resolved to a
      # file path and ERB-eval'd at build time, so a traversing value is
      # a code-execution vector. Only carry through flat/nested layout
      # identifiers; anything with `.`, `\`, a leading `/`, or other
      # oddities is dropped so the imported post falls back to the
      # collection default.
      SAFE_LAYOUT = %r{\A[A-Za-z0-9][A-Za-z0-9_\-/]*\z}.freeze

      def jekyll_extras(fm)
        # Preserve frontmatter keys Abqari understands. Anything else
        # is dropped silently — Jekyll's frontmatter is wildly diverse
        # and we don't want to inherit unknowns into the new site's
        # schema.
        keep = %w[layout permalink redirect_from author authors series share_image]
        extras = fm.slice(*keep).reject { |_, v| v.nil? || v == '' }
        extras.delete('layout') if extras['layout'] && !extras['layout'].to_s.match?(SAFE_LAYOUT)
        extras
      end

      def redirects_for(_source_slug)
        nil # Jekyll posts usually keep the same slug; nothing to forward
      end
    end
  end
end

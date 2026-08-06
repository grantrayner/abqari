# frozen_string_literal: true

require 'fileutils'

module Abqari
  class TaxonomyPage
    DEFAULT_PERMALINK = '/:taxonomy/:slug/'
    DEFAULT_LAYOUT = 'taxonomy'

    attr_reader :taxonomy, :term, :posts, :site

    def initialize(taxonomy, term, posts, site)
      @taxonomy = taxonomy
      @term = term
      @posts = posts
      @site = site
      @config = site.taxonomy_config(taxonomy)
    end

    def title
      # Series taxonomies (configured with `field: series`) get a
      # cleaner h1 / <title> — just the series name, e.g. "Damascus
      # 2026" rather than "Posts tagged 'Damascus 2026'". Other
      # taxonomies (tags, countries, etc.) keep the historical
      # "tagged" framing.
      return term.to_s if @config['field'] == 'series'

      "Posts tagged ‘#{term}’"
    end

    def description
      return "#{posts.size} item#{'s' if posts.size != 1} in this series." if @config['field'] == 'series'

      "All posts tagged #{term}."
    end

    def content
      ''
    end

    def frontmatter
      {}
    end

    def url
      permalink = @config['permalink'] || DEFAULT_PERMALINK
      '/' + permalink
        .gsub(':taxonomy', taxonomy)
        .gsub(':slug', term_slug)
        .sub(%r{\A/}, '')
        .sub(%r{/?\z}, '/')
    end

    # The term's URL segment, refusing to be empty.
    #
    # `slugify` strips to URL-safe ASCII, so a term with no Latin
    # characters — a CJK or Arabic tag — produces "". That collapsed
    # `/tags/:slug/` to `/tags/`, and the page then wrote over the
    # taxonomy index at `_site/tags/index.html`. With two such terms the
    # build did fail, via `detect_output_collisions!`, but the message
    # named colliding paths rather than the tag that caused them.
    #
    # `Page#render_permalink` has had this guard for page slugs; this is
    # the same failure one level up, so it fails the same way and names
    # the term.
    def term_slug
      slug = Helpers.slugify(term)
      return slug unless slug.empty?

      # The term is interpolated raw rather than via `inspect`: when the
      # process's default encoding isn't UTF-8, `inspect` renders it as
      # `日本語`, and a user staring at escape sequences
      # can't tell which of their tags is at fault.
      raise PathSafe::Error,
            %(the #{taxonomy} term "#{term}" produced an empty slug — it has no ) +
            'URL-safe characters, so its page would overwrite the taxonomy index. ' \
            'Rename the term, or add a Latin-character alias.'
    end

    def output_path
      File.join(@site.output_dir, url.sub(%r{\A/}, '').chomp('/'), 'index.html')
    end

    # Reflect the latest update across the posts this taxonomy collects.
    def lastmod
      posts.map(&:lastmod).compact.max
    end

    # Bundle images aren't sitemap-relevant for tag pages — they live on the posts.
    def bundle_images
      []
    end

    # Incremental rendering — re-render when shared deps change or any post
    # in this taxonomy was modified more recently than this page's output.
    # The layout this page renders through. Shared by `render` and
    # `needs_render?` so the staleness check can't drift from what's
    # actually rendered.
    def layout_name
      @config['layout'] || DEFAULT_LAYOUT
    end

    def needs_render?
      return true unless File.exist?(output_path)

      output_mtime = File.mtime(output_path)
      return true if @site.shared_deps_mtime > output_mtime
      # Layouts are deliberately excluded from GLOBAL_DEP_GLOBS and
      # tracked per-page instead (see Renderer::GLOBAL_DEP_GLOBS). Only
      # Page consulted them, so editing `taxonomy.html.erb` with the dev
      # server running rebuilt nothing and the browser reloaded to stale
      # HTML.
      return true if @site.layout_deps_mtime(layout_name) > output_mtime

      posts.any? { |post| (post.lastmod || Time.now) > output_mtime }
    end

    def write
      FileUtils.mkdir_p(File.dirname(output_path))
      File.write(output_path, @site.post_process(render, page: self))
    end

    private

    def render
      RenderContext.new(self, @site).render_layout(layout_name)
    end
  end
end

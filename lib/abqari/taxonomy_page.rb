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
        .gsub(':slug', Helpers.slugify(term))
        .sub(%r{\A/}, '')
        .sub(%r{/?\z}, '/')
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
    def needs_render?
      return true unless File.exist?(output_path)

      output_mtime = File.mtime(output_path)
      return true if @site.shared_deps_mtime > output_mtime

      posts.any? { |post| (post.lastmod || Time.now) > output_mtime }
    end

    def write
      FileUtils.mkdir_p(File.dirname(output_path))
      File.write(output_path, @site.post_process(render, page: self))
    end

    private

    def render
      layout = @config['layout'] || DEFAULT_LAYOUT
      RenderContext.new(self, @site).render_layout(layout)
    end
  end
end

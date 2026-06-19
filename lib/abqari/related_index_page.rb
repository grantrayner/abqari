# frozen_string_literal: true

require 'fileutils'

module Abqari
  # Auto-generated index page that lists ALL related items for a source
  # page, used when there are more matches than fit in the show-view's
  # `related.limit` block. URL is `/<source url>related/`, e.g.
  # `/posts/writing-in-markdown/related/`.
  #
  # Generated only when `total_related > limit` — pages with zero or
  # few related items don't get an index page (the show-view block
  # already shows everything). Site#generate_related_pages handles the
  # decision and creation.
  class RelatedIndexPage
    attr_reader :site, :source_page, :related_items

    def initialize(source_page, site, related_items)
      @source_page = source_page
      @site = site
      @related_items = related_items
    end

    def title
      "Related to #{@source_page.title}"
    end

    def description
      "All items related to '#{@source_page.title}' — ranked by tag, series, and category overlap."
    end

    def content
      ''
    end

    def frontmatter
      {}
    end

    def tags
      []
    end

    def url
      "#{@source_page.url.chomp('/')}/related/"
    end

    def output_path
      File.join(@site.output_dir, url.sub(%r{\A/}, '').chomp('/'), 'index.html')
    end

    def lastmod
      @related_items.map(&:lastmod).compact.max || @source_page.lastmod
    end

    def bundle_images
      []
    end

    # Re-render when shared deps change or when the source page or any
    # related item has been touched. Conservatively: always re-render
    # when shared deps change — the related list could shift if any
    # post in the collection changed its tags/series.
    def needs_render?
      true
    end

    def write
      FileUtils.mkdir_p(File.dirname(output_path))
      File.write(output_path, @site.post_process(render, page: self))
    end

    private

    def render
      RenderContext.new(self, @site).render_layout('related_index')
    end
  end
end

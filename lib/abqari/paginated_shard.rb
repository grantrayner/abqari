# frozen_string_literal: true

require 'fileutils'

module Abqari
  class PaginatedShard
    attr_reader :paginator, :site

    def initialize(source_page, paginator)
      @source = source_page
      @paginator = paginator
      @site = source_page.site
    end

    def title
      "#{@source.title} · Page #{@paginator.page}"
    end

    def description
      @source.description
    end

    def content
      @source.content
    end

    def frontmatter
      @source.frontmatter
    end

    def tags
      []
    end

    def post?
      false
    end

    def date
      nil
    end

    def url
      "#{absolute_base}page/#{@paginator.page}/"
    end

    def output_path
      File.join(@site.output_dir, relative_base, 'page', @paginator.page.to_s, 'index.html')
    end

    # Reflect the latest update across the posts this page lists.
    def lastmod
      @paginator.posts.map(&:lastmod).compact.max
    end

    def bundle_images
      []
    end

    # Incremental rendering — re-render when shared deps change or any post
    # on this shard was modified more recently than the output.
    def needs_render?
      return true unless File.exist?(output_path)

      output_mtime = File.mtime(output_path)
      return true if @site.shared_deps_mtime > output_mtime

      @paginator.posts.any? { |post| (post.lastmod || Time.now) > output_mtime }
    end

    def write
      FileUtils.mkdir_p(File.dirname(output_path))
      File.write(output_path, @site.post_process(render, page: self))
    end

    private

    def absolute_base
      @source.url.sub(%r{/?\z}, '/')
    end

    def relative_base
      @source.url.sub(%r{\A/}, '').sub(%r{/?\z}, '/')
    end

    def render
      # Mirror the source page's layout resolution — `layout_name` falls
      # back to the collection's default layout before `application`, so
      # a paginating page inside a collection renders pages 2+ with the
      # same layout as page 1 (previously they diverged to `application`).
      layout = @source.respond_to?(:layout_name) ? @source.layout_name : (@source.frontmatter['layout'] || 'application')
      RenderContext.new(self, @site).render_layout(layout)
    end
  end
end

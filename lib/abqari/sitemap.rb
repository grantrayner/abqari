# frozen_string_literal: true

require 'cgi'

module Abqari
  class Sitemap
    XMLNS = 'http://www.sitemaps.org/schemas/sitemap/0.9'
    XMLNS_IMAGE = 'http://www.google.com/schemas/sitemap-image/1.1'

    def initialize(site)
      @site = site
    end

    def write
      base = @site.config['url']
      return unless base

      File.write(File.join(@site.output_dir, 'sitemap.xml'), build(base))
    end

    private

    def build(base)
      base = base.sub(%r{/\z}, '')
      urls = @site.all_pages.map { |page| url_entry(base, page) }.compact

      <<~XML
        <?xml version="1.0" encoding="UTF-8"?>
        <urlset xmlns="#{XMLNS}" xmlns:image="#{XMLNS_IMAGE}">
        #{urls.join("\n")}
        </urlset>
      XML
    end

    def url_entry(base, page)
      return nil if skip?(page)

      lines = ['  <url>', "    <loc>#{xml_escape("#{base}#{page.url}")}</loc>"]

      lastmod = format_lastmod(page)
      lines << "    <lastmod>#{lastmod}</lastmod>" if lastmod

      images_for(page).each do |image_url_path|
        # `Page#bundle_images` returns URL paths (not filesystem
        # paths) consistently — bundle assets are converted via
        # `page.url + basename`, frontmatter absolute paths pass
        # through as-is, externals are filtered out. So we just
        # prepend the site base.
        lines << '    <image:image>'
        lines << "      <image:loc>#{xml_escape("#{base}#{image_url_path}")}</image:loc>"
        lines << '    </image:image>'
      end

      lines << '  </url>'
      lines.join("\n")
    end

    def skip?(page)
      return true unless page.url
      return false unless page.respond_to?(:frontmatter)
      return true if page.frontmatter['sitemap'] == false
      # A page that tells crawlers `noindex` shouldn't also be advertised
      # in the sitemap — the two signals contradict each other and
      # Search Console flags it.
      return true if page.frontmatter['robots'].to_s.include?('noindex')

      false
    end

    def format_lastmod(page)
      stamp = page.respond_to?(:lastmod) ? page.lastmod : nil
      stamp&.strftime('%Y-%m-%d')
    end

    def images_for(page)
      page.respond_to?(:bundle_images) ? page.bundle_images : []
    end

    # Page URLs are constrained by `PERMALINK_ALLOWED` to URL-safe
    # ASCII, so the practical risk is the `base` URL or a frontmatter
    # image path carrying `&`/`<`/`>`. Escape every interpolation so
    # one stray ampersand can't poison the whole feed.
    def xml_escape(text)
      CGI.escapeHTML(text.to_s)
    end
  end
end

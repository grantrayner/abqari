# frozen_string_literal: true

require 'fileutils'

module Abqari
  class Redirects
    def initialize(site)
      @site = site
    end

    def write
      mappings = collect
      return if mappings.empty?

      mappings.each { |from, to| write_stub(from, to) }
      write_redirects_file(mappings)
    end

    private

    def collect
      result = {}
      @site.all_pages.each do |page|
        next unless page.respond_to?(:frontmatter)

        Array(page.frontmatter['redirect_from']).each do |from|
          result[normalise(from)] = page.url
        end
      end
      result
    end

    def normalise(path)
      path = "/#{path}" unless path.start_with?('/')
      path = "#{path}/" unless path.end_with?('/') || File.extname(path).length.positive?
      path
    end

    def write_stub(from, to)
      relative = from.sub(%r{\A/}, '').sub(%r{/\z}, '')
      dest = File.join(@site.output_dir, relative, 'index.html')
      FileUtils.mkdir_p(File.dirname(dest))

      base = @site.config['url']&.sub(%r{/\z}, '')
      canonical = base ? "#{base}#{to}" : to

      File.write(dest, <<~HTML)
        <!DOCTYPE html>
        <html lang="en">
        <head>
          <meta charset="UTF-8">
          <meta http-equiv="refresh" content="0; url=#{to}">
          <link rel="canonical" href="#{canonical}">
          <title>Redirecting…</title>
        </head>
        <body>
          <p>This page has moved to <a href="#{to}">#{to}</a>.</p>
        </body>
        </html>
      HTML
    end

    def write_redirects_file(mappings)
      lines = mappings.map { |from, to| "#{from} #{to} 301" }
      File.write(File.join(@site.output_dir, '_redirects'), "#{lines.join("\n")}\n")
    end
  end
end

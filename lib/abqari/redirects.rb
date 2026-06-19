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

    # `from` is user input (frontmatter `redirect_from:`). Route through
    # PathSafe so a hostile or accidental `redirect_from: ../../etc`
    # can't write the stub outside `_site/`. Same invariant as
    # Page#output_path — every user-input → filesystem path goes
    # through `PathSafe.join_under` (docs/security.md §2).
    def write_stub(from, to)
      relative = from.sub(%r{\A/}, '').sub(%r{/\z}, '')
      dest = PathSafe.join_under(@site.output_dir, relative, 'index.html')
      FileUtils.mkdir_p(File.dirname(dest))

      base = @site.config['url']&.sub(%r{/\z}, '')
      canonical = base ? "#{base}#{to}" : to

      # Escape every interpolation. `to` and `canonical` flow into HTML
      # attributes and text content; both author-controlled today, but
      # the redirect path is the only stub-emitter that didn't escape,
      # so close that gap for symmetry.
      to_attr        = Helpers.h(to)
      canonical_attr = Helpers.h(canonical)
      to_text        = Helpers.h(to)

      File.write(dest, <<~HTML)
        <!DOCTYPE html>
        <html lang="en">
        <head>
          <meta charset="UTF-8">
          <meta http-equiv="refresh" content="0; url=#{to_attr}">
          <link rel="canonical" href="#{canonical_attr}">
          <title>Redirecting…</title>
        </head>
        <body>
          <p>This page has moved to <a href="#{to_attr}">#{to_text}</a>.</p>
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

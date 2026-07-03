# frozen_string_literal: true

require 'fileutils'
require 'set'

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
      # URLs of every real page in the build. A `redirect_from:` that
      # collides with one of these would overwrite that page's
      # index.html with a meta-refresh stub (write_deploy_artifacts runs
      # AFTER render_pages) — silently deleting published content, or
      # creating a self-referential redirect loop when it matches the
      # page's own URL. Fail loudly instead.
      page_urls = @site.all_pages.map { |p| p.url if p.respond_to?(:url) }.compact.to_set

      result = {}
      @site.all_pages.each do |page|
        next unless page.respond_to?(:frontmatter)

        Array(page.frontmatter['redirect_from']).each do |from|
          # A `from` with whitespace (or control chars) corrupts the
          # space-delimited `_redirects` file — `/old page/ /new/ 301`
          # parses as four fields. Reject it at source with the offending
          # file named.
          if from.to_s.match?(/[[:space:][:cntrl:]]/)
            raise "redirect_from #{from.inspect} in #{describe(page)} contains whitespace/control " \
                  'characters, which would corrupt the _redirects file. Use a URL-safe path.'
          end

          key = normalise(from)

          if key == page.url
            raise "redirect_from #{from.inspect} in #{describe(page)} points at the page's own URL " \
                  "(#{page.url}) — this would create an infinite redirect loop"
          end
          if page_urls.include?(key)
            raise "redirect_from #{from.inspect} in #{describe(page)} collides with an existing page " \
                  "at #{key} — the redirect stub would overwrite that page. Choose a different source path."
          end
          if result.key?(key) && result[key] != page.url
            raise "redirect_from #{from.inspect} is declared twice with different targets " \
                  "(#{result[key]} and #{page.url}). Each source path may redirect to only one place."
          end

          result[key] = page.url
        end
      end
      result
    end

    # Best-effort human identifier for a page in an error message —
    # generated pages have no source_path, so fall back to the URL.
    def describe(page)
      if page.respond_to?(:source_path) && page.source_path
        page.source_path
      else
        page.url
      end
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
      # A `from` that carries a file extension (`/old-page.html`) is a
      # literal file path — write the stub AT that path, not at
      # `old-page.html/index.html` (which serves at `/old-page.html/`,
      # a different URL). Extension-less sources are pretty-URL
      # directories and get an index.html.
      dest = if File.extname(relative).empty?
               PathSafe.join_under(@site.output_dir, relative, 'index.html')
             else
               PathSafe.join_under(@site.output_dir, relative)
             end
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
          <meta name="robots" content="noindex">
          <title>Redirecting…</title>
        </head>
        <body data-pagefind-ignore>
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

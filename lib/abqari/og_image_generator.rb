# frozen_string_literal: true

require 'cgi'
require 'fileutils'

module Abqari
  # Auto-generated OG share images. When `og_images.auto: true` in
  # config/site.yml, the build emits a styled SVG card per content
  # page at `<page-url>og.svg` — so a post at `/posts/hello/` gets
  # `/posts/hello/og.svg`. The head template's share_image
  # resolution chain falls through to this URL when no explicit
  # `share_image:` or `image:` is set on the page.
  #
  # Output is SVG, not PNG. Modern social platforms (Facebook,
  # LinkedIn, Mastodon, Discord, Slack) render SVG og:image fine
  # in 2026; Twitter/X can be finicky, but its share cards have
  # been generally improving on this front. Users that need PNG
  # for max compatibility can convert via vips/magick — or supply
  # their own hero, which always takes precedence.
  #
  # Card layout:
  #   1200×630 (standard OG dimensions, ~1.91:1 aspect)
  #   theme-coloured gradient background (from config/site.yml's
  #     manifest.theme_color — falls back to a tasteful default)
  #   site title (small, top-left)
  #   page title (large, centred, wrapped at ~22 chars)
  #   author + date (small, bottom-left)
  #
  # Why SVG instead of pre-rendered PNG? Three reasons:
  #   - Zero external dependencies (vips/magick not required)
  #   - Tiny output (~1-2 KB per page vs. 30-80 KB PNG)
  #   - Themed via existing site colors — no separate design system
  class OgImageGenerator
    OG_WIDTH  = 1200
    OG_HEIGHT = 630

    # Approximate character widths at the chosen font size, used for
    # naive word-wrapping. Sans-serif at 72px renders ~22 chars per
    # line within the safe content area; lower for narrow lines.
    TITLE_CHARS_PER_LINE = 22
    TITLE_MAX_LINES      = 4

    def initialize(site)
      @site = site
    end

    def enabled?
      @site.config.dig('og_images', 'auto') == true
    end

    def write
      return unless enabled?

      eligible_pages.each do |page|
        next if skip?(page)
        svg = render_svg(page)
        write_file(page, svg)
      end
    end

    private

    def eligible_pages
      # All real Pages with URLs. Filters out generated pages
      # (FolioShowPage, PaginatedShard, RelatedIndexPage,
      # TaxonomyPage) — they don't carry their own titles in the
      # same way, and most of them shouldn't be SHARED directly
      # anyway. Pages can opt out with `og_image: false`.
      Array(@site.pages).select do |p|
        p.respond_to?(:url) && p.url && p.respond_to?(:title) && !p.title.to_s.empty?
      end
    end

    def skip?(page)
      fm = page.frontmatter rescue {}
      # Explicit opt-out OR explicit share_image set OR page hero set
      # (in which case the head template uses the hero, not the auto
      # image — no point generating one that won't be used).
      return true if fm['og_image'] == false
      return true if fm['share_image']
      return true if fm['image']
      # Only emit for pretty-URL pages (trailing slash). Flat-file
      # URLs like `/404.html`, `/sitemap.xml`, `/robots.txt` can't
      # have a sibling `og.svg` because their path isn't a directory.
      return true unless page.url.to_s.end_with?('/')
      false
    end

    def render_svg(page)
      title    = page.title.to_s
      site_t   = @site.config['title'].to_s
      author   = page.frontmatter['author'] || @site.config['author']
      date_str = if page.respond_to?(:date) && page.date
                   page.date.strftime('%-d %B %Y')
                 end
      meta_parts = [author, date_str].compact.reject(&:empty?)

      bg_a, bg_b = gradient_colors

      lines = wrap_title(title)
      title_y_start = title_block_y(lines.size)

      title_tspans = lines.each_with_index.map do |line, i|
        y = title_y_start + (i * 88)
        %(<text x="80" y="#{y}" fill="#ffffff" font-size="72" font-weight="700" letter-spacing="-2">#{escape(line)}</text>)
      end.join("\n  ")

      <<~SVG
        <?xml version="1.0" encoding="UTF-8"?>
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 #{OG_WIDTH} #{OG_HEIGHT}" width="#{OG_WIDTH}" height="#{OG_HEIGHT}" role="img" aria-label="#{escape(title)}">
          <defs>
            <linearGradient id="bg" x1="0" y1="0" x2="1" y2="1">
              <stop offset="0" stop-color="#{bg_a}"/>
              <stop offset="1" stop-color="#{bg_b}"/>
            </linearGradient>
          </defs>
          <rect width="#{OG_WIDTH}" height="#{OG_HEIGHT}" fill="url(#bg)"/>
          <text x="80" y="100" fill="#ffffff" font-size="28" font-weight="600" opacity="0.85" font-family="ui-sans-serif, system-ui, sans-serif">#{escape(site_t)}</text>
          <g font-family="ui-sans-serif, system-ui, sans-serif">
          #{title_tspans}
          </g>
          #{meta_block(meta_parts)}
        </svg>
      SVG
    end

    def meta_block(parts)
      return '' if parts.empty?
      %(<text x="80" y="#{OG_HEIGHT - 60}" fill="#ffffff" font-size="26" opacity="0.8" font-family="ui-sans-serif, system-ui, sans-serif">#{escape(parts.join('  ·  '))}</text>)
    end

    def title_block_y(line_count)
      # Centre the title block vertically in the lower-middle of the
      # card. Single line lands a touch above centre; multi-line
      # blocks grow downward from the same starting Y.
      base = OG_HEIGHT / 2 - (line_count - 1) * 44
      base.clamp(200, OG_HEIGHT - 200)
    end

    def wrap_title(text)
      words = text.split(/\s+/)
      lines = []
      current = []
      words.each do |w|
        candidate = (current + [w]).join(' ')
        if candidate.length > TITLE_CHARS_PER_LINE && !current.empty?
          lines << current.join(' ')
          current = [w]
        else
          current << w
        end
      end
      lines << current.join(' ') unless current.empty?
      lines = lines.first(TITLE_MAX_LINES)
      # If we truncated, append an ellipsis to the last line.
      lines[-1] = "#{lines[-1]}…" if text != lines.join(' ') && lines.any?
      lines
    end

    def gradient_colors
      # Source the gradient from the site's theme_color (manifest) so
      # auto-OG images feel on-brand. Generate a darker shade for the
      # gradient endpoint. Fallback to a tasteful neutral pair.
      raw = @site.config.dig('manifest', 'theme_color').to_s
      if raw.match?(/\A#[0-9a-fA-F]{6}\z/)
        [raw, darken(raw, 0.35)]
      else
        %w[#1f2937 #0f172a]  # slate-800 → slate-900
      end
    end

    def darken(hex, factor)
      r = hex[1, 2].to_i(16)
      g = hex[3, 2].to_i(16)
      b = hex[5, 2].to_i(16)
      r = (r * (1 - factor)).round.clamp(0, 255)
      g = (g * (1 - factor)).round.clamp(0, 255)
      b = (b * (1 - factor)).round.clamp(0, 255)
      format('#%02x%02x%02x', r, g, b)
    end

    def escape(s)
      CGI.escapeHTML(s.to_s)
    end

    def write_file(page, svg)
      # Page URL is something like `/posts/hello-from-the-blog/`.
      # Map to a directory under output_dir and write `og.svg`.
      #
      # Routed through PathSafe so a hostile `page.url` (it ultimately
      # derives from frontmatter `permalink:`) can't write outside
      # output_dir. PathSafe.join_under raises if it would.
      dir_part   = page.url.sub(%r{\A/}, '').sub(%r{/\z}, '')
      target_dir = PathSafe.join_under(@site.output_dir, dir_part)
      target     = PathSafe.join_under(target_dir, 'og.svg')
      FileUtils.mkdir_p(target_dir)
      File.write(target, svg)
    end
  end
end

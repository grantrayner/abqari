# frozen_string_literal: true

require 'cgi'
require 'date'
require 'json'
require 'time'
require 'uri'

module Abqari
  module Helpers
    extend self

    # HTML-escape a value for safe interpolation in markup. Abqari uses
    # plain `ERB.new` (no auto-escaping), so any value that originates
    # outside the author's own frontmatter — Folio publications, fetched
    # data, anything user-submitted — should pass through `h()` before
    # rendering. Author-controlled frontmatter follows Jekyll/Hugo
    # convention (trusted), but applying `h()` defensively never hurts.
    def h(text)
      CGI.escapeHTML(text.to_s)
    end

# JSON serialiser for values that will be interpolated raw into a
# `<script>` block — JSON-LD, embedded config, etc. Plain
# `JSON.generate` does NOT escape `<`, `>`, `&`, or the line /
# paragraph separators U+2028/U+2029, any of which let a hostile
# string break out of the script tag — a Folio response with
# `"title": "x</script><script>alert(1)</script>"` ships as working
# HTML otherwise. Folio data is bounded-trust per docs/security.md
# §1; this helper closes the gap.
#
# Strategy: replace HTML- and JS-significant characters with their
# JSON `\uXXXX` escape sequences. The output is still valid JSON
# (round-trips through `JSON.parse`), but contains no literal `<`,
# `>`, or `&`, so the host HTML parser sees it as inert text right
# up to the closing `</script>` we emit ourselves.
#
# Always use `<%== script_safe_json(value) %>` inside a `<script>`
# block. Outside `<script>`, prefer `h(value.to_json)`.
SCRIPT_JSON_ESCAPE = {
  '<'                    => '\u003c',
  '>'                    => '\u003e',
  '&'                    => '\u0026',
  " "               => '\u2028',
  " "               => '\u2029'
}.freeze
SCRIPT_JSON_RE = /[<>&  ]/.freeze

def script_safe_json(value)
  JSON.generate(value).gsub(SCRIPT_JSON_RE, SCRIPT_JSON_ESCAPE)
end

    # Validate a URL for use in href / src attributes. Returns the
    # HTML-escaped URL when it's a same-origin path or an http(s) URL;
    # returns nil otherwise. Blocks `javascript:`, `data:` (HTML),
    # `vbscript:` and other scheme-based XSS vectors. Use whenever a
    # URL comes from outside author-controlled content (Folio buy_url,
    # fetched data, etc.).
    #
    # Protocol-relative URLs (`//evil.com/x`) are rejected. Browsers
    # treat them as `<current-scheme>://evil.com/x`, so they're a
    # cross-origin redirect vector disguised as a same-origin path.
    # Same-origin paths must start with a single `/` followed by a
    # non-`/` character (or be a lone `/`).
    def sanitized_url(url)
      return nil if url.nil?

      s = url.to_s.strip
      return nil if s.empty?
      return nil if s.start_with?('//')
      return h(s) if s.start_with?('/', '#')

      begin
        uri = URI.parse(s)
      rescue URI::InvalidURIError
        return nil
      end

      return nil unless uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS) || uri.is_a?(URI::MailTo)
      return nil if uri.is_a?(URI::HTTP) && uri.host.to_s.empty?

      h(uri.to_s)
    end

    # Truncate `text` so the visible result (kept content + omission)
    # is at most `length` characters. When `omission` is longer than
    # `length` the budget for content is zero — falling back to a
    # negative slice would silently return the LAST N chars of the
    # text (Ruby's `String#[]` with a negative second arg returns nil
    # or the trailing window). Clamp the slice width to 0 so the
    # caller gets just the omission, not a surprise suffix.
    def truncate(text, length: 100, omission: '…')
      return '' if text.nil?

      text = text.to_s
      return text if text.length <= length

      slice_width = [length - omission.length, 0].max
      text[0, slice_width].rstrip + omission
    end

    def pluralize(count, singular, plural: nil)
      word = count.to_i == 1 ? singular : (plural || "#{singular}s")
      "#{count} #{word}"
    end

    # Count words in a string — naive whitespace split. Used for
    # JSON-LD `wordCount` and any UI that surfaces word counts. The
    # `reading_time` helper has its own (more punctuation-aware)
    # tokenizer; this one keeps `wordCount` honest as a rough integer.
    def word_count(text)
      text.to_s.scan(/\S+/).length
    end

    # Format a date or time. Default format is "1 January 2026"
    # (day month-name year, no comma). Callers can override with any
    # strftime format string — e.g. `format: '%Y'` for year-only.
    def local_time(time, format: '%-d %B %Y')
      to_time(time).strftime(format)
    end

    # Whole years between the given year (or date) and today. Useful in
    # about pages — "with over <%= years_since(2002) %> years of experience"
    # — so the number doesn't go stale every January.
    #
    # Accepts an integer year or any value `to_time` understands.
    def years_since(year_or_date, today: Date.today)
      from = year_or_date.is_a?(Integer) ? Date.new(year_or_date, 1, 1) : to_time(year_or_date).to_date
      diff = today.year - from.year
      diff -= 1 if today.month < from.month || (today.month == from.month && today.day < from.day)
      [diff, 0].max
    end

    def time_ago(time)
      seconds = (Time.now - to_time(time)).to_i

      case seconds
      when 0..59             then 'just now'
      when 60..3599          then "#{pluralize(seconds / 60,     'minute')} ago"
      when 3600..86_399      then "#{pluralize(seconds / 3600,   'hour')} ago"
      when 86_400..2_591_999 then "#{pluralize(seconds / 86_400, 'day')} ago"
      else local_time(time)
      end
    end

    # Inverse of time_ago. "in 3 hours", "in 2 weeks", "in 4 months". Used
    # by the scheduled-post banner so the author sees how far away a future
    # date actually is.
    def time_until(time)
      seconds = (to_time(time) - Time.now).to_i
      return time_ago(time) if seconds <= 0

      case seconds
      when 0..59                 then 'in less than a minute'
      when 60..3599              then "in #{pluralize(seconds / 60,         'minute')}"
      when 3600..86_399          then "in #{pluralize(seconds / 3600,       'hour')}"
      when 86_400..604_799       then "in #{pluralize(seconds / 86_400,     'day')}"
      when 604_800..2_591_999    then "in #{pluralize(seconds / 604_800,    'week')}"
      when 2_592_000..31_535_999 then "in #{pluralize(seconds / 2_592_000,  'month')}"
      else                            "in #{pluralize(seconds / 31_536_000, 'year')}"
      end
    end

    def link_to(text, url, **attrs)
      safe_url = sanitized_url(url) || '#'
      attrs_str = attrs.map { |k, v| %(#{h(k.to_s)}="#{h(v.to_s)}") }.join(' ')
      attrs_str = " #{attrs_str}" unless attrs_str.empty?
      %(<a href="#{safe_url}"#{attrs_str}>#{h(text)}</a>)
    end

    def excerpt(text, words: 50, omission: '…')
      stripped = text.to_s.gsub(/<[^>]+>/, '').strip
      arr = stripped.split(/\s+/)
      return stripped if arr.length <= words

      "#{arr[0, words].join(' ')}#{omission}"
    end

    def reading_time(text, wpm: 200)
      stripped = text.to_s.gsub(/<[^>]+>/, '')
      word_count = stripped.split(/\s+/).length
      minutes = (word_count / wpm.to_f).ceil
      "#{minutes} min read"
    end

    def slugify(text)
      text.to_s.downcase.gsub(/[^a-z0-9]+/, '-').gsub(/\A-|-\z/, '')
    end

    # Render a markdown string to HTML. For frontmatter prose fields
    # (publication excerpts, bundle/series descriptions) that authors
    # write with bold, italics, links, paragraphs, lists — the same
    # markdown they'd use in a page body. Uses the engine's standard
    # `MARKDOWN_OPTIONS` so the dialect (tables, footnotes, autolinks,
    # raw HTML) matches what `Page#content` produces.
    #
    # Returns '' for nil/empty input so the caller can `<%== markdown(...) %>`
    # unconditionally without an extra `if` guard.
    def markdown(text)
      return '' if text.nil? || text.to_s.strip.empty?

      Commonmarker.to_html(text.to_s, options: Page::MARKDOWN_OPTIONS)
    end

    def to_time(value)
      case value
      when Time then value
      when Date then value.to_time
      else Time.parse(value.to_s)
      end
    end
  end
end

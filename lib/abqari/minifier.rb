# frozen_string_literal: true

module Abqari
  # Conservative HTML minifier. Strips comments, collapses whitespace between
  # tags, and trims leading/trailing whitespace — but preserves the contents of
  # <pre>, <textarea>, <script>, and <style> blocks where whitespace matters.
  module Minifier
    PRESERVE_TAGS = %w[pre textarea script style].freeze
    PLACEHOLDER = "\x00ABQARI_PRESERVED_%d\x00"

    # Comments and preserved blocks are recognised in ONE left-to-right
    # pass, via ordered alternation, so whichever construct STARTS first
    # consumes the other — the same single-pass discipline (and for the
    # same reason) as CSS_TOKEN_REGEX below.
    #
    # Stashing preserved blocks first and stripping comments afterwards
    # is what this replaced, and it was wrong: a tag-like string written
    # inside a comment — `<!-- see the <script> tag -->` in a layout —
    # opened a preserved region at the `<script>` text, which then ran
    # to the next GENUINE `</script>` further down the document,
    # swallowing the comment's own `-->` on the way. The orphaned `<!--`
    # then paired with some later `-->`, and the comment pass deleted
    # the placeholder and everything between. Pages came out with an
    # empty `<main>`, in production builds only (dev doesn't minify).
    #
    # Comments matched here are dropped, except conditional comments
    # (`<!--[if …]>`), which are stashed so they survive verbatim.
    HTML_TOKEN_REGEX = %r{
      (?<comment><!--.*?-->)
      |
      (?<preserved><(?<tag>#{PRESERVE_TAGS.join('|')})\b[^>]*>.*?</\k<tag>>)
    }imx.freeze
    CONDITIONAL_COMMENT_REGEX = /\A<!--\[if/i.freeze

    def self.minify(html)
      preserved = []

      protected_html = html.gsub(HTML_TOKEN_REGEX) do
        match = ::Regexp.last_match
        if match[:comment] && !match[:comment].match?(CONDITIONAL_COMMENT_REGEX)
          ''
        else
          preserved << match[0]
          format(PLACEHOLDER, preserved.length - 1)
        end
      end

      minified = protected_html
                 # Collapse inter-tag whitespace to a SINGLE space, not
                 # nothing. `<em>a</em> <strong>b</strong>` must stay
                 # "a b" — deleting the space renders "ab". The size win
                 # from collapsing runs is nearly identical; only the
                 # word-joining bug is avoided. (This runs after <pre>/
                 # <textarea>/<script>/<style> are stashed, so
                 # significant whitespace inside them is untouched.)
                 .gsub(/>\s+</, '> <')
                 .gsub(/\s{2,}/, ' ')
      minified = trim(minified)

      restore(minified, preserved)
    end

    # `String#strip` also removes NUL bytes, which would bite the
    # PLACEHOLDER's trailing \x00 whenever a document starts or ends
    # with a preserved block — the placeholder then fails to match on
    # restore and ships to the browser as literal
    # "\x00ABQARI_PRESERVED_0" text. `\s` in a Ruby regex is whitespace
    # only, so trimming this way leaves the sentinels intact.
    TRIM_REGEX = /\A\s+|\s+\z/.freeze
    PLACEHOLDER_REGEX = /\x00ABQARI_PRESERVED_(\d+)\x00/.freeze

    def self.trim(text)
      text.gsub(TRIM_REGEX, '')
    end

    def self.restore(text, preserved)
      text.gsub(PLACEHOLDER_REGEX) { preserved[::Regexp.last_match(1).to_i] }
    end
    private_class_method :trim, :restore

    # Comments and quoted strings are recognised in ONE left-to-right
    # pass, via ordered alternation, so whichever construct STARTS first
    # consumes the other. Handling them in two passes is wrong in both
    # directions:
    #
    #   - Strings first: a bare `'` is a string delimiter, and English
    #     prose in comments is full of apostrophes ("the theme's tokens").
    #     Two comments each carrying one apostrophe get paired into a
    #     single "string" spanning both — and every rule between them,
    #     plus the `*/` that should have closed the first comment, is
    #     swallowed and then deleted by the comment pass. This silently
    #     ate the whole `:root` token block out of every bundled theme,
    #     in production builds only (dev doesn't minify), which is the
    #     worst possible place for it to hide.
    #
    #   - Comments first: `content: "/* not a comment */"` is a legal
    #     string value and must survive verbatim.
    CSS_TOKEN_REGEX = %r{
      (?<comment>/\*.*?\*/)
      |
      (?<string>"(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*')
    }mx.freeze

    # Conservative CSS minifier. Strips comments and collapses
    # whitespace; quoted strings are stashed so `content: "a  b"`
    # survives intact. Two deliberate omissions: no tightening around
    # `:` (removing the space in `.nav :hover` would turn a descendant
    # selector into a compound one) and runs collapse to a single space
    # rather than nothing (`calc(100% - 2rem)` needs its spaces).
    def self.css(css)
      preserved = []
      stripped = css.gsub(CSS_TOKEN_REGEX) do
        match = ::Regexp.last_match
        if match[:comment]
          ''
        else
          preserved << match[:string]
          format(PLACEHOLDER, preserved.length - 1)
        end
      end

      minified = stripped
                 .gsub(/\s+/, ' ')
                 .gsub(/\s*([{};,>])\s*/, '\1')
                 .gsub(';}', '}')
      minified = trim(minified)

      restore(minified, preserved)
    end

    JS_LINE_COMMENT_REGEX  = %r{^[ \t]*//.*$}.freeze
    JS_BLOCK_COMMENT_REGEX = %r{^[ \t]*/\*.*?\*/[ \t]*$}m.freeze

    # Ultra-conservative JS comment stripper. Template literals can
    # legally contain a line-start `//`, so any file using backticks is
    # returned untouched. For the rest, only WHOLE-LINE comments are
    # dropped — a trailing `// note` after code stays, because telling
    # it apart from `"https://…"` inside a string needs real parsing.
    def self.js(js)
      return js if js.include?('`')

      js.gsub(JS_BLOCK_COMMENT_REGEX, '')
        .gsub(JS_LINE_COMMENT_REGEX, '')
        .gsub(/\n{3,}/, "\n\n")
        .sub(/\A\n+/, '')
    end
  end
end

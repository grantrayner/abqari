# frozen_string_literal: true

module Abqari
  # Conservative HTML minifier. Strips comments, collapses whitespace between
  # tags, and trims leading/trailing whitespace — but preserves the contents of
  # <pre>, <textarea>, <script>, and <style> blocks where whitespace matters.
  module Minifier
    PRESERVE_TAGS = %w[pre textarea script style].freeze
    PRESERVE_REGEX = /<(#{PRESERVE_TAGS.join('|')})\b[^>]*>.*?<\/\1>/im.freeze
    PLACEHOLDER = "\x00ABQARI_PRESERVED_%d\x00"
    COMMENT_REGEX = /<!--(?!\[if).*?-->/m.freeze

    def self.minify(html)
      preserved = []

      protected_html = html.gsub(PRESERVE_REGEX) do |match|
        preserved << match
        format(PLACEHOLDER, preserved.length - 1)
      end

      minified = protected_html
                 .gsub(COMMENT_REGEX, '')
                 # Collapse inter-tag whitespace to a SINGLE space, not
                 # nothing. `<em>a</em> <strong>b</strong>` must stay
                 # "a b" — deleting the space renders "ab". The size win
                 # from collapsing runs is nearly identical; only the
                 # word-joining bug is avoided. (This runs after <pre>/
                 # <textarea>/<script>/<style> are stashed, so
                 # significant whitespace inside them is untouched.)
                 .gsub(/>\s+</, '> <')
                 .gsub(/\s{2,}/, ' ')
                 .strip

      minified.gsub(/\x00ABQARI_PRESERVED_(\d+)\x00/) do
        preserved[::Regexp.last_match(1).to_i]
      end
    end

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
                 .strip

      minified.gsub(/\x00ABQARI_PRESERVED_(\d+)\x00/) do
        preserved[::Regexp.last_match(1).to_i]
      end
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

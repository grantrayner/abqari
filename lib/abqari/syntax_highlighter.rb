# frozen_string_literal: true

require 'rouge'
require 'cgi'
require 'fileutils'

module Abqari
  class SyntaxHighlighter
    DEFAULT_THEME = 'github'
    # CommonMarker 1.x emits two shapes depending on whether `render.unsafe`
    # is true (it is, in our config — so authors can use raw HTML in
    # markdown). With unsafe, the lang lives on `<code class="language-X">`
    # and `<pre>` carries an inline `style=`. Without unsafe, lang lived on
    # `<pre lang="X">`. Both shapes also wrap tokens in inline-style
    # `<span>` tags from commonmarker's bundled highlighter — which we
    # strip and re-render with Rouge for theme-aware output.
    COMMONMARKER_BLOCK = %r{<pre lang="(?<lang>[^"]+)"[^>]*>\s*<code>(?<code>.*?)</code>\s*</pre>}m.freeze
    # Permissive: any attributes on <pre>, optional language class on <code>.
    PLAIN_BLOCK = %r{<pre[^>]*>\s*<code(?:\s+class="language-(?<lang>[^"]+)")?>(?<code>.*?)</code>\s*</pre>}m.freeze
    SPAN_TAGS = %r{</?span[^>]*>}.freeze

    def self.process(html)
      html = html.gsub(COMMONMARKER_BLOCK) { highlight(Regexp.last_match[:lang], Regexp.last_match[:code]) }
      html.gsub(PLAIN_BLOCK) do
        m = Regexp.last_match
        # Skip blocks the first pass already produced — they carry
        # `class="highlight"` on the <pre>. Re-running `highlight` on them
        # would strip the Rouge `<span>`s (losing the highlighting) and
        # unescape entities a second time (`&amp;amp;` → `&amp;` → `&`).
        pre_tag = m[0][/\A<pre[^>]*>/]
        next m[0] if pre_tag&.include?('highlight')

        highlight(m[:lang], m[:code])
      end
    end

    def self.highlight(lang, code)
      # Strip any inline <span> tags from commonmarker's pre-highlighting,
      # then decode HTML entities back to source.
      raw = CGI.unescapeHTML(code.gsub(SPAN_TAGS, ''))

      lexer = (lang && Rouge::Lexer.find(lang)) || Rouge::Lexers::PlainText
      formatter = Rouge::Formatters::HTML.new
      highlighted = formatter.format(lexer.lex(raw))
      lang_class = lang ? %( class="language-#{lang}") : ''

      %(<div class="highlight"><pre class="highlight"><code#{lang_class}>#{highlighted}</code></pre></div>)
    end

    # Writes a syntax stylesheet (Rouge theme) to _site/assets/css/syntax.css.
    # Not fingerprinted — the head partial includes it at a stable URL.
    class Stylesheet
      def initialize(site)
        @site = site
      end

      # The rendered Rouge theme CSS. Also consumed by AssetPipeline's
      # CSS bundle, which is what the head partial actually links; the
      # standalone file below stays for sites that override the head
      # partial and reference it directly.
      def css
        theme_name = @site.config['syntax_theme'] || DEFAULT_THEME
        theme = Rouge::Theme.find(theme_name) || Rouge::Themes::Github
        theme.render(scope: '.highlight')
      end

      def write
        return unless @site.config['syntax_highlighting']

        dest = File.join(@site.output_dir, 'assets', 'css', 'syntax.css')
        FileUtils.mkdir_p(File.dirname(dest))
        File.write(dest, css)
      end
    end
  end
end

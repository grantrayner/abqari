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
      html.gsub(PLAIN_BLOCK) { highlight(Regexp.last_match[:lang], Regexp.last_match[:code]) }
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

      def write
        return unless @site.config['syntax_highlighting']

        theme_name = @site.config['syntax_theme'] || DEFAULT_THEME
        theme = Rouge::Theme.find(theme_name) || Rouge::Themes::Github
        css = theme.render(scope: '.highlight')

        dest = File.join(@site.output_dir, 'assets', 'css', 'syntax.css')
        FileUtils.mkdir_p(File.dirname(dest))
        File.write(dest, css)
      end
    end
  end
end

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
      # The two dark-mode contexts every theme's token file uses (see
      # docs/theming.md "Dark mode"). The syntax layer mirrors them so
      # code blocks follow the same light/dark resolution as the rest
      # of the page: OS preference unless the visitor chose light, or
      # the explicit toggle.
      DARK_MEDIA_SCOPE  = ':root:not([data-theme="light"]) .highlight'
      DARK_TOGGLE_SCOPE = '[data-theme="dark"] .highlight'

      def initialize(site)
        @site = site
      end

      # The rendered Rouge theme CSS — a light theme at `.highlight`,
      # a dark theme under the standard dark-mode scopes, and a final
      # override handing the block background to `--color-code-bg` so
      # the active theme owns it (Rouge's hardcoded backgrounds fight
      # warm palettes and never switched in dark mode). Also consumed
      # by AssetPipeline's CSS bundle, which is what the head partial
      # actually links; the standalone file below stays for sites that
      # override the head partial and reference it directly.
      def css
        parts = [light_theme.render(scope: '.highlight')]
        if (dark = dark_theme)
          parts << "@media (prefers-color-scheme: dark) {\n#{dark.render(scope: DARK_MEDIA_SCOPE)}\n}"
          parts << dark.render(scope: DARK_TOGGLE_SCOPE)
        end
        parts << background_override
        parts.join("\n")
      end

      def write
        return unless @site.config['syntax_highlighting']

        dest = File.join(@site.output_dir, 'assets', 'css', 'syntax.css')
        FileUtils.mkdir_p(File.dirname(dest))
        File.write(dest, css)
      end

      private

      def light_theme
        name = @site.config['syntax_theme'] || DEFAULT_THEME
        Rouge::Theme.find(name) || Rouge::Themes::Github
      end

      # Resolution for the dark-mode token palette:
      #   1. `syntax_theme_dark: <name>` — explicit Rouge theme
      #      (mode-suffixed names like `github.dark` work too).
      #   2. `syntax_theme_dark: false` — opt out; the light theme's
      #      tokens are used in both modes (pre-1.2 behaviour).
      #   3. unset — the light theme's own dark mode when it has one
      #      (Rouge's `github` does); otherwise reuse the light theme,
      #      on the assumption a modeless custom pick (monokai etc.)
      #      was chosen to work on the site's dark code background.
      def dark_theme
        name = @site.config['syntax_theme_dark']
        return nil if name == false

        if name
          found = Rouge::Theme.find(name.to_s)
          return found if found

          Log.warn "syntax_theme_dark: #{name.inspect} not found — deriving dark tokens from syntax_theme"
        end
        light = light_theme
        light.respond_to?(:mode) ? light.mode(:dark) : light
      end

      # Rouge themes hardcode a block background tuned to their own
      # palette; emitted last (and mirrored into both dark scopes so
      # equal-specificity source order wins there too), this hands the
      # background to the active theme's `--color-code-bg` token in
      # both modes. Token colours stay Rouge's.
      #
      # The var() fallbacks matter: `theme: bootstrap` and `theme: none`
      # bundle WITHOUT `_common.css`, so `--color-code-bg` is undefined
      # there and a bare var() would compute to `initial` — transparent
      # code blocks. The fallbacks are Github's own light/dark block
      # backgrounds, so no-common themes keep Rouge-native panels.
      LIGHT_BG_FALLBACK = '#f6f8fa'
      DARK_BG_FALLBACK  = '#161b22'

      def background_override
        <<~CSS
          .highlight, .highlight pre { background-color: var(--color-code-bg, #{LIGHT_BG_FALLBACK}); }
          @media (prefers-color-scheme: dark) {
            #{DARK_MEDIA_SCOPE}, #{DARK_MEDIA_SCOPE} pre { background-color: var(--color-code-bg, #{DARK_BG_FALLBACK}); }
          }
          #{DARK_TOGGLE_SCOPE}, #{DARK_TOGGLE_SCOPE} pre { background-color: var(--color-code-bg, #{DARK_BG_FALLBACK}); }
        CSS
      end
    end
  end
end

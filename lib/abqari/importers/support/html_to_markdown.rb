# frozen_string_literal: true

module Abqari
  module Importers
    module Support
      # Thin wrapper over `reverse_markdown`. The gem is lazy-required
      # so a site that never runs `bin/import` doesn't pay the load
      # cost on every build.
      #
      # Conversion tuning:
      #
      #   * `unknown_tags: :pass_through` keeps unrecognised HTML
      #     elements verbatim rather than dropping them — preserves
      #     things like Substack-specific `<figcaption>` wrappers or
      #     Ghost's `<bookmark>` cards. The user can clean those up
      #     manually after import; dropping them silently loses
      #     content.
      #
      #   * `github_flavored: true` emits GFM table syntax and
      #     fenced code blocks, matching how Abqari posts are
      #     authored (kramdown + GFM extensions).
      #
      # Pre-clean pass: strip platform chrome before conversion so
      # the resulting markdown doesn't contain "Subscribe now" CTAs,
      # share buttons, etc. The selectors are passed in by the
      # caller — each importer ships its own list because each
      # platform's chrome is different.
      module HtmlToMarkdown
        # Convert an HTML string to Markdown. `strip_selectors:` is
        # an array of CSS selectors whose matching elements are
        # removed from the DOM before conversion. Empty array = no
        # pre-clean.
        def self.convert(html, strip_selectors: [])
          return '' if html.to_s.empty?

          require_reverse_markdown!
          html = pre_clean(html, strip_selectors) unless strip_selectors.empty?

          md = ReverseMarkdown.convert(
            html,
            unknown_tags: :pass_through,
            github_flavored: true
          )

          # `reverse_markdown` sometimes emits 3+ consecutive blank
          # lines around block elements. Collapse to a single blank.
          md.gsub(/\n{3,}/, "\n\n").strip + "\n"
        end

        # `reverse_markdown` is an OPTIONAL dependency, loaded only here.
        #
        # It isn't in the gemspec's runtime dependencies because it pulls
        # nokogiri, which pulls racc — a chain that costs every install a
        # native-extension gem for a one-time migration feature most
        # sites never run. On Ruby 3.3 that chain is worse than heavy:
        # 3.3 bundles racc 1.7.3, Bundler resolves to 1.8.1, and 1.8.1
        # ships no precompiled Linux binary, so a toolchain-free image
        # (ruby:3.3-slim, most deploy bases) fails `bundle install`
        # outright — on the version the gemspec advertises as its floor.
        #
        # So: importing asks for the gem at the moment it's needed,
        # rather than every user paying for it up front.
        def self.require_reverse_markdown!
          require 'reverse_markdown'
        rescue LoadError
          raise Abqari::UserError, <<~MSG
            Content importing needs the `reverse_markdown` gem, which Abqari
            doesn't install by default (it pulls in nokogiri, which most
            sites never need).

            Install it, then re-run this import:

                gem install reverse_markdown

            Or add it to your site's Gemfile:

                gem 'reverse_markdown', '~> 2.1'
          MSG
        end

        # Remove DOM subtrees matching any of `selectors`. We use a
        # regex-based pass for the simple cases reverse_markdown
        # already handles internally (and to avoid pulling in a
        # full HTML parser like Nokogiri). Patterns target whole
        # opening-to-closing-tag spans with a class match. Good
        # enough for the platform-chrome blocks we know about —
        # callers should keep the selectors simple (`div.foo`,
        # `aside.bar`).
        def self.pre_clean(html, selectors)
          selectors.each do |sel|
            tag, klass = parse_selector(sel)
            next unless tag

            if klass
              # Match <tag …class="… klass …" …>…</tag> with the
              # class anywhere in the class attribute.
              pattern = %r{
                <#{Regexp.escape(tag)}\b
                  [^>]*\bclass\s*=\s*["'][^"']*\b#{Regexp.escape(klass)}\b[^"']*["']
                  [^>]*>
                .*?
                </#{Regexp.escape(tag)}>
              }mxi
            else
              pattern = %r{<#{Regexp.escape(tag)}\b[^>]*>.*?</#{Regexp.escape(tag)}>}mi
            end
            html = html.gsub(pattern, '')
          end
          html
        end

        # Decompose `'div.subscription-widget'` → `['div', 'subscription-widget']`
        # and `'aside'` → `['aside', nil]`. Returns `[nil, nil]` for
        # patterns we don't support (id selectors, attribute selectors,
        # descendant combinators) — those are caller errors and we
        # ignore them rather than crashing the whole import.
        def self.parse_selector(selector)
          return [nil, nil] unless selector.is_a?(String)
          m = selector.match(/\A([a-z][a-z0-9]*)(?:\.([a-z0-9_-]+))?\z/i)
          return [nil, nil] unless m
          [m[1], m[2]]
        end
      end
    end
  end
end

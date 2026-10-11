# frozen_string_literal: true

require 'uri'

require_relative 'theme_bootstrap'
require_relative 'plausible_script'
require_relative 'speculation_rules'

module Abqari
  class HeadersFile
    # The CSP is built per-build based on which optional features are
    # configured (Plausible analytics, etc.). The base policy is strict:
    # 'self' only, with the inline theme-bootstrap script pinned by SHA256
    # so we don't need 'unsafe-inline'. Each opt-in feature extends the
    # policy minimally — Plausible adds plausible.io to script-src and
    # connect-src plus the inline init script's hash, and that's it.
    #
    # To allow an origin the engine doesn't model, add it to `csp:` in
    # config/site.yml — additive, so everything computed here survives.
    # `media:` does the same for off-origin audio / video.
    #
    # Override the whole thing by setting `headers:` in config/site.yml
    # — that disables this dynamic build entirely and ships your structure
    # verbatim. Reach for it only when you need to weaken a hardening
    # directive or use a non-http scheme; `csp:` covers adding origins
    # without losing the pinned script hashes.
    BASE_HEADERS = {
      'X-Content-Type-Options'    => 'nosniff',
      'Referrer-Policy'           => 'strict-origin-when-cross-origin',
      'Permissions-Policy'        => 'camera=(), microphone=(), geolocation=()',
      'Strict-Transport-Security' => 'max-age=31536000; includeSubDomains'
    }.freeze

    def initialize(site)
      @site = site
    end

    def write
      File.write(File.join(@site.output_dir, '_headers'), build)
    end

    private

    def build
      # User override wins outright — no merging.
      if (custom = @site.config['headers'])
        return custom.map { |path, hdrs| section(path, hdrs) }.join("\n\n") + "\n"
      end

      sections = [
        section('/*',        BASE_HEADERS.merge('Content-Security-Policy' => csp_policy)),
        section('/assets/*', { 'Cache-Control' => 'public, max-age=31536000, immutable' })
      ]
      sections.join("\n\n") + "\n"
    end

    def section(path, hdrs)
      lines = [path.to_s]
      hdrs.each { |k, v| lines << "  #{k}: #{v}" }
      lines.join("\n")
    end

    # Build the CSP from a structured representation so opt-in features
    # can extend it cleanly. Returns the serialized policy string.
    #
    # Static-site defence in depth:
    #   - `object-src 'none'`  — never load <object>/<embed>/<applet>.
    #     A static site has no legitimate reason to embed plugins; the
    #     directive blocks an attacker who somehow lands HTML on the
    #     site from pulling in a Flash/PDF/etc.
    #   - `form-action 'self'` — `<form action="https://evil.com">`
    #     becomes a no-op. Abqari emits only same-origin / same-provider
    #     newsletter forms, so the constraint is invisible to honest
    #     templates and stops a content-injection from doubling as a
    #     phishing redirect.
    def csp_policy
      policy = {
        'default-src'     => ["'self'"],
        'img-src'         => ["'self'", 'data:'],
        'style-src'       => ["'self'"],
        'script-src'      => ["'self'", "'#{ThemeBootstrap::SHA256}'", "'#{SpeculationRulesGuard::SHA256}'"],
        'font-src'        => ["'self'"],
        'connect-src'     => ["'self'"],
        'object-src'      => ["'none'"],
        'frame-ancestors' => ["'none'"],
        'form-action'     => ["'self'"],
        'base-uri'        => ["'self'"]
      }

      apply_plausible(policy)        if plausible_key
      apply_folio(policy)            if folio_enabled?
      apply_fontawesome_kit(policy)  if fontawesome_kit?
      apply_search(policy)           if search_enabled?
      apply_speculation_rules(policy) if speculation_rules_enabled?
      apply_newsletter(policy)
      apply_media(policy)
      # Last, so an operator-declared origin can extend a directive that
      # a feature rule above created.
      apply_csp_extensions(policy)

      policy.map { |k, vs| "#{k} #{vs.join(' ')}" }.join('; ')
    end

    # Off-origin audio / video. Media served from the site itself needs
    # no directive at all — it falls under `default-src 'self'`, which is
    # why the base policy declares no `media-src`. Setting `media.host`
    # creates it as `'self' <host>` (`add_origin` seeds `'self'` on any
    # directive it has to create), so colocated bundle audio keeps
    # working alongside the CDN.
    #
    # Accepts one host or a list:
    #
    #   media:
    #     host: https://media.example.com
    #
    #   media:
    #     host:
    #       - https://audio.example.com
    #       - https://video.example.com
    def apply_media(policy)
      cfg = @site.config['media']
      return unless cfg.is_a?(Hash)

      Array(cfg['host']).each { |host| add_origin(policy, 'media-src', host) }
    end

    # Directives an operator may extend via `csp:`. The omissions are
    # deliberate: `default-src` would silently widen every directive
    # that inherits from it, and `object-src` / `frame-ancestors` /
    # `base-uri` are the static-site hardening directives documented on
    # `csp_policy` — making those easy to weaken is exactly what this
    # key must not do. A site that genuinely needs to change them owns
    # the whole header via `headers:`.
    EXTENDABLE_DIRECTIVES = %w[
      child-src connect-src font-src form-action frame-src img-src
      manifest-src media-src script-src style-src worker-src
    ].freeze

    # Operator-declared extra origins:
    #
    #   csp:
    #     img-src:     [https://cdn.example.com]
    #     connect-src: [https://api.example.com]
    #
    # Additive only. Values are appended to the computed policy, so
    # `'self'`, the pinned inline-script hashes and every feature-derived
    # origin survive. That's the point of the key: before it existed the
    # only way to allow an unmodelled origin was `headers:`, which
    # replaces the built policy wholesale and takes the theme-bootstrap
    # hash, `'wasm-unsafe-eval'` and the Plausible hash down with it.
    #
    # Raises on an unknown directive or a value that isn't an http(s)
    # origin. A malformed CSP fails open — the browser ignores the parts
    # it can't parse — so skipping bad config silently would ship a
    # policy the operator believes is in force. Fail the build instead.
    def apply_csp_extensions(policy)
      cfg = @site.config['csp']
      return unless cfg.is_a?(Hash)

      cfg.each do |directive, values|
        name = directive.to_s
        unless EXTENDABLE_DIRECTIVES.include?(name)
          raise ArgumentError,
                "csp: #{name.inspect} is not an extendable directive. " \
                "Extendable: #{EXTENDABLE_DIRECTIVES.join(', ')}. " \
                'Set `headers:` to take over the whole header instead.'
        end

        Array(values).each do |value|
          assert_http_origin!(name, value)
          add_origin(policy, name, value)
        end
      end
    end

    # `add_origin` is deliberately silent for feature-derived values (a
    # relative `newsletter.action` is legitimately same-origin). Values
    # typed directly into `csp:` get the opposite treatment: anything
    # that isn't a scheme + host is an operator error worth stopping the
    # build for, and rejecting everything else is what keeps `*`,
    # `data:` and `'unsafe-inline'` out of this path by construction.
    def assert_http_origin!(directive, value)
      uri = begin
        URI.parse(value.to_s)
      rescue URI::InvalidURIError
        nil
      end
      return if (uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)) && !uri.host.to_s.empty?

      raise ArgumentError,
            "csp: #{directive} value #{value.inspect} is not an http(s) origin. " \
            'Use scheme + host (e.g. https://cdn.example.com). CSP keywords and ' \
            "non-http schemes ('unsafe-inline', data:, blob:, *) are rejected here — " \
            'set `headers:` if you need them.'
    end

    # Pagefind (opt-in via `search: true`) loads its runtime from the
    # same origin, but that runtime compiles a WebAssembly module —
    # and WASM compilation is governed by `script-src` regardless of
    # origin. Without `'wasm-unsafe-eval'` the search box silently
    # fails with a CSP violation on any host that enforces `_headers`
    # (Cloudflare Pages, Netlify). Same-origin does NOT exempt WASM.
    def apply_search(policy)
      policy['script-src'] << "'wasm-unsafe-eval'"
    end

    def search_enabled?
      @site.config['search'] == true
    end

    # The `<script type="speculationrules">` block the head emits is an
    # inline script as far as CSP is concerned. `'inline-speculation-rules'`
    # is Chrome's keyword for exactly this, but Chrome stops honouring
    # it once script-src lists a hash — and the base policy always does
    # — so the block is pinned by its own SHA-256 as well. The body is
    # config-dependent, so the hash is computed per build from the same
    # SpeculationRules.script the head emits.
    def apply_speculation_rules(policy)
      policy['script-src'] << "'#{SpeculationRules.sha256(@site)}'"
      policy['script-src'] << "'inline-speculation-rules'"
    end

    def speculation_rules_enabled?
      SpeculationRules.enabled?(@site)
    end

    # Plausible: external tracker + inline init script. Both need explicit
    # CSP allowlisting. Outbound tracking events also hit plausible.io's
    # API endpoint, which is why connect-src is extended.
    def apply_plausible(policy)
      policy['script-src']  << 'https://plausible.io'
      policy['script-src']  << "'#{PlausibleScript::SHA256}'"
      policy['connect-src'] << 'https://plausible.io'
    end

    # Folio cover images are served from a separate cover host. Layouts
    # emit them as `<img src="https://…">`, so img-src needs the host
    # explicitly. Defaults to the hosted foliobooks.app cover CDN; a
    # Folio instance on another domain sets `folio.covers_host` to its
    # own. Buy / cart URLs are anchor navigations (no CSP) — only
    # img-src needs extension.
    DEFAULT_FOLIO_COVERS_HOST = 'https://covers.foliobooks.app'

    def apply_folio(policy)
      cfg = @site.config['folio'] || {}
      covers = cfg['covers_host'].to_s
      covers = DEFAULT_FOLIO_COVERS_HOST if covers.empty?
      add_origin(policy, 'img-src', covers)
    end

    def folio_enabled?
      cfg = @site.config['folio'] || {}
      !cfg['base_url'].to_s.empty? && !cfg['author_slug'].to_s.empty?
    end

    # Font Awesome Pro kit. Loaded via JS from kit.fontawesome.com, which
    # injects styles into the page (so style-src needs 'unsafe-inline')
    # and pulls woff2s from ka-f.fontawesome.com (font-src). The trade-off
    # vs the vendored Free dist: PRO icons + auto-versioning, in exchange
    # for a weaker CSP. Sites that want strict CSP should use the
    # `fontawesome: true` (Free vendored) path instead.
    def apply_fontawesome_kit(policy)
      policy['script-src'] << 'https://kit.fontawesome.com'
      policy['style-src']  << "'unsafe-inline'"
      policy['font-src']   << 'https://ka-f.fontawesome.com'
      policy['connect-src'] << 'https://ka-f.fontawesome.com'
    end

    def fontawesome_kit?
      kit = (@site.config['icons'] || {})['fontawesome_kit']
      kit.is_a?(String) && !kit.empty?
    end

    # `_newsletter_subscribe.html.erb` lets the operator point the form at
    # any third-party provider (Mailchimp, Buttondown, ConvertKit, …). The
    # default `form-action 'self'` would block those POSTs. We trust the
    # operator-configured `newsletter.action` (and the optional `script:`
    # URL) and add their origins to the matching directives — narrowly,
    # not via `unsafe-inline` or wildcards.
    def apply_newsletter(policy)
      cfg = @site.config['newsletter']
      return unless cfg.is_a?(Hash)

      add_origin(policy, 'form-action', cfg['action'])
      add_origin(policy, 'script-src',  cfg['script'])
      add_origin(policy, 'connect-src', cfg['script'])
    end

    # Parse `value` as an http(s) URL and append its `scheme://host`
    # origin to `directive` if it isn't already there. Silent no-op for
    # anything that doesn't parse as http(s) — same-origin / relative
    # values fall under `'self'`, scheme-based attacks (javascript:,
    # data:) never get past the URI type-check.
    def add_origin(policy, directive, value)
      return if value.nil? || value.to_s.empty?

      uri = URI.parse(value.to_s)
      return unless uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)
      return if uri.host.to_s.empty?

      origin = "#{uri.scheme}://#{uri.host}"
      policy[directive] ||= ["'self'"]
      policy[directive] << origin unless policy[directive].include?(origin)
    rescue URI::InvalidURIError
      # Malformed config — let it through unguarded; the form just won't
      # work, which is the same surface visitors would see anyway.
      nil
    end

    # The Plausible script key when the analytics block is fully
    # configured — both `enabled: true` AND `key:` set. Used to gate
    # the CSP extension (plausible.io added to script-src + connect-src
    # only when we're actually emitting the tracker).
    def plausible_key
      cfg = @site.config['plausible']
      return nil unless cfg.is_a?(Hash)
      return nil unless cfg['enabled'] == true

      key = cfg['key'].to_s
      key.empty? ? nil : key
    end
  end
end

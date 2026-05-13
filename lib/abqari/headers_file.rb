# frozen_string_literal: true

require_relative 'theme_bootstrap'
require_relative 'plausible_script'

module Abqari
  class HeadersFile
    # The CSP is built per-build based on which optional features are
    # configured (Plausible analytics, etc.). The base policy is strict:
    # 'self' only, with the inline theme-bootstrap script pinned by SHA256
    # so we don't need 'unsafe-inline'. Each opt-in feature extends the
    # policy minimally — Plausible adds plausible.io to script-src and
    # connect-src plus the inline init script's hash, and that's it.
    #
    # Override the whole thing by setting `headers:` in config/site.yml
    # — that disables this dynamic build entirely and ships your structure
    # verbatim. Useful for cases where you need precise control.
    BASE_HEADERS = {
      'X-Content-Type-Options'    => 'nosniff',
      'Referrer-Policy'           => 'strict-origin-when-cross-origin',
      'Permissions-Policy'        => 'camera=(), microphone=(), geolocation=(), interest-cohort=()',
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
    def csp_policy
      policy = {
        'default-src'     => ["'self'"],
        'img-src'         => ["'self'", 'data:'],
        'style-src'       => ["'self'"],
        'script-src'      => ["'self'", "'#{ThemeBootstrap::SHA256}'", "'#{SpeculationRulesGuard::SHA256}'"],
        'font-src'        => ["'self'"],
        'connect-src'     => ["'self'"],
        'frame-ancestors' => ["'none'"],
        'base-uri'        => ["'self'"]
      }

      apply_plausible(policy)        if plausible_key
      apply_folio(policy)            if folio_enabled?
      apply_fontawesome_kit(policy)  if fontawesome_kit?

      policy.map { |k, vs| "#{k} #{vs.join(' ')}" }.join('; ')
    end

    # Plausible: external tracker + inline init script. Both need explicit
    # CSP allowlisting. Outbound tracking events also hit plausible.io's
    # API endpoint, which is why connect-src is extended.
    def apply_plausible(policy)
      policy['script-src']  << 'https://plausible.io'
      policy['script-src']  << "'#{PlausibleScript::SHA256}'"
      policy['connect-src'] << 'https://plausible.io'
    end

    # Folio cover images are served from a separate cover host
    # (covers.foliobooks.app). Layouts emit them as `<img src="https://…">`,
    # so img-src needs the host explicitly. Buy / cart URLs are anchor
    # navigations (no CSP) — only img-src needs extension.
    def apply_folio(policy)
      policy['img-src'] << 'https://covers.foliobooks.app'
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

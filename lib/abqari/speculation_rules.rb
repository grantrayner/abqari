# frozen_string_literal: true

require 'digest'
require 'base64'

module Abqari
  # The `<script type="speculationrules">` block in the head, built here
  # rather than in `_head.html.erb` so HeadersFile hashes the exact bytes
  # the page carries and the two can't drift.
  #
  # The hash is what lets the block run. Chrome stops honouring the
  # `'inline-speculation-rules'` keyword once script-src lists any hash,
  # and ours always does (ThemeBootstrap, SpeculationRulesGuard), so on
  # its own the keyword left every page logging a CSP violation with
  # nothing prerendered. The keyword stays in the policy for browsers
  # that do honour it.
  #
  # Unlike the other inline scripts, the body depends on config (the
  # URL patterns and eagerness), so its hash is per-site, not a constant.
  module SpeculationRules
    EAGERNESS         = %w[conservative moderate eager].freeze
    DEFAULT_EAGERNESS = 'moderate'

    module_function

    def enabled?(site)
      cfg = site.config['speculation_rules']
      !cfg.is_a?(Hash) || cfg['enabled'] != false
    end

    # The surrounding whitespace is what the inline template produced
    # before the body moved here. Keeping it byte-identical means a hash
    # already copied into a host that ignores `_headers` (Render) stays
    # valid across the upgrade for any site that doesn't change config.
    def script(site)
      "\n  { \"prerender\": [{ \"source\": \"document\",\n    \"where\": #{where(href_matches(site))},\n    " \
        "\"eagerness\": #{json(eagerness(site))} }] }\n  "
    end

    def sha256(site)
      "sha256-#{Base64.strict_encode64(Digest::SHA256.digest(script(site)))}"
    end

    # `speculation_rules.href_matches:` — one URL pattern or a list.
    # Defaults to the posts collection, which is all the engine knows is
    # article-shaped; a site whose main content is a custom collection
    # (`/news/*`) names it here.
    def href_matches(site)
      patterns = Array(settings(site)['href_matches']).map { |p| p.to_s.strip }.reject(&:empty?)
      patterns.empty? ? ["/#{posts_path(site)}/*"] : patterns
    end

    def eagerness(site)
      value = settings(site)['eagerness'].to_s
      EAGERNESS.include?(value) ? value : DEFAULT_EAGERNESS
    end

    def where(patterns)
      clauses = patterns.map { |p| "{ \"href_matches\": #{json(p)} }" }
      clauses.one? ? clauses.first : "{ \"or\": [#{clauses.join(', ')}] }"
    end

    # Same slug the posts collection resolves to (Site#collection_config
    # takes it straight from config; the defaults carry none).
    def posts_path(site)
      collections = site.config['collections']
      posts = collections.is_a?(Hash) ? collections['posts'] : nil
      slug = posts.is_a?(Hash) ? posts['slug'].to_s : ''
      slug.empty? ? 'posts' : slug
    end

    def settings(site)
      cfg = site.config['speculation_rules']
      cfg.is_a?(Hash) ? cfg : {}
    end

    # Patterns come from site config, but this lands raw inside a
    # <script>, so a stray `</script>` must not be able to close it.
    def json(value)
      Helpers.script_safe_json(value)
    end
  end
end

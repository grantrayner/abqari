# frozen_string_literal: true

require 'date'
require 'fileutils'
require 'json'
require 'set'
require 'time'
require 'uri'
require 'yaml'

module Abqari
  # IndieWeb foundation — Milestone A.
  #
  # Three pieces, each independently useful:
  #
  #   1. Webmentions::Fetcher — polls webmention.io at build time, caches
  #      the result, exposes a per-URL lookup so the post layout can
  #      render replies/likes/reposts under each post.
  #
  #   2. Webmentions::Sender — POSTs notifications to external sites that
  #      our posts link to. Tracks what's been sent in a YAML log so
  #      re-builds don't spam. Off by default; opt in with
  #      `indieweb.send_webmentions: true`.
  #
  #   3. Bridgy — generates the `<link>` tags that announce the site to
  #      Bridgy Fed (Fediverse / ActivityPub bridge) and webmention.io.
  #      Tags only — no runtime federation logic here; Bridgy Fed handles
  #      the signed-HTTP/AP plumbing on its own infrastructure.
  #
  # Config (`indieweb:` block in config/site.yml):
  #
  #     indieweb:
  #       enabled: true                       # master switch (default false)
  #       domain: example.com                  # required when enabled
  #       webmention_io_token: "..."           # optional — needed for receive
  #       bridgy_fed: true                     # adds Bridgy Fed link tags
  #       send_webmentions: true               # POST to targets on build
  #       send_window_days: 30                 # only send for posts published
  #                                            #   within the last N days
  #
  # Cache: `vendor/webmentions/` (gitignored, like vendor/folio/) — one
  # file for received mentions, one for sent-log tracking.
  module Indieweb
    USER_AGENT = "abqari-indieweb/#{Abqari::VERSION}"

    def self.config_for(site)
      site.config['indieweb'] || {}
    end

    def self.enabled?(site)
      cfg = config_for(site)
      cfg['enabled'] == true && !cfg['domain'].to_s.empty?
    end

    # Convenience: site.indieweb returns this module, keeping the public
    # API symmetrical with site.folio.
    def self.webmention_endpoint(site)
      cfg = config_for(site)
      return nil unless cfg['domain']
      "https://webmention.io/#{cfg['domain']}/webmention"
    end

    # Fetcher — pulls received webmentions from webmention.io and exposes
    # them keyed by the target URL. The fetcher caches the full JF2
    # response under `vendor/webmentions/mentions.json` and uses an ETag
    # header so subsequent builds typically get a 304 and reuse the cache.
    #
    # Layouts query this via `site.webmentions_for(page.url)`, which
    # returns an array of mention hashes (or `[]` when none).
    class Fetcher
      # webmention.io's public mentions endpoint. `target` filtering
      # happens client-side: pulling all mentions for the domain in one
      # paginated fetch is cheaper than one HTTP call per post.
      API_BASE = 'https://webmention.io/api/mentions.jf2'

      # Plenty of headroom for high-volume sites — typical hobby sites
      # pull a few hundred mentions per build, well under this cap.
      MAX_RESPONSE_BYTES = 4 * 1024 * 1024
      PAGE_SIZE = 200

      def initialize(site)
        @site = site
        @cfg  = Indieweb.config_for(site)
      end

      def enabled?
        Indieweb.enabled?(@site) && !webmention_io_token.empty?
      end

      # ENV fallback so the API token can live in a CI secret instead of
      # committed site.yml. Config value wins when set.
      def webmention_io_token
        value = @cfg['webmention_io_token'].to_s
        value.empty? ? ENV['ABQARI_WEBMENTION_IO_TOKEN'].to_s : value
      end

      def cache_dir
        File.join(@site.site_root, 'vendor', 'webmentions')
      end

      def cache_path
        File.join(cache_dir, 'mentions.json')
      end

      def etag_path
        File.join(cache_dir, 'etag')
      end

      # Run the fetch. Idempotent on the cache layer: a 304 just reuses
      # the on-disk copy. Populates `site.data['webmentions']` as a
      # `{ target_url => [mention, ...] }` hash so the post layout's
      # lookup is O(1).
      def fetch
        unless enabled?
          @site.data['webmentions'] = {}
          return
        end

        FileUtils.mkdir_p(cache_dir)
        mentions = load_or_refresh
        index    = index_by_target(mentions)
        @site.data['webmentions'] = index
        Log.info "Webmentions: #{mentions.size} cached mention(s) across #{index.size} target URL(s)"
      end

      private

      def load_or_refresh
        cached = File.exist?(cache_path) ? safe_parse(File.read(cache_path)) : nil
        etag   = File.exist?(etag_path)  ? File.read(etag_path).strip       : nil

        # Token in the `Authorization` header rather than the query
        # string. Query strings end up in upstream proxy access logs,
        # web-server panels, and outbound HTTP monitoring — bearer-style
        # secrets shouldn't ride there. The webmention.io API accepts
        # the token in either place; pick the form that doesn't leak.
        uri = URI("#{API_BASE}?domain=#{URI.encode_www_form_component(@cfg['domain'])}" \
                  "&per-page=#{PAGE_SIZE}")
        headers = {
          'Accept'        => 'application/json',
          'User-Agent'    => USER_AGENT,
          'Authorization' => "Bearer #{webmention_io_token}"
        }
        headers['If-None-Match'] = etag if etag

        begin
          res = HttpSafe.get(uri, headers: headers, max_bytes: MAX_RESPONSE_BYTES)
        rescue StandardError => e
          Log.warn "Webmentions fetch failed (#{e.class}: #{e.message}) — using cached data"
          return cached_children(cached)
        end

        case res.code.to_i
        when 200
          parsed = safe_parse(res.body) || {}
          Abqari.atomic_write(cache_path, JSON.pretty_generate(parsed))
          if res['etag']
            Abqari.atomic_write(etag_path, res['etag'].to_s)
          elsif File.exist?(etag_path)
            # 200 with no ETag: drop the stale one. Otherwise it keeps
            # riding `If-None-Match` and the API answers 304 forever —
            # the cache freezes and new mentions never appear.
            File.delete(etag_path)
          end
          cached_children(parsed)
        when 304
          cached_children(cached)
        else
          Log.warn "Webmentions fetch: HTTP #{res.code} — using cached data"
          cached_children(cached)
        end
      end

      def cached_children(payload)
        return [] unless payload.is_a?(Hash)
        Array(payload['children'])
      end

      def safe_parse(body)
        JSON.parse(body)
      rescue JSON::ParserError
        nil
      end

      # Group mentions by the canonical-path form of `wm-target` so the
      # post layout's URL ("/posts/foo/") matches even when the original
      # webmention pointed at "https://example.com/posts/foo".
      def index_by_target(mentions)
        own_host = begin
          URI(@site.config['url'].to_s).host
        rescue URI::InvalidURIError
          nil
        end

        index = Hash.new { |h, k| h[k] = [] }
        mentions.each do |mention|
          target = mention['wm-target'] || mention['target']
          next if target.to_s.empty?
          # Drop mentions whose target is a DIFFERENT host — the lookup
          # keys on path only (page.url has no host), so without this a
          # mention for `https://other.example/posts/foo` would be
          # attributed to our `/posts/foo/`. webmention.io is queried
          # per-domain so this is belt-and-braces, but cheap.
          next unless target_host_matches?(target, own_host)

          key = canonicalise(target)
          index[key] << mention
        end
        # Newest first within each target — matches the "Replies"
        # section visual convention.
        index.each_value { |list| list.sort_by! { |m| m['published'].to_s }.reverse! }
        index
      end

      # True when `target`'s host matches the site's own host. When the
      # site host is unknown (no `url` configured), don't filter — keep
      # the historical path-only behaviour.
      def target_host_matches?(target, own_host)
        return true if own_host.nil?

        URI(target.to_s).host == own_host
      rescue URI::InvalidURIError
        false
      end

      def canonicalise(url)
        uri = URI(url.to_s)
        path = uri.path
        path = "#{path}/" unless path.end_with?('/')
        path
      rescue URI::InvalidURIError
        url.to_s
      end
    end

    # Sender — POSTs webmention notifications to external sites linked
    # from our posts. The sent-log lives at
    # `vendor/webmentions/sent.yml` so re-builds don't double-send.
    #
    # Endpoint discovery follows the webmention spec:
    #   1. HEAD the target; check `Link: <...>; rel="webmention"`
    #   2. Fall back to GET; check `<link rel="webmention">` in <head>
    #
    # Only posts published within `send_window_days` (default 30) are
    # candidates — historical posts have already received their
    # notifications in earlier builds, and replaying them on every
    # CI run wastes outbound HTTP and can look like spam.
    class Sender
      MAX_TARGET_BYTES = 1 * 1024 * 1024 # 1 MB cap for endpoint discovery HTML
      LINK_REL_WEBMENTION_RE = /<(?<url>[^>]+)>\s*;[^,]*?rel\s*=\s*"?webmention"?/i.freeze
      HTML_WEBMENTION_RE = %r{<link\b[^>]*?rel=["']?webmention["']?[^>]*?href=["']([^"']+)["']|<link\b[^>]*?href=["']([^"']+)["'][^>]*?rel=["']?webmention["']?}i.freeze

      def initialize(site)
        @site = site
        @cfg  = Indieweb.config_for(site)
      end

      def enabled?
        Indieweb.enabled?(@site) && @cfg['send_webmentions'] == true
      end

      def log_path
        File.join(@site.site_root, 'vendor', 'webmentions', 'sent.yml')
      end

      def send_window_days
        @cfg.fetch('send_window_days', 30).to_i
      end

      # Walk recently-published posts, extract outbound external links
      # from their rendered bodies, send a notification per (source, target)
      # pair not already in the sent log.
      def send_all
        return unless enabled?
        # Hard production gate — same rationale as the syndication
        # Dispatcher. Sending webmentions is an outbound POST to every
        # site a post links to; doing it from a dev build (which includes
        # drafts / future posts and resolves source URLs against the dev
        # `url`) would ping targets with unpublished, localhost-scoped
        # source URLs. Only fire in production.
        return unless @site.respond_to?(:env) && @site.env == :production

        FileUtils.mkdir_p(File.dirname(log_path))
        log = load_log
        cutoff = Date.today - send_window_days
        sent_count = 0

        recent_posts(cutoff).each do |post|
          source_url = absolute_url_for(post)
          next if source_url.nil?

          outbound_targets_for(post).each do |target|
            key = "#{source_url}|#{target}"
            # Skip only when previously SENT successfully. Prior
            # `'no-endpoint'` (transient DNS / 5xx) and `'failed'`
            # (target up but POST rejected) entries are recorded for
            # visibility but get retried on the next build — a single
            # bad build must not permanently exclude a (source, target)
            # pair. Same retry policy as the syndication Dispatcher.
            prev = log['sent'][key]
            next if prev && prev['status'] == 'sent'

            endpoint = discover_endpoint(target)
            unless endpoint
              log['sent'][key] = { 'status' => 'no-endpoint', 'at' => Time.now.utc.iso8601 }
              next
            end

            if post_notification(endpoint, source_url, target)
              log['sent'][key] = { 'status' => 'sent', 'at' => Time.now.utc.iso8601 }
              sent_count += 1
              Log.info "Webmention sent: #{source_url} → #{target}"
            else
              log['sent'][key] = { 'status' => 'failed', 'at' => Time.now.utc.iso8601 }
            end
          end
        end

        save_log(log) if sent_count.positive? || log_dirty?(log)
        Log.info "Webmentions: sent #{sent_count} new notification(s)" if sent_count.positive?
      end

      private

      def load_log
        return { 'sent' => {} } unless File.exist?(log_path)
        raw = YAML.safe_load_file(log_path, permitted_classes: Abqari::YAML_PERMITTED_CLASSES) || {}
        raw['sent'] ||= {}
        raw
      end

      def save_log(log)
        Abqari.atomic_write(log_path, YAML.dump(log))
      end

      def log_dirty?(log)
        @initial_keys ||= load_log['sent'].keys.sort
        log['sent'].keys.sort != @initial_keys
      end

      def recent_posts(cutoff)
        posts = @site.respond_to?(:posts) ? @site.posts : Array(@site.collection('posts'))
        posts.select do |p|
          next false unless p.respond_to?(:date) && p.date && p.date.to_date >= cutoff
          # Defence in depth — never ping targets for drafts or future
          # posts even if one reaches `posts`. See the production gate in
          # `send_all`.
          next false if p.respond_to?(:draft?) && p.draft?
          next false if p.respond_to?(:future?) && p.future?

          true
        end
      end

      def absolute_url_for(page)
        base = canonical_site_url
        return nil if base.to_s.empty?
        "#{base.sub(%r{/\z}, '')}#{page.url}"
      end

      def canonical_site_url
        # Already env-resolved — see the same method on
        # Syndication::Dispatcher for why there's no `environments` dig.
        @site.config['url']
      end

      # Extract distinct off-site http(s) URLs from a post's body.
      # Reads `post.content` (the markdown rendered to HTML — sending
      # runs after render in `Site#build`, so this is populated).
      # Author-controlled markdown source means `[text](url)` and
      # bare URLs are the only shapes we need to handle; the bare-URL
      # regex below catches both forms once Commonmarker has emitted
      # them as anchor `href`s or as plain text.
      def outbound_targets_for(post)
        body = post.respond_to?(:content) ? post.content.to_s : ''
        return [] if body.empty?

        urls = body.scan(%r{\bhttps?://[^\s\)\]"<>]+}).map { |u| u.sub(/[\.,;\)]+\z/, '') }
        own_host = own_host_from_url(canonical_site_url)
        urls.uniq.reject { |u| same_host?(u, own_host) }
      end

      def own_host_from_url(url)
        URI(url.to_s).host
      rescue URI::InvalidURIError
        nil
      end

      def same_host?(url, own_host)
        return false if own_host.nil?
        URI(url).host == own_host
      rescue URI::InvalidURIError
        true # treat malformed URLs as "ours" so we don't try to send to them
      end

      def discover_endpoint(target)
        uri = URI(target)
        # HEAD first — cheaper, and many sites expose the Link header
        # without us needing the body.
        head = http_request(uri, :head)
        if head && (link = link_header_endpoint(head['link'], uri))
          return link
        end

        # Fall back to GET on the body.
        body = http_request(uri, :get, max_bytes: MAX_TARGET_BYTES)
        return nil unless body
        if (link = link_header_endpoint(body['link'], uri))
          return link
        end
        link_in_html(body.body, uri)
      rescue StandardError => e
        Log.debug "webmention endpoint discovery failed for #{target}: #{e.class}: #{e.message}"
        nil
      end

      # `Link: <https://example.com/wm>; rel="webmention"` — possibly
      # alongside other rel links in the same header.
      def link_header_endpoint(header_value, base)
        return nil if header_value.to_s.empty?
        header_value.split(/,\s*(?=<)/).each do |part|
          m = part.match(LINK_REL_WEBMENTION_RE)
          return URI.join(base, m[:url]).to_s if m
        end
        nil
      end

      def link_in_html(body, base)
        m = body.match(HTML_WEBMENTION_RE)
        return nil unless m
        href = m[1] || m[2]
        URI.join(base, href).to_s
      end

      def http_request(uri, method, max_bytes: 64 * 1024)
        # Route every method (GET/HEAD) through HttpSafe so the
        # streaming + body-size cap + timeouts apply uniformly.
        # Discovery probes target arbitrary external hosts found in
        # post bodies — a hostile or compromised target could
        # otherwise stream gigabytes into the build's memory.
        HttpSafe.request(method, uri,
                         headers: { 'User-Agent' => USER_AGENT },
                         max_bytes: max_bytes,
                         open_timeout: 5,
                         read_timeout: method == :head ? 5 : 10)
      rescue StandardError => e
        Log.debug "webmention #{method.upcase} #{uri} failed: #{e.class}: #{e.message}"
        nil
      end

      def post_notification(endpoint, source, target)
        body = URI.encode_www_form(source: source, target: target)
        res = HttpSafe.request(:post, endpoint,
                               headers: {
                                 'Content-Type' => 'application/x-www-form-urlencoded',
                                 'User-Agent'   => USER_AGENT
                               },
                               body: body,
                               max_bytes: 64 * 1024,
                               open_timeout: 5,
                               read_timeout: 10)
        res.code.to_i.between?(200, 299)
      rescue StandardError => e
        Log.warn "Webmention POST failed (#{endpoint}): #{e.class}: #{e.message}"
        false
      end
    end

    # Bridgy Fed + webmention.io link tags. Pure markup — no runtime
    # logic. Layouts call these from `<head>` via the `_head` partial.
    #
    # Bridgy Fed (fed.brid.gy) acts as the ActivityPub bridge: it speaks
    # the federation protocol on the site's behalf and translates
    # incoming AP activity into webmentions, which webmention.io catches
    # for us. Net result: a Mastodon user can search `@<your-domain>`
    # and follow the site directly, with their replies showing up under
    # posts as ordinary webmentions.
    module Bridgy
      def self.head_links(site)
        cfg = Indieweb.config_for(site)
        return [] unless Indieweb.enabled?(site)

        links = []
        # Webmention endpoint discovery — sites that link to ours can
        # ping this URL; webmention.io receives on our behalf.
        if (endpoint = Indieweb.webmention_endpoint(site))
          links << %(<link rel="webmention" href="#{endpoint}">)
          # Pingback for legacy interop. Free side-effect of having
          # webmention.io as the inbox.
          links << %(<link rel="pingback" href="https://webmention.io/webmention?forward=#{endpoint}">)
        end

        if cfg['bridgy_fed'] == true
          # Bridgy Fed exposes an AP actor at /ap/<domain>; advertising
          # the URL via `rel="me"` is enough for Mastodon's user lookup
          # to find the site. The site's own URL appearing as rel=me
          # on the Bridgy actor (set up out-of-band) closes the loop.
          domain = cfg['domain']
          links << %(<link rel="me" href="https://fed.brid.gy/r/https://#{domain}/">)
          links << %(<link rel="alternate" type="application/activity+json" )
          links[-1] += %(href="https://fed.brid.gy/r/https://#{domain}/">)
        end
        links
      end
    end
  end
end

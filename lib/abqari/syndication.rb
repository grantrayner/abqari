# frozen_string_literal: true

require 'date'
require 'fileutils'
require 'json'
require 'net/http'
require 'time'
require 'uri'
require 'yaml'

module Abqari
  # Syndication — Milestone B of the IndieWeb work.
  #
  # POSSE = "Publish on your Own Site, Syndicate Elsewhere." On each
  # build, for every post not yet syndicated, post a short summary +
  # canonical URL to the configured destinations (Mastodon, Bluesky).
  # The originating posts on those networks point back at the site's
  # canonical version — search engines see your site as the source of
  # truth, while readers who only follow you on Mastodon/Bluesky still
  # discover new work.
  #
  # Each destination is a separate class under `Syndication::Networks`,
  # implementing two methods:
  #
  #   * `configured?` — has the operator filled in the required tokens?
  #   * `post(text:, url:)` — POST the syndicated snippet, return the
  #     resulting URL of the syndicated post (or nil on failure).
  #
  # The dispatcher walks recent posts, formats the snippet for each
  # network (different length limits), and tracks every successful
  # post in `vendor/syndication/sent.yml` so re-builds never double-
  # syndicate.
  #
  # Config (`syndication:` block in config/site.yml):
  #
  #     syndication:
  #       enabled: true                     # master switch
  #       window_days: 14                   # only syndicate posts published
  #                                         #   within the last N days (older
  #                                         #   posts predate syndication setup)
  #       mastodon:
  #         enabled: true
  #         instance: https://mastodon.social
  #         access_token: "..."             # from your instance's app settings
  #         visibility: public              # public | unlisted | private
  #       bluesky:
  #         enabled: true
  #         handle: yourname.bsky.social    # the full handle, with .bsky.social
  #         app_password: "..."             # app password, NOT account password
  module Syndication
    USER_AGENT = "abqari-syndication/#{Abqari::VERSION}"

    # Hard caps per network. Mastodon allows configurable instance max
    # (default 500) — we use the conservative default so the same
    # snippet posts cleanly to any instance. Bluesky enforces 300.
    LIMITS = { 'mastodon' => 500, 'bluesky' => 300 }.freeze

    def self.config_for(site)
      site.config['syndication'] || {}
    end

    def self.enabled?(site)
      cfg = config_for(site)
      cfg['enabled'] == true
    end

    # Network-specific config sub-hash with the per-network defaults
    # folded in. `enabled` defaults to true within a network block —
    # configuring it at all means you want it on, unless explicitly off.
    def self.network_config(site, name)
      (config_for(site)[name] || {}).merge('name' => name)
    end

    # Build-time orchestrator. Walks recent posts, dispatches to each
    # configured network, accumulates a per-post log.
    class Dispatcher
      def initialize(site)
        @site = site
        @cfg  = Syndication.config_for(site)
      end

      def enabled?
        Syndication.enabled?(@site)
      end

      def log_path
        File.join(@site.site_root, 'vendor', 'syndication', 'sent.yml')
      end

      def window_days
        @cfg.fetch('window_days', 14).to_i
      end

      def networks
        @networks ||= begin
          out = []
          out << Networks::Mastodon.new(@site) if network_enabled?('mastodon')
          out << Networks::Bluesky.new(@site)  if network_enabled?('bluesky')
          out
        end
      end

      def run
        return unless enabled?
        return if networks.empty?

        FileUtils.mkdir_p(File.dirname(log_path))
        log = load_log
        cutoff = Date.today - window_days
        syndicated = 0

        recent_posts(cutoff).each do |post|
          url = absolute_url_for(post)
          next if url.nil?

          networks.each do |net|
            next unless net.configured?
            key = "#{net.name}|#{url}"
            # Skip only when previously SENT successfully. Failures
            # are recorded for visibility but get retried on the next
            # build — a transient API outage shouldn't permanently
            # skip syndication for a post.
            prev = log['sent'][key]
            next if prev && prev['status'] == 'sent'

            text = Formatter.snippet_for(post, url, limit: LIMITS[net.name])
            result = net.post(text: text, url: url)
            if result
              log['sent'][key] = {
                'status' => 'sent',
                'at' => Time.now.utc.iso8601,
                'syndicated_url' => result
              }
              syndicated += 1
              Log.info "Syndicated to #{net.name}: #{url} → #{result}"
            else
              log['sent'][key] = {
                'status' => 'failed',
                'at' => Time.now.utc.iso8601
              }
            end
          end
        end

        save_log(log) if syndicated.positive? || log_dirty?(log)
        Log.info "Syndication: posted #{syndicated} new entry/entries" if syndicated.positive?
      end

      private

      def network_enabled?(name)
        cfg = @cfg[name]
        return false unless cfg.is_a?(Hash)
        cfg['enabled'] != false
      end

      def load_log
        @initial_log_keys = []
        return { 'sent' => {} } unless File.exist?(log_path)
        raw = YAML.safe_load_file(log_path, permitted_classes: Abqari::YAML_PERMITTED_CLASSES) || {}
        raw['sent'] ||= {}
        @initial_log_keys = raw['sent'].keys.sort
        raw
      end

      def save_log(log)
        File.write(log_path, YAML.dump(log))
      end

      def log_dirty?(log)
        @initial_log_keys ||= []
        log['sent'].keys.sort != @initial_log_keys
      end

      def recent_posts(cutoff)
        posts = @site.respond_to?(:posts) ? @site.posts : Array(@site.collection('posts'))
        posts.select do |p|
          next false unless p.respond_to?(:date) && p.date && p.date.to_date >= cutoff
          # Per-post opt-out: `syndicate: false` in frontmatter excludes
          # this post from POSSE entirely. Useful for personal/private
          # posts where the operator wants the canonical URL but no
          # social-network broadcast.
          fm = p.respond_to?(:frontmatter) ? p.frontmatter : {}
          fm['syndicate'] != false
        end
      end

      def absolute_url_for(page)
        base = canonical_site_url
        return nil if base.to_s.empty?
        "#{base.sub(%r{/\z}, '')}#{page.url}"
      end

      def canonical_site_url
        env_url = @site.config.dig('environments', @site.env.to_s, 'url') if @site.respond_to?(:env)
        env_url || @site.config['url']
      end
    end

    # Build the snippet posted to each network. Format:
    #   <title> — <description, truncated as needed> <url>
    #
    # The title + URL are non-negotiable; the description shrinks to
    # whatever fits inside the per-network character limit. Posts can
    # opt out per-frontmatter via `syndicate: false`, or supply their
    # own snippet via `syndication_text:`.
    module Formatter
      module_function

      def snippet_for(post, url, limit:)
        custom = post.respond_to?(:frontmatter) ? post.frontmatter['syndication_text'] : nil
        return clamp(custom.to_s, limit) if custom && !custom.to_s.empty?

        title = post.respond_to?(:title) ? post.title.to_s : ''
        description = post.respond_to?(:frontmatter) ? post.frontmatter['description'].to_s : ''

        # URL with a leading space. Reserve room for `<title>` (required)
        # and `<url>` (required); fill the remainder with description.
        url_part   = " #{url}"
        title_part = title.to_s.strip
        remaining  = limit - title_part.length - url_part.length - 3 # 3 chars for " — "

        if remaining > 20 && !description.empty?
          desc_part = description.strip
          desc_part = "#{desc_part[0, remaining - 1]}…" if desc_part.length > remaining
          "#{title_part} — #{desc_part}#{url_part}"
        else
          # Title alone (+ url) — no room for a description, or no
          # description supplied.
          base = "#{title_part}#{url_part}"
          base = clamp(base, limit)
          base
        end
      end

      def clamp(text, limit)
        text.length <= limit ? text : "#{text[0, limit - 1]}…"
      end
    end

    # Per-network adapters.
    module Networks
      # Base class — shared HTTP helpers, configuration lookup, common
      # logging. Subclasses define `name`, `configured?`, `post`.
      class Base
        def initialize(site)
          @site = site
          @cfg  = Syndication.network_config(site, name)
        end

        def name
          raise NotImplementedError
        end

        def configured?
          false
        end

        # Returns the URL of the syndicated post on success, nil on failure.
        def post(text:, url:)
          raise NotImplementedError
        end

        protected

        def http_json(uri, method:, headers: {}, body: nil)
          uri = URI(uri) unless uri.is_a?(URI)
          req = case method
                when :post then Net::HTTP::Post.new(uri.request_uri)
                when :get  then Net::HTTP::Get.new(uri.request_uri)
                else raise ArgumentError, "unsupported method: #{method}"
                end
          headers.each { |k, v| req[k] = v }
          req['User-Agent'] = USER_AGENT
          req.body = body if body

          Net::HTTP.start(uri.host, uri.port,
                          use_ssl: uri.scheme == 'https',
                          open_timeout: 5, read_timeout: 15) do |http|
            res = http.request(req)
            return [res.code.to_i, parse_json(res.body)]
          end
        rescue StandardError => e
          Log.warn "#{name} request failed (#{uri}): #{e.class}: #{e.message}"
          [nil, nil]
        end

        def parse_json(body)
          JSON.parse(body.to_s)
        rescue JSON::ParserError
          nil
        end
      end

      # Mastodon — uses the standard API. `access_token` is a per-user
      # OAuth token; in the Mastodon UI: Preferences → Development →
      # New Application (give it `write:statuses` scope).
      class Mastodon < Base
        def name
          'mastodon'
        end

        def configured?
          !instance_url.to_s.empty? && !token.to_s.empty?
        end

        def post(text:, url:)
          uri = URI("#{instance_url.sub(%r{/\z}, '')}/api/v1/statuses")
          body = URI.encode_www_form(
            status: text,
            visibility: visibility
          )
          status, payload = http_json(uri,
                                      method: :post,
                                      headers: {
                                        'Authorization' => "Bearer #{token}",
                                        'Content-Type'  => 'application/x-www-form-urlencoded'
                                      },
                                      body: body)
          return nil unless status&.between?(200, 299) && payload
          payload['url']
        end

        private

        def instance_url
          @cfg['instance'].to_s
        end

        def token
          @cfg['access_token'].to_s
        end

        def visibility
          @cfg.fetch('visibility', 'public').to_s
        end
      end

      # Bluesky — uses AT Protocol's `createSession` (login with handle
      # + app password) then `createRecord` to post. App passwords are
      # generated from the Bluesky UI (Settings → App Passwords) and
      # are distinct from the account password.
      class Bluesky < Base
        SERVICE_HOST = 'bsky.social'

        def name
          'bluesky'
        end

        def configured?
          !handle.to_s.empty? && !app_password.to_s.empty?
        end

        def post(text:, url:)
          session = create_session
          return nil unless session

          # Bluesky requires facets to be set explicitly for embedded
          # links; without them the URL renders as plain text but
          # remains visible. We pass it as plain text for simplicity —
          # Bluesky's client auto-linkifies bare URLs in display.
          uri = URI("https://#{SERVICE_HOST}/xrpc/com.atproto.repo.createRecord")
          body = JSON.dump(
            repo: session['did'],
            collection: 'app.bsky.feed.post',
            record: {
              '$type'     => 'app.bsky.feed.post',
              text:       text,
              createdAt:  Time.now.utc.iso8601,
              facets:     link_facets(text, url)
            }
          )
          status, payload = http_json(uri,
                                      method: :post,
                                      headers: {
                                        'Authorization' => "Bearer #{session['accessJwt']}",
                                        'Content-Type'  => 'application/json'
                                      },
                                      body: body)
          return nil unless status&.between?(200, 299) && payload

          # createRecord returns `{ uri: 'at://...', cid: '...' }`. Build
          # the web URL from the at-URI: at://<did>/app.bsky.feed.post/<rkey>
          # → https://bsky.app/profile/<handle>/post/<rkey>.
          rkey = payload['uri'].to_s.split('/').last
          rkey.empty? ? payload['uri'] : "https://bsky.app/profile/#{handle}/post/#{rkey}"
        end

        private

        def handle
          @cfg['handle'].to_s
        end

        def app_password
          @cfg['app_password'].to_s
        end

        def create_session
          uri = URI("https://#{SERVICE_HOST}/xrpc/com.atproto.server.createSession")
          body = JSON.dump(identifier: handle, password: app_password)
          status, payload = http_json(uri,
                                      method: :post,
                                      headers: { 'Content-Type' => 'application/json' },
                                      body: body)
          return nil unless status&.between?(200, 299)
          payload
        end

        # Bluesky's text-format spec requires byte offsets, not character
        # offsets, for facets (because the protocol passes UTF-8 byte
        # streams). Find the URL in the text and emit a `link` facet
        # spanning its byte range so the post displays it as a clickable
        # link rather than a plain string of characters.
        def link_facets(text, url)
          bytes = text.b
          target = url.b
          start = bytes.index(target)
          return [] unless start
          finish = start + target.bytesize
          [{
            index: { byteStart: start, byteEnd: finish },
            features: [{ '$type' => 'app.bsky.richtext.facet#link', uri: url }]
          }]
        end
      end
    end
  end
end

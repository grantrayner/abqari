# frozen_string_literal: true

require 'net/http'
require 'json'
require 'openssl'
require 'yaml'
require 'fileutils'
require 'set'

module Abqari
  # Folio integration. Folio (foliobooks.app) is a publishing/storefront app
  # that exposes a public read-only JSON API for embedding book metadata on
  # author websites. This class fetches that data at build time and stashes
  # it in `site.data` keyed by slug, so layouts can render books / bundles /
  # series without hitting Folio at runtime — and the visitor never makes a
  # request to Folio either.
  #
  # API endpoints used:
  #   GET /api/v1/authors/:slug/publications.json
  #   GET /api/v1/authors/:slug/bundles.json
  #   GET /api/v1/authors/:slug/series.json
  #
  # Cache-first design (matches the Jekyll plugin in apps/memoirs):
  #   1. Fresh build, network OK     → 200 → write cache → use it
  #   2. Subsequent build, no change → 304 → use cache
  #   3. Folio briefly unreachable   → use cache, log warning
  #   4. First build, no network     → empty data; layouts fall back to front matter
  #
  # Cache files live in `vendor/folio/` (gitignored) so each CI runner
  # rebuilds its own cache and there's no version-control churn.
  class Folio
    OPEN_TIMEOUT = 5
    READ_TIMEOUT = 10
    # 8 MB is enormously generous for Folio's JSON shape — a prolific
    # author with hundreds of titles plus full metadata still fits well
    # under 1 MB. The cap exists so a compromised or misconfigured
    # upstream can't exhaust the CI runner's memory.
    MAX_RESPONSE_BYTES = 8 * 1024 * 1024
    USER_AGENT = "abqari-folio-fetcher/#{Abqari::VERSION}"

    def initialize(site)
      @site = site
      @cfg  = site.config['folio'] || {}
    end

    def enabled?
      base_url && author_slug
    end

    def base_url
      @cfg['base_url']
    end

    def author_slug
      @cfg['author_slug']
    end

    def config
      @cfg
    end

    def cache_dir
      # Folio cache is site-specific (different sites pull different
      # publications), so it lives under the site root.
      File.join(@site.site_root, 'vendor', 'folio')
    end

    # Fetches publications + bundles, derives series, populates site.data.
    # Called from Site#build before page rendering so layouts can read
    # site.data['folio_publications'] etc. when they render.
    #
    # Slug filtering. An author may have multiple imprints under one Folio
    # account (e.g. fiction + non-fiction) but want a given site to show
    # only some. Configure either of:
    #
    #   folio:
    #     include_slugs: [memoirs-of-an-assassin, the-russia-assignment]
    #     exclude_slugs: [some-other-book]
    #
    # `include_slugs` (when set) wins — only those publications survive,
    # and only the bundles/series that reference them are kept. Otherwise
    # `exclude_slugs` removes the listed publications. Both default to
    # empty (all publications kept) so existing sites are unaffected.
    def fetch
      return unless enabled?

      FileUtils.mkdir_p(cache_dir)

      pubs    = filter_publications(fetch_endpoint('publications'))
      bundles = filter_bundles(fetch_endpoint('bundles'), pubs)
      series  = filter_series(fetch_endpoint('series'), pubs)

      @site.data['folio_publications'] = index_by_slug(pubs)
      @site.data['folio_bundles']      = index_by_slug(bundles)
      @site.data['folio_series']       = index_by_slug(series)

      pubs_count    = @site.data['folio_publications'].size
      bundles_count = @site.data['folio_bundles'].size
      series_count  = @site.data['folio_series'].size
      Log.info "Folio: loaded #{pubs_count} publication(s), #{bundles_count} bundle(s), #{series_count} series"
    end

    private

    # Apply include/exclude slug filters to the fetched publications list.
    # `include_slugs` (when present) is treated as the only-keep set;
    # `exclude_slugs` removes named slugs. Both arrays of strings.
    def filter_publications(pubs)
      include = Array(config['include_slugs']).map(&:to_s)
      exclude = Array(config['exclude_slugs']).map(&:to_s)

      pubs = pubs.select { |p| include.include?(p['slug'].to_s) } if include.any?
      pubs = pubs.reject { |p| exclude.include?(p['slug'].to_s) } if exclude.any?
      pubs
    end

    # Drop bundles whose `publications` array would be empty after filtering
    # (otherwise we ship empty-bundle pages). Bundles that retain at least
    # one publication keep all their original publications array — we
    # don't surgically rewrite the bundle's contents.
    def filter_bundles(bundles, kept_pubs)
      kept_slugs = kept_pubs.map { |p| p['slug'].to_s }.to_set
      bundles.select do |b|
        Array(b['publications']).any? { |p| kept_slugs.include?(p['slug'].to_s) }
      end
    end

    # Drop series with zero remaining publications.
    def filter_series(series_list, kept_pubs)
      kept_slugs = kept_pubs.map { |p| p['slug'].to_s }.to_set
      series_list.select do |s|
        Array(s['publications']).any? { |p| kept_slugs.include?(p['slug'].to_s) }
      end
    end

    # Endpoint name → list-payload key mapping (matches Folio's API response shape):
    ENDPOINTS = {
      'publications' => 'publications',
      'bundles'      => 'bundles',
      'series'       => 'series'
    }.freeze

    def fetch_endpoint(name)
      cache_path = File.join(cache_dir, "#{name}.yml")
      etag_path  = File.join(cache_dir, "etag-#{name}")
      cached     = File.exist?(cache_path) ? (YAML.safe_load_file(cache_path, permitted_classes: Abqari::YAML_PERMITTED_CLASSES) || {}) : {}
      etag       = File.exist?(etag_path) ? File.read(etag_path).strip : nil

      uri = URI("#{base_url.sub(%r{/\z}, '')}/api/v1/authors/#{author_slug}/#{name}.json")
      headers = { 'Accept' => 'application/json', 'User-Agent' => USER_AGENT }
      headers['If-None-Match'] = etag if etag

      # HttpSafe streams the body, caps it at MAX_RESPONSE_BYTES, and
      # applies timeouts. TooLargeError bubbles to the rescue below so
      # we fall back to cached data rather than crashing the build.
      res = HttpSafe.get(uri,
                         headers: headers,
                         max_bytes: MAX_RESPONSE_BYTES,
                         open_timeout: OPEN_TIMEOUT,
                         read_timeout: READ_TIMEOUT)

      case res.code
      when '304'
        cached[ENDPOINTS[name]] || []
      when '200'
        body = JSON.parse(res.body)
        items = body[ENDPOINTS[name]] || []
        File.write(cache_path, { ENDPOINTS[name] => items }.to_yaml)
        File.write(etag_path, res['etag'].to_s) if res['etag']
        items
      else
        Log.warn "Folio: unexpected HTTP #{res.code} from /#{name} — using cached data"
        cached[ENDPOINTS[name]] || []
      end
    # Narrowed rescue list: the expected failure modes for a Folio
    # fetch are network (timeouts, DNS, TCP/TLS), an oversized
    # response, malformed JSON, or filesystem failure writing the
    # cache. Anything else (a Ruby bug, a programming error) should
    # surface so we don't silently mask it as "Folio unreachable."
    # Backtrace logged at debug so `ABQARI_LOG=debug` surfaces the
    # full stack when triaging upstream issues.
    rescue Net::OpenTimeout, Net::ReadTimeout, Errno::ECONNRESET, Errno::ECONNREFUSED,
           Errno::EHOSTUNREACH, Errno::ENETUNREACH, SocketError, IOError,
           OpenSSL::SSL::SSLError, HttpSafe::TooLargeError,
           JSON::ParserError, Psych::SyntaxError, SystemCallError => e
      Log.warn "Folio: fetch /#{name} failed (#{e.class}: #{e.message}) — using cached data"
      e.backtrace&.first(5)&.each { |line| Log.debug "  #{line}" }
      cached[ENDPOINTS[name]] || []
    end

    def index_by_slug(items)
      items.each_with_object({}) { |item, h| h[item['slug']] = item if item['slug'] }
    end
  end
end

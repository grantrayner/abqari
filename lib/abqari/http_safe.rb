# frozen_string_literal: true

require 'net/http'
require 'uri'
require 'socket'  # Addrinfo — the resolver the SSRF guard shares with Net::HTTP
require 'ipaddr'

module Abqari
  # Bounded HTTP GET helper for build-time fetches.
  #
  # The engine pulls data from third parties (Folio publications, Google
  # Fonts CSS + woff2 files). A misbehaving or compromised upstream that
  # streamed a multi-gigabyte body would otherwise pin a CI runner's
  # memory and disk. `HttpSafe.get` streams the body, caps the total
  # bytes, and applies open/read timeouts to every call.
  #
  # Returns an `HttpSafe::Response` (not a Net::HTTPResponse) — callers
  # use `.code`, `.success?`, `.body`, `.[]` for header lookup. Headers
  # are downcased on lookup so `res['ETag']` and `res['etag']` are the
  # same key.
  #
  # On size overflow: raises `HttpSafe::TooLargeError`. Callers either
  # let it bubble (Folio falls through to its rescue → cached data) or
  # surface it as a build failure.
  module HttpSafe
    class TooLargeError < StandardError; end

    DEFAULT_MAX_BYTES    = 8 * 1024 * 1024 # 8 MB — generous for JSON / CSS / single woff2
    DEFAULT_OPEN_TIMEOUT = 5
    DEFAULT_READ_TIMEOUT = 10

    Response = Struct.new(:code, :message, :headers, :body) do
      # Case-insensitive header lookup — matches Net::HTTPResponse#[] semantics
      # so call sites don't have to remember which casing the server returned.
      def [](name)
        headers[name.to_s.downcase]
      end

      def success?
        code.to_i.between?(200, 299)
      end
    end

    module_function

    # Fetch `uri` with bounded body size and timeouts. Headers are a
    # plain { 'Name' => 'value' } hash.
    def get(uri,
            headers: {},
            max_bytes: DEFAULT_MAX_BYTES,
            open_timeout: DEFAULT_OPEN_TIMEOUT,
            read_timeout: DEFAULT_READ_TIMEOUT,
            block_private: false)
      request(:get, uri,
              headers: headers,
              max_bytes: max_bytes,
              open_timeout: open_timeout,
              read_timeout: read_timeout,
              block_private: block_private)
    end

    # General-purpose bounded request — same streaming + cap +
    # timeouts as `get`, parameterised by HTTP method and optional
    # body. Used by the POSSE adapters (Mastodon/Bluesky POST) and
    # the webmention sender (POST + HEAD) so a misbehaving upstream
    # can't stream gigabytes into the build process's memory.
    #
    # Supported methods: :get, :head, :post. POSTs take a `body:`
    # (string already-encoded — form or JSON) and a Content-Type in
    # `headers:`.
    def request(method, uri,
                headers: {},
                body: nil,
                max_bytes: DEFAULT_MAX_BYTES,
                open_timeout: DEFAULT_OPEN_TIMEOUT,
                read_timeout: DEFAULT_READ_TIMEOUT,
                block_private: false)
      uri = URI(uri) unless uri.is_a?(URI)

      # Never transmit a bearer token in cleartext. Callers that attach
      # an Authorization header (webmention.io, POSSE adapters) must use
      # https — an http:// endpoint would leak the token to any on-path
      # observer / proxy log.
      if headers.keys.any? { |k| k.to_s.casecmp?('authorization') } && uri.scheme != 'https'
        raise ArgumentError, "refusing to send an Authorization header over #{uri.scheme}:// (cleartext) to #{uri.host}"
      end

      # SSRF guard for untrusted destinations (importer image URLs from a
      # third-party export). Best-effort: resolve the host and refuse
      # private / loopback / link-local addresses so a hostile export
      # can't make the build fetch `http://169.254.169.254/…` or an
      # internal service. (DNS-rebinding TOCTOU remains — acceptable for
      # a local build tool.)
      assert_public_host!(uri) if block_private

      req = build_request(method, uri, body)
      headers.each { |k, v| req[k] = v.to_s }

      Net::HTTP.start(uri.host, uri.port,
                      use_ssl: uri.scheme == 'https',
                      open_timeout: open_timeout,
                      read_timeout: read_timeout) do |http|
        http.request(req) do |res|
          response_body = method == :head ? '' : read_capped_body(res, max_bytes, uri)
          return Response.new(res.code, res.message, flatten_headers(res), response_body)
        end
      end
    end

    def build_request(method, uri, body)
      case method
      when :get  then Net::HTTP::Get.new(uri.request_uri)
      when :head then Net::HTTP::Head.new(uri.request_uri)
      when :post
        req = Net::HTTP::Post.new(uri.request_uri)
        req.body = body if body
        req
      else
        raise ArgumentError, "unsupported HTTP method: #{method.inspect}"
      end
    end

    def read_capped_body(res, max_bytes, uri)
      body = String.new(encoding: Encoding::ASCII_8BIT)
      res.read_body do |chunk|
        body << chunk
        if body.bytesize > max_bytes
          raise TooLargeError,
                "response from #{uri.host} exceeded cap (#{max_bytes} bytes)"
        end
      end
      body
    end

    def flatten_headers(res)
      headers = {}
      res.each_header { |name, value| headers[name.downcase] = value }
      headers
    end

    class BlockedHostError < StandardError; end

    # Ranges that `IPAddr#loopback?` / `#private?` / `#link_local?` do
    # NOT already cover, but that a build must never reach.
    #
    # `0.0.0.0/8` is the one that matters most: `0.0.0.0` is not
    # loopback, private or link-local by any of those predicates, yet
    # connecting to it reaches localhost on Linux and macOS — so it was
    # a one-token bypass of the whole guard.
    BLOCKED_RANGES = [
      IPAddr.new('0.0.0.0/8'),     # "this network"; 0.0.0.0 reaches localhost
      IPAddr.new('100.64.0.0/10'), # CGNAT — carrier-internal, not public
      IPAddr.new('192.0.0.0/24'),  # IETF protocol assignments
      IPAddr.new('198.18.0.0/15'), # benchmarking
      IPAddr.new('224.0.0.0/4'),   # multicast
      IPAddr.new('240.0.0.0/4'),   # reserved, includes 255.255.255.255
      IPAddr.new('::/128'),        # unspecified
      IPAddr.new('ff00::/8')       # multicast
    ].freeze

    # Raise unless every address `uri.host` resolves to is public.
    #
    # Resolution goes through `Addrinfo.getaddrinfo` — deliberately the
    # same resolver `Net::HTTP` will use to open the socket. The previous
    # implementation used `Resolv.getaddresses` and fell back to parsing
    # the host with `IPAddr`, which created a gap between what the guard
    # checked and what the connection actually did: `Resolv` returns
    # nothing for `http://2130706433/`, `IPAddr.new` rejects it, so the
    # guard skipped the host — and then `getaddrinfo` expanded it to
    # 127.0.0.1 and connected. The same held for `0x7f000001`,
    # `017700000001`, `127.1` and `127.0.1`; every legacy `inet_aton`
    # form was a bypass. Asking the connecting resolver removes that
    # whole class of mismatch rather than enumerating the forms.
    #
    # A host that doesn't resolve here won't connect there either (same
    # resolver), so an empty result falls through and lets the request
    # fail with its natural "no such host" error rather than a
    # misleading "refusing to fetch".
    #
    # DNS-rebinding TOCTOU remains — the address could change between
    # this check and the connect. Acceptable for a local build tool.
    def assert_public_host!(uri)
      host = uri.host.to_s
      # `URI` keeps the brackets on an IPv6 literal; the resolver
      # wants them off.
      probe = host.delete_prefix('[').delete_suffix(']')

      addresses =
        begin
          Addrinfo.getaddrinfo(probe, nil, nil, :STREAM).map(&:ip_address).uniq
        rescue StandardError
          []
        end
      return if addresses.empty?

      addresses.each do |addr|
        ip = begin
          IPAddr.new(addr)
        rescue StandardError
          next
        end
        next if public_ip?(ip)

        raise BlockedHostError,
              "refusing to fetch #{host}: resolves to non-public address #{addr}"
      end
    end

    def public_ip?(ip)
      # `::ffff:127.0.0.1` is loopback wearing an IPv6 hat — unwrap it
      # so the IPv4 rules apply rather than the (much narrower) v6 ones.
      ip = ip.native if ip.ipv4_mapped?

      return false if ip.loopback? || ip.private? || ip.link_local?

      BLOCKED_RANGES.none? { |range| range.include?(ip) }
    rescue StandardError
      # An address we can't reason about is not one we should fetch.
      false
    end
  end
end

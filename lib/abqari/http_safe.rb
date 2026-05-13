# frozen_string_literal: true

require 'net/http'
require 'uri'

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
            read_timeout: DEFAULT_READ_TIMEOUT)
      uri = URI(uri) unless uri.is_a?(URI)
      req = Net::HTTP::Get.new(uri.request_uri)
      headers.each { |k, v| req[k] = v.to_s }

      Net::HTTP.start(uri.host, uri.port,
                      use_ssl: uri.scheme == 'https',
                      open_timeout: open_timeout,
                      read_timeout: read_timeout) do |http|
        http.request(req) do |res|
          body = read_capped_body(res, max_bytes, uri)
          return Response.new(res.code, res.message, flatten_headers(res), body)
        end
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
  end
end

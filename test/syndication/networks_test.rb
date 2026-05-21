# frozen_string_literal: true

require_relative '../test_helper'

# Mastodon + Bluesky adapter tests. We mock Net::HTTP at the
# request-execution level so we can verify the request shape (URLs,
# headers, body) and inject deterministic responses without booting
# real social-network APIs.
class SyndicationNetworksTest < Minitest::Test
  Mastodon = Abqari::Syndication::Networks::Mastodon
  Bluesky  = Abqari::Syndication::Networks::Bluesky

  # Capture-and-respond stub installed for the duration of a block.
  # Records every Net::HTTP request issued, returns the response the
  # block supplies for each call by request_uri.
  def with_stubbed_http(responder)
    captured = []
    require 'net/http'

    orig_start = Net::HTTP.method(:start)
    Net::HTTP.singleton_class.send(:define_method, :start) do |host, port = nil, *rest, &block|
      stub = Class.new do
        define_method(:request) do |req|
          captured << { host: host, port: port, method: req.method, path: req.path,
                         headers: req.each_header.to_h, body: req.body }
          status, body = responder.call(req)
          res_class = Net::HTTPResponse::CODE_TO_OBJ[status.to_s] || Net::HTTPOK
          # Net::HTTPResponse subclasses don't all accept the same args
          # cleanly; easier to wrap our own struct that quacks like one.
          Struct.new(:code, :body).new(status.to_s, body)
        end
      end.new
      block.call(stub)
    end

    yield captured
  ensure
    Net::HTTP.singleton_class.send(:remove_method, :start)
    Net::HTTP.singleton_class.send(:define_method, :start, orig_start)
  end

  def site_with(config)
    Struct.new(:config).new(config)
  end

  # ---------- Mastodon ---------------------------------------------------

  def test_mastodon_not_configured_when_token_missing
    net = Mastodon.new(site_with({ 'syndication' => { 'mastodon' => {
      'instance' => 'https://mastodon.social' } } }))
    refute net.configured?
  end

  def test_mastodon_not_configured_when_instance_missing
    net = Mastodon.new(site_with({ 'syndication' => { 'mastodon' => {
      'access_token' => 'tk' } } }))
    refute net.configured?
  end

  def test_mastodon_posts_to_statuses_endpoint_and_returns_url
    net = Mastodon.new(site_with({ 'syndication' => { 'mastodon' => {
      'instance' => 'https://mastodon.social',
      'access_token' => 'tk',
      'visibility' => 'public' } } }))

    result = with_stubbed_http(->(_req) {
      [200, JSON.dump('url' => 'https://mastodon.social/@me/12345')]
    }) do |captured|
      out = net.post(text: 'Hi there https://example.com/p/', url: 'https://example.com/p/')
      assert_equal 'https://mastodon.social/@me/12345', out

      req = captured.last
      assert_equal 'mastodon.social', req[:host]
      assert_equal '/api/v1/statuses', req[:path]
      assert_includes req[:headers]['authorization'].to_s, 'Bearer tk'
      # URI.encode_www_form uses form-data encoding (space → '+').
      assert_match(/status=Hi\+there/,  req[:body])
      assert_match(/visibility=public/, req[:body])
      out
    end
    assert_equal 'https://mastodon.social/@me/12345', result
  end

  def test_mastodon_returns_nil_on_non_2xx
    net = Mastodon.new(site_with({ 'syndication' => { 'mastodon' => {
      'instance' => 'https://mastodon.social',
      'access_token' => 'tk' } } }))

    with_stubbed_http(->(_req) { [422, '{"error":"oops"}'] }) do |_|
      assert_nil net.post(text: 'x', url: 'https://example.com/p/')
    end
  end

  # ---------- Bluesky ----------------------------------------------------

  def test_bluesky_not_configured_when_app_password_missing
    net = Bluesky.new(site_with({ 'syndication' => { 'bluesky' => {
      'handle' => 'me.bsky.social' } } }))
    refute net.configured?
  end

  def test_bluesky_creates_session_then_record_and_returns_post_url
    net = Bluesky.new(site_with({ 'syndication' => { 'bluesky' => {
      'handle' => 'me.bsky.social',
      'app_password' => 'pw' } } }))

    responder = ->(req) {
      if req.path.include?('createSession')
        [200, JSON.dump('did' => 'did:plc:xyz', 'accessJwt' => 'jwt-token')]
      else
        [200, JSON.dump('uri' => 'at://did:plc:xyz/app.bsky.feed.post/abc123',
                        'cid' => 'cid-xxx')]
      end
    }

    out = with_stubbed_http(responder) do |captured|
      url = net.post(text: 'Hello https://example.com/p/', url: 'https://example.com/p/')

      # 1st: createSession; 2nd: createRecord
      assert_equal 2, captured.size
      assert captured.first[:path].include?('createSession')
      assert captured.last[:path].include?('createRecord')

      auth_header = captured.last[:headers]['authorization'].to_s
      assert_includes auth_header, 'Bearer jwt-token'

      body = JSON.parse(captured.last[:body])
      assert_equal 'did:plc:xyz',           body['repo']
      assert_equal 'app.bsky.feed.post',    body['collection']
      assert_includes body['record']['text'], 'Hello'
      assert_kind_of Array, body['record']['facets'], 'link facets included'

      url
    end

    assert_equal 'https://bsky.app/profile/me.bsky.social/post/abc123', out
  end

  def test_bluesky_returns_nil_when_session_creation_fails
    net = Bluesky.new(site_with({ 'syndication' => { 'bluesky' => {
      'handle' => 'me.bsky.social',
      'app_password' => 'wrongpw' } } }))

    with_stubbed_http(->(_req) { [401, '{"error":"AuthenticationRequired"}'] }) do |_|
      assert_nil net.post(text: 'x', url: 'https://example.com/p/')
    end
  end

  def test_bluesky_link_facet_uses_byte_offsets
    net = Bluesky.new(site_with({ 'syndication' => { 'bluesky' => {
      'handle' => 'h.bsky.social', 'app_password' => 'pw' } } }))

    # Multi-byte characters before the URL — facet byte offsets must
    # account for UTF-8 byte length, not character length.
    text = 'café — https://example.com/p/'
    url  = 'https://example.com/p/'

    responder = ->(req) {
      if req.path.include?('createSession')
        [200, JSON.dump('did' => 'did:plc:x', 'accessJwt' => 'j')]
      else
        body = JSON.parse(req.body)
        facet = body['record']['facets'].first
        bytes = text.b
        assert_equal bytes.index(url.b), facet['index']['byteStart']
        assert_equal bytes.index(url.b) + url.bytesize, facet['index']['byteEnd']
        [200, JSON.dump('uri' => 'at://did:plc:x/app.bsky.feed.post/r1', 'cid' => 'c')]
      end
    }

    with_stubbed_http(responder) do |_|
      net.post(text: text, url: url)
    end
  end

  # When `syndication_text:` mentions the URL twice (e.g. "Read
  # more at #{url} — see #{url}"), the facet should span the LAST
  # occurrence — the trailing canonical URL the formatter appends.
  # The first-match form (`index`) facets the leading mention and
  # orphans the canonical, which Bluesky's client renders as a
  # half-linked dangling URL.
  def test_bluesky_link_facet_picks_last_url_occurrence_when_duplicated
    net = Bluesky.new(site_with({ 'syndication' => { 'bluesky' => {
      'handle' => 'h.bsky.social', 'app_password' => 'pw' } } }))

    url  = 'https://example.com/p/'
    text = "Read at #{url} — #{url}"

    responder = ->(req) {
      if req.path.include?('createSession')
        [200, JSON.dump('did' => 'did:plc:x', 'accessJwt' => 'j')]
      else
        body  = JSON.parse(req.body)
        facet = body['record']['facets'].first
        bytes = text.b
        assert_equal bytes.rindex(url.b), facet['index']['byteStart'],
                     'facet should span the rightmost (canonical) URL occurrence'
        assert_equal bytes.rindex(url.b) + url.bytesize, facet['index']['byteEnd']
        [200, JSON.dump('uri' => 'at://did:plc:x/app.bsky.feed.post/r1', 'cid' => 'c')]
      end
    }

    with_stubbed_http(responder) do |_|
      net.post(text: text, url: url)
    end
  end
end

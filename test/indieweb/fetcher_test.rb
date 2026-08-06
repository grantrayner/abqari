# frozen_string_literal: true

require_relative '../test_helper'
require 'tmpdir'
require 'json'

# Fetcher — webmention.io polling, ETag-based caching, and the
# per-URL grouping the post layout queries. HTTP is stubbed via a
# fake `HttpSafe.get` so these tests run offline and deterministically.
class IndiewebFetcherTest < Minitest::Test
  Fetcher = Abqari::Indieweb::Fetcher

  def setup
    @site_root = Dir.mktmpdir('abqari-iw-fetcher-test-')
    @site = Struct.new(:config, :data, :site_root).new(
      { 'indieweb' => { 'enabled' => true, 'domain' => 'example.com',
                        'webmention_io_token' => 'tk' } },
      {},
      @site_root
    )
  end

  def teardown
    FileUtils.rm_rf(@site_root)
    restore_http_safe!
  end

  # Patch HttpSafe.get to a deterministic stub. Captures the request
  # so tests can assert what was sent (ETag forwarding, URL shape).
  def stub_http_safe(response:)
    @captured_requests = []
    Abqari::HttpSafe.singleton_class.send(:alias_method, :__orig_get, :get) unless Abqari::HttpSafe.respond_to?(:__orig_get)
    Abqari::HttpSafe.singleton_class.send(:define_method, :get) do |uri, headers: {}, **|
      $http_safe_capture << { uri: uri.to_s, headers: headers }
      $http_safe_response
    end
    $http_safe_capture = @captured_requests
    $http_safe_response = response
  end

  def restore_http_safe!
    return unless Abqari::HttpSafe.respond_to?(:__orig_get)
    Abqari::HttpSafe.singleton_class.send(:remove_method, :get)
    Abqari::HttpSafe.singleton_class.send(:alias_method, :get, :__orig_get)
    Abqari::HttpSafe.singleton_class.send(:remove_method, :__orig_get)
  end

  def fake_response(status:, body: '', etag: nil)
    headers = etag ? { 'etag' => etag } : {}
    Abqari::HttpSafe::Response.new(status.to_s, 'OK', headers, body)
  end

  def jf2_payload
    {
      'name' => 'Webmentions',
      'children' => [
        { 'wm-target' => 'https://example.com/posts/foo/',
          'wm-property' => 'in-reply-to',
          'author' => { 'name' => 'Reply Author', 'url' => 'https://reply.example/' },
          'content' => { 'text' => 'Great post!' },
          'published' => '2024-03-15T10:00:00Z',
          'url' => 'https://reply.example/post' },
        { 'wm-target' => 'https://example.com/posts/foo',  # no trailing slash variant
          'wm-property' => 'like-of',
          'author' => { 'name' => 'Liker', 'photo' => 'https://liker.example/me.jpg' },
          'published' => '2024-03-14T09:00:00Z' },
        { 'wm-target' => 'https://example.com/posts/bar/',
          'wm-property' => 'mention-of',
          'author' => { 'name' => 'Other' },
          'published' => '2024-03-10T12:00:00Z' }
      ]
    }
  end

  def test_disabled_when_no_token
    @site.config['indieweb']['webmention_io_token'] = ''
    Fetcher.new(@site).fetch
    assert_equal({}, @site.data['webmentions'])
  end

  def test_fetches_and_indexes_by_target_url
    stub_http_safe(response: fake_response(status: 200,
                                            body: JSON.dump(jf2_payload),
                                            etag: 'W/"abc"'))
    Fetcher.new(@site).fetch

    # Two distinct targets after normalisation: /posts/foo/ and /posts/bar/
    assert_equal 2, @site.data['webmentions'].size
    assert_equal 2, @site.data['webmentions']['/posts/foo/'].size,
                 'both variant URLs for foo should normalise to /posts/foo/'
    assert_equal 1, @site.data['webmentions']['/posts/bar/'].size
  end

  def test_caches_response_and_etag_to_disk
    stub_http_safe(response: fake_response(status: 200,
                                            body: JSON.dump(jf2_payload),
                                            etag: 'W/"abc"'))
    f = Fetcher.new(@site)
    f.fetch
    assert File.exist?(f.cache_path), 'cache file written'
    assert File.exist?(f.etag_path),  'etag file written'
    assert_equal 'W/"abc"', File.read(f.etag_path)
  end

  def test_forwards_etag_on_subsequent_fetch
    # First fetch — populate cache + etag.
    stub_http_safe(response: fake_response(status: 200,
                                            body: JSON.dump(jf2_payload),
                                            etag: 'W/"abc"'))
    Fetcher.new(@site).fetch

    # Second fetch — should send If-None-Match: W/"abc" and accept 304.
    stub_http_safe(response: fake_response(status: 304))
    Fetcher.new(@site).fetch

    assert @captured_requests.last[:headers]['If-None-Match'] == 'W/"abc"',
           'expected If-None-Match header on second request'
    # Cached data still reachable.
    refute_empty @site.data['webmentions']['/posts/foo/']
  end

  def test_non_200_falls_back_to_cached_data
    stub_http_safe(response: fake_response(status: 200,
                                            body: JSON.dump(jf2_payload),
                                            etag: nil))
    Fetcher.new(@site).fetch
    cached_size = @site.data['webmentions'].size

    stub_http_safe(response: fake_response(status: 503))
    Fetcher.new(@site).fetch
    assert_equal cached_size, @site.data['webmentions'].size,
                 'should still expose cached mentions when upstream errors'
  end

  def test_mentions_sorted_newest_first_per_target
    stub_http_safe(response: fake_response(status: 200,
                                            body: JSON.dump(jf2_payload),
                                            etag: nil))
    Fetcher.new(@site).fetch
    list = @site.data['webmentions']['/posts/foo/']
    dates = list.map { |m| m['published'] }
    assert_equal dates.sort.reverse, dates, 'mentions should be sorted newest first'
  end

  # --- URL sanitisation ----------------------------------------------
  #
  # Webmention payloads are attacker-controlled: anyone can send one, and
  # the author URL, avatar and source URL are copied from the SENDER's
  # markup into `href`/`src` attributes by `partials/_webmentions`.
  # Erubi escapes the values but not their scheme, so `javascript:...`
  # would survive escaping and stay a working link. The fetcher scrubs
  # every URL to an absolute http(s) URL before the data is exposed.

  def hostile_payload(author_url: nil, photo: nil, url: nil)
    {
      'children' => [
        { 'wm-target' => 'https://example.com/posts/foo/',
          'wm-property' => 'in-reply-to',
          'author' => { 'name' => 'Attacker', 'url' => author_url, 'photo' => photo },
          'published' => '2024-03-15T10:00:00Z',
          'url' => url }
      ]
    }
  end

  def fetch_hostile(**kwargs)
    stub_http_safe(response: fake_response(status: 200,
                                            body: JSON.dump(hostile_payload(**kwargs))))
    Fetcher.new(@site).fetch
    @site.data['webmentions']['/posts/foo/'].first
  end

  def test_javascript_scheme_urls_are_dropped
    mention = fetch_hostile(
      author_url: "javascript:fetch('//evil.example')",
      photo: 'javascript:alert(1)',
      url: 'javascript:alert(2)'
    )

    assert_nil mention['author']['url']
    assert_nil mention['author']['photo']
    assert_nil mention['url']
  end

  def test_data_and_vbscript_scheme_urls_are_dropped
    mention = fetch_hostile(
      author_url: 'vbscript:msgbox(1)',
      photo: 'data:text/html;base64,PHNjcmlwdD5hbGVydCgxKTwvc2NyaXB0Pg=='
    )

    assert_nil mention['author']['url']
    assert_nil mention['author']['photo']
  end

  def test_protocol_relative_and_same_origin_urls_are_dropped
    # `//evil.example/x` inherits the page's scheme — a cross-origin
    # link wearing a same-origin costume. A bare path is a stranger's
    # "profile" pointing into the reader's own site.
    mention = fetch_hostile(author_url: '//evil.example/x', photo: '/admin/secret.png')

    assert_nil mention['author']['url']
    assert_nil mention['author']['photo']
  end

  def test_mailto_is_dropped_from_third_party_urls
    # Valid for site-authored content, but a remote profile link that
    # silently opens a mail client is not what the reader expects.
    mention = fetch_hostile(author_url: 'mailto:someone@example.com')
    assert_nil mention['author']['url']
  end

  def test_legitimate_http_urls_survive_untouched
    mention = fetch_hostile(
      author_url: 'https://reply.example/profile?a=1&b=2',
      photo: 'http://reply.example/me.jpg',
      url: 'https://reply.example/post#comment'
    )

    assert_equal 'https://reply.example/profile?a=1&b=2', mention['author']['url']
    assert_equal 'http://reply.example/me.jpg', mention['author']['photo']
    assert_equal 'https://reply.example/post#comment', mention['url']
  end

  def test_sanitisation_preserves_non_url_fields
    # Scrubbing URLs must not drop the rest of the mention — the name
    # and body still render (escaped) and the grouping key still works.
    mention = fetch_hostile(author_url: 'javascript:alert(1)')

    assert_equal 'Attacker', mention['author']['name']
    assert_equal 'in-reply-to', mention['wm-property']
    assert_equal '2024-03-15T10:00:00Z', mention['published']
  end

  def test_sanitisation_applies_to_cached_payloads_too
    # A cache written by an older version holds raw upstream data, so
    # the scrub has to happen on load, not only on fetch.
    stub_http_safe(response: fake_response(status: 200,
                                            body: JSON.dump(hostile_payload(
                                                              author_url: 'javascript:alert(1)'
                                                            ))))
    Fetcher.new(@site).fetch

    # Second run: upstream is down, so the on-disk cache is what renders.
    stub_http_safe(response: fake_response(status: 503))
    Fetcher.new(@site).fetch

    mention = @site.data['webmentions']['/posts/foo/'].first
    assert_nil mention['author']['url']
  end
end

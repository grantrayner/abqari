# frozen_string_literal: true

require_relative 'test_helper'
require 'webrick'
require 'socket'

# Tests for HttpSafe — the bounded HTTP GET helper used by Folio and
# FontPipeline. Spins up a local WEBrick server on a random port so we
# can prove the size cap actually fires, the headers come back case-
# insensitive, and the success? check matches Net::HTTPSuccess.
class HttpSafeTest < Minitest::Test
  def setup
    @server = WEBrick::HTTPServer.new(
      Port: 0,
      Logger: WEBrick::Log.new(File::NULL),
      AccessLog: []
    )
    @port = @server.config[:Port]

    @server.mount_proc('/ok') do |_req, res|
      res.status = 200
      res['ETag'] = 'W/"abc123"'
      res.body = '{"hello":"world"}'
    end

    @server.mount_proc('/notfound') do |_req, res|
      res.status = 404
      res.body = 'nope'
    end

    @server.mount_proc('/big') do |req, res|
      size = (req.query['size'] || '1024').to_i
      res.status = 200
      res.body = 'x' * size
    end

    @server.mount_proc('/echo-header') do |req, res|
      res.status = 200
      res.body = (req['X-Test'] || '').to_s
    end

    @thread = Thread.new { @server.start }
  end

  def teardown
    @server.shutdown
    @thread.join
  end

  def url(path)
    "http://127.0.0.1:#{@port}#{path}"
  end

  # --- response shape ---------------------------------------------------

  def test_successful_get_returns_body_and_code
    res = Abqari::HttpSafe.get(url('/ok'))
    assert_equal '200', res.code
    assert res.success?
    assert_equal '{"hello":"world"}', res.body
  end

  def test_response_header_lookup_is_case_insensitive
    res = Abqari::HttpSafe.get(url('/ok'))
    assert_equal 'W/"abc123"', res['ETag']
    assert_equal 'W/"abc123"', res['etag']
    assert_equal 'W/"abc123"', res['ETAG']
  end

  def test_non_success_response_has_code_and_no_success_flag
    res = Abqari::HttpSafe.get(url('/notfound'))
    assert_equal '404', res.code
    refute res.success?
  end

  def test_request_headers_are_sent
    res = Abqari::HttpSafe.get(url('/echo-header'), headers: { 'X-Test' => 'abqari' })
    assert_equal 'abqari', res.body
  end

  # --- size cap ---------------------------------------------------------

  def test_response_under_cap_is_returned_in_full
    res = Abqari::HttpSafe.get(url('/big?size=1024'), max_bytes: 4096)
    assert_equal 1024, res.body.bytesize
  end

  def test_response_at_exact_cap_is_returned
    res = Abqari::HttpSafe.get(url('/big?size=4096'), max_bytes: 4096)
    assert_equal 4096, res.body.bytesize
  end

  def test_response_over_cap_raises_too_large
    assert_raises(Abqari::HttpSafe::TooLargeError) do
      Abqari::HttpSafe.get(url('/big?size=10000'), max_bytes: 4096)
    end
  end
end

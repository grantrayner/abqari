# frozen_string_literal: true

require_relative 'test_helper'
require 'net/http'
require 'socket'

# The dev server must serve the site's own /404.html for unknown URLs
# — mirroring what static hosts (Cloudflare Pages, Netlify, GitHub
# Pages) do in production — so authors can preview their 404 page with
# `bin/serve` instead of seeing WEBrick's stock error page.
class ServerCustom404Test < Minitest::Test
  def setup
    @site = Abqari::Site.new
    @site.build
    silent_log = WEBrick::Log.new(File::NULL)
    @server = Abqari::Server.new(@site, port: pick_unused_port, bind: '127.0.0.1', logger: silent_log)
    @server_thread = Thread.new { @server.start }

    deadline = Time.now + 5
    until accepting?(port)
      raise 'dev server didn\'t start within 5s' if Time.now > deadline

      sleep 0.05
    end
  end

  def teardown
    @server&.stop_watcher
    @server.send(:shutdown_subscribers)
    server = @server.instance_variable_get(:@server)
    server&.shutdown
    @server_thread&.join(2)
  end

  def test_unknown_url_serves_the_site_404_page_with_404_status
    res = Net::HTTP.get_response('127.0.0.1', '/nope/', port)

    assert_equal '404', res.code
    assert_includes res.body, 'Page not found',
                    'expected the site\'s own 404.html, not WEBrick\'s stock error page'
    refute_includes res.body, 'WEBrick/'
  end

  def test_existing_pages_still_serve_200
    res = Net::HTTP.get_response('127.0.0.1', '/', port)

    assert_equal '200', res.code
    assert_includes res.body, '<html'
  end

  private

  def port
    @server.instance_variable_get(:@port)
  end

  def pick_unused_port
    server = TCPServer.new('127.0.0.1', 0)
    p = server.addr[1]
    server.close
    p
  end

  def accepting?(p)
    s = TCPSocket.new('127.0.0.1', p)
    s.close
    true
  rescue Errno::ECONNREFUSED
    false
  end
end

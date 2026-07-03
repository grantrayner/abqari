# frozen_string_literal: true

require_relative 'test_helper'
require 'net/http'
require 'json'
require 'socket'

# Smoke test for the SSE-based livereload endpoint. Starts a real
# Server on an unused port, opens an EventSource-equivalent HTTP
# connection, triggers a broadcast, and verifies the event arrives
# on the wire in valid SSE format.
class ServerSseTest < Minitest::Test
  def setup
    # A PRIVATE Site instance, not the shared TestHelpers.built_site.
    # `Server#start` launches a background file-watcher that calls
    # `site.build` (→ mutates `@generated_pages`) on every change it
    # sees under the engine tree. Pointed at the shared fixture, that
    # watcher races other tests' use of it — the historical source of
    # the order-independent flake. A private instance keeps the race
    # (if any) contained to a throwaway object; teardown stops the
    # watcher regardless.
    @site = Abqari::Site.new
    @site.build
    # Silence WEBrick's internal logger. The SSE endpoint rescues
    # `Errno::ECONNRESET` at the handler level, but WEBrick's request
    # loop logs the SAME error from `io_fillbuf` when the test's
    # `socket.close` lands while WEBrick's read is still parked.
    # That's cosmetic — the tests pass either way — but the stderr
    # noise drowns out genuine errors in CI output.
    silent_log = WEBrick::Log.new(File::NULL)
    @server = Abqari::Server.new(@site, port: pick_unused_port, bind: '127.0.0.1', logger: silent_log)
    @server_thread = Thread.new { @server.start }

    # Wait for the server to start listening — poll the port until it
    # accepts a TCP connect or the timeout fires. Avoids a flaky
    # `sleep 0.5` race.
    deadline = Time.now + 5
    until accepting?(@server.instance_variable_get(:@port))
      raise 'dev server didn\'t start within 5s' if Time.now > deadline

      sleep 0.05
    end
  end

  def teardown
    # Stop the file watcher FIRST so no background rebuild can fire
    # after the test — a leaked watcher thread would keep calling
    # site.build during later tests.
    @server&.stop_watcher
    @server.send(:shutdown_subscribers)
    # WEBrick's `shutdown` is asynchronous — give it a moment so the
    # next test's port acquisition doesn't race with the socket
    # closing.
    server = @server.instance_variable_get(:@server)
    server&.shutdown
    @server_thread&.join(2)
  end

  def test_sse_endpoint_emits_initial_state_and_broadcasts
    received = []
    received_mutex = Mutex.new

    # Open a raw HTTP connection so we can keep reading events from
    # the stream. Net::HTTP doesn't natively support EventSource but
    # holding the response open and reading chunked bytes works.
    socket = TCPSocket.new('127.0.0.1', @server.instance_variable_get(:@port))
    socket.write("GET /__reload__ HTTP/1.1\r\nHost: localhost\r\nConnection: keep-alive\r\n\r\n")

    # Read the initial response (headers + first event). WEBrick
    # writes the `: connected` comment + initial state event right
    # away, so this should arrive within a few hundred ms.
    reader = Thread.new do
      buffer = +''
      loop do
        data = socket.readpartial(4096)
        buffer << data
        # Stop after we see at least one data: event (initial state).
        break if buffer.include?("data:") && buffer.split("data:").size >= 3
      rescue EOFError, IOError
        break
      end
      received_mutex.synchronize { received << buffer }
    end

    # Give the connection a moment to land, then broadcast once.
    sleep 0.3
    @server.send(:broadcast, version: 999.0, scope: 'all')

    reader.join(2)
    socket.close

    body = received_mutex.synchronize { received.join }
    refute_empty body, 'expected to receive bytes on the SSE stream'

    # Verify it's the right content type and contains both the
    # initial state event and the broadcast event.
    assert_match(/Content-Type:\s+text\/event-stream/i, body)
    assert_match(/^data:\s+\{"version":/m, body)
    assert_match(/"version":\s*999\.0/, body)
  end

  def test_broadcast_fans_out_to_multiple_subscribers
    # Open two connections, broadcast once, verify both receive it.
    sockets = Array.new(2) do
      s = TCPSocket.new('127.0.0.1', @server.instance_variable_get(:@port))
      s.write("GET /__reload__ HTTP/1.1\r\nHost: localhost\r\nConnection: keep-alive\r\n\r\n")
      s
    end

    # Wait for both subscribers to register on the server side. The
    # endpoint enqueues a Queue into @subscribers under a mutex after
    # the request thread starts; poll until we see both.
    deadline = Time.now + 3
    until @server.instance_variable_get(:@subscribers).size >= 2
      raise 'subscribers didn\'t register in time' if Time.now > deadline

      sleep 0.05
    end

    @server.send(:broadcast, version: 777.0, scope: 'css')

    received = sockets.map do |s|
      buffer = +''
      Thread.new do
        loop do
          buffer << s.readpartial(4096)
          break if buffer.include?('"version":777.0') || buffer.include?('"version": 777.0')
        rescue EOFError, IOError
          break
        end
      end.join(2)
      s.close
      buffer
    end

    received.each_with_index do |buffer, i|
      assert_match(/777/, buffer, "subscriber #{i} should have received the broadcast")
    end
  end

  private

  def pick_unused_port
    server = TCPServer.new('127.0.0.1', 0)
    port = server.addr[1]
    server.close
    port
  end

  def accepting?(port)
    s = TCPSocket.new('127.0.0.1', port)
    s.close
    true
  rescue Errno::ECONNREFUSED
    false
  end
end

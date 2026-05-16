# frozen_string_literal: true

require 'webrick'
require 'json'
require 'timeout'

module Abqari
  class Server
    DEFAULT_PORT = 4000
    # Localhost-only by default. WEBrick's stdlib default is to bind to
    # 0.0.0.0 (all interfaces) — which would expose unrendered drafts
    # and future-dated content to anyone on the same Wi-Fi. Operators
    # that want to preview on a phone over LAN can override with
    # `ABQARI_BIND=0.0.0.0 bin/serve`.
    DEFAULT_BIND = '127.0.0.1'
    POLL_INTERVAL = 0.5
    DEBOUNCE = 0.1
    WATCH_GLOBS = ['content/**/*', 'app/**/*', 'themes/**/*', 'config/**/*', 'lib/**/*', 'data/**/*'].freeze
    CSS_PATTERN = /\.css\z/.freeze

    # How long to hold an SSE connection open before sending a no-op
    # heartbeat. Keeps load-balancers and overzealous proxies from
    # tearing down "idle" streams. 30 s is the typical proxy patience
    # window.
    SSE_HEARTBEAT = 30

    def initialize(site, port: DEFAULT_PORT, bind: nil)
      @site = site
      @port = port
      @bind = bind || ENV['ABQARI_BIND'] || DEFAULT_BIND
      @version = Time.now.to_f
      @scope = 'all'
      @mutex = Mutex.new
      # Active SSE subscribers — each is a Queue that receives one
      # event per rebuild. Tracked so `rebuild` can fan a single
      # event out to every connected browser tab.
      @subscribers       = []
      @subscribers_mutex = Mutex.new
    end

    def start
      start_watcher

      server = WEBrick::HTTPServer.new(
        BindAddress: @bind,
        Port: @port,
        DocumentRoot: @site.output_dir,
        AccessLog: [],
        DirectoryIndex: ['index.html']
      )

      server.mount_proc('/__reload__', &method(:handle_reload_endpoint))

      trap('INT')  { shutdown_subscribers; server.shutdown }
      trap('TERM') { shutdown_subscribers; server.shutdown }

      host = @bind == '0.0.0.0' ? 'localhost' : @bind
      Log.info "Abqari serving on http://#{host}:#{@port} (bind: #{@bind})"
      Log.info "Watching for changes via #{watcher_kind} (Ctrl-C to stop)."
      server.start
    end

    # SSE endpoint at /__reload__. Browsers open one EventSource per
    # tab and stay connected for the lifetime of the dev session;
    # each rebuild fans an event out to every connected stream,
    # which the client uses to decide between a CSS swap and a full
    # `location.reload()`.
    #
    # SSE wire format:
    #   data: {"version": 1.234, "scope": "css"}\n\n
    #
    # Headers required by the spec: text/event-stream content type,
    # explicit no-cache, and keep-alive. WEBrick's chunked-response
    # mode plus a body proc lets us hold the socket open and write
    # events as the queue produces them.
    def handle_reload_endpoint(_req, res)
      res['Content-Type']  = 'text/event-stream'
      res['Cache-Control'] = 'no-cache'
      res['Connection']    = 'keep-alive'
      res.chunked          = true

      queue = Queue.new
      @subscribers_mutex.synchronize { @subscribers << queue }

      res.body = proc do |out|
        # Initial flush — comment-line forces WEBrick to send headers
        # so the client's EventSource fires `onopen` and starts
        # consuming events. Followed by the current state so a tab
        # that connects mid-build doesn't miss its first rebuild.
        out.write(": connected\n\n")
        out.write(format_event(version: @version, scope: @scope))

        loop do
          # Pull with timeout so a quiet period still gets a
          # heartbeat (`:\n\n` is the SSE comment form — invisible
          # to the application code on the client).
          msg = pop_with_timeout(queue, SSE_HEARTBEAT)
          if msg.nil?
            out.write(": heartbeat\n\n")
            next
          end
          break if msg == :close

          out.write(format_event(msg))
        end
      rescue IOError, Errno::EPIPE, Errno::ECONNRESET
        # Client tab closed or network hiccup. Drop the queue;
        # WEBrick will tidy up the request thread.
        nil
      ensure
        @subscribers_mutex.synchronize { @subscribers.delete(queue) }
      end
    end

    private

    def watcher_kind
      listen_available? ? 'Listen (FS events)' : 'polling'
    end

    def listen_available?
      return @listen_available if defined?(@listen_available)

      @listen_available = begin
        require 'listen'
        true
      rescue LoadError
        false
      end
    end

    def start_watcher
      listen_available? ? start_listen_watcher : start_poll_watcher
    end

    # Native FS-event-based watcher (FSEvents on macOS, inotify on Linux).
    # Zero overhead between changes; debounced so an editor's atomic write
    # (which often fires twice in quick succession) only triggers one rebuild.
    #
    # Listen runs its callback on its own background thread; an
    # uncaught exception inside the block would silently kill that
    # thread and leave hot-reload off. Wrap the body in a rescue
    # that logs but continues so the next FS event still fires.
    def start_listen_watcher
      # Watch both site and engine source trees so editing engine CSS
      # during local-development (path:source) hot-reloads the site.
      bases = [@site.site_root, @site.engine_root].uniq
      roots = WATCH_GLOBS.flat_map do |g|
        bases.map { |b| File.join(b, g.split('/').first) }
      end.uniq.select { |p| Dir.exist?(p) }

      pending = []
      pending_mutex = Mutex.new
      debounce_thread = nil

      listener = Listen.to(*roots) do |modified, added, removed|
        pending_mutex.synchronize { pending.concat(modified + added + removed) }

        debounce_thread&.kill
        debounce_thread = Thread.new do
          sleep DEBOUNCE
          changed = pending_mutex.synchronize do
            batch = pending.dup
            pending.clear
            batch
          end
          rebuild(changed) unless changed.empty?
        rescue StandardError => e
          Log.error "Listen-debounce error: #{e.class}: #{e.message}"
          e.backtrace&.first(5)&.each { |line| Log.error "  #{line}" }
        end
      rescue StandardError => e
        Log.error "Listen-watcher callback error: #{e.class}: #{e.message}"
        e.backtrace&.first(5)&.each { |line| Log.error "  #{line}" }
      end

      listener.start
    end

    # Fallback: 500ms mtime polling. Used when Listen isn't installed.
    #
    # Supervised — if an exception bubbles out of the polling loop the
    # thread used to silently die, leaving the server serving stale
    # `_site/` content with no hot-reload until the operator noticed
    # and restarted. The wrapping `loop` restarts the watcher after
    # `WATCHER_RESTART_BACKOFF` seconds and re-logs the underlying
    # cause. The same supervision wraps the Listen-based watcher
    # below.
    def start_poll_watcher
      supervise(:poll) do
        snapshot = file_snapshot
        loop do
          sleep POLL_INTERVAL
          current = file_snapshot
          next if current == snapshot

          changed = (current.keys | snapshot.keys).select { |path| current[path] != snapshot[path] }
          rebuild(changed) unless changed.empty?
          snapshot = current
        end
      end
    end

    def rebuild(changed_paths)
      @mutex.synchronize do
        count = changed_paths.size
        Log.info "Change detected (#{count} file#{'s' unless count == 1}). Rebuilding…"
        @site.build(incremental: true)
        @scope = changed_paths.all? { |p| p =~ CSS_PATTERN } ? 'css' : 'all'
        @version = Time.now.to_f
      end

      broadcast(version: @version, scope: @scope)
    # Catch broadly: a content typo, a path-safety raise, or any
    # other build-time failure should NOT crash the dev server —
    # operators expect to fix the error in their editor and have the
    # next save retry. Log with backtrace at debug so
    # `ABQARI_LOG=debug bin/serve` surfaces the full stack while
    # default logs stay tidy.
    rescue StandardError => e
      Log.error "Build failed: #{e.class}: #{e.message}"
      e.backtrace&.first(5)&.each { |line| Log.debug "  #{line}" }
    end

    # ----------------------------------------------------------------
    # SSE plumbing
    # ----------------------------------------------------------------

    # Push an event to every connected EventSource. Non-blocking — if
    # a subscriber's queue is closed (its tab disconnected mid-write)
    # the Queue#<< call just no-ops.
    def broadcast(payload)
      @subscribers_mutex.synchronize do
        @subscribers.each do |q|
          q << payload
        rescue ClosedQueueError
          nil
        end
      end
    end

    # Close every active stream — used on shutdown so client tabs
    # exit their EventSource loop cleanly instead of seeing a TCP
    # reset.
    def shutdown_subscribers
      @subscribers_mutex.synchronize do
        @subscribers.each do |q|
          q << :close
          q.close
        rescue StandardError
          nil
        end
        @subscribers.clear
      end
    end

    # Pop with a timeout. Queue#pop blocks indefinitely on its own;
    # we want to wake periodically to send the SSE heartbeat that
    # keeps proxies from tearing down the stream. Returns nil on
    # timeout, the message on success.
    def pop_with_timeout(queue, seconds)
      Timeout.timeout(seconds) { queue.pop }
    rescue Timeout::Error
      nil
    end

    # Format an SSE `data:` event. Newlines in the payload aren't a
    # concern since we always emit JSON (a single line, no embedded
    # newlines).
    def format_event(payload)
      "data: #{JSON.generate(payload)}\n\n"
    end

    def file_snapshot
      bases = [@site.site_root, @site.engine_root].uniq
      WATCH_GLOBS.each_with_object({}) do |pattern, hash|
        bases.each do |base|
          Dir.glob(File.join(base, pattern)).each do |path|
            next if File.directory?(path)

            hash[path] = File.mtime(path).to_i
          end
        end
      end
    end

    # Wrap a watcher body in a restart loop so a crash inside the loop
    # doesn't silently take the entire dev-server hot-reload offline.
    # On exception, log clearly and back off briefly before
    # restarting; if the same error fires `MAX_RESTARTS` times in
    # `RESTART_WINDOW` seconds give up (an unrecoverable bug should
    # surface, not spin forever).
    WATCHER_RESTART_BACKOFF = 1
    MAX_RESTARTS            = 5
    RESTART_WINDOW          = 60

    def supervise(kind)
      Thread.new do
        restarts = []
        loop do
          begin
            yield
            break # block returned normally — watcher exited cleanly
          rescue StandardError => e
            restarts << Time.now
            restarts.shift while restarts.first && (Time.now - restarts.first) > RESTART_WINDOW

            Log.error "#{kind} watcher crashed: #{e.class}: #{e.message}"
            e.backtrace&.first(5)&.each { |line| Log.error "  #{line}" }

            if restarts.size > MAX_RESTARTS
              Log.error "#{kind} watcher exceeded #{MAX_RESTARTS} restarts in #{RESTART_WINDOW}s — giving up. Hot-reload is OFF."
              break
            end

            Log.warn "#{kind} watcher restarting in #{WATCHER_RESTART_BACKOFF}s…"
            sleep WATCHER_RESTART_BACKOFF
          end
        end
      end
    end
  end
end

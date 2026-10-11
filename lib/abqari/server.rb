# frozen_string_literal: true

require 'webrick'
require 'json'
require 'timeout'

module Abqari
  class Server
    # Override with `ABQARI_PORT=4001 bin/serve`. Worth having because a
    # machine running several Abqari sites has several dev servers wanting
    # 4000, and `bin/serve` takes no arguments by design.
    DEFAULT_PORT = 4000
    # Localhost-only by default. WEBrick's stdlib default is to bind to
    # 0.0.0.0 (all interfaces) — which would expose unrendered drafts
    # and future-dated content to anyone on the same Wi-Fi. Operators
    # that want to preview on a phone over LAN can override with
    # `ABQARI_BIND=0.0.0.0 bin/serve`.
    DEFAULT_BIND = '127.0.0.1'
    # 0 is excluded deliberately: WEBrick reads it as "any free port", which
    # would start a server the operator then has to hunt for. Ports below
    # 1024 need root and would fail later and less clearly.
    PORT_RANGE = (1..65_535).freeze
    POLL_INTERVAL = 0.5
    DEBOUNCE = 0.1
    # `plugins/` is here so a plugin edit is noticed at all. Plugins
    # load once at Site.new, so the change can only be reported (see
    # #warn_stale_ruby), not picked up.
    WATCH_GLOBS = ['content/**/*', 'app/**/*', 'themes/**/*', 'config/**/*', 'lib/**/*', 'data/**/*',
                   'plugins/**/*'].freeze
    # More than this and the stale-Ruby warning stops being one line.
    STALE_RUBY_LISTED = 3
    CSS_PATTERN = /\.css\z/.freeze

    # How long to hold an SSE connection open before sending a no-op
    # heartbeat. Keeps load-balancers and overzealous proxies from
    # tearing down "idle" streams. 30 s is the typical proxy patience
    # window.
    SSE_HEARTBEAT = 30

    # WEBrick logs every exception that escapes a request thread as an
    # ERROR with a full backtrace — including the ones that only mean
    # "the browser went away". A dev session produces a steady stream
    # of those: each open tab holds an SSE connection to `/__reload__`,
    # and navigating or reloading tears that socket down without a
    # clean close, so the `sock.eof?` check in WEBrick's own request
    # loop raises `Errno::ECONNRESET` from `io_fillbuf`.
    #
    # The SSE handler's `rescue` can't help here: WEBrick raises before
    # it ever dispatches to application code, so the error never
    # reaches our block. The logger is the only interception point.
    #
    # Suppression is by exception CLASS, never by message text — a
    # genuine fault whose message happens to mention a reset
    # connection is still logged in full. Set
    # `ABQARI_VERBOSE_LOG=true` to opt out and see everything WEBrick
    # reports, which is what you want when debugging the socket layer
    # itself.
    class QuietLog < WEBrick::Log
      # Each of these means the peer hung up. None is actionable, and
      # none indicates a fault in the site being served.
      CLIENT_DISCONNECTS = [
        Errno::ECONNRESET,   # peer sent RST — by far the common one
        Errno::EPIPE,        # wrote to a socket the peer already closed
        Errno::ECONNABORTED, # aborted between accept and read
        Errno::ENOTCONN      # socket no longer connected
      ].freeze

      def error(msg)
        return if CLIENT_DISCONNECTS.any? { |klass| msg.is_a?(klass) }

        super
      end
    end

    # WEBrick's stock FileHandler, with one change: an unknown URL
    # serves the site's own `/404.html` (when the build produced one)
    # instead of WEBrick's default error page. Static hosts —
    # Cloudflare Pages, Netlify, GitHub Pages — all do this in
    # production, so without it the 404 page is the one page an
    # author can never preview with `bin/serve`. The status stays
    # 404; only the body changes.
    class NotFoundFileHandler < WEBrick::HTTPServlet::FileHandler
      def service(req, res)
        super
      rescue WEBrick::HTTPStatus::NotFound
        custom = File.join(@root, '404.html')
        raise unless File.file?(custom)

        res.status = 404
        res.content_type = 'text/html; charset=utf-8'
        res.body = File.read(custom)
      end
    end

    # `port:` and `bind:` resolve the same way: an explicit argument wins,
    # then the environment, then the default. Embedders and the test suite
    # pass explicit values and are unaffected by whatever is exported in the
    # shell — which matters, because a stray ABQARI_PORT would otherwise
    # make every test that binds a socket fight for the same one.
    class << self
      # ABQARI_PORT, parsed strictly.
      #
      # `String#to_i` is the wrong tool here and quietly wrong in three ways:
      # "abc".to_i is 0, which WEBrick reads as "bind any free port" and
      # starts a server on a port nobody knows; "4000x".to_i is 4000, so a
      # typo silently works; and "99999".to_i is 99999, which fails deep in
      # the socket layer with a message that doesn't mention the env var.
      #
      # An operator who sets this has a specific port in mind. If we can't
      # honour it, say so here rather than serving something surprising.
      def port_from_env
        raw = ENV['ABQARI_PORT'].to_s.strip
        return nil if raw.empty?

        unless raw.match?(/\A\d+\z/)
          raise UserError, "ABQARI_PORT=#{raw.inspect} is not a number. " \
                           'Set it to a port between 1 and 65535, or unset it ' \
                           "to use the default (#{DEFAULT_PORT})."
        end

        port = raw.to_i
        unless PORT_RANGE.cover?(port)
          raise UserError, "ABQARI_PORT=#{port} is out of range. " \
                           "Use #{PORT_RANGE.min}–#{PORT_RANGE.max} " \
                           '(ports below 1024 also need root).'
        end

        port
      end

      # Check the environment knobs WITHOUT constructing a server or
      # touching the filesystem.
      #
      # `bin/serve` builds the entire site before it reaches
      # `Server.new`, so a typo'd ABQARI_PORT cost a full build before
      # the (genuinely good) error appeared. Call this first and it
      # fails in microseconds instead.
      def validate_env!
        port_from_env
        nil
      end
    end

    def initialize(site, port: nil, bind: nil, logger: nil)
      @site = site
      @port = port || self.class.port_from_env || DEFAULT_PORT
      @bind = bind || ENV['ABQARI_BIND'] || DEFAULT_BIND
      # WEBrick's internal logger. Defaults to `QuietLog` — WEBrick's
      # own stderr logger with client-disconnect errors filtered out
      # (see the class comment above for why that filtering can't live
      # at the SSE endpoint). Pass `logger:` to override: tests use a
      # fully silent `WEBrick::Log.new(File::NULL)`, and
      # `ABQARI_VERBOSE_LOG=true` falls back to stock WEBrick logging.
      @logger = logger || default_logger
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

      server_opts = {
        BindAddress: @bind,
        Port: @port,
        AccessLog: [],
        DirectoryIndex: ['index.html']
      }
      server_opts[:Logger] = @logger
      server = WEBrick::HTTPServer.new(server_opts)

      # No :DocumentRoot — that would auto-mount the stock FileHandler.
      # Mount the 404-aware subclass at the root instead; it inherits
      # DirectoryIndex and the rest of the server config.
      server.mount('/', NotFoundFileHandler, @site.output_dir)
      server.mount_proc('/__reload__', &method(:handle_reload_endpoint))

      # Shutdown choreography is delicate:
      #
      #   - The trap handler can't call `Mutex#synchronize` itself
      #     (`ThreadError: can't be called from trap context`).
      #   - But every open SSE connection has a WEBrick request thread
      #     parked in `queue.pop` (waiting for an event or the 30-second
      #     heartbeat tick). `server.shutdown` only sets a flag — it
      #     doesn't kill those threads. WEBrick's main loop waits for
      #     them to finish before `server.start` returns.
      #   - So if we just call `server.shutdown` from the trap, WEBrick
      #     hangs until every parked SSE thread times out (~30s each).
      #
      # The fix: the trap spawns a fresh Ruby thread (allowed from a
      # trap context, runs in normal context). That thread closes the
      # subscriber queues FIRST — which unblocks the parked SSE
      # threads — then calls `server.shutdown` so WEBrick can drain
      # cleanly.
      # Block form (not lambda): Ruby passes the signal number as the
      # block argument and lambdas are strict about arity. The block
      # form ignores extra args, so a clean Ctrl-C doesn't crash with
      # `wrong number of arguments (given 1, expected 0)`.
      shutdown_hook = proc do
        Thread.new do
          shutdown_subscribers
          server.shutdown
        end
      end

      trap('INT',  shutdown_hook)
      trap('TERM', shutdown_hook)

      host = @bind == '0.0.0.0' ? 'localhost' : @bind
      Log.info "Abqari serving on http://#{host}:#{@port} (bind: #{@bind})"
      Log.info "Watching for changes via #{watcher_kind} (Ctrl-C to stop)."
      server.start
    end

    # Stop the file watcher (Listen listener or the polling thread).
    # In the CLI the process just exits so this is unused, but it lets
    # embedders — and the test suite — shut a server down cleanly
    # instead of leaking a background thread that keeps calling
    # `rebuild` (→ `site.build`) after the server is otherwise done.
    def stop_watcher
      @listener&.stop
      @listener = nil
      if @watcher_thread
        @watcher_thread.kill
        @watcher_thread.join(1)
        @watcher_thread = nil
      end
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

    # Stock WEBrick logging is one env var away, for when the noise is
    # the thing you're trying to read.
    def default_logger
      ENV['ABQARI_VERBOSE_LOG'] == 'true' ? WEBrick::Log.new : QuietLog.new
    end

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

      @listener = Listen.to(*roots) do |modified, added, removed|
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

      @listener.start
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
      @watcher_thread = supervise(:poll) do
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
        warn_stale_ruby if changed_paths.any? { |p| p.end_with?('.rb') }
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
      warn_stale_ruby(after_failure: true)
    end

    # The change warning alone isn't enough: the usual sequence is
    # edit the plugin, then edit the layout that calls the new helper,
    # and by the time every page fails with `undefined method ... for
    # an instance of Abqari::RenderContext` the warning has scrolled
    # away. So a failed build repeats it, as an error, last.
    def warn_stale_ruby(after_failure: false)
      stale = @site.stale_ruby_sources
      return if stale.empty?

      files = stale.first(STALE_RUBY_LISTED).join(', ')
      files += " and #{stale.size - STALE_RUBY_LISTED} more" if stale.size > STALE_RUBY_LISTED
      if after_failure
        Log.error "Restart bin/serve: #{files} changed after it started, and it is still running " \
                  'the old Ruby, so helpers added since are undefined.'
      else
        Log.warn "#{files} changed, but bin/serve loads Ruby once at startup — restart it to pick that up."
      end
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
    #
    # `WATCHER_RESTART_BACKOFF` can be overridden via the
    # `ABQARI_WATCHER_RESTART_BACKOFF` env var — primarily for tests,
    # so `server_supervise_test` doesn't have to wait 5+ seconds for
    # the give-up branch to fire. Production callers shouldn't set
    # this; the 1s default exists to avoid hot-restarting on a tight
    # loop when the underlying error is unrecoverable.
    DEFAULT_WATCHER_RESTART_BACKOFF = 1.0
    MAX_RESTARTS                    = 5
    RESTART_WINDOW                  = 60

    def watcher_restart_backoff
      return DEFAULT_WATCHER_RESTART_BACKOFF unless ENV['ABQARI_WATCHER_RESTART_BACKOFF']
      ENV['ABQARI_WATCHER_RESTART_BACKOFF'].to_f
    end

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

            backoff = watcher_restart_backoff
            Log.warn "#{kind} watcher restarting in #{backoff}s…"
            sleep backoff
          end
        end
      end
    end
  end
end

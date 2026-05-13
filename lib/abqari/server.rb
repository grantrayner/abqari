# frozen_string_literal: true

require 'webrick'
require 'json'

module Abqari
  class Server
    DEFAULT_PORT = 4000
    POLL_INTERVAL = 0.5
    DEBOUNCE = 0.1
    WATCH_GLOBS = ['content/**/*', 'app/**/*', 'themes/**/*', 'config/**/*', 'lib/**/*', 'data/**/*'].freeze
    CSS_PATTERN = /\.css\z/.freeze

    def initialize(site, port: DEFAULT_PORT)
      @site = site
      @port = port
      @version = Time.now.to_f
      @scope = 'all'
      @mutex = Mutex.new
    end

    def start
      start_watcher

      server = WEBrick::HTTPServer.new(
        Port: @port,
        DocumentRoot: @site.output_dir,
        AccessLog: [],
        DirectoryIndex: ['index.html']
      )

      server.mount_proc('/__reload__') do |_req, res|
        res['Content-Type'] = 'application/json'
        res['Cache-Control'] = 'no-store'
        res.body = JSON.generate(version: @version, scope: @scope)
      end

      trap('INT')  { server.shutdown }
      trap('TERM') { server.shutdown }

      Log.info "Abqari serving on http://localhost:#{@port}"
      Log.info "Watching for changes via #{watcher_kind} (Ctrl-C to stop)."
      server.start
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
        end
      end

      listener.start
    end

    # Fallback: 500ms mtime polling. Used when Listen isn't installed.
    def start_poll_watcher
      Thread.new do
        snapshot = file_snapshot
        loop do
          sleep POLL_INTERVAL
          current = file_snapshot
          next if current == snapshot

          changed = (current.keys | snapshot.keys).select { |path| current[path] != snapshot[path] }
          rebuild(changed) unless changed.empty?
          snapshot = current
        end
      rescue StandardError => e
        Log.error "Watcher error: #{e.message}"
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
    rescue StandardError => e
      Log.error "Build failed: #{e.message}"
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
  end
end

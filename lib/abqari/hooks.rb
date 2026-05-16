# frozen_string_literal: true

module Abqari
  # Plugin hook registry. Plugins register named-event callbacks; the
  # engine invokes them at known points during the build.
  #
  # Two flavours:
  #
  #   - `register(event, &block)` + `run(event, ...)` — event-style.
  #     Every registered callback is called for its side effect; the
  #     return value is ignored.
  #
  #   - `register(event, &block)` + `run_filter(event, value, ...)` —
  #     filter-style. The value is threaded through every callback;
  #     each callback returns the (possibly modified) value, and the
  #     final result is what the engine consumes downstream.
  #
  # Events exposed by the engine (see docs/plugins.md for the canonical
  # list):
  #
  #   Lifecycle:
  #     :before_build         (site)            — Site#build entry
  #     :after_load_pages     (site)            — after `load_pages`, before generators
  #     :after_generate       (site)            — after `generate_all`
  #     :before_render_page   (site, page)      — per page, before its render call
  #     :after_build          (site)            — Site#build exit (success or failure)
  #
  #   Filters:
  #     :post_process         (html, site, page) -> html
  #     :resolved_frontmatter (fm, page)         -> fm
  #
  # Thread safety: registration and run iterate over a snapshot of the
  # callback list, so registering inside a hook callback is safe (the
  # new callback fires on the next event, not the current one).
  module Hooks
    @hooks = Hash.new { |h, k| h[k] = [] }
    @mutex = Mutex.new

    class << self
      # Register a callback for `event`. Returns the block for chaining.
      def register(event, &block)
        raise ArgumentError, "Hooks.register requires a block (event: #{event.inspect})" unless block

        @mutex.synchronize { @hooks[event] << block }
        block
      end

      # Run every callback registered for `event`. Each return value is
      # discarded; use `run_filter` if you need to transform a value.
      def run(event, *args)
        snapshot = @mutex.synchronize { @hooks[event].dup }
        snapshot.each do |hook|
          hook.call(*args)
        rescue StandardError => e
          Log.error "plugin hook #{event} crashed: #{e.class}: #{e.message}"
          e.backtrace&.first(5)&.each { |line| Log.error "  #{line}" }
          # Re-raise — a misbehaving plugin should fail the build, not
          # silently produce wrong output. Operators can debug from
          # the logged backtrace.
          raise
        end
      end

      # Thread `value` through every callback registered for `event`.
      # Each callback receives `(value, *args)` and returns the new
      # value. Final value flows back to the caller.
      def run_filter(event, value, *args)
        snapshot = @mutex.synchronize { @hooks[event].dup }
        snapshot.each do |hook|
          value = hook.call(value, *args)
        rescue StandardError => e
          Log.error "plugin filter #{event} crashed: #{e.class}: #{e.message}"
          e.backtrace&.first(5)&.each { |line| Log.error "  #{line}" }
          raise
        end
        value
      end

      # Reset the registry. Used in tests and any caller that wants a
      # fresh hook table — the engine itself doesn't currently clear
      # between rebuilds (plugins survive incremental rebuilds, matching
      # Jekyll's _plugins/ semantics).
      def clear!
        @mutex.synchronize { @hooks = Hash.new { |h, k| h[k] = [] } }
      end

      # Read-only snapshot of the current registry — useful in tests
      # and for `bin/audit` style introspection.
      def registered_events
        @mutex.synchronize { @hooks.keys.dup }
      end

      def count(event)
        @mutex.synchronize { @hooks[event].size }
      end
    end
  end

  # Plugin auto-loader. Walks `<site_root>/plugins/**/*.rb` once at
  # Site construction time and `Kernel#load`s each file in sorted
  # order. Plugins are conventionally tiny Ruby files that call
  # `Abqari::Hooks.register` to wire themselves into the lifecycle.
  #
  # Why `load` instead of `require`: `require` caches by path, so a
  # plugin edit isn't reloaded on subsequent Site.new calls. `load`
  # re-executes every time — important for the dev-server case where
  # editing a plugin file should re-register its hooks on the next
  # incremental rebuild.
  #
  # The hook table is NOT cleared between reloads. A plugin that
  # registers in its top-level body will accumulate duplicate
  # callbacks across rebuilds. Plugins that need rebuild-safe
  # registration should use the `setup` convention (see
  # docs/plugins.md): wrap registration in a module method called by
  # `Abqari::Hooks.clear!`-aware sites.
  module PluginLoader
    PLUGIN_GLOB = File.join('plugins', '**', '*.rb')

    module_function

    def load_from(site_root)
      pattern = File.join(site_root, PLUGIN_GLOB)
      paths = Dir.glob(pattern).sort
      return if paths.empty?

      Log.info "Loading #{paths.size} plugin file(s) from #{File.join(site_root, 'plugins')}/"
      paths.each do |path|
        load(path)
      rescue StandardError, ScriptError => e
        Log.error "plugin load failed: #{path} — #{e.class}: #{e.message}"
        e.backtrace&.first(5)&.each { |line| Log.error "  #{line}" }
        raise
      end
    end
  end
end

# frozen_string_literal: true

require 'fileutils'

module Abqari
  # Static search via Pagefind. After bin/build emits HTML, Pagefind walks
  # _site/, builds a chunked search index under _site/pagefind/, and ships
  # a tiny JS runtime that runs entirely in the visitor's browser.
  #
  # Privacy-friendly (no server, no API), free, and the index is just static
  # files served alongside your site.
  #
  # Pagefind is a single Rust binary. Install it once:
  #   macOS:    brew install pagefind
  #   General:  curl -LSf https://pagefind.app/install.sh | bash
  #   Cargo:    cargo install pagefind
  #
  # Enable in config/site.yml:
  #   search: true
  #
  # Then render the search widget anywhere in your templates:
  #   <%= render 'partials/search' %>
  class Search
    BINARY = 'pagefind'

    def initialize(site)
      @site = site
    end

    def enabled?
      @site.config['search'] == true
    end

    # Called from Site#build — only runs when `search: true` is set so a
    # default site doesn't pay the cost.
    def run
      return unless enabled?

      run!
    end

    # Always runs pagefind, regardless of the config flag. Used by bin/index
    # so an explicit invocation works even when search isn't enabled in config.
    # Skips with a helpful warning if the binary isn't on PATH; never raises
    # so a fresh checkout never fails the build.
    def run!
      unless command_available?
        Log.warn "Abqari: `#{BINARY}` is not on PATH."
        Log.warn '       Install: https://pagefind.app/docs/installation/'
        Log.warn '       Skipping search index.'
        return
      end

      success = system(BINARY, '--site', @site.output_dir, out: File::NULL, err: File::NULL)
      if success
        Log.info 'Indexed for search → _site/pagefind/'
      else
        Log.warn "Abqari: pagefind exited with status #{$?.exitstatus}; search may be incomplete."
      end
    end

    private

    def command_available?
      ENV['PATH'].split(File::PATH_SEPARATOR).any? { |dir| File.executable?(File.join(dir, BINARY)) }
    end
  end
end

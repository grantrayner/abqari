# frozen_string_literal: true

require 'digest'
require 'fileutils'

module Abqari
  class AssetPipeline
    OUTPUT_SUBDIR = 'assets'
    HASH_LENGTH = 10
    DEFAULT_THEME = 'minimal'

    def initialize(site)
      @site = site
      @paths = {}
    end

    def process
      # Processing order matters — later passes overwrite earlier ones
      # on logical-path conflict (same filename).
      #
      # Within a category (theme vs app/assets), engine first, site
      # second — so a site can override a theme file or a structural
      # CSS asset just by dropping its own version at the same path.
      #
      # Between categories, themes lose to app/assets (preserving the
      # original semantic: `_common.css` and `site.css` win over
      # theme-bundled CSS on conflict). Hence the order:
      #   1. engine theme   →  2. site theme
      #   3. engine assets  →  4. site assets
      [engine_theme_dir, site_theme_dir, engine_app_assets, site_app_assets].uniq.each do |dir|
        process_dir(dir) if dir && Dir.exist?(dir)
      end
    end

    def path_for(name)
      @paths[name] || raise(ArgumentError, "Unknown asset: #{name}. Add it to app/assets/ or themes/#{theme_name}/.")
    end

    def theme_name
      @site.config['theme'] || DEFAULT_THEME
    end

    private

    def engine_app_assets
      File.join(@site.engine_root, 'app', 'assets')
    end

    def site_app_assets
      File.join(@site.site_root, 'app', 'assets')
    end

    def engine_theme_dir
      return nil if theme_name.to_s == 'none'

      File.join(@site.engine_root, 'themes', theme_name)
    end

    def site_theme_dir
      return nil if theme_name.to_s == 'none'

      File.join(@site.site_root, 'themes', theme_name)
    end

    def process_dir(src)
      Dir.glob(File.join(src, '**', '*')).sort.each do |entry|
        next if File.directory?(entry)
        next if File.basename(entry).start_with?('.')
        next if entry.include?(File.join('assets', 'images') + File::SEPARATOR)

        logical = entry.sub("#{src}/", '')
        fingerprinted = fingerprint(entry, logical)

        dest = File.join(@site.output_dir, OUTPUT_SUBDIR, fingerprinted)

        # Skip the copy if the fingerprinted target already exists — fingerprints
        # are content-addressable, so a matching name means matching content.
        unless File.exist?(dest)
          FileUtils.mkdir_p(File.dirname(dest))
          FileUtils.cp(entry, dest)
        end

        @paths[logical] = "/#{OUTPUT_SUBDIR}/#{fingerprinted}"
      end
    end

    def fingerprint(file, logical)
      hash = Digest::SHA1.file(file).hexdigest[0, HASH_LENGTH]
      ext = File.extname(logical)
      base = logical[0...-ext.length]
      "#{base}.#{hash}#{ext}"
    end
  end
end

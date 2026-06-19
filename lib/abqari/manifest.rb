# frozen_string_literal: true

require 'json'
require 'fileutils'

module Abqari
  # Web App Manifest writer. Emits `_site/manifest.json` from site config.
  # Linked from <head> via _head.html.erb. Treated as part of the build, not
  # a static file in `public/`, so the values stay in sync with site.yml
  # (title, theme color, etc.) without manual duplication.
  #
  # Override any field via `manifest:` in config/site.yml; the rest fall
  # back to sensible defaults derived from other config keys.
  class Manifest
    DEFAULTS = {
      'display'          => 'standalone',
      'start_url'        => '/',
      'theme_color'      => '#ffffff',
      'background_color' => '#ffffff',
      'icons'            => [
        { 'src' => '/icon-192.png', 'sizes' => '192x192', 'type' => 'image/png' },
        { 'src' => '/icon-512.png', 'sizes' => '512x512', 'type' => 'image/png' }
      ]
    }.freeze

    def initialize(site)
      @site = site
      @cfg = site.config['manifest'] || {}
    end

    def write
      File.write(File.join(@site.output_dir, 'manifest.json'), JSON.pretty_generate(payload))
    end

    private

    def payload
      DEFAULTS.merge(
        'name'       => @cfg['name']       || @site.config['title'],
        'short_name' => @cfg['short_name'] || @site.config['title'],
        'lang'       => @cfg['lang']       || @site.config['locale'] || 'en'
      ).merge(@cfg).reject { |_, v| v.nil? }
    end
  end
end

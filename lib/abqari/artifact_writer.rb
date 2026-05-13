# frozen_string_literal: true

require 'fileutils'

module Abqari
  # Filesystem-output collaborator. Owns the steps that produce files in
  # `_site/` outside of the page-render loop:
  #
  #   - Wiping / preparing the output directory at the start of a build.
  #   - Copying static passthrough trees (public/, themes/<n>/public/).
  #   - Copying vendored assets (D3, fonts).
  #   - Emitting deploy artifacts (sitemap, feed, robots, headers,
  #     security.txt, redirects, manifest, llms.txt, OG images,
  #     syntax-highlighter stylesheet).
  #
  # Each step is idempotent: re-running an incremental build only copies
  # files that changed (mtime comparison). The reset_output guard
  # prevents accidentally wiping anything outside site_root.
  class ArtifactWriter
    def initialize(site)
      @site = site
    end

    # Wipe `output_dir` and recreate it empty. Refuses to delete:
    #   - The filesystem root (`/`, `C:\`)
    #   - The user's home directory
    #   - Anything not under `site_root` (unless explicitly opted-in
    #     via ABQARI_ALLOW_EXTERNAL_OUTPUT=true).
    def reset_output
      target = File.expand_path(@site.output_dir)

      raise PathSafe::Error, "refusing to wipe filesystem root: #{target}" if filesystem_root?(target)
      raise PathSafe::Error, "refusing to wipe home dir: #{target}" if target == File.expand_path('~')

      unless ENV['ABQARI_ALLOW_EXTERNAL_OUTPUT'] == 'true'
        PathSafe.assert_under(@site.site_root, target)
      end

      FileUtils.rm_rf(target)
      FileUtils.mkdir_p(target)
    end

    # Copy static passthrough files into the build output. Two sources:
    #   1. Top-level `public/` — site-wide files (favicons, manifest).
    #   2. The active theme's `themes/<name>/public/` — theme-scoped
    #      vendor files (e.g. the Bootstrap dist for `theme: bootstrap`).
    #      Theme files win on conflict (copied second).
    def copy_public
      [File.join(@site.site_root, 'public'),
       @site.find_in_paths(File.join('themes', @site.config['theme'].to_s, 'public'))].each do |public_dir|
        next unless Dir.exist?(public_dir)

        Dir.glob(File.join(public_dir, '**', '*'), File::FNM_DOTMATCH).sort.each do |entry|
          next if File.directory?(entry)
          next if File.basename(entry).start_with?('.')

          rel  = entry.sub("#{public_dir}/", '')
          dest = File.join(@site.output_dir, rel)
          next if File.exist?(dest) && File.mtime(dest) >= File.mtime(entry)

          FileUtils.mkdir_p(File.dirname(dest))
          FileUtils.cp(entry, dest)
        end
      end
    end

    # Mirror the FontPipeline-populated `vendor/fonts/` into
    # `_site/assets/fonts/`. No-op when the cache is missing (FontPipeline
    # is opt-in via `bin/fetch-fonts`).
    def copy_fonts
      src = File.join(@site.site_root, 'vendor', 'fonts')
      return unless Dir.exist?(src)

      dest_dir = File.join(@site.output_dir, 'assets', 'fonts')
      FileUtils.mkdir_p(dest_dir)
      Dir.glob(File.join(src, '*')).sort.each do |entry|
        next if File.directory?(entry) || File.basename(entry).start_with?('.')

        dest = File.join(dest_dir, File.basename(entry))
        next if File.exist?(dest) && File.mtime(dest) >= File.mtime(entry)

        FileUtils.cp(entry, dest)
      end
    end

    # Copy vendored D3 to _site/assets/d3/. Only runs when visualizations
    # are enabled — keeps the ~280 KB out of builds that don't need it.
    def copy_d3
      return unless @site.visualizations.enabled?

      src = File.join(@site.engine_root, 'vendor', 'd3', 'd3.v7.min.js')
      return unless File.exist?(src)

      dest_dir = File.join(@site.output_dir, 'assets', 'd3')
      FileUtils.mkdir_p(dest_dir)
      dest = File.join(dest_dir, 'd3.v7.min.js')
      return if File.exist?(dest) && File.mtime(dest) >= File.mtime(src)

      FileUtils.cp(src, dest)
    end

    # Emit every deploy artifact that ships alongside the rendered HTML.
    # Order matters only insofar as some artifacts (e.g. Manifest) read
    # config values that should already be validated; all of those run
    # after Site#build has done its setup.
    def write_deploy_artifacts
      Sitemap.new(@site).write
      Feed.write_all(@site)
      Robots.new(@site).write
      HeadersFile.new(@site).write
      SecurityTxt.new(@site).write
      Redirects.new(@site).write
      Manifest.new(@site).write
      LlmsTxt.new(@site).write
      OgImageGenerator.new(@site).write
      SyntaxHighlighter::Stylesheet.new(@site).write
    end

    private

    def filesystem_root?(path)
      path == '/' || path == File::SEPARATOR || path.match?(/\A[A-Za-z]:[\\\/]?\z/)
    end
  end
end

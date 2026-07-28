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

    # Directory names we refuse to let `output_dir` resolve to, because
    # wiping them destroys the user's source, not build output. Checked
    # against the target itself AND against the site root's key children.
    PROTECTED_SITE_DIRS = %w[content config data public .git].freeze

    # Wipe `output_dir` and recreate it empty. Refuses to delete:
    #   - The filesystem root (`/`, `C:\`)
    #   - The user's home directory
    #   - The site root itself (`ABQARI_OUTPUT_DIR=.` — the guard below
    #     for "under site_root" passes on equality, which would wipe the
    #     whole project).
    #   - A source directory (`content/`, `config/`, `data/`, `.git`, …).
    #   - Anything not under `site_root` (unless explicitly opted-in
    #     via ABQARI_ALLOW_EXTERNAL_OUTPUT=true).
    def reset_output
      target    = File.expand_path(@site.output_dir)
      site_root = File.expand_path(@site.site_root)

      raise PathSafe::Error, "refusing to wipe filesystem root: #{target}" if filesystem_root?(target)
      raise PathSafe::Error, "refusing to wipe home dir: #{target}" if target == File.expand_path('~')
      raise PathSafe::Error, "refusing to wipe site root: #{target}" if target == site_root

      protected_dir = PROTECTED_SITE_DIRS.find do |name|
        dir = File.expand_path(File.join(site_root, name))
        target == dir || dir.start_with?(target + File::SEPARATOR)
      end
      if protected_dir
        raise PathSafe::Error,
              "refusing to wipe #{target}: it is (or contains) the site's #{protected_dir}/ directory"
      end

      unless ENV['ABQARI_ALLOW_EXTERNAL_OUTPUT'] == 'true'
        PathSafe.assert_under(@site.site_root, target)
      end

      FileUtils.rm_rf(target)
      FileUtils.mkdir_p(target)
    end

    # Copy static passthrough files into the build output. Three
    # sources, later wins on conflict:
    #   1. Top-level `public/` — site-wide files (favicons, manifest).
    #   2. The ENGINE theme's `themes/<name>/public/` — theme-scoped
    #      vendor files (e.g. the Bootstrap dist for `theme: bootstrap`).
    #   3. The SITE's `themes/<name>/public/` — per-file overrides.
    #
    # Engine and site theme dirs MERGE (same semantics as the asset
    # pipeline): a site adding one file to `themes/bootstrap/public/`
    # must not stop the engine's vendored dist from shipping. The old
    # `find_in_paths` picked exactly one dir, so a single site-local
    # file silently 404'd `/css/bootstrap.min.css`. Precedence is
    # resolved in the map — NOT via copy order + the mtime skip, which
    # would let whichever source file happened to be newer win.
    def copy_public
      theme = @site.config['theme'].to_s
      sources = [
        File.join(@site.site_root, 'public'),
        File.join(@site.engine_root, 'themes', theme, 'public'),
        File.join(@site.site_root, 'themes', theme, 'public')
      ]

      merged = {}
      sources.each do |public_dir|
        next unless Dir.exist?(public_dir)

        Dir.glob(File.join(public_dir, '**', '*'), File::FNM_DOTMATCH).sort.each do |entry|
          next if File.directory?(entry)
          # Symlink containment — the one tree-walker that used to miss
          # this. `FileUtils.cp` follows symlinks, so without the guard a
          # `public/notes.txt -> ~/.ssh/id_ed25519` copies the target's
          # CONTENTS into _site/ and ships them. Every other walker
          # (asset pipeline, bundle assets, image pipeline, loader)
          # enforces the same invariant.
          next if @site.external_symlink?(entry)

          rel = entry.sub("#{public_dir}/", '')
          # Dotfile filter checks EVERY path component, not just the
          # basename. FNM_DOTMATCH descends into hidden directories, so a
          # basename-only check would still copy `.git/config`,
          # `.svn/entries`, editor state dirs, etc. `.well-known/` is the
          # one hidden dir a static site legitimately publishes.
          next if hidden_path?(rel)

          merged[rel] = entry
        end
      end

      merged.each do |rel, entry|
        dest = File.join(@site.output_dir, rel)
        next if File.exist?(dest) && File.mtime(dest) >= File.mtime(entry)

        FileUtils.mkdir_p(File.dirname(dest))
        FileUtils.cp(entry, dest)
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
      # Crawler-facing inventories (sitemap, llms.txt) are suppressed when
      # the site opts out of indexing — otherwise a staging/preview deploy
      # with `indexable: false` still publishes a full list of its URLs,
      # defeating the point. `robots.txt` (which emits `Disallow: /` in
      # that mode) is always written so crawlers get the signal.
      indexable = @site.config['indexable'] != false

      Sitemap.new(@site).write if indexable
      Feed.write_all(@site)
      Robots.new(@site).write
      HeadersFile.new(@site).write
      SecurityTxt.new(@site).write
      Redirects.new(@site).write
      Manifest.new(@site).write
      LlmsTxt.new(@site).write if indexable
      OgImageGenerator.new(@site).write
      SyntaxHighlighter::Stylesheet.new(@site).write
    end

    private

    def filesystem_root?(path)
      path == '/' || path == File::SEPARATOR || path.match?(/\A[A-Za-z]:[\\\/]?\z/)
    end

    # True when any component of the relative path is a dotfile/dotdir,
    # except an allowlisted `.well-known` (RFC 8615 — security.txt,
    # ACME challenges, etc., which a static site is meant to publish).
    ALLOWED_DOT_DIRS = %w[.well-known].freeze

    def hidden_path?(rel)
      rel.split('/').any? do |component|
        component.start_with?('.') && !ALLOWED_DOT_DIRS.include?(component)
      end
    end
  end
end

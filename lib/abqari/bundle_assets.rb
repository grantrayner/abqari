# frozen_string_literal: true

require 'fileutils'

module Abqari
  # Copies colocated assets into the rendered output. Two flavours:
  #
  # 1. **Bundle-style collections** (`bundle: true`) — each item is its
  #    own directory containing `index.md` plus assets. Assets are
  #    copied next to the rendered HTML:
  #
  #      content/posts/2026-05-07-foo/hero.jpg
  #      → _site/posts/foo/hero.jpg
  #
  #      content/photos/2026-03-01-bread-shop/photo.svg
  #      → _site/photos/bread-shop/photo.svg
  #
  # 2. **Flat collections** (`bundle: false`) — items are single .md
  #    files; non-.md siblings (covers, PDFs, sample images) are copied
  #    into the collection's root output dir:
  #
  #      content/<collection>/cover.svg
  #      → _site/<collection>/cover.svg
  #
  # The page itself rewrites relative <img>/<a> URLs in its rendered HTML
  # so authors can reference assets by short relative names; absolute
  # paths in front matter (`/photos/bread-shop/photo.svg`) work directly.
  class BundleAssets
    def initialize(site)
      @site = site
    end

    def copy
      copy_bundle_assets
      copy_flat_collection_assets
    end

    private

    # Bundle-style: each page that has a bundle directory gets its
    # siblings copied next to the rendered HTML. Works for posts AND
    # any user-defined bundle collection (photos, etc.).
    #
    # Destinations are routed through PathSafe so neither `page.url`
    # (ultimately derived from frontmatter `permalink:`) nor an asset
    # filename can resolve outside output_dir. PathSafe raises if either
    # tries to escape.
    def copy_bundle_assets
      @site.all_pages.each do |page|
        next unless page.respond_to?(:bundle_dir) && page.bundle_dir

        rel_dir  = page.url.sub(%r{\A/}, '').chomp('/')
        dest_dir = PathSafe.join_under(@site.output_dir, rel_dir)
        FileUtils.mkdir_p(dest_dir)

        page.bundle_assets.each do |source|
          dest = PathSafe.join_under(dest_dir, File.basename(source))
          next if File.exist?(dest) && File.mtime(dest) >= File.mtime(source)

          FileUtils.cp(source, dest)
        end
      end
    end

    # Flat collections: any non-.md sibling of an .md file in the
    # collection's source dir is copied into the collection's root
    # output. Covers, sample PDFs, etc. live alongside the markdown.
    # Disabled collections are skipped entirely.
    def copy_flat_collection_assets
      @site.collections.each do |_name, cfg|
        next if cfg['bundle'] != false
        next unless cfg.fetch('enabled', true)

        source_dir = File.join(@site.site_root, cfg['source'].to_s)
        next unless Dir.exist?(source_dir)

        dest_dir = PathSafe.join_under(@site.output_dir, collection_base(cfg))
        FileUtils.mkdir_p(dest_dir)

        Dir.glob(File.join(source_dir, '*')).sort.each do |source|
          next if File.directory?(source)
          next if File.extname(source).downcase == '.md'
          next if @site.external_symlink?(source)

          dest = PathSafe.join_under(dest_dir, File.basename(source))
          next if File.exist?(dest) && File.mtime(dest) >= File.mtime(source)

          FileUtils.cp(source, dest)
        end
      end
    end

    # Strip the slug placeholder (and anything after it) from the
    # collection's permalink template to find the asset root.
    # `/publications/:slug/` → `publications`.
    def collection_base(cfg)
      cfg['permalink'].to_s.sub(/:slug.*/, '').sub(%r{\A/}, '').chomp('/')
    end
  end
end

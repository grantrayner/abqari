# frozen_string_literal: true

require 'yaml'
require 'json'

module Abqari
  # Site-loading collaborator. Owns reading the three classes of input
  # that bootstrap a build:
  #
  #   - `config/site.yml` (and environment overrides)
  #   - `content/**/*.md` (every page the build will render)
  #   - `data/**/*.{yml,yaml,json}` (operator-curated reference tables)
  #
  # Plus the nav/footer link cascade, which reads from both config (data/
  # files) and frontmatter — it's loader-shaped, so it lives here too.
  #
  # No build-time mutation of pages happens in this class. Loaders return
  # arrays/hashes; Site stores them. Filtering for drafts / future-dated /
  # disabled / external-symlink pages happens at load time so downstream
  # code sees a clean list.
  class SiteLoader
    def initialize(site)
      @site = site
    end

    # Parse `config/site.yml`, apply per-environment overrides via
    # deep-merge. Returns a Hash. No env-var coercion or schema work
    # happens here — SiteConfig.validate! handles that downstream.
    def load_config
      # Site config is site-only (no engine fallback) — every consuming
      # site declares its own theme, Folio config, etc.
      site_root = ENV['ABQARI_SITE_ROOT'] || Dir.pwd
      path = File.join(site_root, 'config', 'site.yml')
      return {} unless File.exist?(path)

      raw = YAML.safe_load_file(path, permitted_classes: Abqari::YAML_PERMITTED_CLASSES) || {}
      envs = raw.delete('environments') || {}
      env  = @site.env.to_s
      overrides = envs[env] || {}

      warn_on_unknown_env(env, envs)

      deep_merge(raw, overrides)
    end

    # Walk `content/**/*.md`. For each markdown file:
    #   - Skip if it lives under a disabled collection's source dir.
    #   - Skip if it's an external symlink (escapes site_root).
    #   - Skip drafts unless ABQARI_INCLUDE_DRAFTS=true or drafts config
    #     allows it in this env.
    #   - Skip future-dated posts unless we're in dev or the env var
    #     is set.
    #   - Skip pages with `enabled: false` in frontmatter — total opt-out.
    #
    # Returns the surviving array of `Page` instances.
    def load_pages
      pattern = File.join(@site.site_root, 'content', '**', '*.md')
      pages = []

      Dir.glob(pattern).sort.each do |path|
        next if disabled_collection_path?(path)
        next if @site.external_symlink?(path)

        page = Page.new(path, @site)
        next if page.disabled?
        next if page.draft?  && !include_drafts?
        next if page.future? && !include_future?

        pages << page
      end

      pages
    end

    # Read every `data/**/*.{yml,yaml,json}` file into a hash keyed by
    # the path-relative-with-extension-stripped form:
    #
    #   data/nav.yml             → result['nav']
    #   data/foo/bar.yml         → result['foo_bar']
    #   data/testimonials.yml    → result['testimonials']
    #
    # YAML files use `YAML.safe_load` with `permitted_classes:
    # [Date, Time]` (the engine-wide allow-list) so naked dates and
    # ISO timestamps round-trip without opening up arbitrary class
    # instantiation.
    def load_data
      result = {}
      data_dir = File.join(@site.site_root, 'data')
      return result unless Dir.exist?(data_dir)

      Dir.glob(File.join(data_dir, '**', '*.{yml,yaml,json}')).sort.each do |path|
        rel = path.sub("#{data_dir}/", '')
        key = rel.sub(/\.(yml|yaml|json)\z/, '').tr('/', '_')
        raw = File.read(path, encoding: 'UTF-8')
        result[key] = if path.end_with?('.json')
                        JSON.parse(raw)
                      else
                        YAML.safe_load(raw, permitted_classes: Abqari::YAML_PERMITTED_CLASSES)
                      end
      end
      result
    end

    # Nav cascade: data/nav.yml `links:` array > frontmatter `nav:` blocks.
    def nav_links
      explicit_links_from('nav') || frontmatter_links_for('nav')
    end

    # Footer cascade: same shape as nav.
    def footer_links
      explicit_links_from('footer') || frontmatter_links_for('footer')
    end

    private

    # Warn when the operator explicitly set ABQARI_ENV to a value that
    # doesn't match any `environments.*` key in site.yml. The most
    # common case is a typo (`ABQARI_ENV=stage` when the config has
    # `staging:`); the silent fall-through to the base config is
    # surprising — the user thinks their per-env overrides are active
    # but they aren't.
    #
    # Only warns when:
    #   - ABQARI_ENV is set explicitly (not the defaulted "development")
    #   - the config has at least one environment defined
    #   - the requested env isn't among them
    #
    # Mismatches in defaulted-development mode stay silent — sites that
    # don't define environments at all shouldn't see noise.
    def warn_on_unknown_env(env, envs)
      return unless ENV['ABQARI_ENV']
      return if envs.empty?
      return if envs.key?(env)

      Log.warn(
        "ABQARI_ENV=#{env.inspect} doesn't match any environments.* key " \
        "in config/site.yml (defined: #{envs.keys.sort.map(&:inspect).join(', ')}). " \
        'Falling back to the base config without env-specific overrides.'
      )
    end

    # Layer 1 of the nav/footer cascade — explicit links array.
    def explicit_links_from(key)
      block = @site.data[key]
      return nil unless block.is_a?(Hash) && block['links'].is_a?(Array)

      block['links']
    end

    # Layer 2 — pages that opted in via frontmatter.
    def frontmatter_links_for(key)
      candidates = @site.pages.select { |page| page.frontmatter[key].is_a?(Hash) }
      candidates.sort_by { |page| page.frontmatter[key]['order'] || Float::INFINITY }.map do |page|
        block = page.frontmatter[key]
        { 'label' => block['label'] || page.title, 'url' => page.url }
      end
    end

    # True when the given source path lives under a disabled collection's
    # source dir. Disabled collections behave as if their files don't
    # exist — no pages, no taxonomy contributions, no nav entries.
    def disabled_collection_path?(path)
      @site.collections.any? do |_name, cfg|
        next false if cfg.fetch('enabled', true)

        source = File.join(@site.site_root, cfg['source'].to_s)
        path.start_with?(source + File::SEPARATOR)
      end
    end

    # Whether `published: false` posts render in this build.
    #
    # Resolution order (first match wins):
    #   1. ABQARI_INCLUDE_DRAFTS=true → always include
    #   2. Production → never include (drafts must not leak to live)
    #   3. Development → `drafts.show_in_development` config (default true)
    def include_drafts?
      return true if ENV['ABQARI_INCLUDE_DRAFTS'] == 'true'
      return false if @site.env == :production

      @site.config.dig('drafts', 'show_in_development') != false
    end

    def include_future?
      ENV['ABQARI_INCLUDE_FUTURE'] == 'true' || @site.env != :production
    end

    def deep_merge(base, override)
      base.merge(override) do |_, b, o|
        b.is_a?(Hash) && o.is_a?(Hash) ? deep_merge(b, o) : o
      end
    end
  end
end

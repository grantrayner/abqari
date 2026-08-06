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
      unless File.exist?(path)
        # Silent `{}` here means "wrong directory" or a typo'd
        # ABQARI_SITE_ROOT produces a defaults-only build with no signal.
        # Warn loudly (and let ABQARI_STRICT_CONFIG make it fatal).
        msg = "config/site.yml not found at #{path} — building with defaults only " \
              '(no title, no url). Are you in the site directory?'
        raise UserError, msg if ENV['ABQARI_STRICT_CONFIG'] == 'true'

        Log.warn msg
        return {}
      end

      raw = load_yaml_file(path) || {}
      envs = raw.delete('environments') || {}
      env  = @site.env.to_s
      overrides = envs[env] || {}

      warn_on_unknown_env(env, envs)

      deep_merge(raw, overrides)
    end

    # `YAML.safe_load_file` with the engine-wide permitted classes, and
    # a syntax error turned into something a person can act on.
    #
    # Psych's own message already names the file, line and column — the
    # problem was that it arrived at the top of a ten-frame trace
    # through Psych internals, which reads as an engine crash rather
    # than "line 12 of your config has a stray colon". Keep Psych's
    # detail, drop the frames (ABQARI_DEBUG=1 brings them back).
    def load_yaml_file(path)
      YAML.safe_load_file(path, permitted_classes: Abqari::YAML_PERMITTED_CLASSES)
    rescue Psych::SyntaxError => e
      rel = path.sub("#{@site.site_root}/", '')
      raise UserError, "#{rel}:#{e.line}:#{e.column} — invalid YAML: #{e.problem} #{e.context}".strip
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
        next if stray_bundle_markdown?(path)

        page = Page.new(path, @site)
        next if page.disabled?
        next if page.draft?  && !include_drafts?
        next if page.future? && !include_future?

        pages << page
      end

      pages
    end

    # True for a markdown file sitting INSIDE a bundle directory that
    # isn't that bundle's `index.md` — e.g.
    # `content/posts/my-post/notes.md`.
    #
    # A bundle is one content file plus its assets, so a second `.md`
    # has no defined role and used to get two contradictory ones: it was
    # copied verbatim into the output as a "bundle asset" (frontmatter
    # and all, even when marked `published: false`), AND loaded here as
    # a stray page rendering at `/posts/my-post/notes/` — because
    # `Page#collection` rejects it for not being an index, leaving it
    # uncollected rather than dropping it. Published twice, in two
    # forms, neither intended.
    #
    # The asset half is fixed by the publishable-extension allow-list.
    # This is the page half. Warn rather than skip silently: the author
    # put the file there for a reason and needs to know it does nothing.
    def stray_bundle_markdown?(path)
      return false if File.basename(path) == 'index.md'

      @site.collections.each do |_name, cfg|
        next unless cfg.fetch('enabled', true)
        next if cfg['bundle'] == false # flat collections: `<slug>.md` IS the page

        source = File.join(@site.site_root, cfg['source'].to_s)
        next unless path.start_with?(source + File::SEPARATOR)

        # Depth >= 2 means it's nested inside a slug directory rather
        # than sitting at the collection root.
        next unless path.sub("#{source}/", '').split('/').length >= 2

        rel = path.sub("#{@site.site_root}/", '')
        Log.warn "Skipping #{rel} — only `index.md` is rendered inside a bundle " \
                 'directory, so this file is neither published nor rendered. Move it ' \
                 'out to publish it, or rename it with a leading dot ' \
                 "(`.#{File.basename(path)}`) to keep it local and silence this."
        return true
      end

      false
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
        result[key] = if path.end_with?('.json')
                        begin
                          JSON.parse(File.read(path, encoding: 'UTF-8'))
                        rescue JSON::ParserError => e
                          raise UserError,
                                "data/#{rel} — invalid JSON: #{e.message.lines.first.to_s.strip}"
                        end
                      else
                        load_yaml_file(path)
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

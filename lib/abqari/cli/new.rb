# frozen_string_literal: true

require 'fileutils'
require 'optparse'
require 'erb'

module Abqari
  module CLI
    # `abqari new <projectname>` — scaffolds a new Abqari site by
    # recursive-copying `lib/abqari/templates/site_skeleton/` into the
    # target directory, with simple ERB token substitution on files
    # whose name ends in `.tt`. Modelled on Jekyll's `jekyll new`,
    # Rails's `rails new`, and Astro's `npm create astro@latest`.
    #
    # Defaults — zero prompts:
    #   * `title:`       = the projectname, title-cased
    #   * `description:` = a short placeholder
    #   * `author:`      = "Your name" (operator edits later)
    #   * `theme:`       = minimal
    #   * `locale:`      = en
    #   * Engine source  = whichever shape the user passes via
    #                      `--engine`. Defaults to "rubygems" (the
    #                      published gem, pinned to the current
    #                      major.minor).
    #
    # Flags:
    #   --name "..."          Site title (defaults to projectname)
    #   --description "..."   Site description
    #   --author "..."        Author
    #   --theme NAME          Theme (one of VALID_THEMES below)
    #   --locale CODE         ISO 639-1 (en, fr, ja, …)
    #   --with LIST           Extra collections to enable alongside posts
    #                         (comma-separated: photos, publications,
    #                         workshops — repeatable). For each one the
    #                         scaffold sets `enabled: true` in
    #                         config/site.yml AND creates the
    #                         `content/<name>/index.md` collection index
    #                         page (a real content file the engine does
    #                         not auto-generate). Everything stays
    #                         opt-in-able later by hand; the flag just
    #                         removes the copy-an-example friction.
    #   --engine SOURCE       'rubygems' (default — the published gem),
    #                         'git' (github URL placeholder — operator
    #                         edits to point at their fork), or 'path'
    #                         (path-source to ../abqari, useful for
    #                         engine devs).
    #   --blank               Bare-minimum scaffold: no example post,
    #                         no tutorial text on the home / about
    #                         pages, no in-line docs in
    #                         `config/site.yml`. Useful for users who
    #                         already know Abqari and want a clean
    #                         slate. Default mode includes a welcome
    #                         post, populated home page, and heavily-
    #                         commented config to demo the surface.
    #   --skip-bundle         Skip running `bundle install` afterwards
    #   --force               Overwrite target directory if non-empty
    class New
      VALID_THEMES = %w[minimal magazine notebook sand bootstrap custom none].freeze
      VALID_ENGINES = %w[rubygems git path].freeze
      # Collections `--with` can enable. Posts is always on — it's the
      # backbone collection (disable it in config/site.yml if you must).
      WITH_COLLECTIONS = %w[photos publications workshops].freeze

      # Skeleton paths that only copy when their collection is selected
      # via `--with`. Each matches itself and anything underneath it.
      COLLECTION_CONTENT_PATHS = {
        'photos'       => 'content/photos',
        'publications' => 'content/publications',
        'workshops'    => 'content/workshops'
      }.freeze

      # Directories that are example-only — skipped when --blank is
      # passed. Paths are relative to the skeleton root, no trailing
      # slash. Each path matches itself AND anything underneath it.
      BLANK_MODE_SKIP = %w[
        content/posts/welcome
      ].freeze

      # Engine-source line in the scaffolded Gemfile, one per --engine
      # option. The default pins to the running engine's major.minor so
      # a scaffolded site tracks patch releases but not breaking ones.
      # The git line defaults to the canonical repo so it bundles
      # out of the box — operators tracking a fork edit the URL.
      DEFAULT_RUBYGEMS_GEMFILE_LINE = "gem 'abqari', '~> #{Abqari::VERSION.split('.').first(2).join('.')}'"
      DEFAULT_GIT_GEMFILE_LINE      = "gem 'abqari', git: 'https://github.com/grantrayner/abqari.git'"
      DEFAULT_PATH_GEMFILE_LINE     = "gem 'abqari', path: '../abqari'"

      def self.run(argv)
        new.run(argv)
      end

      def initialize
        @options = {
          theme:         'minimal',
          locale:        'en',
          engine:        'rubygems',
          with:          [],
          blank:         false,
          skip_bundle:   false,
          force:         false
        }
      end

      def run(argv)
        parser = build_parser
        rest = parser.parse(argv)

        if rest.empty?
          warn parser.help
          warn "\nMissing required argument: projectname"
          return false
        end

        projectname = rest.first
        target_dir  = File.expand_path(projectname)

        return false unless preflight_ok?(target_dir)
        return false unless validate_options!

        copy_skeleton!(target_dir, build_template_vars(projectname))
        materialize_theme!(target_dir)
        run_bundle_install!(target_dir) unless @options[:skip_bundle]
        print_next_steps(projectname, target_dir)
        true
      end

      private

      def build_parser
        OptionParser.new do |opts|
          opts.banner = 'Usage: abqari new <projectname> [options]'
          opts.separator ''
          opts.separator 'Options:'
          opts.on('--name TITLE',         'Site title (defaults to projectname)')                 { |v| @options[:name] = v }
          opts.on('--description DESC',   'Site description')                                     { |v| @options[:description] = v }
          opts.on('--author NAME',        'Author')                                               { |v| @options[:author] = v }
          opts.on('--theme NAME',         "Theme (#{VALID_THEMES.join('/')})")                    { |v| @options[:theme] = v }
          opts.on('--locale CODE',        'ISO 639-1 locale (en, fr, ja, …)')                    { |v| @options[:locale] = v }
          opts.on('--engine SOURCE',      "Gem source: 'rubygems' (default), 'git', or 'path'")   { |v| @options[:engine] = v }
          opts.on('--with LIST', Array,   "Extra collections to enable (#{WITH_COLLECTIONS.join('/')}, comma-separated, repeatable)") { |v| @options[:with] |= v.map(&:strip) }
          opts.on('--blank',              'Minimum-viable scaffold (no example post, no tutorial text, no in-line config docs)') { @options[:blank] = true }
          opts.on('--skip-bundle',        "Don't run `bundle install` after scaffolding")         {     @options[:skip_bundle] = true }
          opts.on('--force',              'Overwrite the target directory if non-empty')         {     @options[:force] = true }
          opts.on('-h', '--help', 'Show this message') { puts opts; exit }
        end
      end

      # --- Preflight + validation ----------------------------------------

      def preflight_ok?(target_dir)
        if File.exist?(target_dir) && !@options[:force]
          contents = Dir.children(target_dir) rescue []
          unless contents.empty?
            warn "Target directory #{target_dir} already exists and is non-empty."
            warn 'Re-run with --force to overwrite, or pick a different name.'
            return false
          end
        end
        true
      end

      def validate_options!
        unless VALID_THEMES.include?(@options[:theme])
          warn "Unknown theme: #{@options[:theme].inspect}. Valid: #{VALID_THEMES.join(', ')}"
          return false
        end
        unless VALID_ENGINES.include?(@options[:engine])
          warn "Unknown --engine: #{@options[:engine].inspect}. Valid: #{VALID_ENGINES.join(', ')}"
          return false
        end
        unknown = @options[:with] - WITH_COLLECTIONS
        unless unknown.empty?
          warn "Unknown --with collection(s): #{unknown.join(', ')}. Valid: #{WITH_COLLECTIONS.join(', ')} (posts is always on)"
          return false
        end
        true
      end

      # --- Template vars passed to ERB (.tt) files ------------------------

      def build_template_vars(projectname)
        title = @options[:name] || titleize(projectname)
        {
          projectname:  projectname,
          title:        title,
          description:  @options[:description] || "A new Abqari site.",
          author:       @options[:author] || 'Your Name',
          theme:        @options[:theme],
          locale:       @options[:locale],
          with:         @options[:with],
          fonts_block:  fonts_block,
          gemfile_line: engine_gemfile_line,
          # Pins the scaffolded site to the Ruby doing the scaffolding.
          # Without a committed `.ruby-version`, a deploy host picks its
          # own default — which is how a site ends up building on a
          # newer Ruby than it was developed on, and hitting native gems
          # that ship no precompiled binary for it.
          ruby_version: RUBY_VERSION,
          year:         Time.now.year
        }
      end

      def engine_gemfile_line
        case @options[:engine]
        when 'rubygems' then DEFAULT_RUBYGEMS_GEMFILE_LINE
        when 'git'      then DEFAULT_GIT_GEMFILE_LINE
        when 'path'     then DEFAULT_PATH_GEMFILE_LINE
        end
      end

      # The scaffolded `fonts:` section, matched to the chosen theme.
      # Magazine and sand build their identity on webfonts their stacks
      # only *name* — without the matching `fonts:` block +
      # `bin/fetch-fonts`, both silently fall back to system serifs.
      # System-font themes get a commented example instead.
      def fonts_block
        entries = ThemeFonts.yaml_entries(@options[:theme], indent: '  ')
        if entries.empty?
          <<~YAML.rstrip
            # The #{@options[:theme]} theme uses system fonts — nothing to download.
            # To self-host Google Fonts later (each shipped theme's faces are
            # listed in the engine's docs/theming.md), declare them here and
            # run `bin/fetch-fonts` once:
            #
            # fonts:
            #   - family: Inter
            #     weights: [400, 600]
            #     style: normal
          YAML
        else
          <<~YAML.rstrip
            # Self-hosted webfonts for the #{@options[:theme]} theme — run
            # `bin/fetch-fonts` once to download them into vendor/fonts/
            # (served from your own origin; no requests to Google at visit
            # time). Switching theme later? Each shipped theme's faces are
            # listed in the engine's docs/theming.md.
            fonts:
            #{entries}
          YAML
        end
      end

      def titleize(slug)
        slug.to_s.tr('-_', ' ').split(/\s+/).map(&:capitalize).join(' ')
      end

      # --- Copy the skeleton, with .tt → ERB substitution ----------------
      #
      # Two modes:
      #   default — copy everything, render `.tt` files, skip `.blank.*`
      #             variants. Default mode is the "full" experience —
      #             example post, populated home page, commented config.
      #   --blank — skip directories listed in `BLANK_MODE_SKIP`, prefer
      #             `.blank.<ext>.tt` variants over the regular `.tt`
      #             when both exist. The blank variant renders at the
      #             same destination path (e.g. `content/index.blank.md.tt`
      #             → `content/index.md`).
      def copy_skeleton!(target_dir, vars)
        skeleton = File.expand_path('../templates/site_skeleton', __dir__)
        unless Dir.exist?(skeleton)
          raise "Site skeleton not found at #{skeleton}. (Engine install bug — please report.)"
        end

        FileUtils.mkdir_p(target_dir)

        blank = @options[:blank]

        Dir.glob(File.join(skeleton, '**', '*'), File::FNM_DOTMATCH).each do |src|
          next if %w[. ..].include?(File.basename(src))

          rel = src.sub(skeleton, '').sub(%r{\A/}, '')
          next if skip_in_mode?(rel, blank, skeleton)

          dest = File.join(target_dir, destination_for(rel))

          if File.directory?(src)
            FileUtils.mkdir_p(dest)
          elsif src.end_with?('.tt')
            File.write(dest, render_erb(File.read(src, encoding: 'UTF-8'), vars))
          else
            FileUtils.cp(src, dest)
            FileUtils.chmod('+x', dest) if File.executable?(src)
          end
        end

        puts "Created #{target_dir}#{' (blank scaffold)' if blank}"
      end

      # True when the skeleton entry at `rel` should not be copied in
      # the current mode. Two rules:
      #   1. Anything under a `BLANK_MODE_SKIP` path is dropped in
      #      blank mode.
      #   2. `.blank.<ext>.tt` files are skipped UNLESS we're in blank
      #      mode. In blank mode, the *non*-blank counterpart is the
      #      one that's skipped (the blank variant takes the slot).
      def skip_in_mode?(rel, blank, skeleton_root)
        if blank && BLANK_MODE_SKIP.any? { |p| rel == p || rel.start_with?("#{p}/") }
          return true
        end

        # Collection content dirs only scaffold when requested via
        # `--with` — an unselected collection stays config-off with no
        # stray content/<name>/ directory.
        COLLECTION_CONTENT_PATHS.each do |collection, path|
          next if @options[:with].include?(collection)
          return true if rel == path || rel.start_with?("#{path}/")
        end

        blank_variant = rel.include?('.blank.')
        return true if !blank && blank_variant

        if blank && rel.end_with?('.tt') && !blank_variant
          # Non-blank `.tt` is shadowed when a `.blank.<ext>.tt` sibling
          # exists. Compute the sibling path (`foo.md.tt` →
          # `foo.blank.md.tt`) and skip the regular file when present.
          # The regex only matches paths with at least two dots
          # (extension + .tt) — single-dot files like `Gemfile.tt`
          # have no blank variant by construction; guard against the
          # no-match case where `sub` returns the input unchanged and
          # we'd otherwise mistake the file for its own sibling.
          sibling = rel.sub(/(\.[^.]+)\.tt\z/, '.blank\1.tt')
          if sibling != rel && File.exist?(File.join(skeleton_root, sibling))
            return true
          end
        end
        false
      end

      # Map a skeleton-relative path to its destination path inside
      # the target site:
      #   * `.tt` suffix is stripped (`config/site.yml.tt` → `config/site.yml`)
      #   * `.blank.` segment collapses to `.` so a blank variant renders
      #     at the same destination as the full one (`index.blank.md.tt`
      #     → `index.md`).
      def destination_for(rel)
        rel.sub('.blank.', '.').sub(/\.tt\z/, '')
      end

      # ERB with `trim_mode: '-'` so `<%- -%>` strips its surrounding
      # whitespace cleanly. Vars are bound via a small struct so the
      # template can reference them as locals (`title`, `description`,
      # etc.) without ceremony.
      def render_erb(src, vars)
        ERB.new(src, trim_mode: '-').result_with_hash(vars)
      end

      # --- Theme materialization ------------------------------------------
      #
      # Two theme choices need files the generic skeleton doesn't carry:
      #
      #   * `--theme none` — the engine requires no CSS for `none`, but a
      #     site with zero stylesheets is rarely the intent. Scaffold a
      #     commented, empty `app/assets/css/app.css` so there's an
      #     obvious file to write into (and the CSS bundle has its
      #     anchor).
      #   * `--theme custom` — the starter used to load from inside the
      #     installed gem, where the user can't (and shouldn't) edit it.
      #     Copy it into the site's `themes/custom/`, which shadows the
      #     gem's copy; their edits live in their repo.
      def materialize_theme!(target_dir)
        case @options[:theme]
        when 'none'
          dest = File.join(target_dir, 'app', 'assets', 'css', 'app.css')
          FileUtils.mkdir_p(File.dirname(dest))
          File.write(dest, <<~CSS)
            /* `theme: none` — no engine CSS at all (not even _common.css).
             * This file is yours; the build bundles it with the syntax
             * stylesheet and app/assets/css/site.css if present. */
          CSS
        when 'custom'
          src  = File.join(Abqari::ROOT, 'themes', 'custom', 'css', 'app.css')
          dest = File.join(target_dir, 'themes', 'custom', 'css', 'app.css')
          FileUtils.mkdir_p(File.dirname(dest))
          FileUtils.cp(src, dest)
          puts 'Copied the custom-theme starter to themes/custom/css/app.css — edit away.'
        end
      end

      # --- `bundle install` after scaffolding -----------------------------

      def run_bundle_install!(target_dir)
        puts ''
        puts 'Running bundle install...'
        Dir.chdir(target_dir) do
          success = system('bundle', 'install')
          unless success
            warn '[warn] `bundle install` failed. Run it manually inside the project, or check the Gemfile.'
          end
        end
      end

      def print_next_steps(projectname, _target_dir)
        puts ''
        puts 'Next:'
        puts "  cd #{projectname}"
        unless ThemeFonts.for(@options[:theme]).empty?
          puts "  bin/fetch-fonts      # download the #{@options[:theme]} theme's webfonts"
        end
        puts '  bin/serve            # dev server on http://localhost:4000'
        puts ''
        puts 'Then:'
        puts '  - Edit config/site.yml — set `url:`, social handles, etc.'
        puts '  - Edit content/index.md — your home page.'
        puts '  - `bin/new post "Title"` to scaffold a new post.'
        puts '  - `bin/build` for a production build.'
      end
    end
  end
end

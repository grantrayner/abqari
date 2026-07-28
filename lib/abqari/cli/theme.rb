# frozen_string_literal: true

require 'fileutils'
require 'optparse'

module Abqari
  module CLI
    # `abqari theme eject <name>` — copy an engine theme's stylesheet
    # into the current site so it can be edited there.
    #
    # Why this exists: for a gem-installed site the engine's themes live
    # inside the gem directory — read-only in practice, and invisible to
    # anyone who doesn't know about `bundle show abqari`. The asset
    # pipeline already gives site-local `themes/<name>/` precedence over
    # the engine's copy, so "make a theme yours" is just a copy into the
    # right place. This command does that copy.
    #
    #   abqari theme eject minimal              # shadow it in place:
    #                                           # themes/minimal/css/app.css
    #   abqari theme eject minimal --as mytheme # fork it under a new name
    #                                           # and point config at it
    #   abqari theme eject custom               # the annotated starter
    #
    # `--as` writes the copy under the new name and updates `theme:` in
    # config/site.yml (when the line is unambiguous). Ejecting under the
    # SAME name needs no config change — the site-local copy shadows the
    # engine's automatically.
    #
    # Bootstrap is the one theme that can't be renamed: the engine keys
    # its special-casing (skip `_common.css`, emit the vendored dist's
    # link/script tags) on the literal name 'bootstrap'.
    class Theme
      def self.run(argv)
        new.run(argv)
      end

      def initialize
        @options = { as: nil, force: false }
      end

      def run(argv)
        parser = build_parser
        rest = parser.parse(argv)

        subcommand, name = rest
        unless subcommand == 'eject' && name
          warn parser.help
          return false
        end

        eject(name)
      end

      private

      def build_parser
        OptionParser.new do |opts|
          opts.banner = <<~BANNER
            Usage: abqari theme eject <name> [options]

            Copies the engine theme's css/app.css into this site's
            themes/ directory, where it shadows the gem's copy and your
            edits live in your repo.

            Available themes: #{engine_theme_names.join(', ')}
          BANNER
          opts.separator ''
          opts.separator 'Options:'
          opts.on('--as NAME', 'Eject under a different theme name (updates config/site.yml)') { |v| @options[:as] = v }
          opts.on('--force',   'Overwrite an existing themes/<name>/css/app.css')             { @options[:force] = true }
          opts.on('-h', '--help', 'Show this message') { puts opts; exit }
        end
      end

      def eject(name)
        target_name = @options[:as] || name

        return false unless valid_names?(name, target_name)
        return false unless site_root?

        src = File.join(Abqari::ROOT, 'themes', name, 'css', 'app.css')
        unless File.file?(src)
          warn "Unknown theme #{name.inspect}. Available: #{engine_theme_names.join(', ')}"
          return false
        end

        if name == 'bootstrap' && target_name != 'bootstrap'
          warn "The bootstrap theme can't be ejected under another name — the engine keys"
          warn "its special-casing (vendored dist links, no _common.css) on the literal"
          warn "name 'bootstrap'. Use `abqari theme eject bootstrap` to shadow it in place."
          return false
        end

        dest = File.join('themes', target_name, 'css', 'app.css')
        if File.exist?(dest) && !@options[:force]
          warn "#{dest} already exists. Re-run with --force to overwrite."
          return false
        end

        FileUtils.mkdir_p(File.dirname(dest))
        FileUtils.cp(src, dest)
        puts "Ejected #{name} → #{dest}"

        point_config_at(target_name) if target_name != current_config_theme
        print_next_steps(dest)
        true
      end

      def valid_names?(*names)
        names.uniq.each do |n|
          next if n.match?(AssetPipeline::THEME_NAME_RE)

          warn "Invalid theme name #{n.inspect}: lowercase letters, digits, '-', '_' only."
          return false
        end
        true
      end

      def site_root?
        return true if File.file?(File.join('config', 'site.yml'))

        warn 'No config/site.yml here — run this from your site root.'
        false
      end

      def engine_theme_names
        Dir.children(File.join(Abqari::ROOT, 'themes')).sort
      end

      def current_config_theme
        config_path = File.join('config', 'site.yml')
        File.read(config_path, encoding: 'UTF-8')[/^theme:\s*(\S+)/, 1]
      rescue StandardError
        nil
      end

      # Point `theme:` at the ejected name. Config files are the
      # operator's — hand-commented, hand-ordered — so only a
      # single unambiguous `theme:` line is edited in place; anything
      # else gets an instruction instead of a surprise rewrite.
      def point_config_at(target_name)
        config_path = File.join('config', 'site.yml')
        config = File.read(config_path, encoding: 'UTF-8')

        if config.scan(/^theme:.*$/).size == 1
          File.write(config_path, config.sub(/^theme:.*$/, "theme: #{target_name}"))
          puts "Set `theme: #{target_name}` in config/site.yml"
        else
          puts "Now set `theme: #{target_name}` in config/site.yml"
        end
      end

      def print_next_steps(dest)
        puts ''
        puts 'Next:'
        puts "  - Edit #{dest} — start with the :root token blocks."
        puts '  - bin/serve to preview; theme edits hot-reload.'
      end
    end
  end
end

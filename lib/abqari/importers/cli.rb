# frozen_string_literal: true

require 'optparse'

module Abqari
  module Importers
    # Argv parser + dispatcher for `bin/import`. Lives in the
    # importers namespace because it depends on the registry —
    # if you add a new importer to `Importers::REGISTRY`, this
    # CLI surfaces it automatically.
    class CLI
      def self.run(argv, site_root: Dir.pwd)
        new(site_root: site_root).run(argv)
      end

      def initialize(site_root:)
        @site_root = site_root
        @options = {
          collection:      'posts',
          download_images: true,
          flat:            false,
          force:           false,
          dry_run:         false,
          write_canonical: false,
          strip_selectors: []
        }
      end

      def run(argv)
        platform, *rest = argv

        # An explicit `--help` is a success; being invoked with nothing
        # is a usage error. Both printed help and returned true, so
        # `bin/import` alone exited 0 — out of step with every other
        # command here (`abqari new` and `abqari theme` with no args
        # both exit 1) and a trap for any script checking the status.
        if %w[-h --help help].include?(platform)
          print_help
          return true
        end

        if platform.nil?
          warn 'Missing required argument: platform'
          warn ''
          print_help
          return false
        end

        importer_class = Importers.lookup(platform)
        unless importer_class
          warn "Unknown importer: #{platform.inspect}"
          warn ''
          print_help
          return false
        end

        parser = build_parser(platform)
        # `permute!` allows options to appear after the positional source
        # path. `order!` (the default) stops at the first non-option arg,
        # which silently drops trailing flags like `--keep-remote`.
        rest = parser.permute(rest)

        if rest.empty?
          warn "Usage: bin/import #{platform} <source> [options]"
          return false
        end
        source = rest.shift

        opts = Base::Options.new(
          site_root:       @site_root,
          collection:      @options[:collection],
          download_images: @options[:download_images],
          flat:            @options[:flat],
          force:           @options[:force],
          dry_run:         @options[:dry_run],
          write_canonical: @options[:write_canonical],
          strip_selectors: @options[:strip_selectors],
          logger:          ->(line) { puts line }
        )

        puts "Importing from #{platform} (#{source})…"
        puts "Mode: dry-run (no files written)" if opts.dry_run

        importer = importer_class.new(source: source, opts: opts)
        report = importer.run!

        puts ''
        puts report.summary_line
        unless opts.dry_run
          puts "Report: ./_import_report.md"
        end
        true
      rescue StandardError => e
        warn "Import failed: #{e.class}: #{e.message}"
        warn e.backtrace.first(8).join("\n") if ENV['ABQARI_DEBUG']
        false
      end

      private

      def build_parser(platform)
        OptionParser.new do |opts|
          opts.banner = "Usage: bin/import #{platform} <source> [options]"
          opts.separator ''
          opts.separator 'Options:'
          opts.on('--into COLLECTION',
                  'Destination collection (default: posts)') do |v|
            @options[:collection] = v
          end
          opts.on('--keep-remote',
                  'Leave image URLs as remote references instead of downloading') do
            @options[:download_images] = false
          end
          opts.on('--flat',
                  'Write flat-file posts (content/<col>/<slug>.md) instead of bundles') do
            @options[:flat] = true
          end
          opts.on('--dry-run',
                  'Process the source but write nothing to disk') do
            @options[:dry_run] = true
          end
          opts.on('--force',
                  'Overwrite existing files (default: skip)') do
            @options[:force] = true
          end
          opts.on('--canonical',
                  'Write `canonical_url:` to frontmatter for SEO mirroring') do
            @options[:write_canonical] = true
          end
          opts.on('--strip SEL', Array,
                  'Extra CSS-style selectors to strip (comma-separated)') do |list|
            @options[:strip_selectors].concat(list)
          end
          opts.on('-h', '--help', 'Show this help') do
            puts opts
            exit 0
          end
        end
      end

      def print_help
        puts <<~HELP
          Usage: bin/import <platform> <source> [options]

          Platforms:
        HELP
        Importers::REGISTRY.each do |name, info|
          puts "    #{name.ljust(10)} #{info[:description]}"
        end
        puts <<~HELP

          Common options:
            --into COLLECTION   Destination collection (default: posts)
            --keep-remote       Leave image URLs alone instead of downloading
            --flat              Flat-file posts instead of bundles
            --dry-run           Preview without writing
            --force             Overwrite existing files (default: skip)
            --canonical         Write canonical_url: to frontmatter
            --strip SEL,SEL     Extra selectors to strip before MD conversion

          Examples:
            bin/import substack ~/Downloads/substack-export.zip
            bin/import ghost ~/Downloads/export.json --into notes
            bin/import jekyll ~/old-site/ --dry-run
        HELP
      end
    end
  end
end

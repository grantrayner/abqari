# frozen_string_literal: true

require 'json'
require 'optparse'

module Abqari
  module CLI
    # `abqari headers` — print the built `_site/_headers` as rules for
    # hosts that don't read that file.
    #
    # Render static sites ignore `_headers`: the CSP, the security
    # headers and the year-long `immutable` cache on `/assets/*` all
    # have to be entered in the dashboard or `render.yaml`. Without the
    # cache rule Render serves assets with `max-age=0`, so fonts are
    # revalidated on every page and text flashes in the fallback font.
    #
    # It reads the BUILT file rather than computing headers itself, so
    # the CSP hashes are the ones the site's own bundled engine and
    # config produced. The global `abqari` on PATH may be a different
    # version, and one hash (speculation rules) depends on config.
    #
    #   bin/build && bundle exec abqari headers
    #   bundle exec abqari headers path/to/_site
    class Headers
      DEFAULT_PATH = File.join('_site', '_headers')

      def self.run(argv)
        new.run(argv)
      end

      def run(argv)
        rest = build_parser.parse(argv)
        path = resolve(rest.first || DEFAULT_PATH)

        unless File.file?(path)
          warn "No headers file at #{path}. Run `bin/build` first (it writes _site/_headers)."
          return false
        end

        rules = parse(File.read(path, encoding: 'UTF-8'))
        if rules.empty?
          warn "#{path} has no header rules."
          return false
        end

        puts render_yaml(rules)
        true
      end

      # `_headers` blocks: an unindented path line, then indented
      # `Name: value` lines. Same shape HeadersFile writes, for both the
      # generated policy and a `headers:` override in site.yml.
      def parse(text)
        path = nil
        text.each_line.with_object([]) do |line, rules|
          next if line.strip.empty? || line.lstrip.start_with?('#')

          if line.match?(/\A\S/)
            path = line.strip
          elsif path
            name, value = line.strip.split(/:\s*/, 2)
            rules << { 'path' => path, 'name' => name, 'value' => value.to_s } unless name.to_s.empty?
          end
        end
      end

      private

      def resolve(path)
        File.directory?(path) ? File.join(path, '_headers') : path
      end

      # JSON strings are valid YAML double-quoted scalars, so the CSP's
      # quotes, colons and semicolons survive a paste untouched.
      def render_yaml(rules)
        lines = rules.flat_map do |rule|
          ["  - path: #{rule['path'].to_json}",
           "    name: #{rule['name']}",
           "    value: #{rule['value'].to_json}"]
        end
        <<~YAML
          # Render doesn't read _site/_headers. Paste this block under your static
          # site in render.yaml, or add each rule (Path, Name, Value) in the
          # dashboard under Settings → Headers.
          #
          # The Content-Security-Policy pins SHA-256 hashes of Abqari's inline
          # scripts, and one depends on config. After upgrading abqari or changing
          # config/site.yml, rebuild, re-run this, and re-copy any rule that changed.
          headers:
          #{lines.join("\n")}
        YAML
      end

      def build_parser
        OptionParser.new do |opts|
          opts.banner = <<~BANNER
            Usage: abqari headers [path]

            Prints the built _site/_headers (or the _headers file / output
            directory at [path]) as Render header rules, ready for render.yaml
            or the dashboard's Settings → Headers. Run bin/build first.
          BANNER
          opts.on('-h', '--help', 'Show this message') { puts opts; exit }
        end
      end
    end
  end
end

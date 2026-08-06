# frozen_string_literal: true

require 'csv'
require 'fileutils'
require 'tmpdir'
require 'uri'

module Abqari
  module Importers
    # Substack export importer.
    #
    # Substack's export shape (as of 2025–2026):
    #
    #   substack-export/
    #     posts.csv              # post_id, post_date, title, subtitle,
    #                            #   type, audience, status, slug,
    #                            #   email_sent_at, ...
    #     posts/
    #       12345.html
    #       67890.html
    #
    # Some columns vary across export vintages (Substack rolls schema
    # changes silently). The reader is tolerant — we look up columns
    # by name, default missing ones to nil, and never assume column
    # ordering.
    #
    # Source accepts both a `.zip` (auto-extracted to a tmp dir) and
    # an already-unzipped directory. Zip extraction uses the shell
    # `unzip` so we don't pull in rubyzip as a dep — the operator
    # is running this from a CLI environment that has `unzip` on
    # every Mac/Linux system.
    class Substack < Base
      # Substack chrome to strip before HTML→Markdown conversion.
      # Each entry is a `tag.class` pair that HtmlToMarkdown can
      # parse — see `Support::HtmlToMarkdown.parse_selector`.
      #
      # These selectors come from inspecting the actual HTML
      # Substack ships in 2025 exports. New chrome blocks appear
      # periodically; users can add their own via `--strip-selectors`
      # without forking this list.
      def self.strip_selectors
        %w[
          div.subscription-widget-wrap
          div.subscription-widget
          div.button-wrapper
          div.footnote-hovercard
          aside.poll
          aside.subscribe-widget
          div.embedded-publication-wrap
          div.share-dialog
          div.captioned-button-wrap
        ]
      end

      def each_post
        with_export_root do |root|
          manifest_path = File.join(root, 'posts.csv')
          unless File.exist?(manifest_path)
            raise "Substack export missing posts.csv at #{manifest_path}"
          end

          CSV.foreach(manifest_path, headers: true, encoding: 'UTF-8') do |row|
            next unless publishable?(row)

            html_path = File.join(root, 'posts', "#{row['post_id']}.html")
            unless File.exist?(html_path)
              # Some rows in posts.csv have no corresponding HTML
              # file (email-only sends, draft cleanup). Skip rather
              # than fail the run.
              next
            end

            body_html = File.read(html_path, encoding: 'UTF-8')
            yield Base::ImportedPost.new(
              title:             row['title'],
              slug:              row['slug'] || derive_slug_from_title(row['title']),
              date:              parse_date(row['post_date']),
              body_html:         body_html,
              tags:              [], # Substack export doesn't include tags in posts.csv
              description:       row['subtitle'],
              feature_image_url: nil, # Substack inlines hero images in the body
              source_url:        row['post_url'],
              source_slug:       row['slug'],
              extra_frontmatter: substack_extras(row)
            )
          end
        end
      end

      private

      def publishable?(row)
        status   = row['status'].to_s.downcase
        type     = row['type'].to_s.downcase
        audience = row['audience'].to_s.downcase
        return false unless status.empty? || status == 'published'
        # Skip podcast episodes and email-only thread posts — they
        # don't have body HTML in the export shape we know about.
        return false if %w[podcast thread].include?(type)
        # Mark paid-only posts (we still import them, but flag in fm)
        # via substack_extras; this method just decides import vs skip.
        true
      end

      def substack_extras(row)
        audience = row['audience'].to_s.downcase
        extras = {}
        extras['audience'] = audience if audience == 'only_paid'
        extras
      end

      def parse_date(value)
        return nil if value.to_s.empty?
        # Substack uses ISO-8601 like 2024-03-15T10:00:00.000Z.
        Date.parse(value)
      rescue ArgumentError
        nil
      end

      def derive_slug_from_title(title)
        Support::SlugNormalizer.normalize(title.to_s)
      end

      # Substack URLs are `https://<sub>.substack.com/p/<slug>`. We
      # write `/p/<slug>/` as the redirect_from so existing inbound
      # links keep working after migration. We can't recover the
      # subdomain reliably from the export, so the host part stays
      # implicit — the engine matches the path-only form.
      def redirects_for(source_slug)
        slug = source_slug.to_s.strip
        return nil if slug.empty?
        ["/p/#{slug}/"]
      end

      # Yield the directory holding `posts.csv`. Handles both a
      # directory source and a zip — extracts the zip to a tempdir,
      # cleans up when the block returns.
      def with_export_root(&block)
        if File.directory?(@source)
          yield resolve_root(@source)
        elsif File.file?(@source) && @source.end_with?('.zip')
          Dir.mktmpdir('abqari-substack-') do |tmp|
            unless system('unzip', '-q', @source, '-d', tmp)
              raise "Failed to unzip #{@source}. Is `unzip` on PATH?"
            end
            assert_extraction_contained!(tmp)
            yield resolve_root(tmp)
          end
        else
          raise "Unrecognised source: #{@source} (expected a directory or .zip)"
        end
      end

      # The zip sometimes nests everything under a single top-level
      # Verify the extraction actually stayed inside the tempdir.
      #
      # Defence in depth, not a known hole: the `unzip` call is argv-form
      # so there's no shell injection, and modern Info-ZIP already
      # refuses `../` entries and strips leading slashes. But an export
      # zip is the least-trusted input this engine accepts, and we're
      # delegating containment to a third-party binary whose behaviour
      # varies by build — busybox's unzip has had traversal bugs, and
      # "whatever `unzip` is on PATH" is not a guarantee we control.
      # Cheap to check, so check.
      #
      # Symlinks are refused outright rather than resolved: a Substack
      # export has no legitimate use for one, and refusing avoids having
      # to reason about multi-hop chains where an intermediate link
      # points outside.
      def assert_extraction_contained!(tmp)
        root = File.realpath(tmp)

        Dir.glob(File.join(tmp, '**', '*'), File::FNM_DOTMATCH).each do |entry|
          next if %w[. ..].include?(File.basename(entry))

          if File.symlink?(entry)
            raise "Refusing to import #{@source}: the archive contains a symlink " \
                  "(#{entry.sub("#{tmp}/", '')}). Extract it yourself and import the " \
                  'directory if you trust its contents.'
          end

          begin
            PathSafe.assert_under(root, File.realpath(entry))
          rescue PathSafe::Error, Errno::ENOENT
            raise "Refusing to import #{@source}: the archive extracted a path outside " \
                  "the temporary directory (#{entry}). This archive is not safe to import."
          end
        end
      end

      # directory; sometimes it dumps `posts.csv` + `posts/` directly
      # at the root. Detect by looking for `posts.csv` at each level.
      def resolve_root(root)
        return root if File.exist?(File.join(root, 'posts.csv'))

        nested = Dir.children(root).map { |name| File.join(root, name) }.select { |p| File.directory?(p) }
        nested.each do |sub|
          return sub if File.exist?(File.join(sub, 'posts.csv'))
        end
        root # caller will raise on the missing-CSV check
      end
    end
  end
end

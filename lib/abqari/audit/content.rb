# frozen_string_literal: true

require 'yaml'

module Abqari
  class Audit
    # Content-quality rule:
    #   - Posts without a frontmatter `description:` (warn)
    #   - Tags used by only one post (info)
    #   - Frontmatter values that fall outside an operator-supplied
    #     whitelist (warn) — see `validate:` in config/site.yml
    #   - `series_position:` problems that break prev/next navigation
    #     silently (warn / info)
    class Content < Rule
      def run
        flag_posts_without_description
        flag_single_use_tags
        check_frontmatter_whitelists
        flag_series_position_problems
      end

      private

      def flag_posts_without_description
        @site.posts.each do |post|
          next if post.frontmatter['description'].to_s.length.positive?

          add(category: 'content', severity: 'warn', location: post.url,
              message: 'Post has no description',
              suggestion: 'Add a `description:` to front matter for OG/SEO')
        end
      end

      def flag_single_use_tags
        @site.posts_by_term('tags').each do |tag, posts|
          next if posts.size > 1

          add(category: 'content', severity: 'info', location: posts.first.url,
              message: "Tag '#{tag}' is used by only one post",
              suggestion: 'Consolidate with a related tag or remove')
        end
      end

      # Frontmatter validation against operator-supplied whitelists.
      # `validate:` in config/site.yml maps a frontmatter field to a
      # YAML data file whose top-level keys are the allowed values:
      #
      #   validate:
      #     country: data/countries.yml
      #     language: data/languages.yml
      #
      # Catches typos before they ship as broken `/country/syra/` pages.
      def check_frontmatter_whitelists
        validate_cfg = @site.config['validate']
        return unless validate_cfg.is_a?(Hash) && validate_cfg.any?

        whitelists = load_whitelists(validate_cfg)
        flag_unknown_values(whitelists)
      end

      def load_whitelists(validate_cfg)
        whitelists = {}
        validate_cfg.each do |field, path|
          full = File.join(@site.site_root, path.to_s)
          next unless File.exist?(full)

          data = YAML.safe_load_file(full, permitted_classes: Abqari::YAML_PERMITTED_CLASSES) || {}
          whitelists[field] = data.keys.map { |k| k.to_s.downcase } if data.is_a?(Hash)
        end
        whitelists
      end

      # Series ordering problems. All three findings here share a
      # failure mode: the page still builds, still appears on its series
      # index, and still looks correct in isolation — only the prev/next
      # chain quietly loses it. Nothing else in the build surfaces that,
      # which is what makes them worth an audit rule.
      #
      # `Site#series_sibling` requires an Integer position (a quoted
      # YAML "3" is skipped) and compares strictly (two pages sharing a
      # position are invisible to each other, so the chain skips one).
      #
      # Scoped per collection, matching how the series taxonomies and
      # `series_sibling` scope: a lesson and a post with the same
      # `series:` value are independent series, not one shared run.
      def flag_series_position_problems
        pages_in_series.group_by { |page| [page.collection, page.frontmatter['series'].to_s] }
                       .each { |(_collection, series), pages| check_series_positions(series, pages) }
      end

      def pages_in_series
        @site.all_pages.select do |page|
          next false unless page.respond_to?(:collection) && page.collection
          next false unless page.respond_to?(:frontmatter) && page.frontmatter.is_a?(Hash)

          !page.frontmatter['series'].to_s.strip.empty?
        end
      end

      def check_series_positions(series, pages)
        by_position = {}

        pages.each do |page|
          position = page.frontmatter['series_position']

          if position.nil?
            add(category: 'content', severity: 'info', location: page.url,
                message: "In series '#{series}' but has no series_position",
                suggestion: 'Add an Integer `series_position:` so prev/next navigation can order it')
          elsif !position.is_a?(Integer)
            add(category: 'content', severity: 'warn', location: page.url,
                message: "series_position #{position.inspect} is a #{position.class}, not an Integer",
                suggestion: 'Unquote the value — a non-Integer position is skipped by prev/next navigation')
          else
            (by_position[position] ||= []) << page
          end
        end

        flag_duplicate_positions(series, by_position)
      end

      def flag_duplicate_positions(series, by_position)
        by_position.each do |position, sharers|
          next if sharers.size < 2

          others = sharers.size - 1
          sharers.each do |page|
            add(category: 'content', severity: 'warn', location: page.url,
                message: "series_position #{position} in '#{series}' is shared with " \
                         "#{others} other #{others == 1 ? 'page' : 'pages'}",
                suggestion: 'Give each page a distinct position — duplicates make prev/next skip one')
          end
        end
      end

      def flag_unknown_values(whitelists)
        @site.taxonomy_pages.each do |page|
          whitelists.each do |field, allowed|
            values = Array(page.frontmatter[field]).reject { |v| v.to_s.strip.empty? }
            next if values.empty?

            values.each do |value|
              next if allowed.include?(value.to_s.downcase)

              add(category: 'content', severity: 'warn', location: page.url,
                  message: "Unrecognised #{field}: '#{value}'",
                  suggestion: 'Add it to the whitelist file or check for a typo')
            end
          end
        end
      end
    end
  end
end

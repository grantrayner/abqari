# frozen_string_literal: true

require 'yaml'

module Abqari
  class Audit
    # Content-quality rule:
    #   - Posts without a frontmatter `description:` (warn)
    #   - Tags used by only one post (info)
    #   - Frontmatter values that fall outside an operator-supplied
    #     whitelist (warn) — see `validate:` in config/site.yml
    class Content < Rule
      def run
        flag_posts_without_description
        flag_single_use_tags
        check_frontmatter_whitelists
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

          data = YAML.safe_load_file(full) || {}
          whitelists[field] = data.keys.map { |k| k.to_s.downcase } if data.is_a?(Hash)
        end
        whitelists
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

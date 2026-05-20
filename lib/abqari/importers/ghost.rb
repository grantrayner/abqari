# frozen_string_literal: true

require 'json'

module Abqari
  module Importers
    # Ghost JSON-export importer.
    #
    # Ghost's export shape (5.x / 6.x):
    #
    #   {
    #     "db": [{
    #       "data": {
    #         "posts":      [ { id, slug, title, html, mobiledoc,
    #                           published_at, status, visibility,
    #                           feature_image, custom_excerpt, ... } ],
    #         "tags":       [ { id, name, slug, ... } ],
    #         "posts_tags": [ { post_id, tag_id, ... } ],
    #         "users":      [ { id, name, ... } ]
    #       }
    #     }]
    #   }
    #
    # We resolve tags via the join table. `mobiledoc` is a richer
    # source representation than `html` but Ghost's renderer
    # already produces the HTML field for us — using `html` keeps
    # the importer simple. Sites that need fancier conversion (e.g.
    # preserving Ghost bookmark cards as native blocks) can add
    # mobiledoc parsing in a later pass.
    class Ghost < Base
      def self.strip_selectors
        %w[
          figure.kg-bookmark-card
          div.kg-callout-card
          figure.kg-product-card
          figure.kg-signup-card
          figure.kg-button-card
        ]
      end

      def each_post
        data = load_data

        tag_lookup    = index_by(data['tags'] || [], 'id') { |t| t['name'] }
        post_tag_join = (data['posts_tags'] || []).group_by { |j| j['post_id'] }

        (data['posts'] || []).each do |post|
          next unless publishable?(post)

          tag_ids = (post_tag_join[post['id']] || []).map { |j| j['tag_id'] }
          tags    = tag_ids.map { |id| tag_lookup[id] }.compact

          yield Base::ImportedPost.new(
            title:             post['title'],
            slug:              post['slug'],
            date:              parse_date(post['published_at']),
            body_html:         post['html'].to_s,
            tags:              tags,
            description:       post['custom_excerpt'] || post['meta_description'],
            feature_image_url: post['feature_image'],
            source_url:        nil, # Ghost export omits the canonical site URL
            source_slug:       post['slug'],
            extra_frontmatter: ghost_extras(post)
          )
        end
      end

      private

      def load_data
        raw = File.read(@source, encoding: 'UTF-8')
        parsed = JSON.parse(raw)
        # Some Ghost versions wrap data in `db: [...]`, others
        # ship `data: {...}` directly. Handle both.
        wrapped = parsed['db'].is_a?(Array) ? parsed.dig('db', 0, 'data') : nil
        wrapped || parsed['data'] || parsed
      end

      def publishable?(post)
        post['status'].to_s == 'published' || post['status'].nil?
      end

      def ghost_extras(post)
        extras = {}
        # Visibility (`public` / `members` / `paid`) is content-policy
        # metadata that may matter to the operator post-import.
        if post['visibility'] && post['visibility'] != 'public'
          extras['visibility'] = post['visibility']
        end
        extras
      end

      def parse_date(value)
        return nil if value.to_s.empty?
        Date.parse(value)
      rescue ArgumentError
        nil
      end

      def redirects_for(source_slug)
        slug = source_slug.to_s.strip
        return nil if slug.empty?
        ["/#{slug}/"]
      end

      def index_by(arr, key)
        out = {}
        arr.each { |row| out[row[key]] = block_given? ? yield(row) : row }
        out
      end
    end
  end
end

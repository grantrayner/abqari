# frozen_string_literal: true

require 'json'
require 'cgi'
require 'fileutils'

module Abqari
  # Generates RSS + JSON Feed for a single collection. Per-collection
  # feeds are opt-in via `collections.<name>.feeds.enabled` (default
  # true for posts — back-compat — and false for everything else).
  #
  # Output paths:
  #   posts        →  /feed.xml + /feed.json   (back-compat root paths)
  #   <other>      →  /<collection>/feed.xml + /<collection>/feed.json
  #
  # The root `/feed.xml` for posts is intentional: pre-existing
  # subscribers + feed-reader caches keep working without redirects.
  class Feed
    MAX_ITEMS = 20

    def initialize(site, collection_name = 'posts')
      @site = site
      @collection_name = collection_name
    end

    def write
      return if items.empty?
      return unless base_url

      FileUtils.mkdir_p(File.dirname(rss_path))
      File.write(rss_path,  rss)
      File.write(json_path, json_feed)
    end

    # Class-level entry point: writes feeds for every collection that
    # has `feeds.enabled: true`. Defaults to true only for posts so
    # existing sites don't suddenly start emitting photo / publication
    # feeds without opt-in.
    def self.write_all(site)
      site.collections.each do |name, cfg|
        next unless cfg.fetch('enabled', true)

        feeds_enabled = cfg.dig('feeds', 'enabled')
        feeds_enabled = (name == 'posts') if feeds_enabled.nil?
        next unless feeds_enabled

        new(site, name).write
      end
    end

    private

    def items
      @items ||= @site.collection(@collection_name)
                       .select { |p| p.respond_to?(:date) && p.date }
                       .first(MAX_ITEMS)
    end

    def base_url
      @site.config['url']&.sub(%r{/\z}, '')
    end

    # Posts → /feed.xml + /feed.json (back-compat root paths).
    # Other  → /<collection>/feed.xml + /<collection>/feed.json
    #
    # If `posts` is renamed via `slug:` (e.g. slug: stories), the feed
    # follows: /stories/feed.xml + /stories/feed.json. The `/feed.xml`
    # root path is reserved for un-renamed posts.
    def rss_path
      File.join(@site.output_dir, *path_parts('feed.xml'))
    end

    def json_path
      File.join(@site.output_dir, *path_parts('feed.json'))
    end

    def feed_url(filename)
      "#{base_url}#{absolute_path_segment}/#{filename}"
    end

    # The "effective" collection name for URL purposes — slug if set,
    # canonical name otherwise.
    def effective_name
      slug = @site.collection_config(@collection_name)['slug'].to_s
      slug.empty? ? @collection_name : slug
    end

    def path_parts(filename)
      effective_name == 'posts' ? [filename] : [effective_name, filename]
    end

    def absolute_path_segment
      effective_name == 'posts' ? '' : "/#{effective_name}"
    end

    def feed_title
      base = @site.config['title'].to_s
      # Use the slug-aliased name so the feed's own <title> matches the
      # `<link rel="alternate" … title="…">` the head advertises (a
      # `posts → stories` site reads "Stories", not "Posts").
      effective_name == 'posts' ? base : "#{base} — #{effective_name.capitalize}"
    end

    def rss
      entries = items.map do |item|
        item_url = xml_escape("#{base_url}#{item.url}")
        <<~ITEM.chomp
            <item>
              <title>#{xml_escape(item.title)}</title>
              <link>#{item_url}</link>
              <guid isPermaLink="true">#{item_url}</guid>
              <pubDate>#{item.date.rfc822}</pubDate>
              <description>#{xml_escape(item.description.to_s)}</description>
            </item>
        ITEM
      end

      <<~RSS
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0" xmlns:atom="http://www.w3.org/2005/Atom">
          <channel>
            <title>#{xml_escape(feed_title)}</title>
            <link>#{xml_escape("#{base_url}#{absolute_path_segment}/")}</link>
            <description>#{xml_escape(@site.config['description'].to_s)}</description>
            <language>#{xml_escape(@site.config['locale'] || 'en')}</language>
            <atom:link href="#{xml_escape(feed_url('feed.xml'))}" rel="self" type="application/rss+xml"/>
        #{entries.join("\n")}
          </channel>
        </rss>
      RSS
    end

    def json_feed
      data = {
        version: 'https://jsonfeed.org/version/1.1',
        title: feed_title,
        description: @site.config['description'],
        home_page_url: "#{base_url}#{absolute_path_segment}/",
        feed_url: feed_url('feed.json'),
        language: @site.config['locale'] || 'en',
        items: items.map do |item|
          {
            id: "#{base_url}#{item.url}",
            url: "#{base_url}#{item.url}",
            title: item.title,
            summary: item.description,
            date_published: item.date.iso8601,
            tags: item.respond_to?(:tags) ? item.tags : []
          }.compact.reject { |_, v| v.respond_to?(:empty?) && v.empty? }
        end
      }
      JSON.pretty_generate(data)
    end

    def xml_escape(text)
      CGI.escapeHTML(text.to_s)
    end
  end
end

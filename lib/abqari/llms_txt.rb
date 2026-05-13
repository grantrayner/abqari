# frozen_string_literal: true

module Abqari
  # llms.txt — opt-in machine-readable summary of the site for LLM
  # crawlers and AI tools. Inverse policy from robots.txt's
  # `block_ai_scraping`: where robots.txt slams the door on AI training,
  # llms.txt opens a curated front door for AI READERS.
  #
  # File location: /llms.txt (no `.well-known/` prefix in the draft
  # spec at llmstxt.org).
  #
  # Format (draft spec, kept deliberately minimal):
  #
  #   # <Site Title>
  #
  #   > <one-line summary>
  #
  #   ## Posts
  #
  #   - [Title](https://...): one-line description
  #
  #   ## Publications
  #
  #   - [Title](https://...): one-line description
  #
  # Off by default — opt in with `llms.enabled: true` in
  # `config/site.yml`. When disabled, no file is written.
  class LlmsTxt
    SECTIONS = %w[posts publications workshops photos].freeze

    def initialize(site)
      @site = site
    end

    def enabled?
      @site.config.dig('llms', 'enabled') == true
    end

    def write
      return unless enabled?
      File.write(File.join(@site.output_dir, 'llms.txt'), build)
    end

    private

    def build
      lines = []
      lines << "# #{title}"
      lines << ''
      lines << "> #{summary}" if summary
      lines << ''
      SECTIONS.each do |coll_name|
        block = section_for(coll_name)
        lines.concat(block) if block.any?
      end
      lines.join("\n") + "\n"
    end

    def title
      @site.config['title'].to_s.empty? ? 'Untitled site' : @site.config['title']
    end

    def summary
      explicit = @site.config.dig('llms', 'description')
      return explicit.to_s.strip unless explicit.to_s.strip.empty?
      desc = @site.config['description'].to_s.strip
      desc.empty? ? nil : desc
    end

    def section_for(coll_name)
      coll_cfg = @site.collection_config(coll_name) || {}
      return [] unless coll_cfg.fetch('enabled', true)

      items = (@site.collection(coll_name) rescue []) || []
      return [] if items.empty?

      heading = coll_name.capitalize
      lines = []
      lines << "## #{heading}"
      lines << ''
      items.each do |item|
        title = item.respond_to?(:title) ? item.title.to_s.strip : nil
        next if title.nil? || title.empty?
        url    = absolute_url(item.url)
        desc   = item_description(item)
        line   = "- [#{title}](#{url})"
        line += ": #{desc}" unless desc.empty?
        lines << line
      end
      lines << ''
      lines
    end

    def item_description(item)
      raw = (item.respond_to?(:description) && item.description) ||
            (item.respond_to?(:frontmatter) && item.frontmatter['description'])
      raw.to_s.strip.gsub(/\s+/, ' ')
    end

    def absolute_url(path)
      base = @site.config['url'].to_s.sub(%r{/\z}, '')
      "#{base}#{path}"
    end
  end
end

# frozen_string_literal: true

module Abqari
  class Robots
    # AI training crawlers that explicitly identify themselves and
    # respect robots.txt. Blocked when `block_ai_scraping: true` is set
    # in config (the default). Bots that ignore robots.txt won't be
    # stopped by anything in this file — but the major AI training
    # crawlers (OpenAI, Anthropic, Google's AI carve-out, Meta, Apple,
    # Perplexity, Common Crawl, ByteDance, Cohere) all honour it.
    #
    # Notes:
    #   - `Google-Extended` is Google's separate user-agent for AI
    #     training. Blocking it does NOT affect regular Googlebot
    #     search indexing.
    #   - `Applebot-Extended` is the same idea for Apple.
    #   - `CCBot` is Common Crawl, used by many third-party trainers.
    #   - User-facing fetchers (ChatGPT-User, Perplexity's on-demand
    #     fetcher) ARE included — block-all-AI is the safer default;
    #     remove specific bots from this list if you want their search
    #     citations.
    AI_BOTS = %w[
      GPTBot
      ChatGPT-User
      OAI-SearchBot
      ClaudeBot
      Claude-Web
      anthropic-ai
      Google-Extended
      Applebot-Extended
      Meta-ExternalAgent
      FacebookBot
      PerplexityBot
      Perplexity-User
      YouBot
      cohere-ai
      Bytespider
      MistralAI-User
      CCBot
      Diffbot
      omgili
      omgilibot
    ].freeze

    def initialize(site)
      @site = site
    end

    def write
      File.write(File.join(@site.output_dir, 'robots.txt'), build)
    end

    private

    def build
      indexable = @site.config['indexable']
      base = @site.config['url']&.sub(%r{/\z}, '')

      if indexable == false
        <<~ROBOTS
          # Indexing disabled in #{@site.env}.
          User-agent: *
          Disallow: /
        ROBOTS
      else
        sections = []
        sections << ai_block if block_ai_scraping?
        sections << build_default(base)
        sections.join("\n")
      end
    end

    def build_default(base)
      lines = ['User-agent: *', 'Allow: /']
      Array(@site.config['robots_disallow']).each { |path| lines << "Disallow: #{path}" }
      lines << ''
      lines << "Sitemap: #{base}/sitemap.xml" if base
      "#{lines.join("\n")}\n"
    end

    def ai_block
      lines = ['# Block AI training crawlers (config: block_ai_scraping)']
      AI_BOTS.each { |bot| lines << "User-agent: #{bot}" }
      lines << 'Disallow: /'
      lines << ''
      "#{lines.join("\n")}\n"
    end

    def block_ai_scraping?
      @site.config['block_ai_scraping']
    end
  end
end

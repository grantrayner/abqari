# frozen_string_literal: true

module Abqari
  # Conservative HTML minifier. Strips comments, collapses whitespace between
  # tags, and trims leading/trailing whitespace — but preserves the contents of
  # <pre>, <textarea>, <script>, and <style> blocks where whitespace matters.
  module Minifier
    PRESERVE_TAGS = %w[pre textarea script style].freeze
    PRESERVE_REGEX = /<(#{PRESERVE_TAGS.join('|')})\b[^>]*>.*?<\/\1>/im.freeze
    PLACEHOLDER = "\x00ABQARI_PRESERVED_%d\x00"
    COMMENT_REGEX = /<!--(?!\[if).*?-->/m.freeze

    def self.minify(html)
      preserved = []

      protected_html = html.gsub(PRESERVE_REGEX) do |match|
        preserved << match
        format(PLACEHOLDER, preserved.length - 1)
      end

      minified = protected_html
                 .gsub(COMMENT_REGEX, '')
                 .gsub(/>\s+</, '><')
                 .gsub(/\s{2,}/, ' ')
                 .strip

      minified.gsub(/\x00ABQARI_PRESERVED_(\d+)\x00/) do
        preserved[::Regexp.last_match(1).to_i]
      end
    end
  end
end

# frozen_string_literal: true

require 'uri'
require 'fileutils'

module Abqari
  class FontPipeline
    GOOGLE_CSS_API = 'https://fonts.googleapis.com/css2'
    USER_AGENT = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 ' \
                 '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'

    # Timeouts and per-response cap. CSS responses are <10 KB and woff2
    # files <500 KB typically; 8 MB is far above worst-case and exists so
    # a misbehaving upstream can't hang the build or fill memory.
    OPEN_TIMEOUT       = 5
    READ_TIMEOUT       = 10
    MAX_RESPONSE_BYTES = 8 * 1024 * 1024

    def initialize(site)
      @site = site
      # Font cache is site-specific — populated from the site's own
      # `fonts:` config.
      @cache_dir = File.join(@site.site_root, 'vendor', 'fonts')
    end

    def fetch
      fonts = Array(@site.config['fonts'])
      if fonts.empty?
        Log.info 'No fonts configured. Add a `fonts:` array to config/site.yml.'
        return
      end

      FileUtils.mkdir_p(@cache_dir)
      generated = fonts.map { |font| download_font(font) }
      File.write(File.join(@cache_dir, 'fonts.css'), generated.join("\n\n"))
      Log.info "Fetched #{fonts.size} font family/families → vendor/fonts/"
    end

    private

    def download_font(font)
      family = font['family'] || raise(ArgumentError, "Font config missing 'family'")
      weights = Array(font['weights'] || [400])
      style = font['style'] || 'normal'

      css = fetch_css(family, weights, style)
      rewrite_and_download(css)
    end

    def fetch_css(family, weights, style)
      family_param = "#{family.gsub(' ', '+')}:#{weight_spec(weights, style)}"
      uri = URI("#{GOOGLE_CSS_API}?family=#{family_param}&display=swap")

      response = http_get(uri)
      response.body
    end

    # Build the family axis spec for the Google Fonts CSS API.
    #
    # Normal: `wght@300;400;700`            — one weight per entry
    # Italic: `ital,wght@1,300;1,400;1,700` — each (ital, weight) tuple on
    # its own, separated by `;`. Google rejects `ital,wght@1,300;400;700`
    # with a 400 Bad Request because every entry past the first must
    # carry its own ital flag.
    def weight_spec(weights, style)
      sorted = weights.sort
      if style == 'italic'
        "ital,wght@#{sorted.map { |w| "1,#{w}" }.join(';')}"
      else
        "wght@#{sorted.join(';')}"
      end
    end

    def rewrite_and_download(css)
      css.gsub(%r{url\((https://fonts\.gstatic\.com/[^)]+\.woff2)\)}) do
        url = ::Regexp.last_match(1)
        filename = File.basename(URI(url).path)
        dest = File.join(@cache_dir, filename)

        download(url, dest) unless File.exist?(dest)

        "url(/assets/fonts/#{filename})"
      end
    end

    def download(url, dest)
      response = http_get(URI(url))
      File.binwrite(dest, response.body)
    end

    def http_get(uri)
      response = HttpSafe.get(uri,
                              headers: { 'User-Agent' => USER_AGENT },
                              max_bytes: MAX_RESPONSE_BYTES,
                              open_timeout: OPEN_TIMEOUT,
                              read_timeout: READ_TIMEOUT)
      unless response.success?
        raise "Fetch failed for #{uri}: #{response.code} #{response.message}"
      end

      response
    end
  end
end

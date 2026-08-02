# frozen_string_literal: true

require_relative 'test_helper'

# Auto OG cards — the head partial and OgImageGenerator must agree on
# which pages get one. The generator only writes cards for real content
# Pages with directory URLs; generated pages (taxonomy indexes,
# pagination shards, related indexes) and flat-URL pages (/404.html)
# never get a file. When the head's guard drifts from the generator's,
# those pages emit og:image URLs that 404 — social shares show a broken
# image and validators flag every affected page.
class OgImageEligibilityTest < Minitest::Test
  def test_every_emitted_auto_og_image_exists_on_disk
    site = TestHelpers.built_site
    base_url = site.config['url'].to_s.sub(%r{/\z}, '')

    html_files = Dir.glob(File.join(TestHelpers::CANONICAL_OUTPUT_DIR, '**', '*.html'))
    refute_empty html_files, 'fixture build produced no HTML'

    missing = []
    html_files.each do |path|
      html = File.read(path, encoding: 'UTF-8')
      html.scan(/property="og:image" content="([^"]*og\.svg)"/) do |(url)|
        rel  = url.sub(base_url, '')
        file = File.join(TestHelpers::CANONICAL_OUTPUT_DIR, rel)
        next if File.exist?(file)

        missing << "#{path.sub(TestHelpers::CANONICAL_OUTPUT_DIR, '')} → #{url}"
      end
    end

    assert_empty missing, <<~MSG
      og:image URLs pointing at files the build never wrote:

        #{missing.join("\n  ")}
    MSG
  end

  def test_auto_card_predicate_rejects_generated_and_flat_pages
    site = TestHelpers.built_site

    flat = site.pages.find { |p| p.url == '/404.html' }
    refute_nil flat, 'fixture should have a /404.html page'
    refute Abqari::OgImageGenerator.auto_card?(flat),
           'flat-URL pages cannot host a sibling og.svg'

    generated = (site.all_pages - site.pages).first
    refute_nil generated, 'fixture should have generated pages (tags etc.)'
    refute Abqari::OgImageGenerator.auto_card?(generated),
           'generated pages never get auto cards'

    eligible = site.pages.find do |p|
      p.url.to_s.end_with?('/') && !p.title.to_s.empty? &&
        p.frontmatter['image'].to_s.empty? && p.frontmatter['share_image'].to_s.empty? &&
        p.frontmatter['og_image'] != false
    end
    refute_nil eligible, 'fixture should have at least one card-eligible page'
    assert Abqari::OgImageGenerator.auto_card?(eligible)
  end
end

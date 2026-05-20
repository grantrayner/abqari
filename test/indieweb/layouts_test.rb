# frozen_string_literal: true

require_relative '../test_helper'

# Microformats2 — verify the class hooks land in the right places in
# the rendered output. These tests run against the canonical fixture
# site so they catch regressions introduced by future layout edits
# that strip the classes.
class IndiewebLayoutsTest < Minitest::Test
  def setup
    @site = TestHelpers.built_site
  end

  def post_url
    post = @site.posts.find { |p| p.respond_to?(:url) && p.url.start_with?('/posts/') }
    refute_nil post, 'fixture must contain at least one post'
    post.url
  end

  def test_post_layout_emits_h_entry_root
    html = TestHelpers.read_output("#{post_url}index.html")
    assert_match(/<article[^>]*class="[^"]*\bh-entry\b/, html, 'h-entry on article')
    assert_match(/<h1[^>]*class="[^"]*\bp-name\b/,       html, 'p-name on h1')
    assert_match(/<time[^>]*class="[^"]*\bdt-published\b/, html, 'dt-published on date')
    assert_match(/<div class="e-content">/,              html, 'e-content wraps body')
  end

  def test_post_layout_includes_u_url_link
    html = TestHelpers.read_output("#{post_url}index.html")
    # Hidden u-url anchor pointing at the post's canonical URL.
    assert_match(/<a class="u-url" href="[^"]+"/, html)
  end

  def test_post_tags_carry_p_category
    # Find a fixture post that actually has tags rendered in the footer.
    post = @site.posts.find { |p| p.respond_to?(:tags) && p.tags.any? }
    skip 'no fixture post with tags' unless post
    html = TestHelpers.read_output("#{post.url}index.html")
    assert_match(/<a[^>]*class="[^"]*\bp-category\b/, html, 'tag links carry p-category')
  end

  def test_post_list_uses_h_feed_and_h_entry
    html = TestHelpers.read_output('posts/index.html')
    assert_match(/<ul[^>]*class="[^"]*\bh-feed\b/,  html, 'h-feed on the list container')
    assert_match(/<li[^>]*class="[^"]*\bh-entry\b/, html, 'h-entry on each card')
    assert_match(/<a[^>]*class="[^"]*\bu-url\b/,    html, 'u-url on card link')
  end

  def test_about_page_emits_h_card_root
    html = TestHelpers.read_output('about/index.html')
    assert_match(/<article class="h-card"/, html, 'h-card root on about page')
  end

  def test_about_page_h_card_identity_block_when_author_configured
    html = TestHelpers.read_output('about/index.html')
    # Fixture site.yml has `author:` set, so the identity block should
    # render with at least p-name.
    assert_match(/<span class="p-name">/, html)
  end

  def test_head_includes_no_indieweb_tags_when_disabled
    # Fixture site doesn't enable indieweb, so the rel="webmention"
    # tag must NOT appear in any rendered head.
    html = TestHelpers.read_output('about/index.html')
    refute_match(/rel="webmention"/, html, 'webmention tag absent when indieweb disabled')
    refute_match(/fed\.brid\.gy/,    html, 'Bridgy Fed link absent when disabled')
  end
end

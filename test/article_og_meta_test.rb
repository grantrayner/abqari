# frozen_string_literal: true

require_relative 'test_helper'

# Posts emit `og:type: article`, so social platforms expect the
# article:* companion meta — published/modified times and tags. Dates
# in JSON-LD alone aren't enough: Facebook/LinkedIn read the OG-level
# properties, not schema.org.
class ArticleOgMetaTest < Minitest::Test
  def test_posts_emit_article_meta
    site = TestHelpers.built_site
    post = site.posts.find { |p| p.date && p.respond_to?(:tags) && Array(p.tags).any? }
    refute_nil post, 'fixture needs a dated, tagged post'

    html = TestHelpers.read_output(File.join(post.url, 'index.html'))

    assert_includes html, %(property="article:published_time" content="#{post.date.iso8601}")
    assert_match(/property="article:modified_time" content="[^"]+"/, html)
    Array(post.tags).each do |tag|
      assert_includes html, %(property="article:tag" content="#{tag}")
    end
  end

  def test_non_post_pages_do_not_emit_article_meta
    html = TestHelpers.read_output('about/index.html')
    refute_includes html, 'article:published_time'
    refute_includes html, 'article:tag'
  end
end

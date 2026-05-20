# frozen_string_literal: true

require_relative '../test_helper'

# Formatter — builds the per-network snippet from a post + URL. Tests
# cover the truncation logic, custom-override path, and the empty-
# description fallback.
class SyndicationFormatterTest < Minitest::Test
  Formatter = Abqari::Syndication::Formatter

  StubPost = Struct.new(:title, :frontmatter, keyword_init: true) do
    def respond_to?(m, *)
      %i[title frontmatter].include?(m) || super
    end
  end

  def post(title: 'My Post', description: nil, custom: nil)
    fm = {}
    fm['description']      = description if description
    fm['syndication_text'] = custom      if custom
    StubPost.new(title: title, frontmatter: fm)
  end

  def test_basic_snippet_includes_title_description_and_url
    text = Formatter.snippet_for(post(description: 'A short note.'),
                                  'https://example.com/posts/foo/',
                                  limit: 500)
    assert_includes text, 'My Post'
    assert_includes text, 'A short note'
    assert_includes text, 'https://example.com/posts/foo/'
  end

  def test_truncates_description_to_fit_limit
    long_desc = 'x' * 600
    text = Formatter.snippet_for(post(description: long_desc),
                                  'https://example.com/foo/',
                                  limit: 100)
    assert text.length <= 100, "snippet must fit in #{100} chars (got #{text.length})"
    assert text.end_with?('…') || text.end_with?(' https://example.com/foo/'),
           'truncated text should end with ellipsis when description was clipped'
    assert_includes text, 'https://example.com/foo/'
  end

  def test_falls_back_to_title_plus_url_when_no_description
    text = Formatter.snippet_for(post(description: nil),
                                  'https://example.com/p/',
                                  limit: 500)
    assert_equal 'My Post https://example.com/p/', text
  end

  def test_custom_syndication_text_overrides_default
    text = Formatter.snippet_for(post(custom: 'My own snippet'),
                                  'https://example.com/p/',
                                  limit: 500)
    # Custom text wins; URL is the operator's responsibility to include.
    assert_equal 'My own snippet', text
  end

  def test_custom_text_is_clamped_to_limit
    text = Formatter.snippet_for(post(custom: 'a' * 1000),
                                  'https://example.com/p/',
                                  limit: 300)
    assert text.length <= 300
    assert text.end_with?('…')
  end

  def test_returns_title_alone_when_title_already_eats_the_limit
    long_title = 'x' * 280
    text = Formatter.snippet_for(post(title: long_title, description: 'will be skipped'),
                                  'https://example.com/p/',
                                  limit: 300)
    # No room for description; title + URL only.
    assert text.length <= 300
    refute_includes text, 'will be skipped'
  end
end

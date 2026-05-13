# frozen_string_literal: true

require_relative 'test_helper'

class HelpersTest < Minitest::Test
  include Abqari::Helpers

  # truncate

  def test_truncate_returns_short_text_unchanged
    assert_equal 'hello', truncate('hello', length: 10)
  end

  def test_truncate_long_text_with_default_omission
    assert_equal 'hello…', truncate('hello world', length: 6)
  end

  def test_truncate_custom_omission
    assert_equal 'hello...', truncate('hello world', length: 8, omission: '...')
  end

  def test_truncate_handles_nil
    assert_equal '', truncate(nil)
  end

  # pluralize

  def test_pluralize_one_uses_singular
    assert_equal '1 post', pluralize(1, 'post')
  end

  def test_pluralize_zero_uses_plural
    assert_equal '0 posts', pluralize(0, 'post')
  end

  def test_pluralize_many_appends_s
    assert_equal '5 posts', pluralize(5, 'post')
  end

  def test_pluralize_custom_plural
    assert_equal '2 children', pluralize(2, 'child', plural: 'children')
  end

  # slugify

  def test_slugify_lowercases_and_dashes
    assert_equal 'hello-world', slugify('Hello World')
  end

  def test_slugify_strips_special_chars
    assert_equal 'foo-bar', slugify('Foo & Bar!')
  end

  def test_slugify_collapses_repeats
    assert_equal 'foo-bar', slugify('  foo--bar  ')
  end

  def test_slugify_preserves_existing_slug
    assert_equal 'already-a-slug', slugify('already-a-slug')
  end

  # local_time

  def test_local_time_default_format
    time = Time.new(2026, 4, 15, 12, 30)
    assert_equal '15 April 2026', local_time(time)
  end

  def test_local_time_custom_format
    time = Time.new(2026, 4, 15)
    assert_equal '2026-04-15', local_time(time, format: '%Y-%m-%d')
  end

  def test_local_time_accepts_date
    assert_equal '15 April 2026', local_time(Date.new(2026, 4, 15))
  end

  # reading_time

  def test_reading_time_one_minute_for_under_200_words
    assert_equal '1 min read', reading_time('word ' * 50)
  end

  def test_reading_time_scales_with_word_count
    assert_equal '3 min read', reading_time('word ' * 500)
  end

  def test_reading_time_strips_html
    text = '<p>' + ('word ' * 100) + '</p>'
    assert_equal '1 min read', reading_time(text)
  end

  # excerpt

  def test_excerpt_short_text_passes_through
    assert_equal 'hello world', excerpt('hello world', words: 50)
  end

  def test_excerpt_long_text_truncates
    text = (1..100).map { |i| "word#{i}" }.join(' ')
    result = excerpt(text, words: 5)
    assert result.start_with?('word1 word2 word3 word4 word5')
    assert result.end_with?('…')
  end

  # years_since

  def test_years_since_after_anniversary
    # 2002-01-01 → 2026-06-15 = 24 years
    assert_equal 24, years_since(2002, today: Date.new(2026, 6, 15))
  end

  def test_years_since_before_anniversary_in_year
    # 2002-06-15 anniversary not yet reached on 2026-03-01 → 23 years
    assert_equal 23, years_since(Date.new(2002, 6, 15), today: Date.new(2026, 3, 1))
  end

  def test_years_since_clamps_to_zero_for_future
    assert_equal 0, years_since(3000, today: Date.new(2026, 1, 1))
  end

  # link_to

  def test_link_to_basic
    assert_equal '<a href="/">Home</a>', link_to('Home', '/')
  end

  def test_link_to_with_attrs
    html = link_to('Home', '/', class: 'nav-link', rel: 'noopener')
    assert_includes html, 'class="nav-link"'
    assert_includes html, 'rel="noopener"'
    assert_includes html, 'href="/"'
  end

  def test_link_to_escapes_text
    html = link_to('<script>x</script>', '/')
    refute_includes html, '<script>'
    assert_includes html, '&lt;script&gt;'
  end

  def test_link_to_blocks_javascript_url
    html = link_to('Click', 'javascript:alert(1)')
    assert_includes html, 'href="#"'
    refute_includes html, 'javascript:'
  end

  # h

  def test_h_escapes_html
    assert_equal '&lt;script&gt;alert(1)&lt;/script&gt;', h('<script>alert(1)</script>')
  end

  def test_h_escapes_attribute_breakers
    assert_equal '&quot; onerror=&quot;x', h('" onerror="x')
  end

  def test_h_handles_nil
    assert_equal '', h(nil)
  end

  # sanitized_url

  def test_sanitized_url_allows_https
    assert_equal 'https://example.com/path', sanitized_url('https://example.com/path')
  end

  def test_sanitized_url_allows_http
    assert_equal 'http://example.com', sanitized_url('http://example.com')
  end

  def test_sanitized_url_allows_relative_path
    assert_equal '/about', sanitized_url('/about')
  end

  def test_sanitized_url_allows_anchor
    assert_equal '#section', sanitized_url('#section')
  end

  def test_sanitized_url_allows_mailto
    assert_equal 'mailto:hi@example.com', sanitized_url('mailto:hi@example.com')
  end

  def test_sanitized_url_blocks_javascript_scheme
    assert_nil sanitized_url('javascript:alert(1)')
  end

  def test_sanitized_url_blocks_data_scheme
    assert_nil sanitized_url('data:text/html,<script>alert(1)</script>')
  end

  def test_sanitized_url_blocks_vbscript
    assert_nil sanitized_url('vbscript:msgbox(1)')
  end

  def test_sanitized_url_handles_nil_and_empty
    assert_nil sanitized_url(nil)
    assert_nil sanitized_url('')
    assert_nil sanitized_url('   ')
  end

  def test_sanitized_url_escapes_quotes_in_url
    # Even when scheme is allowed, the result must be safe to drop into href=""
    result = sanitized_url('https://example.com/?q="><script>')
    refute_includes result, '"'
    refute_includes result, '<script>'
  end
end

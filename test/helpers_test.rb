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

  def test_truncate_clamps_when_omission_longer_than_length
    # `omission` is 3 chars, `length` is 2. The earlier implementation
    # computed `text[0, -1]` and returned a tail slice of the text — a
    # surprise leak. The clamped slice width should be 0, so the result
    # is just the omission.
    assert_equal '...', truncate('hello world', length: 2, omission: '...')
  end

  def test_truncate_clamps_when_omission_equals_length
    assert_equal '...', truncate('hello world', length: 3, omission: '...')
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

  # slugify — diacritic folding. These characters must FOLD to their
  # base letter, not vanish. slugify builds public taxonomy URLs
  # (`/tags/:slug/`), so dropping them mangles the URL: "Café" used to
  # slug to "caf" and "Mabrūk" to "mabr-k".

  def test_slugify_folds_accents_to_base_letters
    assert_equal 'cafe',   slugify('Café')
    assert_equal 'naive',  slugify('naïve')
    assert_equal 'zurich', slugify('Zürich')
  end

  def test_slugify_folds_transliteration_marks
    # Macrons and dots-below — the transliterated Arabic that prompted
    # this (a Syrian-Arabic site is full of it).
    assert_equal 'mabruk',      slugify('Mabrūk')
    assert_equal 'sahha-enjoy', slugify('Ṣaḥḥa — enjoy')
  end

  def test_slugify_folds_letters_unicode_does_not_decompose
    # Stroked/ligature letters have no combining mark to strip, so they
    # need the explicit table or they'd disappear entirely.
    assert_equal 'aland-o',      slugify('Åland Ø')
    assert_equal 'fussball',     slugify('Fußball')
    assert_equal 'aether-oeuvre', slugify('Æther œuvre')
  end

  def test_slugify_leaves_non_latin_scripts_empty
    # No Latin base letter to fold to. Page::Path#render_permalink
    # turns the empty result into an explicit, actionable error.
    assert_equal '', slugify('日本語')
    assert_equal '', slugify('مرحبا')
  end

  def test_slugify_handles_binary_encoded_input
    # Path-derived strings arrive tagged ASCII-8BIT; unicode_normalize
    # rejects binary outright, which crashed the whole build.
    binary = "Caf\u00e9".dup.force_encoding(Encoding::ASCII_8BIT)
    assert_equal 'cafe', slugify(binary)
  end

  def test_slugify_survives_invalid_encoding
    # A bad byte sequence used to raise from `downcase` and fail the
    # entire build rather than degrading one slug.
    assert_equal 'caf-e', slugify("caf\xC3(e")
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

  # word_count

  def test_word_count_ignores_markup
    # Callers pass rendered HTML (page.content), so attributes must not
    # count as words — JSON-LD wordCount is consumed by search engines.
    assert_equal 2, word_count('<p class="lede">hello world</p>')
  end

  def test_word_count_does_not_count_heading_anchor_attributes
    # Commonmarker 2.x repeats the heading text in aria-label and
    # data-heading-content; only the visible text should count.
    html = %(<h2 id="a-title">A title<a href="#a-title" ) +
           %(aria-label="Link to heading 'A title'" ) +
           %(data-heading-content="A title" class="anchor"></a></h2>)
    assert_equal 2, word_count(html)
  end

  def test_word_count_handles_plain_text_and_nil
    assert_equal 3, word_count('one two three')
    assert_equal 0, word_count(nil)
  end

  def test_reading_time_scales_with_word_count
    assert_equal '3 min read', reading_time('word ' * 500)
  end

  def test_reading_time_strips_html
    text = '<p>' + ('word ' * 100) + '</p>'
    assert_equal '1 min read', reading_time(text)
  end

  def test_reading_time_wpm_zero_does_not_raise
    # `wpm: 0` used to divide to Infinity → FloatDomainError. Now wpm is
    # clamped to ≥1, so it returns a sane string instead of crashing.
    assert_match(/\A\d+ min read\z/, reading_time('word ' * 100, wpm: 0))
  end

  def test_reading_time_empty_text_is_one_minute
    assert_equal '1 min read', reading_time('')
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

  # script_safe_json

  def test_script_safe_json_escapes_closing_script_tag
    out = script_safe_json('name' => 'Evil </script><script>alert(1)</script>')
    refute_includes out, '</script>'
    refute_includes out, '<script>'
    # Round-trip: the escaped JSON is still valid and parses back to the
    # original string (we escape the host-HTML problem, not the data).
    assert_equal 'Evil </script><script>alert(1)</script>', JSON.parse(out)['name']
  end

  def test_script_safe_json_escapes_html_comment_delimiters
    # `<!--` and `-->` inside a <script> block can break out under HTML5
    # script-data parsing rules (--> in particular ends a comment-state
    # script). Escaping `<` and `>` handles both.
    out = script_safe_json('html' => '<!--bad-->')
    refute_includes out, '<!--'
    refute_includes out, '-->'
    assert_equal '<!--bad-->', JSON.parse(out)['html']
  end

  def test_script_safe_json_escapes_ampersand
    # An unescaped `&` doesn't break out of <script>, but it does break
    # out of HTML attribute context if someone later moves the partial.
    # Cheap to escape and keeps the audit story consistent.
    out = script_safe_json('owner' => 'Tom & Jerry')
    refute_includes out, '&'
    assert_equal 'Tom & Jerry', JSON.parse(out)['owner']
  end

  def test_script_safe_json_escapes_line_separators
    # U+2028 and U+2029 terminate JS string literals (legal JSON, illegal
    # inside a literal in pre-ES2019 JS). Replace with their `\u202X`
    # forms so the JSON stays parseable everywhere.
    out = script_safe_json('s' => "a b c")
    refute_includes out, " "
    refute_includes out, " "
  end

  def test_script_safe_json_passes_through_safe_values
    assert_equal '{"a":1,"b":"hello"}', script_safe_json('a' => 1, 'b' => 'hello')
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

  def test_sanitized_url_blocks_protocol_relative
    # //evil.com/x is parsed as <current-scheme>://evil.com/x by browsers — a
    # cross-origin redirect disguised as a same-origin path. The legacy short-
    # circuit on `start_with?('/')` let these through; the new guard rejects
    # any string starting with `//`.
    assert_nil sanitized_url('//evil.com/foo')
    assert_nil sanitized_url('//evil.com')
    assert_nil sanitized_url(' //evil.com/foo')
  end

  def test_sanitized_url_allows_root
    assert_equal '/', sanitized_url('/')
  end

  def test_sanitized_url_handles_nil_and_empty
    assert_nil sanitized_url(nil)
    assert_nil sanitized_url('')
    assert_nil sanitized_url('   ')
  end

  def test_sanitized_url_returns_raw_url_escaping_is_callers_job
    # sanitized_url validates the scheme but returns the RAW URL — it no
    # longer HTML-escapes. Escaping is the caller's job: `<%= %>` does it
    # via Erubi auto-escaping, and helpers that build raw HTML (link_to,
    # buy_button) call `h()` themselves. Returning pre-escaped output
    # here double-escapes any URL with a query string in a `<%=` context.
    result = sanitized_url('https://example.com/?a=1&b=2')
    assert_equal 'https://example.com/?a=1&b=2', result,
                 'no HTML-escaping — a single & must not become &amp;'
  end

  def test_link_to_escapes_the_url_it_embeds
    # link_to returns a full <a> tag emitted raw (<%==), so it must
    # escape the sanitized_url result itself.
    html = link_to('X', 'https://example.com/?a=1&b=2')
    assert_includes html, 'href="https://example.com/?a=1&amp;b=2"'
  end
end

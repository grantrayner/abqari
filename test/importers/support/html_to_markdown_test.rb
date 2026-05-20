# frozen_string_literal: true

require_relative '../../test_helper'
require 'abqari/importers'

# HtmlToMarkdown — wraps reverse_markdown with our cleaning + tuning.
# These tests exercise the pre-clean selector pass and the GFM output
# shape; the gem's own conversion correctness is covered by its tests
# upstream.
class HtmlToMarkdownTest < Minitest::Test
  Conv = Abqari::Importers::Support::HtmlToMarkdown

  def test_basic_conversion_to_gfm
    md = Conv.convert('<p>Hello <strong>world</strong>.</p>')
    assert_match(/Hello \*\*world\*\*/, md)
  end

  def test_headings_round_trip
    md = Conv.convert('<h2>Section</h2><p>Body.</p>')
    assert_match(/^## Section/, md)
    assert_match(/^Body\./, md)
  end

  def test_pre_clean_strips_div_with_class
    html = '<p>Keep</p><div class="subscription-widget">Drop me</div><p>Also keep</p>'
    md = Conv.convert(html, strip_selectors: ['div.subscription-widget'])
    assert_match(/Keep/,      md)
    assert_match(/Also keep/, md)
    refute_match(/Drop me/,   md, 'subscription widget should be stripped')
  end

  def test_pre_clean_handles_multiple_selectors
    html = <<~HTML
      <p>Body.</p>
      <div class="share-dialog">share buttons</div>
      <aside class="poll">vote!</aside>
    HTML
    md = Conv.convert(html, strip_selectors: %w[div.share-dialog aside.poll])
    assert_match(/Body\./,    md)
    refute_match(/share but/, md)
    refute_match(/vote!/,     md)
  end

  def test_pre_clean_leaves_unmatched_classes_alone
    html = '<div class="keep-me">visible content</div>'
    md = Conv.convert(html, strip_selectors: ['div.subscription-widget'])
    assert_match(/visible content/, md)
  end

  def test_collapses_runs_of_blank_lines
    # reverse_markdown can emit several blanks around blocks; we
    # collapse runs longer than two to keep the output tidy.
    md = Conv.convert('<p>a</p>' + ('<br/>' * 6) + '<p>b</p>')
    refute_match(/\n{4,}/, md, 'no more than two consecutive newlines')
  end

  def test_empty_input_returns_empty_string
    assert_equal '', Conv.convert('')
    assert_equal '', Conv.convert(nil)
  end

  def test_parse_selector_handles_tag_only
    assert_equal ['aside', nil], Conv.parse_selector('aside')
  end

  def test_parse_selector_handles_tag_class
    assert_equal ['div', 'foo-bar'], Conv.parse_selector('div.foo-bar')
  end

  def test_parse_selector_rejects_id_selectors
    # We intentionally don't support `#id` — silently ignore so a
    # caller mistake doesn't crash the whole import.
    assert_equal [nil, nil], Conv.parse_selector('#nope')
  end
end

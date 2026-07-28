# frozen_string_literal: true

require_relative 'test_helper'

# docs/theming.md documents the token vocabulary as a public theme API.
# This test pins the doc to the CSS it describes, in both directions,
# so neither can drift silently: a token added to `_common.css` without
# documentation fails, and a documented token that no longer exists in
# the CSS fails.
class ThemeTokensDocTest < Minitest::Test
  ENGINE_ROOT = File.expand_path('..', __dir__)

  # Internal custom properties — the CSS-only fan/tilt layout plumbing.
  # The doc deliberately describes these as "not theme API" rather than
  # documenting them individually.
  INTERNAL_RE = /\A--(i|n|max-)/.freeze

  def common_css
    @common_css ||= File.read(File.join(ENGINE_ROOT, 'app', 'assets', 'css', '_common.css'),
                              encoding: 'UTF-8')
  end

  def doc
    @doc ||= File.read(File.join(ENGINE_ROOT, 'docs', 'theming.md'), encoding: 'UTF-8')
  end

  # Real tokens all have a family prefix plus a name (`--color-bg`,
  # `--space-xs`); the two-segment requirement keeps CLI flags the doc
  # mentions (`--as`, `--force`) out of the comparison.
  TOKEN_RE = /(--[a-z0-9]+-[a-z0-9-]+)/.freeze

  def css_tokens
    declared = common_css.scan(/^\s*#{TOKEN_RE}\s*:/o).flatten
    consumed = common_css.scan(/var\(\s*#{TOKEN_RE}/o).flatten
    (declared + consumed).uniq.reject { |t| t.match?(INTERNAL_RE) }.sort
  end

  def doc_tokens
    doc.scan(TOKEN_RE).flatten.uniq.reject { |t| t.match?(INTERNAL_RE) }.sort
  end

  def test_every_css_token_is_documented
    undocumented = css_tokens.reject { |token| doc.include?(token) }
    assert_empty undocumented,
                 "tokens in _common.css missing from docs/theming.md: #{undocumented.join(', ')}"
  end

  def test_every_documented_token_exists_in_css
    ghost = doc_tokens.reject { |token| common_css.include?(token) }
    assert_empty ghost,
                 "docs/theming.md documents tokens absent from _common.css: #{ghost.join(', ')}"
  end
end

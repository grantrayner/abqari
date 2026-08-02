# frozen_string_literal: true

require_relative 'test_helper'

# The syntax stylesheet ships three pieces: a light Rouge theme at
# `.highlight`, a dark Rouge theme mirrored under the two standard
# dark-mode scopes (media query + explicit toggle — the same pair
# every theme's token file uses), and a trailing override that hands
# the code-block background to `--color-code-bg` so the active theme
# owns it in both modes. Before this existed, dark mode rendered
# light-theme tokens on Rouge's hardcoded near-white background —
# a blinding white rectangle on every dark page.
class SyntaxDarkThemeTest < Minitest::Test
  def stylesheet_for(config = {})
    site = Struct.new(:config).new({ 'syntax_highlighting' => true }.merge(config))
    Abqari::SyntaxHighlighter::Stylesheet.new(site)
  end

  def test_light_theme_scoped_to_highlight
    css = stylesheet_for.css
    assert_match(/^\.highlight/, css)
  end

  def test_dark_tokens_emitted_under_both_dark_scopes
    css = stylesheet_for.css
    assert_includes css, '@media (prefers-color-scheme: dark)'
    assert_includes css, ':root:not([data-theme="light"]) .highlight'
    assert_includes css, '[data-theme="dark"] .highlight'
  end

  def test_dark_scope_carries_dark_github_palette
    css = stylesheet_for.css
    # Github dark body text — present only when the dark mode rendered.
    dark_section = css[css.index('[data-theme="dark"] .highlight')..]
    assert_match(/color: #c9d1d9/, dark_section)
  end

  def test_background_handed_to_code_bg_token_in_both_modes
    css = stylesheet_for.css
    override = css[css.rindex('.highlight, .highlight pre')..]
    assert_includes override, 'background-color: var(--color-code-bg, #f6f8fa)'
    assert_includes override, ':root:not([data-theme="light"]) .highlight'
    assert_includes override, '[data-theme="dark"] .highlight'
  end

  def test_background_override_carries_fallbacks_for_no_common_themes
    # `theme: bootstrap` / `theme: none` bundle without `_common.css`,
    # so `--color-code-bg` is undefined there — a bare var() would
    # compute to transparent. The fallbacks keep Rouge-native panels.
    css = stylesheet_for.css
    override = css[css.rindex('.highlight, .highlight pre')..]
    assert_includes override, 'var(--color-code-bg, #f6f8fa)'
    assert_includes override, 'var(--color-code-bg, #161b22)'
  end

  def test_explicit_dark_theme_name_is_honoured
    css = stylesheet_for('syntax_theme_dark' => 'monokai').css
    dark_section = css[css.index('[data-theme="dark"] .highlight')..]
    # Monokai's signature green keyword colour.
    assert_match(/#a6e22e/i, dark_section)
  end

  def test_dark_can_be_opted_out
    css = stylesheet_for('syntax_theme_dark' => false).css
    # No dark token palette (Github dark's body text colour is the
    # marker); the dark scopes still appear once, in the background
    # override, which ships regardless — the theme owns block bg.
    refute_includes css, 'color: #c9d1d9'
    assert_includes css, 'background-color: var(--color-code-bg'
  end

  def test_modeless_light_theme_reused_for_dark
    css = stylesheet_for('syntax_theme' => 'monokai').css
    dark_section = css[css.index('[data-theme="dark"] .highlight')..]
    assert_match(/#a6e22e/i, dark_section)
  end
end

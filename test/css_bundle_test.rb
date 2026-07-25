# frozen_string_literal: true

require_relative 'test_helper'

# CSS/JS minification + the single-file CSS bundle. The bundle exists
# so a page costs one render-blocking stylesheet request instead of
# four, and so the Rouge syntax styles get a content hash (the old
# standalone syntax.css was served un-fingerprinted under the
# `/assets/* immutable` cache rule — change the Rouge theme and
# returning visitors kept the stale one for a year).
class CssMinifierTest < Minitest::Test
  def test_strips_comments_and_collapses_whitespace
    css = "/* banner */\n.a {\n  color: red;\n}\n\n.b { margin: 0; }\n"
    assert_equal '.a{color: red}.b{margin: 0}', Abqari::Minifier.css(css)
  end

  def test_preserves_quoted_strings_verbatim
    css = %(.a { content: "a  /* not a comment */  b"; })
    assert_includes Abqari::Minifier.css(css), '"a  /* not a comment */  b"'
  end

  def test_preserves_descendant_selector_before_pseudo_class
    # `.nav :hover` (descendant) must not become `.nav:hover` (compound).
    out = Abqari::Minifier.css('.nav :hover { color: red; }')
    assert_includes out, '.nav :hover'
  end

  def test_preserves_calc_operator_spacing
    out = Abqari::Minifier.css('.a { width: calc(100%   -   2rem); }')
    assert_includes out, 'calc(100% - 2rem)'
  end

  def test_tightens_child_combinator_and_commas
    out = Abqari::Minifier.css('.a > .b ,  .c { color: red; }')
    assert_equal '.a>.b,.c{color: red}', out
  end

  # --- Apostrophes in comments ----------------------------------------
  #
  # Regression: comments and strings must be tokenised in one pass. When
  # strings were stashed first, a bare `'` was treated as a delimiter —
  # and CSS comments in this codebase are English prose, full of
  # apostrophes. Two comments each carrying one paired up into a single
  # "string" spanning both, so every rule between them (plus the `*/`
  # that should have closed the first comment) was swallowed and then
  # deleted by the comment pass.
  #
  # Real-world impact: `_common.css` has an odd number of apostrophes, so
  # the concatenated bundle lost the entire `:root` token block of
  # whatever theme followed it — every colour and font custom property in
  # the site. Production builds only, because dev doesn't minify.

  def test_apostrophes_in_comments_do_not_eat_the_rules_between_them
    css = <<~CSS
      /* The theme's tokens. */
      :root {
        --color-text: #1a1a1a;
      }
      /* Safari's tap-flash suppression. */
      .card { border: 1px solid red; }
    CSS
    out = Abqari::Minifier.css(css)
    assert_includes out, ':root{--color-text: #1a1a1a}'
    assert_includes out, '.card{border: 1px solid red}'
  end

  def test_odd_apostrophe_count_across_many_comments_is_safe
    # Three apostrophes across three comments — the pathological case,
    # since no pairing is possible without crossing a comment boundary.
    css = <<~CSS
      /* one's */
      .a { color: red; }
      /* two's */
      .b { color: green; }
      /* three's */
      .c { color: blue; }
    CSS
    out = Abqari::Minifier.css(css)
    assert_equal '.a{color: red}.b{color: green}.c{color: blue}', out
  end

  def test_apostrophe_in_a_comment_does_not_pair_with_a_real_string
    css = <<~CSS
      /* the theme's default */
      .a::after { content: 'x'; }
      .b { color: red; }
    CSS
    out = Abqari::Minifier.css(css)
    assert_includes out, %(content: 'x')
    assert_includes out, '.b{color: red}'
  end

  def test_real_theme_bundle_keeps_its_root_token_block
    # End-to-end against the actual shipped files, in bundle order. This
    # is the assertion that would have caught the original bug: the unit
    # cases above all pass on a single file in isolation, because an
    # unpaired apostrophe needs a second one downstream to do damage.
    common = File.read(File.expand_path('../app/assets/css/_common.css', __dir__), encoding: 'UTF-8')
    theme  = File.read(File.expand_path('../themes/minimal/css/app.css', __dir__), encoding: 'UTF-8')

    out = Abqari::Minifier.css([common, theme].join("\n"))

    # The theme's light-mode tokens live in a bare `:root` block right
    # after its doc comment — exactly where the swallowed span landed.
    assert_match(/:root\{[^}]*--color-text/, out,
                 "theme's :root token block lost its selector during minification")
    assert_includes out, '--font-body'
  end
end

class JsMinifierTest < Minitest::Test
  def test_strips_whole_line_comments
    js = "// setup\nlet a = 1;\n\n/* block\n   comment */\nlet b = 2;\n"
    out = Abqari::Minifier.js(js)
    refute_includes out, 'setup'
    refute_includes out, 'block'
    assert_includes out, 'let a = 1;'
    assert_includes out, 'let b = 2;'
  end

  def test_keeps_trailing_comments_and_urls_in_strings
    js = %(let u = "https://example.com/x"; let a = 1; // keep-me-or-not\n)
    out = Abqari::Minifier.js(js)
    assert_includes out, 'https://example.com/x'
    # Trailing comments are kept on purpose — stripping them safely
    # needs real parsing.
    assert_includes out, 'keep-me-or-not'
  end

  def test_files_with_template_literals_are_untouched
    js = "let s = `\n// this is CONTENT, not a comment\n`;\n"
    assert_equal js, Abqari::Minifier.js(js)
  end
end

class CssBundleTest < Minitest::Test
  def setup
    @site = TestHelpers.built_site
  end

  def bundle_href
    @site.assets.path_for('css/bundle.css')
  end

  def bundle_content
    File.read(File.join(@site.output_dir, bundle_href.sub(%r{\A/}, '')), encoding: 'UTF-8')
  end

  def test_bundle_is_fingerprinted
    assert_match %r{\A/assets/css/bundle\.[0-9a-f]{10}\.css\z}, bundle_href
  end

  def test_bundle_carries_all_stylesheet_layers_in_cascade_order
    content = bundle_content
    syntax_pos = content.index('.highlight')
    common_pos = content.index(':focus-visible')  # a11y primitive from _common.css
    assert syntax_pos, 'bundle should contain the Rouge syntax styles'
    assert common_pos, 'bundle should contain _common.css'
    assert syntax_pos < common_pos, 'syntax styles must precede _common (same order as the old links)'
  end

  def test_bundle_is_minified_in_production
    refute_includes bundle_content, '/*',
                    'production bundle should carry no comments'
  end

  def test_head_links_only_the_bundle
    html = TestHelpers.read_output('index.html')
    assert_includes html, bundle_href
    refute_includes html, '/assets/css/syntax.css'
    refute_match %r{/assets/css/_common\.[0-9a-f]{10}\.css}, html
    refute_match %r{/assets/css/app\.[0-9a-f]{10}\.css}, html
  end

  def test_standalone_syntax_stylesheet_still_written_for_overridden_heads
    assert TestHelpers.output_exists?('assets/css/syntax.css')
  end

  def test_individual_assets_still_fingerprinted_and_shipped
    # Sites that override the head partial may reference these directly.
    assert_match %r{\A/assets/css/_common\.[0-9a-f]{10}\.css\z},
                 @site.assets.path_for('css/_common.css')
  end

  def test_shipped_js_has_no_whole_line_comments_when_backtick_free
    logical = 'js/viz-tag-bubble.js'
    href = @site.assets.path_for(logical)
    shipped = File.read(File.join(@site.output_dir, href.sub(%r{\A/}, '')), encoding: 'UTF-8')
    skip 'source gained template literals' if File.read(
      File.join(@site.engine_root, 'app', 'assets', logical), encoding: 'UTF-8'
    ).include?('`')
    refute_match %r{^\s*//}, shipped
  end
end

# frozen_string_literal: true

require_relative 'test_helper'

# HTML comments vs. preserved blocks in `Minifier.minify`.
#
# Regression cover for a production-only content-loss bug: the minifier
# stashed <pre>/<textarea>/<script>/<style> blocks BEFORE stripping
# comments, so tag-like text written inside a comment —
# `<!-- see the <script> tag -->`, the kind of thing that shows up in a
# documented layout or partial — opened a "preserved" region at the
# comment's own text. That region ran to the next genuine `</script>`
# further down the page and swallowed the comment's `-->`; the orphaned
# `<!--` then paired with a `-->` much later, and the comment pass
# deleted the placeholder plus everything in between. The page shipped
# with an empty <main>, and only in production (dev builds don't
# minify). Same failure class the CSS_TOKEN_REGEX commentary documents
# for stylesheets, which is why both now run a single ordered pass.
class MinifierHtmlCommentsTest < Minitest::Test
  # The original repro, reduced. Three ingredients are needed: a comment
  # naming a preserved tag, a real block of that tag later, and any
  # second comment after it — the orphaned `<!--` needs a `-->` to pair
  # with before the comment pass will delete the span.
  def test_script_tag_named_inside_a_comment_does_not_eat_the_page
    html = <<~HTML
      <body>
        <!-- see the <script> tag below -->
        <main>
          <h1>Headline</h1>
          <p>Body copy that must survive.</p>
        </main>
        <script src="/js/theme-toggle.js" defer></script>
        <!-- footer follows -->
        <footer>©</footer>
      </body>
    HTML

    out = Abqari::Minifier.minify(html)

    assert_includes out, '<h1>Headline</h1>'
    assert_includes out, '<p>Body copy that must survive.</p>'
    assert_includes out, '<script src="/js/theme-toggle.js" defer></script>'
    assert_includes out, '<footer>©</footer>'
    refute_includes out, 'see the'
    refute_includes out, 'footer follows'
    refute_includes out, '<!--'
  end

  def test_every_preserved_tag_name_is_inert_inside_a_comment
    Abqari::Minifier::PRESERVE_TAGS.each do |tag|
      html = "<main><!-- mentions <#{tag}> --><p>kept</p></main>" \
             "<#{tag}>body</#{tag}><!-- trailing -->"
      out = Abqari::Minifier.minify(html)

      assert_includes out, '<p>kept</p>',        "<#{tag}> in a comment ate the page"
      assert_includes out, "<#{tag}>body</#{tag}>", "<#{tag}> in a comment ate the real block"
      refute_includes out, 'mentions'
      refute_includes out, 'trailing'
    end
  end

  def test_comment_markers_inside_a_real_script_are_left_alone
    html = '<main><p>kept</p></main>' \
           '<script>var s = "<!-- not a comment -->";</script>'
    out = Abqari::Minifier.minify(html)

    assert_includes out, 'var s = "<!-- not a comment -->";'
    assert_includes out, '<p>kept</p>'
  end

  def test_ordinary_comments_are_still_stripped
    out = Abqari::Minifier.minify("<p>a</p>\n<!-- a note -->\n<p>b</p>")

    refute_includes out, 'a note'
    assert_includes out, '<p>a</p>'
    assert_includes out, '<p>b</p>'
  end

  def test_conditional_comments_survive_verbatim
    html = '<p>a</p><!--[if lt IE 9]><script src="/js/shim.js"></script><![endif]--><p>b</p>'
    out = Abqari::Minifier.minify(html)

    assert_includes out, '<!--[if lt IE 9]><script src="/js/shim.js"></script><![endif]-->'
  end

  # `String#strip` also eats NUL bytes, so trimming with it truncated
  # the stash placeholder's trailing sentinel whenever the document
  # began or ended with a preserved block — the placeholder then never
  # matched on restore and shipped as literal text.
  def test_document_ending_in_a_preserved_block_is_restored
    out = Abqari::Minifier.minify("<p>a</p>\n<script>var a = 1;</script>")

    assert_includes out, '<script>var a = 1;</script>'
    refute_includes out, 'ABQARI_PRESERVED'
  end

  def test_document_starting_with_a_preserved_block_is_restored
    out = Abqari::Minifier.minify("<style>.a { color: red; }</style>\n<p>a</p>")

    assert_includes out, '<style>.a { color: red; }</style>'
    refute_includes out, 'ABQARI_PRESERVED'
  end

  def test_css_string_at_the_document_edges_is_restored
    out = Abqari::Minifier.css('"lead"')

    assert_equal '"lead"', out
  end

  def test_preserved_blocks_still_keep_their_whitespace
    html = "<div><pre>line1\n    indented</pre></div>"

    assert_includes Abqari::Minifier.minify(html), "line1\n    indented"
  end
end

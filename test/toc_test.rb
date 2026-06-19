# frozen_string_literal: true

require_relative 'test_helper'

# Auto-generated TOC partial — three gating layers:
#
#   1. Frontmatter `toc: true/false` wins over everything.
#   2. Collection config `collections.<name>.toc.enabled` — default true.
#   3. `min_headings` quality floor (default 3) — applies even when
#      `toc: true` is set explicitly.
#
# These tests cover the default behaviour and the frontmatter override
# via fixture content. (Collection-config-disabled is exercised
# implicitly: posts without `toc: false` use the default `enabled: true`
# from config/site.yml.)
class TocTest < Minitest::Test
  def html_for(slug)
    TestHelpers.read_output("guides/#{slug}/index.html")
  end

  # --- Default behaviour ----------------------------------------------

  def test_post_with_enough_headings_renders_toc
    # `themes-an-overview` has 3+ h2/h3 headings → TOC renders.
    html = html_for('themes-an-overview')
    assert_match(/<nav class="toc"/, html)
    assert_match(/<details class="toc__details" open>/, html)
    assert_match(%r{<h2 id="toc-heading" class="toc__heading">Contents</h2>}, html)
  end

  def test_short_post_renders_no_toc
    # `hello-from-the-blog` has fewer than the min_headings floor → no TOC.
    html = html_for('hello-from-the-blog')
    refute_match(/<nav class="toc"/, html)
  end

  # --- Frontmatter override -------------------------------------------

  def test_frontmatter_toc_false_suppresses_toc_even_with_enough_headings
    # `toc-disabled-example` has 3 h2 headings (would qualify) but
    # carries `toc: false` in frontmatter. Override wins.
    html = html_for('toc-disabled-example')
    refute_match(/<nav class="toc"/, html, 'TOC should be suppressed by frontmatter toc: false')
    # Sanity: the post itself still rendered — the headings are present
    # in the body, just no TOC navigation above them.
    assert_match(/First heading/, html)
  end

  # --- Collapse-toggle markup (no JS, native <details>) ---------------

  def test_toc_uses_native_details_summary_for_collapse_toggle
    html = html_for('themes-an-overview')
    # `<details open>` makes the expanded state the default. `<summary>`
    # is the click/keyboard target; the chevron SVG sits on the right.
    assert_match(/<details class="toc__details" open>/, html)
    assert_match(/<summary class="toc__summary">/, html)
    assert_match(/<svg class="toc__chevron"/, html)
  end

  # --- Heading levels --------------------------------------------------

  def test_default_levels_include_h2_and_h3_but_skip_h4
    # `toc-levels-demo` is a fixture post with mixed h2/h3/h4
    # headings. The engine default `levels: [2, 3]` should list h2 +
    # h3 entries and drop h4 entries.
    html = html_for('toc-levels-demo')
    toc = html[%r{<nav class="toc"[\s\S]*?</nav>}]
    refute_nil toc, 'expected the TOC nav to render'

    assert_match(/First section/,                  toc, 'h2 should appear')
    assert_match(/A subsection of the first/,      toc, 'h3 should appear')
    refute_match(/A deeper sub-subsection/,        toc, 'h4 should NOT appear under default levels [2, 3]')

    # Visible CSS hooks for the two rendered levels — h2 items carry
    # `.toc__item--h2`, h3 items `.toc__item--h3` (indented + smaller
    # font in the shared stylesheet).
    assert_match(/class="toc__item toc__item--h2"/, toc)
    assert_match(/class="toc__item toc__item--h3"/, toc)
    refute_match(/class="toc__item toc__item--h4"/, toc, 'h4 modifier class should not appear when h4 is excluded')
  end
end

# frozen_string_literal: true

require_relative 'test_helper'

# ERB raw-interpolation audit. After the Erubi migration, `<%= … %>`
# auto-escapes via `h(...)` and `<%== … %>` is the explicit raw-output
# form. The risk class has inverted:
#
#   Before: an interpolation MISSING `h()` was the danger.
#   After:  an interpolation marked `<%==` is the danger — it skips
#           the auto-escape and emits markup verbatim.
#
# This test walks every `.erb` under `app/views/`, finds every `<%== %>`,
# and either accepts it via a safe-pattern allow-list OR fails with the
# specific offender. Adding a new raw interpolation is therefore a
# visible, reviewer-gated decision: wrap the expression with a helper
# that already returns safe HTML (so the call matches an existing
# allow-pattern), or add a new substring to RAW_ALLOW_LIST with a
# rationale in the PR description.
#
# See docs/security.md §3 for the trust model and the cases where
# `<%==` is the correct choice.
class ErbEscapeAuditTest < Minitest::Test
  VIEWS_DIR = File.expand_path('../app/views', __dir__)

  # Patterns the audit treats as safe-by-construction raw output.
  # Helpers known to return escaped/bounded HTML (so wrapping them in
  # `<%==` is correct — re-escaping would emit literal `<` characters
  # for the inner markup).
  SAFE_PATTERNS = [
    /\bJSON\.generate\b/,                  # JSON-LD inside <script>
    /\bto_json\b/,                         # …same
    /\blink_to\b/,                         # helper returns <a> tag
    /\bpicture_tag\b/,                     # helper returns <picture>
    /\bbundle_picture_tag\b/,
    /\bicon\b/,                            # helper returns <svg>
    /\bheroicon\b/,
    /\brender\s+['"]/,                     # render 'partials/foo'
    /\brender\s*\(/,                       # render('partials/foo')
    /\bfolio_(buy|cart)_button\b/,
    /\byield_content\b/,                   # pre-rendered inner layout
    /\Apage\.content\b/,                   # pre-rendered markdown body
    /\bSCRIPT\b/                           # *::SCRIPT constants (pre-built <script>)
  ].freeze

  # Intentional raw interpolations that don't match the helper
  # allow-list above. Each entry is a unique substring of the
  # expression body. Adding one is deliberate; every entry has been
  # reviewed and confirmed safe at its assignment site.
  RAW_ALLOW_LIST = [
    # publication/bundle/series layouts: `description_content` holds
    # either Folio's pre-rendered `excerpt_html` (already safe HTML) or
    # `h(fm_d)` (frontmatter description, already escaped) — see the
    # assignment site in each layout for the two-branch ternary.
    'description_content',

    # _publication_card.html.erb: heading tag built from `heading_level`.
    'heading_open',
    'heading_close',

    # _nav.html.erb: literal ' aria-current="page"' fragment for the
    # active link. String literal, no interpolation.
    " aria-current=\"page\"",

    # _carousel.html.erb: literal HTML attribute fragments for fetchpriority/loading.
    "fetchpriority=\"high\"",
    "loading=\"lazy\"",

    # workshops_index + _next_workshop: `parts.join(' &middot; ')` where
    # `parts` is a mix of pre-escaped helper output and literal
    # `<time>...</time>` HTML produced via `%(...)`.
    "parts.join("
  ].freeze

  def test_no_unaudited_raw_interpolations
    offenders = []

    Dir.glob(File.join(VIEWS_DIR, '**', '*.erb')).sort.each do |path|
      rel = path.sub(VIEWS_DIR + '/', '')
      File.read(path, encoding: 'UTF-8').scan(/<%==\s*([^%]*(?:%(?!>)[^%]*)*)%>/) do |(expr)|
        body = expr.to_s.strip
        next if SAFE_PATTERNS.any? { |re| body.match?(re) }
        next if RAW_ALLOW_LIST.any? { |allowed| body.include?(allowed) }

        offenders << "#{rel}: <%== #{body} %>"
      end
    end

    assert offenders.empty?, <<~MSG
      Found #{offenders.size} <%== raw interpolation(s) without an
      allow-list match. Each `<%==` skips Erubi's auto-escape and emits
      markup verbatim — a missed audit becomes stored XSS.

      For each offender:
        - replace with `<%=` if the value isn't actually safe HTML, OR
        - wrap in a helper that returns safe HTML (link_to / picture_tag
          / icon / render / etc.) so it matches a SAFE_PATTERNS regex, OR
        - add a substring of the expression body to RAW_ALLOW_LIST in
          test/erb_escape_audit_test.rb with a rationale in the PR.

      See docs/security.md §3 for the trust model.

      Offenders:
      #{offenders.map { |o| "  #{o}" }.join("\n")}
    MSG
  end
end

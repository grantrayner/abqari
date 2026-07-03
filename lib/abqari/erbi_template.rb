# frozen_string_literal: true

require 'erubi'

module Abqari
  # ERB-compatible adapter around Erubi for auto-escaping templates.
  #
  # ERB has a deliberate "you escape your own output" contract — the
  # engine emits `<%= value %>` verbatim and trusts the template author
  # to wrap with `h(...)` for any value that isn't already safe HTML.
  # That worked under Abqari's content-trusted model, but a single
  # missed `h()` in a future partial is enough to ship stored XSS in a
  # meta tag or JSON-LD node — see docs/security.md §3.
  #
  # Erubi flips the default: `<%= %>` always escapes, `<%== %>` is the
  # opt-in raw output for values that are already known-safe HTML
  # (rendered partials, helper output that builds tags, JSON inside
  # `<script>` blocks, pre-rendered markdown content). The friction is
  # the feature: emitting raw markup becomes a deliberate, visible
  # choice instead of an unmarked default.
  #
  # The class exposes only `#result(binding)` so callers (Renderer's
  # template cache, RenderContext layout chaining + render_string) can
  # swap `ERB.new(src, trim_mode: '-')` → `ErbiTemplate.new(src)` and
  # keep using the same `.result(binding)` API.
  #
  # Options used:
  #   escape: true           - <%= escapes via `h(...)`, <%== is raw
  #   escapefunc: 'h'        - call our `Helpers#h` (= `CGI.escapeHTML`)
  #                            rather than Erubi's default. Keeps one
  #                            escape function in the codebase.
  #   trim: true             - equivalent to ERB's `trim_mode: '-'`
  #   bufval: 'String.new(encoding: ::Encoding::UTF_8)'
  #                          - force the accumulator to UTF-8. Erubi's
  #                            default `::String.new` returns ASCII-8BIT,
  #                            which downstream `Commonmarker.to_html`
  #                            rejects when a post opts in via
  #                            `erb: true` and the body contains non-
  #                            ASCII glyphs. (Plain `+""` doesn't help
  #                            because the eval-time encoding still
  #                            defaults to ASCII-8BIT.)
  #   freeze_template_literals: true - frozen-string-literal-friendly
  class ErbiTemplate
    # `filename` names the template on disk (a layout/partial path, or a
    # synthetic label for an inline `erb: true` markdown body). It's
    # threaded into both Erubi's compile and the `eval` below so a
    # runtime error in a template reports the real file + line instead
    # of an anonymous `(eval):NN` frame — with layout chaining and
    # nested partials, that's the difference between "which of a dozen
    # templates failed?" and a direct pointer.
    def initialize(source, filename = '(erb)')
      @filename = filename
      @compiled_src = Erubi::Engine.new(
        source,
        escape: true,
        escapefunc: 'h',
        trim: true,
        bufval: 'String.new(encoding: ::Encoding::UTF_8)',
        freeze_template_literals: true,
        filename: filename
      ).src
    end

    # Evaluate against the supplied binding and return the rendered
    # output. The compiled source declares its own `_buf` and returns it
    # as the last expression, mirroring ERB#result. Passing `@filename`
    # + line 1 makes backtraces point at the template file.
    def result(bindng)
      eval(@compiled_src, bindng, @filename, 1) # rubocop:disable Security/Eval
    end
  end
end

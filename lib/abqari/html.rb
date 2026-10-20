# frozen_string_literal: true

require 'nokolexbor'

module Abqari
  # HTML must be read with the same tag, comment and attribute rules as
  # the browser. Regex stripping can change script hash input or hide an
  # executable tag. Lexbor also keeps this work out of Ruby's regex engine.
  module Html
    module_function

    def document(html)
      Nokolexbor::HTML(html.to_s)
    end

    def fragment(html)
      Nokolexbor::DocumentFragment.parse(html.to_s)
    end

    # Plain text, never trusted HTML. Callers must still escape it when
    # rendering (the normal <%= interpolation does this automatically).
    # Non-visible code and comments must not inflate reading estimates.
    def text(html, separator: '')
      tree = fragment(html)
      tree.css('script, style, template').each(&:remove)
      tree.xpath('.//text()').map(&:content).join(separator)
    end
  end
end

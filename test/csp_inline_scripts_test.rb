# frozen_string_literal: true

require_relative 'test_helper'
require 'digest'
require 'base64'

# Every inline script a built page carries must be allowed by the CSP
# the same build writes to `_headers`. Checked against real output, not
# the constants, because the speculation-rules block shipped for 1.1.x
# with nothing but `'inline-speculation-rules'` behind it — which Chrome
# ignores once script-src has hashes — and every page logged a violation
# while the unit tests for each piece passed.
class CspInlineScriptsTest < Minitest::Test
  # Data blocks aren't executed, so CSP doesn't govern them.
  DATA_TYPES = %w[application/ld+json application/json].freeze

  def setup
    TestHelpers.built_site
  end

  def test_every_inline_script_on_the_home_page_is_allowed
    script_src = TestHelpers.read_output('_headers')[/script-src ([^;\n]+)/, 1]
    refute_nil script_src, '_headers should carry a script-src directive'

    inline_scripts(TestHelpers.read_output('index.html')).each do |attrs, body|
      hash = "'sha256-#{Base64.strict_encode64(Digest::SHA256.digest(body))}'"
      assert_includes script_src.split, hash, "CSP does not allow the inline <script#{attrs}>"
    end
  end

  def test_home_page_carries_the_speculation_rules_block
    assert(inline_scripts(TestHelpers.read_output('index.html')).any? { |attrs, _| attrs.include?('speculationrules') },
           'the fixture should exercise the speculation-rules block')
  end

  private

  def inline_scripts(html)
    html.scan(%r{<script(\s[^>]*)?>(.*?)</script>}m)
        .map { |attrs, body| [attrs.to_s, body] }
        .reject { |attrs, _| attrs.include?(' src=') }
        .reject { |attrs, _| DATA_TYPES.any? { |t| attrs.include?(t) } }
  end
end

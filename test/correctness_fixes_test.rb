# frozen_string_literal: true

require_relative 'test_helper'
require 'ostruct'
require 'tmpdir'

# Tests for review items #16 (singularize_slug exceptions),
# #17 (case-insensitive livereload injection), and #19 (parent layout
# YAML errors surface instead of silently misrouting the chain).

class SingularizeSlugTest < Minitest::Test
  def site
    @site ||= TestHelpers.built_site
  end

  def test_plural_to_singular_basic
    assert_equal 'story',       site.singularize_slug('stories')
    assert_equal 'book',        site.singularize_slug('books')
    assert_equal 'photo',       site.singularize_slug('photos')
    assert_equal 'publication', site.singularize_slug('publications')
  end

  def test_ss_words_stay_as_is
    assert_equal 'boss',  site.singularize_slug('boss')
    assert_equal 'press', site.singularize_slug('press')
  end

  def test_invariant_words_stay_as_is
    # The earlier implementation would have wrongly produced
    # `new` / `serie` / `len` here.
    assert_equal 'news',    site.singularize_slug('news')
    assert_equal 'series',  site.singularize_slug('series')
    assert_equal 'lens',    site.singularize_slug('lens')
    assert_equal 'species', site.singularize_slug('species')
  end
end

class LivereloadInjectionTest < Minitest::Test
  def renderer
    @renderer ||= Abqari::Renderer.new(TestHelpers.built_site)
  end

  # The LIVERELOAD_SCRIPT heredoc ends with `</script>\n`, so the
  # injected output puts a newline between `</script>` and the
  # preserved `</body>` tag. Each assertion matches the script,
  # any trailing whitespace, and then the (case-preserving) body
  # tag.
  def assert_injected_before(closing_tag, html)
    injected = renderer.send(:inject_livereload, html)
    assert_match(%r{<script>.*</script>\s*#{Regexp.escape(closing_tag)}}m, injected)
  end

  def test_injects_before_lowercase_closing_body
    assert_injected_before('</body>', '<html><body>hello</body></html>')
  end

  def test_injects_before_mixed_case_closing_body
    # HTML is case-insensitive; layouts that close with `</Body>`
    # used to silently miss livereload because of a literal-string
    # match. Confirm the regex variant covers them.
    assert_injected_before('</Body>', '<HTML><BODY>hello</Body></HTML>')
  end

  def test_injects_before_uppercase_closing_body
    assert_injected_before('</BODY>', '<HTML><BODY>hello</BODY></HTML>')
  end

  def test_no_op_when_no_closing_body
    html = '<p>fragment</p>'
    assert_equal html, renderer.send(:inject_livereload, html)
  end

  def test_only_injects_once_at_first_match
    # If a layout happens to contain `</body>` literal inside a CDATA
    # block (or an inlined example), only the first occurrence gets
    # the injection. Confirms `sub` semantics, not `gsub`. The
    # `(function() {` opener appears once per LIVERELOAD_SCRIPT
    # injection — counting it is the cleanest proxy for "how many
    # times did we inject?"
    html = '<body>1</body>...</body>'
    out  = renderer.send(:inject_livereload, html)
    assert_equal 1, out.scan('(function() {').size,
                 'livereload script should be injected exactly once'
  end
end

class ParentLayoutErrorTest < Minitest::Test
  def setup
    @renderer = Abqari::Renderer.new(TestHelpers.built_site)
  end

  def test_invalid_yaml_frontmatter_raises_with_path_context
    Dir.mktmpdir('abqari-layout-test') do |dir|
      path = File.join(dir, 'broken_layout.html.erb')
      File.write(path, <<~ERB)
        ---
        layout: [this, is, broken: { yaml
        ---
        <p>body</p>
      ERB

      err = assert_raises(RuntimeError) { @renderer.send(:parent_layout_of, path) }
      assert_includes err.message, path,
                      'error must name the offending layout file'
      assert_includes err.message, 'invalid YAML frontmatter',
                      'error must explain what went wrong'
    end
  end

  def test_missing_frontmatter_returns_nil
    Dir.mktmpdir('abqari-layout-test') do |dir|
      path = File.join(dir, 'plain.html.erb')
      File.write(path, "<p>no frontmatter</p>\n")
      assert_nil @renderer.send(:parent_layout_of, path)
    end
  end

  def test_empty_layout_key_returns_nil
    Dir.mktmpdir('abqari-layout-test') do |dir|
      path = File.join(dir, 'no_parent.html.erb')
      File.write(path, "---\ntitle: just metadata\n---\n<p>body</p>")
      assert_nil @renderer.send(:parent_layout_of, path)
    end
  end

  def test_valid_parent_returns_string
    Dir.mktmpdir('abqari-layout-test') do |dir|
      path = File.join(dir, 'extends.html.erb')
      File.write(path, "---\nlayout: application\n---\n<p>body</p>")
      assert_equal 'application', @renderer.send(:parent_layout_of, path)
    end
  end
end

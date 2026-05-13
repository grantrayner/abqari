# frozen_string_literal: true

require_relative 'test_helper'
require 'tmpdir'

# Tests for Page#parse_frontmatter — proves that a malformed frontmatter
# block raises an error that includes the source file path. Without this,
# a build of hundreds of pages reports "did not find expected key at line 4"
# with no way to locate the offending file.
class YamlErrorContextTest < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir('abqari-yaml-error-test')
    @site   = build_site_stub(@tmpdir)
  end

  def teardown
    FileUtils.rm_rf(@tmpdir)
  end

  def build_site_stub(root)
    # Minimal Site stand-in. Page#parse only reads source_path; the rest
    # of the Site API isn't touched.
    site = Object.new
    site.define_singleton_method(:site_root) { root }
    site
  end

  def write_page(name, contents)
    path = File.join(@tmpdir, name)
    File.write(path, contents)
    path
  end

  def test_malformed_yaml_error_includes_source_path
    path = write_page('broken.md', <<~MD)
      ---
      title: Hello
        bad_indent: oops
      tags: [unterminated
      ---
      body
    MD

    err = assert_raises(StandardError) { Abqari::Page.new(path, @site) }
    assert_includes err.message, path,
                    "error message should name the source path, got: #{err.message}"
  end

  def test_disallowed_class_error_includes_source_path
    # Frontmatter that uses a Ruby class outside the safe_load allowlist
    # (e.g. a symbol) should still surface the file path.
    path = write_page('symbol.md', <<~MD)
      ---
      mode: !ruby/symbol live
      ---
      body
    MD

    err = assert_raises(StandardError) { Abqari::Page.new(path, @site) }
    assert_includes err.message, path,
                    "error message should name the source path, got: #{err.message}"
  end

  def test_valid_frontmatter_parses_without_error
    path = write_page('ok.md', <<~MD)
      ---
      title: Hello
      tags:
        - one
        - two
      ---
      body
    MD

    page = Abqari::Page.new(path, @site)
    assert_equal 'Hello', page.frontmatter['title']
    assert_equal %w[one two], page.frontmatter['tags']
  end

  def test_no_frontmatter_is_tolerated
    path = write_page('bare.md', "just markdown body\n")
    page = Abqari::Page.new(path, @site)
    assert_equal({}, page.frontmatter)
  end
end

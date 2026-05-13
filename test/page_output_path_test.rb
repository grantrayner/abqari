# frozen_string_literal: true

require_relative 'test_helper'
require 'ostruct'
require 'tmpdir'

# Negative-path tests for Page#output_path. Frontmatter `permalink:` is
# user-controlled; the engine MUST not let it write outside output_dir.
class PageOutputPathTest < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir('abqari-permalink-test')
    @site = OpenStruct.new(
      output_dir: File.join(@tmpdir, '_site'),
      site_root: @tmpdir,
      collections: {}
    )
    def @site.collection_config(_); {}; end
    @source = File.join(@tmpdir, 'content', 'about.md')
    FileUtils.mkdir_p(File.dirname(@source))
    File.write(@source, "---\ntitle: About\n---\nbody")
  end

  def teardown
    FileUtils.rm_rf(@tmpdir)
  end

  def build_page(frontmatter)
    page = Abqari::Page.allocate
    page.instance_variable_set(:@source_path, @source)
    page.instance_variable_set(:@site, @site)
    page.instance_variable_set(:@frontmatter, frontmatter)
    page.instance_variable_set(:@body, '')
    page
  end

  def test_legal_directory_permalink_lands_under_output_dir
    page = build_page('permalink' => '/about/')
    assert_equal File.join(@site.output_dir, 'about', 'index.html'), page.output_path
  end

  def test_legal_extensionless_permalink_treated_as_directory
    page = build_page('permalink' => '/colophon')
    assert_equal File.join(@site.output_dir, 'colophon', 'index.html'), page.output_path
  end

  def test_legal_file_permalink_preserves_extension
    page = build_page('permalink' => '/404.html')
    assert_equal File.join(@site.output_dir, '404.html'), page.output_path
  end

  def test_dotdot_permalink_is_blocked
    page = build_page('permalink' => '../../etc/passwd')
    assert_raises(Abqari::PathSafe::Error) { page.output_path }
  end

  def test_traversal_to_root_is_blocked
    page = build_page('permalink' => '/../../../tmp/pwned/')
    assert_raises(Abqari::PathSafe::Error) { page.output_path }
  end

  def test_backslash_segment_is_blocked
    page = build_page('permalink' => '\\windows\\system32\\evil')
    assert_raises(Abqari::PathSafe::Error) { page.output_path }
  end

  def test_space_in_permalink_is_blocked
    page = build_page('permalink' => 'about evil')
    assert_raises(Abqari::PathSafe::Error) { page.output_path }
  end

  def test_colon_in_permalink_is_blocked
    page = build_page('permalink' => '/foo:bar/')
    assert_raises(Abqari::PathSafe::Error) { page.output_path }
  end

  def test_query_string_in_permalink_is_blocked
    page = build_page('permalink' => '/about?evil=1')
    assert_raises(Abqari::PathSafe::Error) { page.output_path }
  end
end

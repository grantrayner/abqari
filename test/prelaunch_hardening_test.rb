# frozen_string_literal: true

require_relative 'test_helper'
require 'ostruct'
require 'tmpdir'

# Regression tests for the pre-launch review hardening pass: content
# robustness (BOM / non-Hash / empty frontmatter, invalid dates),
# output-path collision detection, redirect collision detection, the
# minifier inter-tag whitespace fix, and required-key validation.

class MinifierWhitespaceTest < Minitest::Test
  def test_preserves_a_single_space_between_inline_elements
    # `<em>a</em> <strong>b</strong>` must render "a b", not "ab".
    html = '<p><em>a</em> <strong>b</strong></p>'
    out  = Abqari::Minifier.minify(html)
    assert_includes out, '</em> <strong>'
    refute_includes out, '</em><strong>'
  end

  def test_still_collapses_whitespace_runs
    out = Abqari::Minifier.minify("<p>a</p>\n\n   <p>b</p>")
    assert_includes out, '</p> <p>'
  end

  def test_preserves_pre_block_whitespace
    html = "<div><pre>line1\n    indented</pre></div>"
    assert_includes Abqari::Minifier.minify(html), "line1\n    indented"
  end
end

class FrontmatterRobustnessTest < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir('abqari-fm-test')
    @site = OpenStruct.new(collections: {}, site_root: @tmpdir)
    @site.define_singleton_method(:config) { { 'description' => 'fallback' } }
  end

  def teardown
    FileUtils.rm_rf(@tmpdir)
  end

  def page_from(content, name: 'post.md')
    path = File.join(@tmpdir, name)
    File.write(path, content, mode: 'wb')
    Abqari::Page.new(path, @site)
  end

  def test_utf8_bom_does_not_break_frontmatter_detection
    page = page_from("\xEF\xBB\xBF---\ntitle: Hello\n---\nBody text")
    assert_equal 'Hello', page.frontmatter['title']
    refute_includes page.body, '---'
  end

  def test_empty_frontmatter_block_is_not_rendered_as_body
    page = page_from("---\n---\nJust the body")
    assert_equal({}, page.frontmatter)
    refute_includes page.body, '---'
    assert_includes page.body, 'Just the body'
  end

  def test_non_hash_frontmatter_raises_with_source_path
    # Abqari::UserError — a content mistake, printed without a backtrace.
    err = assert_raises(Abqari::UserError) { page_from("---\njust a bare string\n---\nbody") }
    assert_includes err.message, 'must be a mapping'
    assert_includes err.message, @tmpdir
  end

  def test_malformed_frontmatter_yaml_reports_file_and_position
    err = assert_raises(Abqari::UserError) { page_from("---\ntitle: [unclosed\n---\nbody") }
    assert_includes err.message, @tmpdir, 'names the file'
    assert_match(/line \d+/, err.message, 'and where in the frontmatter')
    refute_match(/psych/i, err.message, 'without Psych internals leaking through')
  end

  def test_invalid_date_raises_with_source_path
    page = page_from("---\ntitle: X\ndate: banana\n---\nbody")
    err = assert_raises(RuntimeError) { page.date }
    assert_includes err.message, 'invalid date'
    assert_includes err.message, @tmpdir
  end

  def test_invalid_encoding_raises_with_source_path
    # A lone 0xFF byte is not valid UTF-8.
    err = assert_raises(RuntimeError) { page_from("---\ntitle: X\n---\n\xFF\xFE bad") }
    assert_includes err.message, @tmpdir
  end
end

class OutputPathCollisionTest < Minitest::Test
  # Minimal page double: only needs source_path + output_path.
  Page = Struct.new(:source_path, :output_path) do
    def respond_to?(m, *)
      %i[source_path output_path url].include?(m) || super
    end

    def url
      output_path
    end
  end

  def renderer_for(pages)
    site = OpenStruct.new
    site.define_singleton_method(:all_pages) { pages }
    Abqari::Renderer.new(site)
  end

  def test_two_pages_same_output_path_raises
    pages = [
      Page.new('content/posts/2024-01-01-foo/index.md', '/site/_site/posts/foo/index.html'),
      Page.new('content/posts/2024-02-01-foo/index.md', '/site/_site/posts/foo/index.html')
    ]
    err = assert_raises(RuntimeError) { renderer_for(pages).send(:detect_output_collisions!) }
    assert_includes err.message, 'output path collision'
    assert_includes err.message, '2024-01-01-foo'
    assert_includes err.message, '2024-02-01-foo'
  end

  def test_distinct_output_paths_pass
    pages = [
      Page.new('a.md', '/site/_site/a/index.html'),
      Page.new('b.md', '/site/_site/b/index.html')
    ]
    # Should not raise.
    renderer_for(pages).send(:detect_output_collisions!)
  end
end

class RedirectCollisionTest < Minitest::Test
  Page = Struct.new(:source_path, :url, :frontmatter) do
    def respond_to?(m, *)
      %i[source_path url frontmatter].include?(m) || super
    end
  end

  def redirects_for(pages)
    site = OpenStruct.new(output_dir: '/tmp/__redir')
    site.define_singleton_method(:all_pages) { pages }
    site.define_singleton_method(:config) { {} }
    Abqari::Redirects.new(site)
  end

  def test_redirect_from_colliding_with_a_real_page_raises
    # Page a wants to forward /keep/ → but a real page b already lives at
    # /keep/. Writing the stub would overwrite b's index.html.
    pages = [
      Page.new('a.md', '/other/', { 'redirect_from' => ['/keep/'] }),
      Page.new('b.md', '/keep/', {})
    ]
    err = assert_raises(RuntimeError) { redirects_for(pages).send(:collect) }
    assert_includes err.message, 'collides with an existing page'
  end

  def test_self_referential_redirect_raises
    pages = [Page.new('a.md', '/loop/', { 'redirect_from' => ['/loop/'] })]
    err = assert_raises(RuntimeError) { redirects_for(pages).send(:collect) }
    assert_includes err.message, 'infinite redirect loop'
  end

  def test_valid_redirect_is_collected
    pages = [Page.new('a.md', '/new/', { 'redirect_from' => ['/old/'] })]
    mappings = redirects_for(pages).send(:collect)
    assert_equal({ '/old/' => '/new/' }, mappings)
  end
end

class CopyPublicSafetyTest < Minitest::Test
  def setup
    @root = Dir.mktmpdir('abqari-copypub-root')
    @out  = File.join(@root, '_site')
    FileUtils.mkdir_p(File.join(@root, 'public'))
    @site = Abqari::Site.allocate
    @site.instance_variable_set(:@site_root, @root)
    @site.define_singleton_method(:site_root) { @site_root }
    out = @out
    @site.define_singleton_method(:output_dir) { out }
    @site.define_singleton_method(:config) { { 'theme' => 'none' } }
    @site.define_singleton_method(:find_in_paths) { |rel| File.join(@site_root, rel) }
    # Real external_symlink? behaviour (the method under implicit test).
  end

  def teardown
    FileUtils.rm_rf(@root)
    FileUtils.rm_rf(@external) if @external && Dir.exist?(@external)
  end

  def public_file(rel, content = 'x')
    path = File.join(@root, 'public', rel)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, content)
    path
  end

  def copy!
    Abqari::ArtifactWriter.new(@site).copy_public
  end

  def test_normal_files_are_copied
    public_file('favicon.ico', 'icon')
    copy!
    assert_equal 'icon', File.read(File.join(@out, 'favicon.ico'))
  end

  def test_well_known_is_copied
    public_file('.well-known/security.txt', 'contact')
    copy!
    assert File.exist?(File.join(@out, '.well-known', 'security.txt'))
  end

  def test_dot_directory_contents_are_not_copied
    public_file('.git/config', 'secret')
    copy!
    refute File.exist?(File.join(@out, '.git', 'config')),
           '.git/ contents must not be published'
  end

  def test_external_symlink_contents_are_not_copied
    @external = Dir.mktmpdir('abqari-copypub-ext')
    secret = File.join(@external, 'secret.txt')
    File.write(secret, 'private key')
    File.symlink(secret, File.join(@root, 'public', 'leak.txt'))
    copy!
    refute File.exist?(File.join(@out, 'leak.txt')),
           'external symlink target must not be copied into _site/'
  end
end

class RequiredKeyValidationTest < Minitest::Test
  def test_blank_url_in_production_warns
    out, err = capture_io do
      Abqari::SiteConfig.validate!({ 'title' => 'X' }, env: :production)
    end
    assert_match(/Missing `url`/, err + out)
  end

  def test_blank_url_in_production_raises_under_strict
    assert_raises(Abqari::UserError) do
      capture_io { Abqari::SiteConfig.validate!({ 'title' => 'X' }, strict: true, env: :production) }
    end
  end

  def test_scheme_less_url_names_the_actual_mistake
    # `URI.parse('example.com')` puts the whole string in `path`, so
    # this used to be reported as "has a path component" — true, but
    # pointing at the wrong problem.
    err = assert_raises(Abqari::UserError) do
      Abqari::SiteConfig.validate!({ 'title' => 'X', 'url' => 'example.com' }, env: :production)
    end
    assert_match(/missing a scheme/, err.message)
    assert_match(%r{https://example\.com}, err.message)
  end

  def test_path_bearing_url_is_rejected
    err = assert_raises(Abqari::UserError) do
      Abqari::SiteConfig.validate!(
        { 'title' => 'X', 'url' => 'https://user.github.io/repo' }, env: :production
      )
    end
    assert_includes err.message, 'subdirectory'
  end

  def test_root_url_is_accepted
    # No raise for a bare host or a lone-slash path.
    Abqari::SiteConfig.validate!({ 'title' => 'X', 'url' => 'https://example.com' }, env: :production)
    Abqari::SiteConfig.validate!({ 'title' => 'X', 'url' => 'https://example.com/' }, env: :production)
  end
end

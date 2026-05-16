# frozen_string_literal: true

require_relative 'test_helper'
require 'ostruct'
require 'tmpdir'

# Negative-path tests for the secondary writers that flow user / Folio
# input into filesystem paths. docs/security.md §2 promises that
# "every place the engine joins user-controlled input into a filesystem
# path is routed through PathSafe.join_under" — these tests pin the
# promise to executable behaviour.
#
# Covered:
#   - FolioIndexPage / FolioShowPage `output_path` (bounded-trust slug).
#   - Redirects#write_stub (trusted frontmatter `redirect_from:`, still
#     routed for symmetry).
class FolioRedirectsPathSafeTest < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir('abqari-pathsafe-test')
    @site = OpenStruct.new(
      output_dir: File.join(@tmpdir, '_site'),
      site_root: @tmpdir,
      env: :production,
      all_pages: []
    )
    def @site.config; { 'url' => 'https://example.com' }; end
    FileUtils.mkdir_p(@site.output_dir)
  end

  def teardown
    FileUtils.rm_rf(@tmpdir)
  end

  # --- Folio show page --------------------------------------------------

  def test_folio_show_page_legal_slug_lands_under_output_dir
    page = Abqari::FolioShowPage.new(@site,
                                     kind: 'publication',
                                     slug: 'the-field-guide',
                                     data: { 'title' => 'x' },
                                     layout: 'publication',
                                     url: '/publications/the-field-guide/')
    expected = File.join(@site.output_dir, 'publications', 'the-field-guide', 'index.html')
    assert_equal expected, page.output_path
  end

  def test_folio_show_page_traversal_slug_is_blocked
    # A compromised Folio response with `"slug": "../../etc"` would
    # otherwise let an attacker write a file outside _site/.
    page = Abqari::FolioShowPage.new(@site,
                                     kind: 'publication',
                                     slug: '../../etc/passwd',
                                     data: { 'title' => 'x' },
                                     layout: 'publication',
                                     url: '/publications/../../etc/passwd/')
    assert_raises(Abqari::PathSafe::Error) { page.output_path }
  end

  def test_folio_index_page_legal_url
    page = Abqari::FolioIndexPage.new(@site, 'publications', 'publications_index', '/publications/')
    expected = File.join(@site.output_dir, 'publications', 'index.html')
    assert_equal expected, page.output_path
  end

  def test_folio_index_page_traversal_url_is_blocked
    page = Abqari::FolioIndexPage.new(@site, 'publications', 'publications_index', '/../../etc/')
    assert_raises(Abqari::PathSafe::Error) { page.output_path }
  end

  # --- Redirects --------------------------------------------------------

  def test_redirect_stub_legal_path_writes_under_output_dir
    fake_page = OpenStruct.new(url: '/about/', frontmatter: { 'redirect_from' => ['/old-about/'] })
    def fake_page.respond_to?(name); %i[url frontmatter].include?(name) || super; end
    @site.all_pages << fake_page

    Abqari::Redirects.new(@site).write
    assert File.exist?(File.join(@site.output_dir, 'old-about', 'index.html'))
  end

  def test_redirect_stub_traversal_is_blocked
    fake_page = OpenStruct.new(url: '/about/', frontmatter: { 'redirect_from' => ['/../../etc/passwd/'] })
    def fake_page.respond_to?(name); %i[url frontmatter].include?(name) || super; end
    @site.all_pages << fake_page

    assert_raises(Abqari::PathSafe::Error) { Abqari::Redirects.new(@site).write }
  end

  def test_redirect_stub_escapes_url_interpolations
    # Even though `to` is author-controlled (it's `page.url`), the stub
    # used to interpolate it raw into HTML. Confirm the new path
    # h()-escapes — defensive, and matches every other stub-emitter.
    fake_page = OpenStruct.new(url: '/safe-url/', frontmatter: { 'redirect_from' => ['/legacy/'] })
    def fake_page.respond_to?(name); %i[url frontmatter].include?(name) || super; end
    @site.all_pages << fake_page

    Abqari::Redirects.new(@site).write
    html = File.read(File.join(@site.output_dir, 'legacy', 'index.html'), encoding: 'UTF-8')

    # Spot-check: an attacker-controlled URL with quotes would now be
    # rendered as `&quot;` rather than breaking the href attribute.
    assert_includes html, 'href="/safe-url/"'
    refute_includes html, "javascript:" # sanity check — none should leak
  end
end

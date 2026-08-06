# frozen_string_literal: true

require_relative 'test_helper'
require 'tmpdir'
require 'fileutils'

# What a page bundle publishes, and what it deliberately doesn't.
#
# A bundle is `content/<collection>/<slug>/index.md` plus colocated
# assets. Publishing used to be a deny-list — everything that wasn't a
# directory, dotfile or `index.md` was copied into the output verbatim.
# That shipped a `notes.md` marked `published: false` to production with
# its frontmatter intact, at a guessable URL, which makes the flag a lie.
#
# Publishing is now an allow-list of media extensions, and non-index
# markdown inside a bundle is neither published as an asset nor rendered
# as a page.
class BundleAssetPolicyTest < Minitest::Test
  def setup
    @prev_root = ENV['ABQARI_SITE_ROOT']
    @tmpdir = Dir.mktmpdir('abqari-bundle-policy-test')
    ENV['ABQARI_SITE_ROOT'] = @tmpdir
    @bundle = File.join(@tmpdir, 'content', 'posts', 'my-post')
    FileUtils.mkdir_p(@bundle)
    File.write(File.join(@bundle, 'index.md'), "---\ntitle: My Post\n---\nBody\n")
  end

  def teardown
    ENV['ABQARI_SITE_ROOT'] = @prev_root
    FileUtils.rm_rf(@tmpdir)
  end

  def write(name, content = 'x')
    File.write(File.join(@bundle, name), content)
  end

  # A Page bound to a minimal site stub — enough for the bundle module.
  def page_for(config = {})
    site = Abqari::Site.allocate
    site.instance_variable_set(:@site_root, @tmpdir)
    site.instance_variable_set(:@config, config)
    site.instance_variable_set(:@memos, {})
    Abqari::Page.new(File.join(@bundle, 'index.md'), site)
  end

  def basenames(paths)
    paths.map { |p| File.basename(p) }
  end

  # --- The leak this closes ------------------------------------------

  def test_sibling_markdown_is_not_published_as_an_asset
    write('notes.md', "---\ntitle: Private\npublished: false\n---\nSECRET\n")
    page = page_for

    refute_includes basenames(page.bundle_assets), 'notes.md',
                    'markdown is content, never a bundle asset'
    assert_includes basenames(page.unpublishable_bundle_files), 'notes.md'
  end

  def test_media_assets_still_publish
    %w[hero.jpg diagram.svg talk.mp3 clip.mp4 handout.pdf captions.vtt].each { |f| write(f) }
    page = page_for

    assert_equal %w[captions.vtt clip.mp4 diagram.svg handout.pdf hero.jpg talk.mp3],
                 basenames(page.bundle_assets).sort
    assert_empty page.unpublishable_bundle_files
  end

  # The allow-list's whole purpose: file types nobody enumerated stay
  # behind instead of shipping by default.
  def test_unrecognised_working_files_are_not_published
    %w[cover.psd layout.sketch draft.docx scratch.txt].each { |f| write(f) }
    page = page_for

    assert_empty page.bundle_assets
    assert_equal %w[cover.psd draft.docx layout.sketch scratch.txt],
                 basenames(page.unpublishable_bundle_files).sort
  end

  def test_extensions_are_matched_case_insensitively
    write('HERO.JPG')
    assert_includes basenames(page_for.bundle_assets), 'HERO.JPG'
  end

  def test_dotfiles_remain_invisible_to_both_lists
    write('.notes.md', 'private')
    page = page_for

    assert_empty page.bundle_assets
    assert_empty page.unpublishable_bundle_files,
                 'a dotfile is the documented escape hatch — not published, not warned about'
  end

  # --- Config extensibility ------------------------------------------

  def test_config_can_add_extensions
    write('route.gpx')
    page = page_for('bundle_assets' => { 'extensions' => ['.gpx'] })

    assert_includes basenames(page.bundle_assets), 'route.gpx'
  end

  def test_config_extensions_accept_bare_and_uppercase_forms
    write('model.stl')
    write('route.gpx')
    page = page_for('bundle_assets' => { 'extensions' => %w[STL gpx] })

    assert_equal %w[model.stl route.gpx], basenames(page.bundle_assets).sort
  end

  def test_config_extensions_are_additive_not_replacing
    write('hero.jpg')
    write('route.gpx')
    page = page_for('bundle_assets' => { 'extensions' => ['.gpx'] })

    assert_includes basenames(page.bundle_assets), 'hero.jpg',
                    'adding one extension must not drop the media defaults'
  end

  # The allow-list would be worthless if a config line could undo it.
  def test_markdown_cannot_be_opted_back_in_via_config
    write('notes.md', "---\npublished: false\n---\nSECRET\n")

    page = nil
    _out, err = capture_io do
      page = page_for('bundle_assets' => { 'extensions' => %w[.md .markdown] })
      page.bundle_assets
    end

    assert_empty page.bundle_assets,
                 'markdown must stay unpublishable regardless of config'
    assert_match(/markdown is content/, err, 'and the attempt is reported')
  end
end

# Non-index markdown inside a bundle is skipped at load time, so it
# never renders as a stray page either. Before, it did BOTH — copied
# raw as an asset and rendered at `/posts/my-post/notes/`.
class StrayBundleMarkdownTest < Minitest::Test
  def setup
    @prev_root = ENV['ABQARI_SITE_ROOT']
    @tmpdir = Dir.mktmpdir('abqari-stray-md-test')
    ENV['ABQARI_SITE_ROOT'] = @tmpdir
  end

  def teardown
    ENV['ABQARI_SITE_ROOT'] = @prev_root
    FileUtils.rm_rf(@tmpdir)
  end

  def loader_for
    site = Abqari::Site.allocate
    site.instance_variable_set(:@site_root, @tmpdir)
    site.instance_variable_set(:@config, {})
    site.instance_variable_set(:@memos, {})
    Abqari::SiteLoader.new(site)
  end

  def path(*parts)
    File.join(@tmpdir, 'content', *parts)
  end

  def test_non_index_markdown_in_a_bundle_is_skipped
    loader = loader_for
    stray = path('posts', 'my-post', 'notes.md')

    # Log.warn writes to stderr.
    _out, err = capture_io do
      assert loader.send(:stray_bundle_markdown?, stray)
    end

    assert_match(/Skipping/, err, 'the skip must be announced, not silent')
    assert_match(%r{content/posts/my-post/notes\.md}, err, 'the warning names the file')
    assert_match(/\.notes\.md/, err, 'and offers the dotfile escape hatch')
  end

  def test_bundle_index_is_not_skipped
    refute loader_for.send(:stray_bundle_markdown?, path('posts', 'my-post', 'index.md'))
  end

  def test_collection_index_is_not_skipped
    refute loader_for.send(:stray_bundle_markdown?, path('posts', 'index.md'))
  end

  # Flat collections are the case a naive "has a sibling index.md" check
  # would break: `content/publications/my-book.md` IS the page.
  def test_flat_collection_pages_are_not_skipped
    refute loader_for.send(:stray_bundle_markdown?, path('publications', 'my-book.md'))
  end

  def test_top_level_pages_are_not_skipped
    refute loader_for.send(:stray_bundle_markdown?, path('about.md'))
  end
end

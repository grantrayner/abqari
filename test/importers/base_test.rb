# frozen_string_literal: true

require_relative '../test_helper'
require 'abqari/importers'
require 'tmpdir'

# Base importer — invariants the per-platform tests rely on but
# can't directly assert because they cover only their own platform's
# behaviour. Tests use a `NullImporter` stub that yields a fixed
# set of `ImportedPost` records; behaviour-under-test is the writer
# pipeline, not the source parser.
class ImporterBaseTest < Minitest::Test
  Base = Abqari::Importers::Base

  class NullImporter < Base
    def initialize(source:, opts:, posts:)
      super(source: source, opts: opts)
      @posts = posts
    end

    def each_post
      @posts.each { |p| yield p }
    end
  end

  def setup
    @site_root = Dir.mktmpdir('abqari-importer-base-test-')
    FileUtils.mkdir_p(File.join(@site_root, 'content', 'posts'))
    @opts = Base::Options.new(
      site_root:       @site_root,
      collection:      'posts',
      download_images: false,
      flat:            false,
      force:           false,
      dry_run:         false,
      write_canonical: false,
      strip_selectors: [],
      logger:          ->(_) {}
    )
  end

  def teardown
    FileUtils.rm_rf(@site_root)
  end

  def post(**overrides)
    Base::ImportedPost.new({
      title:             'A post',
      slug:              'a-post',
      date:              Date.new(2024, 1, 1),
      body_html:         '<p>Body.</p>',
      tags:              [],
      description:       nil,
      feature_image_url: nil,
      source_url:        nil,
      source_slug:       nil,
      extra_frontmatter: {}
    }.merge(overrides))
  end

  def run_with(posts, opts_overrides = {})
    opts = Base::Options.new(**@opts.to_h.merge(opts_overrides))
    NullImporter.new(source: 'stub', opts: opts, posts: posts).run!
  end

  def imported_files
    Dir.glob(File.join(@site_root, 'content', 'posts', '**', 'index.md'))
  end

  def test_writes_a_bundle_index_md
    run_with([post])
    assert_equal 1, imported_files.size
    assert_match(/index\.md\z/, imported_files.first)
    assert_match(%r{2024-01-01-a-post/index\.md\z}, imported_files.first)
  end

  def test_resolves_slug_collisions_in_memory
    posts = [post(slug: 'duplicate'), post(slug: 'duplicate', date: Date.new(2024, 2, 1))]
    run_with(posts)
    paths = imported_files.map { |p| File.basename(File.dirname(p)) }
    assert_includes paths, '2024-01-01-duplicate'
    assert_includes paths, '2024-02-01-duplicate-2'
  end

  def test_skips_existing_files_by_default
    run_with([post])
    rep = run_with([post])
    assert_equal 0, rep.count(:imported)
    assert_equal 1, rep.count(:skipped)
  end

  def test_force_overwrites_existing
    run_with([post])
    rep = run_with([post], force: true)
    assert_equal 1, rep.count(:imported)
  end

  def test_dry_run_skips_disk_writes
    run_with([post], dry_run: true)
    assert_empty imported_files
  end

  def test_frontmatter_includes_required_keys
    run_with([post(description: 'Hello', tags: %w[a b])])
    body = File.read(imported_files.first)
    assert_match(/^title: A post$/, body)
    assert_match(/^published: true$/, body)
    assert_match(/^date: 2024-01-01$/, body)
    assert_match(/^description: Hello$/, body)
    assert_match(/^tags: \[a, b\]$/, body)
  end

  def test_canonical_url_only_when_opt_in
    p = post(source_url: 'https://example.com/p/foo')
    run_with([p]) # default: no canonical
    refute_match(/canonical_url:/, File.read(imported_files.first))

    FileUtils.rm_rf(@site_root)
    FileUtils.mkdir_p(File.join(@site_root, 'content', 'posts'))
    run_with([p], write_canonical: true)
    assert_match(%r{canonical_url:.*example\.com/p/foo}, File.read(imported_files.first))
  end

  def test_handles_empty_title_gracefully
    run_with([post(title: '', slug: '')])
    # Empty title → falls through to 'untitled' slug, doesn't crash.
    assert_equal 1, imported_files.size
  end

  def test_writes_import_report
    run_with([post])
    report_path = File.join(@site_root, '_import_report.md')
    assert File.exist?(report_path), 'expected _import_report.md to be written'
    assert_match(/# Import report/, File.read(report_path))
  end

  def test_flat_mode_writes_single_file_posts
    run_with([post], flat: true)
    bundles = Dir.glob(File.join(@site_root, 'content', 'posts', '*', 'index.md'))
    assert_empty bundles
    files = Dir.glob(File.join(@site_root, 'content', 'posts', '*.md'))
    assert_equal 1, files.size
  end
end

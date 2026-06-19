# frozen_string_literal: true

require_relative '../test_helper'
require 'abqari/importers'
require 'abqari/importers/substack'
require 'tmpdir'

# Substack importer — end-to-end against a small fixture directory
# under `test/importers/fixtures/substack-sample/`. The fixture has
# six rows in posts.csv covering all the publish-status paths the
# importer must handle: published+everyone, paid, draft, podcast,
# and a slug collision against another published post.
class SubstackImporterTest < Minitest::Test
  Substack = Abqari::Importers::Substack
  Options  = Abqari::Importers::Base::Options

  def setup
    @fixture = File.expand_path('fixtures/substack-sample', __dir__)
    @site_root = Dir.mktmpdir('abqari-substack-test-')
    FileUtils.mkdir_p(File.join(@site_root, 'content', 'posts'))
    @opts = Options.new(
      site_root:       @site_root,
      collection:      'posts',
      download_images: false, # don't hit the network in tests
      flat:            false,
      force:           false,
      dry_run:         false,
      write_canonical: false,
      strip_selectors: [],
      logger:          ->(_) {} # silence
    )
  end

  def teardown
    FileUtils.rm_rf(@site_root)
  end

  def run_importer(extra_opts = {})
    opts = Options.new(**@opts.to_h.merge(extra_opts))
    Substack.new(source: @fixture, opts: opts).run!
  end

  def imported_files
    Dir.glob(File.join(@site_root, 'content', 'posts', '**', 'index.md'))
  end

  def test_imports_published_posts
    report = run_importer
    # Four "real" posts (101 / 102 / 103 / 106) — drafts and podcasts
    # are filtered; paid posts come through with `audience:` set in
    # frontmatter. 106 collides with 101's slug, so the de-dupe path
    # kicks in to produce `first-post-2`.
    assert_equal 4, report.count(:imported)
    assert_equal 0, report.count(:failed)
    assert_equal 4, imported_files.size
  end

  def test_skips_drafts_and_podcasts
    report = run_importer
    # Drafts and podcasts don't appear as imported entries at all
    # (they're filtered before yielding).
    titles = report.entries.map(&:title)
    refute_includes titles, 'Draft'
    refute_includes titles, 'Podcast'
  end

  def test_paid_audience_flagged_in_frontmatter
    run_importer
    paid = imported_files.find { |p| File.read(p).include?('Paid post') }
    refute_nil paid, 'paid post should be imported'
    body = File.read(paid)
    assert_match(/audience:\s*only_paid/, body)
  end

  def test_collision_appends_numeric_suffix
    run_importer
    # 101 → first-post, 106 → first-post-2 (slug normalised + de-duped).
    paths = imported_files.map { |p| File.basename(File.dirname(p)) }
    assert_includes paths, '2024-03-15-first-post'
    assert_includes paths, '2024-08-01-first-post-2'
  end

  def test_strips_subscription_widget_chrome
    run_importer
    first = imported_files.find { |p| p.include?('first-post') && !p.include?('first-post-2') }
    body = File.read(first)
    refute_match(/Subscribe now/i, body, 'subscription widget should be stripped')
    assert_match(/Welcome to my newsletter/, body)
  end

  def test_writes_redirect_from_for_substack_slug
    run_importer
    body = File.read(imported_files.find { |p| p.include?('second-post') })
    # Short single-item arrays render inline by the YAML formatter.
    assert_match(%r{^redirect_from:\s*\[/p/second-post/\]\s*$}, body)
  end

  def test_skips_existing_files_by_default
    run_importer
    second = run_importer # rerun — should skip
    assert_equal 0, second.count(:imported)
    assert_equal 4, second.count(:skipped)
  end

  def test_force_overwrites
    run_importer
    second = run_importer(force: true)
    assert_equal 4, second.count(:imported)
    assert_equal 0, second.count(:skipped)
  end

  def test_dry_run_writes_no_files
    report = run_importer(dry_run: true)
    assert_equal 4, report.count(:imported)
    assert_empty imported_files, 'dry-run should not write files'
  end

  def test_into_writes_to_alternate_collection
    FileUtils.mkdir_p(File.join(@site_root, 'content', 'notes'))
    run_importer(collection: 'notes')
    notes = Dir.glob(File.join(@site_root, 'content', 'notes', '**', 'index.md'))
    assert_equal 4, notes.size
  end
end

# frozen_string_literal: true

require_relative '../test_helper'
require 'abqari/importers'
require 'abqari/importers/ghost'
require 'tmpdir'

# Ghost JSON-export importer — exercises the `db: [{ data: {...} }]`
# wrapper Ghost uses for content exports, tag resolution via the
# `posts_tags` join table, and the chrome-stripping for Ghost-specific
# card divs (bookmark cards, callouts, etc.).
class GhostImporterTest < Minitest::Test
  Ghost   = Abqari::Importers::Ghost
  Options = Abqari::Importers::Base::Options

  def setup
    @fixture = File.expand_path('fixtures/ghost-sample.json', __dir__)
    @site_root = Dir.mktmpdir('abqari-ghost-test-')
    FileUtils.mkdir_p(File.join(@site_root, 'content', 'posts'))
    @opts = Options.new(
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

  def imported_files
    Dir.glob(File.join(@site_root, 'content', 'posts', '**', 'index.md'))
  end

  def test_imports_published_posts_only
    report = Ghost.new(source: @fixture, opts: @opts).run!
    # 3 fixture posts: hello-ghost (published), members-only
    # (published, members visibility), draft-post (draft → skip).
    assert_equal 2, report.count(:imported)
    assert_equal 2, imported_files.size
  end

  def test_resolves_tags_via_join_table
    Ghost.new(source: @fixture, opts: @opts).run!
    body = File.read(imported_files.find { |p| p.include?('hello-ghost') })
    assert_match(/tags:\s*\[Ruby, Static sites\]/, body)
  end

  def test_strips_ghost_bookmark_card_chrome
    Ghost.new(source: @fixture, opts: @opts).run!
    body = File.read(imported_files.find { |p| p.include?('hello-ghost') })
    refute_match(/card link/, body, 'bookmark-card content should be stripped')
    assert_match(/This is a Ghost post/, body)
    assert_match(/After the card/, body)
  end

  def test_members_visibility_recorded_in_frontmatter
    Ghost.new(source: @fixture, opts: @opts).run!
    body = File.read(imported_files.find { |p| p.include?('members-only') })
    assert_match(/visibility:\s*members/, body)
  end

  def test_writes_redirect_from_from_slug
    Ghost.new(source: @fixture, opts: @opts).run!
    body = File.read(imported_files.find { |p| p.include?('hello-ghost') })
    assert_match(%r{^redirect_from:\s*\[/hello-ghost/\]\s*$}, body)
  end

  def test_dry_run_writes_nothing
    opts = Options.new(**@opts.to_h.merge(dry_run: true))
    Ghost.new(source: @fixture, opts: opts).run!
    assert_empty imported_files
  end
end

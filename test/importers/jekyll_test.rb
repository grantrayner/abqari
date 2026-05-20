# frozen_string_literal: true

require_relative '../test_helper'
require 'abqari/importers'
require 'abqari/importers/jekyll'
require 'tmpdir'

# Jekyll importer — moves _posts/YYYY-MM-DD-slug.md files into Abqari
# bundle layout, merges categories+tags, copies colocated assets,
# and warns on Liquid template tags that need manual conversion.
class JekyllImporterTest < Minitest::Test
  Jekyll  = Abqari::Importers::Jekyll
  Options = Abqari::Importers::Base::Options

  def setup
    @fixture = File.expand_path('fixtures/jekyll-sample', __dir__)
    @site_root = Dir.mktmpdir('abqari-jekyll-test-')
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

  def test_imports_jekyll_posts_into_bundle_layout
    report = Jekyll.new(source: @fixture, opts: @opts).run!
    assert_equal 2, report.count(:imported)
    # Bundle directories created with the YYYY-MM-DD- prefix.
    paths = imported_files.map { |p| File.basename(File.dirname(p)) }
    assert_includes paths, '2024-03-01-hello-jekyll'
    assert_includes paths, '2024-04-15-welcome'
  end

  def test_merges_categories_into_tags
    Jekyll.new(source: @fixture, opts: @opts).run!
    body = File.read(imported_files.find { |p| p.include?('hello-jekyll') })
    assert_match(/tags:\s*\[ruby, blogging, tutorial\]/, body)
  end

  def test_preserves_markdown_body_verbatim
    Jekyll.new(source: @fixture, opts: @opts).run!
    body = File.read(imported_files.find { |p| p.include?('hello-jekyll') })
    # Body should still be markdown — `**Jekyll**` not converted.
    assert_match(/This is a \*\*Jekyll\*\* post/, body)
  end

  def test_warns_on_liquid_template_tags
    report = Jekyll.new(source: @fixture, opts: @opts).run!
    hello = report.entries.find { |e| e.slug.include?('hello-jekyll') }
    refute_nil hello
    assert hello.warnings.any? { |w| w.match?(/Liquid template tag/) },
           "expected a Liquid warning on the hello-jekyll post, got: #{hello.warnings.inspect}"
  end

  def test_copies_colocated_assets
    Jekyll.new(source: @fixture, opts: @opts).run!
    welcome_dir = imported_files.find { |p| p.include?('welcome') }
    refute_nil welcome_dir
    assets = Dir.glob(File.join(File.dirname(welcome_dir), '*.jpg'))
    assert_equal 1, assets.size, 'expected intro.jpg to be copied alongside the post'
  end
end

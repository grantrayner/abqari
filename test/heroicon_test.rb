# frozen_string_literal: true

require_relative 'test_helper'

# `heroicon(name, variant:)` inlines an engine-bundled Heroicon SVG.
# The icons live in `vendor/heroicons/` and ship in the gem — these
# tests pin both the helper behaviour and the presence of the vendored
# tree (which once existed only as a gemspec glob matching nothing, so
# every heroicon() call silently rendered '').
class HeroiconTest < Minitest::Test
  def setup
    @site = TestHelpers.built_site
    @ctx  = Abqari::RenderContext.new(@site.posts.first, @site)
  end

  def test_vendored_tree_exists_for_every_variant
    Abqari::RenderContext::PictureHelpers::HEROICON_VARIANTS.each_value do |subdir|
      dir = File.join(@site.engine_root, 'vendor', 'heroicons', subdir)
      assert Dir.exist?(dir), "expected vendored heroicons dir #{subdir}"
      refute_empty Dir.glob(File.join(dir, '*.svg')), "expected SVGs in #{subdir}"
    end
  end

  def test_vendored_tree_ships_its_license
    assert File.exist?(File.join(@site.engine_root, 'vendor', 'heroicons', 'LICENSE')),
           'heroicons is MIT-licensed third-party work; the license text must ship'
  end

  def test_renders_an_outline_icon_by_default
    svg = @ctx.heroicon('book-open')
    assert_match(/\A<svg /, svg)
    assert_includes svg, 'viewBox="0 0 24 24"'
    assert_includes svg, 'stroke="currentColor"'
  end

  def test_variant_selects_the_matching_folder
    mini = @ctx.heroicon('book-open', variant: :mini)
    assert_includes mini, 'viewBox="0 0 20 20"'

    micro = @ctx.heroicon('book-open', variant: :micro)
    assert_includes micro, 'viewBox="0 0 16 16"'
  end

  def test_extra_attrs_are_escaped_and_merged_onto_the_svg_tag
    svg = @ctx.heroicon('book-open', class: 'nav-icon', 'aria-label': 'A "quoted" label')
    assert_match(/<svg[^>]* class="nav-icon"/, svg)
    assert_includes svg, 'aria-label="A &quot;quoted&quot; label"'
  end

  def test_unknown_icon_renders_empty_string
    assert_equal '', @ctx.heroicon('no-such-icon-name')
  end

  def test_unknown_variant_renders_empty_string
    assert_equal '', @ctx.heroicon('book-open', variant: :giant)
  end
end

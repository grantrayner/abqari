# frozen_string_literal: true

require_relative 'test_helper'

# Auto OG cards derive their gradient from the active theme when the
# site hasn't set an explicit `manifest.theme_color`. The precedence
# is: explicit theme_color (a deliberate brand choice) → the shipped
# theme's gradient pair → the neutral slate fallback. Before this,
# every site without a theme_color got the same slate card regardless
# of theme, so a warm magazine/sand site shared cold blue-grey links.
class OgThemeGradientTest < Minitest::Test
  def generator_for(config)
    site = Struct.new(:config).new(config)
    Abqari::OgImageGenerator.new(site)
  end

  def gradient(config)
    generator_for(config).send(:gradient_colors)
  end

  def test_explicit_theme_color_always_wins
    colors = gradient({ 'theme' => 'sand',
                        'manifest' => { 'theme_color' => '#0066cc' } })
    assert_equal '#0066cc', colors.first
  end

  def test_shipped_theme_gradient_used_when_no_theme_color
    Abqari::OgImageGenerator::THEME_GRADIENTS.each do |theme, pair|
      assert_equal pair, gradient({ 'theme' => theme }),
                   "#{theme} should use its own OG gradient"
    end
  end

  def test_unlisted_theme_falls_back_to_neutral_slate
    assert_equal %w[#1f2937 #0f172a], gradient({ 'theme' => 'minimal' })
    assert_equal %w[#1f2937 #0f172a], gradient({ 'theme' => 'mytheme' })
  end

  def test_gradient_pairs_are_valid_hex
    Abqari::OgImageGenerator::THEME_GRADIENTS.each_value do |pair|
      pair.each { |hex| assert_match(/\A#[0-9a-f]{6}\z/i, hex) }
    end
  end
end

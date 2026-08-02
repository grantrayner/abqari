# frozen_string_literal: true

module Abqari
  # The self-hosted webfonts each shipped theme's font stacks ask for.
  # A theme is a token file — its `--font-*` stacks can name any face —
  # but the faces only render if the site actually downloads them
  # (`fonts:` in config/site.yml + `bin/fetch-fonts`). Before this map
  # existed, magazine and sand silently fell back to system serifs on
  # every site that didn't hand-maintain the list, and their typographic
  # identity never materialised.
  #
  # Consumed by `abqari new --theme <name>` (scaffolds the matching
  # `fonts:` block) and `abqari theme eject` (prints the block as a
  # hint). Themes not listed use system fonts and need nothing.
  module ThemeFonts
    FONTS = {
      # Display headings; body is Charter/Palatino/Georgia (system).
      'magazine' => [
        { 'family' => 'Playfair Display', 'weights' => [700], 'style' => 'normal' }
      ].freeze,
      # Inter body + JetBrains Mono for headings/meta/code.
      'notebook' => [
        { 'family' => 'Inter',          'weights' => [400, 600], 'style' => 'normal' },
        { 'family' => 'JetBrains Mono', 'weights' => [400, 600], 'style' => 'normal' }
      ].freeze,
      # Merriweather body (regular + italic — serif prose needs a true
      # italic) + Merriweather Sans for headings and UI.
      'sand' => [
        { 'family' => 'Merriweather',      'weights' => [400, 700], 'style' => 'normal' },
        { 'family' => 'Merriweather',      'weights' => [400],      'style' => 'italic' },
        { 'family' => 'Merriweather Sans', 'weights' => [400, 600], 'style' => 'normal' }
      ].freeze
    }.freeze

    def self.for(theme)
      FONTS.fetch(theme.to_s, [])
    end

    # The `fonts:` entries as site.yml-ready YAML lines (no leading
    # `fonts:` key — callers decide how to frame the block).
    def self.yaml_entries(theme, indent: '')
      self.for(theme).map do |font|
        <<~YAML.gsub(/^/, indent).rstrip
          - family: #{font['family']}
            weights: [#{font['weights'].join(', ')}]
            style: #{font['style']}
        YAML
      end.join("\n")
    end
  end
end

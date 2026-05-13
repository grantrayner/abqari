# frozen_string_literal: true

require_relative 'lib/abqari'

Gem::Specification.new do |spec|
  spec.name        = 'abqari'
  spec.version     = Abqari::VERSION
  spec.authors     = ['Grant Rayner']
  spec.summary     = 'Ruby static site generator — Folio-aware, prose-led.'
  spec.description = <<~DESC
    Abqari is a Ruby static site generator for author / publisher sites.
    Folio integration brings in publications, bundles, and series; the
    engine provides layouts, partials, themes, and a structural CSS
    framework that user sites consume and selectively override.
  DESC

  spec.required_ruby_version = '>= 3.3'
  spec.license               = 'MIT'

  # The gem ships its lib code, the structural app/ (views, icons,
  # _common.css and other assets), the bundled themes, and the
  # vendored 3rd-party assets that the engine renders against
  # (heroicons, d3). It deliberately does NOT ship `content/`,
  # `config/`, `data/`, `vendor/folio/`, or `vendor/fonts/` —
  # those are site-specific and live in the consuming repo.
  spec.files = Dir[
    'lib/**/*',
    'app/views/**/*',
    'app/icons/**/*',
    'app/assets/**/*',
    'themes/**/*',
    'vendor/heroicons/**/*',
    'vendor/d3/**/*',
    'README*',
    'LICENSE*',
    'CHANGELOG*'
  ]

  spec.executables = Dir['bin/*'].map { |f| File.basename(f) }

  spec.add_dependency 'base64',       '~> 0.2'
  spec.add_dependency 'commonmarker', '~> 1.1'
  spec.add_dependency 'erubi',        '~> 1.13'
  spec.add_dependency 'rouge',        '~> 4.0'
  spec.add_dependency 'webrick',      '~> 1.8'
end

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
  spec.homepage              = 'https://github.com/grantrayner/abqari'
  spec.metadata              = {
    # Note: `homepage_uri` is intentionally omitted — `spec.homepage`
    # above is the canonical source. RubyGems warns when both are set.
    'source_code_uri'       => 'https://github.com/grantrayner/abqari',
    'changelog_uri'         => 'https://github.com/grantrayner/abqari/blob/main/CHANGELOG.md',
    'documentation_uri'     => 'https://github.com/grantrayner/abqari#readme',
    'bug_tracker_uri'       => 'https://github.com/grantrayner/abqari/issues',
    'rubygems_mfa_required' => 'true'
  }

  # The gem ships its lib code (including the site_skeleton template
  # tree used by `abqari new`), the structural app/ (views, icons,
  # _common.css and other assets), the bundled themes, and the
  # vendored 3rd-party assets that the engine renders against
  # (heroicons, d3). It deliberately does NOT ship `content/`,
  # `config/`, `data/`, `vendor/folio/`, or `vendor/fonts/` from
  # the engine repo — those are site-specific and live in the
  # consuming site.
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
  ] + Dir[
    # The skeleton ships a `.github/workflows/` tree (the deploy
    # workflows for Cloudflare / Render / GitHub Pages). `Dir.glob`
    # excludes dotfiles by default, so the lib/**/* entry above
    # silently drops them. The explicit dotglob below picks them up.
    'lib/abqari/templates/site_skeleton/.github/**/*'
  ]

  # Single global executable. `exe/abqari` is on PATH after `gem
  # install abqari`; it dispatches to subcommands (currently `new` —
  # bootstrap a new site — with `version` / `help` as standard
  # auxiliaries). Per-site commands (build, serve, audit, etc.)
  # live as `bin/*` scripts inside each scaffolded site, not as
  # global executables, to avoid name conflicts on PATH.
  spec.bindir      = 'exe'
  spec.executables = ['abqari']

  spec.add_dependency 'base64',          '~> 0.2'
  spec.add_dependency 'commonmarker',    '~> 1.1'
  # csv: used by `Abqari::Importers::Substack` to read the export's
  # posts.csv manifest. Moved out of Ruby's default gem set in 3.4 —
  # pinned explicitly so the gem still works under Bundler's frozen mode.
  spec.add_dependency 'csv',             '~> 3.3'
  spec.add_dependency 'erubi',           '~> 1.13'
  # reverse_markdown: lazy-loaded by the content importers (bin/import).
  # Normal builds never pull it into memory; the gem is small pure Ruby.
  spec.add_dependency 'reverse_markdown', '~> 2.1'
  spec.add_dependency 'rouge',           '~> 4.0'
  # ruby-vips: native libvips bindings for the image pipeline. The gem
  # is small pure-FFI Ruby; the install footprint is the libvips C
  # library (`brew install vips` / `apt install libvips42`). The
  # pipeline falls back to shell-out (vips / magick CLI) if libvips
  # is missing at runtime, so deploys that don't ship libvips still
  # work — just slower per image.
  spec.add_dependency 'ruby-vips',    '~> 2.2'
  spec.add_dependency 'webrick',      '~> 1.8'

  spec.post_install_message = <<~MSG
    Abqari's image pipeline uses libvips for responsive image
    generation. Install the C library once:

      macOS:    brew install vips
      Ubuntu:   sudo apt install libvips42
      Alpine:   apk add vips

    If libvips isn't available, the build falls back to shell-out to
    `vips` / `magick` (slower) and ultimately to passthrough mode
    (originals only, no responsive variants).
  MSG
end

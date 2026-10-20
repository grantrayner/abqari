# frozen_string_literal: true

# Load ONLY the version constant — never the engine. Requiring
# `lib/abqari` here would pull in erubi/commonmarker/rouge/webrick, and
# Bundler evaluates this file before installing dependencies when the
# gem is consumed from a git or path source. See lib/abqari/version.rb.
require_relative 'lib/abqari/version'

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
  spec.files = (Dir[
    'lib/**/*',
    'app/views/**/*',
    'app/icons/**/*',
    'app/assets/**/*',
    'themes/**/*',
    'vendor/heroicons/**/*',
    'vendor/d3/**/*',
    'README*',
    'LICENSE*',
    'CHANGELOG*',
    # Ships so someone auditing the installed gem finds the reporting
    # channel and the trust model without going back to GitHub.
    'SECURITY*',
    'THIRD_PARTY_NOTICES*'
  ] + Dir.glob(
    # The skeleton ships dotfiles — `.gitignore`, the `vendor/*/.gitkeep`
    # placeholders, and the `.github/` deploy workflows (Cloudflare /
    # Render / GitHub Pages). `Dir.glob` excludes dotfiles by default,
    # so the lib/**/* entry above silently drops them; this second pass
    # re-globs the whole skeleton with FNM_DOTMATCH to pick them up.
    # The trailing `file?` filter drops directories from both passes,
    # and `uniq` folds the overlap with lib/**/*.
    'lib/abqari/templates/site_skeleton/**/*', File::FNM_DOTMATCH
  )).select { |f| File.file?(f) }.uniq

  # Single global executable. `exe/abqari` is on PATH after `gem
  # install abqari`; it dispatches to subcommands (currently `new` —
  # bootstrap a new site — with `version` / `help` as standard
  # auxiliaries). Per-site commands (build, serve, audit, etc.)
  # live as `bin/*` scripts inside each scaffolded site, not as
  # global executables, to avoid name conflicts on PATH.
  spec.bindir      = 'exe'
  spec.executables = ['abqari']

  spec.add_dependency 'base64',          '~> 0.2'
  # commonmarker: floor is 2.4 deliberately. Its precompiled native
  # binaries are per-Ruby-ABI, and 3.4 support first appears in 2.4 —
  # on 1.1.x (binaries stop at Ruby 3.3) anyone installing under 3.4
  # falls back to building from source, which needs a Rust toolchain
  # most deploy hosts don't have.
  spec.add_dependency 'commonmarker',    '~> 2.4'
  # csv: used by `Abqari::Importers::Substack` to read the export's
  # posts.csv manifest. Moved out of Ruby's default gem set in 3.4 —
  # pinned explicitly so the gem still works under Bundler's frozen mode.
  spec.add_dependency 'csv',             '~> 3.3'
  spec.add_dependency 'erubi',           '~> 1.13'
  # HTML5 parsing for CSP audits and text extraction. Unlike the
  # nokogiri/racc chain, this has no transitive runtime dependencies;
  # its precompiled gems are checked by the clean-slim CI matrix.
  spec.add_dependency 'nokolexbor',      '~> 0.8.0'
  spec.add_dependency 'rouge',           '~> 4.0'
  # ruby-vips: native libvips bindings for the image pipeline. The gem
  # is small pure-FFI Ruby; the install footprint is the libvips C
  # library (`brew install vips` / `apt install libvips42`). The
  # pipeline falls back to shell-out (vips / magick CLI) if libvips
  # is missing at runtime, so deploys that don't ship libvips still
  # work — just slower per image.
  spec.add_dependency 'ruby-vips',    '~> 2.2'
  spec.add_dependency 'webrick',      '~> 1.8'

  # NOT a runtime dependency, deliberately: `reverse_markdown`.
  #
  # It's needed only by the content importers (`bin/import`), which are
  # a one-time migration step most sites never run — and it pulls in
  # nokogiri, which pulls in racc. On Ruby 3.3 (this gem's declared
  # floor) that chain BREAKS installation on a toolchain-free image:
  # 3.3 bundles racc 1.7.3, Bundler resolves to 1.8.1, and 1.8.1 ships
  # no precompiled Linux binary, so `bundle install` tries to compile
  # and fails for want of `make`. Verified in ruby:3.3-slim.
  #
  # `Importers::Support::HtmlToMarkdown` requires it at point of use and
  # raises an actionable error if it's absent. Adding it back here would
  # make every install pay for a feature almost nobody uses, and would
  # re-break the floor.

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

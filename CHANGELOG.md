# Changelog

All notable changes to Abqari will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- **Workshops collection** — fourth built-in collection alongside posts /
  photos / publications. Ships `app/views/layouts/workshop.html.erb` (show
  view with a structured-metadata `<dl>` block) and
  `app/views/layouts/workshops_index.html.erb`. Frontmatter: `date_from`,
  `date_to`, `duration` (fallback), `location`, `format` (In-person /
  Remote / Hybrid), `instructors` (one or many), `price`,
  `registration_url`. All optional — each `<dl>` row renders only when set.
  Enabled by default; `collections.workshops.enabled: false` to suppress.
- **Newsletter-subscribe partial** — provider-agnostic
  (`<%= render 'partials/newsletter_subscribe' %>`). Configured via the
  `newsletter:` block in `config/site.yml`. Works with any provider that
  accepts an HTML form POST (Cogent Notes, Mailchimp, Buttondown,
  ConvertKit / Kit, TinyLetter, Substack). Renders nothing when unconfigured.
- **`theme_toggle: false` config** — opt-out of the light/dark toggle
  button. Default: enabled.
- **`footer.signature` config** — three states (unset / `false` / string)
  for the "Built with Abqari · &lt;year&gt;" line; supports `{year}`
  substitution in custom strings.
- **`.lede` utility class** — Bootstrap-style standfirst-paragraph
  utility. Now used by every index/show layout. Replaces the older
  `.posts-index__lede` / `.about__lede` / etc. component classes.
- **`.small`, `.muted`, `.text-center`, `.text-end`, `.shadow-sm`,
  `.shadow`, `.shadow-lg`, `.shadow-none`** utilities in `_common.css`.
- **`--font-size-body`, `--line-height-body`, `--font-mono`, `--font-sans`
  tokens** — themes express body density and UI typeface via tokens
  rather than overriding `body { ... }` directly.
- **`app/assets/css/site.css` slot** — site-local CSS that loads after
  the theme's `app.css`. Reserve for genuinely site-specific overrides
  that don't belong in a theme or in `_common.css`.
- **Path-source / gem-source consumption** — engine code loads as a gem
  (`gem 'abqari', path: '...'` or `git: '...'`) rather than being
  vendored into each site. Site-local files (`config/`, `content/`,
  `data/`, `public/`, optional overrides) live in the consuming repo;
  layouts, partials, themes, helpers, `_common.css`, and Ruby live in
  the gem. See README "Consuming Abqari" for the workflow.
- **`Site#site_root` + `Site#engine_root`** — explicit path resolution
  for the engine vs the site. `Site#find_in_paths` for "site override
  first, engine fallback" asset/layout lookups.
- **`taxonomy_url(name, term)` helper** — replaces hardcoded
  `/tags/#{slugify(t)}/` patterns; honors per-taxonomy permalink config.
- **`folio_data` helper** — encapsulates the defensive
  `page.respond_to?(:data) ? page.data : {}` pattern in Folio-aware
  show-view layouts.
- **`bin/new post "Title"` and `bin/new page "Title"`** subcommands for
  content scaffolding.
- **Pagefind static search** integration via `bin/index` and
  `search: true` in `site.yml`.
- **GitHub Actions deploy template** for Cloudflare Pages at
  `.github/workflows/deploy.yml`.
- LICENSE (MIT), CHANGELOG, and VERSION constant.

### Changed

- **Default heading scale** uses `clamp()` — h1 / h2 / h3 fluidly scale
  across viewports instead of switching at hard breakpoints.
- **Default date format** for `local_time` is `"1 January 2026"` (was
  `"January 1, 2026"`). Callers passing an explicit `format:` are
  unaffected.
- **`p` margin-bottom** trimmed from `--space-lg` to `--space-md`
  (paragraphs sit closer together).
- **`.publication__description` no longer muted** — renders as normal
  body text.
- **Container width pattern** moved from `* > *` scaffold to a single
  `.container` wrapper inside `<header>` / `<main>` / `<footer>`. New
  components no longer need `margin-block` discipline to preserve
  horizontal alignment.
- **Notebook theme** palette swung from dusty blue to paper + ochre.
  Mono headings via `--font-heading: var(--font-mono)`. Denser body
  (1rem / 1.55) via density tokens.

### Removed

- **Vendored engine code in consuming sites** — `lib/abqari/`,
  `app/views/`, `app/assets/css/_common.css`, `themes/` no longer need
  to be copied into a site repo. See the path-source / gem-source
  entry under Added.
- **`.lead` class** — replaced by `.lede` (the journalism term is the
  semantically correct one for the opening paragraph of a story).
- **Stories example** from `config/site.yml` collections block —
  slug aliasing (`posts.slug: stories`) handles the rename-built-in case,
  which was the example's most common intent. Replaced with a
  `recipes:` placeholder demonstrating a true custom collection, plus
  a tip explaining the slug-vs-custom distinction.

## [0.1.0]

Initial release. All eleven roadmap steps complete:

- ERB templates with partials and helpers
- Posts as directory bundles with colocated assets
- Tags + custom taxonomies, auto-generated index pages
- Pagination
- Asset pipeline with content-hashed fingerprinting
- Themes (minimal, magazine, notebook, bootstrap)
- Self-hosted Google Fonts via `bin/fetch-fonts`
- Inline SVG icons via the `icon()` helper
- libvips/ImageMagick image pipeline with responsive `<picture>` and CLS-safe dimensions
- SEO suite: sitemap (with `<image:image>` and accurate `<lastmod>`), RSS, JSON Feed, OG, JSON-LD, redirects, per-env robots, `_headers`, security.txt
- Build-time `bin/audit` covering links, SEO, accessibility, privacy, dependencies (with bundler-audit integration), content
- Livereload dev server with Listen-based file watcher, debouncing, partial CSS reload
- Custom permalinks per collection
- Drafts (`published: false`) and future-dated post handling
- Data files at `data/*.{yml,json}` accessible via `site.data`
- Syntax highlighting via Rouge
- Single-locale support via `locale:` config
- `bin/new` site configurator with `--clean` option
- Three-layer cascade for nav and footer (data file → frontmatter → fallback)
- Performance: parallel page rendering, compiled-template cache, mtime-aware copying, HTML minification, content memoization, image dimensions in passthrough mode
- Minitest suite (~70 tests, 180+ assertions)

[Unreleased]: https://github.com/your-handle/abqari/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/your-handle/abqari/releases/tag/v0.1.0

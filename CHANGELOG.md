# Changelog

All notable changes to Abqari will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.1.0] — 2026-08-02

Ordered-series navigation and a CSP that can be extended without
being replaced. Both came out of building a course-shaped site — a
module of ordered lessons with colocated audio — on top of the
existing series taxonomies.

### Added

- `Site#prev_in_series` — the backwards counterpart to
  `next_in_series`. Both now delegate to a shared `series_sibling`
  scan, so the two directions can't drift apart.
- `partials/series_pager` — compact bidirectional prev/next series
  nav, for collections readers move through sequentially. The
  forward-only `partials/next_in_series` card is unchanged and still
  what the built-in `post` layout renders; the pager is opt-in from
  your own layout.
- `RenderContext#series_url` and `Site#series_taxonomy_for` — resolve
  the series index URL for a page's own collection instead of
  assuming `posts_series`.
- `media:` config — allows off-origin audio / video in the CSP:

      media:
        host: https://media.example.com   # or a list

  Colocated bundle media needs nothing; it's same-origin and inherits
  `default-src 'self'`. No `media-src` directive is emitted unless a
  host is configured, so existing sites' headers are byte-identical.
- `csp:` config — additive per-directive origin allow-list for
  anything the engine doesn't model:

      csp:
        img-src:     [https://cdn.example.com]
        connect-src: [https://api.example.com]

  Previously the only escape hatch was `headers:`, which replaces the
  computed policy wholesale and takes the pinned theme-bootstrap hash,
  `'wasm-unsafe-eval'` and the Plausible hash down with it. `csp:`
  appends instead. Restricted to eleven extendable directives (the
  hardening directives and `default-src` are excluded); values must be
  `scheme://host`, so keywords, wildcards and non-http schemes are
  rejected by construction. A bad value fails the build rather than
  being silently dropped — a malformed CSP fails open in the browser,
  so a silent skip would ship a policy the operator believes is
  enforced.
- Audit (Content): `series_position` problems that are otherwise
  invisible — a non-Integer position (warn), duplicate positions
  within one series (warn), and a page in a series with no position
  (info). Each of these builds cleanly and renders correctly in
  isolation while dropping out of the prev/next chain.
- `article:published_time` / `article:modified_time` / `article:tag`
  OG meta on posts. `og:type: article` was already emitted, but the
  dates lived only in JSON-LD — Facebook and LinkedIn read the
  OG-level properties, not schema.org.
- The site skeleton now ships `content/404.md` (`permalink:
  /404.html`, `sitemap: false`, `robots: noindex`), so every new site
  starts with a not-found page in both default and `--blank` modes.
- The skeleton's `config/site.yml` gained a commented "SEO + social
  sharing" section (`share_image`, `og_images.auto`, `twitter`,
  `og_locale`) and now discloses the `block_ai_scraping: true`
  default — the knobs existed but new sites had no way to discover
  them from their own config file.
- `deploy` added to `SiteConfig::KNOWN_KEYS` — configuring
  `bin/deploy`'s `deploy:` block no longer warns as an unknown key
  (and no longer errors under `ABQARI_STRICT_CONFIG=true`).

### Changed

- The dev server no longer logs client-disconnect errors. Every open
  tab holds a live-reload SSE stream, and navigating tears that socket
  down without a clean close — WEBrick's own request loop raises
  `Errno::ECONNRESET` from `io_fillbuf` and logs it at ERROR with a
  full backtrace, one per tab per navigation. The SSE handler already
  rescued these, but WEBrick raises before dispatching to application
  code, so the rescue never saw them; filtering at the logger is the
  only interception point.

  `Server::QuietLog` drops `ECONNRESET`, `EPIPE`, `ECONNABORTED` and
  `ENOTCONN` and is otherwise stock `WEBrick::Log`. Suppression is by
  exception class, never by message text, so a genuine fault that
  happens to mention a reset connection is still logged in full — as
  are all other levels, and all String messages. Set
  `ABQARI_VERBOSE_LOG=true` for stock WEBrick logging when the socket
  layer is what you're debugging. Dev-server only; nothing about a
  production deploy changes.

### Fixed

- **The CSS minifier silently deleted every theme token in production
  builds.** `Minifier.css` stashed quoted strings before stripping
  comments, and treated a bare `'` as a string delimiter — but CSS
  comments here are English prose, full of apostrophes ("the theme's
  tokens", "Safari's tap-flash"). Two comments each carrying one
  apostrophe were paired into a single "string" spanning both, so every
  rule between them — plus the `*/` that should have closed the first
  comment — was swallowed and then deleted.

  `_common.css` has an odd number of apostrophes, so in the concatenated
  bundle the casualty was the entire `:root` block of whatever theme
  followed it: every colour and font custom property in the site. Pages
  rendered in Times with no palette. Development builds don't minify, so
  this only appeared once deployed.

  Comments and strings are now tokenised in a single left-to-right pass
  with ordered alternation, so whichever construct starts first consumes
  the other. `content: "/* not a comment */"` still survives verbatim.

- The `post` layout hardcoded `posts_series` in the series breadcrumb
  and the end-of-series note. Since the layout is deliberately
  reusable (`cookbook` ships on it), any other collection's series
  breadcrumb linked into the posts series index. Now resolved from the
  page's own collection, and rendered as plain text when the
  collection has no series taxonomy configured. Posts are unaffected.

- **Auto OG cards: generated pages advertised og:image files that
  don't exist.** With `og_images.auto: true`, the head emitted an
  `<page-url>og.svg` og:image for any page without a hero — but
  `OgImageGenerator` only writes cards for real content pages with
  directory URLs. Tag indexes, pagination shards, related indexes,
  and flat-URL pages (`/404.html` — which produced the mangled
  `/404.htmlog.svg`) all pointed social validators at 404s. The head
  and the generator now share one eligibility predicate
  (`OgImageGenerator.auto_card?`), so they can't drift apart again.

- Slug-aliased posts feeds carried the wrong `<title>`. The head's
  autodiscovery link says "Site — Stories" for a `posts.slug:
  stories` site, but `Feed#feed_title` tested the internal collection
  name instead of the effective slug and emitted just "Site". The
  comment claimed they matched; now they do.

- The skeleton config's commented social-links example used the wrong
  key (`social_links:` — the engine reads `social:`) and bare handles
  where the engine expects full URLs. Uncommenting it produced an
  unknown-key warning and, with the key corrected, broken footer
  links. A scaffold test now validates both templates' keys — real
  AND commented examples — against `KNOWN_KEYS`.

- The skeleton config claimed posts feeds render at `/posts/feed.xml`;
  they render at the root `/feed.xml` (deliberately, for subscriber
  back-compat). The footer signature also baked in the scaffold-time
  year — it now uses the `{year}` build-time token, so it can't go
  stale.

- The dev server showed WEBrick's stock error page for unknown URLs
  instead of the site's own `/404.html` — the one page an author
  could never preview with `bin/serve`. Static hosts (Cloudflare
  Pages, Netlify, GitHub Pages) serve the custom page in production;
  the dev server now mirrors them. The status stays 404, only the
  body changes, and WEBrick's default page still appears if the
  build produced no `404.html`.

- The no-libvips regression test failed on any machine with the
  `vips`/`magick` CLIs installed: the subprocess inherited PATH, so
  the pipeline (correctly) picked the shell backend instead of the
  no-backend state under test. The subprocess now runs with an empty
  PATH.

- `abqari new --engine git` scaffolded a placeholder URL
  (`your-handle`) that failed `bundle install` as-is; it now defaults
  to the canonical repo.

## [1.0.0] — 2026-07-14

Initial public release. The engine is feature-complete for the
four content types it targets — long-form writing, photo
galleries, publications, and workshops — with the safety
primitives, IndieWeb integration, and POSSE syndication needed to
run a real working author / publisher site.

### What ships

**Authoring**

- Markdown (CommonMark + GFM) with YAML frontmatter.
- Five default collections: `posts`, `photos`, `publications`,
  `workshops`, `cookbook`. Add your own under `collections:` in
  `config/site.yml`.
- Bundle-style collections (`content/<name>/<slug>/index.md` plus
  colocated assets) and flat single-file pages where appropriate.
- Drafts (`published: false`), future-dated scheduling, custom
  taxonomies with scalar (`country: Syria`) or list (`tags: [a, b]`)
  frontmatter.
- Slug aliasing: rename a built-in collection's URL prefix without
  forking the layout (e.g. `posts.slug: guides` publishes posts at
  `/guides/`).
- Content scaffolders: `bin/new`, `bin/new post "Title"`,
  `bin/new page "Title"`.
- Opt-in collections at scaffold time: `abqari new my-site --with
  photos,publications,workshops` enables the named collections in
  config and creates their `content/<name>/index.md` landing pages.
  Default scaffold stays posts-only.
- Content importers: `bin/import substack|ghost|jekyll <source>`
  pulls content from another platform's export into the site's
  collections — downloads images into bundles, writes
  `redirect_from:` for inbound link preservation, idempotent
  re-runs.

**Templating**

- ERB layouts and partials — real Ruby, no sandboxed templating
  language. Erubi auto-escape for `<%= … %>`; explicit raw form
  `<%== … %>` is allow-listed via a build-time audit.
- Standard helper library — `truncate`, `pluralize`, `local_time`,
  `time_ago`, `time_until`, `years_since`, `excerpt`,
  `reading_time`, `slugify`, `asset_path`, `picture_tag`, `icon`,
  `taxonomy_url`, `script_safe_json`, and more.
- Three-layer cascade for nav and footer (data file →
  frontmatter → fallback).
- Light/dark theme toggle with hash-pinned CSP, no FOUC.
- Spam-resistant contact button, image gallery, carousel,
  newsletter, and webmentions partials.

**Styling**

- Mobile-first responsive CSS with `clamp()` fluid type, safe-area
  insets, `100dvh`, `@media (hover: hover)` gates.
- Five hand-tuned themes — `minimal`, `magazine`, `notebook`,
  `sand`, `bootstrap` — plus `custom` as a starter template and
  `none` to bring your own.
- Decorative SVG title-card covers (`cover: svg` or
  `cover: photo_or_svg`) for posts and workshops without an
  `image:` — slug-hashed gradient with the title word-wrapped over
  it, no per-page artwork required.

**Build pipeline**

- Pretty URLs, content-hashed asset fingerprinting, HTML + CSS + JS
  minification.
- Render-blocking CSS (syntax theme, `_common.css`, theme, site
  overrides) ships as a single fingerprinted bundle — one stylesheet
  request per page, immutable-cached.
- Self-hosted Google Fonts via `bin/fetch-fonts`.
- libvips-backed image pipeline: responsive `<picture>`, AVIF +
  WebP variants, CLS-safe dimensions. Falls back to shell-out
  (`vips` / `magick`) or passthrough mode when libvips isn't
  available.
- Parallel page rendering, compiled-template cache, mtime-aware
  copying.
- Build-OK sentinel (`_site/.abqari-build-ok`) written only on
  successful builds; `bin/deploy` refuses to ship without it.
- Atomic state-file writes (POSSE log, webmention cache, sender
  log) — SIGINT mid-write won't corrupt them.

**Discovery and SEO**

- Sitemap with `<lastmod>` and image extension, RSS, JSON Feed
  (one set per collection that opts in).
- Open Graph + Twitter card meta, JSON-LD `Article` and `Book`
  schemas.
- Per-environment `robots.txt`, `_redirects` from `redirect_from:`
  frontmatter, `security.txt`.
- Plausible analytics: one config line, automatic CSP extension.
- Static search via Pagefind, no third-party server.

**IndieWeb and POSSE**

- Microformats2 markup baked into post, post-list, and about
  layouts (`h-entry`, `h-card`, `p-name`, `dt-published`,
  `e-content`, `p-category`, `u-url`, `h-feed`, `p-summary`).
- Webmention receive via webmention.io with ETag caching. A
  "Replies & mentions" section renders below each post —
  conversational mentions get full author + body cards; likes,
  reposts, and bookmarks render facepile-style.
- Webmention send (opt-in): POSTs notifications to external URLs
  recent posts link to. Tracked in `vendor/webmentions/sent.yml`
  with retry-on-failure semantics.
- Bridgy Fed link tags (opt-in): `<link rel="me">` +
  `application/activity+json` advertisement so Mastodon users can
  follow the site directly via ActivityPub.
- POSSE auto-syndication to Mastodon and Bluesky on each build.
  Per-post opt-out via `syndicate: false`; custom snippet via
  `syndication_text:`. Idempotent; replies on the syndicated
  posts flow back as webmentions via Bridgy Fed.

**Security**

- `PathSafe` for every filesystem write derived from user input
  (permalinks, redirects, bundle assets, og:image generation).
- `HttpSafe` for every build-time HTTP — streaming reads with
  size caps, configurable timeouts, no `Net::HTTP.start` outside
  the wrapper.
- ERB rendering uses Erubi with `escape: true` by default.
  `<%== … %>` is allow-listed via `test/erb_escape_audit_test.rb`.
- YAML loading uses `YAML.safe_load_file` with a minimal
  permitted-classes set (`Date`, `Time` only).
- Strict CSP with hashed inline scripts, `object-src 'none'`,
  `frame-ancestors 'none'`, `base-uri 'self'`.
- The dev server binds to `127.0.0.1` by default. WEBrick's stdlib
  default of `0.0.0.0` would expose unrendered drafts and
  future-dated content to anyone on the LAN.

**Quality and shipping**

- `bin/audit`: links + SEO + a11y + privacy + dependency CVEs +
  content quality in one markdown report. `--strict` exits
  non-zero on any error-severity finding.
- `bin/deploy` for Cloudflare and Netlify.
- GitHub Actions workflow templates for Cloudflare Pages, GitHub
  Pages, and Render (all SHA-pinned, Dependabot-managed).
- Test suite: 680+ runs, 8000+ assertions, ~30 second wall-clock.
- Memo registry on `Site` — adding a new cached accessor doesn't
  require touching the rebuild-reset code path.
- Pre-launch hardening pass: security, output-correctness, and DX
  fixes from a full code review, each with regression tests.
- Gem packaging: the site skeleton's dotfiles (`.gitignore`,
  `vendor/*/.gitkeep`) ship in the gem, `abqari new` defaults to the
  released RubyGems engine source, and Heroicons 2.2.0 is vendored
  (with license) so the `heroicon` helper works from a gem install.
- The gemspec reads `VERSION` from a dependency-free
  `lib/abqari/version.rb` rather than loading the engine. Loading it
  pulled in every runtime gem, which broke `bundle install` for any
  git or path source (Bundler evaluates the gemspec before installing
  dependencies).
- `abqari new` writes a `.ruby-version` pinned to the scaffolding
  Ruby, so a scaffolded site doesn't silently build on whatever
  version its deploy host defaults to.
- commonmarker moved to `~> 2.4`. Its precompiled binaries are
  per-Ruby-ABI and 1.1.x stops at Ruby 3.3, so installing under 3.4
  fell back to a source build needing a Rust toolchain. Two rendering
  details are pinned explicitly as a result: `hardbreaks: false`
  (2.x defaults it to true, which turns every hard-wrapped source
  line into a `<br />`), and the TOC partial now reads commonmarker
  2.x's `id`-on-heading anchor markup.
- `word_count` strips HTML before counting. Callers pass rendered
  content, so JSON-LD `wordCount` had been counting tag attributes as
  words.
- `slugify` folds diacritics instead of deleting them: "Café" now
  slugs to `cafe` rather than `caf`, and "Mabrūk" to `mabruk` rather
  than `mabr-k`. It builds public taxonomy URLs (`/tags/:slug/`), so a
  transliterated or accented tag previously got a mangled URL.
  Stroked and ligature letters Unicode doesn't decompose (ø, ß, æ, þ,
  …) fold via an explicit table. Non-Latin scripts still slug to "",
  which `Page::Path` reports as an actionable error. Path-derived
  strings tagged ASCII-8BIT and outright invalid byte sequences are
  now handled rather than raising mid-build.

  Upgrade note: this changes URLs only for taxonomy terms or slugs
  that actually contain such characters. Pure-ASCII sites are
  byte-identical. If you have an affected tag, add `redirect_from:`
  for the old path.
- Theme handling hardened and opened up:
  - `theme:` is validated at the start of every build — a typo aborts
    with one clear message listing the available themes (previously N
    opaque per-page failures), and traversal-shaped names
    (`theme: ../x`) are rejected outright.
  - `abqari theme eject <name> [--as newname]` copies an engine
    theme's stylesheet into the site's `themes/`, where it shadows the
    gem's copy. `abqari new --theme custom` now copies the starter in
    automatically, and `--theme none` scaffolds an editable
    `app/assets/css/app.css` (a `--theme none` site previously failed
    its first build).
  - Site-local `themes/<name>/public/` now MERGES with the engine
    theme's public tree per-file instead of replacing it wholesale.
  - `theme: bootstrap` no longer fingerprints dead copies of the
    vendored dist (~700 KB) into `_site/assets/`.
  - The `minimal` default moved to `SiteConfig::DEFAULTS`, fixing
    stale CSS hot-reload on sites with no `theme:` key; the skeleton
    ships `themes/.gitkeep` so the watcher covers theme work from
    first serve.
  - New `docs/theming.md`: the theming guide and full token reference,
    drift-tested against `_common.css`.
- Ruby 4.0 supported and now the development Ruby (`.ruby-version`
  4.0.2); CI tests 3.3 / 3.4 / 4.0. The gemspec floor stays `>= 3.3`.
  Full suite green on 4.0 with the same locked dependencies —
  commonmarker ≥ 2.4 ships precompiled 4.0 binaries, which is what
  the `~> 2.4` floor bought.

[1.1.0]: https://github.com/grantrayner/abqari/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/grantrayner/abqari/releases/tag/v1.0.0

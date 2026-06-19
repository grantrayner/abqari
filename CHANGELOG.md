# Changelog

All notable changes to Abqari will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] — 2026-06-19

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

- Pretty URLs, content-hashed asset fingerprinting, HTML
  minification.
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
- Test suite: 598 runs, 3782 assertions, ~20 second wall-clock.
- Memo registry on `Site` — adding a new cached accessor doesn't
  require touching the rebuild-reset code path.

[1.0.0]: https://github.com/grantrayner/abqari/releases/tag/v1.0.0

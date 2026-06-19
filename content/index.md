---
title: Hello from Abqari
published: true
description: A minimal Ruby static site generator built around four use cases — long-form writing, photo galleries, publications, and workshops.
layout: home
nav:
  order: 1
  label: Home
---

This is the Abqari project site, rendered from `content/index.md`
via the `home` layout and written to disk as plain HTML. Every
section below is a real working example of the corresponding
feature, and the configurable home modules at the foot of the
page pull live entries from the sample collections.

Distributed as a RubyGem — install with `gem install abqari`
and scaffold a new site with `abqari new mysite`. The source is
open on [GitHub](https://github.com/grantrayner/abqari) and
[every guide on this site](/guides/) is the same documentation
that ships with the gem.

## Four pillars

**Writing.** The [guides](/guides/) listing is the prose-blog example
— this site uses it as the engine-documentation feed. Posts ship with
dated entries, tags, RSS feed, JSON-LD `Article` schema, drafts and
scheduling, paginated index when the post count grows past
`pagination.per_page`. The `slug:` knob in `config/site.yml`
controls the URL prefix (this site uses `guides`; defaults to
`posts`; pick whatever fits) — the layout and source-dir stay the
same. A companion [cookbook](/cookbook/) collection is a second
posts-style listing for shorter, recipe-style entries.

**Photos and galleries.** [Photos](/photos/) is a separate collection
(`content/photos/`) of image-centric posts. Auto-generated `/country/<name>/`
and `/series/<name>/` pages group photos by location and series — driven
by single-value front matter (`country:`, `series:`), no manual index
maintenance.

**Publications.** [Publications](/publications/) is the catalog
collection for books, essays, atlases — anything with a cover and a
price. Manually-maintained out of the box; configure `folio:` in
`config/site.yml` to auto-fill from a [Folio](https://www.foliobooks.app)
storefront. Either source (or both) populates the same collection. Set
`publications.slug: books` if you'd rather the URL prefix be `/books/`.
Bundles and series — collections of publications — render with the
same publication-card pattern as the index, work with Folio
auto-generation or pure-frontmatter manual override, and support
per-page `buy_url` for sites without a storefront.

**Workshops.** [Workshops](/workshops/) is the collection for training
offerings, consulting workshops, courses — services rather than
content. Each workshop carries structured metadata (`date_from`,
`date_to`, `duration`, `location`, `format`, `instructors`, `price`,
`registration_url`) rendered as a `<dl>` block above the body
markdown. Set `collections.workshops.enabled: false` if you don't
run workshops.

## What ships

**Authoring**
- Markdown (CommonMark + GFM) with YAML front matter
- Four default collections: `posts`, `photos`, `publications`,
  `workshops`. Add your own under `collections:` in `config/site.yml`
- Bundle-style collections (`content/<name>/<slug>/index.md` plus
  colocated assets) for `posts`, `publications`, `workshops`; flat
  single-file pages where appropriate
- Drafts (`published: false`), future-dated scheduling, custom taxonomies
  with scalar (`country: Syria`) or list (`tags: [a, b]`) front matter
- Slug aliasing: rename a built-in collection's URL prefix without
  forking the layout (e.g. `posts.slug: stories` puts posts at `/stories/`)
- Generator: `bin/new`, `bin/new post "Title"`, `bin/new page "Title"`
- Importers: `bin/import substack|ghost|jekyll <source>` pulls
  content from another platform's export into the site's
  collections — downloads images into bundles, writes
  `redirect_from:` for inbound link preservation, idempotent
  re-runs

**Templating**
- ERB layouts and partials — real Ruby, no sandboxed templating
- Standard helper library: `truncate`, `pluralize`, `local_time`
  (defaults to "1 January 2026"), `time_ago`, `time_until`, `excerpt`,
  `reading_time`, `slugify`, `asset_path`, `picture_tag`, `icon`,
  `taxonomy_url`, `publication_card_data`, `buy_button`, `cart_button`
- Three-layer cascade for nav and footer (data file → frontmatter → fallback)
- Light/dark theme toggle (opt out with `theme_toggle: false`) with
  hash-pinned CSP, no FOUC
- Spam-resistant contact button + image gallery + carousel partials
- Newsletter subscribe partial — provider-agnostic (Cogent Notes,
  Mailchimp, Buttondown, ConvertKit, TinyLetter, anything that
  accepts an HTML form POST)
- Shared `_publication_card` partial — one source of truth for the
  publication-as-card markup used by the publications index, bundle
  show pages, and series show pages
- Configurable home modules pulling from each collection — toggle
  per-module in `home:` with simple `true`/`false`, or pass a hash
  for field-level switches (`show_excerpt`, `show_price`, `show_tags`,
  `show_dates`, …) so each card surfaces exactly the fields you want

**Styling**
- Mobile-first responsive CSS with `clamp()` fluid type, safe-area
  insets, `100dvh`, `@media (hover: hover)` gates on transform effects
- Five hand-tuned themes — `minimal`, `magazine`, `notebook`, `sand`,
  `bootstrap` (5.3.8 vendored) — plus `custom` as a starter template
  and `none` to bring your own
- Themes are mostly tokens — palette, fonts, density (`--font-size-body`,
  `--line-height-body`) — driven by CSS variables, not rule overrides
- Decorative SVG title-card covers (`cover: svg` or `cover: photo_or_svg`)
  for posts and workshops without an `image:` — slug-hashed gradient
  with the page title word-wrapped over it, no per-page artwork required
- Bootstrap-style utility classes: `.lede`, `.small`, `.muted`,
  `.text-center` / `.text-end`, `.shadow-sm` / `.shadow` / `.shadow-lg`,
  `.rounded-*`
- Site-local override slot at `app/assets/css/site.css` — loads after
  the theme, ideal for site-specific brand details

**Build pipeline**
- Pretty URLs, content-hashed asset fingerprinting, HTML minification
- Self-hosted Google Fonts (`bin/fetch-fonts`)
- PWA manifest + favicons (`bin/icons` generates from a master PNG)
- Inline SVG icons; ships GitHub, RSS, mail, X, Mastodon, Bluesky,
  LinkedIn, sun, moon
- Image pipeline: responsive `<picture>`, WebP/AVIF, CLS-safe dimensions
- Static search via Pagefind, no third-party server
- D3-powered tag and topic visualizations (off by default)
- Pagination, syntax highlighting (Rouge), single-locale support

**Discovery and SEO**
- Sitemap with `<lastmod>` + image extension, RSS, JSON Feed
- Open Graph + Twitter card meta, JSON-LD `Article` schema
- Per-environment `robots.txt`, `_redirects` from frontmatter, `security.txt`
- Plausible analytics: one config line, automatic CSP extension

**Federation and audience** *(all off by default; opt in per feature)*
- **Microformats2 markup** (`h-entry`, `h-card`, `p-name`,
  `dt-published`, `e-content`, `p-category`, `u-url`, `h-feed`,
  `p-summary`) baked into post, post-list, and about layouts.
  Invisible class hooks — no visual change, full machine-readable
  identity for IndieWeb tooling.
- **Webmention receive** via [webmention.io](https://webmention.io) —
  a "Replies & mentions" section renders below each post with
  facepile-style likes/reposts/bookmarks and full-card replies. No
  JavaScript, no comment backend, no moderation queue. Cached
  build-to-build with ETag.
- **Webmention send** (opt-in) — POSTs notifications to external
  URLs your posts link to. Tracked in `vendor/webmentions/sent.yml`
  so re-builds don't double-send.
- **Bridgy Fed link tags** (opt-in) — `<link rel="me">` +
  `application/activity+json` advertisement so Mastodon users can
  search `@<your-domain>` and follow the site directly via
  ActivityPub. Bridgy Fed handles the federation hop on its
  infrastructure; the site stays static.
- **POSSE auto-syndication** — on each build, post a short summary +
  canonical URL of every new post to Mastodon and/or Bluesky. The
  originating post on your site stays the source of truth; replies
  on those networks come back as webmentions and consolidate under
  the canonical post. Per-post opt-out via `syndicate: false`;
  custom snippet via `syndication_text:`. Idempotent — every
  successful crosspost logged to `vendor/syndication/sent.yml`.

**Quality and shipping**
- `bin/audit` — links + SEO + a11y + privacy + dependency CVEs in a
  markdown report
- `bin/deploy` for Cloudflare and Netlify
- GitHub Actions workflow for CI/CD
- `bin/upgrade` to pull engine updates from your upstream fork

**Performance**
- Parallel page rendering, compiled-template caching, mtime-aware copying
- Incremental rebuilds in dev (only changed pages re-render)
- Listen-based file watcher, partial CSS reload

See the [README](https://github.com/grantrayner/abqari#readme) for the full surface.

*This page lives in `content/index.md` in the source repository.
Forks: replace the body with your own welcome copy, or delete the
markdown entirely and let the home modules introduce the site on
their own.*

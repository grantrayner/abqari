# Changelog

All notable changes to Abqari will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.4.0] — 2026-05-21

### Added

**IndieWeb foundation (Milestone A).** Three independently-useful
pieces of native IndieWeb support shipped together:

1. **Microformats2 markup** baked into post, post-list, and about
   layouts. Class hooks only — `h-entry`, `p-name`, `dt-published`,
   `e-content`, `p-category`, `u-url`, `p-summary`, `h-feed`,
   `h-card`. Invisible to humans, structured for IndieWeb parsers
   and feed readers that grok microformats.
2. **Webmention receive** via [webmention.io](https://webmention.io).
   `Indieweb::Fetcher` polls the JF2 API at build time with ETag
   caching (`vendor/webmentions/mentions.json`). A new
   `_webmentions` partial renders a "Replies & mentions" section
   below each post — conversational mentions get full author + body
   cards; likes / reposts / bookmarks render facepile-style. No
   JavaScript, no comment backend, no moderation queue. Spam is
   structurally rare because replies have to be published on real
   websites first.
3. **Webmention send** (opt-in via `send_webmentions: true`).
   `Indieweb::Sender` POSTs notifications to external URLs that
   recent posts link to. Endpoint discovery follows the spec
   (HEAD `Link:` header → GET `<link rel="webmention">`). Sent
   targets are tracked in `vendor/webmentions/sent.yml` so re-builds
   don't double-send. Only runs for posts within the configurable
   `send_window_days` (default 30).
4. **Bridgy Fed link tags** (opt-in via `bridgy_fed: true`). Head
   emits `rel="me"` and `rel="alternate" type="application/activity+json"`
   pointing at [fed.brid.gy](https://fed.brid.gy), which speaks
   ActivityPub on the site's behalf. Mastodon users can then search
   `@<your-domain>` and follow the site directly; replies on
   Mastodon flow back as webmentions via Bridgy.

Config under `indieweb:` in `config/site.yml`:

```yaml
indieweb:
  enabled: true
  domain: example.com
  webmention_io_token: "..."
  bridgy_fed: false
  send_webmentions: false
  send_window_days: 30
```

Implementation: `lib/abqari/indieweb.rb`, `app/views/partials/_webmentions.html.erb`,
microformats class additions across `app/views/layouts/{post,about}.html.erb`
and `app/views/partials/_post_list.html.erb`, default styling in
`_common.css`. See README → "IndieWeb & federation" for the full guide.

**POSSE — Publish on Own Site, Syndicate Elsewhere (Milestone B).**
On each build, syndicate recent posts to Mastodon and/or Bluesky. The
canonical post on your site stays the source of truth; readers on
each network discover new work in their feed; replies on those
networks come back as webmentions (via Bridgy Fed) and consolidate
under the post.

- **Per-network adapters** — `Syndication::Networks::Mastodon` (uses
  the standard Mastodon API; `write:statuses` OAuth token from
  Preferences → Development) and `Syndication::Networks::Bluesky`
  (AT Protocol `createSession` + `createRecord`; app password from
  Settings → App Passwords — NOT the account password).
- **Idempotent dispatcher** — `vendor/syndication/sent.yml` records
  every successful post keyed by `<network>|<canonical_url>`. Sent
  entries are skipped on subsequent builds; failures are recorded
  for visibility but retried (transient API outages shouldn't
  permanently skip a post).
- **Per-post overrides** — `syndicate: false` in frontmatter excludes
  a post from POSSE; `syndication_text: "..."` supplies a custom
  snippet that overrides the auto-formatter.
- **Per-network formatting** — `Syndication::Formatter` builds
  `<title> — <description> <url>`, truncating the description to fit
  each network's character cap (Mastodon 500, Bluesky 300). Bluesky's
  link facets use UTF-8 byte offsets (the adapter handles this
  correctly for multi-byte titles).
- **Window filter** — `window_days` (default 14) excludes historical
  posts; they predate syndication setup and replaying would look
  like spam.

Config under `syndication:` in `config/site.yml`:

```yaml
syndication:
  enabled: true
  window_days: 14
  mastodon:
    instance: https://mastodon.social
    access_token: "..."
    visibility: public
  bluesky:
    handle: yourname.bsky.social
    app_password: "..."
```

Implementation: `lib/abqari/syndication.rb`. See README → "POSSE" for
the full guide including the reply-collection flow that connects
IndieWeb + POSSE end-to-end.

**Content importers (`bin/import`).** New command pulls posts from
another platform's export into the site's `content/<collection>/`
tree. Ships with three importers — Substack (`.zip` or unzipped
directory), Ghost (JSON export), Jekyll (site source directory).
Each imported post lands as a regular Abqari bundle so the result
is indistinguishable from posts authored fresh.

```bash
bin/import substack ~/Downloads/substack-export.zip
bin/import ghost    ~/Downloads/export.json
bin/import jekyll   ~/old-site/
```

Behaviour:

- **HTML → Markdown** via `reverse_markdown` (GFM extensions,
  unknown tags pass through verbatim for manual cleanup).
- **Platform chrome stripped** before conversion. Each importer
  ships a default selector list (Substack subscription widgets,
  Ghost bookmark cards, etc.); extend with `--strip SEL,SEL`.
- **Remote images downloaded** into each post's bundle directory
  by default so the build's image pipeline can re-encode them to
  AVIF + WebP with responsive variants. `--keep-remote` opts out.
- **`redirect_from:` written** so inbound links to the source-
  platform URLs keep working (`/p/<slug>/` for Substack,
  `/<slug>/` for Ghost).
- **Idempotent** — skip files that already exist by default;
  `--force` overwrites.
- **Slug collisions** resolved by numeric suffix (`foo`, `foo-2`,
  `foo-3`).
- **`_import_report.md`** written at the site root (gitignored)
  summarising every post with status + warnings.

Flags: `--into COLLECTION`, `--keep-remote`, `--flat`, `--dry-run`,
`--force`, `--canonical`, `--strip SEL,SEL`. Adds `reverse_markdown
~> 2.1` as a runtime dep (lazy-loaded — normal builds never pull it
into memory). See README → "Importing content" for the full guide.
Implementation under `lib/abqari/importers/`.

**Decorative auto-generated cover SVGs.** New `cover:` enum on the
posts and workshops collections gives text-first authors a polished
cover slot without sourcing imagery. Four modes:

| Mode | Behaviour |
|---|---|
| `photo` (default) | Renders `image:` if set, basic flat-tint placeholder otherwise. The historical behaviour. |
| `photo_or_svg` | Renders `image:` if set, otherwise a decorative title-card SVG. |
| `svg` | Always renders the decorative SVG (ignores `image:`). Uniform tile look across a listing. |
| `none` | No cover slot at all. Text-only cards. |

Lives in config under `<collection>.index.cover` (listing card) and
`<collection>.show.cover` (detail-page hero) — independent of each
other. Frontmatter `cover:` (boolean `false` or one of the enum
strings) on a single page overrides the collection default.

The SVG generator is deterministic per slug: same post always gets
the same gradient + layout across builds. Eight muted two-tone
palettes give adjacent cards distinct tones; the page title is
word-wrapped to 1–3 lines via a balanced-partition search that
minimises the longest wrapped line, with font size auto-scaled
to fit. Two clusters of three faint decorative squares at the
corners (top-left + bottom-right) echo the hand-authored hero
pattern. Inline SVG (no extra HTTP request), `aria-hidden`, scales
gracefully via `viewBox`.

See `lib/abqari/render_context/cover_helpers.rb` for the generator
and the mode-resolution chain.

### Changed

**`show_image` → `cover` enum (hard cutover).** The `show_image: true/false`
toggle on `posts.index`, `posts.show`, `workshops.index`, and
`workshops.show` is replaced by the new `cover:` enum above. To
migrate: replace `show_image: true` with `cover: photo` (current
behaviour) or pick another mode. `show_image: false` becomes
`cover: none`.

**Per-collection config: show-view knobs grouped under `show:`.** The
config shape for per-collection show-page features (TOC, "Up next",
related grid) moved one level deeper, so every knob that affects
the show page now lives under `show:` — mirroring `index:` for the
listing page. Before:

```yaml
collections:
  posts:
    show:
      show_image: true
    toc:
      enabled: true
    next:
      enabled: true
    related:
      enabled: true
```

After:

```yaml
collections:
  posts:
    show:
      show_image: true
      toc:
        enabled: true
      next:
        enabled: true
      related:
        enabled: true
```

The rule is now uniform: "knobs for the listing page go under
`index:`; knobs for the show page go under `show:`." Top-level
keys (`archive`, `pagination`, `feeds`) stay where they are
because they're separate pages or artifacts, not part of either
the index or show view.

Hard cutover. Sites with custom config must move `toc:`, `next:`,
`related:` under `show:` in `config/site.yml` for every collection.
Read-paths in the engine (`Site#related`, `Site#next_in_collection`,
`Renderer#generate_related_pages`, the `_toc` / `_related_items`
partials) updated accordingly.

## [0.3.1] — 2026-05-16

### Changed

**Publisher-agnostic naming.** Renamed the Folio-named pieces of the
publication abstraction so the publisher integration (currently Folio)
is one of several possible sources, not the centre of gravity:

| Before | After |
|---|---|
| `Abqari::FolioPages` | `Abqari::PublisherPages` |
| `Abqari::FolioShowPage` | `Abqari::PublisherShowPage` |
| `Abqari::FolioIndexPage` | `Abqari::PublisherIndexPage` |
| `Abqari::RenderContext::FolioHelpers` | `Abqari::RenderContext::PublicationHelpers` |
| `folio_book(slug)` | `publication_for(slug)` |
| `folio_bundle(slug)` | `bundle_for(slug)` |
| `folio_series(slug)` | `series_for(slug)` |
| `folio_buy_button(slug, kind:)` | `buy_button(subject)` |
| `folio_cart_button(slug, kind:)` | `cart_button(subject)` |
| `folio_data` | (removed — use `page.frontmatter` directly) |
| `lib/abqari/folio_pages.rb` | `lib/abqari/publisher_pages.rb` |
| `lib/abqari/render_context/folio_helpers.rb` | `lib/abqari/render_context/publication_helpers.rb` |
| `app/views/partials/_folio_book_grid.html.erb` | `app/views/partials/_book_grid.html.erb` |
| `app/views/partials/_folio_bundle_cta.html.erb` | `app/views/partials/_bundle_cta.html.erb` |

Hard cutover — the 0.3.0 deprecation aliases for the `folio_*` helpers
are gone. Layouts that still call them must switch to the new names.

`PublisherShowPage#frontmatter` returns the publisher payload directly
— the engine-only `folio_kind` / `folio_slug` bookkeeping keys are
dropped. Templates that referenced them must use `page.kind` /
`page.slug` instead.

- **`bundles_index.html.erb` / `book_series_index.html.erb`** — now
  iterate `site.collection('bundles')` / `site.collection('series')`
  instead of `site.data['folio_*']`, so they show manual content too.
  A site that creates `content/bundles/index.md` (or
  `content/series/index.md`) gets a working index page without any
  publisher integration.

### Internal

- `Renderer#generate_folio_pages` → `Renderer#generate_publisher_pages`.
- `RenderContext::FOLIO_KIND_TO_COLLECTION` → `KIND_TO_COLLECTION`.
- Doc-comments and README updated to use neutral "externally-sourced /
  publisher" language where the code path is publisher-agnostic. The
  `Folio` class itself, the `folio:` config block, the `vendor/folio/`
  cache, and `Site#folio` / `#folio_enabled?` are unchanged — they
  remain the names of the specific publisher implementation.

## [0.3.0] — 2026-05-16

### Breaking

**Frontmatter for publications / bundles / series is now aligned with
the Folio v1 API contract.** Field names changed across all three
collections to match Folio's serializer output, so manual content
and Folio-fetched data speak the same vocabulary throughout the
engine. See `docs/publications.md` for the full schema.

Migration required for existing content (hard cutover — no deprecation
shim). Posts, photos, and workshops are unaffected.

| 0.2.x frontmatter | 0.3.0 frontmatter |
|---|---|
| `description:` on publications | `excerpt:` (`description` still used on posts / photos / workshops / bundles / series) |
| `cover:` / `cover_image:` | `cover_url:` |
| `buy_url:` | `buy_now_url:` |
| `series: foo` + `series_position: 1` | `in_series: { slug: foo, name: …, position: 1 }` |
| `title:` on bundles / series | `name:` |
| `price: "$16.00"` (String) | `price: { cents: 1600, currency: USD, formatted: "$16.00" }` (still accepts shorthand and expands) |

### Added

- **`docs/publications.md`** — canonical reference for the publication
  / bundle / series schema. Every field name documented with type,
  source (frontmatter or Folio), and intent.
- **`Abqari::PublicationNormaliser`** — runs at frontmatter-parse time
  on publication, bundle, and series frontmatter. Expands the
  `price: "$16.00"` String shorthand into the canonical Hash form
  (`{ cents, currency, formatted }`) so call sites read one shape.
  Currency inferred from the symbol; supports `$`, `A$`, `C$`,
  `NZ$`, `S$`, `£`, `€`, `¥`.
- **`FolioShowPage#collection`** — returns `'publications'` /
  `'bundles'` / `'series'`, so Folio-sourced pages join their
  collection automatically. `Site#collection(name)` widened to
  return BOTH manual `Page` objects AND `FolioShowPage` entries;
  manual pages win on slug collision.
- **`buy_button(subject, label:)` + `cart_button(subject, label:)`** —
  publisher-agnostic helpers in `RenderContext`. Render whenever the
  canonical `buy_now_url` / `add_to_cart_url` field is set, whether
  from native frontmatter or any external integration. `subject`
  accepts a frontmatter Hash, a Page-like object, or a slug string.
- **`Page#title` / `Page#description` per-collection vocabulary.**
  Bundles + series use `name:` (Folio convention). Publications
  prefer `tagline:` then `excerpt:` for the short summary. Posts /
  photos / workshops continue to use `title:` / `description:`.

### Changed

- **`_book_related`** rewritten — reads `site.collection('publications')`
  filtered by `in_series.slug`. Works for native sites with manual
  publications AND for Folio-configured sites, no source branching.
- **`publication.html.erb`, `bundle.html.erb`, `series.html.erb`,
  `publications_index.html.erb`, `publications_archive.html.erb`,
  `_publication_header`, `_publication_card`, `_book_jsonld`,
  `_folio_book_grid`, `_folio_bundle_cta`** — all read canonical
  field names from `page.frontmatter` directly. The old
  `folio['x'] || fm['x']` chains are gone; templates speak one
  language.
- **`publication_card_data(slug)`** — simplified. Now a single
  `site.collection('publications').find` lookup instead of the
  legacy two-source merge.
- **`folio_buy_button` / `folio_cart_button`** — kept as deprecated
  aliases over the new generic helpers. Existing layouts continue
  to work; new layouts should use `buy_button` / `cart_button`.
- **Bundle / series show-view "buy the whole set" buttons** — render
  whenever `buy_now_url:` is set on the bundle/series frontmatter.
  Native authors can point at Payhip, Gumroad, or any external
  storefront; Folio bundle integration supplies the same field.

### Migration

For sites running 0.2.x:

1. Rename frontmatter keys per the table above. Mechanical search-
   and-replace handles most cases:
   - `^description:` → `^excerpt:` (in `content/publications/**/*.md` only)
   - `^cover:` → `^cover_url:` (in `content/publications/**/*.md` only)
   - `^buy_url:` → `^buy_now_url:` (publications + bundles + series)
   - `^title:` → `^name:` (in `content/bundles/**/*.md` and
     `content/series/**/*.md`)
   - Replace `series: foo\nseries_position: N` with the `in_series`
     Hash form.
2. The price string shorthand (`price: "$16.00"`) still works — no
   change needed for that field.
3. Wipe `vendor/folio/` and re-run `bin/build` so the Folio cache
   re-fetches under the new processing path.
4. Any custom layouts that read `folio['cover_url'] || fm['cover']`-
   style chains can be simplified to read `page.frontmatter['cover_url']`
   directly. The old chains keep working but become redundant.

## [0.2.0] — 2026-05-16

### Security

- **`script_safe_json` helper** for every JSON-LD partial. Plain
  `JSON.generate` doesn't escape `<`, `>`, `&`, or U+2028/9, so a
  hostile string in a Folio response could break out of the host
  `<script>` tag. Escapes these characters to their `\uXXXX` JSON
  forms (still valid JSON, round-trips through `JSON.parse`). The
  ERB escape audit now FORBIDS `JSON.generate` / `to_json` inside
  `<%==` blocks.
- **Reject protocol-relative URLs** in `Helpers#sanitized_url`.
  `//evil.com/x` is a cross-origin redirect disguised as a same-
  origin path; previously slipped past the `start_with?('/')` short-
  circuit. Now returns `nil`.
- **WEBrick dev server binds to `127.0.0.1`** by default. Previously
  bound to `0.0.0.0`, exposing unrendered drafts and future-dated
  content to anyone on the same LAN. Override with `ABQARI_BIND=0.0.0.0`
  for explicit LAN preview.
- **`PathSafe.join_under` in Folio + Redirects.** Bounded-trust Folio
  slugs and frontmatter `redirect_from:` paths now go through the
  same path-safety guard as `permalink:` — a compromised Folio
  response with `"slug": "../../etc"` can no longer write outside
  `_site/`.
- **Uniform YAML `permitted_classes: [Date, Time]`** via the new
  `Abqari::YAML_PERMITTED_CLASSES` constant. Was inconsistent across
  the six `safe_load` call sites; now centralised and enforced.
- **XML escape in sitemap + feed.** Every interpolated URL flows
  through `CGI.escapeHTML` — one stray `&` no longer breaks the
  emitted feed for every subscriber.
- **CSP hardened** with `object-src 'none'` and `form-action 'self'`.
  Newsletter `action:` and `script:` origins are added narrowly via
  `apply_newsletter` so external providers (Mailchimp / Buttondown /
  ConvertKit) still work.
- **`SiteConfig::KNOWN_KEYS` drift test.** Bi-directional: fails if
  any source file references a top-level config key missing from
  `KNOWN_KEYS`, OR if `KNOWN_KEYS` lists keys no source actually
  reads.
- **`RenderContext` ivar audit** + `@_yielded_content` rename.
  Internal-state ivars use the `@_` prefix; the audit asserts only
  `@page` and `@site` are template-public.
- **Server watcher supervision.** Dev-server crashes inside the file
  watcher used to silently kill hot-reload; now restart up to 5 ×
  per minute with debug-level backtraces, give up loudly past that
  threshold.
- **Narrower rescues** in `Folio#fetch_endpoint` (specific exception
  classes instead of bare `StandardError`) with debug-level
  backtraces.
- **`parent_layout_of` surfaces YAML errors** with the offending
  layout path in the message instead of silently misrouting the
  chain.

### Added

- **Image pipeline rewrite.** Default `optimise: true`. Per-format
  quality (AVIF 50 / WebP 80 / JPEG 85 — perceptual-equivalence
  points). Native libvips backend via `ruby-vips` (now a hard
  dep — `brew install vips` or `apt install libvips42` covers the
  C library). Bundle images (`content/posts/<slug>/hero.jpg`,
  flat-collection assets) now go through the same pipeline as
  `app/assets/images/` — `<img src="hero.jpg">` in markdown is
  rewritten to a full `<picture>` block with AVIF + WebP +
  optimised JPEG fallback across multiple widths. Skip-if-source-
  smaller prevents upscaled-blurrier-and-larger variants. Metadata
  (EXIF / GPS / camera serial) stripped by default;
  `preserve_metadata: true` opts back in.
- **Performance audit rule.** `bin/audit` flags pages with heavy
  image payloads (warn at 500 KB single / 1 MB page total; error at
  1 MB single / 3 MB page total). New "Performance" category in
  audit reports.
- **TZ save/restore in `Site#build`.** `apply_timezone!` was
  process-wide and never restored; now scoped to the build call
  via `ensure`. Host applications embedding the gem get their TZ
  back at the value they had before build.
- **`collection_url_index(name)`** — memoised O(1) url-to-position
  hash. `Site#next_in_collection` and `Site#related` used O(N)
  `pages.index { ... }` scans inside the render loop; now O(1) per
  page, O(N) across the build.
- **Mutex-protected renderer caches.** `@deps_mutex` synchronises
  `shared_deps_mtime` and `layout_deps_mtime` so parallel render
  threads don't race on the first miss.
- **Per-page `description` memoisation** + scoped first-paragraph
  caching. Listing partials no longer trigger cold-cache body
  re-reads after `forget_body!`.
- **Set-based `tag_cooccurrence_data`** — O(tags² × posts_per_tag)
  Array scans replaced with single Set intersection; upper-triangle
  only.
- **Active-theme scoping in shared-deps mtime.** Only walks the
  configured `theme:`, not every theme bundled with the gem.

### Changed

- **`Abqari::FRONTMATTER_RE`** consolidates the three duplicate
  regex constants (Page, RenderContext, Renderer) into one
  canonical definition.
- **`Helpers#truncate` clamps** the slice width to 0 when `omission`
  is longer than `length`. Previously returned the wrong tail slice
  via Ruby's negative-second-arg `String#[]` behaviour.
- **`Site#singularize_slug`** treats `news`, `series`, `lens`,
  `species`, `means`, `physics`, `analytics` as invariant.
- **`inject_livereload`** matches `</body>` case-insensitively;
  preserves the source's casing in the substitution.
- **`Page#raw_body`** logs warnings instead of silently returning
  nil on rescue.
- **`audit/dependencies.rb command_available?`** uses a PATH walk
  instead of `system("command -v ...")` (no shell interpolation
  footgun).

## [0.1.x]

Final 0.1.x release prior to RubyGems publish. Combines what was
previously the `[Unreleased]` accumulator (workshops collection,
newsletter partial, theme system rework, path-source / gem-source
consumption, etc.) — these features all landed before the 0.2.0
security + image pipeline overhaul and are listed under 0.1.x for
historical reference.

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

[Unreleased]: https://github.com/grantrayner/abqari/compare/v0.3.0...HEAD
[0.3.0]: https://github.com/grantrayner/abqari/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/grantrayner/abqari/compare/v0.1.0...v0.2.0
[0.1.x]: https://github.com/grantrayner/abqari/releases/tag/v0.1.0
[0.1.0]: https://github.com/grantrayner/abqari/releases/tag/v0.1.0

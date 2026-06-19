# Abqari architecture

This document is a map of the engine for new contributors. It traces
the build pipeline end-to-end, names the major collaborators, and
points to where each responsibility lives in the code.

For the threat model and what the engine deliberately doesn't defend
against, see `docs/security.md` first — this doc assumes that
context.

---

## 1. Two roots

Abqari is consumed two ways:

```
+-----------------------+        +-------------------------+
|  Engine repo (gem)    |        |  Consuming site repo    |
|                       |        |                         |
|  lib/, app/views/,    |  ⇐⇒  |  config/site.yml,        |
|  app/icons/,          |        |  content/, data/,       |
|  app/assets/,         |        |  vendor/folio/,         |
|  themes/<built-ins>/, |        |  public/, _site/        |
|  vendor/heroicons/,   |        |  themes/<custom>/       |
|  vendor/d3/           |        |  (overrides + extras)   |
+-----------------------+        +-------------------------+
        engine_root                       site_root
```

- **`engine_root`** is the gem's location. Structural assets that
  every consumer shares: layouts, partials, icons, the structural
  `_common.css`, built-in themes, vendored third-party assets
  (heroicons, d3).
- **`site_root`** is the consuming site's location. Site-specific
  content, config, data files, the Folio HTTP cache, the build
  output (`_site/`), audit reports.

When the engine is run against its own fixture site (the repo itself),
the two roots coincide. When consumed as a gem, they're two different
directories.

**`Site#find_in_paths(rel)`** resolves `rel` to a file path with
"site-first, engine-fallback" semantics. Sites override an
engine-shipped layout / partial / icon / theme file just by dropping
their own copy in the matching path.

---

## 2. The Site façade

`Abqari::Site` is the only class with a stable public API. It exposes
all the query helpers used from `RenderContext`, partials, and `Audit`:

```
Site                       — orchestration + public query API
├── @loader     (SiteLoader)      — config, pages, data loading
├── @renderer   (Renderer)        — generators, parallel render,
│                                   post-process, template cache
└── @artifacts  (ArtifactWriter)  — output reset, copying, sitemap/
                                    feed/robots/etc. emitters
```

The three collaborators are **internal**. External callers go through
`Site`. `Site#build` orchestrates the build by calling each one in
order:

1. `@artifacts.reset_output` (wipe + recreate `_site/`)
2. `@pages = @loader.load_pages`
3. `Folio.new(self).fetch` (cache-first HTTP pull from the
   currently-supported publisher integration; no-op when `folio:`
   config is missing)
4. `@renderer.generate_all` (tag pages, paginated shards, viz,
   publisher show pages via `PublisherPages`, related-index pages —
   pushed into `@generated_pages` via `site.add_generated_page(page)`)
5. `assets.process` + `images.process` (pipelines)
6. `@artifacts.copy_fonts` + `copy_d3`
7. `@renderer.render_pages` (parallel write of HTML)
8. `BundleAssets.new(self).copy` (bundle-asset destinations)
9. `@artifacts.copy_public` (static passthrough)
10. `@artifacts.write_deploy_artifacts` (sitemap, feed, robots, …)
11. `visualizations.write_data` + `Search.new(self).run`

The order matters: every step downstream of `load_pages` reads
`@pages`; everything after `render_pages` reads from `_site/`.

---

## 3. Pages

A `Page` is a single `.md` file under `content/`. The lifecycle:

```
File.read(source)
    │
    │  Page#parse           ─► @frontmatter (YAML.safe_load)
    │                          @body         (post-frontmatter text)
    ▼
Page in @site.pages
    │
    │  layouts/partials access page.frontmatter, page.title,
    │  page.description, page.url, page.content, …
    ▼
Page#write
    │
    │  RenderContext.new(self, site).render_layout(layout)
    │  → ErbiTemplate(...).result(get_binding)
    │  → site.post_process(html, page: self)
    │  → File.write(output_path, html)
    │  → forget_body!    (drops @body, @content)
    ▼
output_path under _site/
```

**Lazy `body`.** After `write`, `forget_body!` clears `@body` +
`@content`. Frontmatter stays (used everywhere). If another page
later asks for this one's description, `body` (and via it
`raw_body`) lazily re-reads from disk. OS page cache keeps re-reads
sub-millisecond.

**Path safety.** `Page#output_path` routes frontmatter `permalink:`
through `PathSafe.join_under(site.output_dir, ...)`, which raises if
the result escapes `output_dir`. The permalink string itself is
allowlisted to `[A-Za-z0-9_\-./]+` — anything else is a typo or an
attack vector.

**Generated pages.** `TaxonomyPage`, `PaginatedShard`,
`RelatedIndexPage`, `PublisherShowPage`, and Visualizations' VizPage
are synthetic pages with their own `#write` methods. They don't
inherit from `Page` — the contract is just "respond to `write` and
`url`."

---

## 4. RenderContext + Erubi

`RenderContext` is the binding ERB templates execute against. It
holds references to the current page and site, includes the
`Helpers` mixin (for `h`, `local_time`, `pluralize`, `sanitized_url`,
etc.), and exposes helpers that build HTML markup (`link_to`,
`picture_tag`, `bundle_picture_tag`, `icon`, `heroicon`,
`buy_button`).

```
Page#write
    │
    ▼
RenderContext.new(page, site)
    │
    │  render_layout('post')
    ▼
ErbiTemplate.new(File.read('layouts/post.html.erb'))
    │
    │  Erubi::Engine.new(src, escape: true, escapefunc: 'h', …)
    │  → compiled Ruby source
    ▼
eval(compiled_src, render_context.get_binding)
    │
    │  layout uses <%= page.title %>   (auto-escaped)
    │  layout uses <%== page.content %>(raw — already safe HTML)
    │  layout uses <%== render 'partials/foo' %>(raw)
    ▼
HTML string
```

**Auto-escape.** Erubi compiles `<%= expr %>` to `_buf << h(expr)`.
Auto-escaping is the default; `<%== expr %>` is the explicit raw
form for already-safe HTML (helper output, JSON-LD inside
`<script>`, pre-rendered markdown via `page.content`).

**Audit.** `test/erb_escape_audit_test.rb` walks every `.erb` under
`app/views/`, finds every `<%==`, and fails the build if any raw
interpolation isn't on the allow-list. Adding a new raw
interpolation is a reviewer-gated choice.

---

## 5. The build pipeline (graph form)

```
Site#build
│
├── ArtifactWriter#reset_output         (assert under site_root)
│
├── SiteLoader#load_pages
│   ├── Dir.glob('content/**/*.md').sort
│   ├── skip disabled collections
│   ├── skip external symlinks         (Site#external_symlink?)
│   ├── Page.new(path, site)           (parse + frontmatter)
│   └── skip drafts / future / disabled per env
│
├── Folio#fetch                         (HttpSafe — 8 MB cap, timeouts)
│   └── writes vendor/folio/*.yml
│
├── Renderer#generate_all
│   ├── generate_tag_pages              (TaxonomyPage per term)
│   ├── generate_paginated_pages        (PaginatedShard per page-2..N)
│   ├── generate_visualizations         (VizPage)
│   ├── generate_publisher_pages        (PublisherShowPage +
│   │                                    PublisherIndexPage for
│   │                                    book/bundle/series pages
│   │                                    sourced from a publisher)
│   └── generate_related_pages          (RelatedIndexPage)
│
├── assets.process + images.process     (CSS hashing, image variants)
│
├── ArtifactWriter#copy_fonts + copy_d3
│
├── Renderer#render_pages
│   ├── Thread::Queue work-stealing pool
│   └── per-page: Page#write
│       ├── render via ErbiTemplate
│       ├── post_process (bundle URLs, syntax, images, livereload, minify)
│       └── PathSafe-checked write + forget_body!
│
├── BundleAssets#copy                   (PathSafe-checked dests)
│
├── ArtifactWriter#copy_public
│
├── ArtifactWriter#write_deploy_artifacts
│   ├── Sitemap, Feed, Robots, HeadersFile
│   ├── SecurityTxt, Redirects, Manifest
│   ├── LlmsTxt, OgImageGenerator
│   └── SyntaxHighlighter::Stylesheet
│
├── visualizations.write_data           (D3 data files)
└── Search.new(site).run                (Pagefind index)
```

---

## 6. Safety primitives

Three small modules sit under every I/O / network call:

- **`Abqari::PathSafe`** (`lib/abqari/path_safe.rb`) —
  `join_under(base, *segs)` raises if the joined path escapes `base`;
  `assert_under(base, path)` is the assertion form for already-
  computed paths. Used by `Page#output_path`, `OgImageGenerator`,
  `BundleAssets`, `ArtifactWriter#reset_output`.

- **`Abqari::HttpSafe`** (`lib/abqari/http_safe.rb`) — bounded HTTP
  GET. Streams via `read_body`, caps at `max_bytes` (default 8 MB),
  applies open/read timeouts. Returns a `Response` struct with
  case-insensitive header lookup. Used by `Folio` and `FontPipeline`.

- **`Abqari::ErbiTemplate`** (`lib/abqari/erbi_template.rb`) —
  Erubi adapter with auto-escape on and UTF-8 buffer encoding. The
  ONLY place ERB-style templates are compiled.

---

## 7. Configuration

`config/site.yml` is loaded by `SiteLoader#load_config` with optional
per-environment overrides via `environments:`. Loaded once at
`Site#initialize`, then validated by `Abqari::SiteConfig.validate!`:

- Unknown top-level keys → `Log.warn` (or raise when
  `ABQARI_STRICT_CONFIG=true`).
- `ABQARI_ENV` set but not matching any `environments.*` key →
  `Log.warn`.

Defaults are not centralised today — they're scattered across
`DEFAULT_COLLECTIONS` / `DEFAULT_TAXONOMIES` constants on `Site`,
`fetch()` calls in partials, and per-feature constants. A
consolidated `DEFAULTS = {...}` registry is on the roadmap.

---

## 8. Audit

`Abqari::Audit` is a separate orchestrator that builds the site and
walks `_site/` for issues:

```
Audit
├── Audit::Rule           — shared base (html_files, page_url, add)
├── Audit::Links          — broken internal href detection
├── Audit::SEO            — titles, descriptions, JSON-LD coverage
├── Audit::A11y           — alt text, h1, skip-link, main landmark
├── Audit::Privacy        — external resource warnings
├── Audit::Dependencies   — bundler-audit + outdated check
└── Audit::Content        — descriptions, single-use tags, whitelists
```

`bin/audit --strict` exits non-zero on any error-severity finding;
the CI workflow (`.github/workflows/ci.yml`) wires this into PR
gates alongside `bundle-audit check`.

Adding a new check category: drop a file under `audit/`, inherit
from `Rule`, add the class to `RULES`, add the category label to
`CATEGORIES`. No edits to the orchestrator body.

---

## 9. Layout chaining

Layouts can chain via frontmatter `layout: <parent>` — the inner
layout renders first, the parent wraps it via `<%== yield_content %>`.
Implementation in `RenderContext#render_layout` is recursive: parse
layout frontmatter, render body, set `@yielded_content`, recurse
into parent. Chain terminates at a layout with no parent.

Typical chain: `post.html.erb` → `application.html.erb`. The post
layout owns post-specific structure (meta line, hero, body, tags
footer); the application layout owns the page shell (`<html>`,
`<head>`, nav, footer).

---

## 10. Threading model

- Page rendering is parallel via `Renderer#render_pages` using a
  `Thread::Queue` work-stealing pool. Workers pull pages from a
  shared queue until empty.
- Concurrency-sensitive state has explicit synchronisation:
  - `Renderer`'s template cache: `@template_mutex`.
  - `ImagePipeline`'s shared state (per its own internal mutex).
  - Per-page render errors: collected via `errors_mutex`.
- `Page#body`'s lazy reload is benign-racy — concurrent miss-readers
  both re-read the same file and both assign `@body` to the same
  content. No mutex.

---

## 11. Where to add a feature

Cheat sheet for common changes:

| Feature | Likely location |
|---|---|
| New built-in collection | `Site::DEFAULT_COLLECTIONS` |
| New taxonomy | `Site::DEFAULT_TAXONOMIES` + `taxonomy_config` |
| New layout / partial helper | `RenderContext` or `Helpers` |
| New audit check | new file under `lib/abqari/audit/`, add to `RULES` |
| New deploy artifact (e.g. ads.txt) | new `lib/abqari/<artifact>.rb` class with `#write`, call from `ArtifactWriter#write_deploy_artifacts` |
| New config key | add to `SiteConfig::KNOWN_KEYS`; read via `site.config['key']` |
| New env var | add to "Configuration knobs" table in `docs/security.md` |
| New CLI flag | `bin/<command>` with `OptionParser`; flag wins over env var |
| New content importer (Substack, Ghost, etc.) | new file under `lib/abqari/importers/`, subclass `Base`, register in `Importers::REGISTRY` |
| New syndication network (Threads, X, LinkedIn, etc.) | new file under `lib/abqari/syndication.rb`'s `Networks` module, subclass `Networks::Base`, add to `Dispatcher#networks`, add a `LIMITS[name]` entry |
| New IndieWeb microformat hook | add the class attribute to the relevant layout / partial; verify against indieweb.org/h-entry or h-card; add to `test/indieweb/layouts_test.rb` |

---

## 12. Where NOT to add a feature

These boundaries are deliberate (see `docs/security.md` §3):

- **Don't accept untrusted markdown** through `Page` or
  `Commonmarker.to_html` with `unsafe: true`. The current pipeline
  assumes content is author-trusted.
- **Don't expand `<%==`** to cover untrusted data. Auto-escape via
  `<%=` is the default for a reason.
- **Don't open the `erb_in_markdown` gate by default.** Per-site
  opt-in only; per-page `erb: true` is the second layer.
- **Don't extend the plugin API to load Ruby from third-party themes
  or remote URLs.** The current contract auto-loads from
  `<site_root>/plugins/` only — same trust level as the site's own
  source. See `docs/plugins.md` for the hook list and authoring guide.
- **Don't introduce `eval`, `instance_eval`, `class_eval`** in
  library code. The current codebase has none (the plugin system
  uses `require`, not `eval`).
- **Don't bypass `PathSafe` / `HttpSafe`** for new code that joins
  user input or fetches external resources.

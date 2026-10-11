# Abqari security model

This document describes the engine's trust assumptions, the protections
it does (and does not) implement, and the checklist any contributor
must follow when adding a feature that touches one of those boundaries.

If you're auditing Abqari for production use, this is the page to read
first. The findings table at the bottom links to the relevant code.

---

## 1. Trust model

Abqari is a **single-author** static site generator. Every input it
processes is assumed to come from the site owner or a trusted
collaborator who already has commit access:

| Input source              | Trust level | Notes |
|---------------------------|-------------|-------|
| `content/**/*.md`         | Trusted     | Author-controlled markdown + frontmatter. |
| `config/site.yml`         | Trusted     | Author-controlled YAML. |
| `data/**/*.{yml,json}`    | Trusted     | Author-curated tables (testimonials, nav, footer). |
| `app/views/**/*.erb`      | Trusted     | Template code; runs with full Ruby access. |
| `themes/**/*`             | Trusted     | CSS + ERB partials shipped with the engine or the site. |
| `plugins/**/*.rb`         | Trusted     | Loaded and executed with full Ruby access at Site construction (see `docs/plugins.md`). |
| Folio API (`folio.foliobooks.app` or self-hosted) | Bounded | Build-time HTTP. Size-capped and timed out. |
| Google Fonts CSS / woff2  | Bounded     | Build-time HTTP. Size-capped and timed out. |
| Visitor browsers (HTML output) | Untrusted | Anything we emit must survive being read by any UA. |

The engine **does not** accept untrusted input at build time. There is
no submission endpoint, no comments pipeline, no markdown coming in
from a third-party SaaS. Every protection in the codebase follows
from this assumption.

If you ever route untrusted markdown, HTML, ERB, or YAML through the
engine — for example by accepting reviews from Folio and rendering them
through the same pipeline — **the trust model changes** and the
checklist in §3 applies.

---

## 2. What the engine protects against today

Even under the trusted-author model, build-time inputs can still go
wrong by accident (a typo in a permalink, a runaway upstream API, a
symlink that points at the wrong directory). The engine defends
against the cases where the cost of getting it wrong is high.

### Path safety

- `lib/abqari/path_safe.rb` provides `PathSafe.join_under(base, *segs)`
  and `PathSafe.assert_under(base, path)`. Both raise
  `Abqari::PathSafe::Error` on any traversal attempt.
- Every place the engine joins user-controlled input into a filesystem
  path is routed through `PathSafe.join_under`:
  - `Page#output_path` — frontmatter `permalink:` (+ allowlisted to
    `[A-Za-z0-9_\-./]+`).
  - `OgImageGenerator#write_file`.
  - `BundleAssets#copy_bundle_assets` and `#copy_flat_collection_assets`.
  - `Redirects#write_stub` — frontmatter `redirect_from:`.
  - `PublisherShowPage#output_path` and `PublisherIndexPage#output_path`
    — publisher integrations (e.g. Folio) are bounded-trust, so an
    attacker-controlled `slug:` in a compromised response can't write
    outside `_site/`.
- `ArtifactWriter#reset_output` refuses to `FileUtils.rm_rf` the
  filesystem root, the home dir, the **site root itself** (so
  `ABQARI_OUTPUT_DIR=.` can't wipe the project), or a source directory
  (`content/`, `config/`, `data/`, `.git`), and asserts containment
  under `site_root`. Escape hatch for the containment check only:
  `ABQARI_ALLOW_EXTERNAL_OUTPUT=true` for CI setups that publish to an
  artifact mount.

### Symlink containment

- `Site#external_symlink?` rejects any symlink whose real target lies
  outside `site_root`. Used in `Site#load_pages`, `Page#bundle_assets`,
  and `BundleAssets#copy_flat_collection_assets`.
- Dangling / looping symlinks are skipped with a warning rather than
  crashing the build.
- Escape hatch: `ABQARI_ALLOW_EXTERNAL_SYMLINKS=true`.

### HTTP bounds

- `lib/abqari/http_safe.rb` is the only build-time HTTP client. Every
  request:
  - Streams the body via `Net::HTTPResponse#read_body { ... }`.
  - Raises `HttpSafe::TooLargeError` when the body exceeds `max_bytes`
    (default 8 MB).
  - Applies `open_timeout: 5, read_timeout: 10` (overridable).
- Folio uses 8 MB / 5 s / 10 s. FontPipeline uses the same. Both fall
  back to cached data on any HTTP error so a misbehaving upstream
  can't break the build.

### YAML

- All YAML loading uses `YAML.safe_load` (or `safe_load_file`) with
  the engine-wide `Abqari::YAML_PERMITTED_CLASSES = [Date, Time]`
  allow-list (defined in `lib/abqari.rb`). Call sites:
  - `Page#parse_frontmatter` (content frontmatter)
  - `SiteLoader#load_config` (`config/site.yml`)
  - `SiteLoader#load_data` (`data/**/*.{yml,yaml}`)
  - `Folio#fetch_endpoint` (Folio cache)
  - `Audit::Content#load_whitelists` (whitelist files)
  - `Renderer#parent_layout_of` + `RenderContext#parse_layout_frontmatter`
    (layout frontmatter)
- No `YAML.load`, no `Psych.load`, no `unsafe_load` anywhere in `lib/`.
- `Page#parse_frontmatter` passes `filename: source_path` so Psych
  errors carry the offending file path. Other failure modes are
  wrapped with the same context.

### Parallel render

- `Site#render_pages` collects per-thread exceptions into a mutex-
  guarded array. After all slices join, every failure is logged and
  the build raises with a count. No silent slice failures.

### Output

- **ERB rendering uses Erubi with `escape: true`** (`lib/abqari/erbi_template.rb`).
  Every `<%= … %>` interpolation passes through `Helpers#h`
  (`CGI.escapeHTML`) automatically. The opt-in raw form is `<%== … %>`
  and is reserved for values that are already safe HTML — helper
  output that builds tags (`render`, `link_to`, `picture_tag`,
  `icon`, `heroicon`, `yield_content`), JSON-LD via
  `script_safe_json`, pre-rendered markdown via `page.content`, and a
  small handful of explicitly-reviewed locals.
- `test/erb_escape_audit_test.rb` scans every partial/layout for
  `<%==` and fails the build if any raw interpolation isn't on the
  allow-list, OR if it uses `JSON.generate` / `to_json` (forbidden
  inside `<script>` — they don't escape `<`, `>`, `&`, U+2028/9, so
  a hostile string in the serialised value can break out of the
  script tag). Friction is the feature: adding a new raw
  interpolation is a deliberate, reviewer-gated choice.
- **JSON-LD inside `<script>` blocks uses `Helpers#script_safe_json`**,
  which escapes `<`, `>`, `&` and U+2028/9 to their `\uXXXX` JSON
  escape sequences. The output round-trips through `JSON.parse` and
  is inert to the host HTML parser. Use this every time a value is
  interpolated raw between `<script>...</script>`.
- External URLs are filtered through `Helpers#sanitized_url`, which
  blocks `javascript:`, `data:`, `vbscript:` schemes AND protocol-
  relative `//evil.com/x` URLs (browsers treat the latter as a
  cross-origin redirect under the page's own scheme).
- `Helpers#slugify` produces only `[a-z0-9-]` — no path separators
  can survive a slug computation.

### CSP

- Inline scripts are allowed by SHA256 hash, never `'unsafe-inline'`.
  `ThemeBootstrap`, `SpeculationRulesGuard` and `PlausibleScript` are
  constants; the speculation-rules block depends on config, so
  `SpeculationRules.sha256` hashes the same body the head emits. The
  headers file ships them in `Content-Security-Policy: script-src`.
  `test/csp_inline_scripts_test.rb` checks every inline script on a
  built page against the built policy.
- Defence-in-depth directives: `object-src 'none'` (no
  `<object>`/`<embed>`), `frame-ancestors 'none'` (no clickjacking),
  `form-action 'self'` (no cross-origin form POSTs unless explicitly
  extended via the newsletter config), `base-uri 'self'`.
- Opt-in features extend the policy narrowly: Plausible adds
  `plausible.io` to `script-src` + `connect-src`, Folio adds
  `covers.foliobooks.app` to `img-src`, and a configured
  `newsletter.action` host is added to `form-action` (and to
  `script-src`/`connect-src` if `newsletter.script` is set).

### Dev server

- `Server` binds to `127.0.0.1` by default. WEBrick's stdlib default
  (0.0.0.0) would expose unrendered drafts and future-dated content
  to anyone on the same LAN. Override with `ABQARI_BIND=0.0.0.0
  bin/serve` only when you actually need LAN access (e.g. previewing
  on a phone).

---

## 3. The "untrusted content" checklist

If you're proposing a feature that accepts data from any source that
isn't already in the trust table above (visitor submissions, third-
party APIs that ship markdown/HTML, anything pulled in via webhook),
**stop and read this section before coding**.

The trust model exists because the engine deliberately does not
sanitise everything. Several powerful affordances exist that are
safe under the trust model but become exploit primitives once
untrusted content enters the same pipeline:

1. **Markdown `unsafe: true`** (`lib/abqari/page.rb:18–33`,
   `MARKDOWN_OPTIONS`). Raw HTML pass-through. A `<script>` tag in a
   blog post's markdown body is rendered verbatim. Acceptable when
   the author wrote it; stored-XSS when an attacker did.

2. **ERB in markdown** (`Page#rendered_body`). Two-gate model: the
   site owner must set `erb_in_markdown: true` in `config/site.yml`,
   AND the page must set `erb: true` in its frontmatter. Both gates
   must be open for ERB to execute. Default at both layers is closed
   so a malicious `erb: true` in synced content can't unilaterally
   execute Ruby. When both are open, the post body runs through
   `RenderContext#render_string` — a full Ruby execution context
   with file-read, file-write, and network access. This is the
   single strongest execution primitive in the engine.

3. **ERB partials and layouts** (`app/views/**/*.erb`). Erubi
   auto-escapes `<%= … %>` via `h(...)`. The risk is `<%== … %>`
   (raw): a future contributor marks an untrusted-data interpolation
   as raw and ships stored XSS. The ERB escape audit (`test/
   erb_escape_audit_test.rb`) gates every `<%==` against an
   allow-list to prevent this.

4. **Frontmatter `permalink:`** is allow-listed and path-safe-joined,
   but most other frontmatter keys are not — they're trusted into
   layouts as-is.

### Required steps before merging untrusted-content work

If any of those three primitives are reachable from untrusted input,
the PR must:

- [ ] Add a new constant `MARKDOWN_OPTIONS_UNTRUSTED` with
      `render: { unsafe: false }` and route the untrusted markdown
      through it. Never share the trusted-content render path.
- [ ] Confirm `erb_in_markdown` is still `false` for the site (the
      default). Untrusted-source pages must not be able to opt into
      ERB execution. If the consuming site needs ERB-in-markdown for
      its own trusted content, route the untrusted pipeline through
      a separate `Page` subclass that hard-codes `frontmatter['erb']`
      to false at parse time.
- [ ] Sanitise rendered HTML with a sanitiser (e.g.
      `Sanitize.fragment(html, Sanitize::Config::BASIC)`) before
      writing it to disk or inserting it into a layout.
- [ ] Walk every layout/partial that will receive the untrusted data
      and confirm no `<%==` (raw) interpolation receives it. Erubi
      escapes `<%=` automatically; `<%==` is the only failure mode.
      The ERB escape audit catches new raw interpolations, but adding
      one to the allow-list for an untrusted-data path is the wrong
      review outcome.
- [ ] Update this document with the new trust-table row.

If those steps aren't applicable to the feature you're proposing,
the feature itself probably shouldn't ship.

---

## 4. Configuration knobs

Environment variables that affect security behaviour:

| Variable                              | Default | Purpose |
|---------------------------------------|---------|---------|
| `ABQARI_ALLOW_EXTERNAL_OUTPUT`        | unset   | Permit `output_dir` outside `site_root`. CI artifact mounts only. |
| `ABQARI_ALLOW_EXTERNAL_SYMLINKS`      | unset   | Permit symlinks that escape `site_root`. Avoid. |
| `ABQARI_STRICT_CONFIG`                | unset   | Raise on unknown top-level keys in `site.yml` instead of warning. Recommended for CI. |
| `ABQARI_LOG`                          | `info`  | Logger threshold (`debug`/`info`/`warn`/`error`). |

Site-config keys with security implications:

| Key                  | Default | Purpose |
|----------------------|---------|---------|
| `erb_in_markdown`    | `false` | Site-wide gate for ERB execution inside markdown bodies. Even with `erb: true` in a page's frontmatter, ERB does not run unless this is also set. Keep `false` unless the site author needs `<%= years_since(2002) %>`-style helper calls in markdown AND trusts every source of content under `content/`. |

---

## 5. Reporting a vulnerability

If you find a security issue in Abqari, please **do not open a public
issue**. Email the maintainer privately (see `config/site.yml`
`security_contact:` in the engine fixture for the canonical address)
or open a GitHub security advisory on the repository.

Acknowledged within 7 days; fix targeted within 30 days for high-
severity issues.

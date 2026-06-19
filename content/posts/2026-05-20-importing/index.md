---
title: Importing content from Substack, Ghost, and Jekyll
published: true
description: bin/import pulls posts from another platform's export into your content/<collection>/ tree as regular Abqari bundles.
tags: [importers, migration, substack, ghost, jekyll, v0.4.0]
cover: svg
---

Abqari 0.4.0 ships content importers for three common sources:
**Substack** (ZIP export), **Ghost** (JSON export), and **Jekyll**
(site source directory). Each imported post lands as a regular
Abqari bundle so the result is indistinguishable from posts
authored fresh.

```bash
bin/import substack ~/Downloads/substack-export.zip
bin/import ghost    ~/Downloads/ghost-export.json
bin/import jekyll   ~/old-site/
```

## What each importer does

For every source post:

1. **HTML → Markdown** via `reverse_markdown` (GFM extensions —
   tables, strikethrough, fenced code). Unknown tags pass through
   verbatim for manual cleanup.
2. **Platform chrome stripped** before conversion. Each importer
   ships a default selector list (Substack subscription widgets,
   Ghost bookmark cards, Jekyll-specific shortcodes). Extend with
   `--strip "selector1, selector2"`.
3. **Remote images downloaded** into each post's bundle directory
   so the image pipeline can re-encode them to AVIF + WebP with
   responsive variants. `--keep-remote` opts out and leaves the
   original `<img src="https://...">` URLs intact.
4. **`redirect_from:` written** so inbound links to the source-
   platform URLs keep working:
   - Substack: `/p/<slug>/`
   - Ghost: `/<slug>/`
   - Jekyll: the original permalink, when discoverable from the
     post frontmatter
5. **Idempotent re-runs** — files that already exist are skipped
   by default. `--force` overwrites.
6. **Slug collisions** resolved by numeric suffix
   (`foo`, `foo-2`, `foo-3`).
7. **`_import_report.md`** written at the site root (gitignored)
   summarising every post: status, warnings, redirects added,
   images downloaded.

## Common flags

```
bin/import <source-type> <path>
  --into COLLECTION           target collection (default: posts)
  --flat                      flat single-file posts (no bundles)
  --keep-remote               keep remote image URLs (don't download)
  --strip "sel1, sel2"        extra selectors to strip before conversion
  --canonical                 add canonical_url frontmatter
                              pointing at the source-platform URL
  --dry-run                   show what would happen; touch nothing
  --force                     overwrite existing files
```

## Substack

Substack's export is a ZIP file with a `posts.csv` manifest and
one HTML file per post under `posts/`. The importer reads the
CSV for frontmatter (title, subtitle, publish date, paywall flag)
and the per-post HTML for the body.

```bash
bin/import substack ~/Downloads/substack-export.zip
```

Default chrome stripped:

- Subscription widgets (`.subscription-widget-wrap`,
  `.email-input`)
- Footnote backlinks rendered by Substack's editor
- Paywall placeholder divs (the importer marks paywalled posts
  with `paywall: true` in frontmatter; you decide whether to
  publish them)

Substack URLs follow the pattern `<newsletter>.substack.com/p/<slug>`.
The `redirect_from:` keys point at `/p/<slug>/` so inbound links
keep working if you move the newsletter's domain to your Abqari
site.

## Ghost

Ghost's JSON export contains a `posts` array with body, slug,
publish date, tags, and meta. The importer reads it directly:

```bash
bin/import ghost ~/Downloads/ghost-2025-...-export.json
```

Default chrome stripped:

- Bookmark cards (`.kg-bookmark-card`)
- Embed cards (`.kg-embed-card`)
- Subscribe widgets

Ghost URLs are `<domain>/<slug>/`. The `redirect_from:` keys point
at `/<slug>/`.

## Jekyll

The Jekyll importer reads `_posts/`, `_drafts/`, and (if present)
custom collection directories. YAML frontmatter passes through
mostly intact; some keys are renamed to match Abqari conventions
(`categories` → `tags` if you don't already have tags, the rest
preserved as-is).

```bash
bin/import jekyll ~/old-jekyll-site/
```

The path is the **Jekyll site root** (the directory containing
`_config.yml`), not `_posts/`.

`_config.yml` is read for `permalink:` style — if you used Jekyll's
default `/:year/:month/:day/:title/`, the importer writes
`redirect_from:` matching that pattern so old URLs work.

## Lazy gem load

`reverse_markdown` is the only dep that only the importers use.
It's declared as a runtime dependency but loaded **lazily** —
normal `bin/build` / `bin/serve` never pull it into memory. The
gem is pure Ruby and ~30 KB; the lazy load means it doesn't even
need to be installed for ordinary builds, but `bundle install`
puts it in place for the day you want to import.

## After import

Verify with the audit:

```bash
bundle exec bin/audit
```

The audit catches imported posts with missing alt text, broken
internal links (after `redirect_from:` resolution), and SEO
deficiencies. Then `bin/serve` to spot-check the result before
committing.

## See also

- [Quickstart](/guides/quickstart/) — fresh-site setup
- [Audit](/guides/the-audit/) — finding issues in imported content
- [Collections and taxonomies](/guides/collections/) — how the
  imported posts fit alongside everything else

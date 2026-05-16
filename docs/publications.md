# Publications, bundles, and series

Abqari's publication / bundle / series data model is **aligned with the
Folio v1 API contract** (`apps/folio`, `services/publication_api_serializer.rb`).
The same field names are used whether a publication comes from a hand-
written `content/publications/<slug>/index.md` frontmatter block or
from a Folio fetch.

This page is the canonical reference. Field names here are stable
within Abqari 0.x; renames require a major version bump.

---

## 1. Three collections, one vocabulary

| Collection | Source | Frontmatter file |
|---|---|---|
| `publications` | manual + publisher integration | `content/publications/<slug>/index.md` |
| `bundles` | manual + publisher integration | `content/bundles/<slug>/index.md` |
| `series` | manual + publisher integration | `content/series/<slug>/index.md` |

`site.collection('publications')` returns BOTH manual `Page` objects and
publisher-sourced `PublisherShowPage` objects. Templates iterate one
list.

When a slug exists in both manual content and a publisher source, the
manual page wins. Manual frontmatter overrides any field; missing
fields fall through to the publisher payload (which is exposed as
the page's frontmatter once it's joined to the collection).

---

## 2. Publication

Required:
- `slug` — derived from the bundle directory name; not written in
  frontmatter.
- `title` — string.

Marketing prose:
- `tagline` — short one-line subtitle (intended for cards and link
  previews).
- `excerpt` — long-form description, markdown source.
- `excerpt_html` — pre-rendered HTML. Folio supplies this; native
  frontmatter rarely needs it (CommonMarker renders `excerpt` on the
  fly when `excerpt_html` is absent).

Catalogue:
- `cover_url` — URL or site-relative path to the cover image.
- `cover_alt` — alt text for the cover image (optional).
- `isbn` — string.
- `pages` — integer.
- `language` — ISO 639-1 string.
- `category` — string. Free-form on Folio (literary category); free-
  form here too.
- `reading_age` — string.
- `published_at` — date or ISO 8601 string.
- `release_date` — date or ISO 8601 string (for pre-orders that have a
  scheduled release).
- `updated_at` — Folio supplies this; native frontmatter usually omits
  it (falls back to source file mtime).
- `preorder` — boolean.
- `available_for_purchase` — boolean.
- `version` — integer (Folio's version number tracking).

Pricing — **canonical shape is a Hash**:
```yaml
price:
  cents: 1600
  currency: USD
  formatted: $16.00
```
For convenience, frontmatter accepts a **string shorthand**:
```yaml
price: $16.00         # auto-expands to { cents: 1600, currency: USD, formatted: '$16.00' }
```
Currency inferred from the symbol prefix (`$` → USD, `€` → EUR, `£` →
GBP, `S$` → SGD, etc.). For other currencies, use the Hash form.

Commerce:
- `buy_now_url` — direct purchase link.
- `add_to_cart_url` — add-to-cart link (optional, for stores that
  support a cart flow).
- `shop_url` — author shop URL (Folio supplies this; usually omitted
  in native frontmatter).
- `samples` — array of `{id, name, url}` for downloadable book
  samples (PDFs, first chapters). Optional; both Folio and native
  support.

Relationships:
- `in_series` — `{slug, name, position}` Hash. Position is the
  numeric order within the series (1 = first volume).
- `in_bundles` — array of `{slug, name, price}` summaries.
  Folio supplies this directly; for native publications, the engine
  computes it by inverse-lookup (which `content/bundles/*/index.md`
  lists this publication's slug in its `publications` array).

Author:
- `author` — `{slug, name}` Hash, OR a string (auto-wrapped). Folio
  per-publication; native usually inherits from site-wide `author:`
  in `config/site.yml` unless overridden here.

### Example — minimal native publication

```yaml
---
title: First Light
tagline: Short meditations on the first hours of the day.
excerpt: |
  A small book about beginnings. Twenty-two short pieces — call them
  essays, observations, or notes; the form sits between all three.
cover_url: /publications/first-light/cover.svg
price: $16.00
isbn: 978-981-94-0000-4
language: en
pages: 116
published_at: 2026-05-01
buy_now_url: https://example.com/buy/first-light
in_series:
  slug: light-notebooks
  name: Light Notebooks
  position: 1
tags: [light]
---
```

### Example — publisher-sourced publication

A publisher integration (currently Folio) supplies the canonical
shape directly via the API. No frontmatter file is required;
`PublisherShowPage` is auto-generated at build time and joins
`site.collection('publications')` automatically.

---

## 3. Bundle

A bundle is "two or more publications sold together at a single
price" (Folio's definition).

Required:
- `slug`
- `name` — bundle title. **Note: `name`, NOT `title`** — aligns with
  Folio's bundle shape, which is intentionally distinct from
  publication (`title`).

Marketing prose:
- `description` — long-form, markdown source.
- `description_html` — pre-rendered HTML (Folio supplies).

Catalogue:
- `cover_url` — optional; if absent, the bundle UI composes a stack
  of member-publication covers.
- `updated_at`

Pricing (same shape as publication):
- `price: { cents, currency, formatted }` — Hash, or string shorthand
  in frontmatter.

Commerce:
- `buy_now_url`
- `add_to_cart_url`

Membership:
- `publications` — **array of slugs** (string). The engine resolves
  each slug against `site.collection('publications')` for display.

### Example

```yaml
---
name: Light Notebooks Bundle
description: Both volumes of the Light Notebooks series at a saving.
publications: [first-light, last-light]
price: $28.00
buy_now_url: https://example.com/buy/light-notebooks-bundle
cover_url: /bundles/light-notebooks/cover.svg
---
```

---

## 4. Series

A series is "an ordered sequence of publications" (Folio's
definition). Unlike bundles, **series in Folio have no commerce
attached** — no `price`, no buy buttons. A native author can add
`buy_now_url:` manually to point at, e.g., a Payhip series-bundle.

Required:
- `slug`
- `name`

Marketing prose:
- `description` + `description_html`

Catalogue:
- `cover_url` (optional)
- `updated_at`

Membership:
- `publications` — array of slugs, OR array of `{slug, position}`
  Hashes if explicit ordering is needed. Each publication's own
  `in_series.position` is the authoritative order; this field is the
  inclusion list.

Optional commerce (native only):
- `buy_now_url`, `add_to_cart_url` — render buttons when set; Folio
  series never supplies these.

### Example

```yaml
---
name: Light Notebooks
description: Two short books about beginnings and endings.
publications: [first-light, last-light]
---
```

---

## 5. Field-resolution rules

For any field on a publication / bundle / series page:

1. The page's own frontmatter is the source of truth.
2. Publisher data is folded into the page's frontmatter for
   `PublisherShowPage` objects (auto-generated from publisher
   fetches). When a manual override page exists for the same slug,
   the manual file is the page; publisher data does NOT bleed into
   it (use the override to explicitly carry the fields you want).

There is **no `folio['x'] || fm['x']` chain in templates anymore.**
Templates read `page.frontmatter['x']` (or the shorthand
`page.frontmatter.dig('in_series', 'position')`) and the right
answer surfaces.

---

## 6. JSON-LD

`_book_jsonld.html.erb` reads canonical fields directly. `title`,
`excerpt`, `cover_url`, `isbn`, `language`, `pages`, `published_at`,
`price.cents`, `price.currency`, `available_for_purchase`,
`buy_now_url` all map onto Schema.org Book / Offer fields with no
translation layer.

---

## 7. Migration from Abqari 0.2.x

Hard cutover. Sites running 0.2.x must rename frontmatter keys before
upgrading to 0.3.0:

| 0.2.x frontmatter | 0.3.0 frontmatter |
|---|---|
| `description:` on publications | `excerpt:` |
| `cover:` / `cover_image:` | `cover_url:` |
| `buy_url:` | `buy_now_url:` |
| `series: foo` + `series_position: 1` | `in_series: {slug: foo, name: …, position: 1}` |
| `title:` on bundles | `name:` |
| `title:` on series | `name:` |
| `description:` on bundles/series | `description:` (unchanged) |

Posts, photos, workshops are unaffected — they continue to use
`description`.

The Folio cache in `vendor/folio/` should be wiped after upgrade so
the next build re-fetches and stores the canonical shape (the cache
format hasn't changed, but stale entries from pre-canonical adapters
in earlier sites could confuse things).

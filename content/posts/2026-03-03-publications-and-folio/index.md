---
title: "Publications and Folio integration"
published: true
description: Two data sources for the publications collection — write manual frontmatter, connect a Folio storefront, or both at once.
date: 2026-03-03
tags: [publications, folio, storefront]
---

The `publications` collection is for books, essays, monographs —
anything you sell or list with a price, cover, and metadata.
Abqari supports two data sources, and they coexist: manual
markdown entries authored alongside your content, and a build-time
fetch from a [Folio](https://www.foliobooks.app) storefront.

## Path A: manual entries

Drop a markdown file at `content/publications/<slug>/index.md`
with the book's frontmatter:

```yaml
---
title: The Field Guide to Static Sites
tagline: A practical handbook for self-hosted publishing.
excerpt: |
  Why static sites are coming back, and how to build one that
  outlasts the next platform shift.
cover: cover.svg
price: $18.99
isbn: 978-981-94-0000-1
pages: 184
buy_url: https://example.com/buy/the-field-guide
---
```

The publication show view renders cover, title, tagline, excerpt,
ISBN, page count, price, and a buy button. Everything is optional —
set only what you have.

## Path B: Folio storefront

When you configure `folio:` in `config/site.yml`, Abqari fetches
your catalogue at build time and auto-generates pages for each
publication, bundle, and series. The visitor's browser never makes
a request to Folio — everything is baked into the static HTML.

```yaml
# config/site.yml
folio:
  base_url: https://www.foliobooks.app
  author_slug: your-author-slug
```

That's the entire configuration. On the next build:

```
$ bin/build
Folio: loaded 4 publication(s), 1 bundle(s), 0 series
Built 21 page(s) in production → _site/
```

If you don't see the Folio line, either the config block is
missing or `base_url` / `author_slug` is unset.

### Why build-time fetching

Author sites built around a storefront usually do one of three
things:

1. **Embed the storefront's iframe.** Adds a third-party request,
   breaks strict CSP, slow.
2. **Re-host the data manually** (copy-paste book metadata into
   markdown). Drifts out of sync the moment you update Folio.
3. **Server-side fetch.** Needs a runtime, conflicts with static
   deploys.

Abqari does the same thing as option 3 but at build time. Your
CI run hits Folio's read-only JSON API, caches the response, and
writes static pages. Your readers' browsers see only your origin.

## Auto-generated pages

When Folio is configured, the engine adds these to the build:

| URL | Source | Layout |
| --- | --- | --- |
| `/publications/` | All publications | `publications_index` |
| `/publications/<slug>/` | Each publication | `publication` |
| `/bundles/` | All bundles | `bundles_index` |
| `/bundles/<slug>/` | Each bundle | `bundle` |
| `/series/` | All series | `series_index` |
| `/series/<slug>/` | Each series | `series` |

The `:slug` matches Folio's slug for that entity.

## Hybrid: manual + Folio

A manual `content/publications/<slug>/index.md` overrides the
Folio-generated page for that slug. Useful for richer descriptions
or a custom hero image while still getting live price + buy
buttons from Folio.

Abqari skips auto-generation for any URL where a markdown page
already exists. The page renders through the same `publication`
layout, so cover, price, and buttons still appear — your markdown
body is appended after them.

## The data shape

Inside a layout or partial, the Folio payload is available as
`page.data`:

```erb
<% folio = page.data %>
<h1><%= folio['title'] %></h1>
<% if (price = folio.dig('price', 'formatted')) %>
  <p><%= price %></p>
<% end %>
```

A publication payload includes:

```
slug, title, tagline, excerpt, excerpt_html, author,
price{cents, currency, formatted}, cover_url,
buy_now_url, add_to_cart_url, shop_url, samples,
isbn, category, language, reading_age, pages,
published_at, updated_at, version, preorder, release_date,
available_for_purchase, in_bundles, in_series
```

A bundle payload:

```
slug, name, description, description_html, author, price{...},
buy_now_url, add_to_cart_url,
publications: [{ slug, title, cover_url }, ...], updated_at
```

A series payload:

```
slug, name, description, description_html, author,
publications: [{ slug, title, cover_url, position }, ...],
updated_at
```

## Helpers

Available in any layout or partial — they look up Folio entities
by slug:

```erb
<% book   = folio_book('the-field-guide') %>
<% bundle = folio_bundle('the-starter-library') %>
<% series = folio_series('light-notebooks') %>

<%== folio_buy_button('the-field-guide') %>
<%== folio_cart_button('the-starter-library', kind: :bundle) %>
```

Lookup helpers return `nil` for unknown slugs (rather than
raising), so a missing book doesn't break the build. Button
helpers render an empty string when the entity isn't loaded —
also non-fatal.

The button helpers accept `kind:` (`:book` or `:bundle`) and
`label:`:

```erb
<%== folio_buy_button('the-field-guide', label: 'Get the eBook') %>
```

## The cache

Folio responses are cached on disk:

```
vendor/folio/
├── publications.yml      # last-good response body
├── bundles.yml
├── series.yml
├── etag-publications     # ETag from last 200 response
├── etag-bundles
└── etag-series
```

This directory is gitignored — each CI runner builds its own cache.
Subsequent builds send `If-None-Match` and get back `304 Not Modified`
(no body transfer) when nothing has changed.

If Folio is unreachable (CI offline, brief outage), Abqari falls
back to the cached data and prints a warning:

```
Folio: fetch /publications failed (SocketError: ...) — using cached data
```

The build still succeeds. If there's no cache yet — first build
on a fresh runner with no network — `site.data` stays empty, and
layouts gracefully degrade to whatever fallbacks you've coded
into frontmatter.

To force a fresh fetch:

```bash
bin/fetch-folio
```

This deletes the ETag files and re-requests all three endpoints.

### Safety

All Folio fetches route through `Abqari::HttpSafe` — streaming
read, 8 MB body cap, 5 s open / 10 s read timeouts. A misbehaving
or compromised Folio response can't pin the build runner's memory.

## JSON-LD

Each publication page emits a `Book` schema:

```json
{
  "@context": "https://schema.org",
  "@type": "Book",
  "name": "The Field Guide to Static Sites",
  "url": "https://example.com/publications/the-field-guide/",
  "author": { "@type": "Person", "name": "Grant Rayner" },
  "isbn": "978-981-94-0000-1",
  "image": "https://covers.foliobooks.app/.../cover-web.jpeg",
  "offers": {
    "@type": "Offer",
    "price": 18.99,
    "priceCurrency": "USD",
    "availability": "https://schema.org/InStock"
  }
}
```

Pulled from `app/views/partials/_book_jsonld.html.erb`. Edit
that partial to add fields (e.g. `numberOfPages`, `bookEdition`).

## Bundle CTA on publication pages

When a publication belongs to a bundle, the publication layout
renders a callout linking to the bundle's page with its own
buy/cart buttons:

```
┌───────────────────────────────────────────┐
│ Save with the bundle                       │
│ The Starter Library — $35.99               │
│ [Buy now]  [Add to cart]                   │
└───────────────────────────────────────────┘
```

This comes from `_folio_bundle_cta.html.erb`. Multiple bundles →
multiple CTAs stacked.

## Overriding a single auto-generated page

Auto-generated pages are convenient but not always what you want.
To customise a single publication page, create a markdown file at
the matching path:

```markdown
---
# content/publications/memoirs-of-an-assassin/index.md
title: Memoirs of an Assassin
layout: publication
---

A first-person reckoning with the trade. The chapter below is
from the free sample on Folio — tap **Buy now** to get the
full book.

[Read the sample](#sample)
```

Abqari skips auto-generation for any URL where a markdown page
already exists. The page renders through the same `publication`
layout, so the cover, price, and buttons still appear — your
markdown body is appended after them. The same pattern works
for bundles and series.

To replace an auto-generated INDEX page (`/publications/`,
`/bundles/`, `/series/`), create `content/<collection>/index.md`
with `layout: <publications_index|bundles_index|series_index>`
and your own intro copy.

## Layouts and partials

Six layouts under `app/views/layouts/` drive the Folio output:

| File | Purpose |
| --- | --- |
| `publication.html.erb` | Single publication detail page |
| `bundle.html.erb` | Single bundle detail (with member grid) |
| `series.html.erb` | Single series page (ordered list) |
| `publications_index.html.erb` | Index of all publications |
| `bundles_index.html.erb` | Index of bundles |
| `series_index.html.erb` | Index of series |

Two partials:

| File | Purpose |
| --- | --- |
| `_book_jsonld.html.erb` | Schema.org Book emitter |
| `_folio_bundle_cta.html.erb` | "Save with the bundle" callout |

All eight files are designed to be edited freely. Drop your own
copies into your site's `app/views/` to override the engine
versions while keeping everything else current.

## Styling

The engine ships minimal CSS for the publication layouts — enough
for cards and buttons to render usefully without a theme. The
auto-generated markup uses BEM-style class names you can target
from your theme's CSS to fully restyle:

```css
.publication__header { display: grid; grid-template-columns: auto 1fr; gap: 1rem; }
.publication__cover  { max-width: 200px; }
.folio-button        { display: inline-block; padding: 0.5rem 1rem; }
.folio-button--buy   { background: var(--color-link); color: var(--color-bg); }
.folio-bundle-cta    { padding: 1rem; border: 1px solid currentColor; margin: 2rem 0; }
```

This is intentional minimalism — book sites are wildly varied,
and opinionated defaults usually get in the way more than they
help.

## Disabling Folio

Remove or comment out the `folio:` block in `config/site.yml`.
The auto-generated pages disappear; manual `content/publications/<slug>/`
pages keep rendering through the same layout.

## See also

- [Bundles and series](/guides/bundles-and-series/) — how
  multi-publication groupings render
- [Folio's docs](https://www.foliobooks.app/docs) — the
  upstream API and storefront features

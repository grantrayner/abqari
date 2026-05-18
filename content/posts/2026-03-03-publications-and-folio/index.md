---
title: "Publications and Folio integration"
published: true
description: Two ways to ship books on an Abqari site — write manual content files, or connect a Folio storefront for live pricing, ISBNs, and covers.
date: 2026-03-03
tags: [publications, folio]
---

The `publications` collection is for books, essays, monographs —
anything you sell or list with a price, cover, and metadata.
Abqari supports two data sources, and they coexist.

## Path A: manual entries

Drop a markdown file at `content/publications/<slug>/index.md`
with the book's frontmatter:

```yaml
---
title: The Field Guide to Static Sites
description: A practical handbook for self-hosted publishing.
cover: /publications/the-field-guide/cover.svg
price: $18.99
isbn: 978-981-94-0000-1
pages: 184
buy_url: https://example.com/buy/the-field-guide
---
```

The publication show view renders cover, title, description, ISBN,
page count, price, and a buy button. Everything is optional — set
only what you have.

## Path B: Folio storefront

Connect a [Folio](https://foliobooks.app) storefront and the
engine pulls publications, bundles, and series at build time:

```yaml
folio:
  base_url: https://www.foliobooks.app
  author_slug: your-author-slug
```

Folio gives you live pricing, "add to cart" / "buy now" flows, and
auto-generated `/books/`, `/bundles/`, `/series/` pages. The cache
lives in `vendor/folio/` and refreshes with `bin/fetch-folio`.

## Hybrid

A manual `content/publications/<slug>/index.md` overrides the
Folio-generated page for that slug — useful for a richer
description or a custom hero image while still getting the live
price from Folio.

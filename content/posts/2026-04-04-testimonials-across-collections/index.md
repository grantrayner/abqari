---
title: Testimonials across collections
description: One testimonials system, any collection — posts, publications, workshops can all carry reader quotes via the same partial.
date: 2026-04-04
tags: [testimonials, collections]
---

Testimonials in Abqari aren't tied to publications. The same
`data/testimonials.yml` file feeds blurbs for any collection — a
publication, a workshop, a post, anything that has a slug.

## Data shape

Two equivalent forms per entry. Generic:

```yaml
- quote: "Excellent workshop"
  name: Jane Doe
  featured: true
  collection: workshops
  slug: crisis-response-foundations
```

Or the legacy shorthand (publications only):

```yaml
- quote: "Couldn't put it down"
  name: Uri
  featured: true
  book: memoirs-of-an-assassin
```

## Calling the partial

From any show view:

```erb
<%= render 'partials/testimonials', subject: page %>
```

The partial auto-detects `page.collection` and `page.slug`, then
filters testimonials whose `collection:` + `slug:` (or legacy
`book:`) match. Renders nothing if there are no matches.

## Filter modes

- `subject: page` — match the current page's slug (most ergonomic)
- `collection: 'workshops', slug: '...'` — explicit pair
- `featured: true` — no subject, show featured across all
  collections (use this on the home / about pages for a curated mix)
- `book_slug: '...'` — legacy, kept for back-compat with older sites

## Linked titles

Each testimonial's citation links back to its subject. The link is
resolved via `site.collection(c).find` (any collection) with a
Folio-data fallback for publications, so links work whether the
subject is manual content or Folio-generated.

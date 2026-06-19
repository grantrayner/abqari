---
title: Home page modules
published: true
description: Eight optional modules for the home page — latest post, photo gallery, featured publication, contact — each toggleable in config.
date: 2026-03-28
tags: [home, configuration]
---

The home page is a markdown body (`content/index.md`) plus a stack
of optional modules below. Each module is a self-contained partial
under `app/views/partials/home/`, toggled by one key in
`config/site.yml`:

```yaml
home:
  latest_post:        true
  random_post:        true
  featured_publication: true
  latest_publication: true
  next_workshop:      true
  latest_photo:       true
  random_photo:       true
  photo_gallery:      latest    # 'latest' / 'random' / false
  contact:            true
```

## What's available

- **latest_post** — newest post card
- **random_post** ("From the archive") — random post, rotates on
  every page load via a tiny client-side script (static sites can't
  roll randomness at request time)
- **latest_publication** — newest publication with cover thumbnail
- **featured_publication** — the publication flagged `showcase: true`,
  same shape as latest
- **next_workshop** — soonest upcoming workshop
- **latest_photo** — most recent photo
- **random_photo** ("From the gallery") — random photo, same rotation
  pattern as random_post
- **photo_gallery** — single row of 4 photos in `gallery-index` style
- **contact** — the spam-resistant contact button

Most modules end with a slug-aware `All <collection> →` link
through to the corresponding collection index.

## Order

Module order is fixed in `home.html.erb`'s dispatch block. To
reorder, swap the render calls in that file. Real sites usually
turn most modules off — the engine's fixture turns them all on as
a showcase.

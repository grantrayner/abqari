---
title: Photos and galleries
description: How the photos collection works — gallery index, country and series taxonomies, and the showcase photo at the top of /photos/.
date: 2026-01-28
tags: [photos, galleries, taxonomies]
image: hero.svg
series: Inside Abqari
series_position: 2
---

The `photos` collection is for image-centric posts — one frame per
page, with frontmatter describing where the photo was taken, with
what camera, and which series it belongs to.

## The bundle layout

Each photo lives in `content/photos/<slug>/index.md` alongside its
image file. Convention is `image: photo.svg` (or `.jpg`, `.avif`,
etc.) — colocated assets get copied to `_site/<slug>/` and the URL
is rewritten automatically.

```
content/photos/2026-03-15-tea-break/
├── index.md
└── photo.jpg
```

## Frontmatter shape

```yaml
---
title: Tea break
caption: A short rest between the souk and the citadel.
date: 2026-03-15
city: Damascus
country: Syria
camera: Leica Q2
series: Damascus 2026
series_position: 4
image: photo.jpg
tags: [photography, syria]
---
```

## Country and series taxonomies

Two taxonomies ship by default for photo blogs. Set
`country: Syria` and `series: Damascus 2026` in a photo's
frontmatter and Abqari auto-generates `/country/syria/` and
`/photos/series/damascus-2026/` index pages. Series are
per-collection — posts, photos, publications, and workshops
each get their own `/<collection>/series/<slug>/` page from
the same `series:` frontmatter field. The country field is
validated against `data/countries.yml` — typos like `Syra` get
caught by `bin/audit` before they ship.

## The showcase photo

Flip `display_showcase: true` under `collections.photos.index`
and add `showcase: true` to one photo's frontmatter. That photo
renders full-width at the top of `/photos/` and is excluded
from the grid below so it doesn't appear twice.

---
title: "Hero images: natural on show, 4:3 on index"
description: How post hero images render across show and index views — natural aspect on the post page, 4:3 cropping in the listings.
date: 2026-04-22
tags: [images, design]
---

Most Abqari layouts (posts, photos, workshops, publications) accept
a single frontmatter field for a hero image:

```yaml
image: hero.svg          # relative — colocated bundle asset
image: /assets/hero.jpg  # absolute — anywhere under /assets/
```

For colocated assets, the engine resolves the relative path against
the page's bundle directory automatically. SVGs, JPEGs, WebP, PNG
all work.

## How posts render heroes

Two contexts, two treatments:

- **Show view** (a single post page) — **natural aspect**. Width
  fills the column, height follows the image's intrinsic ratio.
  Upload at 4:3 and you'll see 4:3; upload at 3:2 and you'll see
  3:2; portrait orientation renders portrait. Same approach the
  photo show view uses for the image itself.
- **Index views** (post list, archive, home modules) — **4:3
  crop**. The same image gets cropped to a 4:3 thumbnail via
  `object-fit: cover` so grids stay visually consistent.

This is deliberate: the show view is where the full image gets to
breathe, the index is where it needs to fit in a grid. Most camera
and phone uploads default to 3:2 or 4:3 — forcing a wide 16:9 on
the show view would crop the top and bottom of typical photographs.

## Other heroes

Workshop heroes (`.workshop__hero`) and inline body figures
(`.story-image`) stay at a fixed 16:9 crop. Workshops are usually
event imagery (room photos, flyers) that read best wide, and inline
figures are author-curated within a body of flowing prose where a
banner crop avoids variable-height interruptions.

## Toggling heroes

Two independent settings per collection:

```yaml
collections:
  posts:
    index:
      show_image: true     # heroes on the listing cards
    show:
      show_image: true     # hero on the post page itself
```

Flip either off to suppress heroes on that surface without editing
each post's frontmatter.

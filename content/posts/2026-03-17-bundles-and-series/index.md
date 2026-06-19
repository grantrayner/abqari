---
title: "Bundles and series: grouping publications"
published: true
description: Two meta-collections that wrap multiple books into a single retailable unit — bundles for sets, series for sequences.
date: 2026-03-17
tags: [publications, bundles, series]
image: hero.svg
series: Inside Abqari
series_position: 3
---

A bundle is "buy these three together"; a series is "read this one
first, then this one, then this one." Both let you compose multiple
publications into a single page with shared metadata, pricing, and a
single URL.

## Bundles

A bundle is a curated set sold (or read) together. Each lives at
`content/bundles/<slug>/index.md` and references its component
publications by slug:

```yaml
---
title: "The starter library"
description: A three-book pack for new readers.
publications: [first-light, last-light, margin-notes]
price: "$30"
buy_url: https://example.com/buy/starter
---
```

The bundle page renders all three covers in a single layout with a
"What's included" section that lists each book.

## Series

A series is an ordered sequence. Use it for trilogies, multi-volume
works, or any "read these in order" relationship. Each item in the
series carries:

```yaml
series: Light Notebooks
series_position: 1
```

The engine auto-generates `/publications/series/light-notebooks/`
showing every book with that series name, sorted by
`series_position`. Same mechanism applies to posts, photos, and
workshops — each gets its own `/<collection>/series/<slug>/` page.

## Bundles vs series

Use **bundles** when the value is in the grouping itself (set price,
themed pack, sampler). Use **series** when the value is in the
sequence (read this one first, then that). The two can overlap — a
trilogy is both a series and a bundle — but the layouts and URLs
are independent so you can express either or both.

---
title: "Slug aliasing: putting posts at /stories/"
description: How to rename a built-in collection's URL prefix without forking layouts or moving files around on disk.
date: 2026-02-05
tags: [configuration, urls, collections]
---

The built-in collection names — `posts`, `photos`, `publications`,
`workshops`, `bundles`, `series` — are sensible defaults. They're
also opinions you might disagree with. If you're shipping a fiction
site, "posts" feels generic; you want `/stories/`. If you're a
publisher, "publications" is fine but `/books/` reads better.

Slug aliasing fixes this in three lines of config:

```yaml
collections:
  posts:
    slug: stories
```

That's enough. The engine derives the URL pattern (`/stories/:slug/`),
the layout name (`story`), and the feed URL (`/stories/feed.xml`)
automatically.

## What changes, what doesn't

**Changes**: the public-facing URLs, the layout name lookup, and
the feed path. So a post at `content/posts/hello.md` now renders
at `/stories/hello/` and uses `story.html.erb` (singularized from
the slug).

**Doesn't change**: the on-disk source directory. Posts stay at
`content/posts/` regardless of slug. This is deliberate — it keeps
the project structure consistent across sites and makes it easy to
swap themes or rename collections without moving thousands of
files around.

## Keeping a canonical layout

If your slug doesn't singularize cleanly, or you want to keep
using a canonical layout, set both:

```yaml
collections:
  posts:
    slug: articles
    layout: post     # keep using post.html.erb, not article.html.erb
```

The override wins.

---
title: Per-collection RSS + JSON Feed
description: Different audiences subscribe to different streams. Each collection can emit its own RSS + JSON Feed, opt-in per collection.
---

# Per-collection RSS + JSON Feed

When you have a blog, a photo gallery, AND a list of publications on the same site, your audience may want to subscribe to one stream but not another. Abqari can emit independent feeds per collection — each at its own URL, with its own auto-discovery `<link>` tag.

## Defaults

Posts ship with feeds enabled (this is what most existing sites have at `/feed.xml`):

```yaml
collections:
  posts:
    feeds:
      enabled: true     # default
```

Photos and publications default off:

```yaml
collections:
  photos:
    feeds:
      enabled: false    # default — flip on for a photo subscriber audience
  publications:
    feeds:
      enabled: false    # default — flip on for a "new books" stream
```

## Output paths

Posts use the historical root paths (so existing subscribers keep working):

```
/feed.xml
/feed.json
```

Other collections live under their own URL space:

```
/photos/feed.xml
/photos/feed.json

/publications/feed.xml
/publications/feed.json
```

That's true for any collection you add — `workshops`, `recipes`, `notes`, anything. The output path is `/<collection>/feed.{xml,json}`.

## Auto-discovery

Every page's `<head>` carries a `<link rel="alternate">` for *each* enabled feed. Feed readers will pick up whatever's relevant — typically the one matching the page they're looking at, but most feed readers offer a "show me all available feeds" prompt when they hit a site.

A photo show page (`/photos/bread-shop/`) with both `posts.feeds.enabled: true` and `photos.feeds.enabled: true` advertises:

```html
<link rel="alternate" type="application/rss+xml"   href="/feed.xml"          title="My Site">
<link rel="alternate" type="application/feed+json" href="/feed.json"         title="My Site">
<link rel="alternate" type="application/rss+xml"   href="/photos/feed.xml"   title="My Site — Photos">
<link rel="alternate" type="application/feed+json" href="/photos/feed.json"  title="My Site — Photos">
```

Reader software shows two subscription options. The visitor picks.

## Common configurations

**Photo blog with both written + visual streams**:

```yaml
posts:    { feeds: { enabled: true } }   # writing
photos:   { feeds: { enabled: true } }   # photo updates
```

Two distinct subscriber audiences, each with their own feed.

**Author site with rare publication announcements**:

```yaml
posts:        { feeds: { enabled: true } }    # frequent — blog readers
publications: { feeds: { enabled: true } }    # rare — only fires on new books
```

The publications feed entries are infrequent (one per book release), so subscribers get a near-zero-noise notification stream.

**Just blogging, no other streams**: leave the defaults. `/feed.xml` works as it always did.

## What this doesn't do

- **No combined "everything" feed.** If you want one stream that aggregates posts + photos + publications, you'd need a custom build step. We don't ship one — use cases are narrow.
- **No category-filtered feeds** (e.g., "only photos from Syria"). That'd require generating `/country/syria/feed.xml` per taxonomy term — a much bigger feature. Most users use the related-items block on the show pages instead.
- **No Atom format.** RSS 2.0 + JSON Feed cover ~99% of feed readers. Atom is a third format; we don't ship it. If a reader doesn't support either of ours, it's so old it probably doesn't run anyway.

## Heads-up: feed entry frequency

Photo galleries can produce *frequent* feed updates if you publish a photo a day — that's 30 entries per month per subscriber's reader. Some readers love that ("river of news"); some prefer digests. Abqari ships "every photo = one feed entry" — the simple, predictable choice. If you want weekly digests, you'd build that yourself or use a managed digest service.

---
title: Co-locate images with content (bundle pattern)
description: Drop images next to the markdown they belong to. Renaming or deleting a post takes its assets with it; URLs are predictable.
---

# Co-locate images with content (bundle pattern)

Two places where images live in an Abqari site:

- **Site-wide** — logo, favicons, OG fallback. These belong in `public/`.
- **Per-content** — book covers, story heroes, post inline images. These live in the content's own directory.

The second is where most of your images go. Co-locate them with the markdown that uses them, not in a flat `public/img/` dump.

## Why

```
content/posts/2026-09-12-vientiane/
├── index.md
├── hero.jpg
├── street-vendor.jpg
└── morning-market.jpg
```

When you rename `vientiane` to `laos-trip`, the directory rename takes the images with it — no broken links to chase. When you delete the post, the images go with it — no orphans in `public/img/`. When you read the markdown, you can see exactly which images it depends on.

The URLs come out predictable too: `/posts/vientiane/hero.jpg`, `/posts/vientiane/street-vendor.jpg`. Reference them in your markdown by absolute path or by basename — Abqari rewrites both at build time.

## How

The pattern is **bundle-style content**: each post / book / story is a directory with `index.md` plus its assets, instead of a flat `<slug>.md` file.

For collections that already use bundles (the default for `posts`, `photos`):

```
content/posts/2026-09-12-vientiane/
├── index.md            ← the post body
├── hero.jpg            ← image
└── morning-market.jpg
```

For collections you've configured `bundle: false` (flat files), flip them on:

```yaml
# config/site.yml
collections:
  stories:
    enabled: true
    source: content/stories
    permalink: /stories/:slug/
    layout: story
    # bundle: true is the default — every story is its own directory.
```

Then convert the existing flat files:

```
content/stories/the-kabul-assignment.md          ← was

content/stories/the-kabul-assignment/            ← is now
├── index.md
├── kabul.jpg
└── kabul-market.jpg
```

In the markdown body, reference the images by absolute URL:

```markdown
<figure class="story-image">
  <img src="/stories/the-kabul-assignment/kabul-market.jpg" alt="Kabul market">
</figure>
```

## Folio book overrides

The same pattern works for content overrides on Folio-fed pages. When Folio is configured, Abqari auto-registers `books`, `bundles`, and `series` as bundle collections. Drop a hero image alongside the override:

```
content/books/the-russia-assignment/
├── index.md            ← override frontmatter + prose
└── hero.png            ← extra hero image
```

The image lands at `/books/the-russia-assignment/hero.png` in the build output and you reference it in frontmatter:

```yaml
---
title: "The Russia Assignment"
hero_image: /books/the-russia-assignment/hero.png
---
```

## What stays in public/

Images that aren't tied to a specific post belong in `public/`:

- `public/img/logo.png` — site logo, header, OG fallback
- `public/favicon-32x32.png`, `public/apple-touch-icon.png`, etc. — favicons
- `public/img/og-default.jpg` — default Open Graph image when a page has no specific one

`public/` is a passthrough — files there are copied verbatim into `_site/` with no fingerprinting or rewrite. That's the right shape for assets that don't need versioning.

## Migration sketch

If you currently have a flat `assets/img/` (Jekyll-style) and want to migrate:

1. For each post that uses an image, move the image into the post's bundle directory.
2. Update the markdown body — change `/assets/img/foo.jpg` to `/posts/<slug>/foo.jpg`.
3. Delete `assets/img/` once empty.
4. Anything left over (logos, favicons, defaults) → move to `public/`.

The audit (`bin/audit`) flags broken image links — run it after the migration to catch anything you missed.

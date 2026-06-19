---
title: Show "Up next" below a blog post
description: A single-card link to the next chronologically-newer post, rendered below the article body. Reuses your blog index's card style for visual consistency.
---

# Show "Up next" below a blog post

Adds a single "Up next" card below each post body, linking to the chronologically-newer post in the same collection. The newest post in the archive shows no card — there is no "next." Sits above the related-items block when both are enabled.

```
┌──────────────────────────────────┐
│ Article body                     │
│ ...                              │
└──────────────────────────────────┘

──────────────────────────────────
Up next
┌──────────────────────────────────┐
│ Writing in Markdown              │
│ May 8, 2026 · 3 min read         │
│ A short description.             │
└──────────────────────────────────┘

──────────────────────────────────
Related
┌─────────┐ ┌─────────┐ ┌─────────┐
│  card   │ │  card   │ │  card   │
└─────────┘ └─────────┘ └─────────┘
```

## Default

```yaml
# config/site.yml
collections:
  posts:
    next:
      enabled: true        # set false to suppress
```

That's the entire config. The card uses your blog index's card style — including all the `index.show_*` toggles (description, reading time, tags) you already have configured. So if you've turned reading time off on the blog index, the "Up next" card won't show it either. One source of truth for "what does a post card look like."

## How "next" is determined

Posts in a collection are ordered newest-first. "Next" means the post chronologically *newer* than the one being viewed:

- Reading the second-newest post → next is the newest
- Reading the newest post → no card (there is no newer one — and a card pointing to an *older* post would contradict "Up next")
- Only one post in the collection → no card

This is the standard blog convention. If you'd rather "next" mean "the post written before this one" (older), edit the helper in `lib/abqari/site.rb` — it's three lines.

## Disabling on a single post

Add `next: false` to that post's front matter. Skipping the partial render is up to you to wire — easiest is a one-line conditional in `_next_item.html.erb`:

```erb
<% if page.frontmatter['next'] != false %>
  ...existing content...
<% end %>
```

Most users won't need this; it's only useful for landing pages that masquerade as posts.

## Wiring it into other collections

Photos and publications also benefit from "next" navigation, but they're not wired by default — different collections have different card shapes (photo cards lead with images, publication cards lead with covers). To enable for photos, add the partial render to `app/views/layouts/photo.html.erb` above the related items render, and add `next: { enabled: true }` to `collections.photos` in config. The helper (`site.next_in_collection(page)`) already works for any dated collection.

## What this is not

- **Not pagination.** Pagination is for index pages (`/blog/page/2/`). "Up next" is per-post navigation between adjacent items.
- **Not breadcrumbs.** Doesn't show where you've been.
- **Not "next in series".** That's the related-items block when `match_by` includes `series`.

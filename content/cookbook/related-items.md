---
title: Show related items below a post / photo / book
description: Configurable related-items block at the bottom of every show view, ranked by tag / series / country overlap. Per-collection toggles for on/off and item count.
---

# Show related items below a post / photo / book

Each post, photo, and publication can have a "Related" block at the bottom — items from the same collection that share tags, series, country (or any other front-matter field). Abqari ranks candidates by overlap and shows the top N.

Wired in by default. Configurable per collection.

## Default behaviour

```yaml
# config/site.yml
collections:
  posts:
    related:
      enabled: true
      limit: 3
      match_by: tags
  photos:
    related:
      enabled: true
      limit: 3
      match_by: [series, country, tags]   # earlier fields weight more
  publications:
    related:
      enabled: true
      limit: 3
      match_by: tags
```

Each show view (`/posts/<slug>/`, `/photos/<slug>/`, `/publications/<slug>/`) renders the `_related_items` partial below the article. If there are no items in the same collection sharing any of the `match_by` fields with the current page, the section renders nothing — no padding with unrelated content.

## How ranking works

For every other item in the same collection, Abqari counts how many terms it shares with the current page on each `match_by` field. When `match_by` is a list, earlier fields weight more — so for photos, a candidate that matches `series` outranks one that matches only `country`.

Pages with zero overlap on any field are excluded. Ties are broken by date (newest first).

## "Show all N" overflow

When the total number of related items exceeds the visible `limit`, the show view automatically renders a "Show all N related items" link below the visible block. The link goes to an auto-generated `/<source url>related/` index page that lists every related item in score order.

Example: a post with 12 tag-matching neighbours and `limit: 3`:

- Show view renders 3 cards + the link `Show all 12 related items`
- `/posts/<slug>/related/` is generated, listing all 12

For pages where the total is `≤ limit`, no link is shown and no index page is generated — the visible block already covers everything. This is automatic; you don't configure it separately.

## Common changes

**Hide related on a noisy collection** (e.g., your photos collection has 200+ items and "related by tag alone" matches too much):

```yaml
photos:
  related:
    enabled: false
```

**Show more items**:

```yaml
posts:
  related:
    limit: 6
```

**Match on a custom front-matter field** — say you tag publications with a `category:` instead of `tags:`:

```yaml
publications:
  related:
    match_by: category
```

**Match on multiple fields with priority**:

```yaml
posts:
  related:
    match_by: [series, tags]   # series-shared posts rank above tag-shared posts
```

## Per-page override

Pass `limit:` or `match_by:` directly to the partial when rendering from a custom layout:

```erb
<%= render 'partials/related_items', limit: 6, match_by: %w[tags] %>
```

This overrides the collection's config for that one page. Useful for a "more from this author" block on bigger publications, or a "more from this country" block on a featured photo.

## What it doesn't do

- **No cross-collection matching.** Posts can't be related to photos, even if they share tags. Each show view only pulls from its own collection.
- **No semantic similarity.** Ranking is exact-match overlap. It doesn't use embeddings or look at body content. If you write a post about Ruby and another about Crystal, they won't be related unless they share a literal tag.
- **No "popular" or "trending".** Static sites don't have visit data; ranking is purely by metadata overlap.

For semantic / content-based related items, you'd integrate something like an embedding service at build time and write the matches into front matter. That's outside Abqari's default scope.

## Disabling for a single page

If a specific page shouldn't show related items, the easiest path is to override its layout. Either:

- Set `layout: post-no-related` (or similar) in the page's front matter, with a copy of `post.html.erb` that omits the partial line.
- Or add a `frontmatter['no_related'] == true` check inside the partial (one-line edit).

The second is cleaner if you only need it occasionally — leaves the main layout unchanged.

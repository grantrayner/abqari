---
title: Collections and taxonomies
published: true
description: Posts, photos, publications, workshops, cookbook — plus tags, custom taxonomies, and pagination.
tags: [collections, taxonomies, configuration]
cover: svg
---

A **collection** is a named group of content with shared output
rules — a source directory, a URL prefix, a default layout, an
optional RSS / JSON feed, and a small set of display knobs for
the listing page and the detail page.

Abqari ships with five collections out of the box:

| Collection | Source | URL | Layout |
|---|---|---|---|
| `posts` (aliased to `guides` on this site) | `content/posts/` | `/guides/` | `post` |
| `cookbook` | `content/cookbook/` | `/cookbook/` | `post` |
| `photos` | `content/photos/` | `/photos/` | `photo` |
| `publications` | `content/publications/` | `/publications/` | `publication` |
| `workshops` | `content/workshops/` | `/workshops/` | `workshop` |

Plus the `bundles` and `series` collections that group items
across the other collections — covered in
[Bundles and series](/guides/bundles-and-series/).

## Configuring a collection

Each collection has a block under `collections:` in
`config/site.yml`. Defaults work out of the box; the block exists
to override.

```yaml
collections:
  posts:
    enabled: true
    slug: guides              # URL prefix; default is the collection name
    layout: post              # singularized from slug if unset; pin to override
    bundle: true              # content/<col>/<slug>/index.md + colocated assets
    pagination:
      per_page: 10
    index:                    # the listing page (/guides/)
      cover: photo
      show_date: true
      show_description: true
      show_reading_time: true
      latest_count: 8
    archive:
      enabled: true           # /guides/archive/ with the full list
    show:                     # the detail page (/guides/<slug>/)
      cover: photo
      toc:
        enabled: true
        min_headings: 3
        levels: [2, 3]
      next:
        enabled: true
      related:
        enabled: true
        limit: 3
        match_by: tags
        show_image: true
    feeds:
      enabled: true           # /guides/feed.xml + /guides/feed.json
```

**Slug aliasing** lets you keep `content/posts/` on disk but
publish at any URL prefix — this site uses `/guides/` for the
narrative collection and `/cookbook/` for a second posts-style
collection. The layout is singularized from the slug by default
(`guides` → `guide`); pin `layout: post` if no matching layout
exists.

**Flat vs bundle**. `bundle: true` (default) expects
`content/<col>/<slug>/index.md` with optional colocated assets in
the same directory — see [Co-locate images with content](/cookbook/co-located-images/).
`bundle: false` switches to flat single-file pages
(`content/<col>/<slug>.md`); useful for short reference-style
content like the cookbook.

## Custom collections

To add your own (recipes, talks, case studies), extend the
`collections:` block:

```yaml
collections:
  talks:
    enabled: true
    source: content/talks
    permalink: /talks/:slug/
    layout: talk              # add app/views/layouts/talk.html.erb
    bundle: true
    pagination:
      per_page: 10
    related:
      enabled: true
      match_by: tags
```

If you only need a renamed built-in (e.g. "stories" for posts,
"books" for publications, "training" for workshops), prefer
`slug:` on the built-in over a custom collection — the layout,
RSS feed, JSON Feed, sitemap, and related-machinery are wired up
for free.

## Taxonomies

A **taxonomy** is a tag-like classification. Abqari auto-generates
an index page for each unique term — `/tags/ruby/`, `/series/light-notebooks/`,
`/country/Syria/`, etc.

```yaml
taxonomies:
  tags:                       # the default; included implicitly
    permalink: /tags/:slug/
    layout: tag
  countries:
    field: country            # scalar frontmatter, single value per page
    permalink: /country/:slug/
    layout: country_index
  posts_series:
    field: series
    collection: posts         # scope: only posts
    permalink: /guides/series/:slug/
    layout: series_index
```

Pages opt in by setting the field in frontmatter:

```yaml
---
title: Building with Abqari
tags: [ruby, ssg]
country: Syria
series: Inside Abqari
series_position: 3
---
```

The `collection:` key scopes a taxonomy to one collection so a
photo and a post both tagged "travel" land on `/tags/travel/`
together, while `posts_series` and `photos_series` stay
independent.

Inside the auto-generated layout, `page.taxonomy`, `page.term`,
and `page.posts` give you the taxonomy name, the term, and the
matching pages.

## Pagination

Pagination is opt-in per page; the site-wide default lives in
`config/site.yml`.

| Frontmatter | Behaviour |
| --- | --- |
| `paginate: true` | Use `pagination.per_page` from config (default 10) |
| `paginate: 25` | Override — 25 items per page on this page only |
| `paginate: false` (or absent) | No pagination |
| `paginate_collection: photos` | Override which collection to paginate (otherwise inferred from layout) |

In the layout, `page.paginator` is non-nil when pagination is
active and exposes:

- `paginator.posts` — this page's slice
- `paginator.page` / `paginator.total_pages`
- `paginator.first?` / `paginator.last?`
- `paginator.next_url` / `paginator.prev_url`

The shipped `_pagination` partial wraps this; most call sites
just `<%== render 'partials/pagination', paginator: page.paginator %>`.

## Archive mode

For collections with many items, `archive.enabled: true`
splits the listing into:

- **Front index** (`/guides/`) — curated landing with the latest
  N items as full cards.
- **Archive** (`/guides/archive/`) — compact title + date rows,
  paginated.

The setup needs two pages: `content/posts/index.md` (the curated
front) and `content/posts-archive.md` (the archive — note the
hyphen, kept outside `content/posts/` so it doesn't become a
post itself). Both ship pre-wired in the engine fixture.

## Disabling a collection

`enabled: false` toggles a collection off without deleting any
files. The pages stay on disk but never render, never appear in
navigation, never join feeds or sitemaps. See
[Turn a collection off without deleting content](/cookbook/disable-collection/)
for the full pattern.

## See also

- [Slug aliasing](/guides/slug-aliasing/) — rename a built-in collection's URL prefix without forking the layout
- [Bundles and series](/guides/bundles-and-series/) — group items across collections
- [Per-collection RSS + JSON Feed](/cookbook/per-collection-feeds/) — separate feeds for each collection

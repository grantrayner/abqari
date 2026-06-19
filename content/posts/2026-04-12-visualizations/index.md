---
title: D3 visualizations of your content
published: true
description: Build-time-generated tag and topic visualizations of your site's content — D3 in the browser, no server.
tags: [visualizations, d3, data]
cover: svg
---

Off by default. When enabled, Abqari generates D3-powered
visualizations of your tags and posts **at build time** — JSON
data plus an HTML page per chart. The page loads vendored D3 (no
third-party requests) and renders entirely client-side.

This is unusual for a static site generator. Hugo, Jekyll, Astro
— none of them ship anything like this. The unique fit is that
Abqari already knows your full post and tag graph at build time,
so we can pre-render the chart data into static JSON and let D3
do the rest in the browser.

## What ships

Three visualizations, each independently config-toggleable:

| Viz | What it shows | URL |
| --- | --- | --- |
| **Tag Bubble** | Circle pack of all tags, area proportional to post count | `/visualizations/tag-bubble/` |
| **Tag Co-occurrence** | Chord diagram of which tags appear together on the same posts | `/visualizations/tag-cooccurrence/` |
| **Topic Constellation** | Force-directed graph: each post a node, links connect posts that share at least one tag | `/visualizations/topic-constellation/` |

## Enabling

In `config/site.yml`:

```yaml
visualizations:
  tag_bubble: true
  tag_cooccurrence: true
  topic_constellation: true
```

Set any to `false` (or omit) to skip that viz. When all three are
off, the entire feature is dormant — no JSON written, no pages
generated, no D3 in the build.

## How it works

At build time:

1. `Visualizations#write_data` walks `site.posts` and
   `site.posts_by_term('tags')` to compute the chart data for
   each enabled viz, then writes:
   - `_site/visualizations/tag-bubble.json`
   - `_site/visualizations/tag-cooccurrence.json`
   - `_site/visualizations/topic-constellation.json`
2. A `VizPage` is added to `Site#generated_pages` for each
   enabled viz, which renders through the normal pipeline into
   `_site/visualizations/<name>/index.html`.
3. Vendored D3 is copied to `_site/assets/d3/d3.v7.min.js`.

At runtime in the browser:

1. Visitor opens `/visualizations/tag-bubble/`.
2. The page loads `/assets/d3/d3.v7.min.js` and the matching viz
   JS module from `/assets/js/`.
3. The viz module `fetch`es the JSON and renders into
   `#viz-container`.
4. Hover for tooltips; click a tag bubble to navigate to that
   tag's index page.

## Tuning

**When each viz is useful**:

- **Tag Bubble** wants 10+ tags to look interesting. Sites with 3
  tags get 3 big circles.
- **Tag Co-occurrence** needs posts with multiple overlapping
  tags. Solo tags (no overlap with anything) are filtered out
  automatically.
- **Topic Constellation** works on any blog with a few posts and
  tags. Even small sites produce something engaging — and it's
  fun to drag.

**Performance**. D3 is ~280 KB minified. To keep that out of every
page, **D3 only loads on the three viz pages**, not site-wide.
Your home page, posts, and other content stay JS-free.

**Theming**. The visualizations use `currentColor` for SVG strokes
and text labels, so light/dark theme switches flow through
automatically. Fill colours come from a fixed 12-colour palette
designed to work in both modes. Change the palette by editing
the `PALETTE` array at the top of each `app/assets/js/viz-*.js`
file.

**Linking from your site**. The viz pages aren't added to the nav
automatically — they're meant to be discovered or linked from a
curated spot:

```erb
<a href="/visualizations/topic-constellation/">Explore the topic graph →</a>
```

`site.visualizations.enabled_visualizations` gives you the list
of enabled vizes as an array if you want to render a programmatic
"Explore" page.

## Privacy

D3 is vendored under `vendor/d3/d3.v7.min.js` and served from your
own origin. The strict default CSP (`script-src 'self'`) covers
it without modification. The visualizations make no third-party
requests at any point.

## Limitations

- **One taxonomy.** The visualizations work off `tags` only —
  they don't (yet) honour custom taxonomies declared via
  `taxonomies:`.
- **No date filtering.** Topic Constellation includes all posts;
  there's no "show me only the last year" toggle. The data is in
  the JSON though, so writing your own filtered view is
  straightforward.
- **Posts without tags** don't appear in Tag Bubble or Tag
  Co-occurrence. They appear in Topic Constellation as isolated
  nodes (greyed-out).

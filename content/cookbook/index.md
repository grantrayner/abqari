---
title: Cookbook
published: true
description: Short recipes for common Abqari tasks — one task per page, copy-paste config and code.
layout: posts_index
permalink: /cookbook/
paginate: false
nav:
  order: 3
  label: Cookbook
---

Short, focused recipes for the questions that come up over and
over. Each entry covers one task — drop in the config, copy the
snippet, ship. For deeper walkthroughs of the same features see
the [guides](/guides/).

## Analytics

- [Add Plausible analytics](/cookbook/plausible/) — privacy-friendly, no cookie banner, one config line
- [Add GoatCounter analytics](/cookbook/goatcounter/) — free / self-hostable alternative
- [Add Disqus comments](/cookbook/disqus/) — when you really want a comment thread

## Privacy & SEO

- [Block AI training scrapers](/cookbook/block-ai-scraping/) — robots.txt entries for OpenAI, Anthropic, Google-Extended, Common Crawl, and 15+ others

## Content patterns

- [Co-locate images with content (bundle pattern)](/cookbook/co-located-images/) — keep post / book / story images alongside the markdown that uses them
- [Choose what appears on index cards](/cookbook/index-cards/) — toggle description / reading-time / tags / camera / ISBN per collection
- [Show related items below a post](/cookbook/related-items/) — auto-ranked by tag / series / country overlap
- [Show "Up next" below a blog post](/cookbook/up-next/) — single-card link to the chronologically-newer post
- [Feature one item on the home page](/cookbook/featured-item/) — pin a specific publication, post, or photo
- [Per-collection RSS + JSON Feed](/cookbook/per-collection-feeds/) — separate feeds for blog, photos, publications
- [Run ERB in markdown content](/cookbook/erb-in-markdown/) — `erb: true` per page enables dynamic values, helper calls, and inline partial renders
- [Turn a collection off without deleting content](/cookbook/disable-collection/) — `enabled: false` toggles photos, publications, or any collection without losing files

## Photo galleries

- [Add a photo carousel](/cookbook/photo-carousel/) — slideshow view of any collection
- [Show a random photo on the home page](/cookbook/random-photo/) — discovery-friendly alternative to "latest"

## Personal sites

- [Build a single-page portfolio](/cookbook/personal-site/) — CV / portfolio / landing page with no posts

## Theming

- [Build your own theme](/cookbook/custom-theme/) — start from the `custom` theme (a fully-commented copy of `minimal`)
- [Theme primitives — tokens, containers, breakpoints](/cookbook/theme-primitives/) — shared CSS variables for spacing, container widths, radii
- [Add icons (Font Awesome / Bootstrap Icons)](/cookbook/icons/) — drop the dist into `public/`, toggle one config line
- [Use Bootstrap from a CDN](/cookbook/bootstrap-cdn/) — skip the vendored CSS for quick setup

## Deploy

- [Deploy to Cloudflare Pages](/cookbook/cloudflare/) — free tier, unmetered bandwidth, the recommended host

## Migration

- [Migrate from Jekyll](/cookbook/jekyll/) — port a Jekyll site to Abqari

## Want more recipes?

If you've solved a common problem and want to share, open a PR adding
a recipe under `content/cookbook/`. The format is short — assume the
reader has the [quickstart](/guides/quickstart/) under their belt and
just needs the steps.

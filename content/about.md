---
title: About
published: true
description: A Ruby static site generator for working authors — posts, photos, publications, workshops, and the IndieWeb out of the box.
layout: about
nav:
  order: 99
---

Abqari is a static site generator for Ruby. It's built around the four
content types working authors actually publish — long-form **writing**
(posts), **photos** and image-led notes, **publications** (books and
other catalogue items), and **workshops** or other services that need
structured metadata. Each is a first-class collection with its own
layout, frontmatter shape, and configuration surface.

This site is itself built with Abqari. Every section is a working
example of the corresponding feature; the
[source for this site](https://github.com/grantrayner/abqari) is the
same code you'd use to build your own.

## What ships in the box

- **Four built-in collections** — posts, photos, publications, workshops — plus your own under `collections:`.
- **Themes as tokens, not rules.** Five hand-tuned themes (`minimal`, `magazine`, `notebook`, `sand`, `bootstrap`), `custom` for starter customisation, `none` for bring-your-own. Palette + density via CSS variables.
- **Image pipeline.** libvips-backed AVIF + WebP variants with CLS-safe responsive `<picture>` rewriting.
- **Folio storefront integration** for sites that sell books — manual frontmatter and auto-fetched data coexist in the same collection.
- **Content importers** — `bin/import substack | ghost | jekyll <source>` brings posts from another platform's export into your `content/` tree.
- **IndieWeb-native** — microformats2, webmention send/receive via webmention.io, Bridgy Fed for ActivityPub following.
- **POSSE syndication** to Mastodon and Bluesky on each build, with idempotent retry-on-failure tracking.
- **`bin/audit`** for links, SEO, a11y, privacy, and CVE checks in one markdown report.
- **Static search via Pagefind**, JSON Feed, sitemap with image extension, JSON-LD Article schema, Open Graph + Twitter cards, per-environment robots.

See the [README](https://github.com/grantrayner/abqari#readme) for the
full surface — or browse the [guides](/guides/) and [cookbook](/cookbook/)
for hands-on walkthroughs of each feature.

## Design principles

- **Author-trusted content.** The engine assumes the operator wrote
  the content. No sandboxed templating; no untrusted markdown gate.
- **Sensible defaults.** Sites work out of the box. Configuration is
  for opting *out* of behaviour, not opting *in*.
- **Real Ruby in layouts.** ERB partials run real Ruby via Erubi's
  auto-escape. No new templating language to learn.
- **Small surface, large reach.** Three runtime gem deps:
  `commonmarker`, `erubi`, `ruby-vips`. Plus standard library.
- **One file at a time.** Every config knob has an inline comment
  explaining what it does and what changes if you flip it. `bin/audit`
  surfaces what's drifting.

## Project status

Abqari is on `v1.0.0` — the engine is feature-complete for the
four content types it targets. Distributed via RubyGems
(`gem install abqari`) and as a git source. See the
[CHANGELOG](https://github.com/grantrayner/abqari/blob/main/CHANGELOG.md)
for every shipped feature with dates and rationale.

## Source &amp; contributing

- **Repository:** [github.com/grantrayner/abqari](https://github.com/grantrayner/abqari)
- **README:** setup, project structure, full feature surface
- **CHANGELOG:** every shipped change, dated, with rationale
- **CONTRIBUTING:** how to file issues and submit changes
- **License:** MIT

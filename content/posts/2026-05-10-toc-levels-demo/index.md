---
title: TOC heading-level demo
published: true
date: 2026-05-10
description: "Demonstrates the `levels:` config on the auto-TOC — this post has h2, h3, and h4 headings, but only h2 + h3 appear in the contents list because the engine default is `levels: [2, 3]`."
tags: [demo]
---

This post mixes h2, h3, and h4 headings to make the engine default
visible: with `collections.posts.show.toc.levels: [2, 3]` (the engine
default) the TOC lists the h2 + h3 entries and silently drops the h4
subheadings.

To include h4 in your own site's TOC, set `levels: [2, 3, 4]` in
`config/site.yml`. To show only top-level sections, set `levels: [2]`.

## First section

Body text under the first h2.

### A subsection of the first

Body text under the h3.

#### A deeper sub-subsection

Body text under the h4 — this heading is intentionally absent from
the TOC under the default `levels: [2, 3]`.

## Second section

Another top-level section.

### Another subsection

And its h3 entry, which DOES appear in the TOC.

## Third section

A final top-level section, to push the post past the default
`min_headings: 3` floor.

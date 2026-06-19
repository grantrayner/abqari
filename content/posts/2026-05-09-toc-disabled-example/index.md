---
title: A post that opts out of the table of contents
published: true
date: 2026-05-09
description: "Demonstrates the `toc: false` frontmatter override — this post has enough headings to qualify for an auto-TOC, but suppresses it."
tags: [demo]
toc: false
cover: svg                # also demonstrates the cover enum —
                          # the listing card renders a decorative
                          # initial-tile SVG (initial: A, slug-
                          # hashed gradient) instead of the basic
                          # flat-tint placeholder.
---

This post carries `toc: false` in its frontmatter. Even with three or
more h2 / h3 headings, the auto-TOC suppresses itself — the
frontmatter override always wins over the collection default in
`config/site.yml`.

## First heading

A paragraph under the first heading so the content reads naturally.

## Second heading

Another section.

## Third heading

A third section — enough headings to clear the `min_headings: 3`
default. The TOC is suppressed by the `toc: false` flag, not by
falling under the threshold.

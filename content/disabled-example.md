---
title: Disabled example
description: "This page is checked into the repo but turned off via the `enabled: false` frontmatter flag. Useful for parking content without deleting it."
enabled: false
nav: ~
sitemap: false
---

# Disabled example

This text never reaches the build because the frontmatter has `enabled: false`.
Flip to `enabled: true` (or remove the line) to ship it.

Compared with `published: false` — drafts render in development with a banner
so you can preview unpublished work; `enabled: false` is hidden in **both**
dev and prod, with no banner. Use it when you want a page parked, not in
progress.

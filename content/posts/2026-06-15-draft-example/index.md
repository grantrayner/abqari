---
title: A draft post
description: An example of a post that's still in progress.
image: hero.svg
tags: []
published: false
---

This is what a draft looks like. It only renders in development (`bin/serve`) so
you can preview it without shipping. Production builds skip drafts entirely.

The amber **Draft** banner above is your reminder. When you're ready to publish
this post, change `published: false` to `published: true` in the front matter.
The banner goes away and the post starts appearing on `/posts/`, in feeds,
and in the sitemap.

A few notes on workflow:

- **Tag drafts as you would any other post.** Use real subject tags (`ruby`,
  `static-sites`, etc.) — drafts are determined by `published: false`, not by
  a `drafts` tag. Tag taxonomies stay clean.
- **Force a production preview.** `ABQARI_INCLUDE_DRAFTS=true bin/build` builds
  the production output *with* drafts, useful for catching issues that only
  show up under real CSP / minification / asset fingerprinting.
- **Hide drafts in dev too.** Set `drafts.show_in_development: false` in
  `config/site.yml` if you want to see what production will look like while
  you're previewing.

---
title: A future-dated post
description: An example of a post scheduled to publish in the future.
image: hero.svg
tags: []
---

This is what a scheduled post looks like. The date in the filename
(`2099-01-01-future-example`) and/or `date:` in the front matter is later than
"now" — so production builds skip it until time catches up.

The blue **Scheduled** banner above is your reminder, with the exact moment the
post will publish (in the timezone configured in `config/site.yml`, default UTC)
and how far away that is.

A few notes on workflow:

- **Tag scheduled posts as you would any other post.** Use real subject tags
  (`ruby`, `releases`, etc.) — scheduled posts are determined by their date,
  not by a `scheduled` tag. Tag taxonomies stay clean.
- **Timezone matters.** A naked date like `2026-06-15` means midnight in your
  configured timezone, on every build, regardless of where it runs. Add an
  explicit offset (`2026-06-15T08:00:00+08:00`) if you want a specific
  wall-clock moment in another zone.
- **You still have to rebuild.** Static sites only update on rebuild — a post
  scheduled for June 15 won't actually appear until the next build runs after
  June 15. Set up a cron / scheduled CI workflow if you want automatic publishing.
- **Preview future posts in production.** `ABQARI_INCLUDE_FUTURE=true bin/build`
  builds with future posts included, useful for catching issues that only show
  up under real CSP / minification before they auto-publish.

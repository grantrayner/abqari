---
title: Upgrading Abqari
published: true
description: Bumping the engine version, handling breaking changes, and recovering from a bad upgrade.
tags: [upgrading, maintenance, gem]
cover: svg
---

Abqari is distributed as a RubyGem. Upgrading is `bundle update
abqari` plus a quick verification pass.

## The simple case

```bash
bundle update abqari
bundle exec bin/test
bundle exec bin/audit --strict
bundle exec bin/build
```

If all four pass, you're done. Commit:

```bash
git commit -am "Update Abqari to vX.Y.Z"
```

## What might change between versions

- **Layouts and partials** — when a layout under `app/views/`
  changes, the engine ships the new version inside the gem. Your
  site picks it up automatically unless you've copied that layout
  into your own `app/views/` (the site-first / engine-fallback
  resolution prefers yours).
- **Config schema** — `bin/audit` warns on unknown top-level keys
  in `config/site.yml`, so a key that's been renamed surfaces on
  the next audit run. Set `ABQARI_STRICT_CONFIG=true` to fail the
  build instead of warning.
- **Default values** — minor releases may change defaults
  (e.g. the cover slot default flipping from `photo` to
  `photo_or_svg`). The CHANGELOG lists every default change.

The CHANGELOG is the canonical source for what changed and why:

```bash
gem changelog abqari       # or open CHANGELOG.md on GitHub
```

## Pinning to a known-good version

If a release breaks something, pin to the last working version:

```ruby
# Gemfile
gem 'abqari', '0.3.1'      # or whatever last worked
```

Then `bundle install`. File an issue with the breakage so it gets
into the next patch.

## Customising the engine

The gem ships layouts, partials, themes, icons, and the structural
`_common.css`. Override any of them by dropping a same-named file
in your site's tree:

| To override... | Drop at |
| --- | --- |
| `app/views/layouts/post.html.erb` | `app/views/layouts/post.html.erb` (in your site) |
| `app/views/partials/_head.html.erb` | `app/views/partials/_head.html.erb` |
| `themes/minimal/css/app.css` | `themes/minimal/css/app.css` |
| `app/icons/rss.svg` | `app/icons/rss.svg` |

`Site#find_in_paths` resolves "site first, engine fallback" — your
copy wins, but only for the file you copied. The engine's other
files keep coming from the gem, so a minor upgrade still picks
up most fixes.

When you customise a layout, you commit to maintaining its
divergence from upstream. Watch the CHANGELOG for layout changes
and port new features into your local copy if you want them.

## Breaking changes

Pre-1.0, minor bumps (0.X.0 → 0.Y.0) MAY carry breaking changes.
The CHANGELOG calls them out in a **Changed** section with the
migration path. Recent examples:

- `0.3.0`: `posts.archive.enabled` defaults to `true` (was
  implicit `false`). Old sites that don't want the archive page
  need to set it explicitly.
- `0.4.0`: `show_image: true/false` in `posts.show` replaced by
  the `cover:` enum (`photo` / `photo_or_svg` / `svg` / `none`).

Patch bumps (0.X.Y → 0.X.Y+1) are bug fixes only and should be
drop-in safe.

## Recovering from a bad upgrade

If something breaks after `bundle update abqari` and you need to
roll back fast:

```bash
git checkout HEAD~1 -- Gemfile.lock
bundle install
```

Then file an issue with the breakage and a reproduction.

Your content / config / data are never touched by an Abqari
upgrade — they live in your repo, not the gem. The worst case is
a render error you can fix by pinning the previous version and
working from there.

## See also

- [Quickstart](/guides/quickstart/) — fresh install
- [Deploying](/guides/deploying/) — production deployment
- [CHANGELOG](https://github.com/grantrayner/abqari/blob/main/CHANGELOG.md) — every shipped change, dated, with rationale

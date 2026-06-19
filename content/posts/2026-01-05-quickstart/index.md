---
title: Quickstart
published: true
description: Install Abqari, scaffold a site, and ship your first post in about ten minutes.
tags: [introductions, ruby, getting-started]
cover: svg
---

If you've used Jekyll, Hugo, or Eleventy, the shape will be
familiar. If you haven't, no prior Ruby experience is required —
this is a copy-paste walkthrough from "nothing installed" to
"site live on my laptop" in roughly ten minutes.

For the full beginner-friendly version with terminal hand-holding,
see the [README's Quickstart](https://github.com/grantrayner/abqari#quickstart).
The condensed version is below.

## Requirements

- **Ruby 3.3 or newer.** Check with `ruby --version`.
  - macOS: `brew install ruby` (Homebrew prints the line to add to
    `~/.zshrc` to put the new Ruby on PATH).
  - Ubuntu / Debian: `sudo apt install ruby-full`.
  - Windows: install [WSL](https://learn.microsoft.com/windows/wsl/install)
    and follow the Ubuntu instructions inside it.
- **libvips** for the image pipeline. `brew install vips` /
  `apt install libvips42 libheif1` / `apk add vips`. The build falls
  back to shell-out to `vips` or `magick` CLI if the FFI binding is
  missing — just slower per image.

## Install the gem

```bash
gem install abqari
```

The `abqari` executable lands on PATH; check with `abqari version`.
You should see `abqari 0.4.0` or newer.

## Scaffold a site

```bash
abqari new mysite
cd mysite
```

This creates a fresh site under `mysite/` with example content,
config, and `bin/` scripts wired up. Pass `--blank` for a skeleton
without the example posts. The starter ships with two collections
out of the box — a `posts`-aliased-as-`guides` collection for
longer narrative writing, and a `cookbook` collection for short
recipes; both are configurable in `config/site.yml`.

## Write your first post

```bash
bin/new post "Hello from my new site"
```

Creates a new bundle directory under `content/posts/` with a dated
slug and sensible frontmatter. Open the `index.md` and write.

## See it live

```bash
bin/serve
```

Browse to `http://localhost:4000`. The dev server watches your
content for changes and pushes a Server-Sent Event so the browser
reloads automatically (CSS-only edits hot-swap without a full
reload).

## Build for production

```bash
bin/build
```

Output lands in `_site/`. Deploy anywhere static: Cloudflare Pages,
Netlify, GitHub Pages, your laptop's `python3 -m http.server`, the
list goes on. The companion `bin/deploy` script handles Cloudflare
out of the box; see [Deploying](/guides/deploying/) for the full
guide.

## Next steps

- [Templating with ERB](/guides/templating/) — layouts, partials, helpers
- [Collections & taxonomies](/guides/collections/) — posts, photos, publications, custom collections
- [Cookbook](/cookbook/) — short, focused recipes for common tasks
- [GitHub README](https://github.com/grantrayner/abqari#readme) — the full surface area

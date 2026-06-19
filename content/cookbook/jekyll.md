---
title: Migrate from Jekyll
description: Port a Jekyll site's content and structure to Abqari.
---

# Migrate from Jekyll

Abqari's structure is close enough to Jekyll's that most migrations take an hour or two. The core decisions are similar (markdown, front matter, layouts, post collections), but the details differ.

## Side-by-side mapping

| Jekyll | Abqari |
| --- | --- |
| `_layouts/` | `app/views/layouts/` |
| `_includes/` | `app/views/partials/` (filenames start with `_`) |
| `_data/` | `data/` (no leading underscore) |
| `_posts/2026-01-01-foo.md` | `content/posts/2026-01-01-foo/index.md` (a directory) |
| Liquid templating | ERB (real Ruby) |
| `{{ post.title }}` | `<%= post.title %>` |
| `{% include nav.html %}` | `<%= render 'partials/nav' %>` |
| `{{ content }}` | `<%= page.content %>` |
| `{{ "Hello" \| truncate: 10 }}` | `<%= truncate('Hello', length: 10) %>` |
| `_config.yml` | `config/site.yml` |
| `assets/` | `app/assets/` (or `themes/<theme>/`) |

## 1. Move posts to bundles

Jekyll posts are flat files. Abqari posts are directories. For each post:

```bash
cd content/posts
for post in *.md; do
  dir="${post%.md}"
  mkdir "$dir"
  mv "$post" "$dir/index.md"
done
```

## 2. Move post images

If your Jekyll posts referenced images via `/assets/images/foo.jpg`, those paths still work in Abqari (drop the images in `app/assets/images/`). For the bundle approach, move each post's images into its bundle directory and update the markdown to reference them by short relative name (`![alt](foo.jpg)` instead of `/assets/images/foo.jpg`).

## 3. Translate Liquid templates to ERB

Most Liquid filters have a one-to-one ERB equivalent. The big ones:

| Liquid | ERB / Ruby |
| --- | --- |
| `{{ post.title \| escape }}` | `<%= page.title %>` (ERB auto-escapes via `<%=` defaults; use `<%==` for raw) |
| `{{ "now" \| date: "%Y" }}` | `<%= local_time(Time.now, format: '%Y') %>` |
| `{{ post.content \| truncate: 200 }}` | `<%= truncate(post.content, length: 200) %>` |
| `{% for post in site.posts %}` | `<% site.posts.each do \|post\| %>` |
| `{% if post.tags contains "ruby" %}` | `<% if post.tags.include?('ruby') %>` |
| `{% include foo.html %}` | `<%= render 'partials/foo' %>` |

Layouts are nearly identical structurally — change the syntax and you're 90% there.

## 4. Translate `_config.yml`

Abqari's `config/site.yml` is similar but with key differences:

```yaml
# Jekyll
title: My Blog
description: ...
url: https://example.com
plugins:
  - jekyll-sitemap
  - jekyll-feed

# Abqari
title: My Blog
description: ...
locale: en
theme: minimal
search: true
environments:
  development:
    url: http://localhost:4000
  production:
    url: https://example.com
```

No plugin list — sitemap, feed, redirects, etc. are built in.

## 5. Translate `_data/` files

Identical concept. `data/<filename>.yml` is loaded as `site.data['<filename>']`. Move files over and update template references from `{{ site.data.foo }}` to `<%= site.data['foo'] %>`.

## 6. Re-do permalinks

Jekyll's default post permalink is `/:year/:month/:day/:title/`. Abqari's is `/posts/:slug/`. To match Jekyll:

```yaml
collections:
  posts:
    permalink: /:year/:month/:day/:slug/
```

For a wholesale migration, generate `redirect_from:` entries on each post pointing to the old Jekyll URLs so existing links don't 404:

```yaml
---
title: Old post
redirect_from:
  - /2024/01/15/old-post/
---
```

## 7. Verify

```bash
bundle exec bin/build
bundle exec bin/audit
```

The audit will catch broken internal links, missing alt text on images you copied over, and any pages with title/description issues from the migration.

## What you'll miss from Jekyll

- **GitHub Pages's free hosting with auto-build** — replace with Cloudflare Pages or Netlify (both also free for static sites).
- **The plugin ecosystem** — most Jekyll plugins solve problems Abqari already addresses (sitemap, feed, redirects, syntax highlighting). For the rest, you'll write a few lines of Ruby in a helper or template.

## What you'll gain

- **Real Ruby in templates** — no more fighting Liquid's restrictions.
- **5 gems** instead of 30+. Bundler upgrades stop being scary.
- **Built-in audit, search, image optimisation, security headers, livereload, dark mode.** Mostly things you'd hunt for plugins to do in Jekyll.
- **A repo you fully own.** No mysterious gem behavior — the engine code is in `lib/abqari/`, you can read it.

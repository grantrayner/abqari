---
title: Templating with ERB
published: true
description: Layouts, partials, and helpers — all in real Ruby via auto-escaping Erubi.
tags: [templating, ruby, erb]
cover: svg
---

Abqari uses ERB. Real Ruby in templates, no sandboxed templating
language. If you can write Ruby, you can write a template. Erubi
auto-escapes `<%= … %>` interpolations by default; the explicit
raw form is `<%== … %>`, reserved for values that are already safe
HTML (helper output, rendered partials, pre-rendered markdown).

## Layouts

Layouts live in `app/views/layouts/`. The default is
`application.html.erb`:

```erb
<!DOCTYPE html>
<html lang="<%= site.config['locale'] || 'en' %>">
<%== render 'partials/head' %>
<body>
  <%== render 'partials/nav' %>
  <main><%== page.content %></main>
  <%== render 'partials/footer' %>
</body>
</html>
```

Layouts have access to:

- `page` — the current `Abqari::Page` (frontmatter, content, url, title, …)
- `site` — the `Abqari::Site` (config, posts, taxonomies, data, …)

Pages pick their layout via frontmatter (`layout: post`), or get a
sensible default. The layouts that ship out of the box:

| Layout | Purpose |
| --- | --- |
| `application` | Default for top-level pages (about, 404, etc.) |
| `home` | The home page — modular sections pulling from each collection |
| `post` | Single-post detail page with date, reading time, TOC, related |
| `posts_index` | Listing page for the posts collection — used by both `/guides/` and `/cookbook/` |
| `posts_archive` | Compact archive list, one row per post |
| `photo`, `photos_index`, `photos_archive` | Photo collection layouts |
| `publication`, `publications_index`, `publications_archive` | Publication catalog layouts |
| `workshop`, `workshops_index` | Workshops catalog layouts |
| `tag` | Taxonomy index — used by `/tags/<slug>/`, country, series |
| `about` | About-page layout with `h-card` microformat |

Layouts can chain via frontmatter `layout: <parent>` — the inner
layout renders first, the parent wraps it via
`<%== yield_content %>`.

## Partials

Partials live in `app/views/partials/` with a leading underscore
in the filename. Render with locals:

```erb
<%== render 'partials/nav' %>
<%== render 'partials/post_card', post: post, featured: true %>
```

Locals are exposed as bare identifiers inside the partial:

```erb
<!-- _post_card.html.erb -->
<article class="<%= 'featured' if featured %>">
  <h2><%= post.title %></h2>
</article>
```

`page` and `site` are always available; partials nest freely.

The shipped partials cover the standard scaffold: `_head`, `_nav`,
`_footer`, `_post_list`, `_pagination`, `_search`, `_theme_toggle`,
`_image_gallery`, `_carousel`, `_contact_button`, `_newsletter`,
`_webmentions`, and per-feature JSON-LD partials. Edit any of
them — they're yours.

## Helpers

A standard library of view helpers ships in `lib/abqari/helpers.rb`:

| Helper | Example |
| --- | --- |
| `h(text)` | `h("a & b")` → `"a &amp; b"` |
| `truncate(text, length:, omission:)` | `truncate(post.body, length: 200)` |
| `pluralize(count, singular, plural:)` | `pluralize(2, 'post')` → `"2 posts"` |
| `local_time(time, format:)` | `local_time(post.date)` → `"1 January 2026"` |
| `time_ago(time)` | `time_ago(post.date)` → `"3 days ago"` |
| `time_until(time)` | `time_until(future)` → `"in 2 weeks"` |
| `years_since(year_or_date)` | `years_since(2002)` → integer |
| `link_to(text, url, **attrs)` | `link_to('Home', '/', class: 'nav-link')` |
| `excerpt(text, words:)` | `excerpt(post.content, words: 30)` |
| `reading_time(text, wpm:)` | `reading_time(post.body)` → `"4 min read"` |
| `slugify(text)` | `slugify('Hello World!')` → `"hello-world"` |
| `sanitized_url(url)` | Blocks `javascript:`, `data:`, protocol-relative `//evil.com` |
| `script_safe_json(value)` | JSON inside `<script>` — escapes `<`, `>`, `&`, U+2028/9 |
| `markdown(text)` | Render frontmatter markdown to HTML |
| `asset_path(name)` | `asset_path('css/app.css')` → fingerprinted URL |
| `picture_tag(source, alt:)` | Emits a responsive `<picture>` element |
| `icon(name, **attrs)` | Inlines an SVG from `app/icons/<name>.svg` |
| `heroicon(name)` | Inlines a vendored Heroicon |

Helpers are a plain Ruby module — add your own to
`app/helpers/` (autoloaded) or extend `lib/abqari/helpers.rb`
directly and they're available in every template.

## Auto-escaping is the default

Erubi compiles `<%= expr %>` to `_buf << h(expr)`. Every untrusted
value passes through `CGI.escapeHTML`. The opt-in raw form is
`<%== expr %>` and is reserved for known-safe HTML: helper output
that builds tags (`link_to`, `picture_tag`, `icon`, `heroicon`,
`yield_content`), pre-rendered markdown via `page.content`, and
JSON-LD via `script_safe_json` inside `<script>` blocks.

The build-time ERB escape audit (`test/erb_escape_audit_test.rb`)
scans every partial and layout for `<%==` and fails CI if any raw
interpolation isn't on a small allow-list. Adding a new raw
interpolation is a deliberate, reviewer-gated choice.

## Templates are yours

Unlike Jekyll's Liquid sandbox or Hugo's Go templates, Abqari's
templates run real Ruby. You can `require` libraries, define
methods inline, call any method on `site` or `page`. The whole
point: no plugins, no shortcodes, no special template language.
If Ruby can do it, your template can do it.

## See also

- [Helpers reference in source](https://github.com/grantrayner/abqari/blob/main/lib/abqari/helpers.rb)
- [Add a custom helper](/cookbook/) — coming soon
- [Run ERB in markdown content](/cookbook/erb-in-markdown/) — per-page
  opt-in so a markdown body can call helpers and render partials

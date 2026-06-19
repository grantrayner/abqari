---
title: Run ERB in markdown content (per-page opt-in)
description: "Inline dynamic values, render partials, and call helpers from inside a markdown body. Off by default, opt in per page with `erb: true`."
---

# Run ERB in markdown content

By default, Abqari runs the markdown body straight through commonmarker. ERB tags like `<%= 1 + 1 %>` are treated as literal text and HTML-escaped — fine for code blocks, useless for dynamic content.

When a page needs a value that changes between builds — "Updated <date>", "<count> posts", computed years, an inline partial render — opt in with frontmatter:

```yaml
---
title: About
erb: true
---
```

The body now passes through ERB before commonmarker, with the same context layouts use. You get `page`, `site`, all the helpers (`local_time`, `years_since`, `link_to`, `h`, `sanitized_url`), and `render 'partials/foo'`.

## Example

```markdown
---
title: About the Author
erb: true
---

After leaving military service in 2002, I established myself as a security
consultant. With over <%= years_since(2002) %> years of experience, I have
travelled extensively and supported clients across Asia and the Middle East.
```

The number recomputes every build, so the about page never goes stale.

## Why per-page, not site-wide

ERB tags share their delimiters with code blocks. A blog post that explains ERB, Rails, or any other Ruby tooling is full of literal `<% %>` strings. If ERB processing were always-on, every code block on every page would need the literal-tag escape (`<%%` → `<%`).

Per-page opt-in keeps the surprise factor at zero. Pages that don't set `erb: true` are guaranteed to render their `<% %>` substrings as literal text. Pages that do set it accept the trade-off — and you can see the flag at the top of the file.

## What's available in the body

Same context as ERB layouts:

| In your markdown | Use it for |
| --- | --- |
| `page.title`, `page.frontmatter['…']`, `page.url`, `page.date` | Read this page's metadata |
| `site.config['…']`, `site.collection('posts')`, `site.featured(…)` | Read site config and other content |
| `local_time(date)`, `time_ago(date)`, `time_until(date)` | Format dates |
| `years_since(2002)` | Whole years between then and today |
| `pluralize(n, 'post')` | "1 post" / "5 posts" |
| `truncate(text, length: 100)` | Cap at a length |
| `h(string)` | HTML-escape a value |
| `sanitized_url(url)` | URL-validate before interpolating into href |
| `link_to(text, url)` | Build an `<a>` tag |
| `render 'partials/foo'` | Inline a partial — same as in layouts |

## Dynamic patterns

**Year-aware bio:**

```markdown
With over <%= years_since(2002) %> years of experience, I have travelled…
```

**Last updated:**

```markdown
*Last updated <%= local_time(page.lastmod) %>.*
```

**Inline partial render:**

```markdown
Some prose.

<%= render 'partials/contact_button' %>

More prose.
```

**Pull a value from another page:**

```markdown
<% featured_book = site.featured('books', 'memoirs-of-an-assassin') %>
Read more about [<%= featured_book.title %>](<%= featured_book.url %>).
```

## Code blocks on a page that has ERB enabled

If you opt a page into ERB and need to show a literal `<% … %>` snippet (e.g. you're writing about ERB itself), use the literal-tag escape:

```markdown
The escape for an ERB opening tag is `<%%`. The runtime renders it as `<%`.
```

That renders as a code span containing `<%%`, which becomes `<%` in the output. Same trick for `%%>`.

For pages that are mostly about ERB, just leave `erb: true` off — the body never hits the ERB engine and code blocks render literally.

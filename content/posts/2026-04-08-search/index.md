---
title: Static search with Pagefind
published: true
description: Client-side full-text search without a server or third-party tracking. One config line wires it in.
tags: [search, pagefind, privacy]
cover: svg
---

Abqari ships with [Pagefind](https://pagefind.app/) integration
for static client-side search. No server, no API, no third-party
tracking. The browser fetches only the index chunks it needs for
the current query — typically a few KB.

## How it works

1. **Build emits HTML** — `bin/build` produces `_site/`.
2. **Pagefind walks the output** — chunked search index written
   to `_site/pagefind/`.
3. **Browser does the searching** — Pagefind's small JS runtime
   fetches only the index chunks needed for the current query.

Everything stays on your own origin. The strict default CSP
(`script-src 'self'`) covers Pagefind without modification —
`/pagefind/` is `'self'`.

## Setup

### 1. Install Pagefind once

Pagefind is a single Rust binary, distributed separately from Abqari:

```bash
brew install pagefind                                    # macOS / Homebrew
curl -LSf https://pagefind.app/install.sh | bash         # general
cargo install pagefind                                   # Rust toolchain
npm install -g pagefind                                  # npm
```

### 2. Enable in `config/site.yml`

```yaml
search: true
```

That's the entire configuration. `bin/build` runs `pagefind --site _site/`
automatically after rendering.

### 3. Render the search box

Drop the partial wherever you want the search UI:

```erb
<%== render 'partials/search' %>
```

`_search.html.erb` mounts a search box that opens a results modal.
Without `search: true` it renders nothing — safe to leave in
templates while you iterate.

## What you get

- **Full-text indexing** of every page Abqari builds
- **Highlighting** of matched terms in result snippets
- **Sub-result ranking** within a single page (heading matches
  rank higher)
- **Filtered search** by section if you tag content with
  `data-pagefind-filter`
- **Multilingual support** out of the box (uses your `<html lang>`
  for stemming)
- **Automatic exclusion** of nav, footer, and other non-content
  elements (mark them with `data-pagefind-ignore`)

## Re-indexing without rebuilding

Sometimes you want to refresh the search index without re-rendering
pages — after manually editing an HTML file or iterating on
Pagefind metadata:

```bash
bin/index
```

This runs Pagefind directly against `_site/`, regardless of whether
`search: true` is set in config.

## Graceful degradation

When `search: true` is configured but Pagefind isn't installed,
`bin/build` prints a helpful warning and continues:

```
Abqari: search.enabled = true but `pagefind` is not on PATH.
       Install: https://pagefind.app/docs/installation/
       Skipping search index for this build.
Built 145 page(s) in production → _site/
```

Your build never fails because of a missing Pagefind binary —
useful for fresh checkouts or CI environments where Pagefind
hasn't been installed yet.

## Customising

The shipped partial uses Pagefind's default UI. Customise via
`app/assets/js/search-init.js`:

```javascript
new PagefindUI({
  element: '#abqari-search',
  showSubResults: true,
  showImages: false,
  // see https://pagefind.app/docs/ui/ for all options
});
```

Or write your own UI from scratch — Pagefind exposes a JS API for
programmatic queries.

## Why Pagefind over alternatives

- **Algolia, Typesense, Meilisearch**: fast, but require running a
  service, and most charge for a hosted plan. Search depends on a
  third party, and visitor queries leave your origin.
- **Lunr.js, Elasticlunr**: client-side, but ship the *entire*
  index to every visitor (potentially several MB on a 500-page
  site). Pagefind's chunked approach loads only what's needed.
- **Google Custom Search**: technically free but visually
  intrusive, ad-laden, and a privacy regression.

Pagefind is the modern static-search default. Abqari just wires it in.

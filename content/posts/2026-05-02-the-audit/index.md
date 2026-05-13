---
title: "The audit and frontmatter validation"
description: A build-time check that catches typos in tags, countries, and other taxonomy fields before they ship as broken pages.
date: 2026-05-02
tags: [tooling, validation]
---

`bin/audit` is the build-with-checks script. It runs a full
production build, then walks the output looking for problems — broken
internal links, missing files referenced from frontmatter, malformed
taxonomy values, and a handful of other classes of bug.

## Frontmatter validation

The audit reads any `validate:` block in `config/site.yml`:

```yaml
validate:
  country: data/countries.yml
```

Each entry maps a frontmatter field to a YAML whitelist. The audit
flags any value that doesn't appear as a top-level key in the file.

A photo with `country: Syra` (typo) would otherwise build cleanly
and ship as a working page at `/country/syra/` — invisible until
someone notices the missing photos. The audit catches it before it
goes out.

## Running it

```bash
bin/audit
```

Output looks like:

```
Built 49 page(s) in production → _site/
Audit complete: audit/2026-05-12-1503.md (0 error, 0 warn, 260 info)
```

Errors fail CI; warnings don't but should be fixed; info is
informational only (counts, summaries, redirects emitted).

## What to validate

Anything you take from a finite list: countries, languages,
categories, content types. Don't validate free-form fields like
tags — typos in free-form tags create new tag pages and that's
usually intentional.

---
title: "The audit and frontmatter validation"
published: true
description: Build-time site quality report covering links, SEO, a11y, privacy, dependency CVEs, content, and taxonomy whitelists.
date: 2026-05-02
tags: [tooling, validation, audit]
---

`bin/audit` is the build-with-checks script. It rebuilds the site,
walks the output, and writes a markdown report to
`audit/<YYYY-MM-DD-HHMM>.md` covering six categories.

```bash
bin/audit
```

```
Built 194 page(s) in production → _site/
Audit complete: audit/2026-05-21-1428.md (0 error, 4 warn, 174 info)
```

## What's checked

| Category | Checks |
| --- | --- |
| **Links** | Broken internal links and asset references |
| **SEO** | Title length (>60), description length (>160 or missing), duplicate titles |
| **Accessibility** | Images without `alt`, multiple `<h1>` per page, missing skip link, unlabelled `<nav>` |
| **Privacy** | External resource loads (URLs not on the site host) |
| **Dependencies** | Outdated gems via `bundle outdated`, CVEs via `bundle-audit` |
| **Content** | Posts without descriptions, single-use tags, frontmatter validation |

The report opens with a summary table, a **Suggested fixes** code
block listing every `bundle update <gem>` command needed to clear
dependency findings, and then groups findings by category with
severity (`error`, `warn`, `info`) and a suggestion where
applicable.

Reports accumulate in `audit/` — useful to commit so you have a
diffable history of site quality over time.

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
someone notices the missing photos. The audit catches it before
it goes out.

**What to validate**: anything you take from a finite list —
countries, languages, categories, content types. Don't validate
free-form fields like `tags` — typos in tags just create new tag
pages, and that's usually intentional.

## Strict mode

```bash
bin/audit --strict
```

Exits non-zero on any error-severity finding. Wire into CI so
broken-link or missing-alt regressions block merges:

```yaml
# .github/workflows/ci.yml
- run: bundle exec bin/audit --strict
```

Warnings don't fail strict mode — they're informational. To gate
on warnings too, change to `--strict=warn`.

## Dependency security check

For CVE scanning, install `bundler-audit` once:

```bash
gem install bundler-audit
```

When available, the audit runs `bundle-audit check --update` —
which refreshes the `ruby-advisory-db` (~1,100 advisories) — and
parses every finding into a structured report:

- **Severity** — Critical/High → `error`, Medium → `warn`,
  Low → `info` (driven by the CVE's own criticality)
- **Identifier** — GHSA or CVE number
- **Vulnerable version** — what's in your `Gemfile.lock`
- **Title** — the human-readable advisory description
- **Upgrade path** — the version constraint that resolves the issue
- **Suggested command** — `bundle update <gem>` you can copy/paste

Without `bundle-audit` installed, the audit still runs; the
dependency section just notes the CVE check was skipped.

## Compared to GitHub Dependabot

GitHub Dependabot does three things `bin/audit` does **not**:

- **Runs continuously.** Dependabot scans your repo daily.
  `bin/audit` is on-demand — run it before deploying or wire it
  into CI.
- **Opens pull requests.** Dependabot creates per-gem PRs with
  the changelog. The audit gives you the exact command but you
  run it yourself.
- **Aggregates across an org.** Dependabot is GitHub-hosted; the
  audit is local.

What `bin/audit` does that Dependabot doesn't:

- **Same report covers links, SEO, accessibility, privacy, and
  content** — not just dependencies.
- **Uses the same `ruby-advisory-db`** Dependabot uses for Ruby,
  just at a single point in time.
- **Outputs to git-trackable markdown.** A diffable `audit/`
  history of every check.

Use both: Dependabot (or similar) for continuous monitoring;
`bin/audit` for a comprehensive snapshot before deploys.

## Wiring into CI

The site skeleton's GitHub Actions workflows run the audit on
every push, upload the markdown report as an artifact, and deploy
regardless. You can review the audit attached to each successful
deploy without it ever blocking a release. For PR gates, use the
`--strict` mode above to fail the workflow on errors.

The engine's own CI also gates on `bin/audit --strict` plus
`bundle-audit check --update` plus the full test suite — see
`.github/workflows/ci.yml` and the [Deploying](/guides/deploying/)
guide for the release-time variant.

## See also

- [Accessibility](/guides/accessibility/) — what the audit's a11y
  rules check and why
- [Deploying](/guides/deploying/) — wiring the audit into the
  deploy pipeline

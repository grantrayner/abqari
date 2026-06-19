---
title: Add Plausible analytics
description: Privacy-friendly analytics with no cookie banner needed. First-class config support — one line and you're done.
---

# Add Plausible analytics

[Plausible](https://plausible.io/) is a lightweight, GDPR-friendly analytics service that doesn't use cookies. Tracker is ~1 KB and doesn't require a cookie consent banner.

Abqari has built-in support — you don't need to edit `_head.html.erb` or wrestle with the CSP. One config line and the rest is automatic.

## 1. Sign up

Create an account at [plausible.io](https://plausible.io/) (or self-host the open-source version) and add your site's domain. From the script-snippet view, copy your **script key** — the slug between `plausible.io/js/` and `.js` in the embed snippet:

```html
<!-- Your snippet looks like this; copy the bold part -->
<script async src="https://plausible.io/js/pa--abc123xyz.js"></script>
                                       ^^^^^^^^^^^^^
```

## 2. Add to config

```yaml
# config/site.yml
plausible: pa--abc123xyz
```

That's it. Next build, Abqari:

- Renders the Plausible tracker in `<head>` of every page.
- Auto-extends the strict CSP to allow `https://plausible.io` for both the script tag and the API calls (`script-src` and `connect-src`).
- Pins the inline init script's SHA256 hash so the strict policy stays intact (no `'unsafe-inline'`).
- Skips Plausible during `bin/serve` so your local pageviews don't pollute the dashboard.

## 3. Verify

After deploying, open your site and check the Plausible dashboard — pageviews appear within a minute. To verify CSP locally:

```bash
bin/build
grep Content-Security-Policy _site/_headers
```

You should see `https://plausible.io` in `script-src` and `connect-src`, plus a second `sha256-...` hash alongside the theme-bootstrap one.

## Track in development too

By default, dev builds skip Plausible. To opt in (e.g. testing custom events):

```yaml
plausible:
  key: pa--abc123xyz
  in_development: true
```

## Why Plausible over Google Analytics

- **No cookies, no banner.** Tracks aggregate visits without identifying individuals.
- **1 KB tracker** vs Google's ~50 KB. Faster page loads, better Core Web Vitals.
- **Open-source.** Audit the code or self-host the whole thing.
- **EU-hosted.** Helpful for GDPR compliance.

## Self-hosting Plausible

If you self-host Plausible on your own domain (e.g. `analytics.example.com`), Abqari's built-in support hard-codes `plausible.io`. For now, use the manual approach: leave `plausible:` unset, render the `<script>` tags directly in `_head.html.erb`, and override the `headers:` block in config to extend the CSP. The first-class config form supports the hosted Plausible only.

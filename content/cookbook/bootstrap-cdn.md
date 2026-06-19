---
title: Use Bootstrap from a CDN
description: Skip the 232 KB vendored CSS in favour of a pinned CDN version with SRI integrity hashes.
---

# Use Bootstrap from a CDN

The shipped `bootstrap` theme vendors Bootstrap 5.3.8 — both the CSS (~232 KB) and the JS bundle (~80 KB) — so the strict default CSP (`'self'` only) keeps working. The dist files live under `themes/bootstrap/public/` and are copied to `/css/bootstrap.min.css` and `/js/bootstrap.bundle.min.js` in the build output, alongside their sourcemaps. That's the right default for privacy-conscious sites.

But sometimes you want the CDN: smaller repo, easier upgrades, browser cache potentially shared with other Bootstrap sites you visit (though [origin-keyed caching](https://developer.chrome.com/blog/http-cache-partitioning/) has weakened this benefit).

## Trade-off summary

| | Vendored | CDN |
| --- | :-: | :-: |
| Privacy (no third-party request) | ✓ | ✗ |
| Strict CSP works unchanged | ✓ | ✗ (must allow CDN host) |
| Site stays up if CDN goes down | ✓ | ✗ |
| Easy upgrade to a new patch | drop new files into `themes/bootstrap/public/` | bump version string |
| Bootstrap JS components included | ✓ (5.3.8 bundle) | ✓ |
| Repo size | +312 KB | tiny |

If those trade-offs work for your project, here's how to switch.

## 1. Switch the theme to `none`

In `config/site.yml`:

```yaml
theme: none
```

This stops abqari from generating a fingerprinted `app.css` from the vendored Bootstrap. We'll load Bootstrap from the CDN instead.

## 2. Replace the stylesheet link in the head

Edit `app/views/partials/_head.html.erb`. Replace the line that loads the theme CSS:

```erb
<link rel="stylesheet" href="<%= asset_path('css/app.css') %>">
```

With Bootstrap's official CDN snippet (from [getbootstrap.com](https://getbootstrap.com/docs/5.3/getting-started/download/#cdn-via-jsdelivr)):

```html
<link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.8/dist/css/bootstrap.min.css"
      rel="stylesheet"
      integrity="sha384-sRIl4kxILFvY47J16cr9ZwB07vP4J8+LH7qKQnuqkuIAvNWLzeN8tE5YBujZqJLB"
      crossorigin="anonymous">
```

The `integrity` attribute is a SHA-384 [Subresource Integrity](https://developer.mozilla.org/en-US/docs/Web/Security/Subresource_Integrity) hash — the browser refuses to apply the CSS if the file's hash doesn't match. So even if the CDN is compromised, your site won't render the wrong CSS. Always include this.

## 3. Add the JS bundle (optional)

Bootstrap's interactive components (collapse, modal, dropdown, popover, tooltip, etc.) need its JS bundle. If you want them, add this just before `</body>` in `app/views/layouts/application.html.erb`:

```html
<script src="https://cdn.jsdelivr.net/npm/bootstrap@5.3.8/dist/js/bootstrap.bundle.min.js"
        integrity="sha384-FKyoEForCGlyvwx9Hj09JcYn3nv7wiPVlz7YYwJrWVcXK/BmnVDxM+D2scQbITxI"
        crossorigin="anonymous"></script>
```

Skip this if you only need styling — Bootstrap's grid, buttons, cards, etc. are pure CSS.

## 4. Update your CSP

The strict default CSP blocks third-party scripts and stylesheets. Override it in `config/site.yml`:

```yaml
headers:
  '/*':
    Content-Security-Policy: >
      default-src 'self';
      img-src 'self' data:;
      style-src 'self' https://cdn.jsdelivr.net;
      script-src 'self' 'sha256-…' https://cdn.jsdelivr.net;
      font-src 'self';
      frame-ancestors 'none';
      base-uri 'self'
    Strict-Transport-Security: "max-age=31536000; includeSubDomains"
    X-Content-Type-Options: nosniff
    Referrer-Policy: strict-origin-when-cross-origin
    Permissions-Policy: "camera=(), microphone=(), geolocation=(), interest-cohort=()"
  '/assets/*':
    Cache-Control: "public, max-age=31536000, immutable"
```

The `'sha256-…'` placeholder is the existing theme-bootstrap inline script hash; copy it from `_site/_headers` after a regular build.

`style-src` and `script-src` get `https://cdn.jsdelivr.net` added so the Bootstrap CSS and JS load. SRI hashes ensure integrity even if jsDelivr serves a different file.

## 5. Rebuild and deploy

```bash
bin/build
```

Reload your site — it now loads Bootstrap from the CDN instead of from your origin.

## When to stick with vendored

- **You want strict-CSP-by-default.** Vendored keeps `script-src 'self'` simple.
- **You're deploying to a privacy-focused audience** that scans for third-party requests.
- **You want offline development to "just work"** without internet for asset loads.

For everyone else, CDN is a perfectly reasonable choice.

## Upgrading the vendored Bootstrap

When a new Bootstrap patch ships, replace the four files under `themes/bootstrap/public/`:

```
themes/bootstrap/public/
  css/
    bootstrap.min.css
    bootstrap.min.css.map
  js/
    bootstrap.bundle.min.js
    bootstrap.bundle.min.js.map
```

Download from [getbootstrap.com](https://getbootstrap.com/docs/5.3/getting-started/download/), drop in, rebuild. No code changes — the head partial loads them at fixed paths. Project-level overrides live in `themes/bootstrap/css/app.css` (loaded after the vendored CSS) and stay untouched.

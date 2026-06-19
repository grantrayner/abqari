---
title: Add GoatCounter analytics
description: A simpler, free, self-hostable alternative to Plausible. No account-bound script key — works with any GoatCounter instance.
---

# Add GoatCounter analytics

[GoatCounter](https://www.goatcounter.com/) is a privacy-friendly analytics service with a generous free tier and an open-source, self-hostable backend. No cookies, no fingerprinting, no consent banner.

It doesn't have first-class config support like [Plausible](/cookbook/plausible/), so this is a manual wire-up — but it's only ~20 lines.

## 1. Sign up (or self-host)

Create an account at [goatcounter.com](https://www.goatcounter.com/) — the free tier covers personal sites generously. You'll get a subdomain like `yourname.goatcounter.com`.

Self-hosting works the same way; just substitute your own host below.

## 2. Add the script tag to `_head.html.erb`

Edit `app/views/partials/_head.html.erb` and add before `</head>`:

```erb
<% if site.env != :development %>
<script data-goatcounter="https://yourname.goatcounter.com/count" async src="//gc.zgo.at/count.js"></script>
<% end %>
```

The `unless development` guard keeps your local pageviews out of production analytics. Replace `yourname` with your actual GoatCounter subdomain.

## 3. Extend the CSP

The strict default CSP only allows `'self'` for scripts. To load `gc.zgo.at` and POST events to `*.goatcounter.com`, override the `headers:` block in `config/site.yml`:

```yaml
headers:
  '/*':
    Content-Security-Policy: "default-src 'self'; img-src 'self' data: https://gc.zgo.at; style-src 'self'; script-src 'self' 'sha256-PavunSXMO2Bo6olnU/NbutcybJV35Crx3RXU3guZH2E=' https://gc.zgo.at; font-src 'self'; connect-src 'self' https://yourname.goatcounter.com; frame-ancestors 'none'; base-uri 'self'"
    Strict-Transport-Security: "max-age=31536000; includeSubDomains"
    X-Content-Type-Options: nosniff
    Referrer-Policy: strict-origin-when-cross-origin
    Permissions-Policy: "camera=(), microphone=(), geolocation=(), interest-cohort=()"
  '/assets/*':
    Cache-Control: "public, max-age=31536000, immutable"
```

The `'sha256-...'` is the theme-bootstrap inline script's hash — copy it from a fresh `_site/_headers` after running `bin/build`. The `connect-src` addition allows GoatCounter's API calls to send analytics events. Replace `yourname` again.

> **Heads-up.** Setting `headers:` overrides Abqari's automatic CSP construction — you lose any auto-extension that other config knobs (like Plausible) would normally add. If you want to combine GoatCounter with Plausible, copy the Plausible-extended CSP from a build with `plausible:` set, then add GoatCounter to it.

## 4. Verify

After deploying, open your site and visit your GoatCounter dashboard — pageviews appear within a minute. To verify CSP locally:

```bash
bin/build
grep Content-Security-Policy _site/_headers
```

Should show `gc.zgo.at` in `script-src` and `yourname.goatcounter.com` in `connect-src`.

## Why GoatCounter

- **Free for personal use** (10K pageviews/month). Self-host for unlimited.
- **No cookies, no GDPR banner.** Tracks aggregate visits.
- **Tiny.** Tracker is ~3 KB.
- **Open-source.** Audit the code or run your own instance.
- **Works without an account.** If you self-host, no third-party at all.

## When to pick Plausible vs GoatCounter

| | Plausible | GoatCounter |
| --- | --- | --- |
| Abqari first-class support | yes (one config line) | no (manual head + CSP) |
| Free tier | 30-day trial, then paid | 10K pageviews/month free |
| Self-host complexity | medium (Elixir + DB) | low (single Go binary) |
| Dashboard polish | high | utilitarian |

If you're paying for analytics or care about UI polish, Plausible. If you want zero ongoing cost and don't mind a less polished dashboard, GoatCounter.

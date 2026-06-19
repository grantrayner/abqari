---
title: Deploy to Cloudflare Pages
description: Free tier, unmetered bandwidth, edge-cached HTML. The recommended host.
---

# Deploy to Cloudflare Pages

Cloudflare Pages serves your `_site/` from edge caches near every visitor, free for personal sites, with unmetered bandwidth. It's the recommended Abqari host.

## Two ways to deploy

You can deploy via:

1. **The shipped GitHub Actions workflow** (`.github/workflows/deploy.yml`) — automatic on every push to `main`.
2. **`bin/deploy cloudflare`** locally — manual, when you want explicit control.

Both use Cloudflare's [Wrangler](https://developers.cloudflare.com/workers/wrangler/) CLI under the hood.

## Set up Cloudflare Pages

1. Sign in at [dash.cloudflare.com](https://dash.cloudflare.com/) and go to **Workers & Pages**.
2. **Create application → Pages → Direct upload**. Don't connect to Git — the GitHub Action handles that itself.
3. Name your project (e.g. `my-blog`). Cloudflare gives you a `<project-name>.pages.dev` URL immediately.
4. Optional: add a custom domain in the project's **Custom domains** tab.

## Get your credentials

You need two values for the GitHub Action:

- **Account ID** — visible on any dashboard URL: `dash.cloudflare.com/<ACCOUNT_ID>/...`. Copy it.
- **API token** — go to [API Tokens](https://dash.cloudflare.com/profile/api-tokens), click **Create Token**, use the **Cloudflare Pages: Edit** template, and limit it to your specific Pages project for safety.

## Wire up GitHub Actions

In your GitHub repo, go to **Settings → Secrets and variables → Actions → New repository secret** and add:

- `CLOUDFLARE_API_TOKEN`
- `CLOUDFLARE_ACCOUNT_ID`

Edit the workflow file at `.github/workflows/deploy.yml` and replace `your-project-name` with your Pages project name.

Push to `main` — first deploy is on its way. Subsequent pushes redeploy automatically.

## Or deploy from your laptop

```bash
npm install -g wrangler
wrangler login
```

Add to `config/site.yml`:

```yaml
deploy:
  default: cloudflare
  cloudflare:
    project: my-blog
```

Then:

```bash
bin/deploy cloudflare
```

`bin/deploy` builds the site, then runs `wrangler pages deploy _site --project-name=my-blog`.

## What works automatically

- **`_headers`** — Cloudflare reads it and applies your security headers (CSP, HSTS, etc.) at the edge.
- **`_redirects`** — 301 redirects (declared via `redirect_from:` front matter) are honoured.
- **Asset caching** — fingerprinted assets get the long-cache header from `_headers`; HTML stays short-cached.
- **HTTPS** — automatic, free, with Cloudflare's certificate.

## Limits to know about

- **Free tier**: 500 builds/month, 100 custom domains, unlimited requests, unlimited bandwidth. Generous.
- **Workflow runs**: 1 build per push to `main`. If you push 50 times in a day, that's 50 builds. Squash commits if you're worried about hitting the cap.
- **Single global region** by default. Cloudflare auto-replicates to its edge.

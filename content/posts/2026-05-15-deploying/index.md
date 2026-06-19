---
title: Deploying Abqari sites
published: true
description: Ship your site to Cloudflare Pages, Netlify, Render, GitHub Pages, or anywhere static.
tags: [deploying, cloudflare, ci]
cover: svg
---

Abqari produces a plain `_site/` directory of static files. Deploy
it anywhere that serves static HTML.

## With `bin/deploy`

`bin/deploy` builds the site and pushes `_site/` via the configured
CLI. Configure once in `config/site.yml`:

```yaml
deploy:
  default: cloudflare
  cloudflare:
    project: my-blog
  netlify:
    site_id: 1234abcd-...
```

Then:

```bash
bin/deploy                # uses deploy.default
bin/deploy cloudflare     # explicit target
bin/deploy netlify
```

The first time, install the relevant CLI and authenticate:

```bash
# Cloudflare
npm install -g wrangler
wrangler login

# Netlify
npm install -g netlify-cli
netlify login
```

### Build-OK sentinel

`bin/deploy` refuses to ship if the build didn't complete cleanly.
A successful `Site#build` writes a `_site/.abqari-build-ok` marker
at the very end of the pipeline — only after every step succeeded.
If the marker is missing, deploy aborts:

```
Missing /path/_site/.abqari-build-ok — build did not complete
successfully. Not deploying.
```

This defends against half-built `_site/` directories that can
appear when `bin/build` is wrapped by a pipeline that swallows
exit codes, or when an external rsync touches the output dir
between the build and the deploy.

## Via GitHub Actions

Three deploy workflows ship in the site skeleton, one per host:

- `.github/workflows/deploy-cloudflare.yml`
- `.github/workflows/deploy-github-pages.yml`
- `.github/workflows/deploy-render.yml`

Each builds with Ruby + Bundler caching, installs libvips + Pagefind,
runs the audit (uploaded as an artifact), and deploys on push to
`main`.

### Cloudflare Pages — one-time setup

1. Create a Pages project (use **Direct Upload**, not Git
   integration — the workflow handles deploys).
2. Generate an API token with the **Cloudflare Pages: Edit** scope.
3. In GitHub *Settings → Secrets and variables → Actions*, add:
   - `CLOUDFLARE_API_TOKEN`
   - `CLOUDFLARE_ACCOUNT_ID`
4. Edit `your-project-name` in the workflow file to match your
   project.

Push to `main` and the site deploys.

### GitHub Pages — one-time setup

1. *Settings → Pages*: set source to "GitHub Actions".
2. Enable the `deploy-github-pages.yml` workflow.

Push to `main` and the site deploys to `<user>.github.io/<repo>/`.

### Render — one-time setup

Connect the GitHub repo in Render. The shipped workflow isn't
needed — Render runs `bundle exec bin/build` and serves `_site/`
directly.

## Other hosts

| Host | Approach |
| --- | --- |
| **Cloudflare Pages** | Use the shipped workflow (free tier + unmetered bandwidth) |
| **Netlify** | Replace the deploy step with [`nwtgck/actions-netlify`](https://github.com/nwtgck/actions-netlify) |
| **Render** | Connect the GitHub repo — no Action needed; build `bundle exec bin/build`, publish `_site` |
| **GitHub Pages** | Use the shipped `deploy-github-pages.yml` |
| **S3 + CloudFront** | `aws s3 sync _site s3://your-bucket/ --delete` after build |
| **Anywhere static** | Upload `_site/` via FTP/rsync/SCP/whatever |

## What `_site/` contains

After `bin/build`, your `_site/` directory has everything a static
host needs:

- HTML for every page, post, tag, and pagination shard
- `assets/css/`, `assets/js/`, `assets/images/` — content-hashed
  and immutable-cacheable
- `assets/fonts/` — self-hosted woff2 if `fonts:` is configured
- `pagefind/` — search index if `search: true`
- `sitemap.xml`, `<collection>/feed.xml`, `<collection>/feed.json`,
  `robots.txt`
- `_headers` — security headers (Cloudflare/Netlify read this)
- `_redirects` — 301s declared in `redirect_from:` frontmatter
- `.well-known/security.txt` — when `security_contact:` is set
- `.abqari-build-ok` — the build-success sentinel (gitignored on
  the host side; deployers read it before publishing)

No server, no API, no database. The whole site is files.

## CI safety

The release / deploy workflows for the engine itself SHA-pin every
third-party action — `actions/checkout@<40-char>`,
`ruby/setup-ruby@<40-char>`, etc. — to avoid supply-chain
surprises when a major-tag action is updated upstream. Dependabot
keeps the pins current via the `github-actions` ecosystem. The
same pattern applies to consuming sites: the skeleton workflows
SHA-pin actions out of the box.

## See also

- [Upgrading Abqari](/guides/upgrading/) — bumping the gem version
- [Deploy to Cloudflare Pages](/cookbook/cloudflare/) — the
  step-by-step recipe

# Deploying

A practical, step-by-step walkthrough for getting an Abqari site live
on one of the three first-class hosts.

Each host has its own setup steps below. If you're not sure which to
pick, the table at the top will narrow it down. After the per-host
walkthroughs there's a [DNS section](#custom-domain-dns) (the part
people get stuck on most often) and a
[troubleshooting](#troubleshooting) reference for the common errors.

---

## Pick a host

| You want… | Use |
|---|---|
| The simplest possible setup, zero workflow files needed | **Render (dashboard auto-deploy)** |
| CI gates (audit, tests) blocking deploys, plus Render | **Render (Actions-driven)** |
| Best CDN performance + unmetered bandwidth | **Cloudflare Pages** |
| Free hosting on GitHub itself, no external account | **GitHub Pages** |

All three are free for sites the size you're likely to build. All
three handle HTTPS automatically via Let's Encrypt. Switching later
is a config change, not a migration.

---

## Render — dashboard auto-deploy (simplest)

This is the path I'd recommend for a first deploy. **No GitHub
secrets, no workflow files needed.** Render watches your repo
directly, rebuilds on every push to `main`.

### One-time setup

1. Sign in at [dashboard.render.com](https://dashboard.render.com) (free).
2. Click **New +** → **Static Site**.
3. Connect your GitHub account, then pick the repo.
4. Configure the site:

   | Field | Value |
   |---|---|
   | Name | Anything memorable — appears in the Render URL (`<name>.onrender.com`) |
   | Branch | `main` |
   | Root Directory | _Leave blank_ |
   | Build Command | `sudo apt-get update && sudo apt-get install -y libvips42 libheif1 libheif-plugin-aomenc libheif-plugin-libde265 libheif-plugin-dav1d && bundle install && bundle exec bin/build` |
   | Publish Directory | `_site` |

5. Click **Advanced** → **Add Environment Variable**:

   | Key | Value |
   |---|---|
   | `ABQARI_ENV` | `production` |

6. Click **Create Static Site**.
7. Wait for the first build. It takes ~3-5 minutes (libvips install
   is the slow part; subsequent builds are ~30-60 seconds thanks
   to Render's build cache).
8. When the build finishes you'll see a green **Live** status and a
   URL like `https://abqari-xyz.onrender.com`. Open it — your site
   is up.

### Custom domain

1. In your site's Render dashboard, go to **Settings** → **Custom
   Domains** → **Add Custom Domain**.
2. Enter `www.abqari.dev` (or your domain).
3. Render shows you a target like `abqari-xyz.onrender.com`. Copy it.
4. At your DNS registrar, add a CNAME record:

   | Type | Name | Value | TTL |
   |---|---|---|---|
   | CNAME | `www` | `abqari-xyz.onrender.com` | Auto / 3600 |

5. For the apex (`abqari.dev` without `www`), see
   [Apex domains](#apex-vs-www) below.
6. Wait 5–30 minutes for DNS propagation. Render auto-provisions
   the Let's Encrypt certificate as soon as the DNS verifies.

That's it. Pushing to `main` triggers a rebuild and redeploy.

---

## Render — Actions-driven (CI-gated)

Use this if you want CI gates (the audit, the test suite) to block
deploys, or if you're already standardised on GitHub Actions for
everything else.

### One-time setup

Start with the [dashboard setup above](#render--dashboard-auto-deploy-simplest)
to create the Render site. Then **switch Render off auto-deploy**
(otherwise you'll deploy twice — once from Render's polling and once
from the workflow):

1. In your Render site's **Settings** → **Build & Deploy** →
   **Auto-Deploy** → set to **No**.
2. Same page, scroll to **Deploy Hook** → click the URL to reveal
   it → copy it.

Then in GitHub, repo **Settings** → **Secrets and variables** →
**Actions**:

3. On the **Secrets** tab, click **New repository secret**:

   | Name | Value |
   |---|---|
   | `RENDER_DEPLOY_HOOK_URL` | the deploy hook URL you copied |

4. On the **Variables** tab, click **New repository variable**:

   | Name | Value |
   |---|---|
   | `ENABLE_RENDER` | `true` |

5. Push to `main`. The `Deploy → Render` workflow runs, builds
   locally as a smoke test, then pings the Render hook. Render
   queues its own build immediately.

### Verifying

GitHub: open the **Actions** tab. The `Deploy → Render` workflow
should show a green ✓. Render: open your site's dashboard; you'll
see "Deploying" → "Live" within a couple of minutes.

---

## Cloudflare Pages

Best for sites expecting heavy traffic — Cloudflare's CDN is the
fastest of the three and bandwidth is unmetered on the free tier.

### One-time setup

1. Sign in at [dash.cloudflare.com](https://dash.cloudflare.com).
2. Sidebar → **Workers & Pages** → **Create application** →
   **Pages** tab.
3. Choose **Upload assets** (NOT "Connect to Git" — the GitHub
   Action does the upload).
4. Project name: `abqari` (or anything; you'll reference this in
   the workflow config).
5. Upload anything (or just any file) to create the project, then
   delete that placeholder deploy.
6. Get your Cloudflare credentials:

   - **Account ID**: in the right sidebar of any Cloudflare page,
     under "API". Copy it.
   - **API Token**: top right avatar → **My Profile** →
     **API Tokens** → **Create Token** → use the "Edit Cloudflare
     Workers" template OR create a custom token with:
     - Permissions: Account → Cloudflare Pages → Edit
     - Account Resources: Include → your account
     Click **Continue to summary** → **Create Token** → copy the
     token (you won't see it again).

7. In GitHub, repo **Settings** → **Secrets and variables** →
   **Actions**:

   On the **Secrets** tab, add:

   | Name | Value |
   |---|---|
   | `CLOUDFLARE_API_TOKEN` | the token you just copied |
   | `CLOUDFLARE_ACCOUNT_ID` | the account ID |

   On the **Variables** tab, add:

   | Name | Value |
   |---|---|
   | `ENABLE_CLOUDFLARE` | `true` |
   | `CLOUDFLARE_PROJECT_NAME` | the project name from step 4 |

8. Push to `main`. Workflow runs → builds the site → wrangler
   uploads `_site/` → Cloudflare deploys → you get a URL like
   `https://abqari.pages.dev`.

### Custom domain

In your Pages project → **Custom domains** → **Set up a custom
domain** → enter `www.abqari.dev` → follow the prompts. Cloudflare
adds the DNS records automatically if your domain is on Cloudflare
DNS; otherwise it gives you a CNAME target to add at your registrar.

---

## GitHub Pages

Free, no third-party service. The catch: free GitHub Pages requires
a **public repo** (private repos need a paid plan).

### One-time setup

1. Repo → **Settings** → **Pages**.
2. **Source** → select **GitHub Actions** (NOT "Deploy from a
   branch"). This is the critical step — it grants the workflow
   the `pages: write` and `id-token: write` permissions it needs.
3. Repo → **Settings** → **Secrets and variables** → **Actions** →
   **Variables** tab → **New repository variable**:

   | Name | Value |
   |---|---|
   | `ENABLE_GITHUB_PAGES` | `true` |

   No secrets required — auth happens via OIDC.

4. Push to `main`. The workflow builds the site and publishes it.

   > **Deploy at a domain root, not a subpath.** Abqari emits
   > root-relative asset and link URLs (`/assets/…`, `/posts/…`,
   > `/feed.xml`), so a project site served under a path prefix
   > (`https://<user>.github.io/<repo>/`) would 404 every asset. The
   > build **hard-fails** if `url:` in `config/site.yml` has a path
   > component. Use one of:
   >
   > - a **custom domain** (below) — the recommended path, and what
   >   the shipped workflow assumes; or
   > - a **user/organization Pages repo** named
   >   `<user>.github.io`, which serves at the domain root.
   >
   > Subdirectory/base-path deployment is not supported in 1.0.

### Custom domain

1. Add a file called `CNAME` to the repo root (no extension)
   containing just your domain on one line:

   ```
   www.abqari.dev
   ```

   Commit and push.

2. Repo → **Settings** → **Pages** → **Custom domain** → enter
   `www.abqari.dev` → **Save**.
3. At your DNS registrar, add a CNAME:

   | Type | Name | Value | TTL |
   |---|---|---|---|
   | CNAME | `www` | `<your-username>.github.io` | Auto / 3600 |

4. Wait for the **Enforce HTTPS** checkbox to become available
   (sometimes takes up to 24 hours for Let's Encrypt). Tick it.

---

## Custom domain DNS

Three things you need to get right.

### Apex vs `www`

`www.abqari.dev` is a **subdomain**, which DNS handles with a CNAME
record. That's straightforward — every host gives you a target.

`abqari.dev` (no `www`) is an **apex** (also called "root" or "bare"
domain). CNAME records aren't allowed at the apex by the original
DNS spec, so you have three options:

| Approach | When it works | Pros / cons |
|---|---|---|
| **ALIAS / ANAME record** | Your DNS provider supports it (Cloudflare DNS, Namecheap, DNSimple, Route53, others) | Cleanest — apex resolves directly to host |
| **A records** | Always — but you need IP addresses, not hostnames. Most hosts publish them | Brittle if the host changes IPs |
| **Apex → www redirect** | All registrars | Apex visitors hit a redirect, the canonical lives at www. Simplest, most reliable |

For most cases, **apex → www redirect** is the right call:

- Cloudflare DNS: add a Page Rule "Forwarding URL" 301 redirecting
  `abqari.dev/*` → `https://www.abqari.dev/$1`
- Namecheap: Domain → "Redirect Domain" → set source `@`, target
  `https://www.abqari.dev`
- Most registrars have something similar under "URL forwarding" or
  "Domain forwarding"

Whichever you pick, the goal is: people who type `abqari.dev` end up
at `https://www.abqari.dev/`.

### Where to manage DNS

If you're using **Cloudflare DNS** (recommended — free, fast, full
feature set including CNAME flattening for the apex), set your
domain's nameservers at the registrar to Cloudflare's and manage
everything in the Cloudflare dashboard.

Otherwise, manage records directly at your registrar's DNS panel.

### Verifying DNS

After setting up records, use [dnschecker.org](https://dnschecker.org)
to verify propagation worldwide. Type your domain, pick CNAME, and
you should see your host's target show up in most regions within
a few minutes (some regions take longer).

To check from the command line:

```bash
dig +short www.abqari.dev CNAME
# → your-host's-target.com
```

---

## Verification

After deploying, walk through this checklist:

1. **Site loads at the host's URL.** Visit the URL Render /
   Cloudflare / GitHub Pages assigned. The home page should render.
2. **Site loads at your custom domain.** Visit `https://www.abqari.dev`
   (substitute your domain). Same content.
3. **HTTPS works without warnings.** Click the padlock; the
   certificate should be valid for your domain.
4. **Canonical URL is correct.** View source on any page; look for:

   ```html
   <link rel="canonical" href="https://www.abqari.dev/some-page/">
   ```

   The URL should match what you configured in
   `config/site.yml → environments.production.url`.

5. **Sitemap is reachable.** Visit `https://www.abqari.dev/sitemap.xml`
   — should be a valid XML document with all your pages.
6. **Apex redirects to www.** Visit `https://abqari.dev` (without
   www). Should redirect to `https://www.abqari.dev`.
7. **Audit report uploaded.** GitHub Actions tab → latest workflow
   run → bottom of the page should have an `audit-report` artifact.
   Download it and skim — anything red is worth addressing.

---

## Troubleshooting

### Build fails: `Could not find libvips`

You're missing libvips on the build environment.

- **Render**: ensure your build command starts with
  `sudo apt-get update && sudo apt-get install -y libvips42 libheif1 libheif-plugin-aomenc libheif-plugin-libde265 libheif-plugin-dav1d &&`
- **Cloudflare Pages / GitHub Pages**: the shipped workflows
  include the apt step automatically. If you've edited the
  workflow, make sure you didn't remove it.

You can also drop the image pipeline entirely — see
[`README.md → Images`](../README.md#images) for the `optimise: false`
config option. The build then runs without libvips and ships original
images.

### Build fails: `Vips::Error: heifsave: Unsupported compression`

libvips is installed but the libheif AV1 encoder plugin isn't, so the
pipeline can't write AVIF variants. On Ubuntu 24.04 (the base image
behind `ubuntu-latest` runners and most modern Render environments),
`libvips42` no longer pulls HEIF support in by default — it's split
into per-codec plugin packages.

The fix is to install them alongside `libvips42`:

```bash
sudo apt-get install -y libvips42 libheif1 \
                         libheif-plugin-aomenc \
                         libheif-plugin-libde265 \
                         libheif-plugin-dav1d
```

The shipped workflow files (`deploy-cloudflare.yml`,
`deploy-render.yml`, `deploy-github-pages.yml`) already do this. If
you're using Render's dashboard auto-deploy, update your build
command to include the plugin packages.

If you can't install the plugins for some reason, the image pipeline
will now degrade gracefully — it probes each format at startup, logs
a one-line warning for unsupported formats, and emits a `<picture>`
with the remaining formats only. Sites still ship, just without AVIF
variants.

### Build succeeds but custom domain shows "Site not found"

DNS hasn't propagated yet, or the records are wrong.

- Wait 30 minutes; try again.
- Run `dig +short www.abqari.dev CNAME` — if you get no output or
  the wrong target, the CNAME isn't set correctly.
- Check at [dnschecker.org](https://dnschecker.org) — if half the
  world sees the right value and half doesn't, just keep waiting.

### HTTPS shows "Not secure" or invalid cert

The host hasn't finished provisioning Let's Encrypt yet. Usually
clears within an hour; can take up to 24 hours for GitHub Pages.
Once it clears, force-refresh the page (Cmd+Shift+R) to clear the
cached error state.

### Apex domain returns a 404 or the wrong site

Your apex DNS records are wrong, or there's no apex configuration
at all. Most common fix: add an apex → www redirect at your
registrar (see [Apex vs www](#apex-vs-www) above).

### Workflow doesn't run on push to main

Check the gate variable. Repo → **Settings** → **Secrets and
variables** → **Actions** → **Variables** tab. You need
`ENABLE_CLOUDFLARE` / `ENABLE_RENDER` / `ENABLE_GITHUB_PAGES` set
to exactly `true` (case-sensitive). Without that, the workflow's
job-level `if:` condition skips silently.

### Workflow runs but reports "Required parameter is missing"

Missing secret. Look at the failing step:

- Cloudflare workflow failing on the deploy step → check
  `CLOUDFLARE_API_TOKEN`, `CLOUDFLARE_ACCOUNT_ID`,
  `CLOUDFLARE_PROJECT_NAME` are all set.
- Render workflow failing on the trigger step → check
  `RENDER_DEPLOY_HOOK_URL`.
- GitHub Pages workflow failing → check you set
  **Source: GitHub Actions** under Settings → Pages.

### Render auto-deploy AND the workflow both fire on push

You configured both. Pick one:

- Auto-deploy via Render dashboard: turn the workflow off
  (Variables tab: delete `ENABLE_RENDER` or set it to `false`).
- Workflow-driven: turn auto-deploy off in Render (Settings →
  Build & Deploy → Auto-Deploy → No).

### Images don't appear / 404 on `*.avif` files

Common when you skipped libvips on the build but kept the image
pipeline enabled. Either:

- Re-add libvips to your build command (recommended).
- Set `images.optimise: false` in `config/site.yml` (the pipeline
  passes images through unchanged; AVIF/WebP variants aren't
  generated but originals still ship).

### Site builds locally but fails on CI

Almost always a Ruby version mismatch. Check your local Ruby
version matches `.ruby-version` in the repo (e.g.
`ruby --version` should be `3.3.x`).

---

## Switching hosts later

The deploy workflows are independent — switching is a config
change, not a code change:

1. Disable the old host (Variables tab: set its `ENABLE_*` to
   `false` or delete the variable).
2. Set up the new host using the per-host steps above.
3. Push to `main`. Old workflow skips, new workflow runs.
4. Update DNS to point at the new host.

There's no lock-in. Your repo doesn't know or care which host
you deploy to — only the CNAME at your DNS provider does.

---

## Related docs

- [`README.md → Deploying`](../README.md#deploying) — short reference table for the same three hosts.
- [`README.md → Images`](../README.md#images) — the image pipeline, including how to disable it.
- [`docs/security.md`](security.md) — security model + environment-variable list.
- Workflow files in [`.github/workflows/`](../.github/workflows) — header comments document the same setup steps inline.

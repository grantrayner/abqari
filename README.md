# Abqari

[![Ruby](https://img.shields.io/badge/ruby-%E2%89%A53.3-CC342D.svg?logo=ruby)](https://www.ruby-lang.org/)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![CI](https://github.com/grantrayner/abqari/actions/workflows/ci.yml/badge.svg)](https://github.com/grantrayner/abqari/actions/workflows/ci.yml)

A small, opinionated static site generator written in Ruby.

Distributed as a Ruby gem: your site stays minimal (content, config,
optional overrides), while the engine — layouts, themes, helpers, asset
pipeline — lives in the dependency. Forking the engine is also
supported for users who want to own all the code.

> **Status:** v1.2.0 — see
> [CHANGELOG.md](https://github.com/grantrayner/abqari/blob/main/CHANGELOG.md).
> Distributed via RubyGems (`gem install abqari`) and as a Bundler
> path/git source. The API follows [semver](https://semver.org/) from
> this release onward — breaking changes bump the major version, every
> other change is backwards-compatible within a major.

## Documentation

This README is the complete guide; these cover single topics in depth.
They live in the repository rather than in the gem, so the links are
absolute.

| Guide | Covers |
| --- | --- |
| [Theming](https://github.com/grantrayner/abqari/blob/main/docs/theming.md) | Design tokens, dark mode, ejecting and customising a theme, per-theme webfonts |
| [Deploying](https://github.com/grantrayner/abqari/blob/main/docs/deploying.md) | Cloudflare Pages, GitHub Pages, Render, custom domains, troubleshooting |
| [Publications](https://github.com/grantrayner/abqari/blob/main/docs/publications.md) | The canonical publication schema, bundles, series, Folio integration |
| [Plugins](https://github.com/grantrayner/abqari/blob/main/docs/plugins.md) | Lifecycle hooks, `post_process` filters, writing a site plugin |
| [Security](https://github.com/grantrayner/abqari/blob/main/docs/security.md) | Trust boundaries, what's hardened, what's powerful by design |
| [Architecture](https://github.com/grantrayner/abqari/blob/main/docs/ARCHITECTURE.md) | How the build pipeline fits together — for contributors |

Reporting a vulnerability:
[SECURITY.md](https://github.com/grantrayner/abqari/blob/main/SECURITY.md).

## Design principles

1. **Minimal dependencies.** Seven small runtime gems — three
   (`commonmarker`, `erubi`, `ruby-vips`) do the work on every build;
   the rest cover syntax highlighting, the dev server, and CSV/Base64
   handling. Content importing needs one more (`reverse_markdown`),
   deliberately left out of the runtime set so a normal install doesn't
   pull in nokogiri for a feature it never uses.
2. **Ruby-first.** ERB templates, real Ruby in views.
3. **Rails-style structure.** `app/views/`, `app/helpers/`, `config/`.
4. **SEO baked in.** Sitemap, RSS, JSON Feed, OG, JSON-LD, robots, redirects — all native.
5. **Privacy by default.** No third-party requests. Self-hosted fonts. No tracking pixels.
6. **Fast.** WEBrick dev server, content-hashed build cache.
7. **Standard library of helpers.** truncate, pluralize, time formatting, link helpers.

## Quickstart

Abqari turns plain Markdown files into a fast, dependency-free
website you can host anywhere — Cloudflare Pages, Netlify, GitHub
Pages, your own server. This walkthrough takes you from "nothing
installed" to "site live on my laptop" in about ten minutes; no
prior Ruby experience required. If you've used Jekyll, Hugo, or
Eleventy, the shape will be familiar.

### Before you start — open a terminal, pick a projects folder

You'll be typing commands into a **terminal** (also called "command
line" or "shell"). To open one:

- **macOS**: press ⌘-Space, type `Terminal`, press Return.
- **Linux**: most desktops have a terminal app; on Ubuntu/GNOME it's
  Ctrl-Alt-T.
- **Windows**: open the Ubuntu app you installed via
  [WSL](https://learn.microsoft.com/en-us/windows/wsl/install) —
  that's where you'll run all the commands below.

The terminal opens in your home directory (typically `/Users/<you>`
on macOS or `/home/<you>` on Linux). You'll want a dedicated folder
for code projects so things stay organised. A common convention is
`~/apps/` or `~/code/` (the `~` means "your home directory"). Create
one if you don't already have it:

```bash
mkdir -p ~/apps
cd ~/apps
```

`mkdir -p` creates the folder (the `-p` part is safe to run even if
it already exists). `cd` "changes directory" — it moves the terminal
into that folder, so everything that follows happens there.

From now on, every command in this walkthrough goes into the
terminal exactly as shown. Copy a command, paste it (Cmd-V / Ctrl-V),
press Return. Wait for it to finish before running the next one.

### Step 1 — Install the prerequisites (one-time, per machine)

Three things need to be on your computer before Abqari can run.
Most macOS and Linux machines already have at least one of them; the
commands below are safe to run either way.

**Ruby 3.3 or newer** — the language Abqari is written in. Ruby 3.3,
3.4 and 4.0 are tested on every change: the full suite runs against
each, and each also gets a clean-container install of the built gem
following this quickstart.

Check what you have:

```bash
ruby --version
```

If the output is `ruby 3.3.x` (or newer), you're done with this part.
Otherwise:

- **macOS**: install [Homebrew](https://brew.sh) first if you don't
  have it, then `brew install ruby`. Homebrew prints the exact line
  to add to your shell config (`~/.zshrc` or `~/.bash_profile`) so
  your terminal can find the new Ruby — copy-paste that line, then
  restart your terminal.
- **Ubuntu / Debian Linux**: `sudo apt install ruby-full`
- **Alpine Linux**: `apk add ruby ruby-dev build-base`
- **Windows**: the smoothest path is [WSL](https://learn.microsoft.com/en-us/windows/wsl/install)
  (Windows Subsystem for Linux) — install Ubuntu via WSL, then follow
  the Ubuntu instructions inside it. Native Windows Ruby via
  [RubyInstaller](https://rubyinstaller.org/) also works but has
  rougher edges around libvips and file paths.

**libvips** — a small image-processing library Abqari uses to
generate responsive image variants (AVIF, WebP, multiple widths).

```bash
brew install vips                # macOS
sudo apt install libvips42       # Ubuntu/Debian
apk add vips                     # Alpine
```

This step is technically optional — if libvips is missing, Abqari
falls back to the `vips` / `magick` command-line tools (slower), and
if neither is available it copies images through unmodified — but the
optimised pipeline cuts image bytes by 60–80%, so install it once and
forget about it.

**Git** — for downloading Abqari and (eventually) deploying.

```bash
git --version
```

Most modern macOS and Linux installs ship with Git already. If the
command isn't found: `brew install git` on macOS, `sudo apt install git`
on Ubuntu/Debian.

### Step 2 — Install Abqari (one-time)

Install the gem from RubyGems — this puts the global `abqari` command
on your `PATH`:

```bash
gem install abqari
```

Prefer to work from a git checkout of the engine (to read or fork the
source)? Build and install it locally instead:

```bash
git clone https://github.com/grantrayner/abqari.git
cd abqari
gem build abqari.gemspec
gem install ./abqari-*.gem
```

Test that it worked:

```bash
abqari version
```

You should see a version number, e.g. `abqari 1.2.0`. If you get
`command not found`, see [Troubleshooting](#troubleshooting) below.

### Step 3 — Create your first site

Move back to your projects folder so the new site sits alongside the
engine, not inside it:

```bash
cd ~/apps
abqari new my-site
```

(Substitute your own folder name and site name. `my-site` is just an
example — anything URL-safe works.)

This:
- Creates a new folder called `my-site/`
- Fills it with everything needed for a working site (`Gemfile`,
  `config/site.yml`, sample home page, about page, example post,
  build/serve scripts)
- Runs `bundle install` automatically to fetch the gems

Takes a few seconds. When it finishes you'll see a "Next:" message.

If you'd prefer a totally clean slate — no example post, no
explanatory text on the home page, just the empty structure — add
`--blank`:

```bash
abqari new my-site --blank
```

A new site starts posts-only. To enable more collections from the
start, pass `--with` (comma-separated, any of `photos`,
`publications`, `workshops`):

```bash
abqari new my-site --with photos
abqari new my-site --with publications,workshops
```

For each collection named, the scaffold sets `enabled: true` in
`config/site.yml` and creates the `content/<name>/index.md` collection
index page with a nav entry — that index page is a real content file
the engine doesn't auto-generate, which is the fiddly part of enabling
a collection by hand. Skipped collections stay opt-in-able later: flip
`enabled:` in the config and add the index page (the config comments
show you how).

You can also pass your site's name and theme up-front to skip editing
the config later:

```bash
abqari new my-site --name "Jane's Notebook" --theme magazine --author "Jane Smith"
```

The available themes are `minimal`, `magazine`, `notebook`, `sand`,
`bootstrap`, `custom`, and `none`. You can change the theme later by
editing one line of `config/site.yml`.

### Step 4 — See your site in the browser

```bash
cd my-site
bin/serve
```

Open <http://localhost:4000> in any browser. You'll see your home
page, with the example post and the about page linked from the nav.

`bin/serve` watches for file changes — edit anything in `content/`,
`config/`, or `app/assets/` and the browser auto-reloads. Press
`Ctrl-C` in the terminal to stop the server when you're done.

### Step 5 — Edit the four files that matter

Open `my-site/` in any text editor (VS Code, Sublime Text, plain
TextEdit, etc.). Four files account for most of what a new site
needs to customise:

| File | What it controls |
|---|---|
| `config/site.yml` | Site title, description, author, theme, locale. Comments explain every option. |
| `content/index.md` | Your home page. Plain Markdown. |
| `content/about.md` | Your about page. |
| `app/assets/css/site.css` | Custom CSS that loads after the theme. Empty by default — add brand colours, font swaps, etc. |

Save any file and the browser refreshes automatically (as long as
`bin/serve` is running).

To add a new blog post:

```bash
bin/new post "My new post title"
```

This creates `content/posts/<today's date>-my-new-post-title/index.md`
with the right frontmatter already filled in. ("Frontmatter" is the
settings block between the `---` lines at the top of the file — it
tells Abqari the post's title, date, and other details, and everything
below it is the post itself.) A freshly scaffolded post looks like:

```markdown
---
title: My new post title
date: 2026-08-02
description:
tags: []
---

Your post starts here. Plain Markdown.
```

Fill in `description:` (one sentence — it shows up in listings,
search results, and social shares), add tags like
`tags: [travel, writing]`, write below the second `---`, and save. Drop images (`hero.jpg`,
`photo.jpg`, etc.) into the same folder as the post, reference them by
relative name in the Markdown (`![alt](hero.jpg)`), and Abqari's image
pipeline takes care of responsive variants.

To add a standalone page (say, a contact page) and put it in the top
navigation, run `bin/new page "Contact"`, then add a `nav:` block to
its frontmatter — the scaffolded `content/about.md` shows the shape.

### Step 6 — Build for production

When you're ready to put the site online:

```bash
bin/build
```

This writes the finished HTML to a folder called `_site/`. Upload
the contents of `_site/` to any static host:

- **Cloudflare Pages / Netlify / Vercel**: point the host at your
  site's git repository, set the build command to
  `bundle install && bin/build` (the host's build machine needs the
  gems installed first), and the output directory to `_site`. Push to
  the repo and the host takes care of the rest.
- **GitHub Pages**: same shape, with a workflow file in
  `.github/workflows/`.
- **Your own server**: `rsync -av _site/ user@server:/var/www/site/`
  or similar.

Your scaffolded site ships ready-made GitHub Actions workflows in
`.github/workflows/` for Cloudflare Pages, GitHub Pages, and Render —
open the one for your host and follow the comments at the top to
activate it. There's also a one-command `bin/deploy` script for
Cloudflare Pages and Netlify in the [engine
repo](https://github.com/grantrayner/abqari/blob/main/bin/deploy) you
can copy into your site's `bin/`; it's configured with a `deploy:`
block in `config/site.yml` (see the comments inside the script).

### Troubleshooting

**`abqari: command not found`** after `gem install`
The directory where Ruby installs gem executables isn't on your
shell's `PATH`. Run `gem env home` — it prints the path. Add
`<that-path>/bin` to your shell config:

```bash
# ~/.zshrc or ~/.bashrc
export PATH="$(gem env home)/bin:$PATH"
```

Then restart your terminal or run `source ~/.zshrc`.

**`Could not locate Gemfile`** when running `bin/serve` or `bin/build`
You're running the command from outside your site's directory.
`cd my-site/` first, then re-run.

**`bundle install` fails during `abqari new`**
Most often this is a Ruby version mismatch — Abqari requires 3.3 or
newer. Run `ruby --version` to check. If you have multiple Ruby
versions installed (via rbenv / rvm / asdf), make sure 3.3+ is the
active one.

**`Address already in use` when starting `bin/serve`**
Something already holds port 4000 — most often another Abqari site's dev
server. Either stop it, or run this one somewhere else:

```bash
ABQARI_PORT=4001 bin/serve
```

To find out what's holding the port first: `lsof -nP -iTCP:4000 -sTCP:LISTEN`.

**Browser shows the old version after I edit a file**
`bin/serve`'s live-reload depends on the optional `listen` gem. Run
`bundle install` from inside the site directory — the scaffolded
Gemfile already includes `listen` in the `:development` group.

**`ERROR Errno::ECONNRESET ... io_fillbuf` in the `bin/serve` output**
Harmless, and filtered out as of 1.1.0 — if you still see it, you're
on 1.0.0 or have `ABQARI_VERBOSE_LOG=true` set. It means a browser
closed a connection without a clean shutdown, which happens
every time you navigate: each tab holds a live-reload stream open, and
WEBrick logs the teardown as an error with a backtrace. Nothing is
wrong with your site, and it can't happen in production — the dev
server isn't part of a deploy.

**Images don't appear after I add them**
Make sure the image file sits in the same folder as the post's
`index.md` (e.g., `content/posts/<date>-my-post/hero.jpg`) and the
Markdown references it by relative name only (`![alt](hero.jpg)`,
not `/posts/.../hero.jpg`).

**Build is very slow on the first run**
Abqari's image pipeline encodes AVIF/WebP variants for every photo
on first build — slow once, instant afterwards (cached by mtime).
See [Images](#images) for the cache details.

**An error mentions "libvips" or "vips"**
Re-run `brew install vips` (macOS) or `sudo apt install libvips42`
(Ubuntu/Debian). The build falls back to plain `<img>` without
libvips, so you can also temporarily disable the pipeline by setting
`images.optimise: false` in `config/site.yml`.

### What `abqari new` actually creates

For reference — these are the files in a fresh scaffold:

```
my-site/
├── Gemfile                 # Ruby dependencies; Bundler reads this
├── README.md               # Your site's README (overwrite to taste)
├── .gitignore
├── .ruby-version           # Pinned to the Ruby that scaffolded the site
├── .github/
│   ├── workflows/          # Ready-made deploy workflows (Cloudflare,
│   │                       # GitHub Pages, Render) — opt-in, no-ops
│   │                       # until you enable them (see Deploying)
│   └── dependabot.yml      # Automated engine-update PRs
├── config/
│   └── site.yml            # Site identity, theme, collections, env URLs
├── content/
│   ├── index.md            # Home page
│   ├── about.md            # About page
│   ├── 404.md              # Not-found page (served by your host)
│   └── posts/
│       ├── index.md        # Posts landing
│       └── welcome/        # Example post (omit with --blank)
│           └── index.md
│   # --with photos,publications,workshops adds the matching
│   # content/<name>/index.md landing pages and enables them in config
├── app/
│   └── assets/
│       └── css/
│           └── site.css    # Your custom CSS override slot
├── bin/
│   ├── build               # Production build
│   ├── serve               # Dev server with live reload
│   ├── audit               # Build + check links/SEO/a11y/privacy
│   └── new                 # Scaffold a new post/page
├── public/                 # Static passthrough (favicons, robots.txt)
└── vendor/                 # Auto-populated caches (fonts, publisher data)
```

Engine code (layouts, themes, helpers, asset pipeline) lives in the
gem — your site repo stays minimal. To upgrade the engine later,
edit `Gemfile` and run `bundle update abqari`; see
[Upgrading](#upgrading).

If you'd rather assemble a site by hand (migrating from another
generator, or wanting full control over every file in your repo),
two manual paths follow — both reach the same end state without the
scaffolder.

### Path A — Add Abqari to your site as a gem (recommended)

Create a fresh directory for your site, add Abqari to its `Gemfile`,
write a minimum site structure, build.

```bash
mkdir my-site && cd my-site
git init
bundle init
```

Edit `Gemfile`:

```ruby
source 'https://rubygems.org'

gem 'abqari', '~> 1.2'

group :development do
  gem 'listen', '~> 3.8'    # optional, for the dev-server file watcher
end
```

Or — pin to a git ref while tracking pre-release work:

```ruby
gem 'abqari', git: 'https://github.com/grantrayner/abqari.git', tag: 'v1.2.0'
```

Install the libvips C library once (hard dep for the image pipeline):

```bash
brew install vips                # macOS
sudo apt install libvips42       # Ubuntu/Debian
apk add vips                     # Alpine
```

GitHub Actions `ubuntu-latest` ships with libvips preinstalled, so the CI workflow needs nothing more than `bundle install`.

Then:

```bash
bundle install
```

Your site needs only the bits that are genuinely *yours* — config,
content, public assets, and thin bin wrappers. The minimum:

```
my-site/
├── Gemfile, Gemfile.lock
├── config/
│   └── site.yml             # site config
├── content/
│   └── index.md             # home page
├── public/                  # favicons, robots.txt, etc.
└── bin/
    ├── build                # production build
    └── serve                # dev server with livereload
```

`bin/build` (chmod +x):

```ruby
#!/usr/bin/env ruby
# frozen_string_literal: true

ENV['ABQARI_ENV']       ||= 'production'
ENV['ABQARI_SITE_ROOT'] ||= File.expand_path('..', __dir__)

require 'bundler/setup'
require 'abqari'

Abqari::Site.new.build
```

`bin/serve` is the same shape but with `ABQARI_ENV` defaulting to
`development` and a final line `Abqari::Server.new(site).start`.

Minimum `config/site.yml`:

```yaml
title: My Site
description: A site built with Abqari.
author: Your Name
locale: en
theme: minimal

environments:
  development:
    url: http://localhost:4000
    indexable: false
  production:
    url: https://example.com
    indexable: true
```

Minimum `content/index.md`:

```markdown
---
title: Hello
layout: application
---

Welcome to my site, built with Abqari.
```

Build and serve:

```bash
bin/build         # builds _site/ in production mode
bin/serve         # serves on http://localhost:4000 with livereload
```

Engine code (layouts, themes, helpers, `_common.css`, asset pipeline)
loads from the gem. Drop a file at the same path inside your site to
override any specific engine file — see [Overrides](#overrides).

**Upgrading is `bundle update abqari`.** See
[Upgrading](#upgrading) for the full workflow.

### Path B — Fork the engine

If you'd rather own the engine code directly (every layout, theme,
and helper in your repo, no gem dependency), clone the engine as
your starting point:

```bash
git clone https://github.com/grantrayner/abqari my-site
cd my-site
bundle install
bin/new --name "My Blog" --locale en --theme minimal --clean
bin/serve
```

`bin/new` configures `config/site.yml` and with `--clean` removes the
example posts and resets git history. You inherit every file in the
engine repo and edit it directly. Engine updates require git-merge
from upstream (`bin/upgrade`) — see [Upgrading](#upgrading).

This path is the right call when you want to deeply customize engine
internals. For most sites, Path A is cleaner.

### Commands

A freshly scaffolded site (`abqari new`) ships eight `bin/` scripts —
`build`, `serve`, `audit`, `new`, `import`, `fetch-fonts`,
`fetch-folio`, and `index`. The rest in the table below (`deploy`,
`upgrade`, `test`) are thin one-line wrappers around the engine; add
them when you need the feature (each linked section shows the exact
contents), or inherit them all by
[forking the engine](#path-b--fork-the-engine). `bin/test` is
engine-only — it runs the engine's own suite, not your site's.

| Command | Scaffolded? | What it does |
| --- | --- | --- |
| `bin/new` | ✅ | Configure site identity, locale, theme; `--clean` to wipe examples. See [Generator](#generator). |
| `bin/new post "Title"` | ✅ | Scaffold a new post bundle: `content/posts/<date>-<slug>/index.md`. |
| `bin/new page "Title"` | ✅ | Scaffold a top-level page: `content/<slug>.md`. |
| `bin/import <platform> <source>` | ✅ | Import content from another platform's export (Substack, Ghost, Jekyll). See [Importing content](#importing-content). |
| `bin/build` | ✅ | Render the site to `_site/`. Defaults to `ABQARI_ENV=production`. |
| `bin/serve` | ✅ | Build and serve on `:4000`. Defaults to `ABQARI_ENV=development` with file-watch + livereload. |
| `bin/audit` | ✅ | Build the site, walk the output, write a markdown audit report. See [Audit](#audit). |
| `bin/fetch-fonts` | ✅ | Download self-hosted Google Fonts to `vendor/fonts/`. See [Fonts](#fonts). |
| `bin/fetch-folio` | ✅ | Force-refresh the Folio publications cache. See [Folio integration](#folio-integration). |
| `bin/index` | ✅ | Build the Pagefind search index (also auto-runs in `bin/build` when `search: true`). See [Search](#search). |
| `bin/deploy` | add as needed | Build and ship `_site/` to your configured host. See [Deploying](#deploying). |
| `bin/upgrade` | fork only | Pull engine updates from your upstream Abqari repo. See [Upgrading](#upgrading). |
| `bin/test` | engine only | Run the engine's Minitest suite. See [Testing](#testing). |

### Environment variables

Abqari reads these at build/serve time. Most sites need none of them —
they're for CI, previews, and edge cases.

| Variable | Default | Purpose |
| --- | --- | --- |
| `ABQARI_ENV` | `development` | Build environment. `production` enables indexing + minification and excludes drafts/future posts. |
| `ABQARI_SITE_ROOT` | current dir | Site root. Set by `bin/*` wrappers; override to build a site elsewhere. |
| `ABQARI_OUTPUT_DIR` | `<site>/_site` | Output directory. Refuses to wipe the site root or a source dir. |
| `ABQARI_LOG` | `info` | Log level: `debug` / `info` / `warn` / `error`. |
| `ABQARI_DEBUG` | unset | `1` prints a backtrace for user-facing errors (bad YAML, invalid config, bad flag), which are otherwise reported as a single line. Unexpected exceptions always keep their backtrace. |
| `ABQARI_INCLUDE_DRAFTS` | unset | `true` forces `published: false` posts into the build. |
| `ABQARI_INCLUDE_FUTURE` | unset | `true` forces future-dated posts into the build. |
| `ABQARI_STRICT_CONFIG` | unset | `true` turns unknown-config-key warnings (and a missing `config/site.yml`) into hard errors. Recommended in CI. |
| `ABQARI_PORT` | `4000` | Dev-server port. Useful when you run several Abqari sites and 4000 is taken. Rejects anything that isn't a number in 1–65535, rather than silently binding a port you can't guess. |
| `ABQARI_BIND` | `127.0.0.1` | Dev-server bind address. Set `0.0.0.0` to preview on a phone over LAN. |
| `ABQARI_VERBOSE_LOG` | unset | `true` restores stock WEBrick dev-server logging, including the client-disconnect backtraces Abqari filters out. For debugging the socket layer. |
| `ABQARI_SLOW_PAGE_MS` | `500` | Slow-page warning threshold (ms); `0` disables it. |
| `ABQARI_ALLOW_EXTERNAL_OUTPUT` | unset | `true` permits an output dir outside the site root (CI artifact mounts). |
| `ABQARI_ALLOW_EXTERNAL_SYMLINKS` | unset | `true` permits symlinks that escape the site root. Avoid. |

Boolean variables above accept the literal string `true` (or `1`/`yes`
for `ABQARI_DEBUG`) — `on`, `TRUE` and `y` are not recognised and read
as unset. This is deliberate: a build flag that half-matches is worse
than one that plainly doesn't.

**Secrets** (POSSE syndication + webmentions) can come from the
environment instead of committed `config/site.yml` — set these in your
CI's secret store:

| Variable | Replaces |
| --- | --- |
| `ABQARI_MASTODON_TOKEN` | `syndication.mastodon.access_token` |
| `ABQARI_BLUESKY_APP_PASSWORD` | `syndication.bluesky.app_password` |
| `ABQARI_WEBMENTION_IO_TOKEN` | `indieweb.webmention_io_token` |

> Syndication and webmention sending only fire in `ABQARI_ENV=production`
> — a dev build (`bin/serve`) never posts to Mastodon/Bluesky, even
> with `syndication.enabled: true`.

## Generator

`bin/new` is the one-shot configurator you run on a freshly cloned site. It edits `config/site.yml` in place (preserving comments) and optionally clears the example content.

```bash
bin/new --name "My Blog" \
        --description "Words about things" \
        --locale fr \
        --theme bootstrap \
        --clean
```

| Flag | What it does |
| --- | --- |
| `--name NAME` | **Required.** Sets `title:` and `author:` in `config/site.yml`. |
| `--description TEXT` | Sets `description:` (used in `<meta>`, OG tags, RSS). |
| `--locale CODE` | ISO 639-1 code (`en`, `es`, `fr`, …). Defaults to `en`. See [Locale](#locale). |
| `--theme NAME` | One of `minimal`, `magazine`, `notebook`, `sand`, `bootstrap`, `custom`, `none`. Defaults to `minimal`. |
| `--clean` | Removes example posts, audit reports, vendor fonts, and `_site/`; resets git history on a fresh `main` branch. |

Run it once after `git clone`; after that, edit `config/site.yml` directly. The generator only touches site identity and feature switches — it never modifies templates, layouts, or engine code, since those are yours to customise.

If you skip `bin/new`, the example content stays. Useful for poking around — but commit your own first commit before the example posts get tangled with your real ones.

## Importing content

If you're moving from another platform, `bin/import` pulls content from a platform export into your site's `content/<collection>/` tree. Each imported post lands as a regular Abqari bundle — same layout, same frontmatter conventions, same image pipeline — so the imported posts are indistinguishable from posts you'd write fresh.

**One-time prerequisite.** Importing needs the `reverse_markdown` gem, which Abqari doesn't install by default — it pulls in nokogiri, and a site that never imports shouldn't carry it. Uncomment the line in your `Gemfile` and `bundle install`, or:

```bash
gem install reverse_markdown
```

`bin/import` tells you this if it's missing, so there's nothing to remember up front.

```bash
bin/import substack ~/Downloads/substack-export.zip
bin/import ghost    ~/Downloads/export.json
bin/import jekyll   ~/old-site/
```

After each run, the script writes `_import_report.md` (gitignored) summarising what was imported, skipped, and warned about. Open it in your editor before committing — imports rarely need post-edit tweaks, but the report tells you exactly where to look if they do.

### Supported platforms

| Platform | Source format | Notes |
|---|---|---|
| `substack` | `.zip` (or unzipped directory) | Reads `posts.csv` + `posts/<id>.html`. Filters drafts and podcasts; paid-only posts come through with `audience: only_paid` in the frontmatter. Strips subscription widgets, share buttons, polls, and other platform chrome before HTML→Markdown conversion. |
| `ghost` | `export.json` | Reads the standard Ghost 5.x / 6.x JSON export. Filters drafts; members-only and paid posts come through with `visibility:` set in the frontmatter. Resolves tags via the export's `posts_tags` join table. Strips Ghost-specific bookmark, callout, and product cards. |
| `jekyll` | Site source directory | Reads `_posts/YYYY-MM-DD-slug.md`. Pure-markdown bodies pass through verbatim; `.html` posts run through HTML→Markdown. Merges `categories:` into `tags:`. Copies colocated assets from `assets/posts/<slug>/` (or `assets/<slug>/`) alongside the new bundle. Warns when Liquid template tags (`{% include %}`, `{% post_url %}`) need manual conversion to ERB. |

### Options

All flags are common across platforms.

| Flag | What it does |
| --- | --- |
| `--into COLLECTION` | Destination collection (default: `posts`). Use `--into notes` to import into `content/notes/`, `--into archive` into `content/archive/`, etc. |
| `--keep-remote` | Leave image URLs as remote references instead of downloading. Faster, but source-platform CDN URLs expire over time — recommended only for testing or dry-runs. |
| `--flat` | Write flat-file posts (`content/<col>/<slug>.md`) instead of the default bundle layout (`content/<col>/<slug>/index.md`). |
| `--dry-run` | Process the source but write nothing to disk. The report is also skipped — use this to preview the run. |
| `--force` | Overwrite existing files. Default is to skip files that already exist on disk, so re-running an import is safe. |
| `--canonical` | Write a `canonical_url:` frontmatter key pointing back at the source URL. For sites mirroring content rather than migrating off the source — search engines treat the source as the canonical version. |
| `--strip SEL,SEL` | Comma-separated CSS selectors (`tag` or `tag.class`) to strip from each post body before HTML→Markdown conversion. Use when the per-platform defaults don't catch every chrome block your site's export contains. |

### What you get

For each post, the importer:

1. **Parses the source** — Substack's CSV manifest + per-post HTML files, Ghost's JSON tree, or Jekyll's `_posts/` directory.
2. **Strips platform chrome** — known divs/widgets/CTAs the source platform inserts (subscribe boxes, share buttons, paywalls). Each importer ships its own selector list; extend with `--strip`.
3. **Converts HTML → Markdown** via `reverse_markdown` with GitHub-flavoured extensions. Unknown tags pass through verbatim rather than being silently dropped, so a tag the importer doesn't recognise is visible for manual cleanup rather than lost.
4. **Downloads remote images** into the post's bundle directory (default; opt out with `--keep-remote`). The image pipeline then re-encodes them to AVIF + WebP with responsive variants on the next build, exactly as it does for hand-authored posts. See [Images](#images) for the pipeline details.
5. **Resolves slug collisions** by appending a numeric suffix — duplicates become `my-post`, `my-post-2`, `my-post-3`.
6. **Writes a bundle** at `content/<collection>/YYYY-MM-DD-<slug>/index.md` containing:
   - `title`, `published: true`, `date`, optional `description` / `tags` / `image`
   - `redirect_from: [/p/<original-slug>/]` (Substack) or `[/<original-slug>/]` (Ghost) so existing inbound links keep working
   - `canonical_url:` if you passed `--canonical`
7. **Writes `_import_report.md`** in the site root summarising every post with its bundle path plus any warnings (HTTP failures, Liquid tags needing manual conversion, etc.).

### Image handling

Remote images get downloaded into the post's bundle by default. This is the durable choice: source-platform CDN URLs (`substackcdn.com/image/fetch/...`, Ghost's blob storage, Medium's image proxy) get rotated periodically, and posts that keep remote URLs break six to twenty-four months after migration.

Downloaded images sit alongside `index.md` like any hand-authored bundle asset. Abqari's [image pipeline](#images) picks them up on the next build and emits responsive AVIF + WebP variants, just as it does for bundles you authored from scratch.

If a download fails (404, timeout, oversized file), the URL is left in place and a warning lands in the report. The post still imports — one missing image doesn't sink the run.

### Idempotency

Re-running the importer over the same source is safe. Files that already exist on disk are skipped by default and show up in the report as `skipped`. Use `--force` if you've made source-side edits and want to overwrite the local copies.

If you've made local edits to imported posts and want to pull in only newly-published source posts, leave `--force` off. If you want to start fresh after a botched run, delete the relevant bundle directories first.

### Migration tips

- **Dry-run first.** `--dry-run` shows what the import would produce without writing anything. Useful for sanity-checking platform-specific quirks (paid posts, drafts, slug collisions) before you commit.
- **Commit the import as one change.** Once you've spot-checked the output, commit the new bundle directories together — the next build will optimise the downloaded images and the diff stays clean.
- **Read `_import_report.md`.** The report is the single source of truth for "what changed in this import." Glance through it for warnings before you delete it.
- **Consider `--canonical` for mirroring.** If you're keeping the source site live alongside Abqari (cross-posting from Substack, for example), pass `--canonical` so the imported posts carry `canonical_url:` pointing back. Search engines treat the source as the canonical version.
- **Custom platforms.** No importer for your source? Each importer is a single file under `lib/abqari/importers/`; the base class handles the writer pipeline (HTML→Markdown, image download, frontmatter, idempotency, report) so a new importer is just "parse this source into `ImportedPost` records." Open an issue or contribute one.

## Project structure

### Path A — Consuming site (gem dependency)

A site that consumes Abqari as a gem is small. Only the things that
are genuinely yours live in the repo; the engine code (layouts,
themes, helpers, `_common.css`, asset pipeline) is loaded from the
gem.

```
my-site/
├── .github/workflows/
│   ├── deploy-cloudflare.yml           Cloudflare Pages deploy (gated by ENABLE_CLOUDFLARE)
│   ├── deploy-render.yml               Render deploy via deploy hook (gated by ENABLE_RENDER)
│   └── deploy-github-pages.yml         GitHub Pages deploy (gated by ENABLE_GITHUB_PAGES)
├── Gemfile, Gemfile.lock               Declares the abqari gem dependency
├── bin/
│   ├── build                           Thin wrapper: requires 'abqari', builds
│   ├── serve                           Same, but for dev mode with livereload
│   ├── audit                           Site audit → audit/<timestamp>.md
│   ├── new                             Scaffold a post or page in content/
│   ├── import                          Import from Substack / Ghost / Jekyll exports
│   ├── fetch-folio                     Force-refresh the Folio cache
│   ├── fetch-fonts                     Download self-hosted Google Fonts
│   └── index                           Build the Pagefind search index (if enabled)
├── config/
│   └── site.yml                        Site config + per-environment overrides
├── content/                            Your writing (markdown + frontmatter)
│   ├── index.md                        Home page
│   ├── about.md                        About page
│   ├── posts/                          Posts collection (bundled directories)
│   │   └── 2026-05-07-hello/
│   │       ├── index.md                The post body
│   │       └── hero.jpg                Colocated assets (relative refs)
│   ├── photos/                         Photos collection (image-centric posts)
│   ├── publications/                   Publications (books, atlases, etc.)
│   └── workshops/                      Workshops (training offerings)
├── data/                               YAML/JSON data files for nav, footer, etc.
├── public/                             Static files copied verbatim → _site/
├── app/                                Optional — only present when you override
│   ├── assets/css/site.css             Site-local CSS (loads after theme)
│   ├── icons/<name>.svg                Override engine icons or add your own
│   └── views/                          Override layouts or partials
│       ├── layouts/<name>.html.erb     (rare — most users don't need this)
│       └── partials/<name>.html.erb
└── vendor/
    ├── folio/                          Folio API cache (auto-generated)
    └── fonts/                          Self-hosted webfont cache (`bin/fetch-fonts`)
```

Anything in `app/views/`, `app/assets/`, `app/icons/`, or `themes/` of
your site overrides the gem's version of the same file. See
[Overrides](#overrides) for the resolution rule.

### Path B — Forked engine

The engine repo itself is also a working Abqari site (it's used as
the fixture for development). If you fork the engine, you inherit
every file in this list:

```
abqari/
├── .github/workflows/deploy-*.yml      Three host-specific deploy workflows (Cloudflare, Render, Pages)
├── abqari.gemspec                      Gem manifest (lib/, app/, themes/, etc.)
├── app/
│   ├── assets/css/_common.css          Structural CSS (layout, components)
│   ├── assets/js/                      theme-toggle, contact, carousel, …
│   ├── icons/                          Ships GitHub, RSS, mail, X, Mastodon,
│   │                                   Bluesky, LinkedIn, sun, moon
│   └── views/
│       ├── layouts/                    application | post | photo | publication |
│       │                               bundle | series | workshop | …
│       └── partials/                   head | nav | footer | post_list |
│                                       publication_card | newsletter_subscribe | …
├── bin/                                build | serve | audit | new | check | console |
│                                       fetch-fonts | fetch-folio | icons | import |
│                                       index | deploy | upgrade | test
├── config/site.yml                     Engine fixture's site config (= the reference)
├── content/                            Engine fixture content
├── lib/
│   ├── abqari.rb                       Top-level loader (defines VERSION)
│   └── abqari/                         Generator engine — see file headers
├── themes/                             minimal | magazine | notebook | sand |
│                                       custom | bootstrap
├── test/                               Minitest suite
├── CHANGELOG.md
├── CONTRIBUTING.md
└── LICENSE                             MIT
```

## How it works

`bin/build` does five things:

1. Read `config/site.yml`.
2. Walk `content/**/*.md`, parse YAML front matter and Markdown body.
3. Convert Markdown → HTML via CommonMark + GFM.
4. Render each page through its layout (`app/views/layouts/<layout>.html.erb`).
5. Copy `public/` to `_site/` verbatim.

Each Markdown file becomes one HTML file with a "pretty URL" path. Posts are
directory bundles (`<dir>/index.md`); other content can be flat files:

| Source | Output | URL |
| --- | --- | --- |
| `content/index.md` | `_site/index.html` | `/` |
| `content/about.md` | `_site/about/index.html` | `/about/` |
| `content/posts/index.md` | `_site/posts/index.html` | `/posts/` (canonical) or `/stories/` when `posts.slug: stories` is set |
| `content/posts/2026-04-15-hello/index.md` | `_site/posts/hello/index.html` | `/posts/hello/` (canonical) or `/stories/hello/` with slug aliasing |
| `content/posts/2026-04-15-hello/photo.jpg` | `_site/posts/hello/photo.jpg` | `/posts/hello/photo.jpg` |

Post directory names follow `YYYY-MM-DD-<slug>` (date prefix optional if you set `date:` in front matter). The slug is the directory name minus the date prefix. `/tags/<tag>/` indexes are generated automatically from each post's `tags:` front matter.

Layouts have access to two locals:

- `page` — the current `Abqari::Page` (frontmatter, content, url, title)
- `site` — the `Abqari::Site` (config and all pages)

```erb
<title><%= page.title %> · <%= site.config['title'] %></title>
<%= page.content %>
```

## Templating

### Partials

Partials live in `app/views/partials/` with a leading underscore on
the filename. Render them from a layout or another partial:

```erb
<%= render 'partials/nav' %>
<%= render 'partials/publication_card', pub: card_data, idx: 0, pubs_prefix: '/books/' %>
```

Locals passed to `render` are exposed as bare identifiers in the partial:

```erb
<!-- _publication_card.html.erb -->
<article>
  <h2><%= pub[:title] %></h2>
</article>
```

`page` and `site` are always available; partials nest freely.

**Shipped partials** (rendered from default layouts, or callable from your own):

| Partial | What it does |
| --- | --- |
| `head` | Full `<head>` including OG, Twitter card, JSON-LD, feed autodiscovery, favicons, fonts.css |
| `nav` | Primary site nav (brand + links + theme toggle); driven by `data/nav.yml` and per-page `nav:` frontmatter |
| `footer` | Site footer (link row + meta + social icons + signature); driven by `data/footer.yml` and `footer.signature` config |
| `skip_link` | "Skip to content" a11y affordance |
| `theme_toggle` | Light/dark toggle button; gated by `theme_toggle` config |
| `post_list` | Card-list rendering of posts (used by `posts_index` and tag pages) |
| `pagination` | Prev / next links |
| `back_to_index` | Slug-alias-aware "back to <collection>" link for show views |
| `draft_banner`, `future_banner` | Amber banners on unpublished or future-dated pages |
| `next_item`, `related_items`, `book_related` | Show-view follow-up blocks |
| `next_in_series` | Forward-only "Next in the series" card (index-card treatment) |
| `series_pager` | Bidirectional prev/next series nav; the shape to use for ordered runs — see [Ordered series](#ordered-series-courses-multi-part-guides) |
| `testimonials` | Quote cards filtered by `data/testimonials.yml` and a book slug |
| `publication_card` | Single book rendered as a horizontal card; shared between publications index, bundle pages, series pages |
| `publication_header` | Cover + intro + buy buttons grid; used by the publication detail layout |
| `book_grid` | Card-grid of books on the home page (with optional heading) |
| `bundle_cta` | "Save with the bundle" callout on book pages |
| `book_jsonld` | `Book` schema JSON-LD for SEO |
| `contact_button` | Spam-resistant mailto button (split-half JS reassembly) |
| `newsletter_subscribe` | Provider-agnostic newsletter signup form |
| `carousel` | Slideshow component |
| `home/latest_post`, `home/latest_publication`, etc. | Home-page modules (latest post, random photo, contact, etc.) — opt-in via `home:` config |

### Helpers

A standard library of view helpers ships in `lib/abqari/helpers.rb`
and on `Abqari::RenderContext`, available everywhere ERB runs.

**Text & content**

| Helper | Example |
| --- | --- |
| `truncate(text, length:, omission:)` | `truncate(post.body, length: 200)` |
| `pluralize(count, singular, plural:)` | `pluralize(2, 'post')` → `"2 posts"` |
| `excerpt(text, words:)` | `excerpt(post.content, words: 30)` |
| `reading_time(text, wpm:)` | `reading_time(post.body)` → `"4 min read"` |
| `slugify(text)` | `slugify('Hello World!')` → `"hello-world"` |

**Time**

| Helper | Example |
| --- | --- |
| `local_time(time, format:)` | `local_time(post.date)` → `"15 April 2026"` (default), or pass `format: '%Y'` for year-only |
| `time_ago(time)` | `time_ago(post.date)` → `"3 days ago"` |
| `time_until(time)` | `time_until(event.date)` → `"in 2 weeks"` |
| `years_since(year)` | `years_since(2002)` → `"22"` (rolls over annually) |

**Links & URLs**

| Helper | Example |
| --- | --- |
| `link_to(text, url, **attrs)` | `link_to('Home', '/', class: 'nav-link')` |
| `taxonomy_url(name, term)` | `taxonomy_url('tags', 'ruby')` → `"/tags/ruby/"` — honors slug aliasing |
| `sanitized_url(url)` | strips `javascript:` and other unsafe schemes |

**Assets & icons**

| Helper | Example |
| --- | --- |
| `asset_path(name)` | `asset_path('css/app.css')` → fingerprinted URL |
| `optional_asset_path(name)` | same as `asset_path`, but returns `nil` instead of raising (useful for opt-in assets like `site.css`) |
| `picture_tag(src, alt:, sizes:, widths:)` | emits responsive `<picture>` markup |
| `icon(name, **attrs)` | `icon('github', width: 20)` — inline SVG |
| `heroicon(name, variant:)` | `heroicon('book-open', variant: :solid)` |

**Publications**

| Helper | Example |
| --- | --- |
| `publication_for(slug)` | look up a publication by slug |
| `bundle_for(slug)` | look up a bundle |
| `series_for(slug)` | look up a series |
| `buy_button(subject, label:)` | renders a buy button when the subject has `buy_now_url` |
| `cart_button(subject, label:)` | renders a cart button when the subject has `add_to_cart_url` |
| `publication_card_data(slug)` | normalised hash for the `_publication_card` partial |

**Page resolution**

| Helper | Example |
| --- | --- |
| `collection_index_url(page)` | "back to index" URL, slug-alias aware |
| `collection_index_label(page)` | corresponding label |

Helpers are plain Ruby — extend in your site by adding methods to
`Abqari::Helpers` or `Abqari::RenderContext` in your own override
file. (For consuming sites: drop a `lib/site_helpers.rb` and require
it from `bin/build` before `Abqari::Site.new`.)

## Collections

Four content collections ship as built-in defaults:

| Collection | URL prefix | Layout | Use case |
| --- | --- | --- | --- |
| `posts` | `/posts/:slug/` | `post.html.erb` | Prose blog posts — dated, tagged, RSS/JSON feed |
| `photos` | `/photos/:slug/` | `photo.html.erb` | Image-centric posts with location / camera / series metadata |
| `publications` | `/publications/:slug/` | `publication.html.erb` | Books, atlases, anything with a cover and price; integrates with Folio |
| `workshops` | `/workshops/:slug/` | `workshop.html.erb` | Training offerings: dates, location, format, instructors, registration link |

Two further built-ins — `bundles` and `series` — exist for Folio-sourced
publication groupings rather than for files you author. They take no
`content/` directory of their own; see
[Folio integration](#folio-integration) below.

Each collection has sensible defaults; configure overrides in
`config/site.yml`:

```yaml
collections:
  posts:
    source: content/posts          # source directory
    permalink: /posts/:slug/       # URL pattern
    layout: post                   # default layout
```

Permalink tokens: `:slug`, `:year`, `:month`, `:day`.

### Slug aliasing

To move posts from `/posts/<slug>/` to `/articles/<slug>/`, the
simplest path is slug aliasing: set `slug: articles` on the `posts:`
block. URL prefix, feed URL (`/articles/feed.xml`), and back-link
labels all derive from it. The source directory always stays
canonical (`content/posts/`); the layout stays canonical
(`post.html.erb`). Override `permalink:`, `layout:`, or `source:`
only when you need to depart from the slug-derived defaults.

```yaml
collections:
  posts:
    slug: stories                  # → /stories/, /stories/feed.xml
  publications:
    slug: books                    # → /books/, /books/<slug>/
```

### Custom collections

Add your own under the same `collections:` map. Set `bundle: false`
for flat single-file collections; otherwise items are directory
bundles with colocated assets:

```yaml
collections:
  recipes:
    enabled: true
    source: content/recipes
    permalink: /recipes/:slug/
    layout: recipe                 # you supply layouts/recipe.html.erb
    bundle: true                   # content/recipes/<slug>/{index.md, photo.jpg}
    show:                          # show-page knobs grouped under show:
      related:                     #   (mirrors index: for listing-page knobs)
        enabled: true
        match_by: tags
```

Custom collections work with the same per-collection `index:`,
`show:` (which nests `next:`, `related:`, `toc:`, and `cover:`), and
`feeds:` toggles as the built-ins.

### Disabling a built-in

Set `enabled: false` on any built-in collection your site doesn't
use — its source dir is left alone on disk, but no pages render,
no taxonomy entries get generated, and the collection's nav entry
disappears.

```yaml
collections:
  photos:
    enabled: false                 # site doesn't ship photos
  workshops:
    enabled: false                 # site doesn't run workshops
```

## Posts and bundles

Every post is a **directory under `content/posts/`** containing an `index.md` and any colocated assets. There's no flat-file alternative — single mode by design, fewer edge cases.

```
content/posts/2026-04-15-hello-from-the-blog/
├── index.md
├── hero.jpg
└── screenshot.png
```

Front matter on `index.md` sets title, description, tags, and optionally date:

```yaml
---
title: Hello from the blog
description: A first post.
tags: [introductions, ruby]
---
```

**The directory name is everything.** The slug is the directory name minus the `YYYY-MM-DD-` prefix (if present). Date comes from front matter (`date:`) or that same prefix.

**Bundle assets are auto-resolved.** Reference colocated files by their short relative name in markdown:

```markdown
![A hero image](hero.jpg)

Read the [docs PDF](docs.pdf).
```

At build time:
- The asset is copied to `_site/posts/<slug>/hero.jpg`
- The `<img src="hero.jpg">` in the rendered HTML is rewritten to `<img src="/posts/<slug>/hero.jpg">`
- Absolute URLs (`/assets/...`), external URLs (`https://...`), and anchor links (`#section`) are left untouched

**Why bundles?**

- Co-locate post and its assets — delete the directory, delete the post and everything it owned
- No filename collisions: every post has its own asset namespace
- Editor-friendly: working on a post and its images in one folder
- One model, no "which way do I do this?"

**Templates use `site.posts`** (sorted newest first):

```erb
<% site.posts.each do |post| %>
  <a href="<%= post.url %>"><%= post.title %></a>
  <time><%= local_time(post.date) %></time>
<% end %>
```

Posts use `app/views/layouts/post.html.erb` by default — override per page with `layout:` in front matter. For each unique tag across all posts, Abqari generates a `/tags/<slug>/` index page using `app/views/layouts/tag.html.erb`.

A landing page that lists every post is a Markdown file with `layout: posts_index`:

```yaml
---
title: Posts
layout: posts_index
---
```

### Drafts and scheduling

Add `published: false` to a post's front matter to mark it as a draft. Drafts:

- Are **excluded from production builds** entirely (no HTML, no feed entry, no sitemap entry).
- **Render in development** (`bin/serve`) with a visible amber **Draft** banner at the top of the post, so you can preview them as you write — and you can't accidentally forget a draft is unpublished.
- Are determined **only by `published: false`** — don't tag them with a `drafts` tag. Use real subject tags as you would for any post; tag taxonomies stay clean.

```yaml
---
title: Work in progress
tags: [ruby, static-sites]   # tag normally — `published: false` is what makes it a draft
published: false
---
```

When you're ready to publish, change `published: false` to `published: true` (or remove the line — published is the default). The banner disappears, the post starts appearing on `/posts/` (or your aliased URL prefix if you've set `slug:` on the collection), in feeds, and in the sitemap.

**Hide drafts in dev too.** If you'd rather see what production will look like during preview — e.g. right before deploying — set `drafts.show_in_development: false` in `config/site.yml`:

```yaml
drafts:
  show_in_development: false
```

**Force-include drafts in a production build.** Useful for catching issues that only surface under real CSP, minification, or asset fingerprinting:

```bash
ABQARI_INCLUDE_DRAFTS=true bin/build
```

### Disabling a page (parking content without deleting it)

`enabled: false` in a page's frontmatter is the page-level kill switch. The file stays in `content/` but the page produces **no HTML output, no nav entry, no sitemap entry, no feed entry, no taxonomy contribution** — in any environment.

```yaml
---
title: About
enabled: false        # parked: keep the file, ship nothing
---
```

This is different from drafts:

| Flag | Production | Development | Use case |
| --- | --- | --- | --- |
| `published: false` | hidden | rendered with **Draft** banner | in-progress writing you're previewing |
| `enabled: false` | hidden | hidden | parked content (kept in repo, not shipped) |

Flip back to `enabled: true` (or remove the line — enabled is the default) to ship.

### Scheduled (future-dated) posts

Posts with a date later than "now" — set in `date:` front matter or the `YYYY-MM-DD-` prefix on the filename — are scheduled posts. Like drafts, they:

- Are **excluded from production builds** until time catches up.
- **Render in development** with a visible blue **Scheduled** banner showing the exact moment they'll publish (date + timezone) and how far away that is.
- Get **real subject tags** like any other post (`ruby`, `releases`) — scheduled state is determined by date, not by a `scheduled` tag.

A post can be both a draft and scheduled — both banners stack.

**Important: static sites only update on rebuild.** A post scheduled for June 15 won't actually appear until the next build runs after June 15. If you want true scheduled publishing, set up a daily cron / GitHub Actions schedule that runs `bin/build` + `bin/deploy`.

**Force-include future posts in a production build:**

```bash
ABQARI_INCLUDE_FUTURE=true bin/build
```

### Timezone

Naked dates (`date: 2026-06-15`) are interpreted in the timezone configured in `config/site.yml`:

```yaml
timezone: UTC                       # default
# timezone: Asia/Singapore
# timezone: America/Los_Angeles
```

The site sets `ENV['TZ']` from this config at boot, so a date string parses to the same wall-clock moment whether the build runs on your laptop, a UTC CI runner, or anywhere else. Without this, naked dates would mean different moments on different machines.

Dates with explicit offsets (`2026-06-15T08:00:00+08:00`) keep their offset and ignore this setting.

The scheduled-post banner always shows the resolved moment with its zone, so you can tell at a glance how Abqari interpreted your date string.

### Custom taxonomies

`tags` is the default taxonomy and works out of the box. Add more in `site.yml`:

```yaml
taxonomies:
  tags:
    permalink: /tags/:slug/
    layout: tag
  categories:
    permalink: /categories/:slug/
    layout: tag
  series:
    permalink: /series/:slug/
    layout: tag
```

Posts opt into a taxonomy by setting it in front matter:

```yaml
---
title: A guide
tags: [ruby, ssg]
categories: [tutorials]
series: [getting-started]
---
```

For each unique term across all posts in a taxonomy, Abqari generates an index page at the configured permalink. Layouts use `page.taxonomy`, `page.term`, and `page.posts`.

### Ordered series (courses, multi-part guides)

A taxonomy groups pages; `series_position:` orders them. Together they cover the "module of ordered lessons" shape without any extra machinery — a lesson is a page, a module is a series.

```yaml
# config/site.yml
collections:
  lessons:
    enabled: true
    source: content/lessons
    permalink: /lessons/:slug/
    layout: lesson
    bundle: true          # directory per lesson, so audio/images colocate

taxonomies:
  lesson_modules:
    field: series         # read `series:` from frontmatter
    collection: lessons   # scope to lessons — a post in "Module 1" is a different run
    permalink: /lessons/module/:slug/
    layout: series_index
```

```yaml
---
layout: lesson
title: Greetings and introductions
series: Module 1 — First conversations
series_position: 3
---
```

Series are scoped **per collection**, matching the `<collection>_series` taxonomies: a lesson and a post that happen to share a `series:` value are independent runs, not one merged series.

Navigation comes from two `site` methods and a partial:

| | |
| --- | --- |
| `site.next_in_series(page)` | Page with the smallest position above this one, or nil |
| `site.prev_in_series(page)` | Page with the largest position below this one, or nil |
| `render 'partials/series_pager'` | Renders both as a compact prev/next nav |

```erb
<%# in your lesson layout %>
<%== render 'partials/series_pager' %>
```

`series_pager` renders nothing outside a series, and drops one side at either end without letting the other change column. For a forward-only card in the index-row style, use `next_in_series` instead — that's what the built-in `post` layout does.

`series_url(term)` resolves the series index URL for the *current page's* collection, so a layout shared between collections links each one to its own index. It returns nil when the collection has no series taxonomy configured — render the name as plain text in that case.

**`series_position` must be an unquoted Integer.** `series_position: "3"` is a String, and a String position is invisible to `prev_in_series` / `next_in_series` — the page still builds and still appears on its module index, it just silently drops out of the prev/next chain. Duplicate positions fail the same way: the comparison is strict, so two pages at position 3 can't see each other and the chain skips one. `bin/audit` reports both under **Content**, along with pages in a series that have no position at all.

## Data files

Drop YAML or JSON files in `data/` to expose structured data to templates without putting it in `site.config`. Useful for navigation menus, author bios, footer links, or anything that's not page content but isn't site-level config either.

```yaml
# data/nav.yml
links:
  - label: Home
    url: /
  - label: Stories
    url: /stories/
```

Access in any template via `site.data`:

```erb
<% site.data['nav']['links'].each do |link| %>
  <%= link_to link['label'], link['url'] %>
<% end %>
```

The filename (minus extension) is the key. `data/foo/bar.yml` flattens to `site.data['foo_bar']`. Both `.yml`/`.yaml` and `.json` work.

## Navigation and footer

Both `<nav>` and `<footer>` are auto-generated from a **three-layer cascade** so most users never write nav code, but anyone who wants full control can take it.

### How the cascade resolves

For each of nav and footer, `Site#nav_links` / `Site#footer_links` walks layers in order and stops at the first one that has content:

1. **`data/<key>.yml` `links:` array** — explicit, used as-is.
2. **Frontmatter opt-in** — pages with `nav: { order: N }` (or `footer: { order: N }`) join automatically, sorted by `order`.
3. **Empty** — the partial falls back to a sensible default (nav: a single home link; footer: just the meta line).

### Frontmatter opt-in (the easy path)

Drop a `nav:` or `footer:` block into any page's front matter:

```yaml
---
title: About
nav:
  order: 2          # lower numbers come first
  label: About me   # optional; defaults to the page title
footer:
  order: 1
  label: Imprint
---
```

The page automatically appears in the nav and the footer. To remove it, delete the block. To reorder, change the number.

The shipped [`content/about.md`](https://github.com/grantrayner/abqari/blob/main/lib/abqari/templates/site_skeleton/content/about.md.tt) is a working example: it joins the nav at order 3 and includes a "Subscribe" section with RSS and JSON Feed links — so RSS discovery isn't hidden behind `<link rel="alternate">` alone. Edit the body to make it yours, or delete the file if you don't want an about page.

### Explicit override (the power-user path)

When you need external links, multi-section nav, or a hard-coded order, drop a `links:` array into `data/nav.yml` (or `data/footer.yml`). It overrides the frontmatter cascade entirely:

```yaml
# data/nav.yml
links:
  - label: Home
    url: /
  - label: Stories
    url: /stories/
  - label: GitHub
    url: https://github.com/your-handle
```

### Social icons in the footer

Add a `social:` block to `config/site.yml`. Each key must match an SVG file in `app/icons/<key>.svg`. Out of the box: `github`, `rss`, `mail`, `x`, `mastodon`, `bluesky`, `linkedin`. Drop your own SVGs into `app/icons/` to support more services.

```yaml
# config/site.yml
social:
  github: https://github.com/your-handle
  mastodon: https://mastodon.social/@your-handle
  rss: /feed.xml
  mail: mailto:you@example.com
```

Renders as a row of inline SVG icons, sized 20×20, with `aria-label` and `rel="me"` attributes — privacy-friendly (no third-party scripts) and accessible by default.

### Customising the layout

`_nav.html.erb` and `_footer.html.erb` are yours — change the markup, add a logo, split into multi-column footer sections. The helpers (`site.nav_links`, `site.footer_links`, `site.social_links`) just give you the data; the templates control the layout.

## Pagination

Pagination is opt-in per page via front matter, with a site-wide default page size in `config/site.yml`. Pagination links only render when there's actually more than one page — a 4-post blog with the default `per_page: 10` shows no pagination at all.

| Front matter | Behaviour |
| --- | --- |
| `paginate: true` | Use the site-wide default (`pagination.per_page`, default 10) |
| `paginate: 25` | Override — 25 posts per page on this page only |
| `paginate: false` (or absent) | No pagination |

```yaml
# content/posts/index.md
---
title: Posts
layout: posts_index
paginate: true        # uses config default
---
```

To change the site-wide default:

```yaml
# config/site.yml
pagination:
  per_page: 20
```

The source page becomes `/posts/` (or `/stories/` if you set `posts.slug: stories`), with overflow at `/posts/page/2/`, `/posts/page/3/`, etc. In templates, `page.paginator` is non-nil when pagination is active and exposes:

- `paginator.posts` — this page's slice
- `paginator.page` / `paginator.total_pages`
- `paginator.first?` / `paginator.last?`
- `paginator.next_url` / `paginator.prev_url`

The shipped `_pagination.html.erb` partial wraps this:

```erb
<%= render 'partials/post_list', posts: page.paginator&.posts || site.posts %>
<%= render 'partials/pagination', paginator: page.paginator %>
```

## Assets

Anything under `app/assets/` is **fingerprinted** at build time — content-hashed filename, copied to `_site/assets/`, registered with the asset pipeline. Reference assets via `asset_path`:

```erb
<link rel="stylesheet" href="<%= asset_path('css/app.css') %>">
```

`app/assets/css/app.css` → `_site/assets/css/app.4aab61fc9e.css` and the link tag receives the hashed URL. When the file content changes, the hash changes, and caches invalidate automatically — safe to serve with `Cache-Control: max-age=31536000, immutable` from your host.

For files that should be served verbatim with no fingerprinting (favicon, robots.txt, downloadable PDFs, social images referenced from external sites), use `public/` — it's copied to `_site/` as-is.

## Syntax highlighting

Code fences in Markdown get syntax-highlighted at build time via [Rouge](https://github.com/rouge-ruby/rouge) (pure Ruby, no native deps). The build emits `/_site/assets/css/syntax.css` from a Rouge theme, and the head partial includes it automatically.

````markdown
```ruby
def shouty(text)
  text.upcase + '!'
end
```
````

…renders with proper `<span class="k">def</span>` token classes scoped under `.highlight`. Choose a Rouge theme in `site.yml`:

```yaml
syntax_theme: github       # default — see Rouge's themes for options
syntax_highlighting: false # to disable entirely
```

Rouge supports 200+ languages. Code blocks without a language fence (just triple backticks) render as plain monospace.

## Search

Static client-side search via [Pagefind](https://pagefind.app/) — a single Rust binary that walks `_site/` after build, generates a chunked search index at `_site/pagefind/`, and ships a tiny JS UI that runs entirely in the visitor's browser. No server, no API, no third-party tracking, free.

**Enable in `config/site.yml`:**

```yaml
search: true
```

**Install Pagefind once** (it's not a Ruby gem):

```bash
brew install pagefind                                    # macOS
curl -LSf https://pagefind.app/install.sh | bash         # general
cargo install pagefind                                   # via Rust
```

**Render the search box** anywhere in your templates (use the shipped partial):

```erb
<%= render 'partials/search' %>
```

The partial loads `/pagefind/pagefind-ui.{css,js}` and inits the UI inside `#abqari-search`. Both files are served from your own origin, so the strict CSP doesn't need relaxing.

When `search: true`, `bin/build` automatically runs `pagefind` after rendering. To re-index without rebuilding, run `bin/index` directly. Without Pagefind installed, the build prints a helpful warning and continues — no broken builds for users who haven't installed it yet.

## Themes

Visual styling lives in `themes/<name>/`. Pick one in `config/site.yml`:

```yaml
theme: minimal
```

Five hand-tuned themes ship by default, plus a `custom` starter
template and `none` for bring-your-own CSS:

| Theme | Description |
| --- | --- |
| `minimal` | System fonts, near-white page, blue links. The default. |
| `magazine` | Serif body (Charter), display-serif headings (Playfair Display), drop caps, warm cream palette, warm-rust accent |
| `notebook` | Mono-typeface headings (JetBrains Mono), paper + ochre palette, dense body type, dashed section dividers — docs-style aesthetic |
| `sand` | Warm earth-toned palette (Merriweather body + Merriweather Sans headings, brand-red accents); hand-rolled CSS, no framework dependency |
| `bootstrap` | Bootstrap 5.3.8 vendored (~232 KB) — use when you want Bootstrap's component library |
| `custom` | Annotated starter template — `abqari new --theme custom` copies it into your site's `themes/custom/`, ready to edit |
| `none` | No theme CSS at all — the scaffold gives you an empty `app/assets/css/app.css` to write into |

Theme files live in `themes/<name>/css/app.css` (in the gem for
Path A consumers; in your repo for Path B). At build time the active
theme's CSS ships inside the single fingerprinted bundle
(`/assets/css/bundle.<hash>.css`) along with `_common.css`, the
syntax stylesheet, and your `site.css`.

### Building your own theme

The full guide — including the complete token reference — is in
[docs/theming.md](https://github.com/grantrayner/abqari/blob/main/docs/theming.md). The short version: copy a theme
into your site with

```bash
abqari theme eject custom
```

(or `eject minimal --as mytheme` to fork an existing look under your
own name — any lowercase name works, no registration needed). Your
site-local copy shadows the gem's automatically, and edits hot-reload
under `bin/serve`.

### Architecture: tokens, not rule overrides

Themes are designed to be **mostly variable declarations**. Each
theme's `app.css` is ~150 lines, of which ~120 are `:root` + dark
deltas (palette tokens). The structural CSS — layout, components,
typography hierarchy — lives in `_common.css` (in the engine,
loaded ahead of the theme) and reads its values from CSS variables.

Themes typically override:

| Token | Role | Example |
| --- | --- | --- |
| `--color-text`, `--color-bg`, `--color-link`, `--color-primary`, … | Palette | `#212529` near-black text on `#f3f0ee` warm beige (sand) |
| `--font-body`, `--font-heading`, `--font-mono`, `--font-sans`, `--font-meta` | Typography | `"Merriweather", Georgia, serif` for body in sand |
| `--font-size-body`, `--line-height-body` | Body density | `1rem` / `1.55` in notebook (denser docs feel) |
| `--shadow-card`, `--shadow-soft`, `--shadow-cover` | Shadow tones | Warm rgba tints in sand vs cool grey in minimal |

Plus a small refinements section per theme — decorative things that
can't be expressed as a token (drop caps in magazine, `[bracket]`
notation on banners in notebook, etc.).

For consuming sites, this means **theme-tuning is one config line**:
`theme: sand` and you get the full sand palette + typography. No
need to vendor CSS.

### Light/dark toggle

Each theme has a built-in dark mode that responds to
`prefers-color-scheme` **and** a manual user toggle. The toggle is
rendered in the default nav; opt out with
`theme_toggle: false` in `config/site.yml`.

How it works:
- A tiny inline `<script>` in `<head>` reads `localStorage['theme']` and sets `<html data-theme="dark">` (or `light`) **before** render — no flash of the wrong theme.
- The strict CSP is preserved by pinning the inline script's SHA256 hash in `_headers`. No `'unsafe-inline'`.
- Each theme's CSS responds to `[data-theme="dark"]` / `[data-theme="light"]` overrides; without an attribute, `prefers-color-scheme` still wins.
- Clicking the toggle button flips `data-theme` and persists in localStorage via `app/assets/js/theme-toggle.js` (deferred, no FOUC risk).

The button shows a moon when light is active (click → switch to dark)
and a sun when dark is active. Customize the icons in
`app/icons/sun.svg` and `app/icons/moon.svg`; restyle the button via
`.theme-toggle` in your site's CSS.

## Overrides

Your site can replace any engine view, asset, or theme file by
shipping its own copy at the same relative path. Resolution order —
later wins on conflict:

1. **Engine theme** — `themes/<name>/` inside the gem
2. **Site theme** — `themes/<name>/` in your repo (same name)
3. **Engine assets** — the gem's `app/assets/`
4. **Site assets** — your repo's `app/assets/`

So `themes/minimal/css/app.css` in your site shadows the gem's minimal
theme file-for-file (that's what `abqari theme eject` sets up), and
`app/assets/css/site.css` layers on top of whatever theme is active.
Views resolve the same way: `app/views/partials/_footer.html.erb` in
your site replaces the engine's footer, and `app/icons/<name>.svg`
replaces or adds icons.

Theme names don't need to exist in the engine at all — `theme: mytheme`
plus `themes/mytheme/css/app.css` in your site is a complete custom
theme. To read the engine's copies of anything (Path A), open the
installed gem: `bundle show abqari`.

## Fonts

Self-host Google Fonts to keep your site privacy-friendly (no requests to `fonts.googleapis.com` from your visitors' browsers). Configure in `site.yml`:

```yaml
fonts:
  - family: Inter
    weights: [400, 600]
    style: normal
```

Then run once:

```bash
bin/fetch-fonts
```

Abqari downloads the woff2 files to `vendor/fonts/`, generates a `fonts.css` with rewritten URLs, and serves everything from `/assets/fonts/` at build time. The stylesheet is fingerprinted like any other asset (`/assets/fonts/fonts.<hash>.css`), so changing `fonts:` and re-running `bin/fetch-fonts` busts the immutable cache. The head partial links it whenever `fonts:` is configured and the fetch has run.

`vendor/fonts/` is git-ignored, so every deploy has to fetch the fonts too, or the site ships in fallback fonts with a green build. The shipped GitHub Actions workflows run `bin/fetch-fonts` before `bin/build`; on a host that builds from its own command (Render), add it there. Or commit `vendor/fonts/` instead. See [deploying.md → Fonts](https://github.com/grantrayner/abqari/blob/main/docs/deploying.md#fonts).

If you override the head partial, link the stylesheet with `<%= asset_path('fonts/fonts.css') %>`. An unhashed copy still ships at `/assets/fonts/fonts.css`, but `_headers` caches it for a year, so returning visitors won't see font changes.

## Icons

Inline SVGs live in `app/icons/<name>.svg`. Render from any template:

```erb
<%= icon 'github' %>
<%= icon 'rss', class: 'social', width: '20', height: '20' %>
```

Attribute hash gets merged into the SVG tag. SVGs use
`fill="currentColor"` so they inherit the surrounding text colour.

Nine icons ship by default: `github`, `rss`, `mail`, `x`, `mastodon`,
`bluesky`, `linkedin`, `sun`, `moon`. Add your own by dropping
`.svg` files into `app/icons/` (in your site overrides the gem's
version — or shadows it if the name is new).

For broader needs, `heroicon` renders any [Heroicons](https://heroicons.com)
SVG from the vendored set:

```erb
<%= heroicon 'book-open' %>
<%= heroicon 'arrow-right', variant: :mini %>
```

Variants: `:outline` (default, 24×24 stroke), `:solid` (24×24 fill),
`:mini` (20×20 fill), `:micro` (16×16 fill).

## Images

**On by default.** Every raster image the engine knows about — `app/assets/images/`, post bundle images (`content/posts/<slug>/hero.jpg`), photo collection items, flat-collection assets — gets processed into a `<picture>` block with AVIF + WebP + an optimised original-format fallback, across multiple widths.

Reference an image in markdown the normal way:

```markdown
![Hero](hero.jpg)
```

…and the build's post-process pass rewrites it to:

```html
<picture>
  <source type="image/avif" srcset="/posts/foo/hero-400.abc.avif 400w, /posts/foo/hero-800.def.avif 800w, /posts/foo/hero-1200.ghi.avif 1200w" sizes="(min-width: 768px) 50vw, 100vw">
  <source type="image/webp" srcset="..." sizes="...">
  <img src="/posts/foo/hero-1200.xyz.jpg" alt="Hero" width="1200" height="800" loading="lazy" decoding="async">
</picture>
```

### Defaults

```yaml
images:
  optimise: true                  # turn the pipeline on (default)
  processor: auto                 # auto | vips-native | vips | imagemagick
  formats: [avif, webp]           # AVIF first — browser picks first decodable
  widths: [400, 800, 1200]
  quality:
    avif: 50                      # perceptually ~= JPEG 85, ~40% smaller
    webp: 80                      # ~30% smaller than JPEG at the same quality
    original: 85                  # the JPEG/PNG fallback
  sizes: "(min-width: 768px) 50vw, 100vw"
  source_dir: app/assets/images   # site-wide imagery (not bundle images)
  preserve_metadata: false        # strip EXIF / GPS / embedded thumbnails by default
```

### Install libvips

The pipeline uses **libvips** via the `ruby-vips` gem (added to the gemspec; installed automatically by `bundle install`). The Ruby bindings are tiny pure-FFI code; the install footprint is the libvips C library:

```bash
brew install vips             # macOS
sudo apt install libvips42    # Ubuntu/Debian (since 20.04, AVIF included)
apk add vips                  # Alpine
```

GitHub Actions `ubuntu-latest` ships with libvips pre-installed. The legacy shell-out path (`vips` / `magick` CLIs) is still supported as a fallback when ruby-vips can't load — set `processor: vips` or `processor: imagemagick` to force it, or just let auto-detection do the right thing.

### What gets optimised

- **`app/assets/images/`** — site-wide imagery. Reference via `picture_tag 'hero.jpg', alt: '…'` in any layout, or as `<img src="/assets/images/hero.jpg">` in markdown.
- **Post bundle images** — `content/posts/<slug>/hero.jpg` and any other raster siblings of `index.md`. Reference via the relative path (`hero.jpg`) in the post body; `rewrite_bundle_urls` + the image pipeline take care of the rest.
- **Flat collection assets** — files under `content/publications/`, `content/workshops/`, etc. with their permalink URL prefix.

### What doesn't

- **SVG** is vector — nothing to thumbnail. SVGs pass through untouched.
- **Images smaller than the smallest requested width.** A 300px-wide source with `widths: [400, 800, 1200]` produces a single variant at 300px (its native size). Upscaling is skipped — bigger files, blurrier output, no win.
- **External URLs** (`<img src="https://…">`) — left alone.

### Storage and quality

A typical 4 MB iPhone JPEG becomes:

| Variant | Size |
|---|---|
| `hero-400.<hash>.avif` | ~30 KB |
| `hero-800.<hash>.avif` | ~80 KB |
| `hero-1200.<hash>.avif` | ~150 KB |
| `hero-400.<hash>.webp` | ~50 KB |
| `hero-800.<hash>.webp` | ~150 KB |
| `hero-1200.<hash>.webp` | ~300 KB |
| `hero-1200.<hash>.jpg` (fallback) | ~500 KB |

Roughly half the disk of the original, and each visitor downloads ~150 KB instead of 4 MB. EXIF / GPS / camera serial stripped by default (privacy + 50–500 KB extra savings per photo). Set `preserve_metadata: true` if you publish photography portfolios that surface camera info.

### Cache + determinism

Variants are fingerprinted by `<source-path>:<width>:<format>:<quality>:<source-mtime>`. Subsequent builds skip any variant whose source hasn't changed (mtime-based incrementality, sub-millisecond per variant). Two consecutive cold builds produce byte-identical output.

### Audit

`bin/audit` flags pages with heavy image payloads:

- Single image > 500 KB → warn (> 1 MB → error)
- Total image weight on one page > 1 MB → warn (> 3 MB → error)

### Disabling

`images.optimise: false` reverts to passthrough — originals copied verbatim, `<img>` left as-is. No libvips dependency required. Use when shipping a text-only site, or when you've pre-optimised your imagery upstream.

## Deploy artifacts

Every build emits the files a static host needs to serve a real site:

| File | Purpose |
| --- | --- |
| `sitemap.xml` | All URLs with accurate `<lastmod>` (max of front-matter date, source mtime, and bundle-asset mtimes). Includes Google's `<image:image>` extension for post bundle images. |
| `feed.xml` | RSS 2.0 feed of latest posts |
| `feed.json` | JSON Feed 1.1 |
| `robots.txt` | Per-environment — `Disallow: /` in dev/staging, real one in production |
| `_headers` | Security headers (CSP, HSTS, Permissions-Policy, etc.) + asset cache-control. Read by Cloudflare Pages and Netlify. Render ignores it — `bundle exec abqari headers` prints the same rules to paste in (see [deploying.md](https://github.com/grantrayner/abqari/blob/main/docs/deploying.md#headers-render-ignores-_headers)) |
| `_redirects` | 301 mappings for any post with `redirect_from:` |
| `manifest.json` | Web app manifest, populated from your site title + locale. Override colours/names under `manifest:` in `site.yml` |
| `/.well-known/security.txt` | Generated when `security_contact:` is set |
| `/llms.txt` | Curated machine-readable content index for AI readers — opt-in via `llms.enabled: true` (see [SEO and social sharing](#seo-and-social-sharing)) |
| `<page-url>og.svg` | Auto-generated social share cards — opt-in via `og_images.auto: true` (see [SEO and social sharing](#seo-and-social-sharing)) |

**Redirects** — add `redirect_from:` to a post's front matter:

```yaml
---
title: Building with Abqari
redirect_from:
  - /old-tutorial/
---
```

Abqari generates a stub HTML page at `/old-tutorial/` with a `<meta refresh>` and `<link rel=canonical>`, plus an entry in `_redirects` for hosts that read it.

**SEO meta** — every page's `<head>` includes canonical URL, Open Graph tags, Twitter card tags, RSS/JSON Feed alternates, and (for posts) JSON-LD `Article` structured data. All driven from `site.config` and frontmatter — no manual tagging required.

**Security headers** — the default `_headers` ships with a strict CSP (`'self'` only, with each of Abqari's few inline scripts pinned by SHA-256 rather than allowed by `'unsafe-inline'`), HSTS (1 year), `Referrer-Policy`, `Permissions-Policy` (camera/mic/geolocation off), `X-Content-Type-Options`, and `frame-ancestors 'none'`.

The policy is *built* from the features you've configured — enabling Plausible adds `plausible.io`, setting `newsletter.action` adds that provider's origin, and so on. You never hand-write it. Two keys extend it when the engine can't infer what you need:

```yaml
# Off-origin audio / video. Colocated bundle media needs nothing —
# it's same-origin, so it inherits `default-src 'self'`. This key
# exists for media on a CDN or object store.
media:
  host: https://media.example.com     # or a list

# Any other origin the engine doesn't model.
csp:
  img-src:     [https://cdn.example.com]
  connect-src: [https://api.example.com]
```

Both are **additive**: `'self'`, the pinned inline-script hashes, and every feature-derived origin survive. Values must be `scheme://host` — CSP keywords, wildcards and non-http schemes (`'unsafe-inline'`, `data:`, `blob:`, `*`) are rejected and fail the build rather than being silently dropped, because a malformed CSP fails open in the browser. Extendable directives: `child-src`, `connect-src`, `font-src`, `form-action`, `frame-src`, `img-src`, `manifest-src`, `media-src`, `script-src`, `style-src`, `worker-src`.

To weaken a hardening directive (`object-src`, `frame-ancestors`, `base-uri`, `default-src`) or use a non-http scheme, take over the whole header with a `headers:` block in `site.yml` — that replaces the computed policy entirely, pinned hashes included, so reach for it last.

## SEO and social sharing

Solid SEO ships as standard — there is nothing to install and no
plugin to configure. Once `environments.production.url` is set in
`config/site.yml`, every page automatically gets:

- A unique `<title>` (`Page title · Site title`) and a meta
  description (frontmatter `description:`, falling back to the page's
  first paragraph).
- A canonical URL, plus `rel="prev"/"next"` on paginated pages.
- Open Graph and Twitter card tags — including `og:image` with
  dimensions, and `article:published_time` / `article:modified_time` /
  `article:tag` on posts.
- JSON-LD structured data: `Article` on posts, `WebSite` on the home
  page, `Person` on the about page, `BreadcrumbList` site-wide, and
  `Book` / `Event` / `Course` / `ImageObject` for publications,
  workshops, and photos.
- An entry in `sitemap.xml` (with image extensions and `lastmod`),
  feed autodiscovery links, and a correct `robots.txt`.

Pages can opt out of indexing with `robots: noindex` in frontmatter —
that also drops them from the sitemap.

**Share images.** The image on a social share resolves per page:
frontmatter `share_image:` → the page's own `image:`/cover → the
site-wide `share_image:` config. And if you'd rather never think about
it, turn on auto-generated cards:

```yaml
og_images:
  auto: true
```

Every page without its own hero then gets a themed 1200×630 SVG card
(site title, page title, author, date, your theme's colours) at
`<page-url>og.svg`, wired into `og:image` automatically. Skip a
specific page with `og_image: false` in its frontmatter.

**Twitter / X identity** for share-card attribution:

```yaml
twitter:
  site:    "@yourhandle"
  creator: "@yourhandle"   # per-post override: `twitter_creator:` frontmatter
```

**AI crawlers — blocked by default, welcomed by choice.** Out of the
box, `robots.txt` blocks the major AI *training* crawlers (GPTBot,
ClaudeBot, CCBot, Google-Extended, Applebot-Extended, PerplexityBot,
and friends). Regular search engines are unaffected — blocking
Google-Extended does not touch your Google ranking. Two knobs:

```yaml
block_ai_scraping: false   # allow AI training on your content (default: true)

llms:
  enabled: true            # emit /llms.txt — a curated content index
                           # for AI/LLM readers (default: false)
```

The two are independent: you can block training crawlers while still
publishing an `/llms.txt` roadmap for AI search tools, or any other
combination that matches how you want machines to read your work.

**Near-instant navigation.** Modern browsers prerender the post links
a reader is about to click via [Speculation
Rules](https://developer.mozilla.org/en-US/docs/Web/API/Speculation_Rules_API),
on by default and strict-CSP friendly. It steps aside automatically
for readers on slow or data-saving connections. Tune or disable:

```yaml
speculation_rules:
  enabled: true          # false to omit entirely
  eagerness: moderate    # conservative / moderate / eager
  href_matches: /news/*  # default: the posts collection (/posts/*); one pattern or a list
```

Set `href_matches` when your main content isn't in `posts` — a site
whose articles live in a `news` collection prerenders nothing until it
does. The generated CSP pins the rules block by hash, so changing any
of these changes the CSP; on a host that ignores `_headers`, re-copy it.

Run `bin/audit` after building — it checks every page for missing
descriptions, broken links, missing alt text, and other SEO and
accessibility problems before you deploy.

## Deploying

Abqari produces a plain `_site/` directory of static files — deploy it anywhere that serves static HTML.

Three GitHub Actions workflows ship in `.github/workflows/`, one per first-class host. Each is **gated by an `ENABLE_*` repository variable** so they're inert until you opt in. You can enable one, any combination, or none.

| Host | Workflow file | Gate variable | Required secrets |
| --- | --- | --- | --- |
| **Cloudflare Pages** | [`deploy-cloudflare.yml`](https://github.com/grantrayner/abqari/blob/main/lib/abqari/templates/site_skeleton/.github/workflows/deploy-cloudflare.yml) | `ENABLE_CLOUDFLARE = true` | `CLOUDFLARE_API_TOKEN`, `CLOUDFLARE_ACCOUNT_ID` (+ `CLOUDFLARE_PROJECT_NAME` variable) |
| **Render** | [`deploy-render.yml`](https://github.com/grantrayner/abqari/blob/main/lib/abqari/templates/site_skeleton/.github/workflows/deploy-render.yml) | `ENABLE_RENDER = true` | `RENDER_DEPLOY_HOOK_URL` |
| **GitHub Pages** | [`deploy-github-pages.yml`](https://github.com/grantrayner/abqari/blob/main/lib/abqari/templates/site_skeleton/.github/workflows/deploy-github-pages.yml) | `ENABLE_GITHUB_PAGES = true` | None (uses OIDC) |

Gate variables live in **Settings → Secrets and variables → Actions → Variables**. Secrets live in the **Secrets** tab on the same page.

### Step-by-step setup

**See [`docs/deploying.md`](https://github.com/grantrayner/abqari/blob/main/docs/deploying.md) for the full walkthrough**, including:

- Per-host one-time setup with exact button labels and field values
- Whether to use Render's dashboard auto-deploy or the Actions-driven path
- Cloudflare API token creation (the part where most people get stuck)
- DNS configuration: CNAME for `www`, apex domain options, propagation verification
- Custom domain setup on each host
- A verification checklist for after the first deploy
- Troubleshooting reference for the common failure modes

### Quick start (Render dashboard, no workflow needed)

If you just want a site live quickly, the simplest path is Render's dashboard. No GitHub secrets, no workflow files:

1. Sign in at [dashboard.render.com](https://dashboard.render.com), click **New +** → **Static Site**, connect your repo.
2. Build command: `sudo apt-get update && sudo apt-get install -y libvips42 libheif1 libheif-plugin-aomenc libheif-plugin-libde265 libheif-plugin-dav1d && bundle install && bundle exec bin/build`
   (It looks long, but it's just three steps: install the image
   library on Render's build machine, install the Ruby gems, build
   the site. Copy it verbatim.)
3. Publish directory: `_site`. Environment variable: `ABQARI_ENV=production`.
4. Click **Create Static Site**. Wait ~3-5 minutes for the first build.

The site is live at `<name>.onrender.com`. Add a custom domain via **Settings → Custom Domains** — Render gives you a CNAME target to add at your registrar.

For everything else (Cloudflare Pages, GitHub Pages, Actions-gated Render, DNS, troubleshooting), see [`docs/deploying.md`](https://github.com/grantrayner/abqari/blob/main/docs/deploying.md).

### Other hosts

| Host | Approach |
| --- | --- |
| **Netlify** | Add a Netlify deploy step using [`nwtgck/actions-netlify`](https://github.com/nwtgck/actions-netlify); same shape as the Cloudflare workflow |
| **S3 + CloudFront** | `aws s3 sync _site s3://your-bucket/ --delete` after build |
| **Anywhere static** | Upload `_site/` via FTP/rsync/SCP/whatever |

The audit report is uploaded as a GitHub Actions artifact on every run, so you can review accessibility/SEO/dependency findings even when the site deploys successfully.

## Visualizations

Off by default. When enabled, Abqari generates D3-powered visualizations of your site's content at build time — JSON data + a viz page per chart, rendered entirely client-side from vendored D3 (~280 KB, loaded only on the viz routes).

```yaml
visualizations:
  tag_bubble: true             # /visualizations/tag-bubble/
  tag_cooccurrence: true       # /visualizations/tag-cooccurrence/
  topic_constellation: true    # /visualizations/topic-constellation/
```

| Viz | What it shows | Useful when |
| --- | --- | --- |
| **Tag Bubble** | Circle pack of all tags, area = post count per tag | Spotting where you write most (and tags you haven't returned to) |
| **Tag Co-occurrence** | Chord diagram of which tags appear together | Surfacing topic clusters across multi-tagged posts |
| **Topic Constellation** | Force-directed graph: posts as nodes, links for shared tags | Exploring how your posts relate; clicking a node navigates to it |

Each visualization is independent — turn one on without the others. When all three are off, no JSON is written, no pages are generated, D3 isn't pulled into the build.

**How it works**: at build time, `Site#build` runs `Visualizations#write_data` to compute and emit the JSON files into `_site/visualizations/<name>.json` (data derived from `site.posts` and `site.posts_by_term`). It also adds a `VizPage` to `@generated_pages` for each enabled viz, which renders through the normal pipeline (post-process, minification, incremental check). Each viz page loads `/assets/d3/d3.v7.min.js` and the matching `/assets/js/viz-<name>.<hash>.js`, fetches the JSON, and renders into `#viz-container`.

**No third-party requests**: D3 is vendored, served from your origin. Strict CSP keeps working.

**Performance**: the 280 KB D3 bundle only loads on the three viz pages — site-wide pages stay JS-free.

**Theming**: SVG strokes and text use `currentColor`, so the visualizations honour the active light/dark theme automatically. Fill colours come from a fixed palette suitable for both modes.

**Linking**: viz pages are not auto-included in the nav. Add a link from anywhere — e.g. in `_footer.html.erb` or an "Explore" page — pointing at `/visualizations/<name>/`.

## Contact button

A spam-resistant contact button for your About page. Off by default. To enable, add your email under `contact:` in `config/site.yml`:

```yaml
contact:
  email: you@example.com
  label: Get in touch       # optional, defaults to "Contact"
```

That's it. The button appears at the bottom of `/about/` on the next build.

**How the spam protection works**: the address is split at `@` into `data-user` and `data-domain` attributes. The rendered HTML never contains a string with `@` in it, and there's no `mailto:` prefix anywhere. A 16-line JS file rejoins the halves and opens the user's mail client only after the visitor clicks. Naive scrapers (which is most of them) see HTML and walk away with nothing.

**Removing the button**: any of three works.
- Clear the email field in `config/site.yml` — `contact.email:` (no value).
- Change `layout: about` to `layout: application` in `content/about.md`.
- Delete `app/views/layouts/about.html.erb`.

**Putting it elsewhere**: render the partial from any layout — footer, sidebar, dedicated contact page:

```erb
<%= render 'partials/contact_button' %>
```

The partial honours the same config and renders nothing when `email` is unset, so dropping it into a shared layout is safe.

## Newsletter signup

A provider-agnostic subscription form — works with any service that
accepts an HTML form POST (Mailchimp, Buttondown, ConvertKit / Kit,
Substack, Cogent Notes, …). Configure the provider in `site.yml`:

```yaml
newsletter:
  action: https://your-provider.example/subscribe   # required
  email_field: email               # the provider's email input name
  title: Subscribe to the newsletter
  description: One short email a month — no spam.
  button: Subscribe
  # hidden_fields:                 # provider-specific extras (tags,
  #   - { name: tags, value: blog }   # honeypots, list ids)
```

Then render the form wherever you want it — a layout, the footer, a
dedicated page:

```erb
<%= render 'partials/newsletter_subscribe' %>
```

Per-call overrides (`title:`, `description:`, `button:`) let one site
run different pitches in different places. When `newsletter.action` is
unset the partial renders nothing, so it's safe to leave the call in
place before you've picked a provider. The provider's origin is added
to the CSP `form-action` automatically.

## Analytics with Plausible

Privacy-friendly analytics with no cookies and no consent banner
(~1 KB tracker). Off by default; both keys are required to enable:

```yaml
plausible:
  enabled: true
  key: pa-your-script-key   # the slug in https://plausible.io/js/<key>.js
```

Abqari injects the tracker into `<head>` and extends the CSP for
`plausible.io` automatically — no manual header work. Because both
`enabled:` and `key:` must be set, you can keep the key in config with
`enabled: false` and tracking stays off.

## IndieWeb & federation

Off by default. When `indieweb.enabled: true`, the build adds:

- **Microformats2 markup** (`h-entry`, `h-card`, `u-url`, `dt-published`, `e-content`, `p-category`, `p-name`, `p-summary`, `h-feed`) baked into the post, post-list, and about layouts. Invisible class attributes — no visual change. Lets other IndieWeb sites and federated tools parse your content cleanly.
- **Webmention discovery** — `<link rel="webmention">` in `<head>` points incoming notifications at [webmention.io](https://webmention.io) on your behalf. Your site stays static; webmention.io catches replies/likes/reposts from other people's sites.
- **Webmention rendering** — a "Replies & mentions" section below each post, pulled from webmention.io's cached JF2 feed at build time. Conversational mentions (in-reply-to, mention-of) get the full author + body card; likes / reposts / bookmarks render facepile-style (avatar grid). No JavaScript, no comment backend, no moderation queue — spam is structurally rare because replies have to be published on real websites first.
- **Webmention send** — opt-in. When `send_webmentions: true`, the build POSTs notifications to external URLs your posts link to so the authors of those posts see you've cited them. Tracked in `vendor/webmentions/sent.yml` so re-builds don't double-send. Only runs against posts published within the last `send_window_days` (default 30).
- **Bridgy Fed link tags** — opt-in. When `bridgy_fed: true`, the head emits `rel="me"` and `rel="alternate" type="application/activity+json"` tags pointing at [Bridgy Fed](https://fed.brid.gy), which speaks ActivityPub on your behalf. Mastodon users can then search `@<your-domain>` and follow the site directly.

### Setup

1. Visit [webmention.io](https://webmention.io) and sign in with your domain. The login flow uses `rel="me"` verification — make sure `social:` in `config/site.yml` carries at least one social profile that links back to your domain.
2. Copy the API token from your webmention.io account page.
3. (Optional) Visit [fed.brid.gy](https://fed.brid.gy) and complete its setup (same `rel="me"` pattern).
4. Add to `config/site.yml`:

```yaml
indieweb:
  enabled: true
  domain: example.com               # bare host, no scheme
  webmention_io_token: "..."        # from webmention.io account page
  bridgy_fed: false                 # true once Bridgy Fed setup complete
  send_webmentions: false           # POST to sites your posts link to
  send_window_days: 30
```

### How it works at build time

| Step | What happens |
|---|---|
| 1. Fetch | `Indieweb::Fetcher` pulls `https://webmention.io/api/mentions.jf2?domain=…&token=…` with an ETag header. 304 responses reuse the cached `vendor/webmentions/mentions.json`. |
| 2. Index | Mentions are grouped by target URL (path-normalised so `/posts/foo` and `/posts/foo/` collapse to one key). |
| 3. Render | Each post layout calls `site.webmentions_for(page.url)`; the `_webmentions` partial renders the matching mentions in a `<section class="webmentions">` below the body. |
| 4. Send | After render, `Indieweb::Sender` walks posts published within `send_window_days`, extracts outbound external URLs, discovers each target's webmention endpoint (HEAD `Link:` header → GET `<link rel="webmention">`), POSTs a notification, and logs the result. |

### Per-post overrides

- Set `webmentions: false` in a post's frontmatter to suppress the `_webmentions` partial for that post.
- The send-window means historical posts aren't replayed on every CI run — they were already notified in earlier builds.

### Honest limits

- Webmention adoption is uneven — maybe 10–20% of personal sites support sending them. Growing, but not universal.
- Bridgy Fed is a third-party service. You don't control the federation hop; outages affect your Fediverse presence.
- `webmention.io` is also a third-party service. The integration falls back to cached data on outages but a long outage means no new mentions render.

## POSSE — Publish on Own Site, Syndicate Elsewhere

Off by default. When `syndication.enabled: true`, the build POSTs a short summary + canonical URL of each new post to the configured networks (Mastodon, Bluesky). The originating posts on those networks point back at your canonical URL on your site.

```yaml
# config/site.yml
syndication:
  enabled: true
  window_days: 14                   # only syndicate posts from the last N days
  mastodon:
    enabled: true
    instance: https://mastodon.social
    access_token: "..."             # write:statuses scope
    visibility: public              # public | unlisted | private
  bluesky:
    enabled: true
    handle: yourname.bsky.social
    app_password: "..."             # NOT your account password
```

### Setup

- **Mastodon.** In your instance UI: Preferences → Development → New Application. Scope: `write:statuses`. Copy the access token.
- **Bluesky.** In the Bluesky app: Settings → App Passwords → Add. Use the generated app password (never your account password).

### How it works at build time

| Step | What happens |
|---|---|
| 1. Filter | `Syndication::Dispatcher` walks posts published within `window_days` (default 14). |
| 2. Format | `Syndication::Formatter.snippet_for(post, url, limit:)` builds `<title> — <description> <url>` and truncates the description to fit each network's character cap (Mastodon 500, Bluesky 300). |
| 3. POST | Each configured network adapter (`Networks::Mastodon`, `Networks::Bluesky`) authenticates and posts. The resulting URL on that network is returned. |
| 4. Log | Every successful syndication is recorded in `vendor/syndication/sent.yml` keyed by `<network>|<canonical_url>`. Re-builds skip any post already marked `status: sent`. Failures are logged but retried on the next build — a transient API outage shouldn't permanently skip a post. |

### Per-post overrides

- `syndicate: false` in a post's frontmatter excludes that post from POSSE entirely.
- `syndication_text: "..."` supplies a custom snippet, bypassing the auto-formatter (still subject to the per-network length cap).

### Reply collection

When **both** IndieWeb and POSSE are enabled, the flow is:

1. You publish a post; the build syndicates to Mastodon + Bluesky.
2. A reader replies on Mastodon.
3. Bridgy Fed translates the AP reply into a webmention sent to webmention.io.
4. Next build, webmention.io's API returns it.
5. The post's "Replies & mentions" section now shows the Mastodon reply alongside any direct webmentions from other personal sites.

You wrote once; conversations from three networks consolidate under the canonical post.

### Honest limits

- App tokens expire. Plan for an annual rotation.
- Each network has its own character limits and content-policy quirks. Long titles can squeeze out the description.
- Bluesky's link-facet rendering uses UTF-8 **byte** offsets, not character offsets — the adapter handles this, but it's worth knowing if you're debugging odd link placement.

## Folio integration

Off by default. When `folio:` is configured, Abqari pulls book/bundle data from a [Folio](https://www.foliobooks.app) storefront at build time and auto-generates pages for each entity. The visitor never makes a request to Folio — all data is baked into the static HTML.

```yaml
# config/site.yml
folio:
  base_url: https://www.foliobooks.app
  author_slug: your-author-slug
  # covers_host: https://covers.example — only if your Folio instance
  # serves cover images from a host other than the default
  # covers.foliobooks.app CDN. Whatever host is in effect is added to
  # the CSP's img-src automatically.
```

That's it. On the next build:

```
Folio: loaded 4 publication(s), 1 bundle(s), 0 series
```

Auto-generated pages:

| URL | What it is |
| --- | --- |
| `/books/` | Index of all your books |
| `/books/<slug>/` | One detail page per Folio publication |
| `/bundles/` | Index of bundles |
| `/bundles/<slug>/` | Detail page per Folio bundle |
| `/series/` | Index of series |
| `/series/<slug>/` | Detail page per series |

**Three endpoints, three collections.** Abqari calls `/api/v1/authors/:slug/publications.json`, `/bundles.json`, and `/series.json`. Each response is cached and ETag-revalidated independently.

**Override any auto-generated page** by creating a markdown file at
the matching path. For example, to add a custom intro on
`/books/memoirs-of-an-assassin/`:

```markdown
---
title: Memoirs of an Assassin
---

A first-person reckoning with the trade. The free sample below…
```

Auto-rendered cover, price, and buy/cart buttons stay where they
are; your markdown body is appended after them.

### Manual bundles and series (no Folio)

Bundle and series pages don't *require* Folio. You can hand-author
them entirely via frontmatter — useful for sites without a
storefront, or to add manual bundles alongside externally-sourced
ones. Manual pages always win on slug collision.

For a bundle, create `content/bundles/<slug>/index.md`:

```yaml
---
layout: bundle
name: The Assassin Books            # bundles + series use `name:`,
                                    #   not `title:` (per docs/publications.md)
description: Both novels in the series, packaged together.
price: $16.98                       # auto-expands to the canonical
                                    #   { cents:, currency:, formatted: } hash
buy_now_url: https://example.com/buy
buy_label: Buy the bundle           # default "Buy now"
publications:
  - memoirs-of-an-assassin          # bare slug
  - the-russia-assignment           # bare slug
---
```

For a series, the same shape applies. Each publication entry can
also be a hash with `position:` for the per-card "#N" prefix:

```yaml
---
layout: series
name: Memoirs of an Assassin
description: A series of psychological thrillers.
tagline: Two novels, one arc.
buy_now_url: https://example.com/series
publications:
  - { slug: memoirs-of-an-assassin, position: 1 }
  - { slug: the-russia-assignment,  position: 2 }
---
```

Each entry's slug is resolved against `site.collection('publications')`
— which automatically merges manual content pages with any
externally-sourced entries (Folio, etc.) — so each card carries
title + cover + description + price drawn from the publication's
own canonical frontmatter regardless of source. **One source of
truth per book.**

The same publication-card markup is used by the publications index,
bundle "What's included" lists, and series "Books in this series"
lists — driven by the shared `_publication_card` partial. Visual
treatment is consistent across all three contexts.

**Helpers** available in any layout/partial:

| Helper | What it returns |
| --- | --- |
| `publication_for(slug)` | Publication frontmatter hash, or nil |
| `bundle_for(slug)` | Bundle frontmatter hash, or nil |
| `series_for(slug)` | Series frontmatter hash, or nil |
| `buy_button(subject, label:)` | `<a>` tag when `buy_now_url` is set, else empty string |
| `cart_button(subject, label:)` | `<a>` tag when `add_to_cart_url` is set, else empty string |

`subject` accepts a frontmatter hash, a page-like object, or a slug string.

**Cache.** Folio responses are cached in `vendor/folio/{publications,bundles,series}.yml` with ETag conditional-GET. Subsequent builds get a `304 Not Modified` and reuse the cache. If Folio is briefly unreachable (CI runner offline, etc.), Abqari falls back to the cached data and prints a warning rather than failing the build.

```bash
bin/fetch-folio    # force-refresh the cache (drops ETags)
```

**JSON-LD.** Each book page emits a `Book` schema with author, ISBN, price, language, and availability — pulled from the page's canonical frontmatter (works equally for manual content and externally-sourced entries). No extra config needed.

**Layouts and partials.** The engine ships:

- Layouts — `publication.html.erb`, `bundle.html.erb`, `series.html.erb`, `publications_index.html.erb`, `bundles_index.html.erb`, `book_series_index.html.erb`. (`publication` is named for the canonical collection; `slug: books` on the collection puts it at `/books/<slug>/` without renaming the layout file.)
- Partials — `_publication_header.html.erb` (cover + intro grid on publication detail pages), `_publication_card.html.erb` (shared between the publications index, bundle "What's included", and series "Books in this series"), `_book_jsonld.html.erb` (Book schema for SEO), `_bundle_cta.html.erb` ("save with the bundle" callout).

Customise by overriding in your site (Path A — drop a same-pathed file in `app/views/`) or editing in place (Path B — fork).

## Accessibility

Abqari ships with a WCAG-aware baseline so an out-of-the-box site is usable by keyboard and screen-reader visitors without you having to think about it.

What's already wired in:

| Feature | What it does |
| --- | --- |
| **Skip-to-content link** | First focusable element on every page; visually hidden until tabbed to. Targets `<main id="main-content">` so keyboard users bypass the nav. Defined in [`_skip_link.html.erb`](https://github.com/grantrayner/abqari/blob/main/app/views/partials/_skip_link.html.erb) |
| **`<main>` landmark** | Every layout wraps content in `<main id="main-content" tabindex="-1">` for the skip-link target and screen-reader "jump to main" navigation |
| **`aria-label="Primary"`** on the site nav | Disambiguates from pagination / footer navs in screen readers |
| **`aria-label="Pagination"`** on pagination | Same — pagination shows up as "Pagination, navigation" instead of generic "navigation" |
| **`aria-pressed`** on the theme toggle | Screen-reader users hear the current state ("pressed" = dark mode on); JS keeps it in sync with `data-theme` |
| **`:focus-visible` outline** | Keyboard users see where focus is; mouse clicks don't show an outline (the modern `:focus-visible` rule, not `:focus`). Defined per theme in `themes/<name>/css/app.css` |
| **`prefers-reduced-motion`** | All themes honour the OS-level "reduce motion" preference for users with vestibular disorders |
| **Icons** | Every shipped SVG has `aria-hidden="true"` so screen readers don't announce them; the surrounding link/button has the accessible label |
| **`<html lang>`** | Set on every layout from `locale:` config — required for screen-reader pronunciation |
| **Image alt text enforcement** | `bin/audit` errors on any `<img>` without `alt`; helpers like `picture_tag` require an `alt:` argument |
| **Heading hierarchy check** | `bin/audit` warns on multiple `<h1>` per page |
| **Landmark + skip-link check** | `bin/audit` warns on missing skip link, missing `<main>`, or unlabeled multi-`<nav>` pages |

If you build your own layout or partial, the audit catches the common mistakes. The four pieces of advice that the audit *doesn't* enforce automatically:

1. Don't put text inside `<button>` as an icon-only graphic — the button needs text or `aria-label`.
2. Form inputs need `<label>` elements (Pagefind's search UI handles this internally).
3. Color contrast is the theme's responsibility — the built-in themes are designed to meet WCAG AA in both light and dark modes; verify yours if you customise.
4. If you add motion (animations, parallax), gate it behind `@media (prefers-reduced-motion: no-preference)`.

To remove any of the baseline pieces (e.g. you don't want the skip link), edit the relevant partial or layout. Everything is yours after `git clone`.

## Audit

```bash
bin/audit
```

```
Built 9 page(s) in production → _site/
Audit complete: audit/2026-05-07-1928.md (0 error, 1 warn, 3 info)
```

Rebuilds the site, walks the output, and writes a markdown report to `audit/<YYYY-MM-DD-HHMM>.md` covering:

| Category | Checks |
| --- | --- |
| **Links** | Broken internal links and asset references |
| **SEO** | Title length (>60), description length (>160 or missing), duplicate titles |
| **Accessibility** | Images without `alt`, multiple `<h1>` per page |
| **Privacy** | External resource loads (URLs not on the site host) |
| **Dependencies** | Outdated gems via `bundle outdated`, CVEs via `bundle-audit` (if installed) |
| **Content** | Posts without descriptions, single-use tags, `series_position` problems that break prev/next silently (non-Integer, duplicate, or missing) |
| **Security** | Inline code the built `_headers` CSP would block: `style="…"` attributes, `<style>` blocks, `on…=` handlers, and inline scripts whose hash isn't in `script-src`. Errors, because the page breaks on any host that enforces the policy |

The report opens with a summary table, a **Suggested fixes** code block listing every `bundle update <gem>` command needed to clear the dependency findings, and then groups findings by category with severity (`error`, `warn`, `info`) and a suggestion where applicable. Reports accumulate in `audit/` — useful to commit so you have a diffable history of site quality over time.

### Dependency security check

For CVE scanning, install `bundler-audit` once:

```bash
gem install bundler-audit
```

When it's available, the audit runs `bundle-audit check --update` (which refreshes the `ruby-advisory-db` of ~1000 known advisories) and parses every finding into a structured report:

- **Severity** — Critical/High → `error`, Medium → `warn`, Low → `info` — driven by the CVE's own criticality
- **Identifier** — GHSA or CVE number, with a link to the advisory
- **Vulnerable version** — what's currently in your `Gemfile.lock`
- **Title** — the human-readable advisory description
- **Upgrade path** — the version constraint that resolves the issue (e.g., `~> 5.2.4.4, >= 6.0.3.3`)
- **Suggested command** — `bundle update <gem>` you can copy/paste

Plus, every outdated (non-security) gem is listed via `bundle outdated --strict`, with installed-vs-latest versions and the `bundle update` command per gem.

Without `bundle-audit` installed, the audit still runs — the dependencies section just notes the CVE check was skipped.

### Compared to Dependabot

GitHub Dependabot does three things abqari's audit does **not**:

- **Runs continuously.** Dependabot scans your repo daily and notifies on new advisories. `bin/audit` is on-demand — run it before deploying, or wire it into CI.
- **Opens pull requests.** Dependabot creates per-gem PRs with the changelog and patch. The audit gives you the exact `bundle update` command, but you run it yourself.
- **Aggregates across the org.** Dependabot is a GitHub-hosted service. The audit is local.

What `bin/audit` does that Dependabot doesn't:

- **Same report covers links, SEO, accessibility, privacy, content, and the CSP.** Dependabot only watches dependencies.
- **Uses the same `ruby-advisory-db`** Dependabot's Ruby ecosystem coverage uses, just at a single point in time.
- **Outputs to git-trackable markdown.** A diffable `audit/` history of every check you've run.

Use both: Dependabot (or similar) for continuous monitoring and PR creation; `bin/audit` for a single comprehensive snapshot you can review before deploys.

## Testing

```bash
bin/test
```

The engine ships with a Minitest suite under `test/` — around 80 test
files and 900 tests, running in about a minute. Coverage
spans helpers, paginator logic, full site builds, deploy artifacts,
SEO meta (canonicals, OG cards, feeds, sitemap escaping), the audit
run, the CLI scaffolder, content importers, IndieWeb/syndication,
security hardening, and theme resolution. Test dependencies
(`minitest`, plus `ostruct`/`rexml` for stubs and XML validation,
`listen` for the watcher, and opt-in `simplecov` for coverage) are
declared under `group :development` in the Gemfile, so production
deploys don't pull them.

Tests only ship with the engine fork (Path B). For consuming sites
(Path A), the engine's test suite isn't relevant — the gem itself is
tested upstream; your site has its own tests if you write them.

A few orientation points in the tree:

```
test/
├── test_helper.rb        Shared bootstrap; builds the fixture site once per run to a tmpdir
├── helpers_test.rb       truncate / pluralize / slugify / time / link_to / excerpt
├── paginator_test.rb     prev/next URL generation across edge cases
├── site_test.rb          Full-build integration: pages, pagination, tags, theme, SEO, deploy artifacts
├── audit_test.rb         Audit runs cleanly and writes a report
├── cli_new_test.rb       `abqari new` scaffolding, --with/--blank modes, config drift guards
├── importers/            Substack / Ghost / Jekyll import pipelines
└── …                     One topic per file — grep for the feature name
```

Tests build to `$TMPDIR/abqari-test-site/` so they never clobber `_site/`; the temp dir is removed automatically when the run ends.

Add your own under `test/<name>_test.rb` — `bin/test` picks them up automatically. Test files just need to `require_relative 'test_helper'` and define a `Minitest::Test` subclass:

```ruby
require_relative 'test_helper'

class MyFeatureTest < Minitest::Test
  def test_something
    assert_equal 42, 6 * 7
  end
end
```

Run a single test file: `bundle exec ruby -Ilib -Itest test/helpers_test.rb`. Run a single test method: `bundle exec ruby -Ilib -Itest test/helpers_test.rb -n test_slugify_lowercases_and_dashes`.

## Livereload

`bin/serve` watches `content/`, `app/`, `themes/`, `config/`, `lib/`, `data/`, and `plugins/` for changes. On change:

1. The build runs incrementally (no `_site/` wipe; mtime-aware copies skip unchanged work).
2. The build version bumps and the watcher classifies the change scope.
3. Each rendered page in dev opens a Server-Sent Events stream to `/__reload__`; when the server pushes a rebuild event the client either:
   - **Swaps the `<link rel="stylesheet">` href** in place if only CSS files changed (preserves scroll position and form state), or
   - **Reloads the page** if anything else changed.

**Ruby isn't reloaded.** Plugins, and anything they `require` from `lib/`, load once when `bin/serve` starts. When one of those files changes, the server logs a one-line warning naming it; restart `bin/serve` to load the new code. If a build fails while that code is stale, the failure output ends with the same reminder, because the usual symptom is `NoMethodError: undefined method '…' for an instance of Abqari::RenderContext` from a layout calling a helper the server hasn't loaded.

**Watcher backend.** When the `listen` gem is installed (it's a development-group dep), the watcher uses native FS events (FSEvents on macOS, inotify on Linux) — zero overhead between changes. Without `listen`, it falls back to 500ms mtime polling. Both modes debounce events by 100ms so editor tools that fire two events per save don't double-rebuild.

**Transport.** Server-Sent Events (SSE) over plain HTTP — no WebSocket dep, works through any proxy. The browser opens a single persistent EventSource per tab; the server pushes events with sub-50ms median latency. Connection auto-reconnects if the dev server restarts. The script is only injected when `ABQARI_ENV=development`, so production builds are clean.

## Plugins

Drop a Ruby file into `<site_root>/plugins/`. It's auto-loaded once at `Site.new` and can register callbacks for lifecycle events:

```ruby
# plugins/word_counter.rb
Abqari::Hooks.register(:post_process) do |html, _site, page|
  next html unless page.respond_to?(:post?) && page.post?

  words = html.gsub(/<[^>]+>/, '').split(/\s+/).size
  html.sub('</article>', %(<footer>~#{words} words</footer></article>))
end
```

Lifecycle events: `:before_build`, `:after_load_pages`, `:after_generate`, `:after_build`. Filters: `:post_process(html, site, page)`. Full reference in [`docs/plugins.md`](https://github.com/grantrayner/abqari/blob/main/docs/plugins.md).

`bin/serve` doesn't reload plugins, so restart it after editing one. It warns you when it sees the change (see [Livereload](#livereload)).

## Performance

Build-time and runtime perf are already tuned for typical sites (~50–200 pages). What's baked in:

**Build-time:**
- **Compiled-template cache.** ERB layouts and partials are compiled once per build and reused across all pages — so 500 pages × 10 partials becomes 10 disk reads, not 5000.
- **Memoized markdown rendering.** Each post's body is parsed once, even if a layout calls `page.content` plus `excerpt(page.content)` plus `reading_time(page.content)`.
- **Content-hashed asset caching.** Fingerprinted assets that already exist with a matching name (matching content) are skipped — no rehash, no recopy.
- **Mtime-aware bundle/public/font copying.** Files only copy when the source is newer than the destination.
- **Parallel page rendering.** For sites with 16+ pages, rendering runs on a thread pool sized to `Etc.nprocessors`. Below that threshold, sequential (thread-spawn overhead would dominate).
- **Incremental mode.** `bin/serve`'s watcher rebuilds with `incremental: true` — `_site/` isn't wiped; all the mtime/hash checks above pay off. The tradeoff: because nothing is wiped, output for a **deleted or renamed** source file stays on disk, so the dev server keeps serving a page you've removed until you restart or run `bin/build`. Production builds are always full builds, so a deploy never carries a stale page.
- **HTML minification.** Production builds strip whitespace between tags, remove comments, collapse runs of whitespace. `<pre>`, `<textarea>`, `<script>`, and `<style>` content is preserved. Disable with `minify: false` in `site.yml`.
- **CSS/JS minification.** Production builds strip comments and collapse whitespace in stylesheets and scripts before fingerprinting. Conservative on purpose: quoted CSS strings, `calc()` spacing, and descendant selectors survive; JS files using template literals ship untouched. Same `minify:` switch as HTML.

**Runtime (page load):**
- **One render-blocking stylesheet.** The syntax theme, `_common.css`, theme `app.css`, and `site.css` ship as a single fingerprinted bundle (`/assets/css/bundle.<hash>.css`) — one request instead of four, and the Rouge styles get a content hash so a syntax-theme change busts the immutable cache.
- **Image dimensions.** `<img width="..." height="...">` is set whether or not the image pipeline is enabled — pure-Ruby parsers read PNG/JPEG/GIF headers. No CLS regardless of optimisation toggle.
- **Lazy-loaded images.** `loading="lazy" decoding="async"` on every `<img>`.
- **Strict CSP.** No inline scripts/styles → strict CSP works without `'unsafe-inline'`.
- **Long-cache assets.** Fingerprinted assets get `Cache-Control: public, max-age=31536000, immutable` via `_headers`.
- **No JS by default.** The livereload script is injected only in dev.

Configurable knobs:

```yaml
minify: false              # disable HTML/CSS/JS minification (default: on in production)
syntax_highlighting: false # disable Rouge highlighting
images:
  optimise: true           # enable libvips/magick image pipeline
```

### Slow-page detection

Each page render is timed. If a single page's `write` (render +
post-process + file write) takes longer than `SLOW_PAGE_THRESHOLD_MS`
(default 500ms), the build logs a warning in real time with the URL,
elapsed time, and a short list of likely causes:

```
[warn] Slow page: /posts/the-big-one/ took 1.2s — 47 inline images · 12 code blocks · 340 KB output · TOC
```

End-of-build summary, slowest first (top 5), with one "what this
means + what to try" block per unique cause across the slow set
— deduped so each explanation appears once even when several pages
share a cause:

```
Slow pages (>500ms): 3
   1.2s  /posts/the-big-one/  (47 inline images · 12 code blocks · 340 KB output)
   780ms /posts/photo-essay/  (32 inline images)
   620ms /publications/the-field-guide/  (12 code blocks)

What this means and what to try:
  many_images:
    Every `<img>` is matched against the image-pipeline URL registry
    and rewritten to a responsive `<picture>` block. Per-tag cost is
    small; it adds up.
    Try: Reduce images on this page, move large galleries to their
    own page, or set `images.optimise: false` site-wide if the
    pipeline isn't needed.
  many_code_blocks:
    Rouge tokenises every `<pre>` block separately — long examples
    and many small blocks both add measurable time.
    Try: Shorten code examples, link to a gist for the long ones,
    or set `syntax_highlighting: false` site-wide if you don't need it.
  large_output:
    HTML minification and any plugin `:post_process` filters scan
    the whole document — cost scales with output size.
    Try: Trim the body, split into multiple pages, or set
    `minify: false` if the site doesn't need minified output.
```

Goal: turn a generic "your page is slow" into a specific "here's
why, and here's what to try." The heuristics that surface causes
are five sampled signals (inline images, code blocks, output size,
TOC presence, registered `:post_process` plugin filters); they
correlate with the most common slow-path explanations. Each carries
its own one-line "Try:" suggestion in the summary.

Override the threshold per-build, or disable detection entirely:

```bash
ABQARI_SLOW_PAGE_MS=1000 bin/build    # only flag pages slower than 1s
ABQARI_SLOW_PAGE_MS=0    bin/build    # disable slow-page warnings
```

## Upgrading

Two paths, mirroring the [Quickstart](#quickstart):

### Path A — Sites consuming Abqari as a gem

Pull engine updates the standard Bundler way:

```bash
bundle update abqari       # pulls the latest release within your pin
bin/build                  # verify your site still builds
bin/audit                  # verify nothing regressed
```

`abqari new` scaffolds the Gemfile pinned to the current major.minor
(`gem 'abqari', '~> 1.2'` as of this release). Bundler reads that as
`>= 1.2, < 2.0`, so `bundle update abqari` takes minor and patch
releases but never a major one, which is the release that can need
changes to your site. To track a fork or an unreleased branch
instead, swap the line for a git source:

```ruby
gem 'abqari', git: 'https://github.com/grantrayner/abqari.git', tag: 'v1.2.0'
```

The cadence: read [CHANGELOG.md](https://github.com/grantrayner/abqari/blob/main/CHANGELOG.md) before each upgrade,
note any breaking changes (`Removed:` and `Changed:` entries), then
bump the pin and run the build.

**Your customizations are unaffected** because they live in your
site repo (`config/`, `content/`, `data/`, `public/`, and any
overrides under `app/`). Only the gem's internals — layouts,
themes, helpers, `_common.css` — get updated.

**Site-local override drift** is the one thing to watch. If you've
copied an engine file into your site to override it (e.g.
`app/views/layouts/post.html.erb`), the engine's version may have
changed in ways your local copy doesn't reflect. The audit catches
broken links / missing partials; subtler shifts (CSS classes
renamed, frontmatter fields renamed) need a manual diff against the
gem's current copy. Run `bundle show abqari` to find the gem's
installed path, then diff your override against the upstream file.

### Path B — Forked engine

If you forked the engine, you treat your site as a fork of upstream
Abqari and pull updates explicitly via git.

```bash
# One-time setup
git remote rename origin upstream                          # the abqari source
git remote add origin git@github.com:you/your-site.git     # your own repo
git push -u origin main
```

Then for each upgrade, the shipped `bin/upgrade` wraps the common
flows:

```bash
bin/upgrade --check         # show what would change; modify nothing
bin/upgrade --engine-only   # overwrite lib/, bin/, Gemfile from upstream — safest
bin/upgrade                 # full git merge — for users who want everything
bin/upgrade --to v1.0.0     # target a specific tag
```

`--engine-only` is the recommended default for sites that have
customized templates or themes. It overwrites only the files Abqari
maintains (`lib/`, `bin/`, `Gemfile`) and leaves your `app/views/`,
`themes/`, `content/`, `config/`, `data/` untouched. Engine bug
fixes and new features land cleanly; your customizations survive.

After any upgrade:

```bash
bundle install
bundle exec bin/test
bundle exec bin/audit
git commit -am "Update Abqari engine to vX.Y.Z"
```

#### What conflicts where (fork path)

If you skip `--engine-only` and run a full `git merge upstream/main`,
conflicts are likely in the following areas:

| Path | Who edits it | Conflict resolution |
| --- | --- | --- |
| `lib/abqari/*.rb`, `lib/abqari.rb` | Abqari only | Always take upstream (`git checkout --theirs`) |
| `bin/build`, `bin/serve`, etc. | Abqari mostly | Take upstream unless you've made specific changes |
| `app/views/layouts/*` | Both | Resolve manually — usually keep yours, port new features |
| `app/views/partials/*` | Both | Same — keep yours, copy new partials over |
| `themes/*` | Abqari ships, you customize | Keep yours; new themes appear automatically |
| `content/`, `config/`, `data/`, `app/icons/` | You only | Always keep yours (`git checkout --ours`) |
| `Gemfile` | Both | Merge — keep your additions, accept new Abqari deps |
| `.github/workflows/*`, `LICENSE`, `CHANGELOG.md`, `CONTRIBUTING.md` | Abqari, if you took them | Take upstream |

#### When to prefer which path

| You want… | Pick |
| --- | --- |
| Fast, low-friction upgrades; minimal site repo | **Path A — gem** |
| Engine code in your repo so you can edit it freely | **Path B — fork** |
| To deeply customize layouts / themes for a single site | Either works; Path A keeps your overrides in `app/`, Path B lets you edit in place |
| To run on a machine that can't reach the engine git source at install time | **Path B — fork** (everything's local) |

For most sites, **Path A** is the right call. Path B is for the
unusual case where you want full code ownership and accept the
manual-merge upgrade cost.

## Configuration

### Site config

`config/site.yml` has shared keys at the top, with per-environment overrides under `environments:`:

```yaml
title: My Site
description: A site built with Abqari

environments:
  development:
    url: http://localhost:4000

  production:
    url: https://example.com
```

`Site#config` is the merged result of shared keys + the active environment's keys (deep merged). Templates just call `site.config['url']` — they never know which environment they're in.

### Environments

The active environment is `ABQARI_ENV` (default `development`). The bin scripts set sensible defaults:

| Command | Default `ABQARI_ENV` |
| --- | --- |
| `bin/serve` | `development` |
| `bin/build` | `production` |

Override either way: `ABQARI_ENV=production bin/serve` or `ABQARI_ENV=staging bin/build`.

### Locale

Single-locale sites (Spanish, French, Japanese, etc.) work out of the box — markdown body text, front matter, and slugs are language-agnostic. Set the language code in `config/site.yml`:

```yaml
locale: fr
```

This wires up:
- `<html lang="fr">` on every page
- `<language>fr</language>` in the RSS feed and JSON Feed
- `Preferred-Languages: fr` in `/.well-known/security.txt`

Defaults to `en` when unset. UI strings in the shipped templates (`Posts tagged`, `Older →`, `Built with Abqari`, etc.) are deliberately not translated by the engine — they're plain text in `app/views/`, edit them in your language. We don't bake in translations we'd then have to maintain.

Abqari is **not** multilingual: one site, one locale. If you need both English and Spanish on one domain, that's full i18n — out of scope.

### Front matter

Per-page settings on each Markdown file:

```yaml
---
title: About
description: Who I am and what I do
layout: application       # optional, defaults to 'application'
---
```

## Roadmap

### What's in 1.0

Stable, semver-tracked surface area as of `1.0.0`. The
[CHANGELOG](https://github.com/grantrayner/abqari/blob/main/CHANGELOG.md) lists every shipping feature; broadly:
four built-in collections (`posts`, `photos`, `publications`,
`workshops`) plus the `bundles`/`series` meta-collections, ERB
templating with the standard helper library,
the libvips image pipeline, full SEO suite, IndieWeb + POSSE,
content importers, `bin/audit` quality gates, and shipped deploy
templates for Cloudflare Pages, GitHub Pages, and Render.

### Looking ahead (post-1.0)

- **Multi-locale support** — single-locale only today. Multi-locale
  would touch sitemap, JSON-LD, head meta, and the taxonomy layer.
- **Search by collection** — Pagefind currently indexes the entire
  site. Per-collection search scopes would let visitors restrict to
  e.g. cookbook only.
- **First-class comment moderation surface** — webmentions land
  raw today; a moderation queue (block-list + approval gate) would
  let authors curate before render.
- **More publisher backends** — Folio is the only first-class
  integration. The `PublisherShowPage` / `PublisherIndexPage`
  abstraction is generic; another backend (Shopify? Gumroad?)
  could plug in without engine changes.

## Why "Abqari"?

*ʿAbqarī* (عبقري) is Arabic for "genius." The word traces back to
Wādī ʿAbqar — the legendary valley of the jinn where, in classical
Arab lore, poets received their inspiration. A site generator built
for working authors could hardly ask for a better namesake.

The mark is a rub el hizb (۞), the eight-pointed star Arabic
manuscripts use to divide and structure text — which is, at heart,
what this engine does to yours. You'll find it faintly in the corner
of the auto-generated share cards, and as the favicon on
[abqari.dev](https://www.abqari.dev).

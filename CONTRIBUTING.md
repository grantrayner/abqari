# Contributing to Abqari

Thanks for considering a contribution. This document covers the basics; the
README has the bigger picture.

## Quick orientation

- Engine code lives in `lib/abqari/` — around 50 focused files plus a
  few subdirectories (`audit/`, `cli/`, `importers/`, `page/`,
  `render_context/`, `templates/`).
- Tests are in `test/` (Minitest, no extra gems).
- The example site at the project root is also the test fixture.
- Read the README's **How it works**, **Posts and bundles**, and
  **Performance** sections before changing engine internals.

## Setup

```bash
git clone https://github.com/grantrayner/abqari
cd abqari
bundle install
bin/test          # should report 900+ runs, 0 failures
bin/build         # should produce _site/
bin/audit         # should report 0 errors, 0 warnings
```

Running the suite needs the libvips C library (`brew install vips` /
`sudo apt install libvips42`) — the image-pipeline tests require it.

## Making changes

1. **Open an issue first** for anything beyond a typo fix or trivial
   bug. Discussion before code saves everyone time.
2. **Branch from main**, name like `fix/<topic>` or `feat/<topic>`.
3. **Add tests** for new behaviour. The existing tests (`test/site_test.rb`)
   are the model — integration over unit where it makes sense.
4. **Run the full suite** before opening a PR:
   ```bash
   bin/test          # all tests pass
   bin/build         # builds without errors
   bin/audit         # reports no new errors
   ```
5. **Update the README** if your change affects behaviour, config, or
   the project structure — and `docs/` if it lands in a documented
   subsystem (theming, plugins, publications, deploying, security).
6. **Update CHANGELOG.md** — add an entry under `## [Unreleased]` as
   part of the same change, while you still remember why. Lead with the
   user-visible symptom, and say why it hid if it was hiding.
   [docs/releasing.md](docs/releasing.md) has the entry style and the
   full release procedure.

## Style

- Follow existing Ruby style — no Rubocop, but match the surrounding code.
- Keep lib files small and single-purpose. If a file grows past ~200 lines,
  consider whether it should split.
- Comments explain *why*, not *what*. The code is the *what*.
- Add comments at the top of new partials and config blocks explaining
  what they do and how to opt out.

## Design principles to preserve

These are the project's defining choices. Changes that violate them need
an explicit conversation in an issue first:

1. **Minimal dependencies.** Eight small runtime gems plus development
   extras.
2. **Real Ruby in templates.** ERB, not a sandboxed templating language.
3. **Gem-distributed, fork-friendly.** Distributed as a Ruby gem so
   consuming sites stay minimal (content + config). Forking remains
   supported for users who want to own engine code directly.
4. **Privacy by default.** No third-party requests. Self-hosted everything.
5. **Strict CSP.** No `'unsafe-inline'` — pin inline scripts by hash.
6. **Single-mode bundles.** Every post is a directory. No flat-file alternative.
7. **Single-locale only.** No multilingual support. (Set the locale, write
   in any language, but one site, one locale.)

## Releasing (maintainers)

Releases are automated and authenticated with **trusted publishing** —
there is no RubyGems API key in this repository. The workflow exchanges
GitHub's OIDC token for a credential that RubyGems accepts only for this
repo and this workflow file, and that expires in minutes.

### One-time setup on rubygems.org

Done once per gem, in the RubyGems web UI (nothing to configure in this
repo):

1. Sign in to rubygems.org.
2. Go to **[pending trusted publishers](https://rubygems.org/settings/pending_trusted_publishers)**
   if the gem has never been published, or the gem's own **Trusted
   publishers** page if it exists.
3. Create a publisher:

   | Field | Value |
   | --- | --- |
   | RubyGem name | `abqari` *(pending publishers only)* |
   | Owner | `grantrayner` |
   | Repository | `abqari` |
   | Workflow | `release.yml` |
   | Environment | *leave blank* |

   Leave **Environment** blank unless you also add `environment:` to the
   `publish` job. The two must match exactly, and a mismatch shows up as
   an opaque authentication failure partway through a release.

4. Keep MFA enabled on the account. `rubygems_mfa_required` is set in the
   gemspec, and trusted publishing doesn't replace it.

A pending publisher becomes a normal one after the first successful push,
and makes you the gem's owner — so this works for a gem that hasn't been
released yet.

### Cutting a release

**[docs/releasing.md](docs/releasing.md) is the full procedure** — how
to choose the version number, what the changelog owes the reader, and
which files carry the version alongside `version.rb`. Follow it rather
than the summary here; this section covers only what the automation
does once you tag.

```bash
bin/check                     # tests + strict audit + CVE scan
bin/stranger-test             # clean-container install on every supported Ruby
```

Then update `lib/abqari/version.rb`, move the `[Unreleased]` changelog
entries under a dated `## [X.Y.Z]` heading, update the README's
version-bearing lines, relock, commit, and tag:

```bash
git tag vX.Y.Z && git push origin vX.Y.Z
```

The tag triggers `.github/workflows/release.yml`, which runs two jobs:

- **verify** — holds no credential and cannot mint one. Re-runs the full
  suite, checks the tag matches `Abqari::VERSION`, checks the changelog
  has a section for that version, runs the strict audit and a
  bundler-audit CVE scan.
- **publish** — runs only if `verify` passes. The single job with
  `id-token: write`. Builds the gem, pushes it, archives the `.gem` as a
  workflow artifact.

If `verify` fails, nothing is published and the tag can be deleted and
re-cut. Once a version is on rubygems.org it cannot be replaced — only
yanked — so the gates exist to make that irreversible step the last one.

## Reporting security issues

For security-sensitive issues, please **don't** open a public issue.

Use GitHub's private reporting instead:
[**Report a vulnerability**](https://github.com/grantrayner/abqari/security/advisories/new).
It's private to you and the maintainer, and it gives us a place to
coordinate a fix and an advisory before anything is public.

If that's unavailable to you, email the address published at
[`https://www.abqari.dev/.well-known/security.txt`](https://www.abqari.dev/.well-known/security.txt).

Please include the version (`abqari version`), what you did, what
happened, and what you expected. If a proof of concept is short, paste
it inline. We'll acknowledge within a few days.

## Code of conduct

Be respectful, be specific, be kind. Disagreements are fine; personal
attacks aren't. Maintainers reserve the right to remove comments or close
issues that don't meet this bar.

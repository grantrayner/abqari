# Contributing to Abqari

Thanks for considering a contribution. This document covers the basics; the
README has the bigger picture.

## Quick orientation

- Engine code lives in `lib/abqari/`. ~20 small files, each one focused.
- Tests are in `test/` (Minitest, no extra gems).
- The example site at the project root is also the test fixture.
- Read the README's **How it works**, **Posts and bundles**, and
  **Performance** sections before changing engine internals.

## Setup

```bash
git clone https://github.com/your-handle/abqari
cd abqari
bundle install
bin/test          # should report 600+ runs, 0 failures
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
   the project structure.
6. **Update CHANGELOG.md** — add an entry under the current release
   heading (create a new dated version section when cutting a release).

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

1. **Minimal dependencies.** Five runtime gems plus development extras.
2. **Real Ruby in templates.** ERB, not a sandboxed templating language.
3. **Gem-distributed, fork-friendly.** Distributed as a Ruby gem so
   consuming sites stay minimal (content + config). Forking remains
   supported for users who want to own engine code directly.
4. **Privacy by default.** No third-party requests. Self-hosted everything.
5. **Strict CSP.** No `'unsafe-inline'` — pin inline scripts by hash.
6. **Single-mode bundles.** Every post is a directory. No flat-file alternative.
7. **Single-locale only.** No multilingual support. (Set the locale, write
   in any language, but one site, one locale.)

## Reporting security issues

For security-sensitive issues, please **don't** open a public issue.
Email the maintainer directly using the address in
[`/.well-known/security.txt`](https://example.com/.well-known/security.txt)
(once a deployed site exists), or open a private security advisory on GitHub.

## Code of conduct

Be respectful, be specific, be kind. Disagreements are fine; personal
attacks aren't. Maintainers reserve the right to remove comments or close
issues that don't meet this bar.

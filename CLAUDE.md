# Abqari — working notes

Abqari is published on RubyGems. A version number is a promise to
strangers, and a published version can be yanked but never replaced.

## Before touching anything version-shaped

**Read [docs/releasing.md](docs/releasing.md)** before editing
`lib/abqari/version.rb`, `CHANGELOG.md`, or the version-bearing lines
in `README.md`, and before proposing a release. It covers how to choose
the number, the changelog entry style, the four files that move
together, and the pre-tag gates.

Two rules that get broken by accident:

- **`VERSION` moves only at release time, in its own commit.** Never as
  a side effect of a fix.
- **Changelog entries land under `## [Unreleased]` as part of the
  change**, while the reasoning is still fresh — not reconstructed from
  `git log` later. Lead with the user-visible symptom; say why it hid.

## Gates

```bash
bin/check           # tests + strict audit + CVE scan — the PR gate
bin/stranger-test   # clean-container install on 3.3 / 3.4 / 4.0 (needs Docker)
```

`bin/check` is what CI runs. `bin/stranger-test` is release-only, and
catches the packaging bugs that are invisible on a dev machine.

Every fix ships with a test that fails before it and passes after.

## Layout

- `lib/`, `app/`, `themes/`, `vendor/heroicons|d3` ship in the gem.
- `content/`, `config/`, `data/`, `bin/`, `docs/`, `test/` do **not** —
  `test/gemspec_packaging_test.rb` enforces it. `docs/` is for
  maintainers and users reading the repo, not gem consumers.
- `CONTRIBUTING.md` has the design principles that need an explicit
  conversation before they're violated.

## Conventions

- Comments explain *why*, not *what*. Read a neighbouring file before
  writing a new one.
- `<%= %>` auto-escapes (Erubi). `<%==` is raw output and is gated by
  `test/erb_escape_audit_test.rb` — it must match a safe pattern or be
  added to that allow-list deliberately.
- The minifiers recognise comments and their sibling constructs in a
  single ordered pass. Two-pass stripping has silently deleted page
  content twice; see the commentary in `lib/abqari/minifier.rb`.

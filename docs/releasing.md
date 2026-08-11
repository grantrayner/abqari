# Releasing Abqari

Abqari is on RubyGems, so a version number is a promise to strangers.
Once a version is published it can be **yanked but never replaced** —
the irreversible step is last, and everything here exists to make the
steps before it boring.

This is the maintainer procedure. `CONTRIBUTING.md` covers the
mechanics of the trusted-publishing setup and what the release workflow
does; this covers the judgement calls: which number to pick, what the
changelog owes the reader, and what else has to move with it.

`docs/` doesn't ship in the gem (`gemspec_packaging_test.rb` asserts
it), so this file is for us, not for users.

## 1. Pick the number

Abqari follows [semver](https://semver.org/) from 1.1.0 onward. The
public surface is bigger than the Ruby API — a site's build output is
part of the contract too.

| Bump | For |
| --- | --- |
| **Patch** (1.1.0 → 1.1.1) | Bug fix with no surface change. Docs. Internal refactor. A fix that makes output *correct* where it was broken. |
| **Minor** (1.1.0 → 1.2.0) | New config key with a safe default. New helper, layout, partial, theme, CLI flag. Anything additive that an existing site can ignore. |
| **Major** (1.1.0 → 2.0.0) | Removing or renaming a config key, helper, layout, or theme. Changing default output in a way that moves published URLs. Changing a hook signature. Raising `required_ruby_version`. |

The test: **can a site on the previous version upgrade, run `bin/build`,
and get a working site without touching anything?** Yes and it gains
nothing new → patch. Yes and it gains something → minor. No → major.

### Grey areas, decided

- **Removing a public Ruby constant** is technically breaking even when
  nothing outside the engine could sensibly reference it. 1.1.1 removed
  `Minifier::PRESERVE_REGEX` and `COMMENT_REGEX` in a patch release —
  defensible because they were internal to one private method, but it
  got an explicit `### Changed` entry saying so. Call it out rather
  than hoping nobody notices.
- **Changed rendered HTML or CSS** isn't an API change but users see
  it. Patch if it fixes something visibly wrong; minor if it's a
  redesign. If a site's custom CSS could plausibly target what moved,
  say so in the entry.
- **New audit rule, or an existing one escalated to `error`** is a
  minor at least — it can fail a build that passed yesterday.
- **A dependency's floor rising** follows whatever it does to the
  install: if a supported Ruby line can no longer resolve it, that's
  major.

Never bump the number as a side effect of unrelated work. The version
moves in its own commit, at release time, and nowhere else.

## 2. The changelog contract

`CHANGELOG.md` follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

**`## [Unreleased]` always exists at the top**, even when empty
(`_Nothing yet._`). Every user-visible change lands there as it's made
— not reconstructed from `git log` at release time, when the reasoning
has evaporated.

Sections, in this order, omitting empty ones: `Added`, `Changed`,
`Deprecated`, `Removed`, `Fixed`, `Security`.

### How to write an entry

Entries are read by someone deciding whether to upgrade, and later by
someone bisecting a regression. Both want the same thing: symptom
first, mechanism second.

- **Open with the user-visible symptom in bold**, phrased as what
  happened to them, not what the code did. "The contact button did
  nothing when clicked", not "fixed selector mismatch in
  contact-button.js".
- **Say why it hid.** "Production builds only, because dev doesn't
  minify" is the sentence that stops the next person losing an
  afternoon.
- **Then the mechanism and the fix**, in enough detail to judge the
  blast radius.
- Name the config key, helper, or file so the entry is greppable.
- Skip anything with no user-visible effect. Internal test changes earn
  an entry only when they change what a contributor sees, and they go
  under `Changed`, not `Fixed`.

Lead the release with a short prose paragraph when there's a "should I
upgrade?" answer worth stating plainly. 1.1.1 opens by naming who
should upgrade and why; a routine release doesn't need it.

### Cutting the section

At release time:

1. Move the `[Unreleased]` entries under a new `## [X.Y.Z] — YYYY-MM-DD`
   heading. Use a real date and an em dash — the release workflow greps
   `^## \[X.Y.Z\]`, so the bracketed version must be exact.
2. Leave `## [Unreleased]` in place above it, reset to `_Nothing yet._`.
3. Update the compare links at the bottom of the file:

   ```
   [Unreleased]: https://github.com/grantrayner/abqari/compare/vX.Y.Z...HEAD
   [X.Y.Z]: https://github.com/grantrayner/abqari/compare/vPREV...vX.Y.Z
   ```

   The `[Unreleased]` link points at the version you just cut. It's the
   easiest line to forget and it silently 404s.

## 3. What else carries the version

Four files move together. Missing one leaves the repo self-contradictory.

| File | What changes |
| --- | --- |
| `lib/abqari/version.rb` | The `VERSION` constant. Keep this file dependency-free — the gemspec loads it directly. |
| `CHANGELOG.md` | Dated section + compare links, per above. |
| `Gemfile.lock` | Run `bundle install` after bumping `VERSION`. The lock names abqari's own version in two places. |
| `README.md` | The version-bearing lines — see below. |

### README

Find every candidate, then decide each one:

```bash
grep -n "[0-9]\+\.[0-9]\+\.[0-9]\+" README.md
```

**Bump:**

- The `> **Status:** vX.Y.Z` line near the top.
- The `abqari version` sample output in the quickstart.
- Every `gem 'abqari', git: ..., tag: 'vX.Y.Z'` snippet (there are two).

**Leave alone:**

- Historical statements — "filtered out as of 1.1.0" documents *when*
  something changed and stays true forever.
- The `~> 1.1` pin guidance. That's a major.minor pin and only moves on
  a minor release.

Beyond version numbers, the README needs a real edit whenever a change
touches **config keys, CLI behaviour, the site structure, or the
install steps**. It's the primary user documentation — 2,700 lines of
it — so treat "the README is now wrong" as a release blocker, not
follow-up work. `CONTRIBUTING.md` step 5 says the same thing for
ordinary changes; at release time, verify it actually happened.

Also check `docs/` when the change lands in a documented subsystem:
theming, plugins, publications, deploying, security, architecture.

## 4. Pre-tag checklist

Run in order. Each one has caught something real.

```bash
bin/check           # tests + strict audit + CVE scan
bin/stranger-test   # clean-container install on 3.3 / 3.4 / 4.0
```

`bin/stranger-test` needs a Docker daemon (`colima start` if you use
colima). It installs the gem built from your working tree into
`ruby:X-slim` and follows the README quickstart verbatim. Every
packaging bug this project has shipped was invisible locally and
instant there.

Then, before committing:

- [ ] Version picked deliberately against the table in §1.
- [ ] `CHANGELOG.md` section dated; `[Unreleased]` reset; compare links updated.
- [ ] `version.rb`, `Gemfile.lock`, `README.md` all moved.
- [ ] `docs/` checked for the affected subsystem.
- [ ] Working tree clean — `git diff --name-only` empty after staging.

**Verify the gates against the index, not your desk.** The workflow
checks out the tag; it never sees your working tree. If you've staged
selectively, an unstaged fix looks green locally and fails in CI:

```bash
git show :lib/abqari/version.rb | grep VERSION
git show :CHANGELOG.md | grep "^## \[X.Y.Z\]"
```

## 5. Commit, tag, publish

Version bumps get their own commit, separate from the changes they
release, so `git log` reads as work-then-release rather than a single
opaque lump.

```bash
git tag vX.Y.Z && git push origin vX.Y.Z
```

The tag triggers `.github/workflows/release.yml`:

- **verify** — holds no credential. Re-runs the suite, checks the tag
  matches `Abqari::VERSION`, checks the changelog has a section for
  that version, runs the strict audit and a CVE scan.
- **publish** — only if `verify` passes. The one job with
  `id-token: write`.

If `verify` fails nothing is published; delete the tag, fix, re-cut.
Once it's on rubygems.org the only remedy is a yank and a new patch
version — which is why the checklist above is worth the ten minutes.

## 6. After

- Confirm the version is live: `gem info abqari --remote`.
- Bump consuming sites that track a path or git source, and flip any
  Gemfile pin that was waiting on the release.
- If the release fixes something a site was working around, remove the
  workaround rather than leaving it to rot.

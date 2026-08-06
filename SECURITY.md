# Security policy

## Reporting a vulnerability

Please **don't** open a public issue for a security-sensitive problem.

Use GitHub's private vulnerability reporting:
[**Report a vulnerability**](https://github.com/grantrayner/abqari/security/advisories/new).
It stays private between you and the maintainer, and gives us somewhere
to coordinate a fix and an advisory before anything becomes public.

If that isn't available to you, email the address published at
<https://www.abqari.dev/.well-known/security.txt>.

Please include:

- the version (`abqari version`) and Ruby version (`ruby --version`)
- what you did, what happened, and what you expected
- a short proof of concept inline, if you have one

You'll get an acknowledgement within a few days.

## Supported versions

Abqari is developed by one maintainer. Security fixes land on the
latest released minor version; there are no long-term support branches.

| Version | Supported |
| --- | --- |
| 1.1.x | Yes |
| < 1.1 | No — never published to RubyGems |

## Trust model

Abqari is a **build tool that runs on your machine with your
privileges**, not a server. That shapes what counts as a vulnerability.

**Trusted — powerful by design, not a vulnerability:**

- Your own `config/site.yml`, layouts, partials and plugins. Layouts are
  ERB and execute arbitrary Ruby; `plugins/**/*.rb` is loaded and run.
  This is the same trust you extend to a Rakefile.
- `erb: true` in a page's frontmatter, which additionally requires
  `erb_in_markdown: true` at site level — deliberately double-gated,
  and off by default.

**Untrusted — hardened, and a bug if it escapes:**

- Content imported from a third-party export (`bin/import`). Slugs,
  filenames, frontmatter and remote image URLs are all attacker-shaped.
- Webmention payloads. Anyone can send one; author names, avatars and
  URLs come from the sender and are sanitised before rendering.
- Folio API responses and any other build-time HTTP fetch.
- Anything reached over the network: fetches are bounded by size and
  timeout, and importer image fetches additionally refuse to resolve to
  non-public addresses.

**Invariants worth reporting a break in:**

- Nothing is written or deleted outside the output directory.
  `PathSafe.join_under` guards every user-influenced path, and the only
  recursive delete validates its target first.
- A symlink pointing outside the site root is never followed into the
  build output.
- No YAML is loaded outside `safe_load` with a minimal permitted-class
  set (`Date`, `Time`).
- Generated HTML escapes by default; raw output is an explicit,
  audited opt-in.
- `published: false` content is never written to the output directory in
  any form.

If you've found a way around any of those, we'd very much like to hear
about it.

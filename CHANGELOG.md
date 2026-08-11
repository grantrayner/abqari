# Changelog

All notable changes to Abqari will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

_Nothing yet._

## [1.1.1] — 2026-08-11

Bug-fix release, all of it found while building a site against the
published 1.1.0 gem.

Upgrade if you minify (the default in production): a tag name written
inside an HTML comment could silently delete everything between that
comment and the next one, and layouts carry explanatory comments as a
matter of course. Upgrade too if you use the contact button — it never
worked at all.

### Fixed

- **A tag name written inside an HTML comment silently deleted page
  content — production builds only.** `Minifier.minify` stashed
  `<pre>` / `<textarea>` / `<script>` / `<style>` blocks *before* it
  stripped comments, so ordinary explanatory prose in a layout or
  partial — `<!-- see the <script> tag below -->` — opened a
  "preserved" region at the comment's own text. That region ran to the
  next genuine `</script>` further down the document, swallowing the
  comment's `-->` on the way; the orphaned `<!--` then paired with some
  later `-->`, and the comment pass deleted the placeholder along with
  everything between the two. Pages shipped with an empty `<main>`
  against a green build, and only in production, because dev doesn't
  minify.

  Comments and preserved blocks are now matched in one ordered
  left-to-right pass, so whichever construct starts first consumes the
  other and tag-like text inside a comment can't open a region. This is
  the same single-pass discipline (and the same failure class) as the
  CSS minifier's comment/string handling. Conditional comments
  (`<!--[if …]>`) are stashed rather than stripped, so they now survive
  verbatim instead of having their contents whitespace-collapsed.

- **A document beginning or ending with a `<pre>` / `<script>` /
  `<style>` block leaked the minifier's internal placeholder.** The
  final trim used `String#strip`, which removes NUL bytes as well as
  whitespace, truncating the stash sentinel so the placeholder never
  matched on restore and shipped as literal `ABQARI_PRESERVED_0` text.
  Real pages end in `</html>`, which is why this stayed hidden. Both
  the HTML and CSS minifiers now trim whitespace only.

- **The contact button did nothing when clicked.** `contact-button.js`
  delegates on `.contact-button[data-user][data-domain]`, but the
  partial only ever emitted the styling classes (`btn
  btn-outline-secondary`, or whatever `css_class:` was set to) — the
  wrapper's `.contact-button-wrapper` is a different class token, so
  the selector matched nothing on every site that enabled the button.
  No console error; the button just sat there. `.contact-button` is now
  emitted as a styling-free JS hook alongside `css_class:`, so
  overriding the variant can't break the handler.

- **`contact.subject:` rendered a malformed `data-subject` attribute.**
  `_contact_button.html.erb` built the whole attribute as a Ruby string
  and emitted it through `<%= %>`, which auto-escapes under Erubi — so
  the attribute's own quote characters came out as entities
  (`data-subject=&quot;Project enquiry&quot;`) and the subject would
  not have reached `contact-button.js` even once the click handler
  fired. The attribute name and quotes are now literal template text;
  only the value passes through the escape.

### Changed

- `Minifier::PRESERVE_REGEX` and `Minifier::COMMENT_REGEX` are gone,
  replaced by the single `Minifier::HTML_TOKEN_REGEX`. Both were
  internal to `minify` and nothing outside the engine has reason to
  reference them; they're called out because 1.1.0 is on RubyGems and
  removing a public constant is technically breaking. `PRESERVE_TAGS`
  is unchanged.

- `test/low_priority_hardening_test.rb` no longer relies on
  `Object#stub`. Minitest 6 dropped `minitest/mock` from the default
  install, so that test errored on every run of the suite.

## [1.1.0] — 2026-08-06

First public release on RubyGems. 1.0.0 below was tagged in git but
never published, so this is the first version installable with
`gem install abqari`.

Ordered-series navigation and a CSP that can be extended rather than
replaced — both out of building a course-shaped site on top of the
existing series taxonomies — plus a theme-quality pass: dark mode
gets dark code blocks, the decorative cover tiles join the theme's
colour world, and each shipped theme leans harder into its own
identity.

The Fixed and Security sections are longer than a first release usually
warrants because this version went through a full pre-publication
review. Those entries describe defects that existed in the git history
and never reached a published gem — they're recorded because the
reasoning is worth keeping, and because anyone running from a checkout
or the `v1.0.0` tag *was* exposed to them. If you're coming from a
checkout, the bundle-asset change under **Changed** is the one that can
alter what your site publishes.

### Added

- **`bundle_assets.extensions:`** — extra file extensions to publish
  out of a page bundle, on top of the built-in media set:

      bundle_assets:
        extensions: [.gpx, .stl]

  Additive rather than replacing, so adding one download type can't
  silently drop an image format when the defaults grow. Accepts bare
  (`gpx`), dotted (`.gpx`) and upper-case forms. Markdown cannot be
  added — see the bundle-asset change below.

- **`Abqari::UserError`** — the exception class for expected, actionable
  failures: invalid YAML, an unknown config key under strict mode, a bad
  `url:`, a malformed CLI argument. Entry points print these as a plain
  message and exit 1; every other exception keeps its backtrace, because
  an unexpected error is a defect and hiding its trace makes it
  unreportable. Raising `UserError` is a claim that the message alone
  tells the user what to fix.

  Config and frontmatter validation previously raised `ArgumentError` /
  `RuntimeError`; anything rescuing those specifically should rescue
  `Abqari::UserError` instead.

- **`ABQARI_DEBUG=1`** — restore the backtrace for a `UserError`, for
  when a "user error" turns out to be hiding an engine one.

- **`Abqari.run_cli`** — wraps a CLI entry point with that presentation,
  plus clean `Interrupt` handling (Ctrl-C now prints `Interrupted.` and
  exits 130 instead of unwinding a stack trace through the render pool).
  Used by `exe/abqari` and every scaffolded `bin/*`.

- **`Helpers#external_http_url`** — the stricter sibling of
  `sanitized_url`, for URLs arriving from a third party rather than from
  your own content. Accepts only absolute `http(s)` URLs; rejects
  `mailto:` and same-origin paths, which a stranger's "profile URL" has
  no business being.

- `ABQARI_PORT` — dev-server port, alongside the existing `ABQARI_BIND`.
  `bin/serve` takes no arguments by design, so a machine running several
  Abqari sites had no way to move a second one off 4000 without editing
  the script. Parsed strictly: anything that isn't a whole number in
  1–65535 raises with the variable named, rather than going through
  `String#to_i` — `"abc".to_i` is `0`, which WEBrick reads as "bind any
  free port", so a typo would have started a server on a port the
  operator can't guess, and `"4000x".to_i` is `4000`, so a typo would
  have silently worked. Empty or whitespace-only means unset. Resolution
  order is explicit argument → environment → default, matching `bind:`,
  so an exported value can't hijack the test suite.
- **Dark-mode syntax highlighting.** The syntax layer now renders a
  dark Rouge theme under the same two dark-mode scopes every theme's
  token file uses — previously dark pages showed light-mode tokens on
  Rouge's hardcoded near-white background. New `syntax_theme_dark:`
  config key: a Rouge theme name (`github.dark` style names work),
  `false` to opt out, or unset to derive from `syntax_theme`.
- **`--color-price` token** — price text on publication cards/headers.
  Defaults to `--color-primary`; minimal points it at `--color-text`
  so prices stop rendering in the link blue.
- **Per-theme webfont manifests** (`Abqari::ThemeFonts`). `abqari new
  --theme <name>` scaffolds the matching `fonts:` block and
  `abqari theme eject` prints it — magazine and sand previously
  declared faces (Playfair Display, Merriweather) that no scaffold
  ever downloaded, so their typography silently fell back to system
  serifs on every new site.
- **Theme-keyed cover-tile palettes.** The decorative SVG title cards
  draw from a palette tuned to the active theme (magazine, notebook,
  sand) instead of the neutral set, so slug-hashed teal/violet tiles
  stop landing on warm pages. Tile titles also render in the theme's
  `--font-heading` (the SVG's baked-in sans stays as a no-CSS
  fallback).
- **Theme-derived auto OG cards.** With `og_images.auto: true` and no
  explicit `manifest.theme_color`, share cards now use a gradient
  matched to the active theme instead of the one-size slate pair. An
  explicit `theme_color` still wins.

- `Site#prev_in_series` — the backwards counterpart to
  `next_in_series`. Both now delegate to a shared `series_sibling`
  scan, so the two directions can't drift apart.
- `partials/series_pager` — compact bidirectional prev/next series
  nav, for collections readers move through sequentially. The
  forward-only `partials/next_in_series` card is unchanged and still
  what the built-in `post` layout renders; the pager is opt-in from
  your own layout.
- `RenderContext#series_url` and `Site#series_taxonomy_for` — resolve
  the series index URL for a page's own collection instead of
  assuming `posts_series`.
- `media:` config — allows off-origin audio / video in the CSP:

      media:
        host: https://media.example.com   # or a list

  Colocated bundle media needs nothing; it's same-origin and inherits
  `default-src 'self'`. No `media-src` directive is emitted unless a
  host is configured, so existing sites' headers are byte-identical.
- `csp:` config — additive per-directive origin allow-list for
  anything the engine doesn't model:

      csp:
        img-src:     [https://cdn.example.com]
        connect-src: [https://api.example.com]

  Previously the only escape hatch was `headers:`, which replaces the
  computed policy wholesale and takes the pinned theme-bootstrap hash,
  `'wasm-unsafe-eval'` and the Plausible hash down with it. `csp:`
  appends instead. Restricted to eleven extendable directives (the
  hardening directives and `default-src` are excluded); values must be
  `scheme://host`, so keywords, wildcards and non-http schemes are
  rejected by construction. A bad value fails the build rather than
  being silently dropped — a malformed CSP fails open in the browser,
  so a silent skip would ship a policy the operator believes is
  enforced.
- Audit (Content): `series_position` problems that are otherwise
  invisible — a non-Integer position (warn), duplicate positions
  within one series (warn), and a page in a series with no position
  (info). Each of these builds cleanly and renders correctly in
  isolation while dropping out of the prev/next chain.
- `article:published_time` / `article:modified_time` / `article:tag`
  OG meta on posts. `og:type: article` was already emitted, but the
  dates lived only in JSON-LD — Facebook and LinkedIn read the
  OG-level properties, not schema.org.
- The site skeleton now ships `content/404.md` (`permalink:
  /404.html`, `sitemap: false`, `robots: noindex`), so every new site
  starts with a not-found page in both default and `--blank` modes.
- The skeleton's `config/site.yml` gained a commented "SEO + social
  sharing" section (`share_image`, `og_images.auto`, `twitter`,
  `og_locale`) and now discloses the `block_ai_scraping: true`
  default — the knobs existed but new sites had no way to discover
  them from their own config file.
- `deploy` added to `SiteConfig::KNOWN_KEYS` — configuring
  `bin/deploy`'s `deploy:` block no longer warns as an unknown key
  (and no longer errors under `ABQARI_STRICT_CONFIG=true`).

### Changed

- **`reverse_markdown` is no longer a runtime dependency.**
  *(Affects content importing only.)*

  It's needed just by `bin/import` — a one-time migration step most
  sites never run — and it pulls in nokogiri, which pulls in racc. That
  chain broke installation outright on Ruby 3.3, the version this gem
  advertises as its floor: 3.3 bundles racc 1.7.3, Bundler resolves to
  1.8.1, and 1.8.1 ships no precompiled Linux binary, so `bundle
  install` tried to compile it and failed for want of `make` on any
  toolchain-free image (`ruby:3.3-slim` and most deploy bases). Ruby
  3.4 and 4.0 were unaffected, which is why it went unnoticed — their
  default racc already satisfies the constraint.

  `bin/import` now asks for the gem at the moment it's needed and says
  exactly how to install it. Every other command is unaffected: the
  importers were already lazy-loaded and `require 'abqari'` never
  reached them. Runtime dependencies drop from eight to seven, and a
  normal install no longer carries a native-extension gem for a feature
  it doesn't use.

  To import: `gem install reverse_markdown`, or uncomment the line in
  your site's Gemfile.

- **Bundle assets are an allow-list.** *(Behaviour change — read this
  if you're upgrading from a git checkout.)*

  Files colocated with a post's `index.md` used to publish unless they
  were a directory, a dotfile or `index.md` itself. That shipped
  whatever an author left in the folder — including a `notes.md` marked
  `published: false`, which went to production verbatim, frontmatter and
  all, at a guessable URL. `published: false` has to be a promise, and a
  rule that publishes the file anyway makes the flag lie.

  Only known media extensions now publish: images, video, audio,
  subtitles, and PDF/EPUB/ZIP. Anything else is left behind and named at
  build time — a warning, never a silent skip, since silent omission is
  the failure this closes. Extend with `bundle_assets.extensions:`, or
  prefix a file with a dot (`.notes.md`) to keep it local with no
  warning.

  Excluding `.md` alone would have fixed the case and left the class:
  the next `.psd`, `.sketch` or `.docx` would ship the same way. An
  allow-list fails closed on everything nobody thought of, and it's the
  direction that stays cheap to reverse — loosening it later is not a
  breaking change; tightening it would be.

  Note `copy_flat_collection_assets` has always excluded `.md` for flat
  collections. Bundles simply never applied the same rule, and that
  inconsistency is what let it through.

- **Only `index.md` renders inside a bundle directory.** A second `.md`
  in a bundle had no defined role and got two contradictory ones: copied
  raw into the output as an "asset", *and* loaded as a stray page at
  `/posts/my-post/notes/` (`Page#collection` rejects it for not being an
  index, so it fell through uncollected rather than being dropped).
  Published twice, in two forms, neither intended. It's now skipped with
  a warning naming the file.

- **Collections are finalised before the deriving generators run.**
  `Renderer#generate_all` is now two phases: generators that ADD pages
  to a collection (publisher pages) run first, then
  `Site#finalise_collections!`, then generators that READ collections
  (pagination, taxonomies, visualizations, related indexes). Adding a
  collection-joining page after the barrier now raises, naming the page
  — see the pagination fix below for what the silent version cost.

- **CLI errors are presented, not dumped.** A malformed `config/site.yml`
  used to answer with ten frames of Psych internals; the useful part
  (file, line, column) was there, just buried. Same for a typo'd flag,
  an unknown config key under strict mode, and a bad `url:`. These now
  print one line. `ABQARI_DEBUG=1` brings the trace back.

- **`abqari new` validates its argument.** The argument names a
  directory created in the current directory — it isn't a path. Nothing
  checked that, so `abqari new ""` scaffolded into the cwd with an empty
  title, and `..` or an absolute path wrote ~40 files wherever they
  pointed, overwriting same-named `Gemfile` / `README.md` /
  `content/index.md`. Empty, path-like, `.`/`..` and leading-dash names
  are now refused. Extra positional arguments are reported rather than
  silently dropped (an unquoted two-word name used to lose everything
  after the first word).

- **`--force` refuses a target containing `.git`.** It skips the
  non-empty check by design, but it never meant "write into an unrelated
  repository", and a `.git` directory is the clearest signal of exactly
  that.

- **Code-block backgrounds now belong to the theme.** `.highlight`
  backgrounds come from `--color-code-bg` in both modes; Rouge
  supplies token colours only. Sites that relied on the Rouge theme's
  own background should set `--color-code-bg` (or
  `syntax_theme_dark: false`) to taste.
- **Sand redesigned.** Sandier light surface, brick links (the old
  `#444` grey links were nearly indistinguishable from body text),
  olive-charcoal "desert night" dark mode (the old warm black was a
  near-duplicate of magazine's), tag-chip tokens, pill buttons.
- **Notebook** carries its mono voice through the chrome: nav,
  pagination, and buttons render in `--font-mono`, buttons squared
  to 2px corners (matching its tag chips).
- **Magazine** buttons render in the display serif with slight
  tracking, matching its nav and pagination.
- **Fixture heroes quieted.** The hand-authored post/workshop hero
  SVGs no longer bake large titles in a generic sans (the page h1
  already carries the title) and use muted duotones that sit on any
  theme; the fixture config now downloads every shipped theme's
  webfonts so each theme demos at full character.

- Auto OG cards carry a faint rub el hizb (۞) in the top-right
  corner — Abqari's mark, the eight-pointed star Arabic manuscripts
  use to structure text. Rendered at 12% opacity so it reads as
  texture, not branding, on your cards.

- The dev server no longer logs client-disconnect errors. Every open
  tab holds a live-reload SSE stream, and navigating tears that socket
  down without a clean close — WEBrick's own request loop raises
  `Errno::ECONNRESET` from `io_fillbuf` and logs it at ERROR with a
  full backtrace, one per tab per navigation. The SSE handler already
  rescued these, but WEBrick raises before dispatching to application
  code, so the rescue never saw them; filtering at the logger is the
  only interception point.

  `Server::QuietLog` drops `ECONNRESET`, `EPIPE`, `ECONNABORTED` and
  `ENOTCONN` and is otherwise stock `WEBrick::Log`. Suppression is by
  exception class, never by message text, so a genuine fault that
  happens to mention a reset connection is still logged in full — as
  are all other levels, and all String messages. Set
  `ABQARI_VERBOSE_LOG=true` for stock WEBrick logging when the socket
  layer is what you're debugging. Dev-server only; nothing about a
  production deploy changes.

### Fixed

- **`abqari new --name "My Site: A Story"` produced a site that couldn't
  build.** Template values were interpolated into YAML unquoted, so a
  colon in a title — entirely ordinary — made `config/site.yml` and
  every scaffolded frontmatter file unparseable. The scaffolder reported
  success and exited 0; the failure surfaced on the user's first
  `bin/build`, in a file they never wrote. A `#` was quieter and worse:
  it silently truncated the value at the comment marker.

  Values now emit as YAML scalars via Psych, which quotes only when
  needed (so an ordinary scaffold still reads as plain YAML) and knows
  the whole grammar — including the resolver traps where an unquoted
  `yes` loads back as `true` and `1.0` as a Float. Applies to all seven
  affected templates, not just `config/site.yml`.

- **Folio-sourced entries went missing from paginated archives.**
  Pagination ran before publisher pages and freezes its slices at
  generation time, so on a site with more manual publications than
  `per_page`, every Folio-sourced publication was absent from the
  archive and all its shards — no warning, no error, just missing
  entries against a green build. (The archive layout's own comment
  promised the merged list would paginate automatically.)

- **A relative `ABQARI_OUTPUT_DIR` put local filesystem paths in the
  published sitemap.** `Page#url` strips the output root off an absolute
  output path; an unanchored `sub` with a relative root stripped nothing
  and left the developer's full path as the URL —
  `<loc>https://example.com/Users/me/dev/mysite//about/</loc>` — while
  files still landed correctly, so the build reported success. A
  trailing slash was the mirror image, eating the leading `/`.
  `Site#output_dir` now expands (matching what `reset_output` already
  did before deleting — the two had drifted), and the strip is anchored.

- **Generated pages ignored layout edits in incremental builds.**
  Layouts are deliberately outside `GLOBAL_DEP_GLOBS` and tracked
  per-page, but only `Page` consulted them — so editing
  `taxonomy.html.erb`, an archive layout, `publications_index.html.erb`
  or `visualization.html.erb` with the dev server running rebuilt
  nothing and the browser reloaded to stale HTML. All generated page
  classes now check `layout_deps_mtime`, sharing one `layout_name` with
  their own `render` so the two can't drift.

- **Folio series pages never noticed a changed cache.** The cache path
  was built by pluralising `kind`, giving `vendor/folio/seriess.yml` — a
  file that never exists. Series show pages therefore never re-rendered
  when Folio data changed, and fell through to a `Time.now` lastmod that
  restamped every series entry in the sitemap on every build. The
  determinism test couldn't catch it: both builds run on the same day.

- **Scaffolded `bin/*` failed when run from another directory.** The
  scripts pin `ABQARI_SITE_ROOT` to their own location precisely so
  they're cwd-independent, but `require 'bundler/setup'` resolves its
  Gemfile from the current directory, undoing it. Running
  `/path/to/site/bin/build` from a directory holding any other Gemfile
  died with `cannot load such file -- abqari`, naming neither the site
  nor the cause — hitting cron jobs, deploy hooks and editor task
  runners. All seven bundler-using scripts now pin `BUNDLE_GEMFILE`
  first (with `||=`, so an explicit value still wins).

- **`--blank` dropped the `fonts:` block for font-dependent themes.**
  Blank mode emitted no fonts section while the next-steps text still
  told the user to run `bin/fetch-fonts`, which then reported "No fonts
  configured" — leaving magazine and sand on system serifs, exactly the
  silent typography downgrade the fonts machinery exists to prevent.
  System-font themes still get nothing, since there's nothing to
  declare.

- **A non-ASCII project name crashed mid-scaffold under a C locale.**
  Ruby tags ARGV with the locale encoding, so under `LC_ALL=C` (Docker,
  cron, `env -i`) `abqari new café` raised
  `Encoding::CompatibilityError` partway through writing files — and the
  half-written directory then blocked a corrected retry as "non-empty".
  ARGV is now normalised to UTF-8 when the bytes are valid.

- **A typo'd flag printed a backtrace.** `OptionParser#parse` raises on
  an unknown option and nothing caught it, so `abqari new --bloank
  mysite` met a new user with six frames of trace. Caught centrally in
  the dispatcher, so future subcommands inherit it.

- **The strict-config error told you to enable strict config.** The
  unknown-key message ended "…or set `ABQARI_STRICT_CONFIG=true` to make
  this a hard error" in both branches — including the one raised
  *because* it was already set. The advice now differs by mode.

- **A non-Latin tag overwrote the taxonomy index.** A term with no
  URL-safe characters slugifies to "", collapsing `/tags/:slug/` to
  `/tags/` — so the term page was written over `_site/tags/index.html`.
  With two such terms the build did fail, via the output-collision
  check, but named colliding paths rather than the tag responsible.
  Now refused up front, naming the term (and rendered raw rather than
  through `inspect`, which turns a CJK tag into escape sequences the
  author can't match to anything).

- **Photo bundles went stale in incremental builds.** The bundle-asset
  mtime check was gated on `post?`, so changing only a photo's image
  didn't re-render its page — while `lastmod`, which does include bundle
  assets, still advertised the page as updated. Now gated on having a
  bundle, covering photos and any bundle-style collection you define.

- **Bundle image filenames weren't URL-encoded in the sitemap.** A file
  named `my photo.jpg` produced an `<image:loc>` containing a literal
  space, which is invalid — XML escaping is a different layer and
  doesn't help. Filesystem-derived basenames are now percent-encoded;
  frontmatter values are left alone, since they're author-written URLs
  that may already be encoded.

- **Importer frontmatter could be split by a newline in a title.**
  `yaml_scalar` quoted on a documented character list that didn't
  include control characters — and a literal newline ends the line even
  inside a double-quoted scalar, so a title of `"Hello\npermalink: …"`
  from a third-party export became two mapping entries. Control
  characters are now escaped to their YAML forms.

- **`bin/import` with no arguments exited 0.** It printed help and
  reported success, out of step with every other command (`abqari new`
  and `abqari theme` both exit 1 for the same mistake) and a trap for
  any script checking the status. An explicit `--help` is still a
  success.

- **`abqari new` exited 0 when `bundle install` failed.** The scaffold
  is complete at that point, but the site can't build, so a script
  running `abqari new … && cd … && bin/build` had no way to detect it.

- **`bin/serve` validated `ABQARI_PORT` only after building the site.**
  A typo cost a full build before the error appeared. `Server.validate_env!`
  now runs first.

- **The skeleton's `bin/audit` had no `--verbose`.** The engine's copy
  gained it; the scaffolded copy never did — the only real behavioural
  drift across the eight script pairs.

- **The release workflow's tag check loaded the whole engine to read one
  constant.** `ruby -Ilib -r abqari -e 'puts Abqari::VERSION'` ran
  without `bundle exec`, and `bundler-cache` installs to `vendor/bundle`
  where a bare `ruby` can't see it — so the step died on "cannot load
  such file -- erubi" before reaching the constant, failing every
  release at the first gate.

  It now requires `abqari/version`, which has no dependencies. This is
  the same trap that split `lib/abqari/version.rb` out of the engine in
  the first place (its comment explains the gemspec version), one step
  removed — and like that one, it only appears on a clean runner. Two
  tests now pin both halves: workflows may only require
  `abqari/version` to read VERSION, and reading it must work with no
  gems installed at all.

- **`bin/check`'s CVE step broke whenever the active Ruby changed.**
  `bundler-audit` was expected as a global `gem install`, and a global
  install belongs to exactly one Ruby — so switching the development
  Ruby from 3.3 to 4.0 left `bundle exec bundle-audit` reporting
  "command not found", and the check silently sat at ✗. A gate nobody
  can get to pass is a gate nobody reads.

  It's now in the Gemfile's development group (`require: false` — it's a
  CLI), so it's pinned, Dependabot-visible, and present under whichever
  Ruby is active. Both CI workflows dropped their separate
  `gem install bundler-audit` step and call it through the bundle, so
  the version that gates a release is the version a contributor runs.

  (Unchanged for scaffolded sites: `bin/audit`'s optional CVE section
  still shells out to a globally installed `bundle-audit`, as the README
  describes.)

- **`bin/test` buried its own result.** A passing run emitted well over
  a thousand lines: ~400 chilled-string warnings from inside
  `reverse_markdown` (Ruby 3.4+ warns on every literal mutation in a
  file without the magic comment, and the importer tests call it in a
  loop), plus every `Built 1 page(s)`, `Missing \`url\``, webmention
  and syndication line the suite legitimately triggers. Finding a
  failure meant scrolling past all of it.

  Warnings originating inside installed gems are now filtered
  (`VERBOSE_WARNINGS=1` restores them), and the engine's own info/warn
  output is suppressed only when nothing is capturing it — detected by
  checking whether `$stdout`/`$stderr` has been swapped, so all three
  capture idioms in the suite keep seeing byte-identical output.
  `ABQARI_LOG=info bin/test` restores everything. Errors are never
  suppressed. A clean run is now 12 lines.

  Four tests that deliberately trigger logged errors now capture and
  assert on them rather than printing to the terminal — including
  `test_hook_exceptions_are_re_raised_with_logged_backtrace`, which
  never actually checked that a backtrace was logged.

- **The clean-container test skipped the Ruby version the gemspec
  advertises.** Both `bin/stranger-test` and CI's `stranger` job ran
  3.4 and 4.0 while `required_ruby_version` is `>= 3.3`, leaving the
  floor unproven in the environment the test exists to simulate — and
  the floor is where a native gem is likeliest to have no precompiled
  binary and fall back to a source build these images can't perform.
  That gap hid a real installation break (see the `reverse_markdown`
  entry under **Changed**).

  3.3 is now in all three matrices — the test suite, the local
  stranger script, and CI's clean-container job. The three lists are
  duplicated rather than derived and had already drifted, so each now
  carries a comment pointing at the others.

- **A scheme-less `url:` reported the wrong mistake.**
  `URI.parse('example.com')` puts the whole string in `path`, so the
  path check fired and reported that `url` "has a path component
  (\"example.com\")" — technically true, humanly baffling. Missing
  schemes are now detected first and suggest the corrected value.

- **WCAG-AA contrast across all shipped themes.** A token-level
  contrast pass found seven sub-4.5:1 pairs: magazine's light info
  banner, notebook's light muted/warning and dark muted, and sand's
  dark success/danger/info (now dark-text-on-brighter-accent). All
  measured pairs pass in both modes.
- **Magazine's drop cap was dead CSS on every post.** The selector
  targeted `article > p:first-of-type`, but body paragraphs live
  inside the `e-content` wrapper — the only direct `<p>` child of
  `<article>` is the back-link. Now anchored to `.e-content`.

- **The CSS minifier silently deleted every theme token in production
  builds.** `Minifier.css` stashed quoted strings before stripping
  comments, and treated a bare `'` as a string delimiter — but CSS
  comments here are English prose, full of apostrophes ("the theme's
  tokens", "Safari's tap-flash"). Two comments each carrying one
  apostrophe were paired into a single "string" spanning both, so every
  rule between them — plus the `*/` that should have closed the first
  comment — was swallowed and then deleted.

  `_common.css` has an odd number of apostrophes, so in the concatenated
  bundle the casualty was the entire `:root` block of whatever theme
  followed it: every colour and font custom property in the site. Pages
  rendered in Times with no palette. Development builds don't minify, so
  this only appeared once deployed.

  Comments and strings are now tokenised in a single left-to-right pass
  with ordered alternation, so whichever construct starts first consumes
  the other. `content: "/* not a comment */"` still survives verbatim.

- The `post` layout hardcoded `posts_series` in the series breadcrumb
  and the end-of-series note. Since the layout is deliberately
  reusable (`cookbook` ships on it), any other collection's series
  breadcrumb linked into the posts series index. Now resolved from the
  page's own collection, and rendered as plain text when the
  collection has no series taxonomy configured. Posts are unaffected.

- **Auto OG cards: generated pages advertised og:image files that
  don't exist.** With `og_images.auto: true`, the head emitted an
  `<page-url>og.svg` og:image for any page without a hero — but
  `OgImageGenerator` only writes cards for real content pages with
  directory URLs. Tag indexes, pagination shards, related indexes,
  and flat-URL pages (`/404.html` — which produced the mangled
  `/404.htmlog.svg`) all pointed social validators at 404s. The head
  and the generator now share one eligibility predicate
  (`OgImageGenerator.auto_card?`), so they can't drift apart again.

- Slug-aliased posts feeds carried the wrong `<title>`. The head's
  autodiscovery link says "Site — Stories" for a `posts.slug:
  stories` site, but `Feed#feed_title` tested the internal collection
  name instead of the effective slug and emitted just "Site". The
  comment claimed they matched; now they do.

- The skeleton config's commented social-links example used the wrong
  key (`social_links:` — the engine reads `social:`) and bare handles
  where the engine expects full URLs. Uncommenting it produced an
  unknown-key warning and, with the key corrected, broken footer
  links. A scaffold test now validates both templates' keys — real
  AND commented examples — against `KNOWN_KEYS`.

- The skeleton config claimed posts feeds render at `/posts/feed.xml`;
  they render at the root `/feed.xml` (deliberately, for subscriber
  back-compat). The footer signature also baked in the scaffold-time
  year — it now uses the `{year}` build-time token, so it can't go
  stale.

- The dev server showed WEBrick's stock error page for unknown URLs
  instead of the site's own `/404.html` — the one page an author
  could never preview with `bin/serve`. Static hosts (Cloudflare
  Pages, Netlify, GitHub Pages) serve the custom page in production;
  the dev server now mirrors them. The status stays 404, only the
  body changes, and WEBrick's default page still appears if the
  build produced no `404.html`.

- The no-libvips regression test failed on any machine with the
  `vips`/`magick` CLIs installed: the subprocess inherited PATH, so
  the pipeline (correctly) picked the shell backend instead of the
  no-backend state under test. The subprocess now runs with an empty
  PATH.

- `abqari new --engine git` scaffolded a placeholder URL
  (`your-handle`) that failed `bundle install` as-is; it now defaults
  to the canonical repo.

### Security

- **Webmention URLs are sanitised before any template sees them.**
  Webmentions are the least-trusted data the engine renders — anyone on
  the internet can send one, and the author name, avatar and source URL
  are copied from the *sender's* markup into `href` and `src`
  attributes. Erubi's auto-escaping stops a value breaking out of the
  attribute but leaves the URL scheme untouched, so an author URL of
  `javascript:…` escaped to itself and stayed a working link: stored
  XSS on a published site, one reader click away.

  `Indieweb::Fetcher` now scrubs `url`, `wm-source`, `author.url` and
  `author.photo` to absolute `http(s)` URLs (or `nil`) as mentions are
  indexed — so anything reading `site.data['webmentions']` gets clean
  data by construction, rather than every template having to remember.
  Sanitising at index time covers the cached path too, so a
  `vendor/webmentions/mentions.json` written by an older version is
  scrubbed on load. Dropped URLs degrade to unlinked text.

  Only affects sites with `indieweb.enabled` and a webmention.io token.

- **The importer's SSRF guard resolves through the same resolver that
  connects.** `HttpSafe`'s `block_private` check used `Resolv` plus
  `IPAddr` parsing while the request used `getaddrinfo`, and the gap
  between them was a bypass: `http://2130706433/`, `http://0x7f000001/`,
  `http://017700000001/`, `http://127.1/` and `http://127.0.1/` all
  reach 127.0.0.1, but `Resolv` returned nothing and `IPAddr.new`
  raised, so the guard skipped the host and let the request through.
  `0.0.0.0` passed too — it isn't loopback, private or link-local by
  any of `IPAddr`'s predicates, yet connecting to it reaches localhost.

  Resolution now goes through `Addrinfo.getaddrinfo`, closing the whole
  class of parse mismatch rather than enumerating the forms. Added
  coverage for CGNAT (`100.64/10`), multicast, reserved/broadcast, the
  unspecified addresses, and IPv4-mapped IPv6 (`::ffff:127.0.0.1`).
  A host that doesn't resolve still falls through to its natural "no
  such host" error — safe now that the guard and the connection share
  one resolver.

  Reachable only when importing an attacker-supplied export
  (`bin/import`), the one place `block_private` is enabled.

- **Substack zip extraction is verified after unzipping.** Extraction
  shells out to `unzip` (argv-form, so no shell injection), and modern
  Info-ZIP already refuses traversing entries — but an export zip is the
  least-trusted input the engine accepts, and containment was being
  delegated to whichever `unzip` happens to be on PATH. Every extracted
  path is now checked to resolve inside the tempdir, and archives
  containing symlinks are refused outright (an export has no legitimate
  use for one, and refusing avoids reasoning about multi-hop chains).

- **`Site#memo` is mutex-guarded.** Templates call memoised accessors
  from the parallel render pool. Most memos are warm before rendering
  starts and MRI's GVL makes a torn Hash unlikely, but `Renderer`
  already takes this precaution for its own caches. Re-entrant by
  design: the fast path reads without the lock and the block runs
  outside it, so a memo that calls another memo can't deadlock.

- **Deploy workflow templates are SHA-pinned.** The scaffolded
  `.github/workflows/` used floating tags (`actions/checkout@v5`,
  `cloudflare/wrangler-action@v3`) while this changelog claimed they
  were pinned. A repointed tag on a third-party action holding
  `CLOUDFLARE_API_TOKEN` would have been a credential leak replicated
  across every site scaffolded from the template. All actions in the
  templates — and in this repo's own workflows — are now pinned to a
  commit SHA with the version in a trailing comment; the shipped
  `dependabot.yml` keeps them current as reviewable PRs.

- **Releases authenticate with trusted publishing — there is no RubyGems
  API key in this repository.** The `publish` job exchanges GitHub's
  OIDC token for a credential RubyGems accepts only for this repo and
  this workflow file, valid for minutes. Nothing to store as a repo
  secret, nothing to rotate, and a credential that leaked into a log is
  expired before anyone could read it.

  `id-token: write` is granted at JOB level, so the `verify` job — which
  runs the test suite, the audit, and a `curl | bash` installer — cannot
  request a token at all. The setup steps live in CONTRIBUTING.md; the
  gem's `rubygems_mfa_required` still applies, since trusted publishing
  doesn't replace account MFA.

- **The release workflow no longer runs a third-party installer beside
  the RubyGems key.** `release.yml` piped `curl … | bash` from
  pagefind.app in the same job as `GEM_HOST_API_KEY`, so a compromised
  or hijacked host could have read the key and published a malicious
  release. The workflow is now two jobs: `verify` runs the gate and
  holds no secrets, `publish` sees the key and does nothing but
  checkout, build and push. Workflow permissions dropped from
  `contents: write` to `contents: read`, and the `workflow_dispatch`
  tag input is bound through `env` and shape-validated instead of being
  interpolated into a shell line.

## [1.0.0] — 2026-07-14

Tagged in git, never published to RubyGems — see 1.1.0 for the first
installable release. The engine is feature-complete for the
four content types it targets — long-form writing, photo
galleries, publications, and workshops — with the safety
primitives, IndieWeb integration, and POSSE syndication needed to
run a real working author / publisher site.

### What ships

**Authoring**

- Markdown (CommonMark + GFM) with YAML frontmatter.
- Four default content collections — `posts`, `photos`, `publications`,
  `workshops` — plus `bundles` and `series` for Folio-sourced
  publication groupings. Add your own under `collections:` in
  `config/site.yml`.
- Bundle-style collections (`content/<name>/<slug>/index.md` plus
  colocated assets) and flat single-file pages where appropriate.
- Drafts (`published: false`), future-dated scheduling, custom
  taxonomies with scalar (`country: Syria`) or list (`tags: [a, b]`)
  frontmatter.
- Slug aliasing: rename a built-in collection's URL prefix without
  forking the layout (e.g. `posts.slug: guides` publishes posts at
  `/guides/`).
- Content scaffolders: `bin/new`, `bin/new post "Title"`,
  `bin/new page "Title"`.
- Opt-in collections at scaffold time: `abqari new my-site --with
  photos,publications,workshops` enables the named collections in
  config and creates their `content/<name>/index.md` landing pages.
  Default scaffold stays posts-only.
- Content importers: `bin/import substack|ghost|jekyll <source>`
  pulls content from another platform's export into the site's
  collections — downloads images into bundles, writes
  `redirect_from:` for inbound link preservation, idempotent
  re-runs.

**Templating**

- ERB layouts and partials — real Ruby, no sandboxed templating
  language. Erubi auto-escape for `<%= … %>`; explicit raw form
  `<%== … %>` is allow-listed via a build-time audit.
- Standard helper library — `truncate`, `pluralize`, `local_time`,
  `time_ago`, `time_until`, `years_since`, `excerpt`,
  `reading_time`, `slugify`, `asset_path`, `picture_tag`, `icon`,
  `taxonomy_url`, `script_safe_json`, and more.
- Three-layer cascade for nav and footer (data file →
  frontmatter → fallback).
- Light/dark theme toggle with hash-pinned CSP, no FOUC.
- Spam-resistant contact button, image gallery, carousel,
  newsletter, and webmentions partials.

**Styling**

- Mobile-first responsive CSS with `clamp()` fluid type, safe-area
  insets, `100dvh`, `@media (hover: hover)` gates.
- Five hand-tuned themes — `minimal`, `magazine`, `notebook`,
  `sand`, `bootstrap` — plus `custom` as a starter template and
  `none` to bring your own.
- Decorative SVG title-card covers (`cover: svg` or
  `cover: photo_or_svg`) for posts and workshops without an
  `image:` — slug-hashed gradient with the title word-wrapped over
  it, no per-page artwork required.

**Build pipeline**

- Pretty URLs, content-hashed asset fingerprinting, HTML + CSS + JS
  minification.
- Render-blocking CSS (syntax theme, `_common.css`, theme, site
  overrides) ships as a single fingerprinted bundle — one stylesheet
  request per page, immutable-cached.
- Self-hosted Google Fonts via `bin/fetch-fonts`.
- libvips-backed image pipeline: responsive `<picture>`, AVIF +
  WebP variants, CLS-safe dimensions. Falls back to shell-out
  (`vips` / `magick`) or passthrough mode when libvips isn't
  available.
- Parallel page rendering, compiled-template cache, mtime-aware
  copying.
- Build-OK sentinel (`_site/.abqari-build-ok`) written only on
  successful builds; `bin/deploy` refuses to ship without it.
- Atomic state-file writes (POSSE log, webmention cache, sender
  log) — SIGINT mid-write won't corrupt them.

**Discovery and SEO**

- Sitemap with `<lastmod>` and image extension, RSS, JSON Feed
  (one set per collection that opts in).
- Open Graph + Twitter card meta, JSON-LD `Article` and `Book`
  schemas.
- Per-environment `robots.txt`, `_redirects` from `redirect_from:`
  frontmatter, `security.txt`.
- Plausible analytics: one config line, automatic CSP extension.
- Static search via Pagefind, no third-party server.

**IndieWeb and POSSE**

- Microformats2 markup baked into post, post-list, and about
  layouts (`h-entry`, `h-card`, `p-name`, `dt-published`,
  `e-content`, `p-category`, `u-url`, `h-feed`, `p-summary`).
- Webmention receive via webmention.io with ETag caching. A
  "Replies & mentions" section renders below each post —
  conversational mentions get full author + body cards; likes,
  reposts, and bookmarks render facepile-style.
- Webmention send (opt-in): POSTs notifications to external URLs
  recent posts link to. Tracked in `vendor/webmentions/sent.yml`
  with retry-on-failure semantics.
- Bridgy Fed link tags (opt-in): `<link rel="me">` +
  `application/activity+json` advertisement so Mastodon users can
  follow the site directly via ActivityPub.
- POSSE auto-syndication to Mastodon and Bluesky on each build.
  Per-post opt-out via `syndicate: false`; custom snippet via
  `syndication_text:`. Idempotent; replies on the syndicated
  posts flow back as webmentions via Bridgy Fed.

**Security**

- `PathSafe` for every filesystem write derived from user input
  (permalinks, redirects, bundle assets, og:image generation).
- `HttpSafe` for every build-time HTTP — streaming reads with
  size caps, configurable timeouts, no `Net::HTTP.start` outside
  the wrapper.
- ERB rendering uses Erubi with `escape: true` by default.
  `<%== … %>` is allow-listed via `test/erb_escape_audit_test.rb`.
- YAML loading uses `YAML.safe_load_file` with a minimal
  permitted-classes set (`Date`, `Time` only).
- Strict CSP with hashed inline scripts, `object-src 'none'`,
  `frame-ancestors 'none'`, `base-uri 'self'`.
- The dev server binds to `127.0.0.1` by default. WEBrick's stdlib
  default of `0.0.0.0` would expose unrendered drafts and
  future-dated content to anyone on the LAN.

**Quality and shipping**

- `bin/audit`: links + SEO + a11y + privacy + dependency CVEs +
  content quality in one markdown report. `--strict` exits
  non-zero on any error-severity finding.
- `bin/deploy` for Cloudflare and Netlify.
- GitHub Actions workflow templates for Cloudflare Pages, GitHub
  Pages, and Render (all SHA-pinned, Dependabot-managed).
- Test suite: 680+ runs, 8000+ assertions, ~30 second wall-clock.
- Memo registry on `Site` — adding a new cached accessor doesn't
  require touching the rebuild-reset code path.
- Pre-launch hardening pass: security, output-correctness, and DX
  fixes from a full code review, each with regression tests.
- Gem packaging: the site skeleton's dotfiles (`.gitignore`,
  `vendor/*/.gitkeep`) ship in the gem, `abqari new` defaults to the
  released RubyGems engine source, and Heroicons 2.2.0 is vendored
  (with license) so the `heroicon` helper works from a gem install.
- The gemspec reads `VERSION` from a dependency-free
  `lib/abqari/version.rb` rather than loading the engine. Loading it
  pulled in every runtime gem, which broke `bundle install` for any
  git or path source (Bundler evaluates the gemspec before installing
  dependencies).
- `abqari new` writes a `.ruby-version` pinned to the scaffolding
  Ruby, so a scaffolded site doesn't silently build on whatever
  version its deploy host defaults to.
- commonmarker moved to `~> 2.4`. Its precompiled binaries are
  per-Ruby-ABI and 1.1.x stops at Ruby 3.3, so installing under 3.4
  fell back to a source build needing a Rust toolchain. Two rendering
  details are pinned explicitly as a result: `hardbreaks: false`
  (2.x defaults it to true, which turns every hard-wrapped source
  line into a `<br />`), and the TOC partial now reads commonmarker
  2.x's `id`-on-heading anchor markup.
- `word_count` strips HTML before counting. Callers pass rendered
  content, so JSON-LD `wordCount` had been counting tag attributes as
  words.
- `slugify` folds diacritics instead of deleting them: "Café" now
  slugs to `cafe` rather than `caf`, and "Mabrūk" to `mabruk` rather
  than `mabr-k`. It builds public taxonomy URLs (`/tags/:slug/`), so a
  transliterated or accented tag previously got a mangled URL.
  Stroked and ligature letters Unicode doesn't decompose (ø, ß, æ, þ,
  …) fold via an explicit table. Non-Latin scripts still slug to "",
  which `Page::Path` reports as an actionable error. Path-derived
  strings tagged ASCII-8BIT and outright invalid byte sequences are
  now handled rather than raising mid-build.

  Upgrade note: this changes URLs only for taxonomy terms or slugs
  that actually contain such characters. Pure-ASCII sites are
  byte-identical. If you have an affected tag, add `redirect_from:`
  for the old path.
- Theme handling hardened and opened up:
  - `theme:` is validated at the start of every build — a typo aborts
    with one clear message listing the available themes (previously N
    opaque per-page failures), and traversal-shaped names
    (`theme: ../x`) are rejected outright.
  - `abqari theme eject <name> [--as newname]` copies an engine
    theme's stylesheet into the site's `themes/`, where it shadows the
    gem's copy. `abqari new --theme custom` now copies the starter in
    automatically, and `--theme none` scaffolds an editable
    `app/assets/css/app.css` (a `--theme none` site previously failed
    its first build).
  - Site-local `themes/<name>/public/` now MERGES with the engine
    theme's public tree per-file instead of replacing it wholesale.
  - `theme: bootstrap` no longer fingerprints dead copies of the
    vendored dist (~700 KB) into `_site/assets/`.
  - The `minimal` default moved to `SiteConfig::DEFAULTS`, fixing
    stale CSS hot-reload on sites with no `theme:` key; the skeleton
    ships `themes/.gitkeep` so the watcher covers theme work from
    first serve.
  - New `docs/theming.md`: the theming guide and full token reference,
    drift-tested against `_common.css`.
- Ruby 4.0 supported and now the development Ruby (`.ruby-version`
  4.0.2); CI tests 3.3 / 3.4 / 4.0. The gemspec floor stays `>= 3.3`.
  Full suite green on 4.0 with the same locked dependencies —
  commonmarker ≥ 2.4 ships precompiled 4.0 binaries, which is what
  the `~> 2.4` floor bought.

[Unreleased]: https://github.com/grantrayner/abqari/compare/v1.1.1...HEAD
[1.1.1]: https://github.com/grantrayner/abqari/compare/v1.1.0...v1.1.1
[1.1.0]: https://github.com/grantrayner/abqari/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/grantrayner/abqari/releases/tag/v1.0.0

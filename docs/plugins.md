# Abqari plugin contract

Plugins are Ruby files in `<site_root>/plugins/`. They're auto-loaded
once when `Abqari::Site.new` runs, and register callbacks against
named lifecycle events. The engine calls those callbacks at known
points during a build.

This page is the canonical reference: hook semantics, the full
event list, and the writing-a-plugin walkthrough.

---

## 1. Quickstart

Create `plugins/word_counter.rb` in your site repo:

```ruby
# Add a footer line with the word count to every post.

Abqari::Hooks.register(:post_process) do |html, _site, page|
  next html unless page.respond_to?(:post?) && page.post?

  words = html.gsub(/<[^>]+>/, '').split(/\s+/).size
  footer = %(<footer class="word-count">~#{words} words</footer>)
  html.sub('</article>', "#{footer}</article>")
end
```

Drop it in, run `bin/build`, the footer appears at the bottom of every
post. No `Gemfile` edits, no config, no `require` — auto-loaded.

---

## 2. The hook API

### `Abqari::Hooks.register(event, &block)`

Register a callback for `event`. The block is appended to the event's
callback list; multiple plugins can register for the same event and
all fire in registration order.

### `Abqari::Hooks.run(event, *args)` — event style

The engine calls this internally. Every registered callback fires for
side effects (logging, mutating state on the passed-in objects, etc.).
Return values are ignored.

### `Abqari::Hooks.run_filter(event, value, *args)` — filter style

The engine calls this internally. The `value` is threaded through every
registered callback — each receives `(value, *args)` and returns a
(possibly modified) value. The final value flows back to the engine.

### Failure semantics

A plugin that raises crashes the build. The exception is logged at
`error` with the first five backtrace lines, then re-raised. This is
deliberate — a plugin silently producing wrong output is worse than a
build that fails loudly.

If you need defensive plugin behaviour (skip on unexpected input
rather than crash), wrap your callback body in your own `rescue`.

---

## 3. Lifecycle events

### `:before_build` → `(site)`

Fires at the start of every `Site#build` call (before the output
directory is wiped, before `apply_timezone!`, before pages load).
The site's `config` is fully populated and validated. Pages and
generated_pages are both empty.

Use for: warming external caches, validating site-wide invariants
before any work begins, registering custom audit rules dynamically.

### `:after_load_pages` → `(site)`

Fires after `SiteLoader#load_pages` returns. `site.pages` is the
finalised page list (drafts filtered, futures filtered,
disabled-collection paths skipped). `site.generated_pages` is still
empty.

Use for: validating frontmatter across pages, building cross-page
indexes that downstream hooks consume, generating virtual pages that
mimic existing collections.

### `:after_generate` → `(site)`

Fires after the renderer's generator pass (`generate_all` — tag
pages, paginated shards, visualizations, publisher pages,
related-index pages). `site.all_pages` is the complete list of
everything the build will render.

Use for: appending custom generated pages, post-processing the
generated set, computing build-time stats.

### `:after_build` → `(site)`

Fires in the `ensure` block of `Site#build` — runs even when the
build raises. Use the truthiness of `site.all_pages` to distinguish
success-after-build from failure-during-load.

Use for: ping-back webhooks, deploy notifications, cleanup of
temp files.

### `:post_process` (filter) → `(html, site, page) -> html`

Fires once per rendered page, AFTER the engine's built-in
post-processing (bundle URL rewrite, syntax highlighting, image
pipeline) and BEFORE livereload injection + minification. The
callback receives the HTML string and returns the (possibly
modified) HTML.

Use for: injecting custom analytics scripts, rewriting links to
external services, adding read-time / word-count badges, removing
content that shouldn't ship to production.

---

## 4. Patterns

### Conditional execution by page type

```ruby
Abqari::Hooks.register(:post_process) do |html, _site, page|
  next html unless page.respond_to?(:post?) && page.post?
  # ... transformations for posts only
end
```

`page` is nil for some artifact outputs (sitemaps, feeds, etc.).
Always check before calling page methods.

### Reading site config

```ruby
Abqari::Hooks.register(:before_build) do |site|
  api_key = site.config.dig('my_plugin', 'api_key')
  raise 'my_plugin: missing api_key' unless api_key
end
```

Configure plugins under their own top-level key in `config/site.yml`.
The `KNOWN_KEYS` allow-list in `SiteConfig` accepts any `x_*`-prefixed
key as a user extension — name your config block `x_my_plugin:` to
skip the "unknown config key" warning under
`ABQARI_STRICT_CONFIG=true`.

### Custom audit rules

Audit rules already live under `lib/abqari/audit/`. From a plugin,
you can register a custom rule class and have it run alongside the
built-ins:

```ruby
class MyRule < Abqari::Audit::Rule
  def run
    # ...
    add(category: 'content', severity: 'warn',
        location: '/some/url/', message: 'Found something')
  end
end

Abqari::Hooks.register(:before_build) do |_site|
  # `Abqari::Audit::RULES` is frozen — we'd need a register API for
  # this in the engine. Until then, use :post_process for inline
  # site-wide checks.
end
```

(A first-class audit-rule registration API is on the roadmap.)

### Custom helpers in templates

Plugins can extend `Abqari::RenderContext` directly, since templates
execute against an instance of it:

```ruby
module ReadingTimePlus
  def detailed_reading_time(text, wpm: 200, ceiling: true)
    words = text.to_s.gsub(/<[^>]+>/, '').split(/\s+/).size
    minutes = words.to_f / wpm
    minutes = minutes.ceil if ceiling
    "#{minutes} min read (#{words} words)"
  end
end

Abqari::RenderContext.include(ReadingTimePlus)
```

ERB templates can then call `<%= detailed_reading_time(page.body) %>`.

---

## 5. Auto-load semantics

- `plugins/**/*.rb` are loaded in lexicographic order at
  `Site.new` time. Use numeric prefixes (`01_foo.rb`, `02_bar.rb`)
  if registration order matters.
- `Kernel#load` is used (not `require`) — top-level code re-runs
  on every `Site.new`. In the dev server, that means editing a
  plugin file requires restarting `bin/serve` to re-register hooks
  cleanly; without the restart, both the old AND the new callbacks
  fire on each rebuild.
- Plugins ARE loaded for the test suite (the engine itself doesn't
  ship any, but the test fixture pattern works).
- Plugin load errors (syntax, NameError at the top level) re-raise
  with the offending file path logged.

---

## 6. What's intentionally out of scope

- **A `Plugin` base class.** Plugins are just files that call
  `Hooks.register`. No subclassing, no naming convention, no
  metadata block. Same model as Jekyll's `_plugins/` but simpler.
- **Inter-plugin dependencies.** If plugin B needs plugin A's
  callback to have run first, prefix the filenames (`10_a.rb`,
  `20_b.rb`). The engine doesn't model dependencies because we'd
  rather not invent a package manager.
- **Sandboxing.** Plugins run with full Ruby access — same trust
  level as `app/views/*.erb` (see [security.md §1](security.md)).
  The "trusted content" assumption applies to plugins too.

---

## 7. Stability

The hook list (§3) is the public surface. Adding new events is
additive and safe. Renaming or removing an event is a breaking
change and would land in a major version bump with a deprecation
warning in the prior minor.

The hook API itself (`register`, `run`, `run_filter`, `clear!`,
`count`, `registered_events`) is stable for the 0.x line.

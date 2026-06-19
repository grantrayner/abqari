---
title: Accessibility — what ships, what the audit catches
published: true
description: WCAG-aware baseline out of the box, plus the audit checks that catch regressions in your own content.
tags: [accessibility, a11y, audit]
cover: svg
---

Abqari ships with a WCAG-aware baseline. A site cloned from this
repo, with no a11y work from you, is keyboard-navigable and
screen-reader-friendly. This page is a tour of what's wired in,
why each piece matters, and how to extend or remove parts.

## Why this is built in, not optional

Most static-site generators leave accessibility to the theme — and
themes vary wildly. The result is that "static site" sometimes
means "WCAG-compliant" and sometimes means "div soup with no
landmarks." That's a bad default for non-technical authors who
don't know they're shipping inaccessible sites.

Abqari treats baseline a11y the same way it treats CSP, sitemaps,
and image optimisation: things you should get for free, that you
can opt out of if you have a reason, but that you don't have to
know about to do the right thing.

## What ships

### Skip-to-content link

The first focusable element on every page is a "Skip to content"
link, visually hidden until it receives focus.

```html
<a class="skip-link" href="#main-content">Skip to content</a>
```

It targets `<main id="main-content" tabindex="-1">` on every
layout. Keyboard users tab once, hit Enter, and they're at the
article. Without it, they tab through the entire site nav (and
theme toggle) on every page they visit.

Defined in `app/views/partials/_skip_link.html.erb`. Styled in
each theme's `css/app.css` using the standard transform-based
reveal pattern.

### `<main>` landmark

Every layout wraps the page content in
`<main id="main-content" tabindex="-1">`.

- The `id` is the skip link target.
- The `tabindex="-1"` makes it focusable programmatically — so
  when the skip link's anchor jump fires, focus actually moves
  there. Without `tabindex`, browsers visit the anchor visually
  but leave focus on the link, which breaks subsequent tab
  navigation.
- The `<main>` element itself gives screen readers a "jump to
  main" entry point, separate from the skip link.

### `aria-label` on every nav

Three navs commonly appear on an Abqari page: site nav,
pagination, and (sometimes) a footer or TOC. All of them are
`<nav>` elements. Without `aria-label`, screen readers announce
them all as just "navigation," and a user with three "navigation"
landmarks can't tell which is which.

```erb
<nav aria-label="Primary"> ... </nav>      <!-- _nav.html.erb -->
<nav aria-label="Pagination"> ... </nav>   <!-- _pagination.html.erb -->
```

If you add another nav (a TOC, a category browser), give it a
distinct label.

### Theme toggle with `aria-pressed`

The light/dark toggle is a `<button>` with
`aria-label="Toggle light/dark theme"` and `aria-pressed="true"`
or `"false"` matching the active theme. Screen readers announce
both — users hear *what the button does* and *what state it's in*
on every visit.

The server-rendered HTML defaults `aria-pressed="false"`
(light theme). `theme-toggle.js` re-syncs it on load by reading
the resolved theme (data attribute or system preference), so even
when the user has dark mode on system-wide, the button reflects
the truth.

### Visible focus ring

Themes define a `:focus-visible` rule:

```css
:focus-visible {
  outline: 2px solid var(--color-link);
  outline-offset: 2px;
}
```

The modern `:focus-visible` only matches when focus came from a
keyboard (Tab, arrow keys), not a mouse click. Mouse users don't
see outlines on buttons they click; keyboard users always see
clearly where they are.

The `bootstrap` theme inherits Bootstrap's own focus styles (which
already meet WCAG).

### Reduced motion

Each theme honours the user's OS-level reduce-motion preference:

```css
@media (prefers-reduced-motion: reduce) {
  *, *::before, *::after {
    animation-duration: 0.01ms !important;
    animation-iteration-count: 1 !important;
    transition-duration: 0.01ms !important;
  }
}
```

None of the shipped themes have meaningful animations, so this is
preemptive — but it catches anything you add later, plus anything
third-party themes ship.

### Icons

Every SVG in `app/icons/` has `aria-hidden="true"`. Screen readers
skip them. The surrounding `<a>` or `<button>` provides the
accessible label via `aria-label` or visible text.

### `<html lang>`

Every layout has `<html lang="<%= site.config['locale'] || 'en' %>">`.
Required for correct screen-reader pronunciation. Configure via
`locale:` in `config/site.yml` (single-locale only — Abqari isn't
a multilingual generator).

### Image alt text — enforced by audit

`bin/audit` reports a finding for every `<img>` without an `alt`
attribute. The shipped helpers (`picture_tag`, `icon`, `heroicon`)
take `alt:` as a required argument, so handwritten markdown is
the only place a missing alt slips in. Use `alt=""` for purely
decorative images and a real description for content images.

### Heading hierarchy — audited

`bin/audit` warns on any page with multiple `<h1>` elements.
Pages should have exactly one `<h1>` (the page title); subheadings
are `<h2>` and below. The audit catches regressions when content
authors paste in markdown with rogue `# ` lines.

## What the audit catches

`bin/audit` produces a markdown report covering links, SEO,
accessibility, privacy, content quality, and dependency CVEs.
The accessibility section runs these checks per page:

| Check | Severity | Triggered when |
| --- | --- | --- |
| Image without alt | **error** | `<img>` lacks an `alt` attribute |
| Multiple h1s | warn | More than one `<h1>` on a page |
| Missing skip link | warn | No `class="skip-link"` or `href="#main-content"` |
| Missing `<main>` landmark | warn | No `<main id="main-content">` |
| Unlabelled `<nav>` | warn | A page has 2+ `<nav>` and at least one lacks `aria-label` |

Redirect stubs (pages with only a `<meta http-equiv="refresh">`)
are skipped — they have no user-facing content.

Run it:

```bash
bin/audit
```

Output lands in `audit/<timestamp>.md`. `bin/audit --strict`
exits non-zero on any error-severity finding — wire it into CI:

```yaml
# .github/workflows/ci.yml
- run: bundle exec bin/audit --strict
```

## What the audit doesn't catch

Static-analysis a11y has limits. The audit can't detect:

1. **Color contrast** — automated tools can compute ratios, but
   real-world contrast depends on rendered colors, opacity, blend
   modes, and image backgrounds. The shipped themes meet WCAG AA
   in both light and dark; verify yours when you customise.
2. **Keyboard traps** — testing requires actually tabbing through
   the page.
3. **Screen-reader UX quality** — whether labels make sense to a
   non-sighted user is a human judgment call.
4. **Form labels** — there are no built-in forms shipped, so this
   isn't a default concern. If you add a contact form, every
   input needs a `<label for="...">` (or `aria-label`).
5. **Live region announcements** — if you add dynamic content
   (toasts, async load states), use `aria-live` and the audit
   can't tell whether you did it correctly.

For #1 and #3, run the page through Lighthouse, axe DevTools, or
(ideally) test with a real screen reader (VoiceOver on macOS,
NVDA on Windows).

## Removing or customising

Every piece of the baseline is yours to edit after cloning.

| To do this... | Edit |
| --- | --- |
| Change the skip link text | `app/views/partials/_skip_link.html.erb` |
| Remove the skip link | Delete the partial + remove `<%== render 'partials/skip_link' %>` from each layout |
| Change focus-ring color | `:focus-visible { outline-color: ... }` in your theme's `app.css` |
| Add another nav (TOC, breadcrumbs) | Use `<nav aria-label="Distinct label">` |

The audit is opinionated by design. If a check fires on something
you've decided is fine, the right move is usually to add a comment
explaining why and to silence it locally rather than weakening
the audit globally.

## See also

- [Audit](/guides/the-audit/) — the full reference for `bin/audit`
- [Templating with ERB](/guides/templating/) — helpers that enforce alt text

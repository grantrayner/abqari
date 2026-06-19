---
title: "Themes: picking a visual language"
published: true
description: A tour of the themes Abqari ships, the FOUC-free light/dark toggle, and how to build your own.
date: 2026-01-15
tags: [themes, design, getting-started]
image: hero.svg
series: Inside Abqari
series_position: 1
---

Every Abqari site picks one theme. A theme is a directory under
`themes/<name>/` containing one or more CSS files; the engine
ships several, plus a `bootstrap` variant and a `none`
escape-hatch.

## What ships in the box

| Theme | Description |
| --- | --- |
| `minimal` | System fonts, clean prose, light/dark via `prefers-color-scheme`. The default if you don't touch `config/site.yml`. |
| `magazine` | Serif headings, drop caps, warm cream palette. Best for long-form blogs where each post is the centre of attention. |
| `notebook` | Monospace accents, dense typography, docs-style. Pairs well with technical writing and code samples. |
| `sand` | Warm earth-toned palette for prose-led sites; Merriweather typography, brand-red accents, hand-rolled CSS, no framework. |
| `bootstrap` | Bootstrap 5.3.8 vendored (~232 KB) — full utility framework when you want to customise layout with bs-utilities rather than writing your own CSS. |
| `custom` | A starter that's a near-copy of `minimal` with prominent customisation guidance throughout the CSS file. Recommended when you want a distinctive look without forking a built-in. |
| `none` | No theme CSS at all; bring your own in `app/assets/`. |

## Switching themes

One line in `config/site.yml`:

```yaml
theme: notebook
```

Restart `bin/serve` and the new theme paints immediately. No
fingerprint collisions to worry about — themes are CSS-only.

## Mixing your own CSS

Every theme can be supplemented. Drop `app/assets/css/site.css`
in your site root; the engine auto-includes it after the theme.
Use it for the narrow set of overrides specific to your site —
typography choices, colour tweaks, layout polish. Keep the theme
intact so you stay close to upstream as the engine evolves.

For broader customisation, override individual theme files by
dropping a same-named file in your site's `themes/<name>/`
directory. The engine's site-first / engine-fallback path
resolution prefers your copy, file by file.

## Light/dark toggle

Each theme has a built-in dark mode that responds to
`prefers-color-scheme` *and* a manual user toggle. The toggle is
opt-in via a partial:

```erb
<%== render 'partials/theme_toggle' %>
```

The default nav already renders it — remove that line from
`_nav.html.erb` if you don't want it.

### How the toggle works

1. **A tiny inline `<script>` in `<head>`** reads
   `localStorage['theme']` and sets `<html data-theme="dark">`
   (or `light`) **before** the page renders. No flash of the
   wrong theme.
2. **The strict CSP is preserved** by pinning the inline script's
   SHA256 hash in `_headers`. No `'unsafe-inline'` needed.
3. **Each theme's CSS** responds to `[data-theme="dark"]` /
   `[data-theme="light"]` overrides; without an attribute,
   `prefers-color-scheme` still wins.
4. **Clicking the button** flips `data-theme` and persists in
   `localStorage` via `app/assets/js/theme-toggle.js`. The button
   shows a moon when light is active (click → switch to dark) and
   a sun when dark is active.

Customise the icons in `app/icons/sun.svg` and `app/icons/moon.svg`;
restyle the button via `.theme-toggle` in your theme CSS.

## Building your own theme

Each theme is a single directory: `themes/<name>/`. Inside, mirror
the `app/assets/` structure:

```
themes/my-theme/
└── css/
    └── app.css
```

The asset pipeline picks it up when `theme: my-theme` is set in
`config/site.yml`. CSS variables drive most of the styling — if
you fork an existing theme, you can usually swap in a new colour
palette without touching layout rules.

For a more guided start, set `theme: custom` and edit
`themes/custom/css/app.css` — it's a near-copy of `minimal` with
inline comments throughout explaining what each block does and
how to retune it. See also
[Build your own theme](/cookbook/custom-theme/) for the recipe-style
walkthrough.

## See also

- [Build your own theme](/cookbook/custom-theme/) — start from `custom`, swap palette
- [Theme primitives — tokens, containers, breakpoints](/cookbook/theme-primitives/)
- [Use Bootstrap from a CDN](/cookbook/bootstrap-cdn/)
- [Add icons (Font Awesome / Bootstrap Icons)](/cookbook/icons/)

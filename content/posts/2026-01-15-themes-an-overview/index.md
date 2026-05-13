---
title: "Themes: picking a visual language"
description: A short tour of the five themes Abqari ships with — minimal, magazine, notebook, sand, and bootstrap — and how to switch between them.
date: 2026-01-15
tags: [themes, design, getting-started]
image: hero.svg
series: Inside Abqari
series_position: 1
---

Every Abqari site picks one theme. A theme is a small CSS file in
`themes/<name>/css/app.css` — Abqari ships five plus a `bootstrap`
variant and a `none` escape-hatch.

## What ships in the box

- **minimal** — system fonts, clean prose, light/dark via
  `prefers-color-scheme`. The default if you don't touch `config/site.yml`.
- **magazine** — serif headings, drop caps, warm cream palette. Best
  for long-form blogs where each post is the centre of attention.
- **notebook** — monospace accents, dense typography, docs-style.
  Pairs well with technical writing and code samples.
- **sand** — warm earth-toned palette for prose-led sites; Merriweather
  typography, brand-red accents, hand-rolled CSS, no framework.
- **bootstrap** — Bootstrap 5.3 vendored (~232 KB), full utility
  framework. Use when you want to customise the layout with bs-utilities
  rather than writing your own CSS.
- **custom** — a starter that's a near-copy of `minimal` with prominent
  customisation guidance throughout the CSS file. Recommended when you
  want a distinctive look without forking a built-in theme.
- **none** — no theme CSS at all; bring your own in `app/assets/`.

## Switching themes

One line in `config/site.yml`:

```yaml
theme: notebook
```

Restart `bin/serve` and the new theme paints immediately. No fingerprint
collisions to worry about — themes are CSS-only.

## Mixing your own CSS

Every theme can be supplemented. Drop `app/assets/css/site.css` in your
site root; the engine auto-includes it after the theme. Use it for the
narrow set of overrides specific to your site — typography choices,
colour tweaks, layout polish. Keep the theme intact so you stay close
to upstream as the engine evolves.

---
title: Add icons (Font Awesome / Bootstrap Icons / Heroicons)
description: Three icon options with first-class support — vendored or kit-based, all opt-in via config.
---

# Add icons

Three options ship with first-class support, plus a documented pattern for any other library:

| Option | Distribution | Opt-in | CSP |
| --- | --- | --- | --- |
| Font Awesome Free (vendored) | webfont in `public/fontawesome/` | `icons.fontawesome: true` | strict |
| Font Awesome Pro (kit) | CDN script | `icons.fontawesome_kit: <id>` | needs `'unsafe-inline'` styles |
| Bootstrap Icons (vendored) | webfont in `public/bootstrap-icons/` | `icons.bootstrap_icons: true` | strict |
| Heroicons (inline SVG) | files in `vendor/heroicons/` | `<%= heroicon('book') %>` | strict, no link tag |

Multiple can be active at once. They don't conflict.

## Font Awesome Free (vendored)

[Font Awesome 6 Free](https://fontawesome.com/) — solid, regular, brands. ~470 KB total.

1. Download "Free for Web" from [fontawesome.com/download](https://fontawesome.com/download).
2. Drop into `public/fontawesome/`:
   ```
   public/fontawesome/
   ├── css/all.min.css     (and the per-style files)
   ├── webfonts/fa-*.woff2
   └── LICENSE.txt
   ```
3. Enable:
   ```yaml
   icons:
     fontawesome: true
   ```
4. Use in templates: `<i class="fa-solid fa-book"></i>`, `<i class="fa-brands fa-github"></i>`.

CSP stays strict — everything is self-hosted.

## Font Awesome Pro (kit)

If you have a Pro subscription, the simpler path is to use a Kit. Get a kit ID from your Font Awesome account; configure:

```yaml
icons:
  fontawesome_kit: f50004c95a       # your kit id (no .js suffix)
```

The head partial emits:

```html
<script src="https://kit.fontawesome.com/f50004c95a.js" crossorigin="anonymous"></script>
```

When this is set, the vendored `fontawesome` setting is ignored — you don't need `public/fontawesome/` files.

**CSP cost** — the kit injects styles into the page dynamically and pulls woff2s from `ka-f.fontawesome.com`. Abqari auto-extends the CSP:

- `script-src` += `https://kit.fontawesome.com`
- `style-src` += `'unsafe-inline'`  ← weakens the strict default
- `font-src` += `https://ka-f.fontawesome.com`
- `connect-src` += `https://ka-f.fontawesome.com`

If keeping a strict CSP matters more than Pro icons, stick with the vendored Free path.

## Bootstrap Icons (vendored)

[Bootstrap Icons](https://icons.getbootstrap.com/) — ~2,000 icons in outline + filled variants. ~400 KB.

1. Download from [github.com/twbs/icons/releases](https://github.com/twbs/icons/releases).
2. Drop into `public/bootstrap-icons/font/`:
   ```
   public/bootstrap-icons/
   └── font/
       ├── bootstrap-icons.min.css
       └── fonts/bootstrap-icons.woff2
   ```
3. Enable:
   ```yaml
   icons:
     bootstrap_icons: true
   ```
4. Use: `<i class="bi bi-book"></i>`. Browse the [catalog](https://icons.getbootstrap.com/).

CSP stays strict — self-hosted.

## Heroicons (inline SVG)

[Heroicons](https://heroicons.com/) — ~300 icons × 4 variants (24×24 outline, 24×24 solid, 20×20 mini, 16×16 micro). MIT licensed. From the Tailwind team.

Heroicons distributes as raw SVG files, not a webfont. The Abqari helper inlines the SVG at render time — single static markup, no extra HTTP request, no font load, color and size flow through CSS.

1. Download or clone the [tailwindlabs/heroicons repo](https://github.com/tailwindlabs/heroicons).
2. Copy the `optimized/` subdirectories into `vendor/heroicons/`:
   ```
   vendor/heroicons/
   ├── 24/
   │   ├── outline/   ~290 SVGs
   │   └── solid/     ~290 SVGs
   ├── 20/
   │   └── solid/     ~290 SVGs
   ├── 16/
   │   └── solid/     ~290 SVGs
   └── LICENSE
   ```
3. Use the `heroicon` helper in any layout or partial:
   ```erb
   <%= heroicon('book-open') %>                          <!-- 24×24 outline (default) -->
   <%= heroicon('book-open', variant: :solid) %>         <!-- 24×24 solid -->
   <%= heroicon('arrow-right', variant: :mini) %>        <!-- 20×20 -->
   <%= heroicon('check', variant: :micro) %>             <!-- 16×16 -->

   <!-- Style via CSS class or inline attrs -->
   <%= heroicon('book-open', class: 'text-muted', width: '24', height: '24') %>
   ```

Variant map:

| `:variant` | Source folder |
| --- | --- |
| `:outline` (default) | `24/outline/` |
| `:solid` | `24/solid/` |
| `:mini` | `20/solid/` |
| `:micro` | `16/solid/` |

The icons use `currentColor` for fills/strokes, so `color:` on a parent element controls the icon color. Width/height work as you'd expect on `<svg>`.

No config flag — the helper is always available; it just returns `''` when an icon name isn't found in `vendor/heroicons/`. Browse the [catalog](https://heroicons.com/) for icon names.

## Strict CSP summary

Three of the four options keep the default strict CSP intact:

- **Font Awesome Free (vendored)** — strict
- **Bootstrap Icons (vendored)** — strict
- **Heroicons (inline SVG)** — strict
- **Font Awesome Pro (kit)** — adds `'unsafe-inline'` style-src + 3 hosts

If you keep all four available, only the kit weakens CSP, and only when `icons.fontawesome_kit` is set.

## Removing an icon library

For Font Awesome / Bootstrap Icons: set the config flag to `false` (or delete the line). Optionally delete `public/<name>/` to stop shipping the dist files entirely.

For Heroicons: stop calling the helper. Optionally delete `vendor/heroicons/`.

## Other libraries

Same drop-in pattern works for any library that ships a webfont + CSS bundle:

[Lucide](https://lucide.dev/), [Material Symbols](https://fonts.google.com/icons), [Phosphor](https://phosphoricons.com/), [Tabler](https://tabler.io/icons), [Remix Icon](https://remixicon.com/).

For SVG-only libraries, the Heroicons pattern (vendor + helper) generalizes — drop the SVGs into `vendor/<name>/` and write a small helper modeled on `heroicon`.

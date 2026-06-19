---
title: Build your own theme
description: Start from the `custom` theme — a fully-commented copy of `minimal` with every class Abqari uses already there. Edit, ship.
---

# Build your own theme

Three of the shipped themes (`minimal`, `magazine`, `notebook`) are opinionated visual identities. The fourth (`bootstrap`) bundles Bootstrap 5. The fifth (`custom`) is the **starter for sites that want their own look** — a copy of `minimal` with prominent comments at every customisation point.

Use `custom` when:

- You want a distinctive visual identity (specific brand colours, fonts, component styling).
- You don't want to fork or modify one of the built-in themes (their files might change in future Abqari releases; `custom` is yours).
- You don't want to start from a blank page.

## Activate it

```yaml
# config/site.yml
theme: custom
```

That's it. The site renders identically to `minimal` because `custom` *is* a copy of `minimal`. You then edit `themes/custom/css/app.css` to make it look like your site.

## What's there

Every class Abqari uses is in the file, in named sections:

```
PALETTE + FONTS                — start here. CSS variables that drive everything.
TYPOGRAPHY                     — body, h1–h4, links, code, pre.
NAV + FOOTER                   — site chrome.
THEME TOGGLE                   — sun/moon button styling.
DRAFT + FUTURE BANNERS         — preview-time notices on dated posts.
PHOTO LAYOUT                   — show view for the photos collection.
GALLERY INDEX                  — thumbs grid for /photos/, /country/<x>/, /series/<x>/.
IMAGE GALLERY                  — frontmatter-driven photo arrays.
PUBLICATIONS INDEX             — book list with covers.
PUBLICATION DETAIL             — single book page.
POST LIST                      — blog index cards.
RELATED ITEMS                  — below show views.
NEXT ITEM                      — "Up next" card below posts.
CAROUSEL                       — slideshow.
```

You don't need to style every section — the structural CSS that doesn't change between themes (a11y primitives, tint placeholders, layout standardisation) lives in `app/assets/css/_common.css` and loads automatically.

## Recommended workflow

1. **Set `theme: custom`**, run `bin/serve`. The site looks like `minimal`.
2. **Edit the PALETTE + FONTS block** at the top of `themes/custom/css/app.css`. Change `--color-text`, `--color-bg`, `--color-link`, the fonts. ~3 lines of edits, the whole site picks up the new palette.
3. **Iterate on TYPOGRAPHY** — the `body`, `h1`–`h4`, `a`, `code`, `pre` rules just below the palette. This is where most of "your site's voice" comes from.
4. **Tweak components only when you need to** — most users never edit the photo layout or carousel rules. The defaults are already CLS-safe and accessible.

## Two patterns to know

**Light/dark variants.** The palette is defined three times: in `:root` (the light default), in `@media (prefers-color-scheme: dark)`, and in `[data-theme="dark"]`. The third is for users who've explicitly clicked the theme toggle to override their OS preference. Update all three when changing colours.

**CSS variable composition.** Every component rule reads from CSS variables (`var(--color-text)` etc.). When you change a variable in the palette block, every component picks it up. Don't hard-code colours inside component blocks — use the variables.

## When to graduate beyond `custom`

`themes/custom/` is "your CSS file." That's enough for ~95% of cases. If you find yourself wanting:

- Multiple themes for the same site (e.g., a special "dark mode print" stylesheet)
- Sass/Less preprocessing
- A separate stylesheet per layout

…then you're past what `custom` is shaped for. The asset pipeline copies whatever's in `themes/<name>/`, so you can split into multiple files and link them from layouts. But that's a bigger refactor — most sites never need it.

## Should you even use `custom`, or just edit `minimal` directly?

Either works. The differences:

| | Edit `minimal` | Use `custom` |
| --- | --- | --- |
| Future Abqari updates may change `minimal` | yes — your edits could conflict on `bin/upgrade` | no — `custom` is yours |
| Naming clarity | someone reading your repo expects `minimal` to look like `minimal` | someone reading your repo sees `custom` and knows it's edited |
| Switching between Abqari's stock themes | breaks (your edits are in `minimal`) | clean (just flip `theme:` config) |

Recommendation: **use `custom`** unless you're doing a one-off tiny tweak.

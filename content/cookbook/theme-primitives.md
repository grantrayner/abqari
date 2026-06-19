---
title: Theme primitives — tokens, containers, breakpoints
description: The CSS variables and conventions Abqari themes share. Override individually to retune your site without touching every component.
---

# Theme primitives

Abqari ships a small set of CSS custom-property tokens that themes share — spacing scale, container widths, border radii — plus documented breakpoint conventions for media queries. Use these in your custom theme so components stay consistent and a single change cascades everywhere.

The tokens live in `app/assets/css/_common.css` (loaded before any theme). Themes can override individual tokens by re-declaring them in their own `:root` block.

## Spacing scale

```css
:root {
  --space-xs:  0.25rem;     /*  4px — inline gaps */
  --space-sm:  0.5rem;      /*  8px — small gaps in cards */
  --space-md:  1rem;        /* 16px — body padding, paragraph spacing */
  --space-lg:  1.5rem;      /* 24px — section gaps */
  --space-xl:  2rem;        /* 32px — major section breaks */
  --space-2xl: 3rem;        /* 48px — page-level breaks */
}
```

Six steps. The progression is roughly geometric (each step ≈1.5–2× the previous) — close enough to feel rhythmic without being a strict math system.

**Use:**

```css
.my-card {
  padding: var(--space-md);
  margin-bottom: var(--space-lg);
}
```

**Don't:**

```css
.my-card {
  padding: 1rem;        /* hard-coded — won't follow theme tweaks */
  margin-bottom: 24px;  /* mixed units, drifts from rhythm */
}
```

If you want tighter or looser proportions site-wide, override the tokens in your theme's `:root`:

```css
:root {
  /* halve all spacing for a denser layout */
  --space-md: 0.75rem;
  --space-lg: 1rem;
  /* etc. */
}
```

Every component picks up the new values.

## Container widths

```css
:root {
  --container-narrow:   640px;   /* prose-heavy single column */
  --container-default:  720px;   /* default reading width */
  --container-wide:     880px;   /* image-heavy / wider prose */
  --container-full:    1200px;   /* dashboard-ish */
}
```

Themes pick one for `body { max-width }`. The `custom` theme's :root reads:

```css
--max-width: var(--container-default);
```

Switch to a wider container by changing one line:

```css
--max-width: var(--container-wide);
```

**Per-page overrides** are possible — wrap the wider content in a div with explicit max-width:

```html
<div style="max-width: var(--container-wide)">
  <!-- gallery, dashboard, etc. -->
</div>
```

But don't litter pages with these. If you find yourself doing it often, change the body container instead.

## Border radii

```css
:root {
  --radius-sm:    2px;     /* inline code, tag pills */
  --radius-md:    4px;     /* cards, buttons, banners */
  --radius-lg:    8px;     /* hero blocks */
  --radius-pill:  999px;   /* fully rounded pills */
}
```

Four steps. If you want a more squared aesthetic, set them all to `0` in your theme. If you want softer rounds, bump `--radius-md` to `6px` and the rest follow.

## Breakpoints (conventions, not variables)

CSS doesn't allow `var()` inside media queries — the values can't be tokenised the same way. Use these *consistent* values across themes and your custom CSS:

| Name | Query | When to use |
| --- | --- | --- |
| `sm` | `@media (max-width: 480px)` | phone portrait — single-column collapse, drop gaps |
| `md` | `@media (max-width: 720px)` | tablet portrait / large phone — most 2-col layouts collapse here |
| `lg` | `@media (max-width: 1024px)` | tablet landscape — minor adjustments, container scaling |

**Pattern**: write the desktop-first rule; use one media query at the size where the layout falls apart; collapse to single column.

```css
.my-2-col {
  display: grid;
  grid-template-columns: 1fr 2fr;
  gap: var(--space-lg);
}

@media (max-width: 720px) {
  .my-2-col { grid-template-columns: 1fr; gap: var(--space-md); }
}
```

Don't write a media query at every breakpoint by reflex. Most layouts only need one — the breakpoint where the layout fails. That's usually `md`.

## What about a 12-column grid?

We don't ship one. CSS Grid handles arbitrary column counts per component natively (`grid-template-columns: repeat(auto-fill, minmax(N, 1fr))`), so a "12-col container with row/col helpers" is mostly cargo-cult from the float era.

If you specifically want Bootstrap's `.container`, `.row`, `.col-md-6` system:

```yaml
# config/site.yml
theme: bootstrap
```

That theme bundles vendored Bootstrap 5.3 and is a different set of tradeoffs (weight + utility classes vs a small handwritten theme). The `minimal` / `magazine` / `notebook` / `custom` themes are deliberately the other path.

## Migrating an existing theme

If you've edited `themes/minimal/` or one of the others and want to use tokens:

1. Open the theme's app.css.
2. Find raw values — `1rem`, `2rem`, `4px`. Most are spacing or radii.
3. Replace with token variables matching the value:
   - `1rem` → `var(--space-md)`
   - `1.5rem` → `var(--space-lg)`
   - `4px` → `var(--radius-md)`
4. Build, verify visually identical (which it should be — the token values match the literals).

Once your theme uses tokens consistently, you can retune the whole site by overriding tokens in `:root`. That's the payoff.

The `custom` theme already does this for the body / nav / footer / code rules — open `themes/custom/css/app.css` to see the pattern.

## What this is not

- **Not a utility-class framework** like Tailwind. `<div class="p-4 mb-6">` requires you to learn a vocabulary; tokens just mean components share consistent values.
- **Not a 12-column grid system**. Bootstrap is for that. Components handle their own layouts using CSS Grid.
- **Not container queries**. They're modern but the use case is narrow for blog/photo/publication shapes; we've not seen them needed.

The tokens are about consistency, not power. They're a small, opinionated set of "use these instead of magic numbers."

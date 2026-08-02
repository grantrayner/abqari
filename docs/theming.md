# Theming

Abqari styles a page from up to four CSS layers, concatenated into one
fingerprinted bundle (`/assets/css/bundle.<hash>.css`) in this order:

| # | Layer | File | Owner |
|---|-------|------|-------|
| 1 | Syntax | generated from the Rouge `syntax_theme` | engine |
| 2 | Structure | `app/assets/css/_common.css` | engine |
| 3 | Theme | `themes/<name>/css/app.css` | engine or your site |
| 4 | Site overrides | `app/assets/css/site.css` | your site |

Later layers win on equal specificity. `_common.css` carries all
structure — layout, components, a11y primitives, responsive behaviour —
and reads its colours, fonts, and density from CSS custom properties.
**A theme is a token file**: it declares values for those properties and
(sparingly) adds aesthetic rules. That's the whole contract, and it's
why themes are 100–250 lines instead of thousands.

Every token has a default in `_common.css`, so a theme that defines
nothing still renders correctly — you only declare what you want to
change.

## Making a theme yours

The engine's themes live inside the installed gem, so don't edit them in
place — copy one into your site, where the site-over-engine precedence
makes your copy the live one:

```bash
abqari theme eject custom               # the annotated starter
abqari theme eject minimal              # shadow minimal in place
abqari theme eject sand --as mytheme    # fork sand under your own name
```

`--as` updates `theme:` in `config/site.yml` for you. Theme names are
lowercase letters, digits, `-` and `_` only. Any name works — a site-local
`themes/anything/css/app.css` plus `theme: anything` is a complete
custom theme; no engine registration needed.

Three related knobs:

- `theme: none` — no engine CSS at all, not even `_common.css`. The
  scaffold gives you an empty `app/assets/css/app.css` to write into.
- `app/assets/css/site.css` — loads after the theme; the right place
  for small brand tweaks when forking a whole theme is overkill.
- `theme: bootstrap` — the vendored Bootstrap dist plus a thin token
  bridge. It skips `_common.css` and can't be renamed (the engine keys
  its special-casing on the literal name), but it can be shadowed:
  `abqari theme eject bootstrap`.

With `bin/serve` running, theme edits hot-reload without a full page
refresh.

## Token reference

These are the custom properties `_common.css` reads. Declare them in
`:root` (light values) and in the dark-mode blocks (see below).
Defaults shown are what you get without a theme.

### Colours

| Token | Default | Role |
|-------|---------|------|
| `--color-bg` | `#fafafa` | page background |
| `--color-text` | `#1a1a1a` | body text |
| `--color-muted` | `#6b6b6b` | meta text, captions, timestamps |
| `--color-link` | `#0d6efd` | links |
| `--color-rule` | `rgba(0,0,0,0.12)` | hairlines, borders |
| `--color-card-bg` | `#fff` | cards, panels |
| `--color-code-bg` | `rgba(0,0,0,0.05)` | inline code, code blocks |
| `--color-primary` | `#0d6efd` | buttons, active states |
| `--color-secondary` | `#6c757d` | secondary buttons |
| `--color-success` | `#198754` | success banners |
| `--color-warning` | `#ffc107` | draft/future banners |
| `--color-danger` | `#dc3545` | error states |
| `--color-info` | `#0dcaf0` | info accents |
| `--color-light` | `#f8f9fa` | light surface |
| `--color-dark` | `#212529` | dark surface |
| `--color-price` | `var(--color-primary)` | price text on publication cards/headers — point at `--color-text` when your primary doubles as the link colour, so prices don't read as clickable |

Each `--color-X` above that paints a surface has a matching
`--color-on-X` for text placed on it: `--color-on-primary`,
`--color-on-secondary`, `--color-on-success`, `--color-on-warning`,
`--color-on-danger`, `--color-on-info`, `--color-on-light`,
`--color-on-dark`. Keep each pair at a WCAG-AA 4.5:1 contrast ratio
in both modes — the shipped themes all measure at or above it.

### Webfonts per shipped theme

A theme's `--font-*` stacks can name any face, but the face only
renders if the site downloads it — `fonts:` in `config/site.yml` +
`bin/fetch-fonts`. `abqari new --theme <name>` scaffolds the right
block; `abqari theme eject` prints it. For reference:

| Theme | Webfonts |
|-------|----------|
| `minimal` / `custom` / `bootstrap` / `none` | none — system fonts |
| `magazine` | Playfair Display 700 |
| `notebook` | Inter 400/600 · JetBrains Mono 400/600 |
| `sand` | Merriweather 400/700 + 400 italic · Merriweather Sans 400/600 |

### Fonts and density

| Token | Default | Role |
|-------|---------|------|
| `--font-body` | system-ui stack | body prose |
| `--font-heading` | `var(--font-body)` | headings |
| `--font-meta` | `var(--font-body)` | dates, bylines, captions |
| `--font-mono` | ui-monospace stack | code |
| `--font-sans` | system-ui stack | UI chrome (nav, buttons) |
| `--font-size-body` | `1.0625rem` | base size — the "prose vs docs" knob |
| `--line-height-body` | `1.7` | base leading |

### Spacing, radii, shadows

| Token | Default | Role |
|-------|---------|------|
| `--space-xs`, `--space-sm`, `--space-md`, `--space-lg`, `--space-xl`, `--space-2xl` | `0.25rem` → `3rem` | the six-step spacing scale |
| `--radius-0`, `--radius-1`, `--radius-2`, `--radius-3`, `--radius-4` | `0` → `1rem` | corner radius scale |
| `--radius-pill`, `--radius-circle` | `999px`, `50%` | pills, avatars |
| `--radius-sm`, `--radius-md`, `--radius-lg` | aliases of 1/2/3 | legacy aliases |
| `--shadow-card` | subtle | cards at rest |
| `--shadow-soft` | medium | hover lift |
| `--shadow-cover` | strong | book covers, hero art |

### Layout

| Token | Default | Role |
|-------|---------|------|
| `--content-max-width` | `100%` | prose column width — the engine's layout reads this |
| `--container-narrow`, `--container-default`, `--container-wide`, `--container-full` | `640/720/880/1200px` | preset widths for use in your theme or site.css, e.g. `--content-max-width: var(--container-default)` |

### Tag chips (opt-in)

Tag pills are unstyled-but-tidy by default; these have no `:root`
defaults — declaring any of them opts into the styled look (see the
notebook theme for a worked example): `--tag-bg`, `--tag-font`,
`--tag-font-size`, `--tag-padding`, `--tag-radius`, `--tag-prefix`.

Anything else you find in `_common.css` prefixed `--i`, `--n` or
`--max-` is internal to the CSS-only fan/tilt layouts — not theme API.

## Dark mode

Every theme declares its dark values twice, once per trigger:

```css
/* 1. OS preference, unless the visitor chose light explicitly */
@media (prefers-color-scheme: dark) {
  :root:not([data-theme="light"]) { --color-bg: #101214; /* … */ }
}

/* 2. The visitor clicked the toggle */
[data-theme="dark"] { --color-bg: #101214; /* … */ }
```

The two blocks must stay identical — copy one into the other whenever
you change a value. (A future engine release may collapse this to
`light-dark()`; the two-block form works everywhere today.)

The toggle itself is engine-supplied (`theme_toggle: true` by default):
a CSP-hash-pinned inline script applies the saved choice before first
paint, so there's no flash of the wrong mode.

## Syntax highlighting

The syntax layer follows the same light/dark resolution as the theme
tokens. `syntax_theme` (default `github`) renders at `.highlight`;
its dark counterpart renders under the two dark-mode scopes above.

- `syntax_theme_dark: <name>` — pick the dark Rouge theme explicitly
  (mode-suffixed names like `github.dark` work).
- unset — derived from `syntax_theme`'s own dark mode when it has one;
  themes without modes (monokai etc.) are reused as-is in both modes.
- `syntax_theme_dark: false` — opt out; light tokens in both modes.

The code-block **background** always comes from `--color-code-bg`, not
from Rouge — your theme owns it in both modes. Rouge supplies token
colours only.

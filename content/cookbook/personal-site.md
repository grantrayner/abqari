---
title: Build a single-page portfolio
description: Use Abqari for a personal site, CV, or landing page with no posts. The "long single page" pattern, plus when not to use it.
---

# Build a single-page portfolio

Abqari ships blog-shaped examples by default, but it works just as well as a one-page personal site or portfolio. This recipe shows the pattern: one long `index.md` with a two-column narrative layout (heading-left, prose-right), an image gallery for photos, and the contact button. No posts, no tag pages, no pagination.

## What you'll have

A single page at `/` that looks something like:

```
┌──────────────────────────────────────────────────────┐
│  [GR]                                                │
│                                                      │
│  Hi there. My name is Grant Rayner. For two decades… │
│                                                      │
├─ CONSULTING ─────────────────────────────────────────┤
│  I've spent the past 20+ years working in crisis     │
│  management and travel risk management…              │
│                                                      │
├─ BOOKS ──────────────────────────────────────────────┤
│  Across various topics, I've written and published   │
│  thirteen books…                                     │
│                                                      │
│  [photo grid]                                        │
│                                                      │
├─ CONTACT ────────────────────────────────────────────┤
│                              [Contact me]            │
└──────────────────────────────────────────────────────┘
```

## 1. Strip the example content

```bash
bin/new --name "Your Name" --description "Who I am and what I'm working on" --clean
```

`--clean` removes the example posts, audit reports, vendored fonts, and resets git so you start fresh.

## 2. Replace `content/index.md`

```markdown
---
title: Your Name
description: Who I am and what I'm working on
images:
  - { path: /assets/img/photo-01.jpg, alt: A morning in Damascus }
  - { path: /assets/img/photo-02.jpg, alt: Hand-bound notebook }
  - { path: /assets/img/photo-03.jpg, alt: Workshop in Singapore }
gallery:
  columns: 3
  randomize: true
---

<section class="row">
  <div class="col-heading"><h2>Hi</h2></div>
  <div class="col-body">

  Welcome. My name is Your Name. I work on…

  </div>
</section>

<section class="row">
  <div class="col-heading"><h2>Consulting</h2></div>
  <div class="col-body">

  I've spent the past N years working in…

  </div>
</section>

<section class="row">
  <div class="col-heading"><h2>Photography</h2></div>
  <div class="col-body">

  My favourite shots from recent travels.

  </div>
</section>

<%= render 'partials/image_gallery' %>

<section class="row">
  <div class="col-heading"><h2>Contact</h2></div>
  <div class="col-body">

  Drop me a line.

  </div>
</section>
```

> **Note**: Abqari renders Markdown bodies through CommonMarker only, not ERB. For the `<%= render 'partials/image_gallery' %>` line above to work, switch the file to `content/index.html.erb` (Abqari renders `.html.erb` files through ERB) or place the gallery via a custom layout — see step 4.

## 3. Two-column section CSS

Add to your theme's `app.css`:

```css
.row {
  display: grid;
  grid-template-columns: 1fr 3fr;
  gap: 2rem;
  margin: 3rem 0;
  align-items: start;
}

.col-heading h2 {
  font-size: 0.875rem;
  text-transform: uppercase;
  letter-spacing: 0.05em;
  color: var(--color-muted);
  margin: 0;
}

.col-body p:first-of-type { margin-top: 0; }

@media (max-width: 600px) {
  .row { grid-template-columns: 1fr; gap: 0.5rem; }
}
```

This is the heading-left, prose-right pattern that long-form personal sites use to good effect.

## 4. Custom home layout (recommended)

For full control of the home page — including ERB tags inside the layout — create `app/views/layouts/portfolio.html.erb`:

```erb
<!DOCTYPE html>
<html lang="<%= site.config['locale'] || 'en' %>">
<%= render 'partials/head' %>
<body>
  <%= render 'partials/skip_link' %>
  <main id="main-content" tabindex="-1">

    <h1 class="visually-hidden"><%= site.config['title'] %></h1>

    <%= page.content %>

    <%= render 'partials/image_gallery' %>
    <%= render 'partials/contact_button' %>

  </main>
  <%= render 'partials/footer' %>
</body>
</html>
```

Then point `content/index.md` at it:

```yaml
---
layout: portfolio
title: Your Name
images: [ ... ]
gallery: { columns: 3, randomize: true }
---
```

The visually-hidden `<h1>` covers screen-reader users while letting your visual design lead with whatever stylized logo or intro you prefer.

## 5. Disable blog scaffolding

If you don't want a blog at all, delete:

- `content/blog/`
- `content/posts/`
- `app/views/layouts/blog_index.html.erb`
- `app/views/layouts/post.html.erb`
- `app/views/layouts/tag.html.erb`

Pages can still link to one another via standard Markdown links — you don't need posts/tags machinery for a personal site.

## When this pattern is *not* the right fit

- **You want SEO juice from individual pages.** A single long page with `#consulting`, `#books`, `#contact` anchors gets one URL. Search engines may rank fragments, but it's worse than separate URLs. If you want each section to rank, make it a separate `content/<topic>.md` page and link from the home.
- **The page exceeds ~3000 words.** Long pages tank Time To Interactive and image bandwidth. Split into proper sub-pages.
- **You want comments per section.** Comments belong on individual posts/pages, not on a single landing page.

For a CV / portfolio / "here's who I am" site that fits comfortably on one screen-and-a-half of scrolling, single-page is the right shape.

## Reference: this pattern in the wild

The pattern shown here mirrors `apps/grantrayner` — a real Jekyll site that does exactly this. The Jekyll version uses Bootstrap from a CDN; the Abqari version above uses your theme's CSS, vendored, with the strict CSP intact and no third-party requests.

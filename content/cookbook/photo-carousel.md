---
title: Add a photo carousel
description: Slideshow view of any collection. Vanilla JS, no Bootstrap, CSP-safe.
---

# Add a photo carousel

Abqari ships a lightweight slideshow for browsing a collection one item at a time. Used in the [grphotos](https://github.com/example/grphotos) reference site as `/carousel/`. No Bootstrap, no jQuery, no inline scripts — works under the strict default CSP.

## Render the carousel

The simplest form — slideshow over the entire `photos` collection:

```erb
<%= render 'partials/carousel' %>
```

Or render a different collection:

```erb
<%= render 'partials/carousel', collection: 'posts' %>
```

Or pass an explicit list (e.g. only the latest 20 photos):

```erb
<%= render 'partials/carousel', items: site.collection('photos').first(20) %>
```

## Make it a dedicated page

Most photo blogs put the carousel on its own URL. Create `content/carousel.md`:

```markdown
---
title: Carousel
permalink: /carousel/
nav:
  order: 4
---
```

Then create a small layout for it (`app/views/layouts/carousel.html.erb`):

```erb
<!DOCTYPE html>
<html lang="<%= site.config['locale'] || 'en' %>">
<%= render 'partials/head' %>
<body>
  <%= render 'partials/skip_link' %>
  <%= render 'partials/nav' %>
  <main id="main-content" tabindex="-1">
    <%= render 'partials/carousel' %>
  </main>
  <%= render 'partials/footer' %>
</body>
</html>
```

And reference it from the markdown frontmatter (`layout: carousel`). The page now renders at `/carousel/` with the slideshow as its only content.

## What you get

- Click-able prev/next buttons
- Arrow-key navigation when the carousel has focus
- A "1 / 20" counter showing position
- `aria-hidden` updated per slide for screen readers
- `loading="lazy"` on all but the first image (which gets `fetchpriority="high"`)
- `aria-label` on prev/next buttons

## What it doesn't do

- **No autoplay.** Photo carousels with autoplay are user-hostile — stops the visitor reading captions, eats battery, ignores `prefers-reduced-motion`. If you really want autoplay, add ~5 lines to `carousel.js` to call `show(current + 1)` on a `setInterval`.
- **No swipe gestures.** A pointer-events polyfill for swipe would double the JS size; click + arrow-keys cover most use cases.
- **No fullscreen / lightbox.** The slide is the page when the carousel is on a dedicated route. For a lightbox-style overlay (open one photo at a time without leaving the gallery), you'd build a separate component — out of scope for this recipe.

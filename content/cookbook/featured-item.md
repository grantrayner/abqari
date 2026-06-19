---
title: Feature one item on the home page
description: Pin a specific publication, post, or photo to the top of your home page using a slug-based config knob.
---

# Feature one item on the home page

A common pattern for the three Abqari pillars (writing, photos, publications): show one specific item prominently on the home page — the latest book, a featured essay, a photo of the week. Abqari ships `site.featured(collection, slug)` for this.

## Set the slug in config

```yaml
# config/site.yml
featured:
  publication: the-field-guide
  post: my-best-essay-yet
  photo: 2026-04-02-old-city-walls
```

You can have any number of featured slots — `featured:` is a freeform hash you read in templates.

## Look it up in a template

In any layout (`content/index.md` runs through ERB if you make it `index.html.erb`, or wrap in a custom home layout):

```erb
<% featured_pub = site.featured('publications', site.config.dig('featured', 'publication')) %>
<% if featured_pub %>
  <section class="featured">
    <h2>Latest publication</h2>
    <a href="<%= featured_pub.url %>">
      <% if featured_pub.frontmatter['cover'] %>
        <img src="<%= featured_pub.frontmatter['cover'] %>" alt="<%= featured_pub.title %> cover">
      <% end %>
      <div>
        <h3><%= featured_pub.title %></h3>
        <p><%= featured_pub.frontmatter['description'] %></p>
        <% if featured_pub.frontmatter['price'] %>
          <p class="price"><%= featured_pub.frontmatter['price'] %></p>
        <% end %>
      </div>
    </a>
  </section>
<% end %>
```

`site.featured` returns the matching `Page` (or `nil` if the slug doesn't match anything in that collection). Slug-matches against `Page#slug`; falls back to the URL's last segment for pages without an explicit slug.

## When the slug is wrong

`site.featured` returns nil. The conditional `<% if featured_pub %>` skips the block — your home page renders without the featured section, no error. The audit will flag the missing slug if you wire it through frontmatter validation (`validate.featured: data/featured-allowed.yml`).

## Why slug-based, not "latest"

You could pick the latest item with `site.collection('publications').first` — and that's right for "what's new." But "featured" usually means "the one I want people to see right now" — which is often *not* the latest. A new but low-value piece shouldn't bump out the book that's been your best work for a year. A config knob lets you pin manually.

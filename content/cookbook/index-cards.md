---
title: Choose what appears on index cards
description: Toggle the bits of metadata shown on blog, photo, and publication index cards via simple config booleans. No layout edits required.
---

# Choose what appears on index cards

Each index page (blog list, photo gallery, publications list) renders a card per item. What appears on the card — description, date, reading time, camera, ISBN — varies by use case. Abqari ships toggles per collection so you can pick without editing layouts.

## Where the toggles live

```yaml
# config/site.yml
collections:
  posts:
    index:
      show_date: true
      show_description: true
      description_truncate: 160       # characters, before the ellipsis
      show_reading_time: true
      show_tags: false                # off by default — tags appear on the post itself
  photos:
    index:
      show_location: true             # city + country
      show_date: true
      show_camera: false              # off by default — varies by gallery
      show_caption: false             # off by default — most galleries don't want it on cards
      caption_truncate: 100
  publications:
    index:
      show_description: true
      description_truncate: 200
      show_price: true
      show_isbn: false
      show_pages: false
      show_published: false
```

## What the defaults look like

**Blog post card** (defaults):

```
A first post about what I'm working on
April 15, 2026 · 5 min read
A short description from the post's front matter, truncated at 160…
```

**Photo card** (defaults):

```
[ thumbnail ]
Tea break
Damascus, Syria
March 15, 2026
```

**Publication card** (defaults):

```
[ cover ]   The Field Guide to Static Sites
            A practical handbook for self-hosted publishing in 2026.
            $18.99
```

## Common changes

**Show camera on photo cards** (useful for camera-focused galleries):

```yaml
photos:
  index:
    show_camera: true
```

**Hide reading time** (you write 30-second posts; it's noise):

```yaml
posts:
  index:
    show_reading_time: false
```

**Show ISBN + pages on publication cards** (you sell technical books):

```yaml
publications:
  index:
    show_isbn: true
    show_pages: true
```

**Tighter description** (long descriptions are eating the layout):

```yaml
posts:
  index:
    description_truncate: 80
```

## What the toggles can't do

The toggles are deliberately minimal — booleans + a few truncation lengths. They cover ~95% of "what do I want on the card?" decisions. The other 5%:

- **Custom delimiters or formatting** ("date · camera · series" with bullets)
- **Conditional logic** ("show camera *only* on photos in the Syria series")
- **Custom HTML or links** (a "save" star next to each card)

For those, edit the layout/partial directly — that's faster than chasing config knobs. The relevant files:

- Blog post list: `app/views/partials/_post_list.html.erb`
- Photo gallery / country / series: `app/views/layouts/{gallery_index,country_index,photo_series_index}.html.erb`
- Publications: `app/views/layouts/publications_index.html.erb`

Any toggles you set in config are a runtime *override* of the layout's defaults, not a replacement of the layout. So you can:

1. Use the config toggles as the simple knobs they are, and
2. Edit the partial when you need something more — and your config toggles still work in the edited partial as long as you keep the `cfg.fetch('show_X', default)` reads.

## Per-page overrides

The toggles live on the *collection*, not on individual pages. If you want one page to show different fields than the rest of its collection (e.g., a special "highlights" view of the blog), the cleanest path is a separate page with its own layout that reads from `site.collection('posts')` directly. That's a layout customisation, not a config one.

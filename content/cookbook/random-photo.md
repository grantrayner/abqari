---
title: Show a random photo on the home page
description: A discovery-friendly alternative to "latest" — surface a different photo on every build (or every visit, with a small JS bump).
---

# Show a random photo on the home page

For photo galleries, "latest" isn't always the best home-page anchor. A random photo from the archive surfaces older work that would otherwise sink to the bottom. Two ways to do it: at build time (deterministic per build) or at visit time (different on every page load).

## Build-time: random per deploy

`Array#sample` is built into Ruby; `site.collection` returns an Array. Use it directly in any ERB template:

```erb
<% photo = site.collection('photos').sample %>
<% if photo %>
  <a href="<%= photo.url %>">
    <% if photo.frontmatter['image'] %>
      <img src="<%= photo.frontmatter['image'] %>"
           alt="<%= photo.frontmatter['caption'] || photo.title %>">
    <% end %>
    <h2><%= photo.title %></h2>
    <p><%= photo.frontmatter['caption'] %></p>
    <p>
      <%= [photo.frontmatter['city'], photo.frontmatter['country']].compact.join(', ') %>
      ·
      <time datetime="<%= photo.date.iso8601 %>"><%= local_time(photo.date) %></time>
    </p>
  </a>
<% end %>
```

A new random photo is picked on every `bin/build`. Visitors see the same photo until you redeploy. Most photo blogs are fine with this — it's free, requires no JS, plays nicely with caching.

## Visit-time: different on every page load

If you want a fresh photo on every visit, render *all* photos to the page (in a hidden list) and let JavaScript pick one on load. Requires JS but works under the strict CSP via a small external script.

```erb
<div id="random-photo" data-random-photo>
  <% site.collection('photos').each do |photo| %>
    <template
      data-href="<%= photo.url %>"
      data-image="<%= photo.frontmatter['image'] %>"
      data-title="<%= photo.title %>"
      data-caption="<%= photo.frontmatter['caption'] %>"></template>
  <% end %>
</div>
<script src="/assets/js/random-photo.js" defer></script>
```

`app/assets/js/random-photo.js`:

```js
(function () {
  var root = document.querySelector('[data-random-photo]');
  if (!root) return;
  var templates = root.querySelectorAll('template');
  if (!templates.length) return;
  var t = templates[Math.floor(Math.random() * templates.length)];
  root.innerHTML =
    '<a href="' + t.dataset.href + '">' +
      '<img src="' + t.dataset.image + '" alt="' + (t.dataset.caption || t.dataset.title) + '">' +
      '<h2>' + t.dataset.title + '</h2>' +
      (t.dataset.caption ? '<p>' + t.dataset.caption + '</p>' : '') +
    '</a>';
})();
```

Trade-off: ships every photo's metadata in the HTML, even though only one renders. Fine for ~50 photos; gets bulky beyond that.

## Why a "random" home page is good for photo galleries

Photo work has a long tail. The latest twenty photos get attention; everything before that drops off the radar. A random selector promotes equal visibility for the archive — a five-year-old photo has the same shot at the home page as today's. For a portfolio site, that's usually what you want.

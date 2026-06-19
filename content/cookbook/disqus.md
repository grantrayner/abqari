---
title: Add Disqus comments
description: Drop Disqus into post pages with one partial.
---

# Add Disqus comments

[Disqus](https://disqus.com/) is the easiest way to add comments to a static site. Trade-off: it's a third-party service that loads ~700KB of JavaScript and trackers — privacy-conscious users may prefer [Cusdis](https://cusdis.com/) or just no comments.

## 1. Sign up and get your shortname

Create a Disqus account, register your site, and copy the shortname Disqus assigns (e.g. `my-blog`).

## 2. Allow the Disqus domain in your CSP

Disqus loads scripts and embeds iframes from its own domains. Override the default headers in `config/site.yml`:

```yaml
headers:
  '/*':
    Content-Security-Policy: >
      default-src 'self';
      img-src 'self' data: https://*.disquscdn.com https://*.disqus.com;
      style-src 'self' 'unsafe-inline' https://*.disquscdn.com;
      script-src 'self' 'sha256-…' https://*.disqus.com https://*.disquscdn.com;
      font-src 'self' https://*.disquscdn.com;
      frame-src https://disqus.com;
      connect-src 'self' https://*.disqus.com;
      frame-ancestors 'none';
      base-uri 'self'
    Strict-Transport-Security: "max-age=31536000; includeSubDomains"
    X-Content-Type-Options: nosniff
    Referrer-Policy: strict-origin-when-cross-origin
    Permissions-Policy: "camera=(), microphone=(), geolocation=(), interest-cohort=()"
```

Disqus needs `'unsafe-inline'` for styles. Their script also creates iframes for the comment thread, hence `frame-src https://disqus.com`.

## 3. Add a comments partial

Create `app/views/partials/_disqus.html.erb`:

```erb
<%# Disqus comments. Render at the bottom of post.html.erb. %>
<div id="disqus_thread"></div>
<script src="<%= asset_path('js/disqus-init.js') %>" defer></script>
```

Create `app/assets/js/disqus-init.js`:

```javascript
window.disqus_config = function () {
  this.page.url = window.location.href;
  this.page.identifier = window.location.pathname;
};
(function () {
  var d = document, s = d.createElement('script');
  s.src = 'https://YOUR-SHORTNAME.disqus.com/embed.js';
  s.setAttribute('data-timestamp', +new Date());
  (d.head || d.body).appendChild(s);
})();
```

Replace `YOUR-SHORTNAME`.

## 4. Render at the bottom of posts

Edit `app/views/layouts/post.html.erb` and add before `</article>`:

```erb
<%= render 'partials/disqus' %>
```

## 5. Per-post opt-out

If you want some posts without comments, add `comments: false` to front matter and check it in the layout:

```erb
<% if page.frontmatter['comments'] != false %>
<%= render 'partials/disqus' %>
<% end %>
```

## Privacy considerations

Disqus is owned by Zeta Global, an ad-tech company. Its embeds load ad trackers by default — the more privacy-conscious alternative is [Cusdis](https://cusdis.com/) or self-hosted Commento. If you must use Disqus, at least disable third-party tracking in your Disqus admin settings.

---
title: IndieWeb foundations — microformats, webmentions, Bridgy Fed
published: true
description: Class hooks for h-entry / h-card, webmention.io receive, opt-in webmention send, and Bridgy Fed link tags.
tags: [indieweb, webmentions, federation, v0.4.0]
cover: svg
---

Abqari 0.4.0 ships native IndieWeb support — three independently
useful pieces that together make a static Abqari site a
first-class citizen of the open web, addressable from Mastodon,
discoverable to webmention parsers, and visible to anyone
following the slow erosion of the centralised platforms.

All four pieces are off by default. Opt in once in `config/site.yml`:

```yaml
indieweb:
  enabled: true
  domain: example.com
  webmention_io_token: "..."          # required for webmention receive
  bridgy_fed: true                    # adds Bridgy Fed link tags
  send_webmentions: true              # opt in to outbound notifications
  send_window_days: 30
```

## 1. Microformats2 markup

Class hooks baked into post, post-list, and about layouts. Invisible
to humans, structured for IndieWeb parsers and feed readers that
grok microformats.

- **`h-entry`** on each post `<article>`
- **`p-name`** on the post `<h1>`
- **`dt-published`** on the post date `<time>`
- **`e-content`** wrapping the body
- **`p-category`** on tag links
- **`u-url`** on the canonical post link
- **`p-summary`** on description meta
- **`h-feed`** on the post-list container
- **`h-card`** on the about page

These ship enabled — flip nothing, get the markup. Verify your
site parses cleanly at [indiewebify.me](https://indiewebify.me/).

## 2. Webmention receive (via webmention.io)

The build polls [webmention.io](https://webmention.io) at build
time and caches the response under `vendor/webmentions/mentions.json`.
A new `_webmentions` partial renders a "Replies & mentions" section
below each post:

- **Replies** render as full author + body cards
- **Likes / reposts / bookmarks** render facepile-style — small
  avatars, no body

No JavaScript, no comment backend, no moderation queue. Spam is
structurally rare because replies have to be published on a real
website first.

ETag-cached: subsequent builds typically get a 304 and reuse the
cached JSON. Cache lives under `vendor/webmentions/`, gitignored
out of the box.

Setup:

1. Sign in to [webmention.io](https://webmention.io) with
   IndieAuth (RelMeAuth via your About page's `rel="me"` links).
2. Copy your API token from your webmention.io account page.
3. Add to `config/site.yml`:

   ```yaml
   indieweb:
     enabled: true
     domain: example.com
     webmention_io_token: "your-token"
   ```

4. Build. The first poll fetches every mention webmention.io has
   for your domain.

The token is sent in the `Authorization: Bearer …` header (not the
query string), so it doesn't leak into upstream proxy/access logs.

## 3. Webmention send (opt-in)

Off by default. When `send_webmentions: true`, every build POSTs
webmention notifications to external URLs that recent posts link
to. Endpoint discovery follows the spec:

1. **HEAD** the target; check `Link: <…>; rel="webmention"`.
2. Fall back to **GET**; check `<link rel="webmention" …>` in `<head>`.

Sent targets are tracked in `vendor/webmentions/sent.yml`
(atomic-write, won't corrupt on interrupted build). Only posts
within `send_window_days` (default 30) are candidates — historical
posts have already received their initial round.

Retry policy: `'sent'` entries are skipped; `'no-endpoint'` and
`'failed'` entries get retried on the next build — a single bad
build doesn't permanently exclude a (source, target) pair.

## 4. Bridgy Fed link tags (opt-in)

When `bridgy_fed: true`, the `<head>` emits two link tags:

```html
<link rel="me" href="https://fed.brid.gy/r/https://example.com/">
<link rel="alternate" type="application/activity+json"
      href="https://fed.brid.gy/r/https://example.com/">
```

[Bridgy Fed](https://fed.brid.gy) speaks ActivityPub on your site's
behalf. Mastodon users can then search `@<your-domain>` and follow
the site directly. Replies on Mastodon flow back as webmentions
via Bridgy — which webmention.io receives and your build picks up
on the next poll.

End-to-end, the reply flow becomes:

1. You publish `/guides/foo/`.
2. POSSE auto-syndicates to Mastodon (see [POSSE](/guides/posse/)).
3. Someone replies to the Mastodon toot.
4. Bridgy Fed converts the reply into a webmention POST to
   webmention.io.
5. Your next build fetches the new mention and renders it under
   the post.

The original post on your site becomes the canonical thread —
even when most of the discussion happens on Mastodon.

## Trust + security

Webmention.io's response is bounded-trust input. Abqari's webmention
fetcher routes through `HttpSafe` (8 MB cap, streaming read, 5s
open / 10s read timeouts) so a misbehaving upstream can't OOM the
build. State files are atomically written so a SIGINT mid-write
doesn't corrupt the cache.

Webmention sender's HTTP POSTs and HEAD probes also route through
`HttpSafe` — discovery targets are arbitrary external hosts found
in your post bodies, and the cap defends against hostile or
compromised target sites.

## See also

- [POSSE — Mastodon + Bluesky syndication](/guides/posse/)
- [IndieWeb on Wikipedia](https://en.wikipedia.org/wiki/IndieWeb)
- [webmention.io](https://webmention.io)
- [fed.brid.gy](https://fed.brid.gy)

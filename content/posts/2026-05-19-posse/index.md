---
title: POSSE — Mastodon + Bluesky syndication
published: true
description: Publish on Your Own Site, Syndicate Elsewhere. Each build crossposts new content to Mastodon and Bluesky; replies flow back as webmentions.
tags: [posse, mastodon, bluesky, syndication, v0.4.0]
cover: svg
---

POSSE — "Publish on your Own Site, Syndicate Elsewhere" — turns
the centralised social platforms into distribution channels for
content that lives on your site. The canonical post on
`example.com/guides/foo/` stays the source of truth; readers on
Mastodon and Bluesky discover new work in their normal feed;
replies on those platforms flow back to your site as webmentions
and consolidate under the post.

Abqari ships POSSE for Mastodon and Bluesky in v0.4.0.

## How it works

Each `bin/build` runs the syndication dispatcher after rendering.
For every post in `content/posts/` published within
`window_days` (default 14):

1. Check `vendor/syndication/sent.yml` — if this post has already
   been syndicated to this network, skip.
2. Format the snippet for the network's character cap (Mastodon
   500, Bluesky 300): `<title> — <description> <url>`, truncating
   the description to fit.
3. POST to the network's API.
4. Record the result in `sent.yml` — atomically, so a SIGINT
   mid-write doesn't corrupt the log.

Failures (`'failed'` entries) get retried on the next build; only
`'sent'` entries are skipped. Transient API outages shouldn't
permanently exclude a post from syndication.

## Configure

```yaml
# config/site.yml
syndication:
  enabled: true
  window_days: 14                # only posts published in the
                                 # last N days are candidates;
                                 # historical posts predate
                                 # syndication setup and replaying
                                 # them would look like spam.

  mastodon:
    enabled: true
    instance: https://mastodon.social
    access_token: "..."          # OAuth token, write:statuses scope
    visibility: public           # public | unlisted | private

  bluesky:
    enabled: true
    handle: yourname.bsky.social
    app_password: "..."          # app password, NOT account password
```

### Mastodon token

In your instance's UI:

1. *Preferences → Development → New Application*
2. Name: "Abqari syndication"
3. Scopes: `write:statuses`
4. Submit; copy "Your access token" (NOT client id / secret) and
   paste into `mastodon.access_token`.

### Bluesky app password

In Bluesky:

1. *Settings → App Passwords → Add App Password*
2. Name: "Abqari syndication"
3. Copy the generated password (shown once) and paste into
   `bluesky.app_password`. DO NOT use your account password — app
   passwords are scoped tokens that can be revoked separately.

## Per-post controls

Two frontmatter knobs override default behaviour:

```yaml
---
title: A post
syndicate: false                          # skip POSSE entirely
syndication_text: "Custom snippet  https://example.com/p/foo/"
---
```

- `syndicate: false` excludes a post from POSSE entirely. Useful
  for private/personal posts that you want at a canonical URL but
  not broadcast.
- `syndication_text:` supplies a custom snippet. The auto-formatter
  is skipped. Bluesky link facets find the trailing URL via
  `bytes.rindex` so multiple URL mentions don't break the link
  highlighting.

## What gets posted where

- **Mastodon**: a status with the snippet text and `visibility`
  setting. Your handle's followers see it in their feed.
- **Bluesky**: a post with the snippet text and a `richtext.facet#link`
  spanning the URL bytes — so the URL renders as a clickable link
  rather than plain text. Multi-byte titles (CJK, accented Latin)
  are handled correctly: facet offsets use UTF-8 byte indices.

The post returned by the API (the syndicated URL) is recorded in
`sent.yml` alongside the success marker, so you can inspect what
went where.

## Reply collection

POSSE works best when combined with [IndieWeb webmentions](/guides/indieweb/).
The chain:

1. You publish `/guides/foo/`.
2. POSSE syndicates the post to Mastodon and Bluesky on the next
   build.
3. Someone replies to the Mastodon toot.
4. [Bridgy Fed](https://fed.brid.gy/) converts the reply into a
   webmention POST to webmention.io.
5. The next Abqari build fetches the new mention and renders it
   under the canonical post.

The original post on your site becomes the canonical thread,
gathering replies from every connected network into one place.

## Safety + atomicity

The sent log is atomically written. POSSE state survives crashes
without corruption — a SIGINT or CI timeout mid-write doesn't
result in a half-empty `sent.yml` that re-syndicates every post
on the next build.

The HTTP POSTs to Mastodon and Bluesky route through `HttpSafe`
with a 2 MB response cap, 5 s open timeout, and 15 s read timeout.
A misbehaving instance can't stream gigabytes into the build
process's memory.

Credentials (Mastodon's `Authorization: Bearer …`, Bluesky's
`Authorization: Bearer <accessJwt>` + initial app-password POST)
are sent in headers and body respectively, never in URLs that
might end up in upstream proxy logs.

## See also

- [IndieWeb foundations](/guides/indieweb/) — webmention receive
  + Bridgy Fed
- [POSSE on indieweb.org](https://indieweb.org/POSSE)
- [Mastodon API: statuses](https://docs.joinmastodon.org/methods/statuses/#create)
- [Bluesky AT Protocol: createRecord](https://docs.bsky.app/docs/api/com-atproto-repo-create-record)

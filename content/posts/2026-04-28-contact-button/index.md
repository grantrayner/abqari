---
title: Spam-resistant contact button
published: true
description: A one-config-line contact button for your About page. Email obfuscated against scrapers, no form, no JavaScript framework.
tags: [contact, privacy, configuration]
cover: svg
---

Abqari ships a one-config-line contact button for your About
page. Add your email, the button shows up. No form, no
third-party service, no JavaScript framework — just a small
handler that opens the visitor's mail client when they click.

## Why ship this at all

Most static-site generators leave "how do readers contact you?"
as an exercise. The two common answers — a `mailto:` link or a
contact form — both have problems:

- **Plain `mailto:`** is a magnet for harvesters. Within hours of
  going live, the address is on someone's spam list. By the time
  you notice, it's everywhere.
- **A contact form** needs a third-party service (Formspree,
  Netlify Forms, Web3Forms). That breaks Abqari's "no
  third-party requests" principle, drags in privacy questions,
  and is wildly overkill for "send me an email."

The contact button splits the difference. It's a one-line config
knob that produces a button which works exactly like a `mailto:`
from the visitor's point of view, but with the address obfuscated
against the kind of bot that scrapes static HTML for `@` symbols.

## Enable it

```yaml
# config/site.yml
contact:
  email: you@example.com
  label: Get in touch       # optional, defaults to "Contact"
```

That's the entire setup. The button appears at the bottom of
`/about/` on the next build.

If you don't see the button:

- Did you save `config/site.yml`?
- Did you run `bin/build` (production) or `bin/serve` (with
  auto-reload)?
- Is `email:` actually filled in? An empty value is treated as
  "not configured" — the button stays hidden.

## How the spam protection works

The address is split at `@` into two halves and stored in HTML
data attributes:

```html
<button class="contact-button" data-user="you" data-domain="example.com">
  Get in touch
</button>
```

There is no point in the rendered HTML where the full address
appears as a single string. There is no `mailto:` prefix. A bot
scraping the page sees `you` and `example.com` as two unrelated
tokens. Most harvesters never reassemble them.

A small script attaches a click handler. When the visitor clicks
the button, the handler joins the halves and navigates to
`mailto:user@domain` — which the browser hands to the mail
client.

This is well-known and effective enough that the technique
survives years of bot evolution. It's not bulletproof — bots that
execute JavaScript can still see the assembled address in memory —
but those are the minority.

## Move it elsewhere

By default the button renders only on `/about/`, via the `about`
layout that wraps the page content. You can put the button
anywhere else by rendering the partial:

```erb
<%== render 'partials/contact_button' %>
```

Common spots:

- **Footer** — open `app/views/partials/_footer.html.erb` and drop
  the line in.
- **Every page** — add it to `app/views/layouts/application.html.erb`.
- **A dedicated `/contact/` page** — create `content/contact.md`
  with `layout: about` (or your own layout) and the button will
  render under the page content.

The partial honours the same config block. If `contact.email` is
unset, it renders nothing — so dropping it into a shared layout
is always safe.

## Remove it

Any of three approaches works:

| Approach | Effect |
| --- | --- |
| Clear `contact.email:` in `config/site.yml` | Partial renders nothing site-wide |
| Change `layout: about` → `layout: application` in `content/about.md` | Removes from About; partial still works elsewhere |
| Delete `app/views/layouts/about.html.erb` | About falls back to `application`; same as above |

The first is reversible by adding the email back. The other two
require restoring files.

## Styling

The shipped themes style `.contact-button` with the link colour
and a subtle hover. Override in your theme's `app.css` or
`site.css` if you want a different treatment:

```css
.contact-button {
  display: inline-block;
  padding: 0.5rem 1.25rem;
  background: var(--color-link);
  color: var(--color-bg);
  border: none;
  border-radius: var(--radius-md);
  font: inherit;
  cursor: pointer;
}
.contact-button:hover { opacity: 0.9; }
```

## What it doesn't do

A few things this is intentionally not:

- **Not a contact form.** No fields, no validation, no submission.
  If you want a form, integrate Formspree / Web3Forms / Pages
  Functions yourself — the partial doesn't try to grow into that
  role.
- **Not a chat widget.** No third-party iframe. No tracking.
- **Not a CAPTCHA.** The mail client handles spam filtering;
  that's not Abqari's job.

If any of those become a need, build them as a separate
layout/partial alongside this one. The button is meant to be the
simple option, not a kitchen sink.

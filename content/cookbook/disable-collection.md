---
title: Turn a collection off without deleting content
description: Toggle photos, publications, or any custom collection off with a single config flag — content stays on disk, ready to flip back.
---

# Turn a collection off without deleting content

You're rebuilding your photo gallery and don't want it visible yet. Or you don't sell books and the publications section isn't relevant. Or you're spinning up a writing-only site and want to start without the photo demo content getting in the way.

Don't delete the content directory. Use the `enabled:` flag.

## How

```yaml
# config/site.yml
collections:
  photos:
    enabled: false        # <— this line
    source: content/photos
    permalink: /photos/:slug/
    layout: photo
    # ... index toggles etc. stay as they are
```

That's it. Next build:

- No pages render under `/photos/...` — the collection's index, individual photo pages, all gone.
- No taxonomy pages auto-generate from photo front matter — `/country/<name>/` and `/series/<name>/` disappear too (they were derived from photos).
- The collection's index page (`content/photos/index.md`) is excluded from the auto-generated nav, so the "Photos" link in the header drops.
- All files in `content/photos/` are left untouched on disk.

To bring it back, flip `enabled: true` and rebuild. Everything returns exactly as it was — no content lost.

## Use cases

| Scenario | What to do |
| --- | --- |
| You're rebuilding the gallery; don't want broken/half-edited photos visible | `photos.enabled: false` until you're ready to show |
| You don't ship publications; the demo content is in the way | `publications.enabled: false` (and ignore `content/publications/`) |
| You want a writing-only site for your first month | `photos: enabled: false`, `publications: enabled: false`, leave posts on |
| You're testing a new layout for posts; want to compare with prod | Build with `posts.enabled: false` to verify other collections still work standalone |

## What this *isn't*

- **Not a "scheduled publish"** — `enabled: false` is a manual config flag. For time-based reveals, use post-level `published: false` (drafts) and dated front matter (scheduling).
- **Not a permission system** — there's no per-user / per-environment toggle. If you want photos visible on staging but not production, gate the change with `ABQARI_ENV` and a per-environment overlay in `config/site.yml`.
- **Not a soft-delete** — disabling a collection doesn't preserve its URLs as 410-Gone or redirect them anywhere; they just 404. If you've shipped the URLs publicly, plan a redirect.

## Hardcoded references stay

The home page's markdown body (`content/index.md`) mentions `/photos/`, `/blog/`, `/publications/` directly — those are written-by-you links, not auto-generated. Disabling the collection doesn't remove them from the markdown. If you disable a collection long-term, edit your home page (and any other content) to remove the orphan links manually.

The audit will flag broken internal links, so a `bin/audit` run after toggling is a good way to find what needs cleaning up.

## Why per-collection rather than a global "show me only X"

Collections in Abqari are independent — disabling photos doesn't affect posts or publications, doesn't affect tag taxonomies on posts, doesn't affect the home page's styling. Per-collection toggles give you mix-and-match control without coupling. A "site mode" config (`mode: blog-only`) would be smaller to write but harder to extend; the per-collection flag scales as you add more collections (workshops, projects, recipes).

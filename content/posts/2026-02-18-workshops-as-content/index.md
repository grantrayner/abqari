---
title: Workshops as a content type
published: true
description: A built-in collection for training offerings — structured metadata, upcoming/past partitioning, instructor lists, and a registration CTA.
date: 2026-02-18
tags: [workshops, collections]
---

Most static-site generators treat everything as either a post or a
page. Abqari's workshops collection treats workshops as their own
thing — with structured fields for dates, location, format, price,
and instructors, all rendered as a meta table on the show view.

## Frontmatter shape

```yaml
---
layout: workshop
title: Crisis Response Foundations
description: Two-day workshop on building crisis response capability.
date_from: 2026-06-15
date_to:   2026-06-16
location:  Singapore
format:    In-person
instructors:
  - Grant Rayner
  - Jane Doe
price:     $1,495
registration_url: https://...
tags: [crisis-management]
---
```

Every metadata field is optional. The show view only renders the
rows that have values, and skips the whole `<dl>` block if you set
no metadata at all (handy for evergreen workshop templates).

## Upcoming vs past

The workshops index page partitions automatically: workshops whose
end-date (`date_to` or `date_from`) is before today render in a
compact "Past workshops" section below the upcoming cards. The
past treatment drops the description, format, and price — just
title, dates, and location, with a muted color.

Related workshops on each show view also filter out past entries —
recommending an event that's already happened is noise.

## When to use it

Anything that goes on sale once and runs on a date: workshops,
courses, retreats, summits. If your content has a `date_from` and
ends at a `date_to`, workshops is your collection.

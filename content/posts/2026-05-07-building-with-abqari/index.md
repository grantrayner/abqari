---
title: Building with Abqari
description: How posts, tags, and layouts fit together.
image: hero.svg
tags: [ruby, ssg, tutorials]
redirect_from:
  - /old-tutorial/
---

A second post, published a few weeks after the first. The hero image above lives
inside this post's bundle directory and is referenced from frontmatter by
relative name (`image: hero.svg`) — the same path the index card uses for its
cover thumbnail.

## How it works

Each post is a directory under `content/posts/`. The directory contains:

- An `index.md` with front matter and the post body.
- Any colocated assets (images, downloads, etc.) you want bundled with the post.

The build pipeline:

1. Walks `content/posts/<dir>/index.md`, parses front matter and Markdown body.
2. Reads the date from front matter or the directory's `YYYY-MM-DD-` prefix.
3. Slugifies the directory name (minus the date prefix) to form the URL.
4. Copies non-`.md` siblings of `index.md` into the rendered post's output directory.
5. Rewrites relative `<img>`/`<a>` URLs in the rendered HTML to absolute paths.
6. Generates `/tags/<tag>/` indexes from each post's `tags:` front matter.
7. Renders each post through `app/views/layouts/post.html.erb` by default.

## Customising

Override the layout per page with `layout:` in front matter. Add helpers to `lib/abqari/helpers.rb`. Add partials under `app/views/partials/`.

```ruby
# A custom helper, available everywhere ERB renders
module Abqari
  module Helpers
    def shouty(text)
      text.to_s.upcase + '!'
    end
  end
end
```

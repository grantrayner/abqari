---
title: Writing in Markdown
published: true
description: A tour of the Markdown features supported by Abqari — headings, lists, links, code, tables, footnotes, and a few extras you'll only need now and again.
date: 2026-02-15
tags: [markdown, writing, tutorials]
---

If you're new to Markdown — the plain-text format used to write every post,
page, and photo caption on this site — here's a tour of what you can do.

Each section below shows the **syntax** in a code block followed by the
**rendered result**, so you can scroll back to compare. View the source of
this file (`content/posts/2026-05-08-writing-in-markdown/index.md`) to see
the full unrendered Markdown.

## Headings

```markdown
## Heading 2
### Heading 3
#### Heading 4
```

The `# Heading 1` form is reserved for the post title (set via front matter)
— don't add another `#` in the body. Use `##` for top-level sections,
`###` for sub-sections, and so on, down to `######` for level six.

## Emphasis

```markdown
**Bold**, *italic*, and ***both at once***. ~~Strikethrough~~ for
edits. Use _underscores_ if asterisks feel busy — both work.
```

**Bold**, *italic*, and ***both at once***. ~~Strikethrough~~ for edits.
Use _underscores_ if asterisks feel busy — both work.

For highlighting, Markdown doesn't ship a syntax — but you can use plain
HTML inline: `<mark>like this</mark>` renders as <mark>like this</mark>.

## Lists

### Unordered

```markdown
- First item
- Second item
  - A nested item (indent two spaces)
  - Another nested one
- Third item
```

- First item
- Second item
  - A nested item (indent two spaces)
  - Another nested one
- Third item

### Ordered

```markdown
1. First step
2. Second step
3. Third step — Markdown doesn't care about the actual numbers; you can
   write `1. 1. 1.` and it'll still render 1, 2, 3.
```

1. First step
2. Second step
3. Third step — Markdown doesn't care about the actual numbers; you can
   write `1. 1. 1.` and it'll still render 1, 2, 3.

### Task lists

```markdown
- [x] Done
- [x] Also done
- [ ] Still to do
- [ ] Tomorrow's problem
```

- [x] Done
- [x] Also done
- [ ] Still to do
- [ ] Tomorrow's problem

## Links

```markdown
A standard [inline link](https://example.com) to somewhere else.
Bare URLs auto-link too: https://example.com.
Internal links use the page's path: [the about page](/about/).
```

A standard [inline link](https://example.com) to somewhere else.
Bare URLs auto-link too: https://example.com.
Internal links use the page's path: [the about page](/about/).

## Images

```markdown
![Alt text — what someone would describe to a screen reader](/path/to/image.jpg)
```

In a post bundle (this folder), a colocated image just needs its filename:

```markdown
![Caption](photo.jpg)
```

Always include alt text. The audit (`bin/audit`) flags any `<img>` without
it. For decorative images that don't add information, an empty `alt=""` is
the right answer; for content images, describe what's there.

## Code

Inline code uses backticks: `` `like this` `` renders as `like this`.

For longer blocks, fence with three backticks and add a language hint for
syntax highlighting (powered by Rouge):

````markdown
```ruby
def hello(name)
  "Hello, #{name}!"
end
```
````

```ruby
def hello(name)
  "Hello, #{name}!"
end
```

Languages with built-in highlighting include `ruby`, `python`, `javascript`,
`typescript`, `go`, `rust`, `bash`, `yaml`, `json`, `html`, `css`, `sql`,
`diff`, and dozens more.

## Blockquotes

```markdown
> Markdown is "easy to read and easy to write." That's the design goal.
> If your post needs more than that, you're probably reaching for HTML.
>
> — John Gruber, paraphrased
```

> Markdown is "easy to read and easy to write." That's the design goal.
> If your post needs more than that, you're probably reaching for HTML.
>
> — John Gruber, paraphrased

## Tables

```markdown
| Tool          | Use case                  | Cost  |
| ------------- | ------------------------- | ----- |
| Markdown      | Long-form text            | Free  |
| HTML          | Anything Markdown can't   | Free  |
| Static site   | Publish the result        | Free  |
```

| Tool          | Use case                  | Cost  |
| ------------- | ------------------------- | ----- |
| Markdown      | Long-form text            | Free  |
| HTML          | Anything Markdown can't   | Free  |
| Static site   | Publish the result        | Free  |

Align columns by adding `:` to the dashes:

```markdown
| Left   | Centred  | Right   |
| :----- | :------: | ------: |
| word   | word     | word    |
```

| Left   | Centred  | Right   |
| :----- | :------: | ------: |
| word   | word     | word    |

## Footnotes

```markdown
Inline footnote reference[^1]. Then anywhere later in the document:

[^1]: The note itself. Renders at the bottom of the page with a back-link.
```

Inline footnote reference[^1]. Then anywhere later in the document:

[^1]: The note itself. Renders at the bottom of the page with a back-link.

## Horizontal rule

```markdown
---
```

Three dashes on their own line render a `<hr>`:

---

## Raw HTML

Markdown is a superset of HTML — when something doesn't have a Markdown
equivalent, just write the HTML inline. The `<mark>` example earlier was
one. Another:

```html
<details>
  <summary>Click to expand</summary>
  Hidden content goes here.
</details>
```

<details>
  <summary>Click to expand</summary>
  Hidden content goes here.
</details>

## What about HTML in the source breaking my flow?

Markdown lets you mix HTML and Markdown freely as long as the HTML is on
its own block (separated by blank lines). Inline HTML inside a paragraph
also works — the `<mark>` and the auto-linked URL above are both inline.

## Where to from here

This covers ~90% of what you'll write day to day. For the remaining 10%
(custom containers, callouts, complex layouts), HTML is the right answer
— and Markdown lets you drop it in without leaving your post.

If you came here from another platform, your old posts probably use the
same syntax. Markdown is *the* common ground across blog platforms,
README files, GitHub issues, Notion, Slack — everywhere.

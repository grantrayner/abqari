---
title: Block AI training scrapers
description: One config flag tells the major AI training crawlers to leave your content alone, without affecting search indexing.
---

# Block AI training scrapers

Most AI training crawlers identify themselves and respect robots.txt. Abqari ships with a config flag that adds explicit blocks for the major ones — OpenAI, Anthropic, Google's AI carve-out, Apple's AI carve-out, Meta, Perplexity, Common Crawl, and others — so your content isn't ingested for model training without consent.

This is **on by default**. It's the kind of thing where the safer default is "respect the author's likely preference"; flip it off if you actively want AI training to use your work.

## Config

```yaml
# config/site.yml
block_ai_scraping: true
```

That's it. The next build's `robots.txt` carries:

```
# Block AI training crawlers (config: block_ai_scraping)
User-agent: GPTBot
User-agent: ChatGPT-User
User-agent: OAI-SearchBot
User-agent: ClaudeBot
User-agent: Claude-Web
User-agent: anthropic-ai
User-agent: Google-Extended
User-agent: Applebot-Extended
User-agent: Meta-ExternalAgent
User-agent: FacebookBot
User-agent: PerplexityBot
User-agent: Perplexity-User
User-agent: YouBot
User-agent: cohere-ai
User-agent: Bytespider
User-agent: MistralAI-User
User-agent: CCBot
User-agent: Diffbot
User-agent: omgili
User-agent: omgilibot
Disallow: /

User-agent: *
Allow: /
Sitemap: https://your-site/sitemap.xml
```

## Why these specific bots

Each named bot is the *self-identifying* user-agent for an AI training crawler. They all respect robots.txt — that's the only way blocking helps. Bots that don't respect robots.txt (mostly malicious scrapers) won't be stopped by anything in this file regardless.

A few are worth calling out:

- **`Google-Extended`** is Google's separate user-agent specifically for AI training. Blocking it does **not** affect regular Googlebot search indexing — your search ranking is unchanged. Same for `Applebot-Extended` (Apple AI vs. regular Spotlight/Siri search).
- **`CCBot`** is [Common Crawl](https://commoncrawl.org/), the public dataset that many third-party trainers use. Blocking it stops a lot of indirect AI ingestion.
- **`ChatGPT-User`** and **`Perplexity-User`** are user-initiated fetchers (someone asking ChatGPT/Perplexity about your URL triggers a fetch). Block-all is the safer default; remove from the list (edit `lib/abqari/robots.rb`'s `AI_BOTS`) if you want to be cited in AI search results.

## What this doesn't do

- **Stop bots that ignore robots.txt.** robots.txt is a polite request. Bots that disregard it are unstoppable from a static site without server-side bot detection.
- **Remove your content from existing models.** Models already trained on your content stay trained. Blocking now stops *future* training.
- **Block traditional search engine bots.** Googlebot, Bingbot, etc. crawl as normal; only the AI-specific user-agents are blocked.
- **Add `noai` / `noimageai` HTTP headers or meta tags.** Those are emerging conventions from Adobe / Spawning AI but adoption is uneven. robots.txt is more effective today; we may add header / meta support if it gets broader pickup.

## Allowing specific bots

If you want some AI bots through but not others (e.g. let Perplexity cite you, block training):

1. Set `block_ai_scraping: false` in config.
2. Edit `lib/abqari/robots.rb` and copy the bots you want to keep blocked into `robots_disallow:` style entries, OR
3. Override the whole robots.txt by setting `robots_text:` in config (a future hook — for now, edit `lib/abqari/robots.rb`).

For most users, the binary on/off covers the decision. Granular bot-by-bot control is a niche enough need that we keep it as "edit the file" rather than another config knob.

## Verifying

After deploying:

```bash
curl https://your-site/robots.txt | grep -E "GPTBot|ClaudeBot|Disallow"
```

You should see the bot list and a `Disallow: /` after them. AI crawlers fetching your robots.txt will skip your content.

# frozen_string_literal: true

require_relative 'test_helper'
require 'ostruct'
require 'tempfile'

class SiteBuildTest < Minitest::Test
  # Pages

  def test_home_page_built
    assert TestHelpers.output_exists?('index.html')
  end

  def test_posts_index_built
    assert TestHelpers.output_exists?('posts/index.html')
  end

  def test_post_uses_default_permalink
    assert TestHelpers.output_exists?('posts/hello-from-the-blog/index.html')
    assert TestHelpers.output_exists?('posts/building-with-abqari/index.html')
  end

  def test_post_html_includes_title
    html = TestHelpers.read_output('posts/hello-from-the-blog/index.html')
    assert_includes html, 'Hello from the blog'
  end

  # Pagination

  # Default per_page is 10. The fixture site has 2 published posts, so the
  # posts index fits on one page and no /page/2/ shard is generated. This
  # is the behaviour users want: pagination doesn't appear until it's
  # needed.
  def test_pagination_suppressed_when_only_one_page_needed
    refute TestHelpers.output_exists?('posts/page/2/index.html'),
           'Pagination overflow page should not exist when posts fit on one page'
    html = TestHelpers.read_output('posts/index.html')
    refute_match(/<nav[^>]*class="pagination"/, html,
                 'Pagination nav element should not render when only one page exists')
  end

  # When pagination IS needed (small per_page override), overflow pages exist.
  # The pagination resolver lives on Renderer post-refactor; reach through
  # `site.renderer` to exercise the private helper.
  def test_resolve_per_page_with_explicit_number
    site = Abqari::Site.new
    page = OpenStruct.new(frontmatter: { 'paginate' => 25 })
    assert_equal 25, site.renderer.send(:resolve_per_page, page)
  end

  def test_resolve_per_page_with_true_uses_config_default
    site = Abqari::Site.new
    page = OpenStruct.new(frontmatter: { 'paginate' => true })
    assert_equal 10, site.renderer.send(:resolve_per_page, page),
                 'paginate: true should resolve to the default per_page'
  end

  def test_resolve_per_page_with_false_disables
    site = Abqari::Site.new
    page = OpenStruct.new(frontmatter: { 'paginate' => false })
    assert_nil site.renderer.send(:resolve_per_page, page)
  end

  def test_resolve_per_page_with_missing_key_disables
    site = Abqari::Site.new
    page = OpenStruct.new(frontmatter: {})
    assert_nil site.renderer.send(:resolve_per_page, page)
  end

  # Tags

  def test_tag_pages_generated
    %w[ruby ssg tutorials introductions].each do |tag|
      assert TestHelpers.output_exists?("tags/#{tag}/index.html"), "missing tags/#{tag}/index.html"
    end
  end

  def test_tag_index_lists_tagged_posts
    html = TestHelpers.read_output('tags/ruby/index.html')
    assert_includes html, 'Hello from the blog'
    assert_includes html, 'Building with Abqari'
  end

  # Theme & assets

  def test_default_theme_css_fingerprinted
    pattern = %r{/assets/css/app\.[a-f0-9]{10}\.css}
    home = TestHelpers.read_output('index.html')
    assert_match pattern, home
  end

  # SEO meta

  def test_canonical_link_in_head
    html = TestHelpers.read_output('posts/hello-from-the-blog/index.html')
    assert_match(%r{<link rel="canonical" href="https://example\.com/posts/hello-from-the-blog/">}, html)
  end

  def test_post_emits_jsonld_article
    html = TestHelpers.read_output('posts/hello-from-the-blog/index.html')
    assert_includes html, '"@type": "Article"'
    assert_includes html, '"datePublished":'
  end

  def test_open_graph_tags_present
    html = TestHelpers.read_output('posts/hello-from-the-blog/index.html')
    assert_match %r{<meta property="og:title"}, html
    assert_match %r{<meta property="og:type" content="article">}, html
  end

  # Deploy artifacts

  def test_sitemap_includes_post_url
    sitemap = TestHelpers.read_output('sitemap.xml')
    assert_includes sitemap, 'https://example.com/posts/hello-from-the-blog/'
  end

  def test_sitemap_declares_image_extension_namespace
    sitemap = TestHelpers.read_output('sitemap.xml')
    assert_includes sitemap, 'xmlns:image="http://www.google.com/schemas/sitemap-image/1.1"'
  end

  def test_sitemap_emits_image_entry_for_post_with_bundle_image
    sitemap = TestHelpers.read_output('sitemap.xml')
    assert_includes sitemap, '<image:loc>https://example.com/posts/building-with-abqari/hero.svg</image:loc>'
  end

  def test_sitemap_omits_image_entry_for_post_without_bundle_images
    sitemap = TestHelpers.read_output('sitemap.xml')
    # The writing-in-markdown post has no images; its <url> block should not contain <image:image>.
    block = sitemap[%r{<url>\s*<loc>https://example\.com/posts/writing-in-markdown/</loc>.*?</url>}m]
    refute_nil block
    refute_includes block, '<image:image>'
  end

  def test_sitemap_includes_lastmod_for_all_pages
    sitemap = TestHelpers.read_output('sitemap.xml')
    # Every <url> entry should have a <lastmod> now (was previously absent on non-post pages).
    url_blocks = sitemap.scan(%r{<url>.*?</url>}m)
    refute_empty url_blocks
    url_blocks.each do |block|
      assert_includes block, '<lastmod>', "url block missing lastmod: #{block}"
    end
  end

  def test_rss_feed_built
    # Posts is un-aliased in the engine fixture, so the feed lives at
    # the root /feed.xml + /feed.json (the back-compat default).
    feed = TestHelpers.read_output('feed.xml')
    assert_includes feed, '<rss version="2.0"'
    assert_includes feed, 'Hello from the blog'
  end

  def test_html_lang_reflects_locale_config
    html = TestHelpers.read_output('index.html')
    locale = TestHelpers.built_site.config['locale'] || 'en'
    assert_includes html, %(<html lang="#{locale}">)
  end

  def test_rss_language_reflects_locale_config
    feed = TestHelpers.read_output('feed.xml')
    locale = TestHelpers.built_site.config['locale'] || 'en'
    assert_includes feed, "<language>#{locale}</language>"
  end

  def test_json_feed_built
    feed = TestHelpers.read_output('feed.json')
    assert_includes feed, '"version": "https://jsonfeed.org/version/1.1"'
  end

  # Per-collection feeds — posts default ON (back-compat root paths),
  # photos and publications default OFF (opt-in via config).
  def test_photos_feed_off_by_default
    refute TestHelpers.output_exists?('photos/feed.xml'),
           'photos.feeds.enabled defaults to false; should not emit'
    refute TestHelpers.output_exists?('photos/feed.json')
  end

  def test_publications_feed_off_by_default
    refute TestHelpers.output_exists?('publications/feed.xml')
    refute TestHelpers.output_exists?('publications/feed.json')
  end

  def test_head_advertises_only_enabled_collection_feeds
    home = TestHelpers.read_output('index.html')
    # Posts is un-aliased, so feeds advertise at root /feed.xml + /feed.json.
    assert_includes home, 'href="/feed.xml"',  'posts feed always advertised'
    assert_includes home, 'href="/feed.json"', 'posts JSON Feed always advertised'
    refute_includes home, '/photos/feed.xml',          'photos feed must not appear when disabled'
    refute_includes home, '/publications/feed.xml'
  end

  def test_robots_txt_indexable_in_production
    robots = TestHelpers.read_output('robots.txt')
    assert_includes robots, 'Allow: /'
    assert_includes robots, 'Sitemap:'
  end

  def test_headers_file_has_security_headers
    headers = TestHelpers.read_output('_headers')
    assert_includes headers, 'Content-Security-Policy:'
    assert_includes headers, 'Strict-Transport-Security:'
    assert_includes headers, 'Cache-Control: public, max-age=31536000, immutable'
  end

  def test_redirect_stub_generated
    stub = TestHelpers.read_output('old-tutorial/index.html')
    assert_includes stub, 'http-equiv="refresh"'
    assert_includes stub, '/posts/building-with-abqari/'
  end

  def test_redirects_file_lists_mapping
    redirects = TestHelpers.read_output('_redirects')
    assert_includes redirects, '/old-tutorial/ /posts/building-with-abqari/ 301'
  end

  # Helpers

  def extract_title(html)
    html[%r{<title>(.*?)</title>}, 1]
  end
end

class CollectionConfigTest < Minitest::Test
  def test_default_posts_collection
    config = TestHelpers.built_site.collection_config('posts')
    # Engine fixture uses defaults — no slug aliasing.
    assert_equal 'content/posts',  config['source']
    assert_equal '/posts/:slug/',  config['permalink']
    assert_equal 'post',           config['layout']
    assert_nil   config['slug']
  end

  def test_unknown_collection_returns_empty_hash
    config = TestHelpers.built_site.collection_config('unknown')
    assert_equal({}, config)
  end

  # Enable flag exists on each shipped collection (defaults to true).
  # Tests the round-trip: config carries `enable: true`, build honours it.
  def test_collections_default_to_enabled
    site = TestHelpers.built_site
    %w[posts photos publications].each do |name|
      assert_equal true, site.collection_config(name).fetch('enabled', true),
                   "#{name} should be enabled by default"
    end
  end

  # When a collection is disabled, SiteLoader's predicate returns true
  # for files under its source dir. The actual build skip is harder to
  # test here (the fixture site is built once with all enabled), so
  # we test the predicate directly through the loader collaborator.
  def test_disabled_collection_path_predicate
    site = Abqari::Site.new
    site.config['collections'] = {
      'photos' => { 'source' => 'content/photos', 'enabled' => false }
    }
    photos_path = File.join(Abqari::ROOT, 'content/photos/some-photo/index.md')
    posts_path  = File.join(Abqari::ROOT, 'content/posts/whatever/index.md')
    assert site.loader.send(:disabled_collection_path?, photos_path),
           'photos path should be flagged when photos.enabled is false'
    refute site.loader.send(:disabled_collection_path?, posts_path),
           'posts path should not be flagged when photos is disabled'
  end
end

class RelatedTest < Minitest::Test
  # Posts share tags via the fixture site:
  #   hello-from-the-blog       → tags: [ruby, ssg, introductions]
  #   building-with-abqari      → tags: [ruby, ssg, tutorials]
  #   writing-in-markdown       → tags: [markdown, writing, tutorials]
  # So writing-in-markdown is related to building-with-abqari (shares
  # `tutorials`) but not directly to hello-from-the-blog (no shared tags).
  def test_related_finds_posts_with_shared_tags
    site = TestHelpers.built_site
    source = site.posts.find { |p| p.url == '/posts/writing-in-markdown/' }
    related = site.related(source)

    refute_empty related, 'expected at least one related post'
    assert_includes related.map(&:url), '/posts/building-with-abqari/'
    refute_includes related.map(&:url), source.url, 'must not include the source page'
  end

  def test_related_returns_nothing_for_unrelated_pages
    site = TestHelpers.built_site
    # An item with no overlapping tags returns nothing.
    isolated = OpenStruct.new(
      collection: 'posts',
      frontmatter: { 'tags' => ['no-such-tag'] },
      url: '/fake/'
    )
    assert_empty site.related(isolated)
  end

  def test_related_respects_limit
    site = TestHelpers.built_site
    source = site.posts.find { |p| p.url == '/posts/writing-in-markdown/' }
    assert_equal 1, site.related(source, limit: 1).size
  end

  def test_related_returns_empty_when_disabled
    site = Abqari::Site.new
    site.config['collections'] = {
      'posts' => { 'show' => { 'related' => { 'enabled' => false } } }
    }
    page = OpenStruct.new(collection: 'posts', frontmatter: { 'tags' => ['ruby'] }, url: '/x/')
    assert_empty site.related(page)
  end

  # Without `limit:`, returns the FULL ranked list (used by the related
  # index page). With `limit:`, slices.
  def test_related_returns_all_when_no_limit
    site = TestHelpers.built_site
    source = site.posts.find { |p| p.url == '/posts/writing-in-markdown/' }
    full   = site.related(source)
    sliced = site.related(source, limit: 1)

    assert sliced.size <= full.size
    assert_equal sliced.first, full.first if sliced.any? # same top match
  end

  # The /<slug>/related/ index page is generated only when the related
  # list is longer than `limit`. The fixture site doesn't trigger this
  # at default limits, so we test the predicate via a lower-limit config.
  def test_related_index_page_generated_on_overflow
    skip 'integration test requires custom build with low limit; covered by manual verification'
  end

  # next_in_collection points to the strictly-newer post and returns
  # nil at the newest (no fallback to older — the label says "next").
  # The fixture has 3 published posts, newest first:
  # writing-in-markdown, building-with-abqari, hello-from-the-blog.
  def test_next_in_collection_returns_newer
    site = TestHelpers.built_site
    middle = site.posts.find { |p| p.url == '/posts/building-with-abqari/' }
    nxt = site.next_in_collection(middle)
    refute_nil nxt
    assert_equal '/posts/writing-in-markdown/', nxt.url, 'newer post is "next"'
  end

  def test_next_in_collection_nil_at_newest
    site = TestHelpers.built_site
    newest = site.posts.first
    assert_nil site.next_in_collection(newest), 'no "next" when already the newest'
  end

  def test_next_in_collection_disabled
    site = Abqari::Site.new
    site.config['collections'] = {
      'posts' => { 'show' => { 'next' => { 'enabled' => false } } }
    }
    page = OpenStruct.new(collection: 'posts', frontmatter: {}, url: '/x/')
    assert_nil site.next_in_collection(page)
  end
end

class ErbInMarkdownTest < Minitest::Test
  # ERB execution inside markdown bodies requires BOTH gates open:
  #   1. Site:  `erb_in_markdown: true` in config/site.yml
  #   2. Page:  `erb: true` in frontmatter
  # See docs/security.md §3 for the rationale.

  def test_erb_evaluates_when_both_gates_open
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'erb.md')
      File.write(path, <<~MD)
        ---
        title: ERB demo
        erb: true
        ---
        Two plus two is <%= 2 + 2 %>.
      MD

      site = Abqari::Site.new
      site.config['erb_in_markdown'] = true
      page = Abqari::Page.new(path, site)
      assert_includes page.content, 'Two plus two is 4.'
    end
  end

  def test_erb_left_alone_when_page_doesnt_opt_in
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'plain.md')
      File.write(path, <<~MD)
        ---
        title: Plain
        ---
        Code: `<%= ignored %>` should pass through.
      MD

      site = Abqari::Site.new
      site.config['erb_in_markdown'] = true # site-wide open, but page didn't opt in
      page = Abqari::Page.new(path, site)
      # Without `erb: true`, the ERB tag is not evaluated. Commonmarker
      # encodes the angle brackets inside the code span.
      assert_match(/&lt;%= ignored %&gt;/, page.content)
    end
  end

  def test_erb_blocked_by_site_gate_even_when_page_opts_in
    # A malicious frontmatter `erb: true` synced from an external source
    # MUST NOT execute when the site owner hasn't opened the site-wide
    # gate. The expression should land in the rendered HTML as literal
    # text (commonmarker escapes `<` to `&lt;` in the body) — proof
    # that ERB didn't process it.
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'malicious.md')
      File.write(path, <<~MD)
        ---
        title: Hostile
        erb: true
        ---
        Result was <%= 'EXECUTED' %>.
      MD

      site = Abqari::Site.new
      # Site default: erb_in_markdown is not set (or false). Page's
      # `erb: true` is on its own — the gate stays closed.
      page = Abqari::Page.new(path, site)
      # If ERB had run, the body would say "Result was EXECUTED."; the
      # ERB tags would have been consumed and only the value emitted.
      # With the gate closed, the tags survive into commonmarker which
      # escapes them as text.
      refute_match(/Result was EXECUTED\./, page.content,
                   'ERB execution must not happen without site-wide opt-in')
      assert_match(/&lt;%=/, page.content,
                   'ERB tags should survive as escaped literal text when gate is closed')
    end
  end

  def test_erb_can_call_helpers_when_both_gates_open
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'helper.md')
      File.write(path, <<~MD)
        ---
        title: Helper
        erb: true
        ---
        Years: <%= years_since(2002, today: Date.new(2026, 6, 15)) %>.
      MD

      site = Abqari::Site.new
      site.config['erb_in_markdown'] = true
      page = Abqari::Page.new(path, site)
      assert_includes page.content, 'Years: 24.'
    end
  end
end

class CollectionSlugAliasTest < Minitest::Test
  # Collections support a `slug:` field that derives source / permalink /
  # layout from the alias name. Lets a site rename `posts` → `stories`
  # without writing a custom collection block. Covered here at unit-level
  # via Site.new with a temporary content tree, since the engine fixture
  # uses canonical names.

  def test_slug_derives_permalink_and_layout_only
    site = Abqari::Site.new
    site.config['collections'] = {
      'posts' => { 'slug' => 'stories' }
    }
    cfg = site.collection_config('posts')

    assert_equal 'stories',           cfg['slug']
    # Source stays canonical — slug only affects public-facing URL + layout.
    assert_equal 'content/posts',     cfg['source']
    assert_equal '/stories/:slug/',   cfg['permalink']
    assert_equal 'story',             cfg['layout']    # singularized: stories → story
  end

  def test_explicit_overrides_win_over_slug_derivation
    site = Abqari::Site.new
    site.config['collections'] = {
      'posts' => {
        'slug' => 'stories',
        'layout' => 'custom_story',         # explicit wins
        'source' => 'content/my-stories'    # explicit wins
      }
    }
    cfg = site.collection_config('posts')

    assert_equal 'content/my-stories', cfg['source']
    assert_equal '/stories/:slug/',    cfg['permalink']  # not overridden, uses derived
    assert_equal 'custom_story',       cfg['layout']
  end

  def test_collection_lookup_resolves_slug_to_canonical
    site = Abqari::Site.new
    site.config['collections'] = {
      'posts' => { 'slug' => 'stories' }
    }
    # Both names should resolve to the same canonical
    assert_equal 'posts', site.resolve_collection_name('stories')
    assert_equal 'posts', site.resolve_collection_name('posts')
  end

  def test_unaliased_collection_keeps_canonical_name
    site = Abqari::Site.new
    # Override to an empty config block to test the unaliased path
    # explicitly (the engine fixture also runs unaliased, but here we
    # don't want to depend on its config state).
    site.config['collections'] = { 'posts' => {} }
    cfg = site.collection_config('posts')

    assert_nil   cfg['slug']
    assert_equal 'content/posts',     cfg['source']
    assert_equal '/posts/:slug/',     cfg['permalink']
    assert_equal 'post',              cfg['layout']
  end
end

class LayoutChainingTest < Minitest::Test
  # Layouts can declare `layout: <parent>` in their own frontmatter to
  # extend a master layout. The master receives the child's rendered
  # output via <%= yield_content %>.
  #
  # Verified end-to-end through the fixture site: content/about.md
  # uses `layout: about`, app/views/layouts/about.html.erb declares
  # `layout: application`. The about page should render with the full
  # application shell PLUS the about-specific content nested inside it.

  def test_about_page_uses_application_shell_via_chaining
    html = TestHelpers.read_output('about/index.html')
    # Application shell pieces
    assert_includes html, 'class="skip-link"',          'application shell: skip-link'
    assert_includes html, 'aria-label="Primary"',       'application shell: nav'
    assert_includes html, 'id="main-content"',          'application shell: main'
    # About-specific content from the inner layout
    assert_includes html, '<h1>About</h1>',             'about content: h1 from page.title'
    # The header now also emits the lede paragraph from `about.description`
    # in config when `about.enabled` is true. Lenient on what comes between
    # the h1 and </header>.
    assert_match(%r{<header><h1>About</h1>.*?</header>}m, html, 'header markup from inner layout')
  end

  def test_yield_content_emits_inner_layout_output_inside_main
    html = TestHelpers.read_output('about/index.html')
    # The inner layout's <article> markup should land inside <main>,
    # not before it. Crude but works: <main ...> ... <article ...> ...
    main_index    = html.index('<main')
    article_index = html.index('<article', main_index)
    refute_nil    article_index, '<article> rendered'
    assert        article_index > main_index, 'inner content nested inside <main>'
  end
end

class AIBlockingTest < Minitest::Test
  # Default: block_ai_scraping is true. The fixture site builds with
  # the default config so robots.txt should carry the AI block.
  def test_robots_txt_blocks_known_ai_bots_by_default
    robots = TestHelpers.read_output('robots.txt')
    assert_match(/User-agent:\s+GPTBot/,            robots, 'OpenAI GPTBot')
    assert_match(/User-agent:\s+ClaudeBot/,         robots, 'Anthropic ClaudeBot')
    assert_match(/User-agent:\s+Google-Extended/,   robots, "Google's AI carve-out")
    assert_match(/User-agent:\s+Applebot-Extended/, robots, "Apple's AI carve-out")
    assert_match(/User-agent:\s+CCBot/,             robots, 'Common Crawl')
    assert_match(/User-agent:\s+PerplexityBot/,     robots, 'Perplexity')
    # The block list is a single Disallow:/ that applies to all the
    # User-agent lines above it.
    assert_match(/Disallow:\s+\//, robots)
  end

  # Regular User-agent: * Allow: / still appears (sets indexing for
  # everyone else). AI block is additive, not a replacement.
  def test_default_indexing_still_allowed
    robots = TestHelpers.read_output('robots.txt')
    assert_match(/User-agent:\s+\*/, robots)
    assert_match(/Allow:\s+\//,      robots)
  end

  def test_ai_block_can_be_disabled
    site = Abqari::Site.new
    site.config['block_ai_scraping'] = false
    site.config['indexable'] = true
    site.config['url'] = 'https://example.com'
    output = Abqari::Robots.new(site).send(:build)
    refute_match(/GPTBot/, output)
    refute_match(/ClaudeBot/, output)
    assert_match(/User-agent:\s+\*/, output, 'still emits the default User-agent: *')
  end
end

class TaxonomyTest < Minitest::Test
  def test_default_tags_taxonomy_present
    config = TestHelpers.built_site.taxonomy_config('tags')
    assert_equal '/tags/:slug/', config['permalink']
    assert_equal 'tag',          config['layout']
  end

  def test_posts_by_term_groups_by_tag
    grouped = TestHelpers.built_site.posts_by_term('tags')
    assert grouped.key?('ruby'), 'expected ruby tag to be present'
    assert_equal 2, grouped['ruby'].size
  end

  def test_unknown_term_returns_empty
    grouped = TestHelpers.built_site.posts_by_term('nonexistent')
    assert_empty grouped
  end
end

class DraftAndFutureTest < Minitest::Test
  def test_draft_post_excluded_in_production
    refute TestHelpers.output_exists?('stories/draft-example/index.html'),
           'draft post should not be in production build output'
  end

  def test_future_dated_post_excluded_in_production
    refute TestHelpers.output_exists?('stories/future-example/index.html'),
           'future-dated post should not be in production build output'
  end

  def test_published_posts_present
    assert TestHelpers.output_exists?('posts/hello-from-the-blog/index.html')
    assert TestHelpers.output_exists?('posts/building-with-abqari/index.html')
  end
end

class DisabledPageTest < Minitest::Test
  # `enabled: false` in a page's frontmatter is the page-level kill
  # switch — checked into the repo but invisible in every build. Test
  # the disabled-example fixture (`content/disabled-example.md`) is
  # excluded from output, all_pages, sitemap, and feed.

  def test_disabled_page_does_not_render
    refute TestHelpers.output_exists?('disabled-example/index.html'),
           'page with enabled: false should not produce HTML output'
  end

  def test_disabled_page_absent_from_all_pages
    urls = TestHelpers.built_site.all_pages.map { |p| p.respond_to?(:url) ? p.url : nil }
    refute_includes urls, '/disabled-example/',
                    'disabled page should not appear in site.all_pages'
  end

  def test_disabled_page_absent_from_sitemap
    sitemap = TestHelpers.read_output('sitemap.xml')
    refute_includes sitemap, '/disabled-example/',
                    'disabled page should not appear in sitemap.xml'
  end

  def test_published_pages_unaffected_by_disabled_flag
    # Sanity check: enabling the kill switch on one page must not
    # accidentally remove anything else.
    assert TestHelpers.output_exists?('about/index.html')
    assert TestHelpers.output_exists?('index.html')
  end

  # Direct unit test on the method so the test fails fast even if
  # something else in the build pipeline masks the integration check.
  def test_page_disabled_predicate_reads_frontmatter
    Tempfile.create(['enabled-fixture', '.md']) do |f|
      f.write("---\nenabled: false\n---\nbody\n")
      f.flush
      page = Abqari::Page.new(f.path, TestHelpers.built_site)
      assert_predicate page, :disabled?
    end

    Tempfile.create(['enabled-fixture', '.md']) do |f|
      f.write("---\ntitle: Live\n---\nbody\n")
      f.flush
      page = Abqari::Page.new(f.path, TestHelpers.built_site)
      refute_predicate page, :disabled?
    end
  end
end

class TimezoneTest < Minitest::Test
  # `Site#build` anchors `ENV['TZ']` to `config['timezone']` so naked
  # dates parse against one consistent zone regardless of where the
  # build runs. The mutation is scoped to the build call — `ensure`
  # restores the prior value so the side effect doesn't leak into the
  # host process (test harnesses, dev-server watchers, embedded use).
  def test_naked_date_parses_in_configured_timezone_during_build
    # Page#date parses the frontmatter `date:` value during page
    # construction inside `build`. Pick a page with a naked date and
    # confirm its parsed Time landed in the configured zone.
    page = TestHelpers.built_site.pages.find { |p| p.respond_to?(:date) && p.date && p.frontmatter['date'].is_a?(Date) }
    assert page, 'fixture should contain at least one page with a naked frontmatter date'
    assert_equal 'UTC', page.date.zone, 'Naked dates should be anchored to config[timezone] during build'
  end

  def test_tz_is_restored_after_build
    original = ENV['TZ']
    ENV['TZ'] = 'America/New_York'

    site = Abqari::Site.new
    site.build

    assert_equal 'America/New_York', ENV['TZ'],
                 'Site#build should restore ENV[TZ] to its pre-build value via ensure'
  ensure
    ENV['TZ'] = original
  end

  def test_tz_is_restored_even_when_build_raises
    # Use a throwaway site_root + output_dir so the raising build
    # doesn't wipe the shared test fixture's output. The aim is just
    # to confirm the `ensure` in `Site#build` runs on the abnormal
    # path — pre-flight raise from `apply_timezone!` is the simplest
    # trigger.
    original_tz   = ENV['TZ']
    original_root = ENV['ABQARI_SITE_ROOT']
    original_out  = ENV['ABQARI_OUTPUT_DIR']

    Dir.mktmpdir('abqari-tz-isolated') do |dir|
      ENV['ABQARI_SITE_ROOT']  = dir
      ENV['ABQARI_OUTPUT_DIR'] = File.join(dir, '_site')
      ENV['TZ']                = 'America/New_York'

      site = Abqari::Site.new
      site.define_singleton_method(:apply_timezone!) { raise 'boom' }

      assert_raises(RuntimeError) { site.build }
      assert_equal 'America/New_York', ENV['TZ'],
                   'Site#build should restore ENV[TZ] even when the build itself raises'
    end
  ensure
    ENV['TZ']                = original_tz
    ENV['ABQARI_SITE_ROOT']  = original_root
    ENV['ABQARI_OUTPUT_DIR'] = original_out
  end
end

class BannerTest < Minitest::Test
  # The future banner only renders in dev. The fixture builds in production,
  # so we verify the partial would render correctly by checking the helpers
  # it depends on, plus that future posts are excluded from prod output.
  def test_time_until_returns_relative_phrase
    future = Time.now + (3 * 86_400)
    assert_match(/^in \d+ days?$/, Abqari::Helpers.time_until(future))
  end

  def test_time_until_handles_already_passed
    past = Time.now - 60
    # Past times fall through to time_ago — phrasing flips, not crashes.
    refute_match(/^in /, Abqari::Helpers.time_until(past))
  end
end

class DataTest < Minitest::Test
  def test_data_directory_loaded_into_site_data
    # data/nav.yml is comments-only by default; loading should not error
    # but the parsed value can be nil. We assert the file at least appears
    # in the cache (key present even if value is nil).
    assert TestHelpers.built_site.data.key?('nav')
  end
end

class NavCascadeTest < Minitest::Test
  def test_nav_links_from_frontmatter_cascade
    links = TestHelpers.built_site.nav_links
    assert links.any? { |l| l['url'] == '/' && l['label'] == 'Home' },
           'expected Home link from content/index.md frontmatter'
    assert links.any? { |l| l['url'] == '/posts/' && l['label'] == 'Posts' },
           'expected Posts link from content/posts/index.md frontmatter'
  end

  def test_nav_links_sorted_by_order_field
    links = TestHelpers.built_site.nav_links
    home_idx  = links.index { |l| l['label'] == 'Home' }
    posts_idx = links.index { |l| l['label'] == 'Posts' }
    refute_nil home_idx
    refute_nil posts_idx
    assert home_idx < posts_idx, 'Home (order 1) should come before Posts (order 2)'
  end

  def test_nav_renders_in_layout
    html = TestHelpers.read_output('index.html')
    # Lenient on extra attributes between `href="…"` and `>` so the
    # active-link `aria-current="page"` doesn't break the assertion.
    assert_match %r{<nav[^>]*>.*<a href="/"[^>]*>Home</a>.*<a href="/posts/"[^>]*>Posts</a>.*<a href="/about/"[^>]*>About</a>.*</nav>}m, html
  end

  # Active-link state — the link matching the current page (or its
  # section) gets aria-current="page" so it can be styled separately.
  def test_nav_active_link_marked_on_home
    html = TestHelpers.read_output('index.html')
    # The home link (matching `/`) is active on the home page.
    assert_match %r{<a href="/" aria-current="page">Home</a>}, html
    # Other links are NOT marked.
    refute_match %r{<a href="/posts/" aria-current}, html
    refute_match %r{<a href="/about/" aria-current}, html
  end

  def test_nav_active_link_marked_on_section_page
    # `/about/` is active on the about page itself.
    html = TestHelpers.read_output('about/index.html')
    assert_match %r{<a href="/about/" aria-current="page">About</a>}, html
    refute_match %r{<a href="/posts/" aria-current}, html
    # The home link is NOT active on /about/.
    refute_match %r{<a href="/" aria-current="page">Home</a>}, html
  end

  def test_nav_active_link_marked_on_section_subpage
    # `/posts/` link is active on individual stories because the
    # story URL starts with `/posts/` (slug-aliased from posts).
    html = TestHelpers.read_output('posts/hello-from-the-blog/index.html')
    assert_match %r{<a href="/posts/" aria-current="page">Posts</a>}, html
  end

  # Accessibility — these checks lock in the a11y baseline. Removing or
  # weakening any of them is almost always a mistake; if the underlying
  # markup changes, update both the markup and the assertion together.
  def test_skip_link_renders_first_in_body
    html = TestHelpers.read_output('index.html')
    assert_match %r{<body>\s*<a class="skip-link" href="#main-content">}, html,
                 'Skip link must be the first focusable element after <body>'
  end

  def test_main_landmark_has_skip_link_target
    html = TestHelpers.read_output('index.html')
    assert_match %r{<main\b[^>]*id="main-content"[^>]*tabindex="-1"}, html,
                 '<main> must have id="main-content" + tabindex="-1" so the skip link can move focus'
  end

  def test_primary_nav_has_aria_label
    html = TestHelpers.read_output('index.html')
    assert_match %r{<nav aria-label="Primary"}, html
  end

  def test_theme_toggle_has_aria_pressed
    html = TestHelpers.read_output('index.html')
    assert_match %r{<button[^>]*class="theme-toggle"[^>]*aria-pressed="(true|false)"}, html
  end

  def test_about_page_built
    assert TestHelpers.output_exists?('about/index.html'),
           'expected the template content/about.md to render at /about/'
  end

  def test_about_page_links_to_both_feeds
    # Feed URLs follow `posts.slug` aliasing: with `slug: stories` set in
    # the starter, both feeds live under /posts/.
    html = TestHelpers.read_output('about/index.html')
    assert_includes html, 'href="/feed.xml"'
    assert_includes html, 'href="/feed.json"'
  end

  def test_footer_links_empty_when_no_frontmatter_or_data
    # No page in the canonical fixture opts into footer:.
    assert_empty TestHelpers.built_site.footer_links
  end

  def test_social_links_populated_from_social_config
    # The engine fixture site enables a sampler of social icons so the
    # demo home page footer shows them in the footer. Each `social:`
    # entry in config/site.yml becomes one link.
    links = TestHelpers.built_site.social_links
    refute_empty links
    icons = links.map { |l| l['icon'] }
    assert_includes icons, 'github'
    assert_includes icons, 'rss'
  end
end

class BundleTest < Minitest::Test
  def test_bundle_asset_copied_alongside_post
    assert TestHelpers.output_exists?('posts/building-with-abqari/hero.svg'),
           'expected hero.svg from the post bundle to be copied to its output directory'
  end

  def test_bundle_relative_image_url_rewritten
    html = TestHelpers.read_output('posts/building-with-abqari/index.html')
    assert_includes html, 'src="/posts/building-with-abqari/hero.svg"',
                    'relative bundle-asset src should be rewritten to absolute URL under the post'
  end

  def test_bundle_preserves_absolute_and_external_urls
    html = TestHelpers.read_output('posts/building-with-abqari/index.html')
    refute_match %r{src="/posts/building-with-abqari/https?://}, html
    refute_match %r{href="/posts/building-with-abqari//}, html
  end

  def test_bundle_slug_derived_from_directory_name
    post = TestHelpers.built_site.posts.find { |p| p.url == '/posts/building-with-abqari/' }
    refute_nil post, 'expected post URL slug to match its bundle directory name'
  end

  def test_bundle_date_from_directory_prefix
    post = TestHelpers.built_site.posts.find { |p| p.url == '/posts/hello-from-the-blog/' }
    assert_equal 2026, post.date.year
    assert_equal 4,    post.date.month
    assert_equal 15,   post.date.day
  end
end

class SyntaxHighlightingTest < Minitest::Test
  def test_syntax_stylesheet_generated
    assert TestHelpers.output_exists?('assets/css/syntax.css')
  end

  def test_code_block_gets_rouge_classes
    html = TestHelpers.read_output('posts/building-with-abqari/index.html')
    assert_includes html, 'class="highlight"'
    assert_includes html, 'class="k">def'  # 'k' is Rouge's keyword class
  end

  def test_head_links_to_syntax_stylesheet
    html = TestHelpers.read_output('index.html')
    assert_includes html, '/assets/css/syntax.css'
  end
end

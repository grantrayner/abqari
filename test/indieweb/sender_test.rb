# frozen_string_literal: true

require_relative '../test_helper'
require 'tmpdir'
require 'yaml'

# Sender — outbound webmention dispatcher. Tests cover:
#   * enable/disable gating
#   * the outbound-link extractor (no in-domain noise; deduplication)
#   * the recency window
#   * sent-log idempotency (re-runs don't double-post)
#
# Network plumbing (HEAD/GET endpoint discovery + POST notification) is
# stubbed at the Net::HTTP layer so these tests run offline.
class IndiewebSenderTest < Minitest::Test
  Sender = Abqari::Indieweb::Sender

  StubPost = Struct.new(:url, :content, :date, :frontmatter, keyword_init: true) do
    def respond_to?(m, *)
      %i[url content date frontmatter].include?(m) || super
    end
  end

  def setup
    @site_root = Dir.mktmpdir('abqari-iw-sender-test-')
    @posts = []
    @site = Struct.new(:config, :data, :site_root, :env, :posts).new(
      {
        'url' => 'https://example.com',
        'indieweb' => { 'enabled' => true, 'domain' => 'example.com',
                        'send_webmentions' => true, 'send_window_days' => 30 }
      },
      {},
      @site_root,
      :production,
      @posts
    )
  end

  def teardown
    FileUtils.rm_rf(@site_root)
  end

  def add_post(slug:, content:, date: Date.today)
    @posts << StubPost.new(
      url: "/posts/#{slug}/",
      content: content,
      date: date,
      frontmatter: {}
    )
  end

  def sent_log
    YAML.safe_load_file(File.join(@site_root, 'vendor', 'webmentions', 'sent.yml'),
                        permitted_classes: Abqari::YAML_PERMITTED_CLASSES) || {}
  end

  def test_disabled_when_send_webmentions_false
    @site.config['indieweb']['send_webmentions'] = false
    add_post(slug: 'a', content: 'See https://other.example/post.')
    sender = Sender.new(@site)
    refute sender.enabled?
    sender.send_all # no-op
    refute File.exist?(sender.log_path)
  end

  def test_extracts_only_external_http_urls
    add_post(slug: 'a', content: <<~MD)
      Internal link: https://example.com/posts/other/ — ignored.
      External: https://external.com/page (kept).
      Inline: visit https://another.example/path? for more.
      Repeated: https://external.com/page (deduped).
    MD
    sender = Sender.new(@site)
    targets = sender.send(:outbound_targets_for, @posts.first)
    assert_includes targets, 'https://external.com/page'
    assert_includes targets, 'https://another.example/path?'
    refute_includes targets, 'https://example.com/posts/other/'
    assert_equal targets.size, targets.uniq.size, 'dedup outbound URLs'
  end

  def test_skips_posts_outside_send_window
    add_post(slug: 'old', content: 'https://other.example/x', date: Date.today - 365)
    add_post(slug: 'new', content: 'https://other.example/y', date: Date.today - 5)

    sender = Sender.new(@site)
    recent = sender.send(:recent_posts, Date.today - sender.send(:send_window_days))
    slugs = recent.map { |p| p.url[%r{/posts/(\w+)/}, 1] }
    assert_includes slugs, 'new'
    refute_includes slugs, 'old'
  end

  def test_does_not_resend_logged_entries
    add_post(slug: 'a', content: 'See https://other.example/post.')

    sender = Sender.new(@site)
    # Pre-seed the sent log so any send attempt would be a no-op.
    FileUtils.mkdir_p(File.dirname(sender.log_path))
    File.write(sender.log_path, YAML.dump('sent' => {
      'https://example.com/posts/a/|https://other.example/post' => { 'status' => 'sent', 'at' => Time.now.utc.iso8601 }
    }))

    # Stub discover_endpoint to ensure the post-notification path is not entered.
    called = false
    sender.singleton_class.send(:define_method, :discover_endpoint) do |_|
      called = true; nil
    end

    sender.send_all
    refute called, 'should not attempt endpoint discovery for already-logged target'
  end

  def test_log_records_no_endpoint_when_discovery_fails
    add_post(slug: 'a', content: 'See https://other.example/post.')
    sender = Sender.new(@site)
    sender.singleton_class.send(:define_method, :discover_endpoint) { |_| nil }

    sender.send_all
    log = sent_log
    key = 'https://example.com/posts/a/|https://other.example/post'
    assert_equal 'no-endpoint', log['sent'][key]['status']
  end
end

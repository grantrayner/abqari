# frozen_string_literal: true

require_relative '../test_helper'
require 'tmpdir'
require 'yaml'

# Dispatcher — orchestration: window filtering, per-post `syndicate:
# false` opt-out, sent-log idempotency, fan-out to configured networks.
#
# Networks are stubbed with a fake adapter that records every `post`
# call so the test can assert exactly which (post, network) pairs got
# dispatched.
class SyndicationDispatcherTest < Minitest::Test
  Dispatcher = Abqari::Syndication::Dispatcher

  StubPost = Struct.new(:url, :title, :frontmatter, :date, keyword_init: true) do
    def respond_to?(m, *)
      %i[url title frontmatter date].include?(m) || super
    end
  end

  # FakeNetwork sits where Mastodon/Bluesky would, captures every
  # `post` call, and returns a deterministic "syndicated_url".
  class FakeNetwork
    attr_reader :calls, :name

    def initialize(name:, returns: ->(url) { "https://fake.example/syndicated/#{url.split('/').last}" })
      @name    = name
      @calls   = []
      @returns = returns
    end

    def configured?
      true
    end

    def post(text:, url:)
      @calls << { text: text, url: url }
      @returns.call(url)
    end
  end

  def setup
    @site_root = Dir.mktmpdir('abqari-synd-test-')
    @posts = []
    @site = Struct.new(:config, :data, :site_root, :env, :posts).new(
      {
        'url' => 'https://example.com',
        'syndication' => { 'enabled' => true, 'window_days' => 14 }
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

  def add_post(slug:, date: Date.today, syndicate: nil)
    fm = { 'description' => "Description for #{slug}" }
    fm['syndicate'] = syndicate unless syndicate.nil?
    @posts << StubPost.new(url: "/posts/#{slug}/", title: "Post #{slug}",
                            frontmatter: fm, date: date)
  end

  def dispatcher_with(networks)
    d = Dispatcher.new(@site)
    d.instance_variable_set(:@networks, networks)
    d
  end

  def sent_log
    log_path = File.join(@site_root, 'vendor', 'syndication', 'sent.yml')
    return {} unless File.exist?(log_path)
    YAML.safe_load_file(log_path, permitted_classes: Abqari::YAML_PERMITTED_CLASSES) || {}
  end

  def test_disabled_when_syndication_enabled_false
    @site.config['syndication']['enabled'] = false
    add_post(slug: 'a')
    net = FakeNetwork.new(name: 'mastodon')
    dispatcher_with([net]).run
    assert_empty net.calls
  end

  def test_runs_each_configured_network_for_each_recent_post
    add_post(slug: 'a')
    add_post(slug: 'b')
    masto = FakeNetwork.new(name: 'mastodon')
    bsky  = FakeNetwork.new(name: 'bluesky')
    dispatcher_with([masto, bsky]).run

    assert_equal 2, masto.calls.size
    assert_equal 2, bsky.calls.size
  end

  def test_skips_posts_outside_window
    add_post(slug: 'old', date: Date.today - 90)
    add_post(slug: 'new', date: Date.today - 1)
    net = FakeNetwork.new(name: 'mastodon')
    dispatcher_with([net]).run
    urls = net.calls.map { |c| c[:url] }
    assert urls.any? { |u| u.include?('/posts/new/') }, 'recent post should be syndicated'
    refute urls.any? { |u| u.include?('/posts/old/') }, 'old post must not be syndicated'
  end

  def test_honors_per_post_syndicate_false_opt_out
    add_post(slug: 'public')
    add_post(slug: 'private', syndicate: false)
    net = FakeNetwork.new(name: 'mastodon')
    dispatcher_with([net]).run
    urls = net.calls.map { |c| c[:url] }
    assert urls.any? { |u| u.include?('/posts/public/') }
    refute urls.any? { |u| u.include?('/posts/private/') }
  end

  def test_logs_successful_posts_and_does_not_repost_on_rerun
    add_post(slug: 'a')
    net1 = FakeNetwork.new(name: 'mastodon')
    dispatcher_with([net1]).run

    # First run posted; sent log records it.
    key = 'mastodon|https://example.com/posts/a/'
    assert sent_log['sent'][key], 'sent log should record the post'
    assert_equal 'sent', sent_log['sent'][key]['status']
    assert sent_log['sent'][key]['syndicated_url'].to_s.start_with?('https://fake.example/'),
           'sent log records the syndicated URL'

    # Second run with a fresh adapter — should NOT call .post again.
    net2 = FakeNetwork.new(name: 'mastodon')
    dispatcher_with([net2]).run
    assert_empty net2.calls, 'previously-syndicated post must not be reposted'
  end

  def test_failed_post_is_logged_as_failed_and_retried_next_run
    add_post(slug: 'a')
    failing = FakeNetwork.new(name: 'mastodon', returns: ->(_) { nil })
    dispatcher_with([failing]).run

    key = 'mastodon|https://example.com/posts/a/'
    # Failures are tracked so we can see them in the log...
    assert_equal 'failed', sent_log['sent'][key]['status']

    # ...but we DO retry on next build (failures aren't sticky like
    # successes are — a transient outage shouldn't permanently skip
    # syndication for this post).
    succeeding = FakeNetwork.new(name: 'mastodon')
    dispatcher_with([succeeding]).run
    assert_equal 1, succeeding.calls.size
  end

  def test_unconfigured_network_is_silently_skipped
    add_post(slug: 'a')
    unconfigured = FakeNetwork.new(name: 'mastodon').tap do |n|
      n.singleton_class.send(:define_method, :configured?) { false }
    end
    dispatcher_with([unconfigured]).run
    assert_empty unconfigured.calls
    # No log entry — we never attempted, so there's nothing to record.
    refute sent_log['sent']&.any?
  end
end

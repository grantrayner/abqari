# frozen_string_literal: true

require_relative 'test_helper'
require 'tmpdir'
require 'fileutils'

# Tests for the plugin contract: hook registry, auto-loading, and
# lifecycle integration.

class HooksRegistryTest < Minitest::Test
  def setup
    Abqari::Hooks.clear!
  end

  def teardown
    Abqari::Hooks.clear!
  end

  def test_register_and_run_fires_callbacks_in_order
    calls = []
    Abqari::Hooks.register(:probe) { |arg| calls << [:a, arg] }
    Abqari::Hooks.register(:probe) { |arg| calls << [:b, arg] }

    Abqari::Hooks.run(:probe, 42)

    assert_equal [[:a, 42], [:b, 42]], calls
  end

  def test_run_with_no_registered_callbacks_is_a_noop
    Abqari::Hooks.run(:nobody_home, 1, 2, 3) # should not raise
    pass
  end

  def test_run_filter_threads_value_through_callbacks
    Abqari::Hooks.register(:transform) { |v| v.upcase }
    Abqari::Hooks.register(:transform) { |v| "#{v}!" }

    result = Abqari::Hooks.run_filter(:transform, 'hello')
    assert_equal 'HELLO!', result
  end

  def test_run_filter_passes_additional_args_unchanged
    Abqari::Hooks.register(:tag) { |html, page| "#{html} (from #{page})" }
    result = Abqari::Hooks.run_filter(:tag, '<p>x</p>', 'home')
    assert_equal '<p>x</p> (from home)', result
  end

  def test_register_requires_a_block
    assert_raises(ArgumentError) { Abqari::Hooks.register(:foo) }
  end

  def test_clear_resets_the_registry
    Abqari::Hooks.register(:probe) { :ignored }
    assert_equal 1, Abqari::Hooks.count(:probe)

    Abqari::Hooks.clear!
    assert_equal 0, Abqari::Hooks.count(:probe)
  end

  def test_hook_exceptions_are_re_raised_with_logged_backtrace
    Abqari::Hooks.register(:explode) { raise 'boom' }

    err = nil
    _out, log = capture_io do
      err = assert_raises(RuntimeError) { Abqari::Hooks.run(:explode) }
    end

    assert_equal 'boom', err.message
    # The backtrace half of the name was never actually checked.
    assert_match(/plugin hook explode crashed/, log)
    assert_match(/hooks_test\.rb:\d+/, log, 'the log should locate the failing hook')
  end

  def test_filter_exceptions_are_re_raised
    Abqari::Hooks.register(:explode) { |_v| raise 'filter-boom' }

    err = nil
    _out, log = capture_io do
      err = assert_raises(RuntimeError) { Abqari::Hooks.run_filter(:explode, 'x') }
    end

    assert_equal 'filter-boom', err.message
    assert_match(/plugin filter explode crashed/, log)
  end

  def test_registered_events_returns_unique_keys
    Abqari::Hooks.register(:a) { :_ }
    Abqari::Hooks.register(:a) { :_ }
    Abqari::Hooks.register(:b) { :_ }
    assert_equal %i[a b].sort, Abqari::Hooks.registered_events.sort
  end
end

class PluginLoaderTest < Minitest::Test
  def setup
    Abqari::Hooks.clear!
    @tmpdir = Dir.mktmpdir('abqari-plugin-test')
  end

  def teardown
    FileUtils.rm_rf(@tmpdir)
    Abqari::Hooks.clear!
  end

  def test_no_plugins_dir_is_silent_noop
    Abqari::PluginLoader.load_from(@tmpdir)
    assert_equal [], Abqari::Hooks.registered_events
  end

  def test_loads_every_plugin_file_in_sorted_order
    FileUtils.mkdir_p(File.join(@tmpdir, 'plugins'))
    File.write(File.join(@tmpdir, 'plugins', '1_first.rb'), <<~RUBY)
      Abqari::Hooks.register(:order) { |arr| arr << :first; arr }
    RUBY
    File.write(File.join(@tmpdir, 'plugins', '2_second.rb'), <<~RUBY)
      Abqari::Hooks.register(:order) { |arr| arr << :second; arr }
    RUBY

    Abqari::PluginLoader.load_from(@tmpdir)
    result = Abqari::Hooks.run_filter(:order, [])
    assert_equal %i[first second], result
  end

  def test_loads_plugins_recursively
    FileUtils.mkdir_p(File.join(@tmpdir, 'plugins', 'nested'))
    File.write(File.join(@tmpdir, 'plugins', 'nested', 'deep.rb'), <<~RUBY)
      Abqari::Hooks.register(:deep) { :loaded }
    RUBY

    Abqari::PluginLoader.load_from(@tmpdir)
    assert_equal 1, Abqari::Hooks.count(:deep)
  end

  def test_plugin_load_errors_are_re_raised_with_path_context
    FileUtils.mkdir_p(File.join(@tmpdir, 'plugins'))
    bad_path = File.join(@tmpdir, 'plugins', 'broken.rb')
    File.write(bad_path, 'def syntax error not valid')

    err = nil
    _out, log = capture_io do
      err = assert_raises(SyntaxError) { Abqari::PluginLoader.load_from(@tmpdir) }
    end

    assert_includes err.message.to_s.downcase, 'syntax'
    assert_match(/plugin load failed/, log)
    assert_includes log, bad_path, 'the log should name the offending plugin file'
  end
end

class PluginLifecycleIntegrationTest < Minitest::Test
  # End-to-end: drop a real plugin file into a temp site, build it,
  # verify the hook fires at the right time and the filter modifies
  # the output HTML.

  def setup
    Abqari::Hooks.clear!
    @tmpdir = Dir.mktmpdir('abqari-plugin-integration')
    setup_minimal_site
  end

  def teardown
    FileUtils.rm_rf(@tmpdir)
    Abqari::Hooks.clear!
  end

  def setup_minimal_site
    FileUtils.mkdir_p(File.join(@tmpdir, 'config'))
    File.write(File.join(@tmpdir, 'config', 'site.yml'), <<~YAML)
      title: Plugin Test
      url: https://example.com
      indexable: true
      block_ai_scraping: false
    YAML

    FileUtils.mkdir_p(File.join(@tmpdir, 'content'))
    File.write(File.join(@tmpdir, 'content', 'index.md'), <<~MD)
      ---
      title: Home
      ---

      Hello, plugin world.
    MD

    FileUtils.mkdir_p(File.join(@tmpdir, 'plugins'))
    File.write(File.join(@tmpdir, 'plugins', 'demo.rb'), <<~RUBY)
      # Demo plugin: replace `world` with `WORLD` in every rendered
      # page, and track lifecycle events in a global probe.
      $plugin_events = []
      Abqari::Hooks.register(:before_build)     { |_site| $plugin_events << :before_build }
      Abqari::Hooks.register(:after_load_pages) { |_site| $plugin_events << :after_load_pages }
      Abqari::Hooks.register(:after_generate)   { |_site| $plugin_events << :after_generate }
      Abqari::Hooks.register(:after_build)      { |_site| $plugin_events << :after_build }

      Abqari::Hooks.register(:post_process) do |html, _site, _page|
        html.gsub('world', 'WORLD')
      end
    RUBY
  end

  def test_lifecycle_events_fire_in_documented_order
    with_env('ABQARI_SITE_ROOT' => @tmpdir,
             'ABQARI_OUTPUT_DIR' => File.join(@tmpdir, '_site'),
             'ABQARI_ALLOW_EXTERNAL_OUTPUT' => 'true',
             'ABQARI_ENV' => 'production') do
      Abqari::Site.new.build
    end

    assert_equal %i[before_build after_load_pages after_generate after_build],
                 $plugin_events,
                 'lifecycle events should fire in the order Hooks documents'
  ensure
    $plugin_events = nil
  end

  def test_post_process_filter_modifies_rendered_html
    output_dir = File.join(@tmpdir, '_site')
    with_env('ABQARI_SITE_ROOT' => @tmpdir,
             'ABQARI_OUTPUT_DIR' => output_dir,
             'ABQARI_ALLOW_EXTERNAL_OUTPUT' => 'true',
             'ABQARI_ENV' => 'production') do
      Abqari::Site.new.build
    end

    html = File.read(File.join(output_dir, 'index.html'), encoding: 'UTF-8')
    refute_includes html, 'plugin world'   # the original text
    assert_includes html, 'plugin WORLD'   # the post-processed text
  end

  private

  def with_env(env)
    old = {}
    env.each { |k, v| old[k] = ENV[k]; ENV[k] = v }
    yield
  ensure
    old.each { |k, v| ENV[k] = v }
  end
end

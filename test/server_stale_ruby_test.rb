# frozen_string_literal: true

require_relative 'test_helper'

# `bin/serve` builds its Site once, so a plugin edited while it runs is
# never re-loaded — nor is anything the plugin required from lib/. A
# site that added a helper to plugins/ and a layout calling it got
#
#   NoMethodError: undefined method 'with_years' for an instance of Abqari::RenderContext
#
# on every page until a restart, with nothing saying why: plugins/
# wasn't even watched. The server can't reload Ruby safely, but it can
# say a restart is needed — when the Ruby changes, and again when a
# build fails while it's stale.
class ServerStaleRubyTest < Minitest::Test
  def setup
    @root = Dir.mktmpdir('abqari-stale-ruby')
    write 'config/site.yml', <<~YAML
      title: Stale Ruby
      url: https://example.com
      indexable: true
      block_ai_scraping: false
    YAML
    write 'content/index.md', "---\ntitle: Home\nlayout: plain\n---\n\nHello.\n"
    write 'app/views/layouts/plain.html.erb', "<main><%= page.title %></main>\n"
    write 'lib/stale_ruby_fixture.rb', "module StaleRubyFixture; end\n"
    write 'plugins/site.rb', "require_relative '../lib/stale_ruby_fixture'\n"

    @prev_env = ENV.to_h.slice('ABQARI_SITE_ROOT', 'ABQARI_OUTPUT_DIR')
    ENV['ABQARI_SITE_ROOT']  = @root
    ENV['ABQARI_OUTPUT_DIR'] = File.join(@root, '_site')

    @site = Abqari::Site.new
    capture_io { @site.build }
    @server = Abqari::Server.new(@site, logger: WEBrick::Log.new(File::NULL))
  end

  def teardown
    %w[ABQARI_SITE_ROOT ABQARI_OUTPUT_DIR].each { |k| ENV[k] = @prev_env[k] }
    FileUtils.rm_rf(@root)
  end

  def test_watcher_sees_plugin_files
    assert_includes @server.send(:file_snapshot).keys, File.join(@root, 'plugins', 'site.rb'),
                    'plugins/ must be watched, or a plugin edit is invisible to bin/serve'
  end

  def test_editing_a_plugin_says_to_restart
    edit 'plugins/site.rb', "require_relative '../lib/stale_ruby_fixture'\n# edited\n"

    _out, err = capture_io { @server.send(:rebuild, [path('plugins/site.rb')]) }

    assert_match %r{plugins/site\.rb changed.*restart}, err
  end

  def test_editing_lib_ruby_a_plugin_required_says_to_restart
    edit 'lib/stale_ruby_fixture.rb', "module StaleRubyFixture; VERSION = 2; end\n"

    _out, err = capture_io { @server.send(:rebuild, [path('lib/stale_ruby_fixture.rb')]) }

    assert_match %r{lib/stale_ruby_fixture\.rb changed.*restart}, err
  end

  # The Sanad sequence: save the plugin, then the layout that calls its
  # new helper. The render failure arrives in the second batch, long
  # after the first warning, so it has to carry the hint itself.
  def test_render_failure_after_a_plugin_edit_names_the_plugin
    edit 'plugins/site.rb', <<~RUBY
      module StaleRubyFixtureHelpers
        def stale_fixture_greeting(name) = name.upcase
      end
      Abqari::RenderContext.include(StaleRubyFixtureHelpers)
    RUBY
    capture_io { @server.send(:rebuild, [path('plugins/site.rb')]) }

    edit 'app/views/layouts/plain.html.erb', "<main><%= stale_fixture_greeting(page.title) %></main>\n"
    _out, err = capture_io { @server.send(:rebuild, [path('app/views/layouts/plain.html.erb')]) }

    assert_match(/NoMethodError.*stale_fixture_greeting.*RenderContext/, err)
    assert_match %r{Restart bin/serve: plugins/site\.rb changed after it started}, err.lines.last
  end

  def test_content_edit_with_unchanged_ruby_is_quiet
    edit 'content/index.md', "---\ntitle: Home again\nlayout: plain\n---\n\nHello.\n"

    _out, err = capture_io { @server.send(:rebuild, [path('content/index.md')]) }

    refute_match(/restart/i, err)
  end

  def test_added_and_deleted_plugins_count_as_stale
    write 'plugins/new.rb', "# added after boot\n"
    FileUtils.rm(path('plugins/site.rb'))

    assert_equal %w[plugins/new.rb plugins/site.rb], @site.stale_ruby_sources
  end

  private

  def path(relative) = File.join(@root, relative)

  def write(relative, body)
    FileUtils.mkdir_p(File.dirname(path(relative)))
    File.write(path(relative), body)
  end

  # Push the mtime forward explicitly: a same-tick rewrite on a
  # coarse-grained filesystem would otherwise look unchanged.
  def edit(relative, body)
    before = File.mtime(path(relative))
    write(relative, body)
    File.utime(before + 2, before + 2, path(relative))
  end
end

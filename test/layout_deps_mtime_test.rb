# frozen_string_literal: true

require_relative 'test_helper'
require 'tmpdir'

# Per-layout mtime in Renderer. Edits to one layout file shouldn't
# invalidate cached output for pages using a different layout. The
# chain is walked via the `layout:` frontmatter on each layout file,
# so `post → application` re-renders post pages when either link
# changes but not when `photo.html.erb` changes.
class LayoutDepsMtimeTest < Minitest::Test
  def setup
    @prev_root = ENV['ABQARI_SITE_ROOT']
    @tmpdir = Dir.mktmpdir('abqari-layout-deps')
    ENV['ABQARI_SITE_ROOT'] = @tmpdir

    FileUtils.mkdir_p(File.join(@tmpdir, 'app/views/layouts'))
    FileUtils.mkdir_p(File.join(@tmpdir, 'config'))
    File.write(File.join(@tmpdir, 'config/site.yml'), "title: T\n")

    write_layout('application', '<html><body><%== yield_content %></body></html>')
    write_layout('post', "---\nlayout: application\n---\n<article><%== page.content %></article>")
    write_layout('photo', "---\nlayout: application\n---\n<figure><%== page.content %></figure>")
    write_layout('orphan', '<div>standalone</div>')

    @site = Abqari::Site.new
    @renderer = @site.renderer
  end

  def teardown
    ENV['ABQARI_SITE_ROOT'] = @prev_root
    FileUtils.rm_rf(@tmpdir)
  end

  def write_layout(name, body)
    File.write(File.join(@tmpdir, 'app/views/layouts', "#{name}.html.erb"), body)
  end

  def test_layout_chain_includes_self_and_parent
    chain = @renderer.send(:layout_chain, 'post')
    assert_equal 2, chain.size, "post chain should be [post, application], got #{chain.inspect}"
    assert chain[0].end_with?('post.html.erb')
    assert chain[1].end_with?('application.html.erb')
  end

  def test_layout_chain_terminates_at_layout_with_no_parent
    chain = @renderer.send(:layout_chain, 'orphan')
    assert_equal 1, chain.size
    assert chain.first.end_with?('orphan.html.erb')
  end

  def test_layout_chain_handles_missing_layout
    chain = @renderer.send(:layout_chain, 'doesntexist')
    assert_empty chain
  end

  def test_layout_chain_does_not_loop_on_self_extending_layout
    # A layout that extends itself (illegally) shouldn't hang the build.
    write_layout('cycle', "---\nlayout: cycle\n---\n<div>loop</div>")
    @renderer.clear_template_cache
    chain = @renderer.send(:layout_chain, 'cycle')
    assert_equal 1, chain.size, 'cycle should terminate at the second visit'
  end

  def test_post_layout_edit_changes_post_mtime_not_photo_mtime
    initial_post_mtime  = @renderer.layout_deps_mtime('post')
    initial_photo_mtime = @renderer.layout_deps_mtime('photo')

    sleep 0.01 # ensure mtime resolution moves
    File.utime(Time.now, Time.now, File.join(@tmpdir, 'app/views/layouts/post.html.erb'))

    @renderer.clear_template_cache
    new_post_mtime  = @renderer.layout_deps_mtime('post')
    new_photo_mtime = @renderer.layout_deps_mtime('photo')

    assert new_post_mtime > initial_post_mtime,
           'post mtime should advance after editing post.html.erb'
    assert_equal initial_photo_mtime, new_photo_mtime,
                 'photo mtime should NOT advance from a post-only edit'
  end

  def test_application_layout_edit_invalidates_every_chain_extending_it
    initial_post_mtime  = @renderer.layout_deps_mtime('post')
    initial_photo_mtime = @renderer.layout_deps_mtime('photo')

    sleep 0.01
    File.utime(Time.now, Time.now, File.join(@tmpdir, 'app/views/layouts/application.html.erb'))

    @renderer.clear_template_cache
    new_post_mtime  = @renderer.layout_deps_mtime('post')
    new_photo_mtime = @renderer.layout_deps_mtime('photo')

    assert new_post_mtime > initial_post_mtime,
           'post chain includes application; touching application should advance post mtime'
    assert new_photo_mtime > initial_photo_mtime,
           'photo chain includes application; touching application should advance photo mtime'
  end

  def test_orphan_layout_unaffected_by_application_edit
    initial_orphan_mtime = @renderer.layout_deps_mtime('orphan')

    sleep 0.01
    File.utime(Time.now, Time.now, File.join(@tmpdir, 'app/views/layouts/application.html.erb'))

    @renderer.clear_template_cache
    new_orphan_mtime = @renderer.layout_deps_mtime('orphan')
    assert_equal initial_orphan_mtime, new_orphan_mtime,
                 'orphan layout has no chain dependency on application'
  end
end

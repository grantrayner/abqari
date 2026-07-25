# frozen_string_literal: true

require_relative 'test_helper'
require 'ostruct'

# `document_title` — the <title> text. "Page · Site" normally; just the
# site title when the page titles itself after the site (the home page
# default — "Mysite · Mysite" reads like a bug) or has no title at all.
class DocumentTitleTest < Minitest::Test
  def setup
    @site = TestHelpers.built_site
  end

  def ctx_for(page_title)
    page = OpenStruct.new(title: page_title, url: '/')
    Abqari::RenderContext.new(page, @site)
  end

  def site_title
    @site.config['title'].to_s
  end

  def test_regular_page_gets_page_dot_site
    assert_equal "About · #{site_title}", ctx_for('About').document_title
  end

  def test_page_titled_after_the_site_collapses_to_site_title
    assert_equal site_title, ctx_for(site_title).document_title
  end

  def test_untitled_page_falls_back_to_site_title
    assert_equal site_title, ctx_for(nil).document_title
    assert_equal site_title, ctx_for('').document_title
  end

  def test_head_partial_uses_document_title
    # The partial must call the helper — a regression back to the inline
    # "page.title · site.title" form reintroduces the duplication.
    head = File.read(File.join(@site.engine_root, 'app', 'views', 'partials', '_head.html.erb'),
                     encoding: 'UTF-8')
    assert_includes head, 'document_title'
  end
end

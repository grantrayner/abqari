# frozen_string_literal: true

require_relative 'test_helper'

# The magazine theme's signature drop cap must target the wrapper the
# post layout actually renders. Regression guard: the original selector
# (`article > p:first-of-type`) matched nothing on post pages — body
# paragraphs live inside `div.e-content`, and the only direct <p> child
# of <article> is the classed back-link — so the theme's headline
# feature was dead CSS. Both directions are pinned: the theme selector
# names the wrapper, and the layouts still render that wrapper.
class MagazineDropCapTest < Minitest::Test
  ENGINE_ROOT = File.expand_path('..', __dir__)

  def magazine_css
    File.read(File.join(ENGINE_ROOT, 'themes', 'magazine', 'css', 'app.css'),
              encoding: 'UTF-8')
  end

  def test_drop_cap_anchors_to_the_body_wrapper
    assert_includes magazine_css, '.e-content > p:first-of-type',
                    'drop cap must target the e-content body wrapper'
    refute_match(/^article > p:first-of-type/, magazine_css,
                 'the article > p form matches nothing on post pages')
  end

  def test_body_wrapper_still_rendered_by_prose_layouts
    %w[post about].each do |layout|
      html = File.read(File.join(ENGINE_ROOT, 'app', 'views', 'layouts', "#{layout}.html.erb"),
                       encoding: 'UTF-8')
      assert_includes html, 'class="e-content"',
                      "#{layout} layout no longer renders .e-content — the magazine drop cap depends on it"
    end
  end
end

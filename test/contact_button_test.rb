# frozen_string_literal: true

require_relative 'test_helper'

# `partials/_contact_button.html.erb` — the spam-resistant mailto button.
#
# The `data-subject` attribute was double-escaped: the partial built the
# whole attribute as a Ruby string (`%(data-subject="#{h(subject)}")`)
# and emitted it through `<%=`, which under Erubi's `escape: true`
# escapes its output — so the attribute's own quote characters came out
# as `&quot;` and the button tag rendered malformed:
#
#     data-subject=&quot;Project enquiry&quot;
#
# The attribute name and quotes are now literal template text; only the
# value passes through the auto-escape, which is exactly what should be
# escaped.
class ContactButtonTest < Minitest::Test
  EMAIL = 'hello@example.com'

  def setup
    @site = TestHelpers.built_site
    @page = @site.pages.first
    @original_contact = @site.config['contact']&.dup
  end

  def teardown
    @site.config['contact'] = @original_contact
  end

  # The partial opens with a long documentation comment that renders
  # unconditionally; drop it so the "renders nothing" cases can assert
  # on an empty string.
  def render_with(contact)
    @site.config['contact'] = contact
    html = Abqari::RenderContext.new(@page, @site).render('partials/contact_button')
    html.sub(/\A\s*<!--.*?-->/m, '')
  end

  def button_tag(html)
    html[/<button\b[^>]*>/m]
  end

  def test_subject_renders_as_a_well_formed_attribute
    html = render_with('email' => EMAIL, 'subject' => 'Project enquiry')

    assert_includes html, 'data-subject="Project enquiry"'
    refute_includes html, '&quot;'
    assert_match(/<button\b[^>]*\sdata-subject="Project enquiry"[^>]*>/, button_tag(html))
  end

  def test_email_halves_survive_alongside_the_subject
    html = render_with('email' => EMAIL, 'subject' => 'Project enquiry')
    tag  = button_tag(html)

    assert_includes tag, 'data-user="hello"'
    assert_includes tag, 'data-domain="example.com"'
    refute_includes html, EMAIL
  end

  def test_subject_value_is_escaped_without_breaking_the_attribute
    html = render_with('email' => EMAIL, 'subject' => 'Ben & "Jerry" <b>')
    tag  = button_tag(html)

    assert_includes tag, 'data-subject="Ben &amp; &quot;Jerry&quot; &lt;b&gt;"'
    # The escaped `<` must not open a second tag: the button tag ends at
    # the first `>` after the attribute list.
    assert_match(/\A<button\b[^<]*>\z/, tag)
  end

  # contact-button.js delegates on `.contact-button[data-user][data-domain]`,
  # but the partial only ever emitted the styling classes — so the
  # selector matched nothing and the button was inert: clicking it did
  # nothing at all, on every site that enabled it. The hook class is now
  # emitted separately from `css_class:`, and this test reads the
  # selector out of the shipped JS so the two can't drift apart again.
  def test_button_carries_the_class_the_click_handler_delegates_on
    js = File.read(File.join(@site.engine_root, 'app', 'assets', 'js', 'contact-button.js'),
                   encoding: 'UTF-8')
    hook = js[/closest\(\s*'\.([a-z-]+)/, 1]
    refute_nil hook, 'could not read the delegated class out of contact-button.js'

    tag = button_tag(render_with('email' => EMAIL))

    assert_match(/\sclass="[^"]*\b#{Regexp.escape(hook)}\b[^"]*"/, tag,
                 "button must carry .#{hook} or the click handler never fires")
  end

  def test_hook_class_survives_a_css_class_override
    @site.config['contact'] = { 'email' => EMAIL }
    html = Abqari::RenderContext.new(@page, @site)
                                .render('partials/contact_button', css_class: 'btn btn-success')
    tag = button_tag(html)

    assert_match(/\sclass="contact-button btn btn-success"/, tag)
  end

  def test_no_subject_attribute_when_subject_is_unset
    tag = button_tag(render_with('email' => EMAIL))

    refute_includes tag, 'data-subject'
    assert_includes tag, 'data-user="hello"'
  end

  def test_renders_nothing_without_an_email
    assert_empty render_with('label' => 'Contact').strip
  end

  def test_renders_nothing_when_disabled
    assert_empty render_with('email' => EMAIL, 'enabled' => false).strip
  end
end

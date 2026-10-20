# frozen_string_literal: true

require_relative 'test_helper'

class HtmlTest < Minitest::Test
  def test_text_uses_html5_attribute_comment_and_entity_rules
    html = '<!-- ignore --!><p title=">">Hello &amp; <b>goodbye</b></p>'
    assert_equal 'Hello & goodbye', Abqari::Html.text(html)
  end

  def test_non_visible_code_does_not_inflate_reading_statistics
    html = '<p>one two</p><script>not visible words</script>' \
           '<style>not visible words</style><template>not visible words</template>'
    assert_equal 'one two', Abqari::Helpers.excerpt(html)
    assert_equal 2, Abqari::Helpers.word_count(html)
    assert_equal '1 min read', Abqari::Helpers.reading_time(html)
  end

  def test_extracted_text_still_uses_template_auto_escaping
    context = Object.new.extend(Abqari::Helpers)
    template = Abqari::ErbiTemplate.new('<%= excerpt("&lt;script&gt;hello&lt;/script&gt;") %>')
    assert_equal '&lt;script&gt;hello&lt;/script&gt;', template.result(context.instance_eval { binding })
  end

  def test_literal_comparisons_and_long_malformed_input_are_text
    assert_equal '2 < 3 and 4 > 1', Abqari::Html.text('2 < 3 and 4 > 1')
    text = '<' * 30_000
    assert_equal text, Abqari::Html.text(text)
  end
end

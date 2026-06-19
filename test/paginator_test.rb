# frozen_string_literal: true

require_relative 'test_helper'

class PaginatorTest < Minitest::Test
  def make(page:, total:)
    Abqari::Paginator.new(posts: [], page: page, total_pages: total, base_url: '/blog/')
  end

  def test_first_page_has_no_prev
    p = make(page: 1, total: 3)
    assert_predicate p, :first?
    assert_nil p.prev_url
    assert_equal '/blog/page/2/', p.next_url
  end

  def test_middle_page_has_both
    p = make(page: 2, total: 3)
    refute_predicate p, :first?
    refute_predicate p, :last?
    assert_equal '/blog/', p.prev_url
    assert_equal '/blog/page/3/', p.next_url
  end

  def test_page_3_prev_points_to_page_2
    p = make(page: 3, total: 5)
    assert_equal '/blog/page/2/', p.prev_url
  end

  def test_last_page_has_no_next
    p = make(page: 3, total: 3)
    assert_predicate p, :last?
    assert_equal '/blog/page/2/', p.prev_url
    assert_nil p.next_url
  end

  def test_single_page_has_neither
    p = make(page: 1, total: 1)
    assert_predicate p, :first?
    assert_predicate p, :last?
    assert_nil p.prev_url
    assert_nil p.next_url
  end

  def test_base_url_normalised_with_trailing_slash
    p = Abqari::Paginator.new(posts: [], page: 2, total_pages: 3, base_url: '/journal')
    assert_equal '/journal/page/3/', p.next_url
  end
end

# frozen_string_literal: true

require_relative 'test_helper'

class PathSafeTest < Minitest::Test
  def test_join_under_returns_absolute_path
    assert_equal '/tmp/site/posts/hello/index.html',
                 Abqari::PathSafe.join_under('/tmp/site', 'posts', 'hello', 'index.html')
  end

  def test_join_under_allows_base_itself
    assert_equal '/tmp/site', Abqari::PathSafe.join_under('/tmp/site')
  end

  def test_join_under_rejects_traversal_via_dotdot
    assert_raises(Abqari::PathSafe::Error) do
      Abqari::PathSafe.join_under('/tmp/site', '..', 'etc', 'passwd')
    end
  end

  def test_join_under_rejects_deep_traversal
    assert_raises(Abqari::PathSafe::Error) do
      Abqari::PathSafe.join_under('/tmp/site', '../../etc/passwd')
    end
  end

  def test_join_under_treats_absolute_segment_as_relative
    # File.join('/tmp/site', '/etc/passwd') == '/tmp/site/etc/passwd' — the
    # leading slash on the segment is purely cosmetic. Verify the join
    # lands inside the base, not at /etc.
    assert_equal '/tmp/site/etc/passwd',
                 Abqari::PathSafe.join_under('/tmp/site', '/etc/passwd')
  end

  def test_join_under_tolerates_nil_and_empty_segments
    assert_equal '/tmp/site/about/index.html',
                 Abqari::PathSafe.join_under('/tmp/site', nil, 'about', '', 'index.html')
  end

  def test_join_under_does_not_match_sibling_prefix
    # /tmp/site_other shouldn't be treated as "under /tmp/site" just because
    # the prefix string matches. The separator check guards against this.
    assert_raises(Abqari::PathSafe::Error) do
      Abqari::PathSafe.join_under('/tmp/site', '../site_other/file.txt')
    end
  end

  # assert_under

  def test_assert_under_passes_for_descendant
    Abqari::PathSafe.assert_under('/tmp/site', '/tmp/site/_site')
  end

  def test_assert_under_passes_for_base_itself
    Abqari::PathSafe.assert_under('/tmp/site', '/tmp/site')
  end

  def test_assert_under_raises_for_outside_path
    assert_raises(Abqari::PathSafe::Error) do
      Abqari::PathSafe.assert_under('/tmp/site', '/etc')
    end
  end

  def test_assert_under_raises_for_sibling_prefix
    assert_raises(Abqari::PathSafe::Error) do
      Abqari::PathSafe.assert_under('/tmp/site', '/tmp/site_other')
    end
  end
end

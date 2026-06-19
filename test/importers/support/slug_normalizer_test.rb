# frozen_string_literal: true

require_relative '../../test_helper'
require 'abqari/importers'

# SlugNormalizer — the canonical-shape + collision-resolution helper
# every importer uses. Two behaviours to lock down: the normalisation
# rule matches `bin/new`'s slugify (so imported posts look like
# generator-scaffolded posts) and collisions append a numeric suffix
# rather than rewriting the original slug.
class SlugNormalizerTest < Minitest::Test
  Normalizer = Abqari::Importers::Support::SlugNormalizer

  def test_lowercases_and_dasherises_punctuation
    assert_equal 'hello-world', Normalizer.normalize('Hello, World!')
  end

  def test_collapses_consecutive_separators
    assert_equal 'a-b-c', Normalizer.normalize('A    B---C')
  end

  def test_strips_leading_and_trailing_dashes
    assert_equal 'foo', Normalizer.normalize('---foo---')
  end

  def test_drops_non_ascii_characters
    # Matches bin/new's slugify (no transliteration). Imported posts
    # from non-Latin sources may end up with empty slugs — the base
    # writer falls back to 'untitled' in that case.
    assert_equal '', Normalizer.normalize('日本語')
  end

  def test_resolve_returns_original_when_unique
    taken = Set.new
    assert_equal 'foo', Normalizer.resolve('foo', taken)
    assert_includes taken, 'foo'
  end

  def test_resolve_appends_numeric_suffix_on_collision
    taken = Set.new
    Normalizer.resolve('foo', taken)
    assert_equal 'foo-2', Normalizer.resolve('foo', taken)
    assert_equal 'foo-3', Normalizer.resolve('foo', taken)
  end

  def test_resolve_falls_back_to_untitled_for_empty_input
    taken = Set.new
    assert_equal 'untitled', Normalizer.resolve('', taken)
  end
end

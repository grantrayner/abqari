# frozen_string_literal: true

require_relative 'test_helper'
require 'tmpdir'
require 'yaml'
# Importers are lazy-loaded by `bin/import` rather than by `require
# 'abqari'` — the reverse_markdown dependency shouldn't load on every
# build. Pull them in explicitly here.
require 'abqari/importers'
require 'abqari/importers/base'
require 'abqari/importers/cli'

# Non-Latin taxonomy terms slugify to "", which collapsed `/tags/:slug/`
# to `/tags/` and wrote the term page over the taxonomy index.
# `Page#render_permalink` has guarded page slugs against exactly this;
# this is the same failure one level up.
class TaxonomyEmptySlugTest < Minitest::Test
  def setup
    @site = TestHelpers.built_site
  end

  def page_for(term)
    Abqari::TaxonomyPage.new('tags', term, [], @site)
  end

  def test_latin_term_builds_a_url
    assert_equal '/tags/ruby/', page_for('ruby').url
  end

  def test_term_with_no_url_safe_characters_is_refused
    err = assert_raises(Abqari::PathSafe::Error) { page_for('日本語').url }

    assert_match(/empty slug/, err.message)
    assert_match(/日本語/, err.message, 'the error should name the term')
  end

  def test_punctuation_only_term_is_refused
    assert_raises(Abqari::PathSafe::Error) { page_for('!!!').url }
  end

  # `C++` and `C#` both slugify to "c". That collision is caught by
  # `detect_output_collisions!`, not here — this only guards emptiness.
  def test_terms_that_slugify_to_the_same_non_empty_value_still_build
    assert_equal '/tags/c/', page_for('C++').url
    assert_equal '/tags/c/', page_for('C#').url
  end
end

# Sitemap `<image:loc>` values are built from filesystem basenames, so a
# space or non-ASCII character has to be percent-encoded — XML escaping
# is a different layer and doesn't help.
class BundleImageUrlEncodingTest < Minitest::Test
  def setup
    @prev_root = ENV['ABQARI_SITE_ROOT']
    @tmpdir = Dir.mktmpdir('abqari-img-url')
    ENV['ABQARI_SITE_ROOT'] = @tmpdir
    @bundle = File.join(@tmpdir, 'content', 'posts', 'my-post')
    FileUtils.mkdir_p(@bundle)
    File.write(File.join(@bundle, 'index.md'), "---\ntitle: T\n---\nbody\n")
  end

  def teardown
    ENV['ABQARI_SITE_ROOT'] = @prev_root
    FileUtils.rm_rf(@tmpdir)
  end

  def images_for(*filenames)
    filenames.each { |f| File.write(File.join(@bundle, f), 'x') }
    site = Abqari::Site.allocate
    site.instance_variable_set(:@site_root, @tmpdir)
    site.instance_variable_set(:@config, {})
    site.instance_variable_set(:@memos, {})
    Abqari::Page.new(File.join(@bundle, 'index.md'), site).bundle_images
  end

  def test_spaces_are_percent_encoded
    assert_includes images_for('my photo.jpg'), '/posts/my-post/my%20photo.jpg'
  end

  def test_non_ascii_is_percent_encoded
    assert_includes images_for('café.png'), '/posts/my-post/caf%C3%A9.png'
  end

  def test_ordinary_names_are_untouched
    assert_includes images_for('hero.jpg'), '/posts/my-post/hero.jpg'
  end
end

# Publishing is gated on having a bundle, not on being a post. Photos
# are bundle-style too, so `post?` meant a photo went stale when only
# its image changed — while `lastmod` still advertised it as updated.
class BundleStalenessGateTest < Minitest::Test
  def test_needs_render_checks_bundle_assets_for_any_bundle_collection
    src = File.read(File.join(Abqari::ROOT, 'lib', 'abqari', 'page', 'incremental.rb'),
                    encoding: 'UTF-8')
    body = src[/def needs_render\?(.*?)\n      end/m, 1]
    refute_nil body

    assert_match(/bundle_dir && bundle_assets/, body,
                 'the bundle-asset check should gate on having a bundle, not on post?')
    refute_match(/post\? && bundle_assets/, body)
  end
end

# The importer writes frontmatter for third-party content, so a title
# carrying a newline could close one mapping entry and open another.
class ImporterYamlScalarTest < Minitest::Test
  def scalar_for(raw)
    Abqari::Importers::Base.allocate.send(:yaml_scalar, raw)
  end

  def assert_round_trips(raw)
    doc = "title: #{scalar_for(raw)}\n"
    parsed = YAML.safe_load(doc)
    assert_equal ['title'], parsed.keys, "#{raw.inspect} should stay a single key"
    assert_equal raw, parsed['title'], "#{raw.inspect} should round-trip intact"
  end

  def test_newline_cannot_inject_a_second_key
    raw = "Hello\npermalink: /../../evil"
    assert_round_trips(raw)
    refute_match(/^permalink:/, "title: #{scalar_for(raw)}")
  end

  # The NUL is written as the `\0` escape, not pasted in raw. A literal
  # NUL byte in the source makes git classify the whole file as binary,
  # so every future change to it shows as "Bin 8825 -> 8826 bytes"
  # instead of a reviewable diff.
  def test_other_control_characters_round_trip
    ["tab\there", "carriage\rreturn", "null\0byte"].each { |raw| assert_round_trips(raw) }
  end

  def test_backslashes_quotes_and_replacement_metacharacters_round_trip
    ['Has: C:\\folder\\file', 'Has: \\"quoted\\"', 'Has: \\1\\&\\`',
     "Hello\\\"\npermalink: /../../evil", "Has: \\\\"].each do |raw|
      assert_round_trips(raw)
    end
  end

  def test_unicode_yaml_line_breaks_remain_inside_one_scalar
    ["\u0085", "\u2028", "\u2029"].each do |separator|
      assert_round_trips("Hello#{separator}permalink: /../../evil")
    end
  end

  def test_ordinary_values_are_not_gratuitously_quoted
    assert_equal 'plain title', scalar_for('plain title')
  end

  def test_yaml_significant_values_are_still_quoted
    %w[yes true null].each { |raw| assert_round_trips(raw) }
    assert_round_trips('Has: colon')
  end
end

# `bin/import` with no arguments is a usage error, not a success —
# every other command here exits 1 for the same mistake.
class ImporterCliExitCodeTest < Minitest::Test
  def test_no_arguments_is_a_failure
    _out, err = capture_io { refute Abqari::Importers::CLI.run([]) }
    assert_match(/Missing required argument/, err)
  end

  def test_explicit_help_is_a_success
    capture_io { assert Abqari::Importers::CLI.run(['--help']) }
  end

  def test_unknown_platform_is_a_failure
    _out, _err = capture_io { refute Abqari::Importers::CLI.run(['nosuchplatform']) }
  end
end

# `reverse_markdown` is an optional dependency: it drags in nokogiri →
# racc, and on Ruby 3.3 (the gemspec floor) racc has no precompiled
# Linux binary, so a toolchain-free image fails `bundle install`
# outright. Importing asks for it at point of use instead.
class OptionalReverseMarkdownTest < Minitest::Test
  def test_gemspec_does_not_declare_it_as_a_runtime_dependency
    spec = Gem::Specification.load(File.join(Abqari::ROOT, 'abqari.gemspec'))
    refute_nil spec

    runtime = spec.dependencies.select { |d| d.type == :runtime }.map(&:name)
    refute_includes runtime, 'reverse_markdown',
                    'declaring it would re-break `bundle install` on Ruby 3.3-slim'
    # The rest of the runtime set should still be intact.
    %w[commonmarker erubi rouge ruby-vips webrick base64 csv].each do |gem_name|
      assert_includes runtime, gem_name
    end
  end

  def test_requiring_the_engine_does_not_load_the_importers
    # The engine must not reach reverse_markdown on a normal build —
    # that's the whole basis for leaving it out of the gemspec.
    engine = File.read(File.join(Abqari::ROOT, 'lib', 'abqari.rb'), encoding: 'UTF-8')
    refute_match(/require_relative 'abqari\/importers/, engine)
  end

  # Hand-rolled stub rather than `Object#stub`: Minitest 6 dropped
  # `minitest/mock` from the default install, and this test errored on
  # every run once the suite moved to it.
  def test_missing_gem_produces_an_actionable_error
    mod = Abqari::Importers::Support::HtmlToMarkdown
    mod.define_singleton_method(:require) { |_name| raise LoadError }

    err = assert_raises(Abqari::UserError) { mod.convert('<p>hi</p>') }

    assert_match(/reverse_markdown/, err.message)
    assert_match(/gem install reverse_markdown/, err.message,
                 'the error should say exactly how to fix it')
  ensure
    mod.singleton_class.send(:remove_method, :require)
  end

  def test_conversion_still_works_when_the_gem_is_present
    # It's in the development group, so it is present here.
    md = Abqari::Importers::Support::HtmlToMarkdown.convert('<p>hello</p>')
    assert_match(/hello/, md)
  end
end

# The dev server's port knob should be checkable without building.
class ServerValidateEnvTest < Minitest::Test
  def setup
    @prev = ENV['ABQARI_PORT']
  end

  def teardown
    ENV['ABQARI_PORT'] = @prev
  end

  def test_validate_env_rejects_a_bad_port_without_a_site
    ENV['ABQARI_PORT'] = 'abc'
    err = assert_raises(Abqari::UserError) { Abqari::Server.validate_env! }
    assert_match(/ABQARI_PORT/, err.message)
  end

  def test_validate_env_accepts_a_good_port
    ENV['ABQARI_PORT'] = '4321'
    assert_nil Abqari::Server.validate_env!
  end

  def test_validate_env_accepts_an_unset_port
    ENV.delete('ABQARI_PORT')
    assert_nil Abqari::Server.validate_env!
  end

  # bin/serve must check before it builds — the whole point is not
  # paying for a full build to learn about a typo.
  def test_skeleton_serve_validates_before_building
    body = File.read(
      File.join(Abqari::ROOT, 'lib', 'abqari', 'templates', 'site_skeleton', 'bin', 'serve'),
      encoding: 'UTF-8'
    )
    validate = body.index('Server.validate_env!')
    build    = body.index('site.build')

    refute_nil validate, 'bin/serve should validate the environment'
    assert validate < build, 'validation must happen before the build'
  end
end

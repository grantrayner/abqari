# frozen_string_literal: true

require_relative 'test_helper'
require 'ostruct'
require 'tmpdir'
require 'fileutils'
require 'vips'

# Image-pipeline behaviour. Covers the five things the rewrite
# promised:
#
#   - Per-format quality (AVIF 50, WebP 80, JPEG 85 by default;
#     legacy scalar `quality: 80` still works).
#   - Skip-if-source-smaller-than-target-width (no upscaled variants).
#   - Metadata stripped by default (EXIF / GPS / embedded thumbnails).
#   - Bundle images get the same pipeline as `app/assets/images/`.
#   - ruby-vips backend produces the expected output, with shell
#     fallback when libvips is unavailable.
#
# Uses libvips directly to generate fixture images so we don't need
# to ship binary blobs in the repo.

class ImagePipelineTest < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir('abqari-img-test')
    @site_root  = File.join(@tmpdir, 'site')
    @output_dir = File.join(@tmpdir, '_site')
    FileUtils.mkdir_p(File.join(@site_root, 'app', 'assets', 'images'))
    FileUtils.mkdir_p(@output_dir)

    @site = build_site_stub
  end

  def teardown
    FileUtils.rm_rf(@tmpdir)
  end

  # --- helpers ----------------------------------------------------------

  def build_site_stub(extra_config = {})
    config = { 'url' => 'https://example.com' }.merge(extra_config)
    site = OpenStruct.new(
      site_root: @site_root,
      output_dir: @output_dir,
      all_pages: [],
      env: :production
    )
    site.define_singleton_method(:config) { config }
    site.define_singleton_method(:collections) { {} }
    site.define_singleton_method(:external_symlink?) { |_| false }
    site
  end

  def create_image(path, width:, height:, format: :jpg)
    # Generate a real raster image via libvips. A 3-band noise pattern
    # gives non-trivial content so compression behaves realistically
    # (a flat colour would compress to ~nothing in every format and
    # mask real per-format quality differences).
    image = ::Vips::Image.gaussnoise(width, height, sigma: 30, mean: 128)
    image = image.bandjoin([
      ::Vips::Image.gaussnoise(width, height, sigma: 30, mean: 100),
      ::Vips::Image.gaussnoise(width, height, sigma: 30, mean: 80)
    ]).cast(:uchar)

    case format
    when :jpg
      image.write_to_file(path, Q: 95)
    when :png
      image.write_to_file(path)
    when :webp
      image.write_to_file(path, Q: 95)
    end
  end

  def asset_path(name)
    File.join(@site_root, 'app', 'assets', 'images', name)
  end

  def pipeline(extra_config = {})
    @site = build_site_stub('images' => extra_config)
    Abqari::ImagePipeline.new(@site)
  end

  # --- per-format quality ----------------------------------------------

  def test_per_format_quality_defaults
    create_image(asset_path('hero.jpg'), width: 1600, height: 900)
    pl = pipeline('optimise' => true)

    avif_q = pl.send(:quality_for, 'avif')
    webp_q = pl.send(:quality_for, 'webp')
    orig_q = pl.send(:quality_for, 'original')

    # The defaults are the perceptual-equivalence points: AVIF much
    # lower numerical Q than WebP, JPEG slightly higher than WebP.
    assert avif_q < webp_q, "AVIF quality (#{avif_q}) should be below WebP (#{webp_q})"
    assert orig_q >= webp_q, "JPEG quality (#{orig_q}) should be >= WebP (#{webp_q})"
    assert_equal 50, avif_q
    assert_equal 80, webp_q
    assert_equal 85, orig_q
  end

  def test_legacy_scalar_quality_still_works
    pl = pipeline('optimise' => true, 'quality' => 75)
    assert_equal 75, pl.send(:quality_for, 'avif')
    assert_equal 75, pl.send(:quality_for, 'webp')
    assert_equal 75, pl.send(:quality_for, 'original')
  end

  def test_per_format_quality_partial_override
    pl = pipeline('optimise' => true, 'quality' => { 'avif' => 40 })
    # AVIF overridden, others fall back to defaults.
    assert_equal 40, pl.send(:quality_for, 'avif')
    assert_equal 80, pl.send(:quality_for, 'webp')
    assert_equal 85, pl.send(:quality_for, 'original')
  end

  # --- skip-if-source-smaller ------------------------------------------

  def test_skip_widths_larger_than_source
    create_image(asset_path('small.jpg'), width: 600, height: 400)
    pl = pipeline('optimise' => true, 'widths' => [400, 800, 1200])

    effective = pl.send(:compute_effective_widths, [400, 800, 1200], 600)

    # 800 and 1200 are above source width — both dropped. Source
    # width itself is added so the largest variant is the native
    # resolution.
    assert_equal [400, 600], effective
  end

  def test_skip_widths_when_all_above_source
    pl = pipeline('optimise' => true)
    effective = pl.send(:compute_effective_widths, [800, 1200, 1600], 600)
    # Only the source width itself survives.
    assert_equal [600], effective
  end

  def test_no_skipping_when_source_is_huge
    pl = pipeline('optimise' => true)
    effective = pl.send(:compute_effective_widths, [400, 800, 1200], 4000)
    # All widths kept, plus source width appended.
    assert_equal [400, 800, 1200, 4000], effective
  end

  # --- metadata stripping ----------------------------------------------
  #
  # We test the contract — strip flag is correctly forwarded to the
  # backend — rather than wrestling with ruby-vips' EXIF-injection
  # API to manufacture a source-with-EXIF in fixture. Producing a
  # JPEG with valid EXIF programmatically requires writing a real
  # EXIF blob (not just setting a single field), which is outside
  # the scope of an SSG-pipeline test. The strip behaviour itself
  # is libvips territory and well-tested upstream; the contract we
  # need to pin is "we tell it to strip by default."

  def test_strip_flag_defaults_to_true
    pl = pipeline('optimise' => true)
    skip 'no backend' unless pl.backend

    assert_equal true, pl.backend.instance_variable_get(:@strip),
                 'default pipeline should strip metadata (privacy + size win)'
  end

  def test_strip_flag_false_when_preserve_metadata_true
    pl = pipeline('optimise' => true, 'preserve_metadata' => true)
    skip 'no backend' unless pl.backend

    assert_equal false, pl.backend.instance_variable_get(:@strip),
                 'preserve_metadata: true should pass strip=false to the backend'
  end

  # --- end-to-end picture_tag ------------------------------------------

  def test_picture_tag_emits_avif_webp_and_jpeg_fallback
    create_image(asset_path('hero.jpg'), width: 1600, height: 900)
    pl = pipeline('optimise' => true)
    skip 'no backend' unless pl.enabled?

    pl.process
    html = pl.picture_tag('hero.jpg', alt: 'Hero')

    assert_match %r{<picture>}, html
    assert_match %r{<source type="image/avif"}, html
    assert_match %r{<source type="image/webp"}, html
    assert_match %r{<img\s+[^>]*alt="Hero"}, html
    # Smallest configured width should appear in srcset; largest in
    # the fallback img src.
    assert_match %r{400w}, html
    assert_match %r{1200w}, html
  end

  def test_picture_tag_omits_upscaled_widths
    create_image(asset_path('small.jpg'), width: 600, height: 400)
    pl = pipeline('optimise' => true)
    skip 'no backend' unless pl.enabled?

    pl.process
    html = pl.picture_tag('small.jpg', alt: 'Small')

    # Source is 600px wide; configured widths are [400, 800, 1200].
    # The srcset should include 400w and 600w; 800w and 1200w should
    # NOT appear.
    assert_match %r{400w}, html
    assert_match %r{600w}, html
    refute_match %r{800w}, html
    refute_match %r{1200w}, html
  end

  def test_picture_tag_passthrough_when_optimise_off
    create_image(asset_path('hero.jpg'), width: 1600, height: 900)
    pl = pipeline('optimise' => false)
    pl.process

    html = pl.picture_tag('hero.jpg', alt: 'Hero')
    refute_match %r{<picture>}, html
    assert_match %r{<img\s+[^>]*src="/assets/images/hero\.jpg"}, html
  end

  # --- post_process_html rewrite ---------------------------------------

  def test_post_process_html_rewrites_asset_img_to_picture
    create_image(asset_path('hero.jpg'), width: 1600, height: 900)
    pl = pipeline('optimise' => true)
    skip 'no backend' unless pl.enabled?

    pl.process
    body = '<article><img src="/assets/images/hero.jpg" alt="Hero"></article>'
    out = pl.post_process_html(body)

    assert_match %r{<picture>}, out
    refute_includes out, '<img src="/assets/images/hero.jpg"'
  end

  def test_post_process_html_leaves_unknown_images_alone
    pl = pipeline('optimise' => true)
    body = '<img src="/external/unknown.jpg" alt="X">'
    assert_equal body, pl.post_process_html(body)
  end

  # --- determinism ------------------------------------------------------

  def test_fingerprint_stable_across_builds
    create_image(asset_path('hero.jpg'), width: 1600, height: 900)
    pl1 = pipeline('optimise' => true)
    skip 'no backend' unless pl1.enabled?

    pl1.process
    html1 = pl1.picture_tag('hero.jpg', alt: 'Hero')

    # Tear down and rebuild — same source content + mtime should
    # produce same fingerprinted filenames.
    pl2 = pipeline('optimise' => true)
    pl2.process
    html2 = pl2.picture_tag('hero.jpg', alt: 'Hero')

    # Strip whitespace differences and compare URL sets.
    urls1 = html1.scan(%r{/assets/images/[a-zA-Z0-9.\-]+}).sort
    urls2 = html2.scan(%r{/assets/images/[a-zA-Z0-9.\-]+}).sort
    assert_equal urls1, urls2
  end

  # --- backend selection -----------------------------------------------

  def test_vips_native_backend_selected_when_ruby_vips_available
    pl = pipeline('optimise' => true)
    # ruby-vips is in the gemspec, so the test environment always has
    # it; backend.name should be the native one.
    skip 'ruby-vips not loaded' unless defined?(::Vips)
    assert_equal 'vips-native', pl.backend.name
  end

  def test_backend_falls_back_when_explicit_request_fails
    pl = pipeline('optimise' => true, 'processor' => 'imagemagick')
    # If magick CLI is present, ok; if not, the auto fallback chain
    # should kick in. Either way, we should get *some* backend back
    # (or nil if literally nothing is on PATH and ruby-vips also missing).
    refute_nil pl.backend.name, 'should have either explicit or fallback backend'
  end
end

# Separate test class for bundle-image coverage — needs a real Site +
# fixture page rather than the stub.
class BundleImagePipelineTest < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir('abqari-bundle-test')
    setup_minimal_site
  end

  def teardown
    FileUtils.rm_rf(@tmpdir)
  end

  def setup_minimal_site
    # Build a tiny site with one post containing a bundle hero image.
    FileUtils.mkdir_p(File.join(@tmpdir, 'config'))
    File.write(File.join(@tmpdir, 'config', 'site.yml'), <<~YAML)
      title: Bundle Test
      url: https://example.com
      indexable: true
      block_ai_scraping: false
      images:
        optimise: true
        widths: [400, 800, 1200]
    YAML

    bundle = File.join(@tmpdir, 'content', 'posts', '2026-01-01-hero')
    FileUtils.mkdir_p(bundle)
    File.write(File.join(bundle, 'index.md'), <<~MD)
      ---
      title: Hero post
      date: 2026-01-01
      image: hero.jpg
      ---
      ![Inline hero](hero.jpg)
    MD

    # Generate a real test image inside the bundle.
    image = ::Vips::Image.gaussnoise(1600, 900, sigma: 30, mean: 128)
    image = image.bandjoin([
      ::Vips::Image.gaussnoise(1600, 900, sigma: 30, mean: 100),
      ::Vips::Image.gaussnoise(1600, 900, sigma: 30, mean: 80)
    ]).cast(:uchar)
    image.write_to_file(File.join(bundle, 'hero.jpg'), Q: 90)
  end

  def test_bundle_image_gets_variants_generated_on_build
    output_dir = File.join(@tmpdir, '_site')

    with_env(
      'ABQARI_SITE_ROOT' => @tmpdir,
      'ABQARI_OUTPUT_DIR' => output_dir,
      'ABQARI_ALLOW_EXTERNAL_OUTPUT' => 'true',
      'ABQARI_ENV' => 'production'
    ) do
      # Reset cached config so the new ENV takes effect.
      site = Abqari::Site.new
      site.build
    end

    # Verify variants land alongside the post HTML.
    bundle_output_dir = File.join(output_dir, 'posts', 'hero')
    variants = Dir.glob(File.join(bundle_output_dir, 'hero-*'))
    assert variants.size >= 3, "expected multiple variants, got: #{variants.inspect}"

    # We should see AVIF, WebP, and JPEG variants.
    assert variants.any? { |v| v.end_with?('.avif') }
    assert variants.any? { |v| v.end_with?('.webp') }
    assert variants.any? { |v| v.end_with?('.jpg') }
  end

  def test_bundle_image_img_tag_rewritten_to_picture
    output_dir = File.join(@tmpdir, '_site')

    with_env(
      'ABQARI_SITE_ROOT' => @tmpdir,
      'ABQARI_OUTPUT_DIR' => output_dir,
      'ABQARI_ALLOW_EXTERNAL_OUTPUT' => 'true',
      'ABQARI_ENV' => 'production'
    ) do
      Abqari::Site.new.build
    end

    html = File.read(File.join(output_dir, 'posts', 'hero', 'index.html'), encoding: 'UTF-8')

    # The post body's `![](hero.jpg)` should have been rewritten to a
    # full <picture> element pointing at the optimised variants.
    assert_match %r{<picture>.*<source type="image/avif".*<source type="image/webp".*<img}m, html,
                 'post body image should have become a <picture> block'
    # The original /posts/hero/hero.jpg src should no longer appear
    # in the rewritten <img> (it's been replaced with the fingerprinted
    # fallback variant).
    refute_match %r{<img src="/posts/hero/hero\.jpg"}, html
  end

  private

  def with_env(env)
    old = {}
    env.each { |k, v| old[k] = ENV[k]; ENV[k] = v }
    yield
  ensure
    old.each { |k, v| ENV[k] = v }
  end
end

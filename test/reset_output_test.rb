# frozen_string_literal: true

require_relative 'test_helper'
require 'tmpdir'

# Containment tests for Site#reset_output. A typo or hostile CI config
# setting ABQARI_OUTPUT_DIR to a path outside site_root must NOT silently
# wipe that target.
class ResetOutputTest < Minitest::Test
  def setup
    @prev_output = ENV['ABQARI_OUTPUT_DIR']
    @prev_root   = ENV['ABQARI_SITE_ROOT']
    @prev_allow  = ENV['ABQARI_ALLOW_EXTERNAL_OUTPUT']
    # test_helper.rb sets ABQARI_ALLOW_EXTERNAL_OUTPUT=true globally so the
    # main suite can build into a tmpdir. We're testing the gate itself,
    # so clear it for these cases and let each test opt in as needed.
    ENV.delete('ABQARI_ALLOW_EXTERNAL_OUTPUT')
    @tmpdir = Dir.mktmpdir('abqari-reset-test')
    ENV['ABQARI_SITE_ROOT'] = @tmpdir
  end

  def teardown
    ENV['ABQARI_OUTPUT_DIR'] = @prev_output
    ENV['ABQARI_SITE_ROOT']  = @prev_root
    ENV['ABQARI_ALLOW_EXTERNAL_OUTPUT'] = @prev_allow
    FileUtils.rm_rf(@tmpdir)
  end

  # ArtifactWriter against a bare site — we want to exercise the
  # containment logic without booting the full Site (which loads
  # config, validates, applies timezone, etc.).
  def reset_output!
    site = Abqari::Site.allocate
    site.instance_variable_set(:@site_root, @tmpdir)
    site.define_singleton_method(:output_dir) { ENV['ABQARI_OUTPUT_DIR'] }
    Abqari::ArtifactWriter.new(site).reset_output
  end

  def test_reset_output_under_site_root_succeeds
    ENV['ABQARI_OUTPUT_DIR'] = File.join(@tmpdir, '_site')
    FileUtils.mkdir_p(ENV['ABQARI_OUTPUT_DIR'])
    File.write(File.join(ENV['ABQARI_OUTPUT_DIR'], 'old.html'), 'x')

    reset_output!
    refute File.exist?(File.join(ENV['ABQARI_OUTPUT_DIR'], 'old.html'))
    assert Dir.exist?(ENV['ABQARI_OUTPUT_DIR'])
  end

  def test_reset_output_refuses_filesystem_root
    ENV['ABQARI_OUTPUT_DIR'] = '/'
    assert_raises(Abqari::PathSafe::Error) { reset_output! }
  end

  def test_reset_output_refuses_home_dir
    ENV['ABQARI_OUTPUT_DIR'] = File.expand_path('~')
    assert_raises(Abqari::PathSafe::Error) { reset_output! }
  end

  def test_reset_output_refuses_path_outside_site_root
    external = Dir.mktmpdir('abqari-external-target')
    begin
      ENV['ABQARI_OUTPUT_DIR'] = external
      File.write(File.join(external, 'precious.txt'), 'do not delete')
      assert_raises(Abqari::PathSafe::Error) { reset_output! }
      assert File.exist?(File.join(external, 'precious.txt')),
             'External directory must NOT be wiped'
    ensure
      FileUtils.rm_rf(external)
    end
  end

  def test_reset_output_allows_external_dir_when_escape_hatch_set
    external = Dir.mktmpdir('abqari-external-allowed')
    begin
      ENV['ABQARI_OUTPUT_DIR'] = external
      ENV['ABQARI_ALLOW_EXTERNAL_OUTPUT'] = 'true'
      File.write(File.join(external, 'will_be_wiped.txt'), 'x')
      reset_output!
      refute File.exist?(File.join(external, 'will_be_wiped.txt'))
      assert Dir.exist?(external)
    ensure
      FileUtils.rm_rf(external)
    end
  end
end

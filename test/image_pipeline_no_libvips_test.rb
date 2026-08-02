# frozen_string_literal: true

require_relative 'test_helper'
require 'open3'
require 'tmpdir'

# The no-libvips machine — the passthrough fallback's entire audience.
# ruby-vips installs fine without the C library, and `require 'vips'`
# defines the Vips module BEFORE the FFI bind raises LoadError. After
# the engine rescues that, `defined?(::Vips)` is true while
# Vips::Image/Vips::Error don't exist — a state no dev machine or CI
# runner reproduces (both have libvips), which is how a NameError in
# format probing shipped and killed every build on clean installs.
#
# The test recreates the partial-load state in a subprocess: a fake
# `vips.rb` shadows the real gem, defines the bare module, then raises
# LoadError — exactly ruby-vips's failure shape.
class ImagePipelineNoLibvipsTest < Minitest::Test
  ENGINE_ROOT = File.expand_path('..', __dir__)

  def test_pipeline_initialises_and_degrades_without_libvips
    Dir.mktmpdir('abqari-novips') do |dir|
      File.write(File.join(dir, 'vips.rb'), <<~RUBY)
        module Vips
        end
        raise LoadError, 'simulated: libvips shared library not found'
      RUBY

      script = <<~RUBY
        require 'abqari'
        require 'ostruct'

        abort 'simulation failed: Vips fully loaded' if ::Vips.respond_to?(:version_string)
        abort 'simulation failed: Vips module missing' unless defined?(::Vips)

        site = OpenStruct.new(site_root: Dir.pwd, engine_root: Dir.pwd)
        site.define_singleton_method(:config) { { 'images' => { 'optimise' => true } } }

        pipeline = Abqari::ImagePipeline.new(site)   # ran format pruning
        abort 'expected passthrough (no backend)' if pipeline.enabled?
        puts 'DEGRADED_OK'
      RUBY

      # Empty PATH: the host's vips/magick CLIs would otherwise give the
      # pipeline a shell backend, and the state under test is no-backend.
      # RbConfig.ruby is an absolute path, so the subprocess still starts.
      out, status = Open3.capture2e(
        { 'PATH' => '' },
        RbConfig.ruby, '-I', dir, '-I', File.join(ENGINE_ROOT, 'lib'), '-e', script
      )
      assert status.success?, "pipeline crashed without libvips:\n#{out}"
      assert_includes out, 'DEGRADED_OK'
    end
  end
end

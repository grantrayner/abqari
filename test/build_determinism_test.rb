# frozen_string_literal: true

require_relative 'test_helper'
require 'digest'

# Build determinism. Two back-to-back builds against the same content
# must produce byte-identical output. Filesystem iteration order (most
# notably `Dir.glob` without `.sort`) is the most common source of
# non-determinism — same content, different bytes-on-disk depending on
# inode order, which produces noisy diffs on every deploy.
#
# This test isn't comprehensive — it can't cover every corner the
# build touches — but it catches the regression class: a new
# `Dir.glob(...).each` somewhere that affects output bytes.
class BuildDeterminismTest < Minitest::Test
  def test_two_consecutive_builds_produce_identical_output
    site1 = Abqari::Site.new
    site1.build
    snapshot1 = hash_output(site1.output_dir)

    site2 = Abqari::Site.new
    site2.build
    snapshot2 = hash_output(site2.output_dir)

    diffs = snapshot1.to_a - snapshot2.to_a
    extras = snapshot2.to_a - snapshot1.to_a
    refute (diffs.any? || extras.any?),
           "build is non-deterministic.\nFiles in build-1 but not build-2:\n  #{diffs.first(5).inspect}\nFiles in build-2 but not build-1:\n  #{extras.first(5).inspect}"
  end

  private

  # Map of relative path → SHA1 of file contents. Identical maps mean
  # identical builds, regardless of inode / mtime / iteration order.
  def hash_output(root)
    Dir.glob(File.join(root, '**', '*')).each_with_object({}) do |path, h|
      next if File.directory?(path)

      rel = path.sub("#{root}/", '')
      h[rel] = Digest::SHA1.file(path).hexdigest
    end
  end
end

# frozen_string_literal: true

# The version constant lives alone, in a file with NO requires, because
# `abqari.gemspec` loads it to read `Abqari::VERSION`.
#
# The gemspec used to `require_relative 'lib/abqari'` instead, which
# pulls in the whole engine — and with it erubi, commonmarker, rouge and
# webrick. That works locally (those gems are already installed) but
# breaks any git or path source: Bundler evaluates the gemspec BEFORE
# installing dependencies, so the requires blow up with
# "cannot load such file -- erubi". Published gems are immune (their
# spec is pre-serialized into the .gem), which is exactly why the bug
# only surfaced on a clean CI/deploy builder.
#
# Keep this file dependency-free.
module Abqari
  VERSION = '1.1.0'
end

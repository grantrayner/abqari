# frozen_string_literal: true

module Abqari
  # Path-safety helpers for build-time file I/O.
  #
  # The engine joins user-controlled input (frontmatter `permalink:`,
  # `ABQARI_OUTPUT_DIR`, slugs, bundle filenames) into filesystem paths.
  # Plain `File.join` will happily build `_site/../../etc/passwd` from
  # an attacker-controlled segment — a hostile or careless content
  # contributor can use that to write outside the build's output dir.
  #
  # `join_under` expands the candidate, then re-checks that it sits
  # under the base. Anything that escapes (via `..`, an absolute
  # segment, or a symlink) raises rather than silently writing the
  # wrong file.
  #
  # `assert_under` is the assertion-only form for paths that were
  # already computed elsewhere (e.g. an `output_dir` that came in from
  # an env var, where we want to guard the deletion site, not rebuild
  # the path).
  module PathSafe
    class Error < StandardError; end

    module_function

    # Join `segments` under `base` and refuse anything that escapes the
    # base directory. Returns the expanded absolute path.
    #
    #   PathSafe.join_under('/site/_site', 'posts', 'hello', 'index.html')
    #   # => "/site/_site/posts/hello/index.html"
    #
    #   PathSafe.join_under('/site/_site', '../etc/passwd')
    #   # => raises Abqari::PathSafe::Error
    #
    # Empty / nil segments are tolerated (treated as no-op), so callers
    # can pass through optional path parts without pre-checking.
    def join_under(base, *segments)
      base_real = File.expand_path(base.to_s)
      clean     = segments.flatten.compact.map(&:to_s).reject(&:empty?)
      candidate = File.expand_path(File.join(base_real, *clean))

      return candidate if candidate == base_real
      return candidate if candidate.start_with?(base_real + File::SEPARATOR)

      raise Error,
            "path traversal blocked: #{clean.inspect} resolves to #{candidate}, " \
            "which is outside #{base_real}"
    end

    # Raise unless `path` is `base` or a descendant of it. Use at sites
    # that already have a fully-computed path and need a containment
    # check before a destructive operation (e.g. `rm_rf`).
    def assert_under(base, path)
      base_real = File.expand_path(base.to_s)
      path_real = File.expand_path(path.to_s)
      return if path_real == base_real
      return if path_real.start_with?(base_real + File::SEPARATOR)

      raise Error, "containment check failed: #{path_real} is not under #{base_real}"
    end
  end
end

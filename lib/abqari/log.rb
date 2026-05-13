# frozen_string_literal: true

module Abqari
  # Tiny leveled logger. No stdlib `Logger` ceremony — one module, four
  # severity methods, level filtered at call time. Configured via the
  # ABQARI_LOG env var (debug / info / warn / error). Default: info.
  #
  # Why not `Logger`? Logger optimises for long-running processes that
  # need rotation, formatters, custom output streams. Abqari is a build
  # tool — output is short, lives in CI logs, and the operator wants:
  #
  #   - info  → user-facing progress (`Built 108 pages…`)
  #   - debug → development triage  (`ABQARI_LOG=debug bin/build`)
  #   - warn  → recoverable issue   (`Folio fetch failed — using cache`)
  #   - error → fatal               (`render failed: …`)
  #
  # Stderr for everything except info — info goes to stdout so it can
  # be redirected separately. Matches the established convention from
  # most Unix build tools.
  #
  # No file output, no rotation, no formatters. Yagni.
  module Log
    LEVELS = { debug: 0, info: 1, warn: 2, error: 3 }.freeze

    @level = (LEVELS[(ENV['ABQARI_LOG'] || 'info').to_sym] || LEVELS[:info])
    @mutex = Mutex.new

    class << self
      attr_accessor :level

      def level_name
        LEVELS.key(@level) || :info
      end

      def debug(msg) = emit(:debug, msg, $stderr)
      def info(msg)  = emit(:info, msg, $stdout)
      def warn(msg)  = emit(:warn, msg, $stderr)
      def error(msg) = emit(:error, msg, $stderr)

      private

      def emit(severity, msg, stream)
        return if LEVELS[severity] < @level

        # Mutex so concurrent threads (parallel page rendering) don't
        # interleave a single log line.
        @mutex.synchronize { stream.puts(format_line(severity, msg)) }
      end

      def format_line(severity, msg)
        # Suppress the prefix for plain `info` — that's where the
        # existing user-facing build output lives, and operators expect
        # `Built 108 pages` not `[info] Built 108 pages`. Other levels
        # get a prefix so warnings/errors are scannable in CI logs.
        return msg.to_s if severity == :info

        "[#{severity}] #{msg}"
      end
    end
  end
end

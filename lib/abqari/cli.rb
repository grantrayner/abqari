# frozen_string_literal: true

require_relative 'cli/new'

module Abqari
  # Tiny subcommand dispatcher for the `abqari` global executable.
  #
  # The dispatcher itself stays small on purpose: parse the leading
  # subcommand word, hand off to its own class. Subcommands live one
  # file each under `lib/abqari/cli/`. Each one accepts an argv tail
  # and returns true on success / false on failure (or raises).
  #
  # Adding a new top-level command:
  #   1. Create `lib/abqari/cli/<name>.rb` with `Abqari::CLI::<Name>`
  #      exposing a `.run(argv)` class method.
  #   2. Add it to `COMMANDS` below.
  #
  # No bin/* in scaffolded sites uses this dispatcher — site-level
  # commands (`build`, `serve`, `audit`, …) are independent thin
  # wrappers that require `'abqari'` and call the engine directly.
  # The global `abqari` binary is intentionally limited to operations
  # that don't run inside an existing site (the main one being
  # `new <projectname>` to bootstrap a fresh site).
  module CLI
    COMMANDS = {
      'new'     => 'Abqari::CLI::New',
      'version' => :builtin_version,
      '-v'      => :builtin_version,
      '--version' => :builtin_version,
      'help'    => :builtin_help,
      '-h'      => :builtin_help,
      '--help'  => :builtin_help
    }.freeze

    USAGE = <<~USAGE
      Usage: abqari <command> [options]

      Commands:
        new <projectname>    Scaffold a new Abqari site in ./<projectname>/
        version              Print the engine version
        help                 Show this message

      Site-level commands (build, serve, audit, …) live inside each
      scaffolded site as `bin/*` scripts — run them from the site's
      root directory, not via this global binary. Run `abqari new`
      to bootstrap a new site.
    USAGE

    class << self
      # Parse argv's leading word + dispatch. Returns true on success,
      # false on failure (or `exit(1)` after writing to $stderr for
      # usage errors).
      def run(argv)
        cmd, *rest = argv
        return print_help if cmd.nil? || cmd == ''

        target = COMMANDS[cmd]
        case target
        when :builtin_version then print_version
        when :builtin_help    then print_help
        when String           then dispatch(target, rest)
        else
          warn "Unknown command: #{cmd.inspect}"
          warn ''
          warn USAGE
          false
        end
      end

      private

      def dispatch(class_name, argv)
        Object.const_get(class_name).run(argv)
      end

      def print_version
        puts "abqari #{Abqari::VERSION}"
        true
      end

      def print_help
        puts USAGE
        true
      end
    end
  end
end

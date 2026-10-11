# frozen_string_literal: true

# The engine itself, not just the subcommands — CLI::New pins the
# scaffolded Gemfile to Abqari::VERSION, and `abqari version` prints it.
require_relative '../abqari'
require_relative 'cli/new'
require_relative 'cli/theme'
require_relative 'cli/headers'

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
      'theme'   => 'Abqari::CLI::Theme',
      'headers' => 'Abqari::CLI::Headers',
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
        theme eject <name>   Copy an engine theme into this site for editing
        headers [path]       Print the built _site/_headers as Render header rules
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

      # Every subcommand's flag parsing funnels through here, so a bad
      # flag is reported once, the same way, for all of them.
      #
      # `OptionParser#parse` raises on an unknown flag, and nothing
      # caught it — so `abqari new --bloank mysite`, a one-character
      # typo of a real flag, met a new user with a six-frame backtrace.
      # Catching centrally (rather than in each subcommand) means a
      # future subcommand gets the behaviour for free.
      def dispatch(class_name, argv)
        Object.const_get(class_name).run(normalize_argv(argv))
      rescue OptionParser::ParseError => e
        warn e.message
        warn ''
        warn "Run `abqari #{command_word(class_name)} --help` for the available options."
        false
      end

      def command_word(class_name)
        COMMANDS.key(class_name) || ''
      end

      # Force ARGV to UTF-8 so non-ASCII arguments survive.
      #
      # Ruby tags ARGV with the locale encoding. Under a C/POSIX locale
      # — Docker images, cron, some CI runners, `env -i` — that's
      # US-ASCII or ASCII-8BIT, and the first `File.expand_path` or ERB
      # render against a UTF-8 template raised
      # `Encoding::CompatibilityError`. `abqari new café` then died
      # PART WAY THROUGH scaffolding, leaving a half-written directory
      # that the non-empty preflight refused to overwrite on retry.
      #
      # The bytes are already correct; only the tag is wrong. Anything
      # that isn't valid UTF-8 is left alone for the subcommand to
      # reject with a real message.
      def normalize_argv(argv)
        argv.map do |arg|
          candidate = arg.dup.force_encoding(Encoding::UTF_8)
          candidate.valid_encoding? ? candidate : arg
        end
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

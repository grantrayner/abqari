# frozen_string_literal: true

require_relative 'test_helper'
require 'stringio'

# `Server::QuietLog` is WEBrick's stderr logger with one behaviour
# changed: exceptions that only mean "the peer hung up" don't get
# logged. Every open browser tab holds an SSE connection to
# `/__reload__`, and a navigation drops that socket without a clean
# close — WEBrick raises ECONNRESET from inside its own request loop,
# above where the SSE handler could rescue it, and logs a full
# backtrace. One per tab per navigation, all of it noise.
#
# The risk in filtering a logger is filtering too much, so the tests
# below pin both halves: disconnects are dropped, and everything else
# still gets through.
class ServerQuietLogTest < Minitest::Test
  def setup
    @sink = StringIO.new
    @log  = Abqari::Server::QuietLog.new(@sink)
  end

  def logged
    @sink.string
  end

  # WEBrick only ever logs exceptions it caught, and `BasicLog#format`
  # calls `arg.backtrace.join` unconditionally — so a bare `.new`
  # exception (backtrace still nil) would blow up in the logger rather
  # than exercise it. Raise and rescue to get a realistic object.
  def raised(klass, message)
    raise klass, message
  rescue klass => e
    e
  end

  # The reported case: WEBrick calls `@logger.error ex` with the raw
  # exception object when one escapes a request thread.
  def test_suppresses_client_disconnect_exceptions
    Abqari::Server::QuietLog::CLIENT_DISCONNECTS.each do |klass|
      @sink.truncate(0)
      @sink.rewind
      @log.error(klass.new('Connection reset by peer @ io_fillbuf - fd:13'))
      assert_empty logged, "#{klass} should not be logged"
    end
  end

  # A subclass of a suppressed class is still a disconnect. `is_a?`
  # gives us this for free; the test exists so a future rewrite to
  # `instance_of?` or a class-name comparison fails here.
  def test_suppresses_subclasses_of_client_disconnects
    subclass = Class.new(Errno::ECONNRESET)
    @log.error(subclass.new('reset'))
    assert_empty logged
  end

  def test_logs_other_exceptions_in_full
    @log.error(raised(RuntimeError, 'layout not found'))

    assert_includes logged, 'RuntimeError'
    assert_includes logged, 'layout not found'
  end

  # Errno::ENOENT is an Errno like the suppressed ones but means a
  # missing file — a real fault when it escapes a request thread.
  def test_logs_unrelated_errno_exceptions
    @log.error(raised(Errno::ENOENT, '_site/index.html'))

    assert_includes logged, 'ENOENT'
  end

  # Suppression keys off the exception CLASS, never the message.
  # A genuine bug that happens to mention a reset connection must
  # still be reported.
  def test_does_not_filter_on_message_text
    @log.error(raised(RuntimeError, 'Connection reset by peer @ io_fillbuf - fd:13'))

    assert_includes logged, 'Connection reset by peer'
  end

  # WEBrick's `ServerError` branch passes a pre-formatted String
  # rather than an exception. Strings are never suppressed.
  def test_logs_string_messages
    @log.error('Errno::ECONNRESET: Connection reset by peer')

    assert_includes logged, 'ECONNRESET'
  end

  # Only `error` is overridden — the other levels must be untouched,
  # including for a disconnect class. WEBrick's default level is INFO,
  # so both of these are emitted.
  def test_other_log_levels_are_unaffected
    @log.warn(raised(Errno::ECONNRESET, 'reset'))
    @log.info('Abqari serving on http://127.0.0.1:4000')

    assert_includes logged, 'ECONNRESET'
    assert_includes logged, 'Abqari serving'
  end

  def test_is_a_webrick_log
    # WEBrick type-checks nothing, but `:Logger` has to quack like one:
    # it receives error/warn/info/debug plus the `debug?`-style guards.
    assert_kind_of WEBrick::Log, @log
    %i[error warn info debug error? warn? info? debug?].each do |m|
      assert_respond_to @log, m
    end
  end
end

# The logger a Server picks when the caller doesn't supply one.
class ServerDefaultLoggerTest < Minitest::Test
  def setup
    @prev_verbose = ENV['ABQARI_VERBOSE_LOG']
    @site = Abqari::Site.new
  end

  def teardown
    ENV['ABQARI_VERBOSE_LOG'] = @prev_verbose
  end

  def logger_for(server)
    server.instance_variable_get(:@logger)
  end

  def test_defaults_to_quiet_log
    ENV.delete('ABQARI_VERBOSE_LOG')

    assert_instance_of Abqari::Server::QuietLog, logger_for(Abqari::Server.new(@site))
  end

  def test_verbose_env_var_restores_stock_webrick_logging
    ENV['ABQARI_VERBOSE_LOG'] = 'true'
    logger = logger_for(Abqari::Server.new(@site))

    assert_instance_of WEBrick::Log, logger
    refute_instance_of Abqari::Server::QuietLog, logger
  end

  # Matches the `== 'true'` convention used by ABQARI_STRICT_CONFIG,
  # ABQARI_INCLUDE_DRAFTS and the rest — '1' and 'yes' are not truthy.
  def test_verbose_env_var_only_accepts_the_string_true
    ['1', 'yes', 'TRUE', ''].each do |value|
      ENV['ABQARI_VERBOSE_LOG'] = value

      assert_instance_of Abqari::Server::QuietLog, logger_for(Abqari::Server.new(@site)),
                         "ABQARI_VERBOSE_LOG=#{value.inspect} should not enable verbose logging"
    end
  end

  # An explicit `logger:` still wins over both defaults — this is how
  # server_sse_test silences WEBrick entirely.
  def test_explicit_logger_overrides_the_default
    injected = WEBrick::Log.new(File::NULL)

    assert_same injected, logger_for(Abqari::Server.new(@site, logger: injected))
  end
end

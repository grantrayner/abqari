# frozen_string_literal: true

require_relative 'test_helper'

# Port resolution: explicit argument, then ABQARI_PORT, then the default.
#
# The parsing is strict on purpose, and the tests below are mostly about the
# ways `String#to_i` would have been wrong. "abc".to_i is 0, and WEBrick reads
# port 0 as "bind any free port" — so a typo wouldn't fail, it would start a
# server on a port the operator has no way to guess. That's the failure this
# whole class of test exists to prevent.
class ServerPortTest < Minitest::Test
  def setup
    @prev = ENV['ABQARI_PORT']
    @site = Abqari::Site.new
  end

  def teardown
    # nil-assigning removes the key, which is what "unset" has to mean here —
    # leaving it as "" would make later tests see an empty override.
    ENV['ABQARI_PORT'] = @prev
  end

  def port_of(server)
    server.instance_variable_get(:@port)
  end

  def build(env: :unset, **kwargs)
    env == :unset ? ENV.delete('ABQARI_PORT') : ENV['ABQARI_PORT'] = env
    Abqari::Server.new(@site, **kwargs)
  end

  # ── Resolution order ────────────────────────────────────────────────

  def test_defaults_to_4000
    assert_equal 4000, port_of(build)
    assert_equal Abqari::Server::DEFAULT_PORT, port_of(build)
  end

  def test_env_var_overrides_the_default
    assert_equal 4001, port_of(build(env: '4001'))
  end

  # The suite binds real sockets on ports it picks itself. If an exported
  # ABQARI_PORT could override an explicit argument, every one of those tests
  # would fight for the same port the moment a developer set the variable in
  # their shell.
  def test_explicit_argument_beats_the_env_var
    assert_equal 5555, port_of(build(env: '4001', port: 5555))
  end

  def test_explicit_argument_beats_the_default
    assert_equal 5555, port_of(build(port: 5555))
  end

  # ── Strict parsing ──────────────────────────────────────────────────

  def test_non_numeric_raises_rather_than_binding_port_zero
    e = assert_raises(Abqari::UserError) { build(env: 'abc') }
    assert_match(/ABQARI_PORT/, e.message)
    assert_match(/not a number/, e.message)
  end

  # "4000x".to_i is 4000 — a typo that would otherwise work silently and
  # leave the operator believing the variable was read as written.
  def test_trailing_junk_raises
    assert_raises(Abqari::UserError) { build(env: '4000x') }
  end

  def test_out_of_range_raises_with_the_range_named
    e = assert_raises(Abqari::UserError) { build(env: '99999') }
    assert_match(/out of range/, e.message)
    assert_match(/65535/, e.message)
  end

  # Port 0 is a valid number and a terrible answer: WEBrick treats it as
  # "any free port", so the server starts somewhere unguessable.
  def test_zero_is_rejected
    assert_raises(Abqari::UserError) { build(env: '0') }
  end

  def test_negative_is_rejected
    assert_raises(Abqari::UserError) { build(env: '-1') }
  end

  # ── Empty and whitespace ────────────────────────────────────────────

  # An exported-but-empty variable is what `export ABQARI_PORT=` leaves
  # behind, and it means "not set", not "port 0".
  def test_empty_string_falls_back_to_the_default
    assert_equal 4000, port_of(build(env: ''))
  end

  def test_whitespace_only_falls_back_to_the_default
    assert_equal 4000, port_of(build(env: '   '))
  end

  def test_surrounding_whitespace_is_tolerated
    assert_equal 4001, port_of(build(env: ' 4001 '))
  end

  # ── Boundaries ──────────────────────────────────────────────────────

  def test_accepts_the_range_boundaries
    assert_equal 1, port_of(build(env: '1'))
    assert_equal 65_535, port_of(build(env: '65535'))
  end

  def test_range_boundary_plus_one_is_rejected
    assert_raises(Abqari::UserError) { build(env: '65536') }
  end
end

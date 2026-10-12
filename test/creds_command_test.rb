# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"
require "stringio"

# `nabu creds` — the ONE write gateway of local/config/credentials.yml (the
# local/config write-through law). `set NAME` prompts (the secret with echo
# off, so it never enters shell history) or reads `user\npassword\n` with
# --stdin for loop-fired sets; `list` shows names + ages only. There is
# deliberately no `show`. Every case runs against a throwaway root.
class CredsCommandTest < Minitest::Test
  SECRET = "pa55-w0rd-rotates"

  def test_stdin_set_stores_the_entry_mode_600_and_never_echoes_the_secret
    with_creds_env do |config|
      out, err, status = with_stdin("member\n#{SECRET}\n", tty: false) do
        with_config(config) { run_cli(%w[creds set titus --stdin]) }
      end
      assert_nil status, err
      assert_match(/stored\s+titus/, out)
      refute_includes out + err, SECRET, "the gateway never prints the secret"
      entry = Nabu::Credentials.new(path: config.credentials_path)["titus"]
      assert_equal "member", entry.user
      assert_equal SECRET, entry.password
      assert_equal 0o600, File.stat(config.credentials_path).mode & 0o777
    end
  end

  def test_re_set_is_idempotent_and_a_rotation_updates
    with_creds_env do |config|
      with_stdin("member\n#{SECRET}\n", tty: false) { with_config(config) { run_cli(%w[creds set titus --stdin]) } }
      bytes = File.binread(config.credentials_path)
      out, = with_stdin("member\n#{SECRET}\n", tty: false) do
        with_config(config) { run_cli(%w[creds set titus --stdin]) }
      end
      assert_match(/unchanged\s+titus/, out)
      assert_equal bytes, File.binread(config.credentials_path)

      out, = with_stdin("member\nnew-#{SECRET}\n", tty: false) do
        with_config(config) { run_cli(%w[creds set titus --stdin]) }
      end
      assert_match(/updated\s+titus/, out)
      assert_equal "new-#{SECRET}", Nabu::Credentials.new(path: config.credentials_path)["titus"].password
      assert_equal 0o600, File.stat(config.credentials_path).mode & 0o777
    end
  end

  def test_interactive_set_prompts_with_the_secret_hidden
    with_creds_env do |config|
      stdin = StringIO.new("member\n#{SECRET}\n")
      noecho_calls = []
      stdin.define_singleton_method(:tty?) { true }
      stdin.define_singleton_method(:noecho) do |&block|
        noecho_calls << true
        block.call(self)
      end
      out, err, status = with_stdin_io(stdin) { with_config(config) { run_cli(%w[creds set titus]) } }
      assert_nil status, err
      # The user-prompt ECHO is environment-dependent (Thor's ask writes
      # it locally but not under a CI pseudo-stdin) — the test pins what
      # matters: the hidden read, the redaction, and the stored result.
      assert_match(/password.*hidden/i, out)
      assert_equal 1, noecho_calls.size, "the secret is read with echo off"
      refute_includes out, SECRET
      assert_equal SECRET, Nabu::Credentials.new(path: config.credentials_path)["titus"].password
    end
  end

  def test_interactive_set_without_a_tty_refuses_and_points_at_stdin
    with_creds_env do |config|
      _out, err, status = with_stdin("", tty: false) { with_config(config) { run_cli(%w[creds set titus]) } }
      assert_equal 1, status
      assert_match(/--stdin/, err)
      refute_path_exists config.credentials_path
    end
  end

  def test_stdin_set_with_a_missing_password_refuses
    with_creds_env do |config|
      _out, err, status = with_stdin("member\n", tty: false) do
        with_config(config) { run_cli(%w[creds set titus --stdin]) }
      end
      assert_equal 1, status
      assert_match(/password or a token is required/, err)
      refute_path_exists config.credentials_path
    end
  end

  def test_list_shows_names_and_ages_only
    with_creds_env do |config|
      Nabu::Credentials.new(path: config.credentials_path)
                       .set!("titus", user: "member", password: SECRET, now: Time.now - (3 * 86_400))
      out, _err, status = with_config(config) { run_cli(%w[creds list]) }
      assert_nil status
      assert_match(/titus\s+updated \d{4}-\d{2}-\d{2} \(3 days ago\)/, out)
      refute_includes out, SECRET
      refute_includes out, "member", "not even the user name is shown"
    end
  end

  def test_list_names_a_declared_credential_with_nothing_stored
    with_creds_env(sources: <<~YAML) do |config|
      gated:
        adapter: TestAdapter
        wired: false
        credentials: titus
    YAML
      out, = with_config(config) { run_cli(%w[creds list]) }
      assert_match(%r{titus\s+MISSING — needed by gated \(bin/nabu creds set titus\)}, out)
    end
  end

  def test_list_on_an_empty_store_is_honest
    with_creds_env do |config|
      out, _err, status = with_config(config) { run_cli(%w[creds list]) }
      assert_nil status
      assert_match(/no credentials stored/, out)
    end
  end

  def test_there_is_no_show_command
    out, = run_cli(%w[help creds])
    assert_match(/creds set/, out)
    assert_match(/creds list/, out)
    refute_match(/creds show/, out)
  end

  def test_sync_of_a_credentials_source_with_nothing_stored_refuses_before_the_grant_prompt
    with_creds_env(sources: <<~YAML) do |config|
      gated:
        adapter: TestAdapter
        wired: false
        credentials: titus
    YAML
      _out, err, status = with_config(config) { run_cli(%w[sync gated]) }
      assert_equal 1, status
      assert_includes err, "credentials required: run bin/nabu creds set titus"
    end
  end

  private

  def with_creds_env(sources: "# none\n")
    Dir.mktmpdir("nabu-creds-cli") do |root|
      path = File.join(root, "config", "sources.yml")
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, sources)
      config = Nabu::Config.new(canonical_dir: File.join(root, "canonical"), db_dir: File.join(root, "db"),
                                sources_path: path, config_path: File.join(root, "config", "nabu.yml"))
      yield config
    end
  end

  def with_stdin(text, tty:, &)
    io = StringIO.new(text)
    io.define_singleton_method(:tty?) { tty }
    with_stdin_io(io, &)
  end

  def with_stdin_io(io)
    original = $stdin
    $stdin = io
    yield
  ensure
    $stdin = original
  end

  def with_config(config)
    original = Nabu::Config.method(:load)
    Nabu::Config.define_singleton_method(:load) { |*, **| config }
    yield
  ensure
    Nabu::Config.define_singleton_method(:load, original)
  end

  def run_cli(argv)
    status = nil
    out, err = capture_io do
      exc = begin
        Nabu::CLI.start(argv)
        nil
      rescue SystemExit => e
        e
      end
      status = exc&.status
    end
    [out, err, status]
  end
end

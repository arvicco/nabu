# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# Nabu::ToolBootstrap (owner rule 2026-09-03: external-tool installs are
# tracked rake tasks, one per capability, idempotent). The suite injects
# a fake shell and downloader — no python, no network, ever.
class ToolBootstrapTest < Minitest::Test
  FakeShell = Struct.new(:calls, :installed) do
    def run(*argv)
      calls << argv
      program = File.basename(argv.first.to_s)
      if program == "pip" && argv[1] == "show"
        raise Nabu::Shell::Error.new("not installed", status: 1, stderr: "") \
          unless installed.include?(argv[2])
      elsif argv.first == "python3" && argv[1] == "-m" && argv[2] == "venv"
        bin = File.join(argv[3], "bin")
        FileUtils.mkdir_p(bin)
        File.write(File.join(bin, "python"), "#!/bin/sh\n")
        FileUtils.chmod(0o755, File.join(bin, "python"))
        FileUtils.touch(File.join(bin, "pip"))
      elsif argv.first == "tar"
        dir = argv[argv.index("-C") + 1]
        File.write(File.join(dir, "vec0.dylib"), "fake dylib")
      end
      ""
    end
  end

  def setup
    @home = Dir.mktmpdir
    @out = StringIO.new
    @shell = FakeShell.new([], [])
  end

  def teardown
    FileUtils.remove_entry(@home)
  end

  def bootstrap(downloader: nil, platform: "arm64-darwin25")
    Nabu::ToolBootstrap.new(home: @home, shell: @shell, out: @out, platform: platform,
                            downloader: downloader || proc { |_url, dest| File.write(dest, "x") })
  end

  def good_downloader
    # A downloader whose payload matches a REAL pinned sha: patch the pin
    # instead — tests stub the constant via a payload-derived pin below.
    proc { |_url, dest| File.write(dest, "tarball-bytes") }
  end

  def with_pinned_sha(payload = "tarball-bytes")
    sha = Digest::SHA256.hexdigest(payload)
    original = Nabu::ToolBootstrap::VEC_SHA256
    Nabu::ToolBootstrap.send(:remove_const, :VEC_SHA256)
    Nabu::ToolBootstrap.const_set(:VEC_SHA256, original.merge("macos-aarch64" => sha).freeze)
    yield
  ensure
    Nabu::ToolBootstrap.send(:remove_const, :VEC_SHA256)
    Nabu::ToolBootstrap.const_set(:VEC_SHA256, original)
  end

  # -- embed! ---------------------------------------------------------------

  def test_embed_installs_everything_then_skips_everything
    with_pinned_sha do
      b = bootstrap(downloader: good_downloader)
      b.embed!

      assert File.executable?(File.join(@home, "venvs/embed/bin/python")), "venv created"
      assert File.exist?(File.join(@home, "tools/sqlite-vec/vec0.dylib")), "dylib installed"
      assert_includes @out.string, "sentence-transformers — installing"
      assert_includes @out.string, "sqlite-vec — installed"

      # Second run: model marker + package presence short-circuit; the
      # only shell traffic is the offline pip-show probe.
      @shell.installed << "sentence-transformers"
      FileUtils.mkdir_p(File.join(@home, "venvs/embed/models",
                                  "models--intfloat--multilingual-e5-base"))
      @out.truncate(0)
      @shell.calls.clear
      b.embed!
      assert_includes @out.string, "model intfloat/multilingual-e5-base — present, skipped",
                      "the marker path must match sentence-transformers' models--org--name layout"
      refute(@shell.calls.any? { |argv| argv.include?("install") }, "nothing reinstalled")
      refute_includes @out.string, "installing"
      refute_includes @out.string, "fetching", "no step re-pays its network cost"
    end
  end

  def test_sqlite_vec_refuses_a_sha_mismatch
    error = assert_raises(Nabu::Error) do
      bootstrap(downloader: proc { |_u, dest| File.write(dest, "tampered") }).embed!
    end
    assert_match(/sha mismatch.*refused/m, error.message)
    refute File.exist?(File.join(@home, "tools/sqlite-vec/vec0.dylib")),
           "an unverified binary is never installed"
  end

  def test_sqlite_vec_refuses_an_unpinned_platform
    error = assert_raises(Nabu::Error) { bootstrap(platform: "sparc-solaris").embed! }
    assert_match(/no pinned sqlite-vec sha/, error.message)
  end

  # -- stanza! / status -----------------------------------------------------

  def test_stanza_installs_venv_and_models
    b = bootstrap
    b.stanza!(lang: "la")
    assert File.executable?(File.join(@home, "venvs/stanza/bin/python"))
    assert(@shell.calls.any? { |argv| argv.any? { |a| a.include?("stanza.download") } },
           "the model fetch runs through the venv python")
  end

  def test_status_reports_installed_and_missing_truthfully
    board = bootstrap.status
    assert(board.values.all? { |state| state.start_with?("MISSING") }, "empty home = all missing")

    bootstrap.stanza!(lang: "la")
    FileUtils.mkdir_p(File.join(@home, "venvs/stanza/models"))
    board = bootstrap.status
    assert_match(/^installed/, board.fetch("stanza venv (silver lemmas)"))
    assert_match(/^installed/, board.fetch("stanza models"))
    assert_match(/^MISSING/, board.fetch("sqlite-vec 0.1.9 (search --similar scan engine)"))
  end
end

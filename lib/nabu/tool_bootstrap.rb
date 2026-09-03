# frozen_string_literal: true

require "digest"
require "fileutils"
require_relative "errors"
require_relative "shell"

module Nabu
  # Tracked, one-command bootstraps for the EXTERNAL tools Nabu's
  # enrichment lanes run on (owner rule 2026-09-03: tool installations
  # are rake tasks in the repo, never ad-hoc shell instructions handed
  # to a human). One task per capability:
  #
  #   rake tools:embed       the WHOLE semantic-search stack: venv +
  #                          sentence-transformers + the e5 model +
  #                          the sqlite-vec scan extension
  #   rake tools:stanza[la]  the silver-lemma stack: venv + stanza +
  #                          the language's models
  #   rake tools:status      what is installed, where, and what isn't
  #
  # Every step is IDEMPOTENT (present = announced skip, never
  # reinstalled), announced as it runs, and network-touching only when
  # something is actually missing — so re-running a task is always safe
  # and the task doubles as its own verifier. Tools live OUTSIDE the
  # repo and the permanent folders (~/.nabu/) — re-creatable from the
  # network, never data, never backed up (the P84-1 venv doctrine).
  # Downloads are integrity-pinned (VEC_SHA256): a moved release or a
  # tampered mirror fails loudly, never installs.
  #
  # The companion docs (docs/manual/embed-venv.md,
  # silver-lemma-venv.md) stay as the transparent human record of what
  # the tasks do; the tasks are the executable surface.
  class ToolBootstrap
    NABU_HOME = File.join(Dir.home, ".nabu")

    EMBED_VENV = File.join(NABU_HOME, "venvs", "embed")
    STANZA_VENV = File.join(NABU_HOME, "venvs", "stanza")
    VEC_DIR = File.join(NABU_HOME, "tools", "sqlite-vec")

    EMBED_MODEL_ID = "intfloat/multilingual-e5-base"

    # The pinned sqlite-vec release (the search --similar scan engine;
    # NOT a gem — the rubygems arm64-darwin build is a 2024 alpha
    # predating int8). Bumping the version means re-measuring every
    # sha (curl + shasum against the new release assets).
    VEC_VERSION = "0.1.9"
    # sha256 of each platform's loadable tarball, measured 2026-09-03
    # against the v0.1.9 GitHub release assets.
    VEC_SHA256 = {
      "macos-aarch64" => "8282126333399ddfe98bbbcc7a1936e7252625aac49df056a98be602e46bfd29",
      "macos-x86_64" => "53ad76e400786515e2edcaed2f01271dda846316390b761fadbd2dcf56aa4713",
      "linux-x86_64" => "b959baa1d8dc88861b1edb337b8587178cdcb12d60b4998f9d10b6a82052d5d7"
    }.freeze

    # +home:+ relocates every install root (tests use a tmpdir);
    # +shell:+ and +downloader:+ are the subprocess/network seams —
    # tests inject fakes, the suite never touches python or the
    # network. +out:+ receives the announcement lines.
    def initialize(home: NABU_HOME, shell: Nabu::Shell, downloader: nil, out: $stdout,
                   platform: RUBY_PLATFORM)
      @home = home
      @shell = shell
      @downloader = downloader || method(:curl_download)
      @out = out
      @platform = platform
    end

    def embed_venv = File.join(@home, "venvs", "embed")
    def stanza_venv = File.join(@home, "venvs", "stanza")
    def vec_dir = File.join(@home, "tools", "sqlite-vec")
    def vec_dylib = File.join(vec_dir, "vec0.#{@platform.include?('linux') ? 'so' : 'dylib'}")

    # The whole semantic-search stack, one call: venv, libraries, the
    # pre-fetched model, the scan extension. Safe to re-run any time.
    def embed!
      say "== nabu semantic-search tools (rake tools:embed) — idempotent, re-run freely"
      venv!(embed_venv, packages: ["sentence-transformers"])
      embed_model!
      sqlite_vec!
      say "== done — next: `bin/nabu embed --status` (census), then `caffeinate -i bin/nabu embed`"
    end

    # The silver-lemma stack for one stanza language (default the
    # Latin wave's "la").
    def stanza!(lang: "la")
      say "== nabu silver-lemma tools (rake tools:stanza) — idempotent, re-run freely"
      venv!(stanza_venv, packages: ["stanza==1.14.0"])
      stanza_model!(lang)
      say "== done — next: `bin/nabu lemma-enrich lat --dry-run`"
    end

    # The tool board: every known tool with its installed-or-not truth.
    def status
      {
        "embed venv (sentence-transformers)" => presence(python_for(embed_venv)),
        "embed model (#{EMBED_MODEL_ID})" => presence(embed_model_marker),
        "sqlite-vec #{VEC_VERSION} (search --similar scan engine)" => presence(vec_dylib),
        "stanza venv (silver lemmas)" => presence(python_for(stanza_venv)),
        "stanza models" => presence(File.join(stanza_venv, "models"))
      }
    end

    def print_status
      status.each { |tool, state| say format("%-52s %s", tool, state) }
    end

    private

    def say(line) = @out.puts(line)

    def presence(path)
      File.exist?(path) ? "installed  #{path}" : "MISSING    (#{path})"
    end

    def python_for(venv) = File.join(venv, "bin", "python")

    # venv + packages, each half skipped when already present. Package
    # presence is probed with `pip show` (quiet, offline).
    def venv!(venv, packages:)
      python = python_for(venv)
      if File.executable?(python)
        say "   venv #{venv} — present, skipped"
      else
        say "   venv #{venv} — creating (python3 -m venv)"
        @shell.run("python3", "-m", "venv", venv)
      end
      pip = File.join(venv, "bin", "pip")
      packages.each do |package|
        name = package.split("==").first
        if pip_installed?(pip, name)
          say "   #{name} — present, skipped"
        else
          say "   #{name} — installing (network)"
          @shell.run(pip, "install", package)
        end
      end
    end

    def pip_installed?(pip, name)
      @shell.run(pip, "show", name)
      true
    rescue Nabu::Shell::Error
      false
    end

    # The model prefetch: the workers run with downloads disabled, so
    # the model must be on disk before a campaign. Presence marker: the
    # model's directory inside the cache (sentence-transformers names it
    # models--<org>--<name>).
    def embed_model_marker
      # sentence-transformers cache layout: models--<org>--<name>
      # (gsub, not tr — tr maps single chars and would emit one dash;
      # caught live by tools:status on 2026-09-03).
      File.join(embed_venv, "models", "models--#{EMBED_MODEL_ID.gsub('/', '--')}")
    end

    def embed_model!
      if File.directory?(embed_model_marker)
        say "   model #{EMBED_MODEL_ID} — present, skipped"
        return
      end
      say "   model #{EMBED_MODEL_ID} — fetching (~1.1 GB, network)"
      script = <<~PY
        from sentence_transformers import SentenceTransformer
        SentenceTransformer(#{EMBED_MODEL_ID.inspect}, cache_folder=#{File.join(embed_venv, 'models').inspect})
      PY
      @shell.run(python_for(embed_venv), "-c", script)
    end

    def stanza_model!(lang)
      marker = File.join(stanza_venv, "models")
      if File.directory?(marker)
        say "   stanza models — present, skipped (#{marker})"
        return
      end
      say "   stanza #{lang} models — fetching (network)"
      script = <<~PY
        import stanza
        stanza.download(#{lang.inspect}, model_dir=#{marker.inspect}, processors="tokenize,pos,lemma")
      PY
      @shell.run(python_for(stanza_venv), "-c", script)
    end

    # The sqlite-vec loadable, integrity-pinned per platform. An
    # unpinned platform refuses loudly rather than installing an
    # unverified binary.
    def sqlite_vec!
      if File.exist?(vec_dylib)
        say "   sqlite-vec #{VEC_VERSION} — present, skipped"
        return
      end
      platform = vec_platform
      sha = VEC_SHA256[platform] or
        raise Nabu::Error, "no pinned sqlite-vec sha for platform #{platform.inspect} " \
                           "(#{RUBY_PLATFORM}) — measure the release asset's sha256 and add it " \
                           "to ToolBootstrap::VEC_SHA256"
      say "   sqlite-vec #{VEC_VERSION} (#{platform}) — downloading (network, sha-verified)"
      FileUtils.mkdir_p(vec_dir)
      tarball = File.join(vec_dir, "vec.tar.gz")
      @downloader.call(vec_url(platform), tarball)
      actual = Digest::SHA256.file(tarball).hexdigest
      unless actual == sha
        File.delete(tarball)
        raise Nabu::Error, "sqlite-vec download sha mismatch (got #{actual}, pinned #{sha}) — " \
                           "refused; the release asset moved or the download was corrupted"
      end
      @shell.run("tar", "xzf", tarball, "-C", vec_dir)
      File.delete(tarball)
      raise Nabu::Error, "sqlite-vec tarball held no #{File.basename(vec_dylib)}" unless File.exist?(vec_dylib)

      say "   sqlite-vec — installed at #{vec_dylib}"
    end

    def vec_platform
      case @platform
      when /arm64.*darwin|aarch64.*darwin/ then "macos-aarch64"
      when /x86_64.*darwin/ then "macos-x86_64"
      when /x86_64.*linux/ then "linux-x86_64"
      else @platform
      end
    end

    def vec_url(platform)
      "https://github.com/asg017/sqlite-vec/releases/download/v#{VEC_VERSION}/" \
        "sqlite-vec-#{VEC_VERSION}-loadable-#{platform}.tar.gz"
    end

    def curl_download(url, dest)
      @shell.run("curl", "-sSfL", "-o", dest, url)
    end
  end
end

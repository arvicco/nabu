# frozen_string_literal: true

require "json"
require "tmpdir"
require "yaml"
require_relative "../errors"
require_relative "../shell"
require_relative "doc_commands"

module Nabu
  module Ops
    # `rake docs:verify` — the documented command flows EXECUTED, not
    # proofread. A by-hand pass over the quickstart once found two real
    # defects (a missing enable step, an alarming fork warning) that
    # reading had missed; this is the standing machine version of it.
    #
    # The verification plan is config/docs_verify.yml: the pages in scope,
    # the ordered flow of steps (each a command to run in the sandbox, the
    # documented claim it checks, and the machine expectations standing for
    # that claim), and the ignore list. The convention that keeps the plan
    # honest (the drift guard, test/docs_verify_coverage_test.rb, runs
    # #coverage_gaps over the real pages): EVERY fenced command, every
    # inline `bin/nabu …` span and every content block in the scoped pages
    # is either verified by a step (`run`, or listed under `covers` /
    # `blocks`) or named under `ignore` with a reason — so a newly
    # documented command cannot silently escape the verifier. Claim quotes
    # must still appear verbatim (whitespace-insensitive) in their page, so
    # rewording a claim forces its expectation to be revisited.
    #
    # Execution: a throwaway sandbox (a fresh clone of the local repo's
    # committed HEAD in a tmpdir), the taught commands run in plan order
    # under /bin/sh with a clean environment. Offline mode (the default)
    # runs only `mode: offline` steps and points every outgoing proxy at an
    # unroutable port, so a step that unexpectedly tries the network fails
    # fast instead of downloading; network steps print a NET line naming
    # the network mode. Each claim prints one verdict line: OK, or FAIL with
    # what the doc says against what happened.
    class DocsVerify
      PLAN = "config/docs_verify.yml"
      MODES = %i[offline network].freeze
      OFFLINE_PROXY = "http://127.0.0.1:9"
      PROXY_VARS = %w[http_proxy https_proxy HTTP_PROXY HTTPS_PROXY all_proxy ALL_PROXY].freeze
      STRIPPED_ENV = /\A(BUNDLE_|BUNDLER_|RUBYOPT\z|RUBYLIB\z|NABU_|no_proxy\z|NO_PROXY\z)/
      QUOTE_WIDTH = 100

      PageRef = Data.define(:path, :sections)
      BlockRef = Data.define(:page, :contains)
      Claim = Data.define(:page, :quote)
      Step = Data.define(:id, :run, :mode, :covers, :blocks, :claim, :stdin, :expect)
      Ignore = Data.define(:command, :block, :reason)

      # The parsed plan; from_h validates the shape so a malformed plan fails
      # loudly before any sandbox is built.
      Plan = Data.define(:pages, :steps, :ignores, :forbid_output) do
        def self.load(path) = from_h(YAML.safe_load_file(path, aliases: true))

        def self.from_h(hash)
          pages = hash.fetch("pages").map { |p| PageRef.new(path: p.fetch("path"), sections: p["sections"]) }
          steps = hash.fetch("steps").map { |s| step(s) }
          ignores = Array(hash["ignore"]).map { |i| ignore(i) }
          new(pages: pages, steps: steps, ignores: ignores, forbid_output: Array(hash["forbid_output"]))
        end

        def self.step(hash)
          id = hash.fetch("id")
          mode = (hash["mode"] || "offline").to_sym
          raise Nabu::Error, "docs_verify step #{id}: mode must be offline or network" unless MODES.include?(mode)

          claim = hash["claim"] && Claim.new(page: hash["claim"].fetch("page"), quote: hash["claim"].fetch("quote"))
          Step.new(id: id, run: hash.fetch("run"), mode: mode, covers: Array(hash.fetch("covers", [hash["run"]])),
                   blocks: Array(hash["blocks"]).map { |b| block_ref(b) },
                   claim: claim, stdin: hash["stdin"], expect: hash.fetch("expect", {}))
        end

        def self.block_ref(hash) = BlockRef.new(page: hash.fetch("page"), contains: hash.fetch("contains"))

        def self.ignore(hash)
          reason = hash["reason"].to_s.strip
          raise Nabu::Error, "docs_verify ignore entry #{hash.inspect}: a reason is required" if reason.empty?

          block = hash["block"] && block_ref(hash["block"])
          Ignore.new(command: hash["command"], block: block, reason: reason)
        end
      end

      # The throwaway sandbox: a fresh clone of +repo+'s committed HEAD.
      # Yields the clone's root and its sha; the tmpdir is removed after.
      def self.sandbox(repo:)
        Dir.mktmpdir("nabu-docs-verify-") do |dir|
          root = File.join(dir, "nabu")
          Nabu::Shell.run("git", "clone", "--quiet", repo, root)
          sha = Nabu::Shell.run("git", "-C", root, "rev-parse", "HEAD").strip
          yield root, sha
        end
      end

      # Environment overrides for the sandbox's commands: inherited
      # Bundler/Ruby/Nabu variables unset (the sandbox resolves its OWN
      # Gemfile, as a fresh user's shell would), plus the offline proxy guard.
      def self.runner_env(mode:, base: ENV)
        env = base.keys.grep(STRIPPED_ENV).to_h { |key| [key, nil] }
        PROXY_VARS.each { |var| env[var] = OFFLINE_PROXY } if mode == :offline
        env
      end

      # The real runner: the command line under /bin/sh in the sandbox root.
      def self.shell_runner(root:, mode:)
        env = runner_env(mode: mode)
        lambda do |command, stdin:|
          Nabu::Shell.capture("/bin/sh", "-c", command, env: env, chdir: root, stdin_data: stdin)
        end
      end

      # The rake task's whole job: clone, load the plan from the clone, run.
      def self.run_sandboxed(repo:, mode:, out: $stdout)
        sandbox(repo: repo) do |root, sha|
          out.puts "docs:verify (#{mode}) — sandbox: fresh clone of #{repo} at #{sha[0, 12]}"
          new(plan: Plan.load(File.join(root, PLAN)), root: root, mode: mode,
              runner: shell_runner(root: root, mode: mode), out: out).run.clean?
        end
      end

      def initialize(plan:, root:, mode: :offline, runner: nil, out: $stdout, clock: nil)
        @plan = plan
        @root = root
        @mode = mode
        @runner = runner
        @out = out
        @clock = clock || -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }
      end

      # The run's tally: executed steps that held / failed, network steps
      # named but not run (offline mode).
      Report = Data.define(:ok, :failed, :network) do
        def clean? = failed.zero?
      end

      # Runs the flow; prints one verdict line per step plus a summary line.
      def run
        tally = Hash.new(0)
        @plan.steps.each do |step|
          if step.mode == :network && @mode == :offline
            tally[:net] += 1
            @out.puts %(NET   #{step.id}: #{step.run} — network step; run rake "docs:verify[network]")
            next
          end
          failures, seconds = execute(step)
          tally[failures.empty? ? :ok : :fail] += 1
          @out.puts verdict(step, failures, seconds)
        end
        summary = "docs:verify (#{@mode}) — #{tally[:ok]} OK, #{tally[:fail]} FAIL"
        summary += ", #{tally[:net]} network-only" if @mode == :offline
        @out.puts summary
        Report.new(ok: tally[:ok], failed: tally[:fail], network: tally[:net])
      end

      # The drift guard: every documented command/content block covered or
      # ignored, every claim quote still on its page, no dead plan entries.
      def coverage_gaps
        pages = @plan.pages.to_h { |ref| [ref.path, page(ref.path)] }
        commands = pages.values.flat_map(&:commands)
        documented = commands.map { |c| DocCommands.key(c.text) }
        covered = @plan.steps.flat_map(&:covers).map { |c| DocCommands.key(c) } +
                  @plan.ignores.filter_map(&:command).map { |c| DocCommands.key(c) }
        block_refs = @plan.steps.flat_map(&:blocks) + @plan.ignores.filter_map(&:block)

        gaps = commands.reject { |c| covered.include?(DocCommands.key(c.text)) }.map do |c|
          "#{page_of(pages, c)}:#{c.line}: `#{c.text}` is neither verified by a step nor ignored"
        end
        gaps += uncovered_blocks(pages, block_refs)
        gaps += stale_claims(pages)
        gaps + dead_entries(documented, pages, block_refs)
      end

      private

      def page(path)
        ref = @plan.pages.find { |p| p.path == path }
        @pages ||= {}
        @pages[path] ||= DocCommands.parse(File.read(File.join(@root, path), encoding: Encoding::UTF_8),
                                           path: path, sections: ref&.sections)
      end

      def page_of(pages, command) = pages.find { |_, p| p.commands.include?(command) }&.first

      def content_blocks(parsed) = parsed.blocks.select { |b| b.commands.empty? }

      def uncovered_blocks(pages, refs)
        pages.flat_map do |path, parsed|
          content_blocks(parsed).filter_map do |block|
            next if refs.any? { |r| r.page == path && block.body.include?(r.contains) }

            "#{path}:#{block.line}: a #{block.lang.empty? ? 'plain' : block.lang} block is neither verified nor ignored"
          end
        end
      end

      def stale_claims(pages)
        @plan.steps.filter_map do |step|
          next unless step.claim
          next if (pages[step.claim.page] || page(step.claim.page)).quotes?(step.claim.quote)

          %(step #{step.id}: claim quote not found in #{step.claim.page}: "#{step.claim.quote}")
        end
      end

      def dead_entries(documented, pages, block_refs)
        undocumented = ->(command) { !documented.include?(DocCommands.key(command)) }
        dead = @plan.steps.flat_map do |step|
          step.covers.select(&undocumented).map { |c| "step #{step.id} covers `#{c}`, which no page documents" }
        end
        dead += @plan.ignores.filter_map(&:command).select(&undocumented)
                     .map { |c| "ignore entry `#{c}` matches no documented command" }
        dead + block_refs.reject { |ref| block_matched?(pages, ref) }
                         .map { |r| "block reference #{r.page} containing #{r.contains.inspect} matches no block" }
      end

      def block_matched?(pages, ref)
        parsed = pages[ref.page]
        parsed && content_blocks(parsed).any? { |b| b.body.include?(ref.contains) }
      end

      def execute(step)
        command = step.run.gsub("{root}", @root)
        started = @clock.call
        result = @runner.call(command, stdin: step.stdin)
        seconds = @clock.call - started
        [check(step, result, seconds), seconds]
      end

      def check(step, result, seconds)
        failures = step.expect.flat_map { |kind, want| Array(expectation(kind, want, step, result, seconds)) }
        @plan.forbid_output.each do |pattern|
          failures << %(forbidden output #{pattern.inspect}) if Regexp.new(pattern).match?(result.output)
        end
        failures
      end

      def expectation(kind, want, step, result, seconds)
        case kind
        when "exit" then exit_failure(want, result)
        when "output_includes"
          Array(want).reject { |s| result.output.include?(s) }.map { |s| %(output lacks "#{s}") }
        when "output_matches"
          Array(want).filter_map { |re| "output does not match /#{re}/" unless Regexp.new(re).match?(result.output) }
        when "max_seconds" then "took #{seconds.round(1)}s, budget #{want}s" if seconds > want
        when "path_exists" then "#{want} does not exist" unless File.exist?(sandbox_path(want))
        when "path_absent" then "#{want} exists (the doc says it would not)" if File.exist?(sandbox_path(want))
        when "file_includes" then file_includes_failure(want)
        when "json_file_equals_block" then json_block_failure(want)
        when "mcp_tools" then mcp_failure(want, result)
        when "transcript" then transcript_failures(want, step, result)
        else raise Nabu::Error, "docs_verify step #{step.id}: unknown expectation #{kind.inspect}"
        end
      end

      def sandbox_path(relative) = File.join(@root, relative)

      def exit_failure(want, result)
        if want == "nonzero"
          "nonzero exit expected, got 0" if result.success?
        elsif result.status != want
          "exit #{want} expected, got #{result.status}"
        end
      end

      def file_includes_failure(want)
        path = sandbox_path(want.fetch("path"))
        return "#{want['path']} does not exist" unless File.file?(path)

        %(#{want['path']} lacks "#{want['text']}") unless File.read(path).include?(want.fetch("text"))
      end

      def json_block_failure(want)
        path = sandbox_path(want.fetch("path"))
        return "#{want['path']} does not exist" unless File.file?(path)

        block = content_blocks(page(want.fetch("page"))).find { |b| b.body.include?(want.fetch("contains")) }
        return "no documented block in #{want['page']} contains #{want['contains'].inspect}" unless block
        return if JSON.parse(File.read(path)) == JSON.parse(block.body)

        "#{want['path']} differs from the documented block (#{want['page']}:#{block.line})"
      rescue JSON::ParserError => e
        "JSON did not parse: #{e.message.lines.first.strip}"
      end

      def mcp_failure(want, result)
        tools = result.output.lines.filter_map do |line|
          JSON.parse(line).dig("result", "tools")
        rescue JSON::ParserError
          nil
        end.last
        count = tools ? tools.size : 0
        "tools/list answered #{count} tools, doc says #{want}" unless count == want
      end

      # The documented transcript of this step's command on +page_path+:
      # each output line (trims marked with … excepted) must appear in the
      # actual output, whitespace-insensitively.
      def transcript_failures(page_path, step, result)
        documented = page(page_path).fenced_commands.find { |c| DocCommands.key(c.text) == DocCommands.key(step.run) }
        return "no `$ #{step.run}` transcript in #{page_path}" unless documented&.output&.any?

        actual = result.output.lines.map { |l| DocCommands.key(l) }
        documented.output.reject { |l| l.include?("…") || l.strip.empty? }.filter_map do |line|
          %(documented output line missing: "#{DocCommands.key(line)}") unless actual.include?(DocCommands.key(line))
        end
      end

      def verdict(step, failures, seconds)
        head = "#{step.id}: #{step.run}"
        return "OK    #{head} (#{seconds.round(1)}s)" if failures.empty?

        said = step.claim ? %( — doc (#{step.claim.page}) says "#{clip(step.claim.quote)}") : ""
        "FAIL  #{head}#{said}; got: #{failures.join('; ')}"
      end

      def clip(text)
        text = DocCommands.key(text)
        text.size > QUOTE_WIDTH ? "#{text[0, QUOTE_WIDTH - 1]}…" : text
      end
    end
  end
end

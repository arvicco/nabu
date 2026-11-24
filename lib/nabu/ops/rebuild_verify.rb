# frozen_string_literal: true

require "time"

# Loaded after "nabu" (the rake task, the suite): the Store readers it
# calls — SourceAggregates, LaneCoverage, RebuildRuns, StageTimings,
# InspectedTextScan, the Loader's sentinels — come with it.
require_relative "rebuild_census"
require_relative "db_snapshot"
require_relative "trickle"

module Nabu
  module Ops
    # `rake rebuild:verify` — the full rebuild's AFTER half: ONE read-only
    # command that says whether the rebuild landed, check by check, each a
    # labeled PASS / WARN / FAIL / SKIP line with its numbers. Exit non-zero
    # on any FAIL. Checks run cheapest first; every check that reads a
    # whole file or table ANNOUNCES its cost (what it reads, how much)
    # before it starts and prints its elapsed after. QUICK=1 skips the
    # heavy ones (each an explicit SKIP line, never a silent omission).
    #
    #   run        the latest FULL rebuild_runs row completed (a dead or
    #              failed run is the loudest FAIL there is)
    #   counts     per-source documents/passages vs the census captured
    #              BEFORE that run (Ops::RebuildCensus). A document loss is
    #              explained only by the documents the rebuild's own run
    #              rows quarantined (a held row a quarantine had shielded
    #              does not survive a fresh build); a lost source or an
    #              unexplained loss FAILs, a passage loss with documents
    #              intact WARNs (a parser change since the census?), gains
    #              are listed. Dictionary-kind sources compare their live
    #              entries: any loss FAILs (a dictionary run row counts
    #              quarantined FILES, so no entry loss is provably
    #              explained), a gain is a NOTE, and a census without
    #              dictionary counts is a SKIP line.
    #   aggregates source_aggregates vs a live recount on a seeded sample
    #              of sources (SourceAggregates.drift — O(source) each)
    #   fulltext   held vs searchable: nothing flagged behind, membership
    #              equal to the live count per source, the indexer's own
    #              indexed count (the rebuild's fts+lemma stage row) equal
    #              to the held total, and the cjk/trigram lane coverage
    #              (Store::LaneCoverage: flags vs built scope vs rows)
    #   stamps     every derivation stamp current — the incremental
    #              planner's verdict sweep (`rebuild --incremental
    #              --dry-run`'s own), priced from its ledger row; a
    #              source whose canonical tree moved under a live trickle
    #              crawl is a NOTE, not a failure
    #   fold       the text_normalized storage classes on a sample of
    #              rowid windows: "" / the one-byte lower sentinel / a
    #              stored fold — a fresh build stores no full fold equal to
    #              text or lower(text) (the loader's slim forms, by
    #              construction)
    #   sizes      every db/ file now vs the census
    #   readers    no process holds a DELETED db/ file open (a pre-rebuild
    #              `nabu mcp` reader pinning the old catalog's blocks —
    #              its watchdog vacates idle handles; a WARN, re-check)
    #   integrity  PRAGMA quick_check on every db/*.sqlite3 (heavy: reads
    #              every page; FULL_INTEGRITY=1 runs integrity_check, which
    #              also cross-checks every index — far slower). On SQLite
    #              ≥ 3.44 either pragma also runs each FTS5 table's own
    #              integrity check, read-only (#fts5_coverage)
    #   inspect    no live passage text shaped like an inspected Ruby
    #              object (Nabu::InspectedText — the conformance detector;
    #              heavy: one scan of the passages table)
    #
    # READ-ONLY by construction: every handle is opened read-only by the
    # caller; nothing is written anywhere.
    class RebuildVerify
      include DurationFormat

      Check = Data.define(:name, :status, :detail, :lines) do
        def initialize(name:, status:, detail:, lines: [])
          super
        end
      end

      Report = Data.define(:checks, :census_path, :seconds) do
        def failed? = checks.any? { |check| check.status == :fail }
        def count(status) = checks.count { |check| check.status == status }
      end

      Run = Data.define(:id, :started_at, :completed_at, :git_sha, :notes, :pid)

      # const: the most changed-source lines a check prints before an
      # announced "… and N more" — a readable screen, never a silent cut
      LINE_CAP = 25
      # const: the text_normalized sample — rowid windows spread evenly over
      # the passage id range, each this many ids (a few hundred thousand
      # rows in all: seconds, against a full-table scan's minutes)
      FOLD_WINDOWS = 40
      FOLD_WINDOW_IDS = 5_000
      # const: how many sampled inspect-shaped hits are named
      INSPECT_SAMPLES = 5
      # The SQLite release whose integrity pragmas began calling virtual
      # tables' integrity methods (FTS5's included) — see #fts5_coverage.
      FTS5_PRAGMA_SINCE = Gem::Version.new("3.44.0")

      def initialize(catalog:, fulltext:, ledger:, db_dir:, local_dir:, cjk_slugs: [], fuzzy_slugs: [],
                     stamps_plan: nil, quick: false, full_integrity: false, sample: 8, seed: 1,
                     deleted_holders: nil, trickle_dir: nil, alive: ProcessProbe.method(:alive?), out: $stdout,
                     clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) })
        @catalog = catalog
        @fulltext = fulltext
        @ledger = ledger
        @db_dir = db_dir
        @local_dir = local_dir
        @cjk_slugs = cjk_slugs
        @fuzzy_slugs = fuzzy_slugs
        @stamps_plan = stamps_plan
        @quick = quick
        @full_integrity = full_integrity
        @sample = sample
        @seed = seed
        @deleted_holders = deleted_holders || method(:lsof_deleted)
        @trickle_dir = trickle_dir
        @alive = alive
        @out = out
        @clock = clock
      end

      def run!
        started = @clock.call
        @out.puts("rebuild:verify — read-only; the latest full rebuild against the census captured before it")
        run = latest_full_run
        census_path, census = run && RebuildCensus.latest_before(@local_dir, run.started_at)
        @out.puts("  census: #{census_path || 'none captured before this rebuild (rake rebuild:census)'}")
        checks = []
        each_check(run, census) do |check|
          checks << check
          print_check(check)
        end
        report = Report.new(checks: checks, census_path: census_path, seconds: @clock.call - started)
        @out.puts("SUMMARY rebuild:verify — #{report.count(:pass)} pass, #{report.count(:warn)} warn, " \
                  "#{report.count(:fail)} fail, #{report.count(:skip)} skip in #{format_duration(report.seconds)}")
        report
      end

      # lsof -F field output (p<pid> / c<command> / n<name> lines) as
      # [[pid, command, path]], one row per name.
      def self.deleted_rows(output)
        pid = command = nil
        rows = []
        output.each_line do |line|
          case line[0]
          when "p" then pid = line[1..].to_i
          when "c" then command = line[1..].strip
          when "n" then rows << [pid, command, line[1..].strip] if pid
          end
        end
        rows
      end

      private

      def each_check(run, census)
        yield run_check(run)
        yield counts_check(run, census)
        yield aggregates_check
        yield fulltext_check(run)
        yield stamps_check
        yield fold_check
        yield sizes_check(census)
        yield readers_check
        yield integrity_check
        yield inspect_check
      end

      def print_check(check)
        @out.puts(format("  %-4<s>s  %-10<n>s %<d>s", s: check.status.to_s.upcase, n: check.name, d: check.detail))
        check.lines.each { |line| @out.puts("        #{line}") }
      end

      def announce(name, text) = @out.puts("  ....  #{name.ljust(10)} #{text}")

      def timed(name, cost)
        announce(name, cost)
        started = @clock.call
        check = yield
        check.with(detail: "#{check.detail} (#{format_duration(@clock.call - started)})")
      end

      def capped(lines)
        return lines if lines.size <= LINE_CAP

        lines.first(LINE_CAP) + ["… and #{lines.size - LINE_CAP} more"]
      end

      def human(bytes) = DbSnapshot.human(bytes.to_i)
      def commas(count) = Eta.commas(count)
      def day(time) = time.utc.strftime("%Y-%m-%d")

      # -- run ----------------------------------------------------------------

      def latest_full_run
        return nil unless Store::RebuildRuns.table?(@ledger)

        row = @ledger[Store::RebuildRuns::TABLE].where(mode: "full").order(Sequel.desc(:id)).first
        return nil if row.nil?

        Run.new(id: row[:id], started_at: Time.iso8601(row[:started_at].to_s),
                completed_at: row[:completed_at] && Time.iso8601(row[:completed_at].to_s),
                git_sha: row[:git_sha], notes: row[:notes], pid: row[:pid])
      end

      def run_check(run)
        return Check.new(name: "run", status: :fail, detail: "no full rebuild recorded in the ledger") if run.nil?

        if run.completed_at.nil?
          state = if run.notes then run.notes
                  elsif Store::RebuildRuns.alive?(run.pid) then "STILL RUNNING (pid #{run.pid}) — verify after it ends"
                  else "the process died mid-run"
                  end
          return Check.new(name: "run", status: :fail,
                           detail: "the full rebuild started #{day(run.started_at)} never completed (#{state}) — " \
                                   "re-run `bin/nabu rebuild`; there is no resume")
        end

        Check.new(name: "run", status: :pass,
                  detail: "full rebuild completed #{day(run.completed_at)} in " \
                          "#{Eta.format_seconds(run.completed_at - run.started_at)} wall " \
                          "(code #{run.git_sha.to_s[0, 10]})")
      end

      # -- counts -------------------------------------------------------------

      def live_counts
        slugs = @catalog[:sources].select_hash(:id, :slug)
        Store::SourceAggregates.all(@catalog).values.to_h do |row|
          [slugs[row.source_id], { "documents" => row.documents_count, "passages" => row.passages_count }]
        end
      end

      # { slug => documents the rebuild's own replay quarantined }. The
      # ledger's DateTime columns hold the writer's LOCAL wall time (every
      # writer passes Time.now) and Sequel literalizes a Time in its own
      # zone, so the bounds go in as local times too.
      def quarantined(run)
        return {} if @ledger.nil? || !@ledger.table_exists?(:runs)

        from = run.started_at.getlocal
        to = run.completed_at.getlocal
        window = @ledger[:runs].where(kind: "rebuild").where { (started_at >= from) & (started_at <= to) }
        window.select_hash(:source_slug, :errored)
      end

      def counts_check(run, census)
        return Check.new(name: "counts", status: :skip, detail: "no completed full rebuild to compare") unless
          run&.completed_at
        unless census
          return Check.new(name: "counts", status: :skip,
                           detail: "no census captured before this rebuild — nothing to compare against")
        end

        now = live_counts
        before = census.fetch("sources")
        held = quarantined(run)
        verdicts = (before.keys | now.keys).compact.sort.filter_map do |slug|
          source_verdict(slug, before.fetch(slug, {}), now.fetch(slug, {}), held[slug].to_i)
        end
        dictionary_detail, dictionary_verdicts = dictionary_comparison(census["dictionaries"], held)
        verdicts.concat(dictionary_verdicts)
        status = if verdicts.any? { |verdict, _| verdict == :fail } then :fail
                 elsif verdicts.any? { |verdict, _| verdict == :warn } then :warn
                 else :pass
                 end
        totals = ->(counts, key) { commas(counts.values.sum { |row| row[key].to_i }) }
        changed = verdicts.count { |verdict, _| verdict != :skip }
        detail = "#{(before.keys | now.keys).compact.size} sources, #{changed} changed; documents " \
                 "#{totals.call(before, 'documents')} → #{totals.call(now, 'documents')}, passages " \
                 "#{totals.call(before, 'passages')} → #{totals.call(now, 'passages')}; #{dictionary_detail}"
        lines = verdicts.sort_by { |verdict, _| %i[fail warn note skip].index(verdict) }
                        .map { |verdict, line| "#{verdict.to_s.upcase.ljust(4)} #{line}" }
        Check.new(name: "counts", status: status, detail: detail, lines: capped(lines))
      end

      # [detail fragment, [[verdict, line]]] for the dictionary-kind
      # sources (RebuildCensus.dictionary_counts). A census captured before
      # the census counted them has no "dictionaries" key: the comparison
      # is a SKIP line with its reason, never a failure.
      def dictionary_comparison(before, quarantined)
        if before.nil?
          return ["dictionary entries not compared (the census predates dictionary counts)",
                  [[:skip, "dictionary entries: the census predates dictionary counts — not compared"]]]
        end

        now = RebuildCensus.dictionary_counts(@catalog)
        slugs = (before.keys | now.keys).sort
        verdicts = slugs.filter_map do |slug|
          dictionary_verdict(slug, before.dig(slug, "entries").to_i, now.dig(slug, "entries").to_i,
                             quarantined[slug].to_i)
        end
        total = ->(counts) { commas(counts.values.sum { |row| row["entries"].to_i }) }
        ["dictionary entries #{total.call(before)} → #{total.call(now)} over #{slugs.size} source(s)", verdicts]
      end

      # A dictionary run row's errored count is quarantined FILES, not
      # entries, so no entry loss can be proven explained from ops-side
      # reads: every loss FAILs, naming the run's quarantined files as the
      # likely cause when there are any; a gain is a NOTE.
      def dictionary_verdict(slug, before, now, quarantined_files)
        return nil if before == now

        line = "#{slug}: dictionary entries #{commas(before)} → #{commas(now)}"
        return [:note, "#{line} — gained"] if now > before
        return [:fail, "#{line} — LOST the whole source"] if now.zero?

        cause = if quarantined_files.positive?
                  "the rebuild quarantined #{commas(quarantined_files)} dictionary file(s), but entry-grained " \
                    "quarantine accounting is not readable — check by hand"
                else
                  "the rebuild quarantined none"
                end
        [:fail, "#{line} — #{commas(before - now)} entry(ies) lost; #{cause}"]
      end

      # [verdict, line] for a changed source, nil for an unchanged one.
      def source_verdict(slug, before, now, quarantined)
        docs_before = before["documents"].to_i
        docs_now = now["documents"].to_i
        pass_before = before["passages"].to_i
        pass_now = now["passages"].to_i
        return nil if docs_before == docs_now && pass_before == pass_now

        line = "#{slug}: documents #{commas(docs_before)} → #{commas(docs_now)}, " \
               "passages #{commas(pass_before)} → #{commas(pass_now)}"
        lost = docs_before - docs_now
        if docs_now.zero? && docs_before.positive?
          [:fail, "#{line} — LOST the whole source"]
        elsif lost > quarantined
          [:fail, "#{line} — #{commas(lost)} document(s) lost, only #{commas(quarantined)} quarantined by the rebuild"]
        elsif lost.positive?
          [:note, "#{line} — explained: the rebuild quarantined #{commas(quarantined)}"]
        elsif pass_now < pass_before && lost.zero?
          [:warn, "#{line} — passages lost with documents intact (a parser change since the census?)"]
        else
          [:note, "#{line} — gained"]
        end
      end

      # -- aggregates ---------------------------------------------------------

      def aggregates_check
        ids = Store::SourceAggregates.all(@catalog).keys.sample(@sample, random: Random.new(@seed))
        return Check.new(name: "aggregates", status: :skip, detail: "no source_aggregates rows") if ids.empty?

        slugs = @catalog[:sources].select_hash(:id, :slug)
        timed("aggregates", "recounting #{ids.size} sampled source(s) live (SEED=#{@seed}; each O(source))") do
          drift = Store::SourceAggregates.drift(@catalog, ids)
          lines = drift.map { |d| "#{slugs[d[:source_id]]}: #{d[:column]} stored #{d[:stored]} ≠ live #{d[:truth]}" }
          verdict = drift.empty? ? "stored counts exact" : "#{drift.size} drift(s)"
          Check.new(name: "aggregates", status: drift.empty? ? :pass : :fail,
                    detail: "#{ids.size} sampled source(s): #{verdict}", lines: capped(lines))
        end
      end

      # -- fulltext -----------------------------------------------------------

      def fulltext_check(run)
        return Check.new(name: "fulltext", status: :fail, detail: "no fulltext index file") if @fulltext.nil?

        rows = Store::SourceAggregates.all(@catalog).values
        held = rows.sum(&:passages_count)
        searchable = rows.sum { |row| row.fts_member_count.to_i }
        lines = membership_gaps(rows)
        indexed = indexed_by_rebuild(run)
        lines << "the indexer indexed #{commas(indexed)} passages but the catalog holds #{commas(held)}" if
          indexed && indexed != held
        findings = Store::LaneCoverage.findings(catalog: @catalog, fulltext: @fulltext, cjk_slugs: @cjk_slugs,
                                                fuzzy_slugs: @fuzzy_slugs)
        lines.concat(findings.map { |finding| "#{finding.lane} lane: #{finding.message}" })
        lanes = findings.empty? ? "all built with rows" : "#{findings.size} finding(s)"
        detail = "held #{commas(held)}, searchable #{commas(searchable)} (delta #{commas(held - searchable)}); " \
                 "indexer #{indexed ? commas(indexed) : 'count unrecorded'}; lanes: cjk #{@cjk_slugs.size} flagged, " \
                 "trigram #{@fuzzy_slugs.size} flagged — #{lanes}"
        Check.new(name: "fulltext", status: lines.empty? ? :pass : :fail, detail: detail, lines: capped(lines))
      end

      # One line per source flagged behind or whose membership differs
      # from its live passage count.
      def membership_gaps(rows)
        slugs = @catalog[:sources].select_hash(:id, :slug)
        rows.filter_map do |row|
          next unless row.fts_behind || row.fts_member_count != row.passages_count

          members = row.fts_member_count.nil? ? "unknown" : commas(row.fts_member_count)
          "#{slugs[row.source_id]}: held #{commas(row.passages_count)}, searchable #{members}" \
            "#{' (flagged behind)' if row.fts_behind}"
        end
      end

      # The rebuild's own indexed-passage count: the work-size denominator
      # its fts+lemma stage row carries (StageTimings.denominate!), when
      # that row belongs to this run.
      def indexed_by_rebuild(run)
        return nil unless run&.completed_at

        row = Store::StageTimings.last(@ledger, kind: "rebuild", scope: "corpus", stage: "fts_lemma")
        return nil if row.nil? || row[:rows].nil?

        finished = row[:finished_at]
        finished = Time.parse(finished.to_s) unless finished.is_a?(Time)
        finished.between?(run.started_at, run.completed_at + 1) ? row[:rows] : nil
      end

      # -- stamps -------------------------------------------------------------

      def stamps_check
        return Check.new(name: "stamps", status: :skip, detail: "no planner handed in") if @stamps_plan.nil?

        eta = Eta.for(@ledger, kind: "rebuild", scope: "corpus", stage: "verdict_sweep")
        timed("stamps", "the incremental planner's verdict sweep — #{eta.render}") do
          plan = @stamps_plan.call
          next Check.new(name: "stamps", status: :fail, detail: "planner refused: #{plan.refusal}") if plan.refusal

          stamps_verdict(plan)
        end
      end

      # A weak-identity source can never carry a stamp (its tree cannot be
      # proven unchanged — it re-derives on every incremental by design),
      # so it WARNs. A source whose canonical tree moved under a LIVE
      # trickle crawl (Ops::Trickle — it only fetches into canonical/,
      # never loads) drifted by design after the rebuild stamped it: a
      # NOTE. Every other dirty verdict means a stamp the rebuild should
      # have minted does not match current code — a FAIL.
      #
      # Caveat: a verdict names only the FIRST drift component the
      # fingerprint finds (migration, canonical, parser, fold, config — in
      # that order), so a parser or fold drift behind a trickle's canonical
      # move reads as canonical here; the next sync re-derives the source
      # either way.
      def stamps_verdict(plan)
        dirty = plan.verdicts.select { |verdict| verdict.state == :dirty }
        weak, drifted = dirty.partition { |verdict| verdict.reason == :weak_identity }
        trickled, drifted = drifted.partition { |verdict| trickle_moved?(verdict) }
        lines = drifted.map { |verdict| "#{verdict.slug}: #{verdict.reason}" }
        lines.unshift("the corpus builders read dirty (builder code changed since the stamp)") if plan.builders_dirty
        lines.unshift("the fulltext index reads dirty (index code changed since the stamp)") if plan.index_dirty
        failed = !lines.empty?
        lines.concat(weak.map { |verdict| "#{verdict.slug}: weak identity — never stampable, re-derives every time" })
        lines.concat(trickled.map { |verdict| trickle_note(verdict.slug) })
        clean = plan.verdicts.count { |verdict| verdict.state == :clean }
        status = if failed then :fail
                 elsif weak.any? then :warn
                 else :pass
                 end
        moved = trickled.any? ? "#{trickled.size} moved by a live trickle crawl, " : ""
        Check.new(name: "stamps", status: status,
                  detail: "#{clean} clean, #{drifted.size} dirty, #{moved}#{weak.size} weak identity, " \
                          "#{plan.verdicts.count { |verdict| verdict.state == :skip }} without canonical",
                  lines: capped(lines))
      end

      def trickle_moved?(verdict)
        verdict.reason == :canonical && !trickle_pid(verdict.slug).nil?
      end

      # The live trickle runner's pid for +slug+ (its pidfile under
      # local/trickle/, that pid alive — Trickle::Control#running_pid's
      # rule), nil when none runs.
      def trickle_pid(slug)
        return nil if @trickle_dir.nil?

        pid = Trickle.read_pid(File.join(@trickle_dir, "#{slug}.pid"))
        pid && @alive.call(pid) ? pid : nil
      end

      def trickle_note(slug)
        "NOTE #{slug}: canonical moved under its live trickle crawl (pid #{trickle_pid(slug)}) — later arrivals " \
          "load at the source's next sync"
      end

      # -- fold ---------------------------------------------------------------

      def fold_check
        low = @catalog[:passages].min(:id)
        high = @catalog[:passages].max(:id)
        return Check.new(name: "fold", status: :skip, detail: "no passages") if low.nil?

        step = [(high - low + 1) / FOLD_WINDOWS, FOLD_WINDOW_IDS].max
        tally = Hash.new(0)
        low.step(high, step) { |start| fold_window(start, start + FOLD_WINDOW_IDS - 1).each { |k, v| tally[k] += v } }
        total = tally.values_at(:empty, :lower, :stored).sum
        return Check.new(name: "fold", status: :skip, detail: "the sample windows hold no live passages") if total.zero?

        share = ->(key) { format("%.1f%%", 100.0 * tally[key] / total) }
        detail = "#{commas(total)} sampled rows: \"\" #{share.call(:empty)} · lower sentinel #{share.call(:lower)} · " \
                 "stored fold #{share.call(:stored)}"
        if tally[:slimmable].zero?
          Check.new(name: "fold", status: :pass, detail: "#{detail}; no stored fold equals text or lower(text)")
        else
          Check.new(name: "fold", status: :fail,
                    detail: "#{detail}; #{commas(tally[:slimmable])} stored fold(s) equal text or lower(text) — " \
                            "the slim forms did not land by construction")
        end
      end

      def fold_window(low, high)
        normalized = Sequel[:text_normalized]
        sentinels = [Store::Loader::EMPTY_SENTINEL, Store::Loader::LOWER_SENTINEL]
        same = Sequel.|({ normalized => Sequel[:text] }, { normalized => Sequel.function(:lower, :text) })
        slimmable = Sequel.&(Sequel.~(normalized => sentinels), same)
        sum = ->(cond) { Sequel.function(:sum, Sequel.case({ cond => 1 }, 0)) }
        row = @catalog[:passages].where(id: low..high, withdrawn: false).select(
          sum.call(normalized => Store::Loader::EMPTY_SENTINEL).as(:empty),
          sum.call(normalized => Store::Loader::LOWER_SENTINEL).as(:lower),
          sum.call(Sequel.~(normalized => sentinels)).as(:stored),
          sum.call(slimmable).as(:slimmable)
        ).first
        row.transform_values(&:to_i)
      end

      # -- sizes --------------------------------------------------------------

      def sizes_check(census)
        now = RebuildCensus.file_sizes(@db_dir)
        before = census ? census.fetch("files", {}) : {}
        lines = (before.keys | now.keys).sort.map do |name|
          was = before[name]
          is = now[name]
          change = was && is && was.positive? ? format(" (%+.1f%%)", 100.0 * (is - was) / was) : ""
          "#{name}: #{was ? human(was) : '—'} → #{is ? human(is) : 'absent'}#{change}"
        end
        detail = "#{now.size} file(s), #{human(now.values.sum)} now" +
                 (census ? " vs #{human(before.values.sum)} before" : " (no census to compare)")
        Check.new(name: "sizes", status: :pass, detail: detail, lines: lines)
      end

      # -- readers ------------------------------------------------------------

      def readers_check
        held = @deleted_holders.call.select { |_, _, path| path.start_with?(File.join(@db_dir, "")) }
        return Check.new(name: "readers", status: :pass, detail: "no process holds a deleted db/ file") if held.empty?

        lines = held.map { |pid, command, path| "pid #{pid} (#{command}) still holds deleted #{path}" }
        Check.new(name: "readers", status: :warn,
                  detail: "#{held.size} open handle(s) on deleted pre-rebuild files — their blocks stay pinned; " \
                          "the nabu mcp watchdog vacates idle handles, so re-check, or restart that client",
                  lines: capped(lines))
      end

      # [[pid, command, path]] for open files whose link count is zero
      # (`lsof +L1`); lsof exits 1 when there are none.
      def lsof_deleted
        self.class.deleted_rows(Shell.run("lsof", "-nP", "+L1", "-Fpcn"))
      rescue Shell::Error
        []
      end

      # -- integrity ----------------------------------------------------------

      def integrity_check
        pragma = @full_integrity ? :integrity_check : :quick_check
        files = Dir.glob(File.join(@db_dir, "*.sqlite3"))
        return skip_heavy("integrity", "PRAGMA #{pragma} over #{files.size} file(s)") if @quick
        return Check.new(name: "integrity", status: :skip, detail: "no db files") if files.empty?

        bytes = files.sum { |path| File.size(path) }
        timed("integrity", "PRAGMA #{pragma} over #{files.size} file(s), #{human(bytes)} — reads every page; " \
                           "#{fts5_coverage} (minutes-class at library scale; QUICK=1 skips)") do
          bad = files.filter_map do |path|
            result = pragma_result(path, pragma)
            "#{File.basename(path)}: #{result}" unless result == "ok"
          end
          Check.new(name: "integrity", status: bad.empty? ? :pass : :fail,
                    detail: "#{pragma}: #{files.size - bad.size} of #{files.size} file(s) ok", lines: bad)
        end
      end

      # FTS5's internal integrity (the inverted index against its doclists,
      # docsize and content) is NOT a separate command here: its own form,
      # `INSERT INTO <fts>(<fts>) VALUES('integrity-check')`, is a write
      # that a read-only handle refuses ("attempt to write a readonly
      # database") — and the verify never opens a db writable. Since SQLite
      # 3.44 the quick_check / integrity_check pragmas call every virtual
      # table's integrity method, so FTS5 tables ARE checked by the pragma
      # this check already runs, read-only (FTS5_PRAGMA_SINCE). Older
      # SQLite: said, not hidden.
      def fts5_coverage
        version = @catalog.get(Sequel.function(:sqlite_version)).to_s
        if Gem::Version.new(version) >= FTS5_PRAGMA_SINCE
          "FTS5 tables' own integrity checks included (SQLite #{version} ≥ 3.44 runs them inside the pragma — " \
            "each reads its whole index)"
        else
          "FTS5 internals NOT covered (SQLite #{version} < 3.44; their integrity-check command is a write the " \
            "read-only verify does not run)"
        end
      end

      def pragma_result(path, pragma)
        db = Store.connect(path, readonly: true)
        # The pragma's table-valued form: one row per finding, "ok" alone
        # when the file is sound.
        db.from(Sequel.function(:"pragma_#{pragma}")).map { |row| row.values.first }.first(5).join(" | ")
      rescue Sequel::DatabaseError => e
        "unreadable — #{e.message.lines.first.to_s.strip}"
      ensure
        db&.disconnect
      end

      # -- inspect ------------------------------------------------------------

      def inspect_check
        return skip_heavy("inspect", "one scan of the passages table") if @quick

        timed("inspect", "one scan of the passages table (the prefilter narrows to text opening " \
                         "#{InspectedText::OPENERS.join(' ')}; minutes-class at library scale; QUICK=1 skips)") do
          hits = inspected_hits
          lines = hits.first(INSPECT_SAMPLES).map { |urn, text| "#{urn}: #{text.to_s[0, 80].inspect}" }
          lines << "… and #{hits.size - INSPECT_SAMPLES} more" if hits.size > INSPECT_SAMPLES
          Check.new(name: "inspect", status: hits.empty? ? :pass : :fail,
                    detail: "#{commas(hits.size)} live passage(s) hold inspect-shaped text", lines: lines)
        end
      end

      def inspected_hits
        trimmed = Sequel.function(:ltrim, Sequel[:passages][:text], Store::InspectedTextScan::TRIM)
        opens = InspectedText::OPENERS.map { |opener| Sequel.like(trimmed, "#{opener}%") }.inject(:|)
        @catalog[:passages].join(:documents, id: :document_id)
                           .where(Sequel[:passages][:withdrawn] => false, Sequel[:documents][:withdrawn] => false)
                           .where(opens)
                           .select(Sequel[:passages][:urn], Sequel[:passages][:text])
                           .filter_map { |row| [row[:urn], row[:text]] if InspectedText.match?(row[:text]) }
      end

      def skip_heavy(name, what)
        Check.new(name: name, status: :skip, detail: "QUICK=1 — #{what} not run")
      end
    end
  end
end

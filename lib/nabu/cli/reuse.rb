# frozen_string_literal: true

# The `nabu reuse` command family — the gram-postings store of the
# parallels postings engine (local/reuse/, the cost law). Lives under cli/
# (the by-area layout; outside the derivation fingerprint).
module Nabu
  # `nabu reuse build SCOPE` builds a scope's gram-postings store (the ONLY
  # trigger — no rebuild or sync ever touches it); `nabu reuse status`
  # shows every build's provenance and whether its inputs moved since.
  class ReuseCLI < Thor
    include DurationFormat

    namespace "reuse"

    # A progress line every this many units (anchors / passages).
    PROGRESS_EVERY = 100_000

    def self.exit_on_failure?
      true
    end

    desc "build SCOPE", "Build the gram-postings store the postings engine scores SCOPE from"
    long_desc <<~HELP, wrap: false
      One census over the corpus for SCOPE (a source slug or urn prefix — the
      parallels --batch scope grammar): every gram SCOPE's anchors will
      probe, with exactly the passages the FTS phrase probe would return
      (main lane via SQLite's own tokenizer, the CJK bigram lane via its run
      windows). `parallels --batch SCOPE --engine postings` then scores from
      it — identical edges to the fts engine, without one FTS query per
      gram.

      Heavy derived data under the cost law: written only here, under
      local/reuse/<build>/ (sharded SQLite), never by `nabu rebuild` or a
      sync. The build stamps what it was built from (scope, gram size,
      common-gram cap, census and index code, SQLite, the CJK lane's
      sources, every source's content slice); `nabu reuse status` reads
      staleness against it, and the postings engine refuses a stale store.
      A rebuild replaces the store whole; a killed build leaves the
      previous one serving.

      --gram-size/--lang (or --profile NAME from config/reuse_profiles.yml)
      must match the parallels run that will read it; a build without
      --lang serves every --lang of that scope. Three passes, each over
      --workers N forked workers: the scope's anchors (wanted grams), the
      corpus (windows), one finalize per shard. The corpus pass reads the
      WHOLE live corpus whatever the scope (any passage can be a candidate,
      and df is corpus-wide) — the prefilter skips passages without a
      character of the anchor vocabulary's scripts unread.

      --measure N is the bounded timing run: the corpus pass stops after N
      passages (id order), every pass is timed, NOTHING is installed, and
      the summary projects the full corpus pass linearly from the scanned
      share of the passage-id range.

      Examples:
        nabu reuse build kanripo --profile chinese --workers 8 2> census.log
        nabu reuse build kanripo --profile chinese --workers 8 --measure 5000000
        nabu reuse build urn:nabu:sblgnt:matt --lang grc
    HELP
    option :gram_size, type: :numeric, banner: "N",
                       desc: "Shingle width (default #{Nabu::Query::Parallels::GRAM_SIZE}, or the profile's)"
    option :lang, type: :string, desc: "Anchor language (the parallels --lang); default every language"
    option :profile, type: :string, banner: "NAME",
                     desc: "Take gram size and lang from a config/reuse_profiles.yml profile"
    option :shards, type: :numeric, default: Nabu::ReuseCensus::DEFAULT_SHARDS, desc: "Gram-hash shards"
    option :workers, type: :numeric, banner: "N",
                     desc: "Forked census workers (default #{Nabu::ReusePool.default_workers})"
    option :measure, type: :numeric, banner: "N",
                     desc: "Timing run: stop the corpus pass after N passages, install nothing, project the rest"
    def build(scope)
      config = Nabu::Config.load
      catalog, fulltext = open_stores(config)
      raise Thor::Error, "no index — run nabu sync or nabu rebuild" unless catalog && fulltext

      profile = options[:profile] && Nabu::ReuseProfiles.default.fetch(options[:profile])
      gram_size = (options[:gram_size] || profile&.gram_size || Nabu::Query::Parallels::GRAM_SIZE).to_i
      lang = options[:lang] || profile&.lang
      workers = positive(:workers, Nabu::ReusePool.default_workers)
      shards = positive(:shards, Nabu::ReuseCensus::DEFAULT_SHARDS)
      warn "reuse build #{scope}: #{gram_size}-grams#{" [#{lang}]" if lang} · #{shards} shards · " \
           "#{workers} worker(s) → #{Nabu::Store::ReusePostings.root(config)}"
      result = Nabu::ReuseCensus.new(catalog: catalog, fulltext: fulltext, root: Nabu::Store::ReusePostings.root(config))
                                .run(scope, gram_size: gram_size, lang: lang, shards: shards, workers: workers,
                                            progress: progress_printer,
                                            measure: options[:measure] && positive(:measure, nil))
      result.measurement ? print_measurement(scope, result) : print_build(result)
    rescue Nabu::Error => e
      raise Thor::Error, e.message
    ensure
      catalog&.disconnect
      fulltext&.disconnect
    end

    desc "status", "Every gram-postings build: provenance, counts, and whether its inputs moved"
    long_desc <<~HELP, wrap: false
      One block per build under local/reuse/: scope, gram size, lang, when it
      was built and how long it took, its counts, and CURRENT or STALE with
      every moved input named (census or index code, SQLite, the CJK lane's
      sources, the corpus-relative cutoff, any source's content slice). The
      content comparison is one grouped pass over the live passages (about a
      minute on the full corpus). Unfinished builds (a killed census's
      staging directory) are listed too.
    HELP
    def status
      config = Nabu::Config.load
      root = Nabu::Store::ReusePostings.root(config)
      builds = Nabu::Store::ReusePostings.builds(root)
      say "reuse: #{builds.size} gram-postings build(s) under #{root}"
      catalog, fulltext = open_stores(config)
      census = catalog && Nabu::ReuseCensus.new(catalog: catalog, fulltext: fulltext, root: root)
      builds.each { |manifest| print_status(manifest, census) }
      Nabu::Store::ReusePostings.unfinished(root).each do |dir|
        say "  unfinished build #{File.basename(dir)} — a killed census; the next build of its scope removes it"
      end
    ensure
      catalog&.disconnect
      fulltext&.disconnect
    end

    no_commands do
      def open_stores(config)
        catalog = File.exist?(config.catalog_path) ? Nabu::Store.connect(config.catalog_path, readonly: true) : nil
        fulltext = if File.exist?(config.fulltext_path)
                     Nabu::Store.connect_fulltext(config.fulltext_path,
                                                  readonly: true)
                   end
        [catalog, fulltext]
      end

      def positive(key, default)
        return default unless options[key]

        value = options[key].to_i
        raise Thor::Error, "reuse build: --#{key} must be a positive integer" unless value.positive?

        value
      end

      # One stderr line per stage start and every PROGRESS_EVERY units —
      # readable while a `2> census.log` run is live.
      def progress_printer
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        last = {}
        lambda do |stage, done|
          mark = done / PROGRESS_EVERY
          return if last[stage] == mark && stage != :finalize

          last[stage] = mark
          elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
          warn "  #{stage} · #{done} · #{format_duration(elapsed)}"
        end
      end

      def print_build(result)
        stamp = result.manifest.provenance
        counts = stamp.fetch("counts")
        say "reuse build #{stamp['scope']}: #{result.manifest.name} in #{format_duration(result.seconds)}"
        say "  #{counts['anchors']} anchors · #{counts['grams']} wanted grams attested " \
            "(#{counts['rare_grams']} under the cap #{stamp['cap']}) · #{counts['postings']} postings"
        say "  #{counts['passages_scanned']} passages scanned · #{counts['passages_prefiltered']} prefiltered · " \
            "lane #{stamp['lane'] ? stamp['lane'].join(', ') : 'absent'}"
        return unless counts["unkeyable_grams"].to_i.positive?

        say "  #{counts['unkeyable_grams']} anchor gram(s) the FTS tokenizer splits — not emulable, " \
            "they score nothing on the postings engine"
      end

      def print_measurement(scope, result)
        m = result.measurement
        seconds = m.fetch("pass_seconds")
        say "reuse build #{scope} --measure: nothing installed · #{format_duration(result.seconds)} total"
        say "  anchors pass: #{m['anchors']} anchors in #{format_duration(seconds['anchors'])}"
        say "  corpus pass: #{m['passages_scanned']} of ~#{m['high_water']} passages scanned " \
            "(#{m['passages_prefiltered']} prefiltered) in #{format_duration(seconds['universe'])} · " \
            "#{m['raw_rows']} raw rows"
        say "  finalize: #{m['postings']} postings in #{format_duration(seconds['finalize'])}"
        return unless m["projected_universe_seconds"]

        say "  projected full corpus pass ≈ #{format_duration(m['projected_universe_seconds'])} " \
            "(linear in passage-id share — sources cluster by id; read the prefiltered share beside it)"
      end

      def print_status(manifest, census)
        stamp = manifest.provenance
        counts = stamp.fetch("counts", {})
        lang = stamp["lang"] ? " [#{stamp['lang']}]" : ""
        say "#{manifest.name}: #{stamp['scope']} · #{stamp['gram_size']}-grams#{lang} " \
            "· built #{stamp['built_at'].to_s[0, 10]} in #{format_duration(stamp['seconds'].to_f)}"
        say "  #{counts['anchors']} anchors · #{counts['postings']} postings · cap #{stamp['cap']} · " \
            "#{stamp['shards']} shards"
        return say("  staleness unknown — no catalog to compare against") unless census

        reasons = census.staleness(manifest)
        if reasons.empty?
          say "  CURRENT — every stamped input matches the live library"
        else
          say "  STALE — #{reasons.join('; ')} — rebuild: nabu reuse build #{stamp['scope']}", :red
        end
      end
    end
  end
end

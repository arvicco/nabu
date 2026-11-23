# frozen_string_literal: true

# P105-5d: rake tasks announce progress through stage/tick lines;
# when their stdout is a pipe (a background log) Ruby's default block
# buffering held those lines back for the length of a multi-hour pass —
# the no-silent-passes class. Flush as written, always.
$stdout.sync = true

require "rake/testtask"

# Keep every task's `desc` on the task object (rake records them only under
# -T/-D otherwise): `reconstruction:book` lists the tools:* tasks with them.
Rake::TaskManager.record_task_metadata = true

# `rake test` runs the suite across worker processes (test/parallel/runner.rb:
# N = Etc.nprocessors, NABU_TEST_WORKERS overrides) and prints ONE merged
# Minitest-shaped report. The single-process path stays: `rake test TEST=path`
# (one file, unparallelized) and the kill-switch NABU_TEST_SERIAL=1 both run
# the classic Rake::TestTask, exposed directly as `rake test:serial`.
Rake::TestTask.new(:"test:serial") do |t|
  t.libs << "test"
  t.libs << "lib"
  t.test_files = FileList["test/**/*_test.rb"]
  t.warning = false
end

desc "Run the test suite (parallel workers; TEST=path or NABU_TEST_SERIAL=1 → single process)"
task :test do
  if ENV["TEST"] || ENV["NABU_TEST_SERIAL"] == "1"
    Rake::Task[:"test:serial"].invoke
  else
    ruby "test/parallel/runner.rb" do |ok, _status|
      abort "rake test: suite FAILED (see report above)" unless ok
    end
  end
end

desc "Run RuboCop"
task :lint do
  sh "rubocop"
end

namespace :lint do
  desc "Run RuboCop with safe autocorrections"
  task :fix do
    sh "rubocop -a"
  end
end

# Fixture sentinel (P5-4). Network-CAPABLE, human-initiated only — the suite
# never runs these (their logic is tested with mocked fetches + tmp dirs). Thin
# wrappers over Nabu::FixtureSentinel; all logic lives there.
namespace :fixtures do
  desc "Re-fetch upstream and drift-check fixtures (no arg = all sources); NEVER overwrites"
  task :check, [:source] do |_task, args|
    $LOAD_PATH.unshift(File.expand_path("lib", __dir__))
    require "nabu"

    require_relative "lib/nabu/ops/proof_cadence"
    sentinel = Nabu::FixtureSentinel.new
    sources = args[:source] ? [args[:source]] : sentinel.sources
    results = sources.map { |source| sentinel.check(source) }
    results.each { |result| print_check_report(result) }
    abort "fixtures:check found drift or fetch/adapter-test failures" unless results.all?(&:ok?)

    # The cadence stamp (Nabu::Ops::ProofCadence): only a clean FULL run
    # re-proves the sentinel — a single-source check stamps nothing.
    next if args[:source]

    stamp = Nabu::Ops::ProofCadence.record!(local_dir: Nabu::Config.load.local_dir, proof: "fixtures-check",
                                            detail: "#{results.size} source(s) clean")
    puts "fixtures:check — all #{results.size} source(s) clean; cadence stamped at #{stamp}"
  end

  desc "Re-fetch and OVERWRITE checked-in fixtures for a source (explicit adoption)"
  task :refresh, [:source] do |_task, args|
    $LOAD_PATH.unshift(File.expand_path("lib", __dir__))
    require "nabu"

    source = Nabu::FixtureSentinel.demand_source(args[:source])
    result = Nabu::FixtureSentinel.new.refresh(source)
    puts "[#{result.source}] refreshed: #{result.updated.join(', ')}" unless result.updated.empty?
    puts "[#{result.source}] skipped (not refetchable): #{result.skipped.join(', ')}" unless result.skipped.empty?
    puts result.reminder
  end
end

# Fresh-machine restore drill (P7-2). Fully LOCAL: backs up the live tree to a
# tmp target, restores into a fresh tmp "machine", rebuilds from restored
# canonical, verifies, replays the golden queries, and cross-checks counts —
# proving "restorable from an rsync backup with zero services" without touching
# the live setup (backup is read-only on its sources; all writes go under tmp).
# The orchestrator runs this against the LIVE corpus at acceptance.
# ONE MODE since P77-r12: the backup carries no db/ (owner ruling 2026-08-16),
# so every drill is the pure three-folder restore + full re-derivation — THE
# LAW'S PROOF (P71-8). ops:drill_pure remains as the habitual alias.
namespace :ops do
  desc "THE LAW'S PROOF: back up the three folders, restore into a tmp root, rebuild, verify, assert derivation"
  task :drill do
    run_drill
  end

  desc "Alias of ops:drill (every drill is the pure drill since P77-r12)"
  task drill_pure: :drill
end

# The online db snapshot (Nabu::Ops::DbSnapshot — its class comment holds
# the WAL reasoning and the RESTORE procedure): every db/*.sqlite3 through
# VACUUM INTO, never a file copy. Owner-fired; refuses a missing/non-writable
# or occupied target and an in-progress rebuild.
namespace :db do
  desc "Snapshot every db/*.sqlite3 into TARGET_DIR via VACUUM INTO (online, WAL-safe; " \
       "a CACHE of derived state — restore per Nabu::Ops::DbSnapshot) (db:snapshot[target_dir])"
  task :snapshot, %i[target_dir] do |_t, args|
    $LOAD_PATH.unshift(File.expand_path("lib", __dir__))
    require "nabu"
    require "nabu/ops/db_snapshot"

    config = Nabu::Config.load
    rebuild_check = lambda do
      ledger = File.file?(config.history_path) ? Nabu::Store.connect(config.history_path, readonly: true) : nil
      Nabu::Ops::DbSnapshot.rebuild_in_progress(ledger: ledger, ps_output: Nabu::Ops::GitHooks.ps_output)
    ensure
      ledger&.disconnect
    end
    Nabu::Ops::DbSnapshot.new(db_dir: config.db_dir, target: args[:target_dir], rebuild_check: rebuild_check).run!
  rescue Nabu::Ops::DbSnapshot::Refused => e
    abort "db:snapshot refused — #{e.message}"
  end
end

# The text_normalized diet's reclaim pass (Nabu::Store::TextNormalizedDiet
# holds the design): rows stored in full whose search form is text or SQLite's
# lower(text) take the sentinel in place. Owner-fired; dry run first:
#   rake "diet:text_normalized[dry_run]"   — counts + projected bytes, no writes
#   rake "diet:text_normalized"            — the pass (resumes a saved cursor)
# BATCH=<ids per window> overrides the window size.
namespace :diet do
  desc "Slim stored passages.text_normalized to the ''/lower sentinels in place (owner-fired; " \
       "[dry_run] = count + projected bytes only; resumable; space returns at VACUUM/rebuild/db:snapshot)"
  task :text_normalized, %i[mode] do |_t, args|
    $LOAD_PATH.unshift(File.expand_path("lib", __dir__))
    require "nabu"
    require "nabu/ops/db_snapshot"
    require "nabu/store/text_normalized_diet"

    $stdout.sync = true
    dry_run = args[:mode].to_s == "dry_run"
    abort "diet:text_normalized — unknown mode #{args[:mode].inspect} (use [dry_run] or none)" \
      unless dry_run || args[:mode].to_s.empty?

    config = Nabu::Config.load
    abort "diet:text_normalized — no catalog at #{config.catalog_path}" unless File.file?(config.catalog_path)
    rebuild_check = lambda do
      ledger = File.file?(config.history_path) ? Nabu::Store.connect(config.history_path, readonly: true) : nil
      Nabu::Ops::DbSnapshot.rebuild_in_progress(ledger: ledger, ps_output: Nabu::Ops::GitHooks.ps_output)
    ensure
      ledger&.disconnect
    end
    catalog = Nabu::Store.connect(config.catalog_path)
    batch = Integer(ENV.fetch("BATCH", Nabu::Store::TextNormalizedDiet::BATCH_ROWS))
    Nabu::Store::TextNormalizedDiet.new(catalog: catalog, catalog_path: config.catalog_path, batch_rows: batch,
                                        rebuild_check: rebuild_check).run!(dry_run: dry_run)
  rescue Nabu::Store::TextNormalizedDiet::Refused => e
    abort "diet:text_normalized refused — #{e.message}"
  ensure
    catalog&.disconnect
  end
end

# The drill's harness discipline (P77-r12, after the 2026-08-15 night the
# owner reconstructed from a 724-byte log and 521 GB of leaked tmp):
# - every run logs to its OWN timestamped file under ~/Library/Logs/nabu/
#   (no shell redirect needed — two same-day runs can never clobber each
#   other's evidence again), and both paths print FIRST, before any work;
# - a CRASH (exception, ^C, kill) prints the real error into the log and
#   REMOVES the workspace — aborted runs prove nothing and keep nothing
#   (owner ruling 2026-08-16); the log is the evidence;
# - a COMPLETED failing drill keeps its workspace (report.txt,
#   verify-issues.tsv, the restored machine/ — the P77-r10 autopsy);
#   KEEP_WORKSPACE=1 additionally keeps it on success.
def run_drill
  $LOAD_PATH.unshift(File.expand_path("lib", __dir__))
  require "nabu"
  require "tmpdir"
  require_relative "lib/nabu/ops/proof_cadence"

  log_path = drill_log_path
  File.open(log_path, "w") do |log_file|
    log_file.sync = true
    say = lambda do |message|
      puts message
      log_file.puts message
    end

    config = Nabu::Config.load
    say.call "drill log       → #{log_path}"
    # P77-r14: the drill cleans its own mess — prior workspaces (kept
    # evidence included) are superseded by this run; small evidence
    # files are salvaged beside the logs, the ~290 GB bulk dies.
    Nabu::Ops::Drill.sweep_prior_workspaces!(salvage_root: File.dirname(log_path)).each do |swept|
      say.call "swept prior drill workspace #{swept[:workspace]}" \
               "#{" (evidence → #{swept[:salvaged]})" if swept[:salvaged]}"
    end
    workspace = Dir.mktmpdir("nabu-drill")
    say.call "drill workspace → #{workspace}"
    begin
      report = Nabu::Ops::Drill.new(config: config, workspace: workspace).run
    rescue Nabu::Ops::Drill::Error => e
      # A DESIGNED refusal (space guard, failed backup section): the
      # message is the whole diagnosis — no backtrace, no crash banner.
      say.call "DRILL REFUSED: #{e.message}"
      FileUtils.remove_entry(workspace)
      abort "ops:drill REFUSED — nothing was written; see above"
    rescue StandardError, SignalException => e
      # Log-and-abort, never swallowed: the crash, its cause (Shell errors
      # carry stderr in the message now), and the cleanup are all on record.
      say.call "DRILL CRASHED: #{e.class}: #{e.message}"
      say.call e.backtrace.first(15).join("\n") if e.backtrace
      FileUtils.remove_entry(workspace)
      say.call "workspace removed — an aborted run proves nothing and keeps nothing " \
               "(owner ruling 2026-08-16); this log is the evidence"
      abort "ops:drill CRASHED — see #{log_path}"
    end
    say.call report.render
    if report.ok? && ENV["KEEP_WORKSPACE"].to_s.empty?
      FileUtils.remove_entry(workspace)
    else
      say.call "drill workspace kept at #{workspace} (report.txt · verify-issues.tsv · the restored machine/)"
    end
    abort "ops:drill FAILED — db/ does NOT fully derive from the three folders (see #{log_path})" unless report.ok?

    # The cadence stamp (Nabu::Ops::ProofCadence): a passing drill only.
    stamp = Nabu::Ops::ProofCadence.record!(local_dir: config.local_dir, proof: "ops-drill",
                                            detail: "derivation proven; log #{log_path}")
    say.call "drill cadence stamped at #{stamp}"
  end
end

# One log file per run, timestamped to the second — never `>` over the
# previous run's evidence.
def drill_log_path
  dir = File.expand_path("~/Library/Logs/nabu")
  FileUtils.mkdir_p(dir)
  File.join(dir, "drill-#{Time.now.strftime('%Y-%m-%d_%H%M%S')}.log")
end

# The Han variant-fold table (P37-2). Regenerates lib/nabu/hani.rb from the
# HELD Unihan Variants data — read-only on canonical/, writes ONLY the
# generated lib file. Changing the table changes text_normalized for lzh/och:
# the conventions §9 rebuild-storm caveat applies (P36-1 fingerprints dirty;
# the owner schedules the re-derive). Provenance and the resolution rule live
# on Nabu::Ops::HaniFoldBuilder.
namespace :fold do
  desc "Regenerate lib/nabu/hani.rb from canonical/unihan/Unihan_Variants.txt (or [path])"
  task :hani, [:variants_path] do |_task, args|
    $LOAD_PATH.unshift(File.expand_path("lib", __dir__))
    require "nabu"

    path = args[:variants_path] || File.expand_path("canonical/unihan/Unihan_Variants.txt", __dir__)
    builder = Nabu::Ops::HaniFoldBuilder.new(variants_path: path)
    File.write(File.expand_path("lib/nabu/hani.rb", __dir__), builder.render)
    census = builder.census
    puts "lib/nabu/hani.rb regenerated: #{builder.table.size} pairs " \
         "(Unihan #{census.unihan_version}, file date #{census.unihan_date})"
    puts "refused: #{census.self_ambiguous.size} self-listing, #{census.multi_trad.size} multi-traditional, " \
         "#{census.trad_simp_conflicts.size} trad/simp conflicts, #{census.z_conflicts.size} z-conflicts, " \
         "#{census.cycles} cycle(s); #{census.semantic_lines_excluded} semantic lines excluded"
    puts "NOTE: a changed table changes lzh/och text_normalized — plan the §9 rebuild (owner-scheduled)."
  end

  desc "Regenerate lib/nabu/jpn.rb from Unihan (kJinmeiyoKanji/kJoyoKanji) + KANJIDIC2 variants"
  task :jpn, [:mappings_path, :kanjidic_path] do |_task, args|
    $LOAD_PATH.unshift(File.expand_path("lib", __dir__))
    require "nabu"

    mappings = args[:mappings_path] ||
               File.expand_path("canonical/unihan/Unihan_OtherMappings.txt", __dir__)
    kanjidic = args[:kanjidic_path] ||
               File.expand_path("canonical/edrdg/kanjidic2/kanjidic2.xml.gz", __dir__)
    builder = Nabu::Ops::JpnFoldBuilder.new(mappings_path: mappings, kanjidic_path: kanjidic)
    File.write(File.expand_path("lib/nabu/jpn.rb", __dir__), builder.render)
    census = builder.census
    puts "lib/nabu/jpn.rb regenerated: #{census.reform_pairs} reform 1:1 pairs, #{census.fold_entries} " \
         "fold entries (Unihan #{census.unihan_version}, KANJIDIC2 #{census.kanjidic_version})"
    puts "  lane 1 jinmeiyō: #{census.jinmeiyo_pairs}  lane 2 kanjidic 1:1: #{census.kanjidic_singles}  " \
         "merges: #{census.merges.size} (#{census.merges.values.sum(&:size)} olds)"
    puts "refused: #{census.ambiguous_refused.size} one-to-many ambiguous, " \
         "#{census.jinmeiyo_conflicts.size} jinmeiyō-lane conflicts; " \
         "dropped #{census.nfc_identity_dropped} NFC-identity"
    puts "NOTE: a changed table changes jpn text_normalized — plan the §9 rebuild (owner-scheduled)."
  end

  desc "Regenerate lib/nabu/xct.rb from config/ewts/rules.csv (or [rules_path])"
  task :xct, [:rules_path] do |_task, args|
    $LOAD_PATH.unshift(File.expand_path("lib", __dir__))
    require "nabu"

    path = args[:rules_path] || Nabu::Ops::XctFoldBuilder::RULES_PATH
    builder = Nabu::Ops::XctFoldBuilder.new(rules_path: path)
    File.write(File.expand_path("lib/nabu/xct.rb", __dir__), builder.render)
    puts "lib/nabu/xct.rb regenerated: #{builder.rows.size} rules (sha256 #{builder.rules_sha256[0, 12]})"
    puts "NOTE: a changed table changes xct/bod/otb text_normalized — plan the §9 rebuild (owner-scheduled)."
  end
end

# The Aozora gaiji IDS lane (P39-5). Regenerates config/gaiji/aozora-ids.tsv
# from the HELD, checked-in composition-description census (NOT canonical, NOT
# the catalog — a pure function of a small TSV, so it runs anywhere). Rung 2 of
# the P38-2 display ladder for aozora; full grammar + refusal policy on
# Nabu::Ops::AozoraIdsBuilder.
namespace :gaiji do
  desc "Regenerate config/gaiji/aozora-ids.tsv from config/gaiji/aozora-descriptions.tsv"
  task :aozora_ids, [:census_path] do |_task, args|
    $LOAD_PATH.unshift(File.expand_path("lib", __dir__))
    require "nabu"

    census = args[:census_path] ||
             File.expand_path("config/gaiji/aozora-descriptions.tsv", __dir__)
    builder = Nabu::Ops::AozoraIdsBuilder.new(census_path: census)
    File.write(File.expand_path("config/gaiji/aozora-ids.tsv", __dir__), builder.render)
    c = builder.census
    puts "config/gaiji/aozora-ids.tsv regenerated: #{c.derived} IDS entries from " \
         "#{c.descriptions} composition descriptions"
    pct = (100.0 * c.derived_occurrences / c.composition_occurrences).round(1)
    puts "  derived #{c.derived_occurrences}/#{c.composition_occurrences} composition " \
         "occurrences (#{pct}%)"
    puts "  refused: #{c.refused.map { |cls, n| "#{n} #{cls}" }.join(', ')}"
  end
end

# OWNER-ONLY escape hatch (P39-1): rewrite every derivation stamp against
# current code WITHOUT re-deriving — for fingerprint FORMULA changes only,
# valid ONLY immediately after a verified full rebuild on unchanged
# canonical. Misuse = silent under-derivation (the refusal message and
# Nabu::Ops::StampRebless spell it out; docs/ops.md "Derivation stamps").
namespace :stamps do
  desc "Rebless derivation stamps against current code (owner-only; requires attestation)"
  task :rebless, [:attestation] do |_task, args|
    $LOAD_PATH.unshift(File.expand_path("lib", __dir__))
    require "nabu"

    config = Nabu::Config.load
    registry = Nabu::SourceRegistry.load(config.sources_path)
    begin
      Nabu::Ops::StampRebless.new(config: config, registry: registry)
                             .run(attestation: args[:attestation])
    rescue Nabu::Error => e
      abort e.message
    end
  end

  # The BY-PROOF sibling (Nabu::Ops::StampProof): for semantic no-op
  # refactors (pure moves) that dirty every stamp. Each DIRTY source whose
  # drift is code-only re-parses a deterministic stratified sample through
  # current code WITHOUT writing the catalog; byte-identical => that
  # source's stamp is reblessed, any divergence => it stays dirty, named.
  # Never fetches. Its own attestation: canonical unchanged since stamping.
  desc "Rebless dirty stamps proven by a re-parse sample (owner-only; requires attestation[,sample])"
  task :rebless_by_proof, %i[attestation sample] do |_task, args|
    $LOAD_PATH.unshift(File.expand_path("lib", __dir__))
    require "nabu"

    $stdout.sync = true
    config = Nabu::Config.load
    registry = Nabu::SourceRegistry.load(config.sources_path)
    begin
      Nabu::Ops::StampProof.new(config: config, registry: registry)
                           .run(attestation: args[:attestation], sample: args[:sample])
    rescue Nabu::Error => e
      abort e.message
    end
  end
end

# The inspected-object text instrument (Nabu::Ops::InspectTextScrub): live
# passages of one source whose text is a printed Ruby Hash/object, found
# with the conformance invariant's own detector. Read-only, always: the
# default scans (count + samples); SCRUB=1 re-parses the affected documents
# in memory from canonical/ and prints the source-wide resync — there is no
# per-document sync path, and a document that now quarantines keeps its
# held rows until the next FULL rebuild (the loader's quarantine shield).
namespace :scrub do
  desc "Scan a source's live passages for inspect-shaped text; SCRUB=1 diagnoses the resync (read-only)"
  task :inspect_text, [:slug] do |_task, args|
    $LOAD_PATH.unshift(File.expand_path("lib", __dir__))
    require "nabu"

    slug = args[:slug] or abort 'usage: rake "scrub:inspect_text[slug]" (SCRUB=1 to diagnose)'
    config = Nabu::Config.load
    catalog = Nabu::Store.connect(config.catalog_path, readonly: true)
    scrub = ENV["SCRUB"] == "1"
    adapter = nil
    if scrub
      entry = Nabu::SourceRegistry.load(config.sources_path)[slug] or abort "scrub: unknown source #{slug}"
      adapter = entry.build_adapter
    end
    puts Nabu::Ops::InspectTextScrub.new(catalog: catalog, slug: slug, adapter: adapter, scrub: scrub,
                                         workdir: config.source_workdir(slug)).report
  rescue Nabu::Error => e
    abort e.message
  ensure
    catalog&.disconnect
  end
end

# The clarify lane (nabu_clarify's title index) re-derived standalone over
# the live catalog — a STAGE re-derive (the reconcile_stages! path the
# incremental rebuild takes), never a full reindex: it reads only names
# (document titles, sources, headwords, places) and writes only the
# fulltext clarify_* tables, then advances the "clarify" stage stamp.
# Catalog-only reads; minutes on the full library.
namespace :index do
  desc "Re-derive the nabu_clarify title index (fulltext clarify lane) over the live catalog"
  task :clarify do
    $LOAD_PATH.unshift(File.expand_path("lib", __dir__))
    require "nabu"

    config = Nabu::Config.load
    catalog = Nabu::Store.connect(config.catalog_path, readonly: true)
    fulltext = Nabu::Store.connect_fulltext(config.fulltext_path)
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    summary = Nabu::Store::Indexer.rebuild_clarify!(catalog: catalog, fulltext: fulltext, stamp: true)
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
    puts "index:clarify done — #{summary.fetch(:entries)} entries in " \
         "#{Object.new.extend(Nabu::DurationFormat).format_duration(elapsed)}"
  ensure
    catalog&.disconnect
    fulltext&.disconnect
  end

  # The translations lane (`search --translations`): annotation-held
  # translations (Nabu::TranslationKeys' registry sources) re-derived
  # standalone over the live catalog — the same stage re-derive shape as
  # clarify: reads only the registry sources' annotations, writes only
  # the fulltext passages_translations tables, advances the stage stamp.
  desc "Re-derive the annotation-held translations index (search --translations) over the live catalog"
  task :translations do
    $LOAD_PATH.unshift(File.expand_path("lib", __dir__))
    require "nabu"

    config = Nabu::Config.load
    catalog = Nabu::Store.connect(config.catalog_path, readonly: true)
    fulltext = Nabu::Store.connect_fulltext(config.fulltext_path)
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    summary = Nabu::Store::TranslationIndex.rebuild!(catalog: catalog, fulltext: fulltext, stamp: true)
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
    puts "index:translations done — #{summary.fetch(:passages)} passages from " \
         "#{summary.fetch(:sources)} sources in " \
         "#{Object.new.extend(Nabu::DurationFormat).format_duration(elapsed)}"
    fulltext[Nabu::Store::TranslationIndex::SCOPE_TABLE].order(:slug).each do |row|
      puts "  #{row.fetch(:slug)}: #{row.fetch(:passages)}"
    end
  ensure
    catalog&.disconnect
    fulltext&.disconnect
  end

  # The annotations lane (`search --annotations`): the declared searchable
  # annotation layers (Nabu::AnnotationKeys' sources). With no argument,
  # the index:translations shape — the whole lane re-derived standalone
  # over the live catalog, stage stamp advanced. With slugs
  # (`rake "index:annotations[cantus,korpus16]"`), the targeted builder:
  # each named source's slice derived alone (the lane created if absent),
  # every other slice untouched, the stamp left for a whole-lane pass.
  # Reads only those sources' annotations; writes only the fulltext
  # passages_annotations tables.
  desc "Re-derive the declared annotation layers index (search --annotations); [slug,…] = those sources only"
  task :annotations do |_task, args|
    $LOAD_PATH.unshift(File.expand_path("lib", __dir__))
    require "nabu"

    config = Nabu::Config.load
    catalog = Nabu::Store.connect(config.catalog_path, readonly: true)
    fulltext = Nabu::Store.connect_fulltext(config.fulltext_path)
    index = Nabu::Store::AnnotationIndex
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    slugs = args.extras
    if slugs.empty?
      summary = index.rebuild!(catalog: catalog, fulltext: fulltext, stamp: true)
      label = "#{summary.fetch(:passages)} passages from #{summary.fetch(:sources)} sources"
    else
      counts = slugs.map { |slug| index.build_source!(catalog: catalog, fulltext: fulltext, slug: slug) }
      label = "#{counts.sum} passages from #{slugs.join(', ')}"
    end
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
    puts "index:annotations done — #{label} in " \
         "#{Object.new.extend(Nabu::DurationFormat).format_duration(elapsed)}"
    fulltext[index::SCOPE_TABLE].order(:slug).each do |row|
      puts "  #{row.fetch(:slug)}: #{row.fetch(:passages)}"
    end
  ensure
    catalog&.disconnect
    fulltext&.disconnect
  end

  # The token-gloss lane (`search --gloss WORD` with no query): the
  # upstream token glosses of the Query::TokenGlosses sources re-derived
  # standalone over the live catalog — the index:translations shape:
  # reads only those sources' annotations, writes only the fulltext
  # token_glosses tables, advances the stage stamp.
  desc "Re-derive the token-gloss index (search --gloss WORD across lemmas) over the live catalog"
  task :glosses do
    $LOAD_PATH.unshift(File.expand_path("lib", __dir__))
    require "nabu"

    config = Nabu::Config.load
    catalog = Nabu::Store.connect(config.catalog_path, readonly: true)
    fulltext = Nabu::Store.connect_fulltext(config.fulltext_path)
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    summary = Nabu::Store::GlossIndex.rebuild!(catalog: catalog, fulltext: fulltext, stamp: true)
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
    puts "index:glosses done — #{summary.fetch(:words)} words (#{summary.fetch(:tokens)} tokens) from " \
         "#{summary.fetch(:sources)} sources in " \
         "#{Object.new.extend(Nabu::DurationFormat).format_duration(elapsed)}"
    fulltext[Nabu::Store::GlossIndex::SCOPE_TABLE].order(:slug).each do |row|
      puts "  #{row.fetch(:slug)}: #{row.fetch(:words)} words, #{row.fetch(:tokens)} tokens"
    end
  ensure
    catalog&.disconnect
    fulltext&.disconnect
  end

  # The gloss-lines lane (`search --gloss-lines`): each passage's token
  # glosses as one line (the Query::TokenGlosses sources). With no
  # argument, the index:annotations shape — the whole lane re-derived
  # standalone over the live catalog, stage stamp advanced. With slugs
  # (`rake "index:gloss_lines[bhsa,achemenet]"`), the targeted builder:
  # each named source's slice derived alone (the lane created if absent),
  # every other slice untouched, the stamp left for a whole-lane pass.
  # Reads only those sources' annotations; writes only the fulltext
  # passages_gloss_lines tables.
  desc "Re-derive the token gloss-lines index (search --gloss-lines); [slug,…] = those sources only"
  task :gloss_lines do |_task, args|
    $LOAD_PATH.unshift(File.expand_path("lib", __dir__))
    require "nabu"

    config = Nabu::Config.load
    catalog = Nabu::Store.connect(config.catalog_path, readonly: true)
    fulltext = Nabu::Store.connect_fulltext(config.fulltext_path)
    index = Nabu::Store::GlossLineIndex
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    clock = Object.new.extend(Nabu::DurationFormat)
    elapsed = -> { clock.format_duration(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) }
    slugs = args.extras
    if slugs.empty?
      summary = index.rebuild!(catalog: catalog, fulltext: fulltext, stamp: true)
      label = "#{summary.fetch(:passages)} passages from #{summary.fetch(:sources)} sources"
    else
      # One progress line per finished source — readable DURING the run.
      counts = slugs.map do |slug|
        index.build_source!(catalog: catalog, fulltext: fulltext, slug: slug)
             .tap { |count| puts "  #{slug}: #{count} passages (#{elapsed.call} elapsed)" }
      end
      label = "#{counts.sum} passages from #{slugs.join(', ')}"
    end
    puts "index:gloss_lines done — #{label} in #{elapsed.call}"
    fulltext[index::SCOPE_TABLE].order(:slug).each do |row|
      puts "  #{row.fetch(:slug)}: #{row.fetch(:passages)}"
    end
  ensure
    catalog&.disconnect
    fulltext&.disconnect
  end
end

# The short handle (owner request 2026-07-22). Same task, same attestation
# guard — the friction lives in the ARGUMENT (a claim you must be able to
# make truthfully), not the task name.
desc "Short alias for stamps:rebless (owner-only; requires attestation)"
task :bless, [:attestation] do |_task, args|
  Rake::Task["stamps:rebless"].invoke(args[:attestation])
end

# Gate rider (P24-0, site/MAINTENANCE.md standing duty): flag drift between
# the canonical/local-source dossier descriptions and the public map
# (docs/library.md; site/library.md is its printed copy, covered
# transitively). Presence/mention check, never verbatim equality — the rule
# is journaled in Nabu::Ops::DossierDrift. Never generates; exit 1 on drift.
namespace :site do
  desc "Gate check: source-dossier descriptions vs docs/library.md (drift = exit 1)"
  task :check do
    $LOAD_PATH.unshift(File.expand_path("lib", __dir__))
    require "nabu"

    config = Nabu::Config.load
    check = Nabu::Ops::DossierDrift.new(
      shelf_dir: Nabu::SourceShelf.dir(config),
      registry: Nabu::SourceRegistry.load(config.sources_path),
      library_md: File.expand_path("docs/library.md", __dir__),
      site_library_md: File.expand_path("site/library.md", __dir__)
    )
    findings = check.findings
    findings.each { |finding| puts "DRIFT #{finding.slug} — #{finding.message}" }
    if findings.empty?
      puts "site:check clean — dossier descriptions and docs/library.md cover each other"
    else
      abort "site:check found #{findings.size} drift finding(s)"
    end
  end

  desc "Regenerate the per-axis site pages (site/axis/*.md + /axis/ index) from the registry + fragments + live counts"
  task :axes do
    $LOAD_PATH.unshift(File.expand_path("lib", __dir__))
    require "nabu"
    require "date"

    config = Nabu::Config.load
    # The catalog is read READ-ONLY for the holdings numbers; NABU_AXES_CATALOG
    # points the generator at another checkout's live db (a worktree run wants
    # the main checkout's synced catalog for honest, dated counts).
    catalog_path = ENV.fetch("NABU_AXES_CATALOG", config.catalog_path)
    generator = Nabu::Ops::AxisPages.new(
      registry: Nabu::SourceRegistry.load(config.sources_path),
      fragments_path: File.expand_path("site/axis/_fragments.yml", __dir__),
      output_dir: File.expand_path("site/axis", __dir__),
      catalog_path: catalog_path,
      # The lemma shelf's holdings live in fulltext (P105-5a) — the
      # sibling file beside whichever catalog is being read.
      fulltext_path: File.join(File.dirname(catalog_path), Nabu::Config::FULLTEXT_DB_FILENAME),
      as_of: Date.today
    )
    results = generator.generate!
    counts = File.exist?(catalog_path) ? "live catalog #{catalog_path}" : "no catalog (holdings say so)"
    puts "site:axes wrote #{results.size} pages (#{results.size - 1} desks + index) — #{counts}"
  end

  desc "Serve the site for staged-change review (port 4747; PORT=n overrides — 4000 stays with siblings)"
  task :preview do
    port = ENV.fetch("PORT", "4747")
    puts "site:preview → http://127.0.0.1:#{port}/nabu/  (Ctrl-C stops)"
    # No livereload: its default port (35729) is another cross-project
    # collision on a box that previews sibling sites (nabu-edubba).
    site_dir = File.expand_path("site", __dir__)
    # The site has its OWN Gemfile + vendor/bundle (no .bundle/config on
    # disk); shed the root bundle's env or `bundle exec` resolves against
    # the root Gemfile (no jekyll there), and point BUNDLE_PATH at the
    # vendored gems explicitly.
    env = {
      "BUNDLE_GEMFILE" => File.join(site_dir, "Gemfile"),
      "BUNDLE_PATH" => File.join(site_dir, "vendor", "bundle")
    }
    exec(env, "bundle", "exec", "jekyll", "serve",
         "--port", port, "--host", "127.0.0.1",
         chdir: site_dir)
  end
end

# Gate rider (P35-6, dev-loop §6b rule 3): every era-bound literal in
# query/render/fetch code carries its `# census: <n>, <date>[, basis]` or
# `# const: <reason>` justification. PRESENCE check only (staleness is the
# gate reviewer's re-diff duty); also enforced inside the suite
# (test/ops/census_check_test.rb), so `rake test` catches an unstamped
# literal the day it lands. Exit 1 lists the misses.
namespace :census do
  desc "Gate check: era-bound literals carry # census:/# const: markers (miss = exit 1)"
  task :check do
    $LOAD_PATH.unshift(File.expand_path("lib", __dir__))
    require "nabu"

    findings = Nabu::Ops::CensusCheck.new(root: __dir__).findings
    findings.each { |f| puts "UNSTAMPED #{f.path}:#{f.line} #{f.constant} — #{f.message}" }
    if findings.empty?
      puts "census:check clean — every era-bound literal carries its census/const marker"
    else
      abort "census:check found #{findings.size} unstamped era-bound literal(s)"
    end
  end
end

# The lect: filter timing harness (Nabu::Ops::LectFilterBench): per
# (term, lect) case, the same search with and without the lect filter,
# median wall times printed. Both databases open READONLY (the engine
# refuses writes). Overrides: CATALOG=/path/catalog.sqlite3
# FULLTEXT=/path/fulltext.sqlite3 CASES="rex@lat,λόγος@grc:koi" REPEATS=5
# LIMIT=20 LECTS=/path/nabu-lects (a registry checkout, bare — default:
# the instance's canonical/nabu-lects with its overrides and overlay).
# The working boards' numbering self-check. The boards (.docs/) are
# gitignored LOCAL files: a checkout without them — any public clone, a
# lane worktree — gets an announced skip and exit 0. BOARDS_DIR overrides
# the location (e.g. a worktree checking the main checkout's boards).
# The same task runs the GH watch-list staleness guard
# The post-release directory probe (ops §12 step 8): the Glama listing
# auto-rebuilds from every GitHub release, and a broken rebuild fails on
# THEIR builder where our CI never looks. The probe reads the public
# listing page (released version visible?) and the score badge (grade,
# informational). VERSION=x.y.z overrides the checked-out Nabu::VERSION.
namespace :release do
  desc "Post-release check: the released version is visible on the Glama listing (missing = exit 1)"
  task :glama do
    require_relative "lib/nabu/ops/glama_release_check"
    version = ENV.fetch("VERSION", Nabu::VERSION)
    report = Nabu::Ops::GlamaReleaseCheck.new(version: version).run
    report.findings.each { |finding| puts "STALE  glama listing: #{finding}" }
    abort "release:glama — #{version} not confirmed on the listing" unless report.clean?

    grade = report.grade ? "score #{report.grade}" : "score not evaluated yet (their queue)"
    puts "release:glama — #{version} visible on #{Nabu::Ops::GlamaReleaseCheck::LISTING_URL} · #{grade}"
  end
end

# Software Heritage "save code now" for the whole repo family — ONE
# owner-fired command (direct POSTs are permission-gated in loop
# sessions): asks SWH to archive each repo and prints the snapshot
# SWHIDs already on record (a fresh save's SWHID appears on a LATER
# run — their queue). Rejected saves fail the task.
namespace :outreach do
  desc "Software Heritage save-code-now for arvicco/nabu + sisters; prints recorded SWHIDs"
  task :swh do
    require_relative "lib/nabu/ops/swh_save"
    report = Nabu::Ops::SwhSave.new.run
    report.rows.each do |row|
      swhid = row.snapshot_swhid || "no visit recorded yet (their queue)"
      puts format("  %<repo>-14s save: %<status>-9s %<swhid>s", repo: row.repo, status: row.request_status,
                                                                swhid: swhid)
    end
    report.findings.each { |finding| puts "FINDING  #{finding}" }
    abort "outreach:swh — #{report.findings.size} finding(s)" unless report.clean?

    puts "outreach:swh — #{report.rows.size} repos saved/queued at archive.softwareheritage.org"
  end

  # The channel-surface probe (Nabu::Ops::OutreachProbe): informational,
  # never fails on an unmet expectation — the table IS the product.
  desc "Probe the outreach channel surfaces from .docs/outreach/probes.yml; one delta line per probe. " \
       "Rows (a top-level `probes:` list): {name, kind: http, url, expect: 200|\"substring\"} · " \
       "{name, kind: registry, q, expect?: \"name substring\"} · " \
       "{name, kind: gh_pr|gh_issue, repo: owner/repo, number, expect?: OPEN|MERGED|CLOSED}; " \
       "the previous run's observations live beside it in probes-last.yml (the delta)"
  task :probe do
    require_relative "lib/nabu/ops/outreach_probe"
    dir = ENV.fetch("BOARDS_DIR", File.expand_path(".docs", __dir__))
    report = Nabu::Ops::OutreachProbe.new(boards_dir: dir).run
    if report.skipped
      puts "outreach:probe — no #{Nabu::Ops::OutreachProbe::FILE} under #{dir} (a public clone or a worktree); skipped"
      next
    end
    report.results.each { |result| puts "  #{result.line}" }
    puts "outreach:probe — #{report.results.size} probe(s): #{report.changed} changed, " \
         "#{report.unmet} expectation(s) not met"
  rescue Nabu::Ops::OutreachProbe::ProbeError => e
    abort "outreach:probe — #{e.message}"
  end
end

# The documented command flows EXECUTED, not proofread
# (Nabu::Ops::DocsVerify; the plan is config/docs_verify.yml): the
# quickstart walkthroughs, the README install block and the MCP
# registration recipes run in a throwaway sandbox (a fresh clone of the
# committed HEAD), one OK/FAIL verdict line per documented claim. The
# default mode is offline (network steps print NET and never run; an
# unroutable proxy guards the rest); `rake "docs:verify[network]"` adds the
# real syncs (the starter shelf: ~690 MB, ten to fifteen minutes).
namespace :docs do
  desc "Run the documented command flows in a fresh-clone sandbox; [network] adds the real syncs"
  task :verify, [:mode] do |_task, args|
    require_relative "lib/nabu/ops/docs_verify"
    mode = args[:mode].to_s == "network" ? :network : :offline
    abort "docs:verify — unknown mode #{args[:mode].inspect} (offline or network)" unless
      [nil, "", "offline", "network"].include?(args[:mode])
    ok = Nabu::Ops::DocsVerify.run_sandboxed(repo: __dir__, mode: mode)
    abort "docs:verify — documented claims failed (verdict lines above)" unless ok
  end
end

# (Nabu::Ops::WatchListCheck): any still-watched row whose checked date is
# over a week old fails the task, named; boards without the section skip.
# And the phase-register freshness probe (Nabu::Ops::PhaseRegisterCheck):
# the register's newest `## P<N>` row must reach the highest phase merged
# on the local main branch (git log, offline); no register file skips.
# And the declared-rule liveness probe (Nabu::Ops::RuleLivenessCheck): a
# lect facet rule whose source holds live documents but which never
# compiled a journal row fails, named; no catalog/journal skips.
# And the standing-proof cadence probe (Nabu::Ops::ProofCadence): ops:drill
# and a full fixtures:check each stamp local/proofs/<proof>.yml on success;
# either unstamped or older than 60 days fails, named; no local/proofs/ skips.
# And the incident-register status probe (Nabu::Ops::IncidentRegisterCheck):
# every incident row's (`## <sigil>I-n ·`) bracketed suffix must carry OPEN, CLOSED,
# FIX-STAGED or MITIGATED — a row without one fails, named; no register skips.
namespace :boards do
  desc "Gate check: register 'Next number' headers vs minted numbers + GH watch-list staleness " \
       "+ phase-register freshness vs merged phases + incident-row status tokens (stale = exit 1)"
  task :check do
    require_relative "lib/nabu/ops/board_check"
    require_relative "lib/nabu/ops/watch_list_check"
    require_relative "lib/nabu/ops/phase_register_check"
    require_relative "lib/nabu/ops/acquisition_check"
    require_relative "lib/nabu/ops/queue_groom_check"
    require_relative "lib/nabu/ops/source_readiness_check"
    require_relative "lib/nabu/ops/rule_liveness_check"
    require_relative "lib/nabu/ops/incident_register_check"
    require_relative "lib/nabu/ops/decision_register_check"
    require_relative "lib/nabu/ops/proof_cadence"
    dir = ENV.fetch("BOARDS_DIR", File.expand_path(".docs", __dir__))
    report = Nabu::Ops::BoardCheck.new(boards_dir: dir).run
    if report.skipped
      puts "boards:check — no boards at #{dir} (a public clone or a worktree); skipped"
      next
    end
    report.findings.each { |finding| puts "STALE  #{finding.register}: #{finding.message}" }

    watch = Nabu::Ops::WatchListCheck.new(boards_dir: dir).run
    watch.findings.each { |finding| puts "STALE  watch list #{finding}" }

    phases = Nabu::Ops::PhaseRegisterCheck.new(
      register_path: File.join(dir, Nabu::Ops::PhaseRegisterCheck::FILE), repo: __dir__
    ).run
    phases.findings.each { |finding| puts "STALE  phase register #{finding}" }

    incidents = Nabu::Ops::IncidentRegisterCheck.new(
      register_path: File.join(dir, Nabu::Ops::IncidentRegisterCheck::FILE)
    ).run
    incidents.findings.each { |finding| puts "STALE  incident register #{finding}" }

    decisions = Nabu::Ops::DecisionRegisterCheck.new(
      register_path: File.join(dir, Nabu::Ops::DecisionRegisterCheck::FILE)
    ).run
    decisions.findings.each { |finding| puts "STALE  decision register #{finding}" }

    require_relative "lib/nabu/ops/rail_plan"
    acquisition = Nabu::Ops::AcquisitionCheck.new(
      boards_dir: dir, adapters_dir: File.expand_path("lib/nabu/adapters", __dir__),
      ledger_path: File.expand_path("local/history.sqlite3", __dir__),
      suspensions: Nabu::Ops::RailPlan.suspensions(Nabu::SourceRegistry.load(Nabu::Config.load.sources_path))
    ).run
    acquisition.findings.each { |finding| puts "STALE  acquisition #{finding}" }

    groom = Nabu::Ops::QueueGroomCheck.new(boards_dir: dir).run
    groom.findings.each { |finding| puts "STALE  #{finding}" }

    readiness = Nabu::Ops::SourceReadinessCheck.new(
      sources_path: File.expand_path("config/sources", __dir__),
      ledger_path: File.expand_path("local/history.sqlite3", __dir__)
    ).run
    readiness.findings.each { |finding| puts "STALE  readiness #{finding}" }

    liveness = Nabu::Ops::RuleLivenessCheck.new(
      rules_paths: [File.expand_path("config/lect_facet_rules.yml", __dir__),
                    File.expand_path("local/config/lect_facet_rules.yml", __dir__)],
      catalog_path: File.expand_path("db/catalog.sqlite3", __dir__),
      journal_path: File.expand_path("db/lects.sqlite3", __dir__)
    ).run
    liveness.findings.each { |finding| puts "STALE  rule liveness #{finding}" }

    cadence = Nabu::Ops::ProofCadence::Check.new(local_dir: File.expand_path("local", __dir__)).run
    cadence.findings.each { |finding| puts "STALE  proof cadence #{finding}" }

    failures = []
    failures << "#{report.findings.size} stale register header(s)" unless report.clean?
    failures << "#{watch.findings.size} stale GH watch row(s)" unless watch.clean?
    failures << "phase register behind the merged phases" unless phases.clean?
    failures << "#{incidents.findings.size} status-less incident row(s)" unless incidents.clean?
    failures << "#{decisions.findings.size} parked ruled decision row(s)" unless decisions.clean?
    failures << "#{acquisition.findings.size} acquisition-duty finding(s)" unless acquisition.clean?
    failures << "#{groom.findings.size} ungroomed queue row(s)" unless groom.clean?
    failures << "#{readiness.findings.size} never-synced source(s)" unless readiness.clean?
    failures << "#{liveness.findings.size} never-compiled lect rule(s)" unless liveness.clean?
    failures << "#{cadence.findings.size} overdue standing proof(s)" unless cadence.clean?
    abort "boards:check — #{failures.join(', ')}" unless failures.empty?

    puts "boards:check — #{report.registers.size} register header(s) current: #{report.registers.join(', ')}"
    if watch.skipped
      puts "boards:check — no GH watch list section on the boards; watch check skipped"
    else
      puts "boards:check — #{watch.rows} GH watch row(s) checked within " \
           "#{Nabu::Ops::WatchListCheck::MAX_AGE_DAYS} days"
    end
    if phases.skipped
      puts "boards:check — no #{Nabu::Ops::PhaseRegisterCheck::FILE} on the boards; phase-register probe skipped"
    else
      merged = phases.highest_merged ? "P#{phases.highest_merged}" : "none"
      puts "boards:check — phase register current: newest row P#{phases.newest_row}, highest merged phase #{merged}"
    end
    if incidents.skipped
      puts "boards:check — no #{Nabu::Ops::IncidentRegisterCheck::FILE} on the boards; incident-status probe skipped"
    else
      puts "boards:check — #{incidents.rows} incident row(s) each carry a status token"
    end
    puts "boards:check — acquisition duties current (segment named, rail fresh, roster suspensions match)" if
      acquisition.clean?
    puts "boards:check — #{groom.summary} (phase-register cross-check clean)" unless groom.skipped
    puts "boards:check — every registered source has ledger runs (readiness probe clean)" unless readiness.skipped
    if liveness.skipped
      puts "boards:check — no catalog/lect journal/rules on this box; rule-liveness probe skipped"
    else
      puts "boards:check — #{liveness.rules} declared lect rule(s) live (rule-liveness probe clean)"
    end
    if cadence.skipped
      puts "boards:check — no local/#{Nabu::Ops::ProofCadence::DIRNAME}/ on this box; proof-cadence probe skipped"
    else
      stamps = cadence.stamps.map { |proof, date| "#{proof} #{date.iso8601}" }.join(", ")
      puts "boards:check — standing proofs run within #{Nabu::Ops::ProofCadence::MAX_AGE_DAYS} days: #{stamps}"
    end
  end
end

namespace :bench do
  desc "Time the lect: filter's catalog-join path over a catalog (read-only)"
  task :lect_filter do
    $LOAD_PATH.unshift(File.expand_path("lib", __dir__))
    require "nabu"

    config = Nabu::Config.load
    catalog = Nabu::Store.connect(ENV.fetch("CATALOG", config.catalog_path), readonly: true)
    fulltext = Nabu::Store.connect_fulltext(ENV.fetch("FULLTEXT", config.fulltext_path), readonly: true)
    lects = (ENV["LECTS"] ? Nabu::Lects.load(ENV["LECTS"]) : Nabu::Lects.load_default(config: config)) or
      abort "bench:lect_filter: nabu-lects module not synced"
    bench = Nabu::Ops::LectFilterBench.new(catalog: catalog, fulltext: fulltext, lects: lects,
                                           repeats: Integer(ENV.fetch("REPEATS", "5")),
                                           limit: Integer(ENV.fetch("LIMIT", "20")))
    cases = Nabu::Ops::LectFilterBench.parse_cases(ENV.fetch("CASES", Nabu::Ops::LectFilterBench::DEFAULT_CASES))
    puts bench.report(bench.run(cases))
  ensure
    catalog&.disconnect
    fulltext&.disconnect
  end

  desc "Parallels recall@K against a held gold set (GOLD=edh-edr|…|census, PRODUCER, K, SAMPLE, SEED; read-only)"
  task :parallels do
    $LOAD_PATH.unshift(File.expand_path("lib", __dir__))
    require "nabu"

    bench_class = Nabu::Ops::ParallelsBench
    options = bench_class.options_from_env(ENV)
    config = Nabu::Config.load
    catalog = Nabu::Store.connect(config.catalog_path, readonly: true)
    links = Nabu::Store::LinkLayers.open_readonly(config) or abort "bench:parallels: no links journal on this box"
    bench = bench_class.new(links: links, catalog: catalog)
    if options.gold == "census"
      puts bench_class.render_census(bench.census)
      next
    end

    fulltext = Nabu::Store.connect_fulltext(config.fulltext_path, readonly: true)
    producer = bench_class.producer_for(options, catalog: catalog, fulltext: fulltext, links: links)
    report = bench.run(gold: bench.gold_set(bench_class.recipe(options.gold)), producer: producer,
                       ks: options.ks, sample: options.sample, seed: options.seed)
    puts bench_class.render(report)
    path = options.out || bench_class.default_sidecar(db_dir: config.db_dir, report: report)
    puts "  sidecar: #{bench_class.write_sidecar(report, path)}"
  rescue Nabu::Error => e
    abort e.message
  ensure
    catalog&.disconnect
    fulltext&.disconnect
    links&.disconnect
  end
end

# Print one check result to stdout.
def print_check_report(result)
  puts "[#{result.source}]"
  result.files.each do |f|
    detail = f.detail ? " (#{f.detail})" : ""
    puts "  #{f.status}: #{f.path}#{detail}"
  end
  at = result.adapter_test
  puts "  adapter test: #{adapter_test_label(at)}" if at
  puts "  => #{result.ok? ? 'clean' : 'DRIFT'}"
end

def adapter_test_label(adapter_test)
  return "skipped (#{adapter_test.detail})" unless adapter_test.ran

  adapter_test.passed ? "passed" : "FAILED"
end

task default: :test

# The one-command phase gate (Nabu::Ops::GatePipeline): site:refresh →
# skills:scaffold → test → lint → boards:check → site:check, each step its
# own child rake process whose real exit status decides; the first red step
# stops the run, named with its exit code. One flushed line per step with
# its elapsed seconds. The step tasks stay runnable on their own.
desc "The phase gate in one command: site:refresh, skills:scaffold, test, lint, boards:check, " \
     "site:check (first red stops, exit 1)"
task :gate do
  require_relative "lib/nabu/ops/gate_pipeline"
  gate = Nabu::Ops::GatePipeline
  report = gate.new(runner: gate.rake_runner(rakefile: File.expand_path("Rakefile", __dir__))).run
  abort "gate: RED at #{report.failed_step} (exit #{report.exit_status})" unless report.green?
end

# The single-source-of-truth site data projection (P58 rider): registry +
# live-census facts into site/_data/*.yml, read by the pages through Liquid —
# a new desk or a fresh census lands everywhere by regeneration, never by
# prose-chasing. The drift guard (test/site/site_data_test.rb) fails the
# suite when the committed desks.yml goes stale against the registry.
namespace :site do
  desc "Regenerate site/_data (desks + census) and site/llms.txt from the registries and the live catalog"
  task :data do
    $LOAD_PATH.unshift(File.expand_path("lib", __dir__))
    require "nabu"

    config = Nabu::Config.load
    catalog_path = ENV.fetch("NABU_AXES_CATALOG", config.catalog_path)
    fulltext_path = ENV.fetch("NABU_SITE_FULLTEXT", config.fulltext_path)
    abort "site:data needs the live catalog (#{catalog_path})" unless File.exist?(catalog_path)
    abort "site:data needs the fulltext index (#{fulltext_path})" unless File.exist?(fulltext_path)
    # The canonical tree quickstart's disk figures measure (one du walk);
    # a worktree run points NABU_SITE_CANONICAL at the main checkout's.
    canonical_dir = ENV.fetch("NABU_SITE_CANONICAL", config.canonical_dir)
    abort "site:data needs the canonical tree (#{canonical_dir})" unless File.directory?(canonical_dir)

    written = Nabu::Ops::SiteData.new(
      registry: Nabu::SourceRegistry.load(config.sources_path),
      data_dir: File.expand_path("site/_data", __dir__),
      catalog_path: catalog_path, fulltext_path: fulltext_path, canonical_dir: canonical_dir
    ).generate!
    # llms.txt renders from the SSOT files just written — never typed.
    written << Nabu::Ops::LlmsTxt.write!(site_dir: File.expand_path("site", __dir__))
    puts "site:data wrote #{written.join(', ')}"
  end

  # The /sources/ corpus table: one row per live public source (registry
  # membership) with the hand prose of site/_data/source_notes.yml — a pure
  # projection, no catalog needed (holdings render from sources.yml at
  # build). The suite's drift guard fails until it is re-run.
  desc "Regenerate the /sources/ corpus table (site/_includes/sources_table.md) from the registry + source notes"
  task :sources do
    $LOAD_PATH.unshift(File.expand_path("lib", __dir__))
    require "nabu"

    config = Nabu::Config.load
    table = Nabu::Ops::SourcesTable.load(registry: Nabu::SourceRegistry.load(config.sources_path),
                                         site_dir: File.expand_path("site", __dir__))
    path = table.write!
    puts "site:sources wrote #{path} — #{table.slugs.size} live public sources, " \
         "#{table.pending.size} description(s) pending"
    warn "site:sources: notes for sources not live and public: #{table.orphans.join(', ')}" unless table.orphans.empty?
  end

  desc "The one gate refresh: site:data + site:axes + site:sources"
  task refresh: %i[data axes sources]
end

# The MCP skill pack (docs/mcp.md §8): skills/nabu-<desk>/SKILL.md per
# research desk. scaffold creates a missing desk's skeleton (seed prose
# from this box's source dossiers + the live-verified examples curated in
# site/axis/_mcp.yml) and re-projects every skill's managed
# sources lanes from the registry — prose is never rewritten. check is the
# read-only drift report (the suite's test/skills guard enforces the same).
namespace :skills do
  skill_pack = lambda do
    $LOAD_PATH.unshift(File.expand_path("lib", __dir__))
    require "nabu"

    config = Nabu::Config.load
    shelf = Nabu::SourceShelf.new(dir: Nabu::SourceShelf.dir(config))
    dossier = lambda do |slug|
      shelf.load(slug)&.description
    rescue Nabu::SourceDossier::FormatError
      nil
    end
    examples_path = File.expand_path("site/axis/_mcp.yml", __dir__)
    examples = (YAML.safe_load_file(examples_path) || {}).transform_values { |axis| axis["mcp"] }
    Nabu::Ops::SkillPack.new(registry: Nabu::SourceRegistry.load(config.sources_path),
                             skills_dir: File.expand_path("skills", __dir__),
                             dossier: dossier, examples: examples)
  end

  desc "Scaffold missing desk skills + refresh every skill's managed sources block from the registry"
  task :scaffold do
    skill_pack.call.sync!.each do |result|
      puts "#{result.action.to_s.ljust(9)} #{result.path}" unless result.action == :unchanged
    end
  end

  desc "Drift check: desk skills whose managed sources lanes disagree with the registry (stale = exit 1)"
  task :check do
    stale = skill_pack.call.stale
    abort "skills:check: stale — run `rake skills:scaffold`:\n  #{stale.join("\n  ")}" unless stale.empty?
    puts "skills:check: every desk skill matches the registry"
  end
end

# External-tool bootstraps (owner rule 2026-09-03): every tool an
# enrichment lane runs on installs through ONE tracked, idempotent task
# — never a list of shell incantations handed to a human. Network-
# capable, human-initiated only; the suite tests the logic with
# injected shells/downloads (test/tool_bootstrap_test.rb) and never
# runs these. Thin wrappers; all logic in Nabu::ToolBootstrap.
namespace :tools do
  desc "Install the WHOLE semantic-search stack (venv + model + sqlite-vec); idempotent"
  task :embed do
    $LOAD_PATH.unshift(File.expand_path("lib", __dir__))
    require "nabu"
    Nabu::ToolBootstrap.new.embed!
  end

  desc "Install the silver-lemma stack (venv + stanza + models); LANG defaults to la"
  task :stanza, [:lang] do |_task, args|
    $LOAD_PATH.unshift(File.expand_path("lib", __dir__))
    require "nabu"
    Nabu::ToolBootstrap.new.stanza!(lang: args[:lang] || "la")
  end

  desc "Show the tool board: what is installed, where, and what isn't"
  task :status do
    $LOAD_PATH.unshift(File.expand_path("lib", __dir__))
    require "nabu"
    Nabu::ToolBootstrap.new.print_status
    Nabu::Ops::GitHooks::Installer.new(root: __dir__).status.each do |tool, state|
      puts format("%<tool>-52s %<state>s", tool: tool, state: state)
    end
  end

  # The local git hook pack (conflict markers, the mid-rebuild hold,
  # commit-message attribution/id refusals). Symlinks the tracked
  # script/git-hooks/* into the shared hooks dir — no network, idempotent.
  # Lives beside ToolBootstrap rather than in it: lib/nabu/ops/ sits
  # outside the derivation fingerprint's shared core, so the hook pack
  # never dirties a stamp.
  desc "Install the git hook pack (pre-commit + commit-msg symlinks); idempotent"
  task :hooks do
    require_relative "lib/nabu/ops/git_hooks"
    Nabu::Ops::GitHooks::Installer.new(root: __dir__).install!
  end
end

# Lane worktrees run the STRICT suite: link the main checkout's
# local/{fixtures,shelves,config} into this worktree's local/ so the
# StrictSkips gate binds as on the main checkout. Idempotent; a no-op on
# the main checkout. All logic in Nabu::Ops::WorktreePrep.
namespace :worktree do
  desc "Link the main checkout's local/{fixtures,shelves,config} into this worktree; idempotent"
  task :prepare do
    require_relative "lib/nabu/ops/worktree_prep"
    Nabu::Ops::WorktreePrep.new(root: __dir__).prepare!
  end
end

# The standalone corpus-wide builder pass (P104; owner rule 2026-09-26:
# rebuilds are owner-fired INTER-PHASE steps — a phase's builder-side
# changes refresh projections through this task, never via a rebuild).
# The O(1) library accounting (Store::SourceAggregates, migration 054):
# the one-time population of an existing live catalog. Counts are
# recounted from the catalog (one documents scan + one passages-join scan
# — minutes at full-library scale, the migration-019 backfill's price);
# the fulltext columns come from the index file's own finish stamps,
# pending markers and O(1) behind probes (read-only on the index). Every
# later write keeps the table current; `nabu rebuild` re-derives it.
namespace :aggregates do
  desc "Backfill the per-source O(1) accounting table (source_aggregates) from the live catalog + index"
  task :backfill do
    $LOAD_PATH.unshift(File.expand_path("lib", __dir__))
    require "nabu"

    config = Nabu::Config.load
    catalog = Nabu::Store.connect(config.catalog_path)
    abort "aggregates:backfill — catalog predates migration 054 (run a sync or rebuild first)" \
      unless Nabu::Store::SourceAggregates.available?(catalog)

    fulltext = (Nabu::Store.connect_fulltext(config.fulltext_path, readonly: true) if File.exist?(config.fulltext_path))
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    rows = Nabu::Store::SourceAggregates.backfill!(catalog: catalog, fulltext: fulltext)
    totals = Nabu::Store::SourceAggregates.rollup(catalog)
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
    puts "aggregates:backfill done — #{rows} sources · #{totals.fetch(:documents_count)} documents · " \
         "#{totals.fetch(:passages_count)} passages · #{totals.fetch(:behind_sources)} behind in " \
         "#{Object.new.extend(Nabu::DurationFormat).format_duration(elapsed)}"
  ensure
    catalog&.disconnect
    fulltext&.disconnect
  end
end

namespace :builders do
  # Verbose (Ops::StageGuide — the intro + one green line per stage):
  # `rake builders:refresh[verbose]` or `rake --verbose builders:refresh`.
  desc "Re-project timeline + places + facets + kind axis + lect facets + " \
       "dictionary stats + derge titles + lemma rollups over the live catalog ([verbose] explains each stage)"
  task :refresh, [:verbose] do |_task, args|
    $LOAD_PATH.unshift(File.expand_path("lib", __dir__))
    require "nabu"
    config = Nabu::Config.load
    catalog = Sequel.connect("sqlite://#{File.join(config.db_dir, 'catalog.sqlite3')}")
    verbose = args[:verbose] == "verbose" || Rake::FileUtilsExt.verbose_flag == true
    narrator = verbose ? Nabu::Ops::StageGuide::Narrator.new(io: $stdout) : nil
    narrator&.intro(:builders_refresh)
    progress = Nabu::ProgressReporter.new(
      on_stage: ->(name, _eta = nil) { puts "  stage: #{name}" },
      on_load_tick: ->(count, _errored) { puts "  … #{count}" if (count % 100_000).zero? },
      on_explain: narrator
    )
    summary = Nabu::Ops::BuilderRefresh.run(catalog: catalog, config: config,
                                            progress: progress)
    puts "builders:refresh done — facets #{summary.facets.rows} rows · " \
         "passage facets #{summary.passage_facets.rows} rows · " \
         "entities #{summary.entities&.rows || 'n/a (catalog predates migration 049)'} rows · " \
         "entry facets #{summary.entry_facets.rows} rows · " \
         "lect #{summary.lect_rows} rows · dictionaries #{summary.dictionary_stats} · " \
         "derge titles #{summary.derge_titles.titled} · " \
         "lemma rollup #{summary.lemma_rollups.lemma_rows} rows · " \
         "language mix #{summary.lemma_rollups.mix_rows} docs"
  ensure
    catalog&.disconnect
  end
end

# The demo slice (Nabu::DemoBuild): the self-contained, open/attribution-
# only demo library the OCI image bakes in (Dockerfile `demo` target). The
# build runs REAL syncs — network, minutes — and is fired per release on
# this box (it needs the full library; GitHub-hosted CI cannot build it),
# never by the suite (test/demo_build_test.rb injects the runner).
# Knobs: DEMO_OUT (default tmp/demo), DEMO_WORK (default <out>-work, the
# full canonical fetch kept between runs), DEMO_MAX_MB (size ceiling).
namespace :demo do
  desc "Build the demo library slice for the image (REAL syncs, network); DEMO_OUT defaults to tmp/demo"
  task :build do
    $LOAD_PATH.unshift(File.expand_path("lib", __dir__))
    require "nabu"
    registry = Nabu::SourceRegistry.load(File.join(__dir__, "config", "sources"))
    census = Nabu::DemoBuild.from_env(ENV, registry: registry).build!
    puts JSON.pretty_generate(census.except(:files))
  end

  desc "Print the demo plan and run its license guard (no network)"
  task :plan do
    $LOAD_PATH.unshift(File.expand_path("lib", __dir__))
    require "nabu"
    registry = Nabu::SourceRegistry.load(File.join(__dir__, "config", "sources"))
    demo = Nabu::DemoBuild.from_env(ENV, registry: registry)
    demo.guard!.each do |slug|
      puts format("%<slug>-20s %<klass>s", slug: slug, klass: registry[slug].manifest.license_class)
    end
    puts "license guard: clean -> #{demo.out_dir}"
  end

  # The LOCAL half of the image rail (Nabu::Ops::DemoPublish): the slice
  # needs this box's full library, so GitHub-hosted CI never builds the
  # image — this task does, multi-arch, tagged :<server.json version> and
  # :latest, pushed to GHCR. It is SELF-CONTAINED: ghcr auth is probed
  # (and `docker login ghcr.io` run inline if missing), a multi-platform
  # buildx builder is found or created, the push is verified to be a real
  # amd64+arm64 index on BOTH tags, and the pushed image is smoked — one
  # command, no setup steps around it. Runs at RELEASE moments only (ops
  # §12 step 7); .github/workflows/demo-release.yml is the normal path.
  # Knobs: DEMO_OUT (the slice, default tmp/demo), DEMO_PLATFORMS
  # (comma list, default linux/amd64,linux/arm64), DEMO_BUILDER (overrides
  # the preflight's builder choice).
  desc "Build + push + verify + smoke the demo image (self-contained: auth, builder, multi-arch check inside)"
  task :publish do
    require_relative "lib/nabu/ops/demo_publish"
    publish = Nabu::Ops::DemoPublish
    slice = File.expand_path(ENV.fetch("DEMO_OUT", "").strip.then { |v| v.empty? ? "tmp/demo" : v }, __dir__)
    platforms = ENV.fetch("DEMO_PLATFORMS", "").split(",").map(&:strip).reject(&:empty?)
    options = { root: __dir__, slice: slice }
    options[:platforms] = platforms unless platforms.empty?
    # The preflight always runs (daemon + auth + builder probes); a
    # DEMO_BUILDER override replaces only its builder CHOICE — before this,
    # the override skipped the whole preflight and a stopped daemon died
    # deep in buildx as a raw shell error.
    builder = publish::Preflight.ensure!
    override = ENV.fetch("DEMO_BUILDER", "").strip
    builder = override unless override.empty?
    options[:builder] = builder if builder
    puts "$ #{publish.publish_argv(**options).join(' ')}"
    publish.publish!(**options)
    publish.verify_pushed!(root: __dir__)
    image = "#{publish::IMAGE}:#{publish.version(root: __dir__)}"
    result = publish::Smoke.run!(image: image, docker_args: ["--pull=always"])
    puts "pushed, verified + smoked #{image} — #{result.server}, #{result.tools.size} tools"
  end

  # The MCP Registry listing as ONE command: installs mcp-publisher if
  # missing (brew), device-flow login, publish server.json. The release
  # workflow's github-oidc publish is the normal path; this is the local
  # fallback for the same act.
  desc "Publish server.json to the MCP Registry (self-contained: install, device-flow login, publish)"
  task :register do
    sh "command -v mcp-publisher >/dev/null 2>&1 || brew install mcp-publisher"
    sh "mcp-publisher login github"
    sh "mcp-publisher publish ./server.json"
  end

  # The demo eval pack (eval/demo/pack.yml) against a running server —
  # script/demo-eval is the entry point; this task forwards to it.
  # IMAGE (default :latest over docker stdio), MCP_URL (an HTTP-mode
  # server) or MCP_COMMAND (a local stdio server) picks the target; ONLY
  # narrows to comma-separated task ids.
  desc "Run the demo eval pack against a server (IMAGE | MCP_URL | MCP_COMMAND; ONLY=ids)"
  task :eval do
    argv = [RbConfig.ruby, File.join(__dir__, "script", "demo-eval")]
    { "MCP_URL" => "--url", "MCP_COMMAND" => "--command", "IMAGE" => "--image", "ONLY" => "--only" }.each do |var, flag|
      value = ENV.fetch(var, "").strip
      argv += [flag, value] unless value.empty?
    end
    sh(*argv)
  end

  # The MCP stdio smoke on its own (initialize → tools/list → nabu_status).
  # IMAGE defaults to the public :latest; DEMO_SMOKE_ARGS adds docker run
  # flags (e.g. "--memory=512m --pull=always").
  desc "MCP stdio smoke against the demo image (IMAGE, default ghcr.io/arvicco/nabu-ancient-texts:latest)"
  task :smoke do
    require_relative "lib/nabu/ops/demo_publish"
    smoke = Nabu::Ops::DemoPublish::Smoke
    image = ENV.fetch("IMAGE", "").strip.then { |v| v.empty? ? "#{Nabu::Ops::DemoPublish::IMAGE}:latest" : v }
    result = smoke.run!(image: image, docker_args: ENV.fetch("DEMO_SMOKE_ARGS", "").split)
    puts "ok #{image} — #{result.server}, protocol #{result.protocol}, #{result.tools.size} tools"
  end
end

# The paced-crawl chain (architecture §19): N slices of a source's paced
# lanes through the shared runner — per-slice progress asserted, consecutive
# zero-yield slices stopped at the spec's declared budget, the cone's end
# honored. The sanctioned way to run a standing slice's chain; never a bash
# loop of syncs. Loads only the adapter + engine (no catalog writes beyond
# the crawl's own fetch gateway).
namespace :crawl do
  desc "Run N paced-crawl slices of SOURCE through the chain runner (crawl:chain[slug,n])"
  task :chain, %i[slug n] do |_t, args|
    $LOAD_PATH.unshift(File.expand_path("lib", __dir__))
    require "nabu"
    require "nabu/paced_crawl_chain"

    slug = args[:slug].to_s.strip
    abort "crawl:chain[slug,n] — name a source slug" if slug.empty?
    slices = Integer(args[:n] || 1)
    config = Nabu::Config.load
    registry = Nabu::SourceRegistry.load(config.sources_path)
    entry = registry[slug] or abort "unknown source: #{slug}"
    adapter = entry.build_adapter
    unless adapter.respond_to?(:paced_crawls)
      abort "#{slug} does not ride the paced-crawl rail (no paced_crawls lanes) — " \
            "use bin/nabu sync #{slug} as usual"
    end
    workdir = File.join(config.canonical_dir, slug)
    progress = ->(line) { $stderr.print(line) }
    adapter.paced_crawls(workdir, progress: progress).each do |name, engine|
      warn "== #{slug} / #{name}: #{slices} slice(s) =="
      summary = Nabu::PacedCrawl::Chain.new(engine: engine, slices: slices).run!
      abort "#{slug}/#{name}: #{summary.stop_reason}" if summary.stalled?
    end
    warn "chain complete — run bin/nabu sync #{slug} to load what the crawl stored"
  end
end

# The acquisition plan's park / re-check conditions as one batch of HTTP
# state checks (Nabu::Ops::AcquisitionProbe — row shape in its class doc):
# the probe list is the gitignored .docs/acquisition/probes.yml (absent =
# announced skip; ACQUISITION_PROBES=path overrides). One request per row,
# short timeout, no retries, ≤3 redirects; then the held-vs-searchable line
# from the live dbs, read-only. Network; informational (never exits 1 on a
# CHANGED row).
namespace :acquisition do
  desc "Probe the acquisition plan's park/re-check URLs (.docs/acquisition/probes.yml rows: " \
       "name, url, expect = status code | any | body substring, note) + the held-vs-searchable delta"
  task :probe do
    $LOAD_PATH.unshift(File.expand_path("lib", __dir__))
    require "nabu"
    require "nabu/ops/acquisition_probe"

    path = ENV.fetch("ACQUISITION_PROBES", File.expand_path(".docs/acquisition/probes.yml", __dir__))
    if File.file?(path)
      Nabu::Ops::AcquisitionProbe.new(rows: Nabu::Ops::AcquisitionProbe.load(path)).run
    else
      puts "acquisition:probe — no probe list at #{path} (a public clone or a worktree); probes skipped"
    end
    config = Nabu::Config.load
    puts Nabu::Ops::AcquisitionProbe.searchable_delta(catalog_path: config.catalog_path,
                                                      fulltext_path: config.fulltext_path)
  rescue Nabu::Ops::AcquisitionProbe::Invalid => e
    abort "acquisition:probe — #{e.message}"
  end
end

# The phase's paced-crawl plan, generated from the adapters' own Schedule
# declarations and the ledger's measured slice times (Nabu::Ops::RailPlan;
# the 2026-11-13 hand-assembled chain over-run). Parallel lanes, one per
# source; slices_per_phase is a cap; no budget = the caps-only view. The
# `lane <slug> step N: <command>` lines are the machine-consumable plan;
# each step is rail:step (the yield-guarded sync), and sources the crawl
# ledger marks exhausted, or whose Schedule declares `suspended:`, are
# skipped (listed, the suspension with its reason).
namespace :rail do
  desc "Print the phase's paced-crawl plan as parallel lanes (rail:plan[budget_minutes], budget optional)"
  task :plan, %i[budget] do |_t, args|
    $LOAD_PATH.unshift(File.expand_path("lib", __dir__))
    require "nabu"
    require "nabu/ops/rail_plan"

    config = Nabu::Config.load
    registry = Nabu::SourceRegistry.load(config.sources_path)
    budget = args[:budget].to_s.strip
    ledger = File.file?(config.history_path) ? Nabu::Store.connect(config.history_path, readonly: true) : nil
    begin
      plan = Nabu::Ops::RailPlan.new(registry: registry, ledger: ledger, canonical_dir: config.canonical_dir,
                                     budget_minutes: budget.empty? ? nil : Float(budget)).plan
      print Nabu::Ops::RailPlan.render(plan)
    ensure
      ledger&.disconnect
    end
  end

  # One plan step (Nabu::Ops::RailStep): `bin/nabu sync SLUG` between two
  # offline diagnoses of the source's paced lanes. Exit 3 = the lane stops
  # (zero yield, or the cone is exhausted), so the plan's && chain breaks.
  desc "Run one yield-guarded rail step: sync SOURCE, stop the lane (exit 3) on zero yield (rail:step[slug])"
  task :step, %i[slug] do |_t, args|
    $LOAD_PATH.unshift(File.expand_path("lib", __dir__))
    require "nabu"
    require "nabu/ops/rail_step"

    slug = args[:slug].to_s.strip
    abort "rail:step[slug] — name a source slug" if slug.empty?
    config = Nabu::Config.load
    registry = Nabu::SourceRegistry.load(config.sources_path)
    entry = registry[slug] or abort "unknown source: #{slug}"
    adapter = entry.build_adapter
    abort "#{slug} does not ride the paced-crawl rail (no paced_crawls lanes)" unless adapter.respond_to?(:paced_crawls)

    engines = adapter.paced_crawls(File.join(config.canonical_dir, slug))
    sync = -> { Nabu::Shell.stream(File.expand_path("bin/nabu", __dir__), "sync", slug) { |line| $stdout.print(line) } }
    verdict = Nabu::Ops::RailStep.new(slug: slug, engines: engines, sync: sync).run!
    puts verdict.line
    exit 3 if verdict.stop?
  end
end

# The trickle runner (Nabu::Ops::Trickle, architecture §19): an owner-fired
# standing crawl of one paced-crawl source, detached from any session, its
# slices back to back at the engine's declared pace until the cone ends, a
# declared stop condition, a stop request or a fatal error. It only crawls;
# loading stays with `bin/nabu sync SLUG --parse-only`. State and progress:
# local/trickle/<slug>.{pid,log,stop}. Runbook: docs/manual/trickle-runner.md.
namespace :trickle do
  trickle_setup = lambda do |args, task|
    $LOAD_PATH.unshift(File.expand_path("lib", __dir__))
    require "nabu"
    require "nabu/ops/trickle"

    slug = args[:slug].to_s.strip
    abort "trickle:#{task}[slug] — name a source slug" if slug.empty?
    config = Nabu::Config.load
    paths = Nabu::Ops::Trickle::Paths.for(local_dir: config.local_dir, slug: slug)
    [slug, config, Nabu::Ops::Trickle::Control.new(paths: paths, canonical_dir: config.canonical_dir)]
  end

  desc "Detach a standing paced crawl of SOURCE at its declared pace (trickle:start[slug])"
  task :start, %i[slug] do |_t, args|
    slug, config, control = trickle_setup.call(args, "start")
    entry = Nabu::SourceRegistry.load(config.sources_path)[slug] or abort "unknown source: #{slug}"
    adapter = entry.build_adapter
    engines = adapter.respond_to?(:paced_crawls) ? adapter.paced_crawls(File.join(config.canonical_dir, slug)) : {}
    control.start!(engines: engines)
  rescue Nabu::Ops::Trickle::Refused => e
    abort "trickle:start refused — #{e.message}"
  end

  desc "Ask SOURCE's trickle to stop after its current request (trickle:stop[slug]; idempotent)"
  task :stop, %i[slug] do |_t, args|
    _slug, _config, control = trickle_setup.call(args, "stop")
    wait = ENV.fetch("TRICKLE_STOP_WAIT", Nabu::Ops::Trickle::Control::DEFAULT_STOP_WAIT.to_s)
    control.stop!(wait: Float(wait))
  end

  desc "List every trickle in local/trickle/: running or finished, held/remaining, last log line"
  task :status do
    $LOAD_PATH.unshift(File.expand_path("lib", __dir__))
    require "nabu"
    require "nabu/ops/trickle"

    config = Nabu::Config.load
    registry = Nabu::SourceRegistry.load(config.sources_path)
    # held/remaining from DISK (the offline diagnosis the SUMMARY takes),
    # never the log's last slice line — that freezes for a whole slice.
    counts = lambda do |slug|
      adapter = registry[slug]&.build_adapter
      next nil unless adapter.respond_to?(:paced_crawls)

      Nabu::Ops::Trickle::Control.disk_counts(adapter.paced_crawls(File.join(config.canonical_dir, slug)))
    rescue Nabu::Error
      nil
    end
    Nabu::Ops::Trickle::Control.status(dir: File.join(config.local_dir, Nabu::Ops::Trickle::DIRNAME), counts: counts)
  end
end

# The reconstruction census (Nabu::Ops::Reconstruction::SourceClass): how
# each registered source's canonical asset would come back with canonical/
# lost and no backup — per-class counts, the attic-flagged sources (upstream
# deletions only a backup holds), and the local/ inventory by role.
namespace :reconstruction do
  desc "Print the reconstruction census: sources per re-acquisition class, attic list, local/ inventory"
  task :census do
    $LOAD_PATH.unshift(File.expand_path("lib", __dir__))
    require "nabu"
    require "nabu/ops/reconstruction/source_class"

    config = Nabu::Config.load
    source_class = Nabu::Ops::Reconstruction::SourceClass
    print source_class.render(source_class.from_config(config).census, local_dir: config.local_dir)
  end

  # The Reconstruction Book (Nabu::Ops::Reconstruction::Book): reads the
  # instance (grants, the canonical/ attic) through Nabu::Config — so run it
  # on the reference instance — and writes docs/reconstruction.md into this
  # checkout. Byte-freshness rides the gate ritual, like site:refresh; the
  # suite guards shape and coverage only.
  desc "Regenerate docs/reconstruction.md (the Reconstruction Book) on the reference instance — a gate step"
  task :book do
    $LOAD_PATH.unshift(File.expand_path("lib", __dir__))
    require "nabu"
    require "nabu/ops/reconstruction/book"

    tool_tasks = Rake::Task.tasks.select { |task| task.name.start_with?("tools:") }
    tool_tasks = tool_tasks.map { |task| [task.name_with_args, task.comment] }
    book = Nabu::Ops::Reconstruction::Book.from_config(Nabu::Config.load, tool_tasks: tool_tasks)
    path = File.join(__dir__, Nabu::Ops::Reconstruction::Book::OUTPUT_FILE)
    File.write(path, book.render)
    puts "wrote #{path}"
  end
end

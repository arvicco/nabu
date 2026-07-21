# frozen_string_literal: true

require "rake/testtask"

Rake::TestTask.new(:test) do |t|
  t.libs << "test"
  t.libs << "lib"
  t.test_files = FileList["test/**/*_test.rb"]
  t.warning = false
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

    sentinel = Nabu::FixtureSentinel.new
    sources = args[:source] ? [args[:source]] : sentinel.sources
    results = sources.map { |source| sentinel.check(source) }
    results.each { |result| print_check_report(result) }
    abort "fixtures:check found drift or fetch/adapter-test failures" unless results.all?(&:ok?)
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
namespace :ops do
  desc "Fresh-machine restore drill: back up locally, restore into a tmp root, rebuild+verify+golden replay"
  task :drill do
    $LOAD_PATH.unshift(File.expand_path("lib", __dir__))
    require "nabu"
    require "tmpdir"

    config = Nabu::Config.load
    Dir.mktmpdir("nabu-drill") do |workspace|
      report = Nabu::Ops::Drill.new(config: config, workspace: workspace).run
      print_drill_report(report)
      abort "ops:drill FAILED — the backup is not restorable as-is (see above)" unless report.ok?
    end
  end
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
      shelf_dir: Nabu::SourceShelf.dir(config.canonical_dir),
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
      as_of: Date.today
    )
    results = generator.generate!
    counts = File.exist?(catalog_path) ? "live catalog #{catalog_path}" : "no catalog (holdings say so)"
    puts "site:axes wrote #{results.size} pages (#{results.size - 1} desks + index) — #{counts}"
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

# Print the drill report to stdout.
def print_drill_report(report)
  puts "Restore drill"
  puts "  backup     → #{report.backup.target}  " \
       "(#{report.backup.sections.count(&:ran?)}/#{report.backup.sections.size} sections, " \
       "#{report.backup.files} files, #{report.backup.ok? ? 'OK' : 'FAILED'})"
  puts "  restore    → #{report.machine_root}"
  puts "  rebuild    quarantined #{report.rebuild_quarantined} document(s)"
  puts "  verify     #{report.verify_clean ? 'clean' : 'FAILED'}"
  puts "  golden     #{report.golden_found} found, #{report.golden_lost} lost, #{report.golden_skipped} skipped"
  puts "  counts     source=#{count_str(report.source_counts)}  " \
       "restored=#{count_str(report.restored_counts)}  " \
       "#{report.counts_match? ? 'MATCH' : 'MISMATCH'}"
  puts "  => #{report.ok? ? 'RESTORABLE' : 'NOT RESTORABLE'}"
end

def count_str(counts)
  return "n/a" if counts.nil?

  "#{counts.documents} docs / #{counts.passages} passages"
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

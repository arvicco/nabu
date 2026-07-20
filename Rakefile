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

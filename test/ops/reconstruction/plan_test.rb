# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"
require "json"
require "nabu/ops/reconstruction/plan"

# `nabu reconstruct plan`: the ordered bootstrap plan from a bare clone,
# every step estimated from the box's OWN history where it can answer and
# "unmeasured" where it cannot — never an invented number. Planted ledger,
# registry, verdicts and capability layers; no box data.
class ReconstructionPlanTest < Minitest::Test
  Plan = Nabu::Ops::Reconstruction::Plan
  Verdict = Nabu::Ops::Reconstruction::SourceClass::Verdict
  PC = Nabu::PacedCrawl

  # A rail adapter with one paced lane (the RailPlanTest seam shape).
  class RailAdapter
    LANE = PC::Spec.new(name: "rail", ledger_file: ".rail-crawl.json", classes: { denied: "denied" }, delay: 0,
                        slice: 10, schedule: PC::Schedule.new(cadence: :per_phase, slices_per_phase: 3,
                                                              stop_after_zero_slices: 3))

    def paced_crawls(workdir, progress: nil)
      { "rail" => PC::Engine.new(spec: LANE, dir: workdir, progress: progress, universe: -> { [] },
                                 held: ->(_) { false }, fetch_one: ->(_) { raise "no network" }) }
    end
  end

  # Not on the rail: no schedule constant.
  class PlainAdapter
    NAME = "plain"
  end

  def entry(slug, klass: PlainAdapter, kind: "source", wired: true)
    Nabu::SourceRegistry::Entry.new(slug: slug, adapter_class_name: klass.name, wired: wired,
                                    sync_policy: "manual", kind: kind)
  end

  def verdict(slug, klass, attic: false)
    Verdict.new(slug: slug, klass: klass, computed: klass, attic: attic)
  end

  CAPABILITIES = {
    "layers" => {
      "catalog" => { "home" => "db/catalog.sqlite3", "producer" => "rebuild", "cost" => "derived" },
      "canonical" => { "home" => "canonical/<slug>/", "producer" => "sync", "cost" => "acquired",
                       "command" => "nabu sync SLUG" },
      "ledger" => { "home" => "local/history.sqlite3", "producer" => "sync", "cost" => "log",
                    "command" => "appended by every run" },
      "notes_shelf" => { "home" => "local/shelves/local-notes/", "producer" => "write_through",
                         "cost" => "ruled", "command" => "nabu note URN TEXT" },
      "mined_links" => { "home" => "local/mined-links.sqlite3", "producer" => "enrichment",
                         "cost" => "time_heavy", "command" => "nabu links mine SCOPE" },
      "vectors" => { "home" => "db/vectors.sqlite3", "producer" => "enrichment", "cost" => "time_heavy",
                     "command" => "nabu embed" },
      "dates_shelf" => { "home" => "local/shelves/local-dates/", "producer" => "enrichment", "cost" => "acquired",
                         "command" => "nabu silver-dates --import FILE" },
      "meter_shelf" => { "home" => "local/shelves/local-meter/", "producer" => "enrichment",
                         "cost" => "time_heavy", "command" => "nabu scan-meter --run" }
    }
  }.freeze

  def setup
    @tmp = Dir.mktmpdir("nabu-reconstruct-plan")
    @canonical = File.join(@tmp, "canonical")
    @local = File.join(@tmp, "local")
    FileUtils.mkdir_p(@local)
    @ledger = Nabu::Store::Ledger.migrate!(Sequel.sqlite)
    @registry = Nabu::SourceRegistry.new([
                                           entry("lects", kind: "module"),
                                           entry("alpha"), entry("beta"), entry("gamma"),
                                           entry("rail", klass: RailAdapter),
                                           entry("cold", wired: false),
                                           entry("local-notes", kind: "shelf")
                                         ])
    @verdicts = [verdict("lects", :public_stable), verdict("alpha", :public_stable),
                 verdict("beta", :manual), verdict("gamma", :public_stable, attic: true),
                 verdict("rail", :rail_paced), verdict("cold", :public_stable),
                 verdict("local-notes", :public_stable)]
  end

  def teardown
    @ledger.disconnect
    FileUtils.remove_entry(@tmp)
  end

  def sync_run(slug, seconds, status: "succeeded")
    start = Time.utc(2026, 11, 1, 10)
    @ledger[:runs].insert(source_slug: slug, kind: "sync", status: status, started_at: start,
                          finished_at: start + seconds)
  end

  def timing(scope, stage, seconds, kind: "sync", at: Time.utc(2026, 11, 1))
    Nabu::Store::StageTimings.record!(@ledger, kind: kind, scope: scope, stage: stage, seconds: seconds, at: at)
  end

  def plant_history
    sync_run("lects", 60)
    sync_run("alpha", 100)
    sync_run("alpha", 9_999, status: "failed") # a failed run never measures
    sync_run("beta", 300)
    # rail: three complete slice steps (fetch + load) over two days =
    # 1 step/day; the newest step is 500 + 100 = 600 s.
    [[Time.utc(2026, 11, 1), 400], [Time.utc(2026, 11, 2), 450], [Time.utc(2026, 11, 3), 500]].each do |at, fetch|
      timing("rail", "fetch", fetch, at: at)
      timing("rail", "load", 100, at: at + 60)
    end
    timing("corpus", "fts_lemma", 1_000, kind: "rebuild")
    timing("corpus", "fts_lemma", 1_200, kind: "rebuild")
    timing("alpha", "load", 50, kind: "rebuild")
  end

  def plant_cone(census:, remaining:)
    dir = File.join(@canonical, "rail")
    FileUtils.mkdir_p(dir)
    last = { "classification" => "yield", "slice" => 10, "census" => census,
             "remaining" => { "before" => remaining + 10, "after" => remaining } }
    File.write(File.join(dir, ".rail-crawl.json"), JSON.generate("denied" => [], "last_slice" => last))
  end

  def mined_layer(scope, seconds)
    Nabu::Store::MinedLinks::Layer.new(producer: "parallels", scope: scope, run_scope: scope, run_ids: [1],
                                       edges: 10, code_version: "x", stamp: nil, inputs: nil, catalog: nil,
                                       origin: "mine", seconds: seconds, mined_at: Time.utc(2026, 11, 2))
  end

  def build(ledger: @ledger, local_dir: @local, mined_layers: [mined_layer("perseus-latin", 22_000)])
    Plan.new(registry: @registry, verdicts: @verdicts, ledger: ledger, capabilities: CAPABILITIES,
             mined_layers: mined_layers, canonical_dir: @canonical, local_dir: local_dir).build
  end

  def test_tools_are_enumerated_from_the_bootstrap_class
    tools = build.tools
    assert_includes tools, "bundle exec rake tools:embed"
    assert(tools.any? { |task| task.start_with?("bundle exec rake tools:stanza") })
  end

  def test_modules_fetch_first_with_their_measured_sync
    plant_history
    modules = build.modules
    assert_equal ["lects"], modules.map(&:slug)
    assert_in_delta 60, modules.first.seconds
  end

  def test_sources_bucket_by_class_with_measured_and_unmeasured_counts
    plant_history
    report = build
    stable = report.classes.fetch(:public_stable)
    assert_equal %w[alpha gamma], stable.sources.map(&:slug), "wired corpus sources only; modules/shelves apart"
    assert_in_delta 100, stable.measured_seconds, 0.01, "the last SUCCEEDED sync, never the failed one"
    assert_equal 1, stable.unmeasured
    assert_in_delta 300, report.classes.fetch(:manual).measured_seconds
    assert_equal 0, report.classes.fetch(:granted).sources.size
    refute report.classes.key?(:rail_paced), "rail sources ride their own cone section"
    assert_equal ["cold"], report.unwired
  end

  def test_rail_cone_math_reads_slices_and_cadence_from_the_ledgers
    plant_history
    plant_cone(census: 100, remaining: 40)
    rail = build.rails.first

    assert_equal "rail", rail.slug
    assert_in_delta 600, rail.slice_seconds, 0.01, "the newest complete step (RailPlan's rule)"
    assert_equal 4, rail.remaining_steps, "ceil(40 / 10)"
    assert_equal 10, rail.full_steps, "ceil(100 / 10): the whole cone re-crawls from a bare clone"
    assert_in_delta 1.0, rail.steps_per_day, 0.01, "3 fetches over 2 days"
    assert_in_delta 10.0, rail.full_days, 0.01
    assert_in_delta 6_000, rail.full_compute_seconds, 0.01
  end

  def test_an_uncrawled_rail_source_is_honestly_unmeasured
    rail = build.rails.first
    assert_nil rail.slice_seconds
    assert_nil rail.full_steps
    assert_nil rail.steps_per_day
    assert_match(/unmeasured/, Plan.render(build))
  end

  def test_rebuild_sums_the_governing_row_of_each_stage
    plant_history
    rebuild = build.rebuild
    assert_in_delta 1_200, rebuild.corpus_seconds, 0.01, "the latest fts_lemma row governs"
    assert_in_delta 50, rebuild.source_seconds, 0.01
  end

  def test_enrichments_are_the_enrichment_layers_with_measured_examples
    plant_history
    enrichments = build.enrichments
    assert_equal %w[dates_shelf meter_shelf mined_links vectors], enrichments.map(&:layer).sort
    mined = enrichments.find { |row| row.layer == "mined_links" }
    assert_in_delta 22_000, mined.seconds
    assert_match(/perseus-latin/, mined.basis)
    assert_nil enrichments.find { |row| row.layer == "vectors" }.seconds
  end

  # An imported enrichment (cost acquired) cannot be re-run without the
  # very input that is lost: it is backup-critical too; a time-heavy one is not.
  def test_backup_critical_set_is_the_irreplaceable_local_layers_plus_attic
    report = build
    assert_equal %w[dates_shelf ledger notes_shelf], report.backup.map(&:first).sort
    assert_equal ["gamma"], report.attic
    assert report.local_present
  end

  def test_render_states_the_honest_headline
    plant_history
    plant_cone(census: 100, remaining: 40)
    out = Plan.render(build)

    assert_match(/1\. tools/, out)
    assert_match(%r{2\. sister/module sources}, out)
    assert_match(/public_stable\s+2 sources/, out)
    assert_match(/wall-clock is parallel/, out)
    assert_match(/rail: full cone 10 slice/, out)
    assert_match(/4\. the owner-fired rebuild/, out)
    assert_match(/5\. enrichments/, out)
    assert_match(/NOT reconstructed/, out)
    assert_match(/unmeasured step/, out)
  end

  def test_degrades_without_ledger_or_local
    out = Plan.render(build(ledger: nil, local_dir: File.join(@tmp, "nope"), mined_layers: []))
    assert_match(%r{no local/ at}, out)
    assert_match(/rebuild.*unmeasured/, out)
  end
end

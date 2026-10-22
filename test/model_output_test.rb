# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

# The model-output shelf convention (architecture §16 "the
# model-output convention"): the seams every future paid-model lane
# composes — the cache/identity key, versioned prompt files, the per-run
# sidecar provenance (verbatim prompts + append-only costs.tsv), and the
# monthly budget table — minted BEFORE the first producer. No model is
# ever called: FakeBackend stands in, counting its calls.
class ModelOutputTest < Minitest::Test
  # A stand-in model backend: the ModelCall backend contract (#name,
  # #complete(prompt:, model:) → ModelCall::Response), counting calls and
  # optionally failing on the Nth (the interruption simulation).
  class FakeBackend
    attr_reader :calls

    def initialize(usd: 0.25, fail_on: nil)
      @usd = usd
      @fail_on = fail_on
      @calls = []
    end

    def name = "fake"

    def complete(prompt:, model:)
      @calls << [prompt, model]
      raise Interrupt, "simulated kill" if @fail_on == @calls.size

      Nabu::ModelCall::Response.new(text: "answer #{@calls.size} (#{model})", usd: @usd)
    end
  end

  def setup
    @root = Dir.mktmpdir("nabu-model-output")
    @prompts = File.join(@root, "config", "prompts")
    write_prompt("restore", "v1", "Restore the lacuna in: {{text}}")
    write_prompt("restore", "v2", "Restore the lacuna (Leiden conventions) in: {{text}}")
    @shelf = Nabu::ModelShelf.new(dir: File.join(@root, "local", "shelves", "local-model-output"))
    @budget = Nabu::ModelBudget.new(path: File.join(@root, "local", "config", "model_budget.yml"))
    @now = Time.utc(2026, 10, 22, 12)
  end

  def teardown
    FileUtils.rm_rf(@root)
  end

  def write_prompt(tool, version, text)
    FileUtils.mkdir_p(File.join(@prompts, tool))
    File.write(File.join(@prompts, tool, "#{version}.md"), text)
  end

  def prompt(version = "v1") = Nabu::ModelOutput.prompt(prompts_dir: @prompts, tool: "restore", version: version)

  def open_run(model: "model-a", version: "v1", label: "pilot", params: { "limit" => 10 })
    @shelf.open_run(producer: "aeneas", label: label, model: model, backend: "fake",
                    stages: [prompt(version)], source: "canonical/edh", params: params, now: @now)
  end

  def gate(run, backend, model: "model-a")
    Nabu::ModelCall.new(shelf: @shelf, run: run, budget: @budget, backend: backend,
                        producer: "aeneas", model: model, clock: -> { @now })
  end

  # -- (1) the cache/identity key ----------------------------------------------

  def test_the_key_is_sha256_of_the_pipe_joined_recipe
    key = Nabu::ModelOutput.key(urn: "urn:nabu:edh:hd000001", tool: "restore", prompt_version: "v1",
                                model: "model-a")
    assert_equal Digest::SHA256.hexdigest("urn:nabu:edh:hd000001|restore|v1|model-a"), key
    assert_equal key, Nabu::ModelOutput.key(urn: "urn:nabu:edh:hd000001", tool: "restore",
                                            prompt_version: "v1", model: "model-a"), "stable"
    refute_equal key, Nabu::ModelOutput.key(urn: "urn:nabu:edh:hd000001", tool: "restore",
                                            prompt_version: "v1", model: "model-b"), "model is identity"
  end

  def test_a_component_carrying_the_separator_or_empty_is_refused
    assert_raises(ArgumentError) do
      Nabu::ModelOutput.key(urn: "a|b", tool: "restore", prompt_version: "v1", model: "m")
    end
    assert_raises(ArgumentError) do
      Nabu::ModelOutput.key(urn: "urn:x", tool: "", prompt_version: "v1", model: "m")
    end
  end

  def test_prompts_are_versioned_files_and_a_missing_version_is_loud
    loaded = prompt("v2")
    assert_equal "restore", loaded.tool
    assert_equal "v2", loaded.version
    assert_equal "Restore the lacuna (Leiden conventions) in: {{text}}", loaded.text
    assert_equal "Restore the lacuna in: [...] ave", prompt.render("text" => "[...] ave")
    assert_raises(Nabu::ModelOutput::Error) { prompt("v9") }
    assert_raises(Nabu::ModelOutput::Error) { prompt.render({}) }
  end

  # -- the cache and the orphan rule ----------------------------------------------

  def test_a_cache_hit_answers_without_a_call_or_a_cost_row
    @budget.set_cap!(month: "2026-10", cap_usd: 5)
    run = open_run
    backend = FakeBackend.new
    first = gate(run, backend).call(urn: "urn:x:1", prompt: prompt, vars: { "text" => "a" })
    again = gate(run, backend).call(urn: "urn:x:1", prompt: prompt, vars: { "text" => "a" })
    refute first.cached
    assert again.cached
    assert_equal first.output, again.output
    assert_equal 1, backend.calls.size, "the hit never reaches the model"
    assert_equal 1, run.costs.size, "a hit costs nothing and books nothing"
    assert_in_delta 0.25, @budget.row("2026-10")[:spend_usd]
  end

  def test_a_prompt_version_bump_orphans_stale_rows_and_never_deletes_them
    @budget.set_cap!(month: "2026-10", cap_usd: 5)
    backend = FakeBackend.new
    v1_run = open_run
    gate(v1_run, backend).call(urn: "urn:x:1", prompt: prompt("v1"), vars: { "text" => "a" })
    v2_run = open_run(version: "v2", label: "pilot-v2")
    result = gate(v2_run, backend).call(urn: "urn:x:1", prompt: prompt("v2"), vars: { "text" => "a" })
    refute result.cached, "the bumped version is a new identity — the v1 row cannot answer it"
    assert_equal 2, backend.calls.size
    assert_equal 2, @shelf.outputs(producer: "aeneas").size, "the v1 row is still on the shelf"
    assert_equal({ %w[restore v1] => 1 }, @shelf.orphans(producer: "aeneas", current: { "restore" => "v2" }))
  end

  # -- (2) per-run sidecar provenance ------------------------------------------------

  def test_the_run_config_carries_the_full_verbatim_prompt_source_and_params
    run = open_run
    config = JSON.parse(File.read(File.join(run.dir, "config.json")))
    assert_equal "canonical/edh", config["source"]
    assert_equal({ "limit" => 10 }, config["params"])
    assert_equal "model-a", config["model"]
    stage = config["stages"].first
    assert_equal ["restore", "v1", "Restore the lacuna in: {{text}}"],
                 stage.values_at("tool", "prompt_version", "prompt")
    assert_equal Digest::SHA256.hexdigest(stage["prompt"]), stage["prompt_sha256"]
  end

  def test_a_call_under_a_prompt_the_run_did_not_record_is_refused
    @budget.set_cap!(month: "2026-10", cap_usd: 5)
    run = open_run
    assert_raises(Nabu::ModelCall::Error) do
      gate(run, FakeBackend.new).call(urn: "urn:x:1", prompt: prompt("v2"), vars: { "text" => "a" })
    end
  end

  def test_costs_tsv_is_appended_per_call_and_survives_an_interruption
    @budget.set_cap!(month: "2026-10", cap_usd: 5)
    run = open_run
    backend = FakeBackend.new(fail_on: 3)
    assert_raises(Interrupt) do
      %w[1 2 3 4].each { |n| gate(run, backend).call(urn: "urn:x:#{n}", prompt: prompt, vars: { "text" => n }) }
    end
    lines = File.readlines(File.join(run.dir, "costs.tsv"), chomp: true)
    assert_equal "stage\tunit\tusd\tbackend", lines.first
    assert_equal ["restore\turn:x:1\t0.250000\tfake", "restore\turn:x:2\t0.250000\tfake"], lines[1..]
    assert_in_delta 0.5, @budget.row("2026-10")[:spend_usd], 1e-9, "spend booked per completed call"

    resumed = open_run # same label/model/config → the SAME run, resumed
    assert_equal run.dir, resumed.dir
    backend2 = FakeBackend.new
    %w[1 2 3 4].each { |n| gate(resumed, backend2).call(urn: "urn:x:#{n}", prompt: prompt, vars: { "text" => n }) }
    assert_equal 2, backend2.calls.size, "finished units answer from the shelf"
    assert_equal 4, resumed.costs.size
    assert_in_delta 1.0, resumed.total_usd, 1e-9
  end

  def test_a_torn_trailing_row_is_set_aside_never_glued_or_lost
    run = open_run
    run.append_cost!(stage: "restore", unit: "urn:x:1", usd: 0.1, backend: "fake")
    File.open(File.join(run.dir, "costs.tsv"), "a") { |f| f.write("restore\turn:x:2\t0.1") } # the kill mid-write
    assert_equal 1, run.costs.size, "the torn tail is not a row"
    assert_equal 1, run.torn_rows.size
    resumed = open_run
    resumed.append_cost!(stage: "restore", unit: "urn:x:3", usd: 0.2, backend: "fake")
    assert_equal(%w[urn:x:1 urn:x:3], resumed.costs.map(&:unit))
    assert_includes File.read(File.join(run.dir, "torn.log")), "restore\turn:x:2\t0.1", "audit copy kept"
  end

  def test_a_rerun_under_a_new_model_is_a_sibling_directory_never_an_overwrite
    first = open_run(model: "model-a")
    second = open_run(model: "model-b")
    refute_equal first.dir, second.dir
    assert_equal File.dirname(first.dir), File.dirname(second.dir), "siblings under one run label"
    assert File.exist?(File.join(first.dir, "config.json")), "the first run is untouched"
    assert_raises(Nabu::ModelShelf::RunConflict, "same run, different params: refused") do
      open_run(model: "model-a", params: { "limit" => 99 })
    end
  end

  def test_model_ids_become_safe_directory_names
    run = open_run(model: "vendor/model:2026-10")
    assert_equal "vendor_model_2026-10", File.basename(run.dir)
  end

  # -- (3) the budget table -------------------------------------------------------

  def test_the_budget_refuses_a_paid_call_over_the_cap_after_the_cache_lookup
    @budget.set_cap!(month: "2026-10", cap_usd: 0.5)
    run = open_run
    backend = FakeBackend.new
    gate(run, backend).call(urn: "urn:x:1", prompt: prompt, vars: { "text" => "a" })
    gate(run, backend).call(urn: "urn:x:2", prompt: prompt, vars: { "text" => "b" })
    error = assert_raises(Nabu::ModelBudget::OverCap) do
      gate(run, backend).call(urn: "urn:x:3", prompt: prompt, vars: { "text" => "c" })
    end
    assert_match(/2026-10/, error.message)
    assert_equal 2, backend.calls.size, "refused BEFORE the call"
    hit = gate(run, backend).call(urn: "urn:x:1", prompt: prompt, vars: { "text" => "a" })
    assert hit.cached, "a cache hit still answers over the cap — the check sits after the lookup"
  end

  def test_the_budget_passes_under_the_cap_and_books_real_usage
    @budget.set_cap!(month: "2026-10", cap_usd: 10)
    run = open_run
    gate(run, FakeBackend.new(usd: 0.125)).call(urn: "urn:x:1", prompt: prompt, vars: { "text" => "a" })
    assert_equal({ spend_usd: 0.125, cap_usd: 10.0 }, @budget.row("2026-10"))
  end

  def test_no_cap_for_the_month_fails_closed
    run = open_run
    backend = FakeBackend.new
    assert_raises(Nabu::ModelBudget::NoCap) do
      gate(run, backend).call(urn: "urn:x:1", prompt: prompt, vars: { "text" => "a" })
    end
    assert_empty backend.calls
  end

  def test_the_budget_table_is_keyed_by_month_and_written_through
    @budget.set_cap!(month: "2026-10", cap_usd: 20)
    @budget.record!(month: "2026-10", usd: 1.5)
    @budget.set_cap!(month: "2026-11", cap_usd: 5)
    reread = Nabu::ModelBudget.new(path: @budget.path)
    assert_equal({ "2026-10" => { spend_usd: 1.5, cap_usd: 20.0 }, "2026-11" => { spend_usd: 0.0, cap_usd: 5.0 } },
                 reread.table)
    @budget.set_cap!(month: "2026-10", cap_usd: 30)
    assert_in_delta 1.5, reread.row("2026-10")[:spend_usd], 1e-9, "raising a cap never resets spend"
    assert_raises(Nabu::ModelBudget::Error) { @budget.set_cap!(month: "2026-1", cap_usd: 5) }
    assert_raises(Nabu::ModelBudget::Error) { @budget.set_cap!(month: "2026-10", cap_usd: -1) }
  end

  def test_the_cli_writes_the_cap_through_and_prints_the_table
    config = Nabu::Config.new(canonical_dir: File.join(@root, "canonical"), db_dir: File.join(@root, "db"),
                              local_dir: File.join(@root, "local"),
                              sources_path: File.join(@root, "config", "sources.yml"),
                              config_path: File.join(@root, "config", "nabu.yml"))
    out, = with_config(config) { run_cli(%w[model-budget]) }
    assert_match(/paid model calls are refused until a cap is set/, out)
    out, = with_config(config) { run_cli(%w[model-budget --cap 20 --month 2026-10]) }
    assert_match(/2026-10: cap \$20\.00/, out)
    assert_match(/2026-10\s+0\.0000\s+20\.00/, out)
    assert_equal({ spend_usd: 0.0, cap_usd: 20.0 },
                 Nabu::ModelBudget.new(path: config.model_budget_path).row("2026-10"))
    _out, err, status = with_config(config) { run_cli(%w[model-budget --cap 5 --month 2026-13]) }
    assert_equal 1, status
    assert_match(/YYYY-MM/, err)
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
      status = begin
        Nabu::CLI.start(argv)
        nil
      rescue SystemExit => e
        e.status
      end
    end
    [out, err, status]
  end

  def test_the_budget_lives_in_the_instance_config
    config = Nabu::Config.new(canonical_dir: "/x/canonical", db_dir: "/x/db", local_dir: "/x/local",
                              sources_path: "/x/config/sources.yml", config_path: "/x/config/nabu.yml")
    assert_equal "/x/local/config/model_budget.yml", config.model_budget_path
    assert_equal "/x/config/prompts", config.prompts_dir
    assert_equal "/x/local/shelves/local-model-output", Nabu::ModelShelf.dir(config)
  end
end

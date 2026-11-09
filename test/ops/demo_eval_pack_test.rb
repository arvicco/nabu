# frozen_string_literal: true

require "test_helper"
require "yaml"
require "nabu/ops/demo_eval"

module Ops
  # The tracked demo eval pack (eval/demo/pack.yml): well-formed, covering
  # the whole MCP tool table, and grounded in the demo slice's own sources
  # — never a URN from outside what the image bakes in.
  class DemoEvalPackTest < Minitest::Test
    E = Nabu::Ops::DemoEval

    def data = @data ||= YAML.safe_load_file(E::PACK)
    def tasks = @tasks ||= E::Pack.load

    def test_the_pack_validates_clean
      assert_empty E::Pack.validate(data)
    end

    def test_the_runner_tool_list_is_the_mcp_tool_table
      require "nabu/mcp/tools"

      assert_equal Nabu::MCP::Tools::TOOLS.keys.sort, E::TOOLS.sort
      assert_equal 14, E::TOOLS.size
    end

    def test_every_tool_is_exercised_at_least_once
      used = tasks.flat_map(&:tools).uniq

      assert_empty E::TOOLS - used, "tools no task exercises"
    end

    def test_the_flagship_surfaces_carry_the_weight
      counts = tasks.flat_map(&:tools).tally
      %w[nabu_search nabu_show nabu_parallels nabu_define].each do |tool|
        assert_operator counts.fetch(tool, 0), :>=, 4, "#{tool} is a flagship surface"
      end
    end

    # The slice carries the Oracc Sign List and a links journal (Achemenet's
    # CDLI reference edges), so these tools answer something real — not
    # only their honest-absence notes. nabu_cognates stays negative-only:
    # no open/attribution gold-lemmatized witness pair exists to bake (the
    # DemoBuild class note records the census).
    def test_the_sign_desk_and_links_carry_positive_tasks
      positive = tasks.reject { |t| t.difficulty == "negative" }.flat_map(&:tools).tally
      %w[nabu_char nabu_signs nabu_links].each do |tool|
        assert_operator positive.fetch(tool, 0), :>=, 1, "#{tool} needs a positive task"
      end
    end

    def test_the_pack_mixes_lookups_chains_and_negatives
      by = tasks.group_by(&:difficulty).transform_values(&:size)

      assert_operator tasks.size, :>=, 30
      assert_operator by.fetch("chain", 0), :>=, 3
      assert_operator by.fetch("negative", 0), :>=, 5
      assert(tasks.select { |t| t.difficulty == "chain" }.all? { |t| t.steps.size >= 2 },
             "a chain task makes more than one call")
    end

    def test_the_declared_slice_is_the_demo_build_set
      require "nabu/demo_build"

      assert_equal Nabu::DemoBuild::DEMO_SOURCES.map(&:slug).sort, data.dig("slice", "sources").sort
    end

    # Ground truth must come from the slice: every corpus urn a task names
    # (in args or checks) belongs to a demo source; dictionary urns to the
    # lexica shelves the slice bakes.
    def test_every_urn_named_belongs_to_the_slice
      slugs = data.dig("slice", "sources")
      urns = YAML.dump(data["tasks"]).scan(/urn:nabu:[^\s"',}]+/).uniq
      outside = urns.reject do |urn|
        _, _, slug, rest = urn.split(":", 4)
        slug == "dict" ? rest.to_s.start_with?("lsj:", "lewis-short:") : slugs.include?(slug)
      end

      refute_empty urns
      assert_empty outside, "urns outside the demo slice"
    end
  end
end

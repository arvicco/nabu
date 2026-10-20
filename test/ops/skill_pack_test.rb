# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

module Ops
  # Nabu::Ops::SkillPack, the MCP skill-pack scaffolder: one
  # skills/nabu-<desk>/SKILL.md per research desk, its managed block (the
  # desk's live sources with their license classes) projected from the
  # registry, its prose seeded once from the source dossiers and owned by
  # hand afterwards. The shipped files are guarded by
  # test/skills/shipped_skills_test.rb; this file tests the generator
  # against a throwaway registry.
  class SkillPackTest < Minitest::Test
    def with_pack(dossiers: {}, examples: {})
      Dir.mktmpdir("skill-pack") do |root|
        File.write(File.join(root, "axes.yml"), <<~YAML)
          alpha:
            persona: "The Alphaist — first letters, read whole."
            desc: "The alpha lane (opened by P12-3), with its tablets."
          beta:
            persona: "The Betaist — second letters."
            desc: "The beta lane."
          local:
            persona: "The Librarian — the owner's own shelves."
            desc: "The memory shelves."
        YAML
        sources_path = File.join(root, "sources.yml")
        File.write(sources_path, <<~YAML)
          pack:
            adapter: TestAdapter
            wired: true
            sync_policy: manual
            axes: [alpha, beta]
          draft:
            adapter: TestAdapter
            wired: false
            sync_policy: manual
            axes: [alpha]
          hidden:
            adapter: TestAdapter
            wired: true
            sync_policy: manual
            availability: blocked
            axes: [alpha]
          tool:
            adapter: TestAdapter
            kind: module
            wired: false
            sync_policy: manual
            axes: [alpha]
          local-notes:
            adapter: Nabu::Adapters::LocalNotes
            wired: true
            axes: [local]
        YAML
        registry = Nabu::SourceRegistry.load(sources_path)
        pack = Nabu::Ops::SkillPack.new(
          registry: registry, skills_dir: File.join(root, "skills"),
          dossier: ->(slug) { dossiers[slug] }, examples: examples
        )
        yield pack, File.join(root, "skills")
      end
    end

    def test_live_slugs_are_public_and_wired_or_modules
      with_pack do |pack, _dir|
        assert pack.live_slug?("pack")
        assert pack.live_slug?("tool"), "a feature module is a live instrument"
        refute pack.live_slug?("draft"), "an unwired source is not live"
        refute pack.live_slug?("hidden"), "a grant-gated private source is never advertised"
        refute pack.live_slug?("nope")
      end
    end

    def test_desks_exclude_the_owner_memory_axis
      with_pack do |pack, _dir|
        assert_equal %w[alpha beta], pack.desks
      end
    end

    def test_scaffold_carries_valid_front_matter_and_the_live_members_only
      with_pack do |pack, _dir|
        text = pack.scaffold("alpha")
        skill = Nabu::Ops::SkillPack.parse(text)

        assert_equal "nabu-alpha", skill.front["name"]
        assert_equal "MIT", skill.front["license"]
        refute_empty skill.front["description"]
        refute_empty skill.front["compatibility"]
        assert_equal({ "desk" => "alpha", "origin" => "generated", "sources" => "pack tool" },
                     skill.front["metadata"])
        assert_includes skill.body, "| `pack` | Conformance Test Adapter | open |"
        refute_includes skill.body, "`draft`"
        refute_includes skill.body, "`hidden`"
      end
    end

    def test_scaffold_seeds_dossier_prose_with_internal_ids_scrubbed
      dossiers = { "pack" => "The pack shelf (fetched per P13-4/P14-4), since P96 widened. Tablets." }
      with_pack(dossiers: dossiers) do |pack, _dir|
        body = Nabu::Ops::SkillPack.parse(pack.scaffold("alpha")).body

        assert_includes body, "- `pack` — The pack shelf, widened. Tablets."
        refute_match(/\bP\d+/, body)
        refute_match(/\bP\d+/, pack.scaffold("alpha"), "the persona/desc line is scrubbed too")
      end
    end

    def test_scaffold_seeds_the_curated_worked_examples
      examples = { "alpha" => [{ "ask" => "Is it covered?", "call" => "nabu_status",
                                 "answer" => "Counts per source (verified at P44-4)." }] }
      with_pack(examples: examples) do |pack, _dir|
        alpha = Nabu::Ops::SkillPack.parse(pack.scaffold("alpha")).body
        beta = Nabu::Ops::SkillPack.parse(pack.scaffold("beta")).body

        assert_includes alpha, "## Worked examples"
        assert_includes alpha, "- *Is it covered?* — `nabu_status`: Counts per source."
        refute_includes beta, "## Worked examples", "a desk without curated examples gets no empty section"
      end
    end

    def test_sync_creates_missing_skills_and_is_idempotent
      with_pack do |pack, dir|
        first = pack.sync!

        assert_equal %w[created created], first.map(&:action).map(&:to_s)
        assert_path_exists File.join(dir, "nabu-alpha", "SKILL.md")
        assert_path_exists File.join(dir, "nabu-beta", "SKILL.md")
        refute_path_exists File.join(dir, "nabu-local")
        assert_equal %w[unchanged unchanged], pack.sync!.map(&:action).map(&:to_s)
        assert_empty pack.stale
      end
    end

    def test_sync_refreshes_only_the_managed_lanes_of_a_hand_tuned_skill
      with_pack do |pack, dir|
        pack.sync!
        path = File.join(dir, "nabu-alpha", "SKILL.md")
        tuned = File.read(path)
                    .sub("origin: generated", "origin: hand-tuned")
                    .sub('sources: "pack tool"', 'sources: "pack"')
                    .sub(/^## What the shelves hold.*\z/m, "## Cautions\n\nHand prose stays.\n")
        tuned = tuned.sub(/(<!-- nabu:skill-sources:begin.*?-->\n).*?(<!-- nabu:skill-sources:end -->)/m,
                          "\\1| stale |\n\\2")
        File.write(path, tuned)

        assert_equal [path], pack.stale
        results = pack.sync!

        assert_equal :refreshed, results.find { |r| r.path == path }.action
        text = File.read(path)

        assert_includes text, "origin: hand-tuned"
        assert_includes text, 'sources: "pack tool"'
        assert_includes text, "Hand prose stays."
        assert_includes text, "| `tool` |"
        refute_includes text, "| stale |"
        assert_empty pack.stale
      end
    end

    def test_parse_refuses_a_file_without_front_matter
      assert_raises(Nabu::Ops::SkillPack::FormatError) { Nabu::Ops::SkillPack.parse("# no front matter\n") }
      assert_raises(Nabu::Ops::SkillPack::FormatError) { Nabu::Ops::SkillPack.parse("---\n- a list\n---\nbody\n") }
    end

    def test_a_skill_without_the_managed_block_is_stale_not_silently_passed
      with_pack do |pack, dir|
        pack.sync!
        path = File.join(dir, "nabu-beta", "SKILL.md")
        File.write(path, File.read(path).sub(/<!-- nabu:skill-sources:begin.*<!-- nabu:skill-sources:end -->\n/m, ""))

        assert_equal [path], pack.stale
        assert_raises(Nabu::Ops::SkillPack::FormatError) { pack.sync! }
      end
    end
  end
end

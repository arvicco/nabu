# frozen_string_literal: true

require "test_helper"

# The guard on the SHIPPED MCP skill pack (skills/*/SKILL.md, docs/mcp.md
# §8): every file carries valid Agent Skills front matter, every research
# desk has its skill, the managed sources lanes match the registry
# (Nabu::Ops::SkillPack — regenerate with `rake skills:scaffold`), and a
# skill names only LIVE public sources: a grant-gated private holding or
# an unwired source never reaches this public guidance, and a renamed or
# retired slug cannot linger in it.
class ShippedSkillsTest < Minitest::Test
  ROOT = Nabu::Config::PROJECT_ROOT
  SKILLS_DIR = File.join(ROOT, "skills")
  NAME_SHAPE = /\A[a-z0-9]+(?:-[a-z0-9]+)*\z/
  ORIGINS = %w[generated hand-tuned].freeze
  REQUIRED_KEYS = %w[name description license compatibility metadata].freeze

  def registry
    @registry ||= Nabu::SourceRegistry.load(File.join(ROOT, "config", "sources.yml"))
  end

  def pack
    @pack ||= Nabu::Ops::SkillPack.new(registry: registry, skills_dir: SKILLS_DIR)
  end

  def skills
    @skills ||= pack.skill_paths.sort.to_h do |path|
      [path, Nabu::Ops::SkillPack.parse(File.read(path, encoding: "UTF-8"))]
    end
  end

  def rel(path) = path.delete_prefix("#{ROOT}/")

  def test_every_research_desk_ships_a_skill
    missing = pack.desks.reject { |desk| File.exist?(pack.path_for(desk)) }

    assert_empty missing, "desks without a skill — run `rake skills:scaffold`: #{missing.join(', ')}"
  end

  def test_front_matter_follows_the_agent_skills_shape
    refute_empty skills

    skills.each do |path, skill|
      front = skill.front

      assert_empty REQUIRED_KEYS - front.keys, "#{rel(path)}: missing front-matter keys"
      assert_match NAME_SHAPE, front["name"], "#{rel(path)}: name shape"
      assert_operator front["name"].length, :<=, 64, "#{rel(path)}: name too long"
      assert_equal File.basename(File.dirname(path)), front["name"], "#{rel(path)}: name must equal its directory"
      assert_kind_of String, front["description"]
      refute_empty front["description"].strip, "#{rel(path)}: empty description"
      assert_operator front["description"].length, :<=, 1024, "#{rel(path)}: description over 1024 chars"
      assert_operator front["compatibility"].length, :<=, 500, "#{rel(path)}: compatibility over 500 chars"
      assert_equal Nabu::Ops::SkillPack::LICENSE, front["license"], "#{rel(path)}: the guidance text's license"
      assert_kind_of Hash, front["metadata"]
      front["metadata"].each do |key, value|
        assert_kind_of String, value, "#{rel(path)}: metadata.#{key} must be a string"
      end
      assert_includes ORIGINS, front["metadata"]["origin"], "#{rel(path)}: metadata.origin"
      refute_empty skill.body.strip, "#{rel(path)}: empty body"
    end
  end

  def test_desk_skills_name_their_desk_and_match_the_registry
    skills.each do |path, skill|
      desk = skill.front["metadata"]["desk"]
      next if desk.nil?

      assert_includes pack.desks, desk, "#{rel(path)}: unknown desk"
      assert_equal pack.path_for(desk), path, "#{rel(path)}: a desk skill lives at its desk's path"
    end
    assert_empty pack.stale.map { |path| rel(path) },
                 "skills whose managed sources lanes drifted — run `rake skills:scaffold`"
  end

  def test_skills_reference_only_live_public_sources
    skills.each do |path, skill|
      declared = skill.front["metadata"].fetch("sources", "").split

      declared.each do |slug|
        assert pack.live_slug?(slug), "#{rel(path)}: metadata.sources names #{slug}, not a live public source"
      end
      named = skill.body.scan(/`([a-z0-9][a-z0-9_-]*)`/).flatten.uniq.select { |token| registry[token] }
      named.each do |slug|
        assert pack.live_slug?(slug), "#{rel(path)}: the body names #{slug}, not a live public source"
      end
    end
  end

  def test_the_pack_is_documented_beside_the_mcp_server
    doc = File.read(File.join(ROOT, "docs", "mcp.md"))

    assert_match(/^## \d+\. The skill pack/, doc, "docs/mcp.md documents the skill pack")
    assert_includes doc, "rake skills:scaffold"
  end
end

# frozen_string_literal: true

require "test_helper"
require "yaml"

# The lect posture completeness check (P59-4, D59-e — "there shouldn't be a
# situation of 'adapter without lects'"): every passage-serving source in
# config/sources.yml must have a posture — machine (a lect_facet_rules.yml
# rule or a lect_overrides.yml row) or declared (config/lect_posture.yml:
# identity / pending / dates / codemap). The check tests EXISTENCE, not
# content — "identity" is an honest recorded answer, so nothing here forces
# a fake stage onto a source that has none. A new adapter without any
# posture turns this red: run `nabu lect suggest <slug>`, then wire a rule/
# override or declare a row.
class LectPostureTest < Minitest::Test
  POSTURE_PATH = File.join(Nabu::Config::PROJECT_ROOT, "config", "lect_posture.yml")
  RULES_PATH = File.join(Nabu::Config::PROJECT_ROOT, "config", "lect_facet_rules.yml")
  OVERRIDES_PATH = File.join(Nabu::Config::PROJECT_ROOT, "config", "lect_overrides.yml")
  SOURCES_PATH = File.join(Nabu::Config::PROJECT_ROOT, "config", "sources.yml")

  def posture
    @posture ||= Nabu::LectPosture.load(POSTURE_PATH)
  end

  def rules
    @rules ||= Nabu::LectRules.load(RULES_PATH)
  end

  def overrides
    @overrides ||= YAML.safe_load_file(OVERRIDES_PATH)["sources"]
  end

  # Passage-serving sources: kind "source" entries whose adapter serves
  # passages (dictionary/notes/language shelves resolve at their own
  # grains) — plus the local library shelf, which mints documents.
  def passage_slugs
    @passage_slugs ||= begin
      registry = Nabu::SourceRegistry.load(SOURCES_PATH)
      slugs = []
      registry.each_source do |entry|
        kind = entry.kind || "source"
        next unless kind == "source" || entry.slug == "local-library"

        klass = begin
          Object.const_get(entry.adapter_class_name)
        rescue NameError
          nil
        end
        slugs << entry.slug if entry.slug == "local-library" ||
                               (klass && klass.content_kind == :passages)
      end
      slugs
    end
  end

  def test_every_passage_serving_source_has_a_posture
    refute_nil posture, "config/lect_posture.yml must exist — it is the judgment record"
    coverage = posture.coverage(rules: rules, overrides: overrides)
    missing = passage_slugs.reject { |slug| coverage.key?(slug) }
    assert_empty missing,
                 "sources with NO lect posture (machine or declared): #{missing.join(', ')} — " \
                 "run `nabu lect suggest <slug>`, then wire a rule/override or declare a row " \
                 "(identity is an honest answer) in config/lect_posture.yml"
  end

  def test_declarations_use_the_ruled_vocabulary_and_name_real_sources
    slugs = Nabu::SourceRegistry.load(SOURCES_PATH).then do |registry|
      list = []
      registry.each_source { |entry| list << entry.slug }
      list
    end
    posture.declarations.each do |declaration|
      assert_includes Nabu::LectPosture::DECLARED_POSTURES, declaration.posture,
                      "#{declaration.slug}: unknown posture #{declaration.posture.inspect}"
      assert_includes slugs, declaration.slug,
                      "#{declaration.slug}: declared but not in config/sources.yml (a ghost row)"
    end
  end

  def test_declarations_never_shadow_machine_postures
    assert_empty posture.shadowing(rules: rules, overrides: overrides),
                 "a declared row duplicates a rules/overrides posture — delete the declaration " \
                 "(machine files are the single source of truth)"
  end

  def test_pending_rows_carry_the_candidate_as_a_note
    posture.declarations.select { |d| d.posture == "pending" }.each do |declaration|
      refute_nil declaration.note,
                 "#{declaration.slug}: a pending posture must name its refinement candidate — " \
                 "pending without a note is just a silence with paperwork"
    end
  end
end

# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "yaml"

# The consolidated core-layer posture record (P61-0, the D59-f wave-1
# frame): config/postures.yml nests per-layer declarations under each
# source (lect: today's 60 rows migrated verbatim; dating:/places:/
# script: arm in the P61-1 sweep). The lect layer keeps the P59-4
# contract byte-for-byte: machine grains (rules/overrides files) stay the
# single source of truth, declarations hold judgment only, shadowing
# refused, pending names its candidate. The existence check per layer
# lives here; dating/places/script existence arms once the sweep
# declares them.
class PosturesTest < Minitest::Test
  POSTURES_PATH = File.join(Nabu::Config::PROJECT_ROOT, "config", "postures.yml")
  RULES_PATH = File.join(Nabu::Config::PROJECT_ROOT, "config", "lect_facet_rules.yml")
  OVERRIDES_PATH = File.join(Nabu::Config::PROJECT_ROOT, "config", "lect_overrides.yml")
  SOURCES_PATH = File.join(Nabu::Config::PROJECT_ROOT, "config", "sources.yml")

  def postures
    @postures ||= Nabu::Postures.load(POSTURES_PATH)
  end

  # P71-0 (owner-ruled overlay-merge): a local/config/postures.yml merges
  # over the project file — per (slug, layer), the local declaration wins.
  def test_load_merges_an_overlay_pair_per_slug_and_layer
    Dir.mktmpdir do |dir|
      project = File.join(dir, "project.yml")
      local = File.join(dir, "local.yml")
      File.write(project, <<~YAML)
        sources:
          alpha:
            lect: {posture: identity}
            dating: {posture: undatable}
      YAML
      File.write(local, <<~YAML)
        sources:
          alpha:
            dating: {posture: dated, note: "local instrument dates it"}
          beta:
            lect: {posture: identity}
      YAML
      merged = Nabu::Postures.load([project, local])
      assert_equal "identity", merged.declared("alpha", layer: "lect").posture,
                   "project-only layers survive the merge"
      assert_equal "dated", merged.declared("alpha", layer: "dating").posture,
                   "the local declaration wins its (slug, layer)"
      assert_equal "identity", merged.declared("beta", layer: "lect").posture
    end
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

  # --- the lect layer: the P59-4 contract, unchanged through the move ---

  def test_every_passage_serving_source_has_a_lect_posture
    refute_nil postures, "config/postures.yml must exist — it is the judgment record"
    coverage = postures.lect_coverage(rules: rules, overrides: overrides)
    missing = passage_slugs.reject { |slug| coverage.key?(slug) }
    assert_empty missing,
                 "sources with NO lect posture (machine or declared): #{missing.join(', ')} — " \
                 "run `nabu layer suggest <slug>`, then wire a rule/override or declare a row " \
                 "(identity is an honest answer) in config/postures.yml"
  end

  # --- the P61-1 sweep: every layer, every source — ARMED ----------------

  def test_every_passage_serving_source_declares_dating_places_and_script
    %w[dating places script].each do |layer|
      coverage = postures.layer_coverage(layer)
      missing = passage_slugs.reject { |slug| coverage.key?(slug) }
      assert_empty missing,
                   "sources with NO #{layer} posture: #{missing.join(', ')} — run " \
                   "`nabu layer suggest <slug>`, then declare (undatable/unplaced/implied " \
                   "are honest answers) in config/postures.yml"
    end
  end

  def test_lect_declarations_never_shadow_machine_postures
    assert_empty postures.shadowing(rules: rules, overrides: overrides),
                 "a declared lect row duplicates a rules/overrides posture — delete the " \
                 "declaration (machine files are the single source of truth)"
  end

  # --- every layer: vocabulary, real sources, pending discipline --------

  def test_declarations_use_each_layers_ruled_vocabulary_and_name_real_sources
    slugs = Nabu::SourceRegistry.load(SOURCES_PATH).then do |registry|
      list = []
      registry.each_source { |entry| list << entry.slug }
      list
    end
    postures.declarations.each do |declaration|
      vocabulary = Nabu::Postures::LAYERS.fetch(declaration.layer)
      assert_includes vocabulary, declaration.posture,
                      "#{declaration.slug}/#{declaration.layer}: unknown posture " \
                      "#{declaration.posture.inspect} (ruled set: #{vocabulary.join('/')})"
      assert_includes slugs, declaration.slug,
                      "#{declaration.slug}: declared but not in config/sources.yml (a ghost row)"
    end
  end

  def test_pending_rows_carry_the_candidate_as_a_note_on_every_layer
    postures.declarations.select { |d| d.posture == "pending" }.each do |declaration|
      refute_nil declaration.note,
                 "#{declaration.slug}/#{declaration.layer}: a pending posture must name its " \
                 "candidate — pending without a note is just a silence with paperwork"
    end
  end

  def test_unknown_layer_keys_are_refused_loudly
    Dir.mktmpdir do |dir|
      path = File.join(dir, "postures.yml")
      File.write(path, "sources:\n  gretil:\n    vibe: {posture: good}\n")
      error = assert_raises(Nabu::Error) { Nabu::Postures.load(path) }
      assert_match(/vibe/, error.message, "a typo'd layer key must never silently vanish")
    end
  end

  # --- the migration fact: the P59-4 record survived the move -----------

  def test_the_lect_migration_kept_the_p59_4_census
    lect = postures.declarations.select { |d| d.layer == "lect" }
    by_posture = lect.group_by(&:posture).transform_values(&:size)
    assert_equal 56, lect.size,
                 "the P59-4 declarations survive the move (61 at migration; itant retired P61-3, " \
                 "oracc retired P62-2, etcsl/ccmh/freising/coptic-scriptorium retired P64-6, " \
                 "titus-avestan retired P66-1 — each when a machine grain took over: the " \
                 "shadowing rule, working; osta ADDED P77-1, disco P77-4)"
    # P64-6 (the №1-№10 rulings): 4 pendings retired to machine grains,
    # tla-hf/gretil/torot → identity, imp/goo300k → dates. P66-1: the LAST
    # pending (titus-avestan) retired — the adapter derives the
    # avestan-stage facet from the verse anchors and the ave-stage rule
    # covers all 248 docs. ZERO lect pendings held through P77-1: osta
    # joins as identity (bare osp, the tla-hf one-tag practice; №R-30's
    # works-table lane retires the row when it lands).
    assert_equal({ "identity" => 42, "dates" => 10, "codemap" => 4 }, by_posture)
  end
end

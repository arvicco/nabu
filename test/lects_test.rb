# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

# Nabu::Lects (P57-3) — the nabu-lects consume seam: a pure READ resolver
# over the lect registry (anchor x stage x variety x orthography) and its
# universal codemap, layered with Nabu-specific per-source overrides
# (config/lect_overrides.yml) and a per-document overlay seam. Exercised
# against a verbatim copy of the real upstream files
# (test/fixtures/nabu-lects/README.md).
class LectsTest < Minitest::Test
  FIXTURES = Nabu::TestSupport.fixtures("nabu-lects")
  LECT_OVERRIDES_PATH = File.join(Nabu::Config::PROJECT_ROOT, "config", "lect_overrides.yml")

  def lects
    @lects ||= Nabu::Lects.load(FIXTURES, overrides_path: LECT_OVERRIDES_PATH)
  end

  # --- #lect: bare anchors -----------------------------------------------

  def test_a_bare_anchor_is_the_whole_span_attested_with_no_ord_or_band
    ine = lects.lect("ine")
    assert_equal "ine", ine.anchor
    assert_nil ine.stage
    assert_nil ine.variety
    assert_nil ine.ortho
    assert_equal "Indo-European", ine.name
    assert_equal :attested, ine.mode
    assert_nil ine.ord
    assert_nil ine.band
  end

  # A bare anchor CAN carry its own band (non/ang/fro — no stages minted).
  def test_a_bare_anchor_with_no_stages_carries_its_own_band
    non = lects.lect("non")
    assert_equal [800, 1350], non.band
    assert_nil non.ord
  end

  # P76 U-7: the band's convention note rides the record verbatim — the
  # "ca." carrier (an approximate note tiers probable via Nabu::Certainty).
  def test_the_band_note_rides_the_record_verbatim
    runic = lects.lect("gmq:run")
    assert_equal "the Elder Futhark epigraphic span, approximate", runic.band_note
    assert_equal "probable", Nabu::Certainty.tier(:band_note, runic.band_note)
    assert_equal "conventional Norse philology, approximate", lects.lect("non").band_note,
                 "a bare anchor carries its own band's note"
    assert_nil lects.lect("ine:pro").band_note, "a note-less record stays nil"
  end

  # --- #lect: stages -------------------------------------------------------

  def test_a_reconstructed_stage_carries_mode_and_ord_from_the_registry
    pie = lects.lect("ine:pro")
    assert_equal "ine", pie.anchor
    assert_equal "pro", pie.stage
    assert_equal "Proto-Indo-European", pie.name
    assert_equal :reconstructed, pie.mode
    assert_equal 5, pie.ord
  end

  # gmq:run is the class-doc pin: real runic inscriptions are ATTESTED
  # epigraphy filed under a proto-looking tag — mode reads the registry
  # field, never the "pro"-adjacent tag spelling.
  def test_an_attested_stage_beside_a_reconstructed_sibling_stays_attested
    run = lects.lect("gmq:run")
    assert_equal "Runic Proto-Norse (attested)", run.name
    assert_equal :attested, run.mode
    assert_equal 10, run.ord
    assert_equal [150, 800], run.band
  end

  def test_stage_name_is_already_the_full_title_no_anchor_prefix
    assert_equal "Medieval Latin", lects.lect("lat:med").name
  end

  # --- #lect: varieties and orthographies -----------------------------------

  def test_a_bare_varietied_lect_composes_anchor_and_variety_names
    vul = lects.lect("lat/vul")
    assert_equal "lat", vul.anchor
    assert_nil vul.stage
    assert_equal "vul", vul.variety
    assert_equal "Latin — Vulgar Latin (attested substandard)", vul.name
    assert_equal :attested, vul.mode
    assert_nil vul.ord
    assert_nil vul.band, "lat carries no anchor-level band (only its stages do)"
  end

  def test_a_staged_varietied_lect_composes_all_three
    ecc = lects.lect("lat:late/ecc")
    assert_equal "late", ecc.stage
    assert_equal "ecc", ecc.variety
    assert_equal "Late Latin — Ecclesiastical Latin", ecc.name
    assert_equal 30, ecc.ord
    assert_equal [200, 600], ecc.band
  end

  def test_an_orthography_wraps_as_a_parenthetical_on_the_staged_name
    kyu = lects.lect("jpn:mod@kyu")
    assert_equal "mod", kyu.stage
    assert_equal "kyu", kyu.ortho
    assert_equal "Modern Japanese (Kyūjitai (pre-reform character forms))", kyu.name
  end

  # --- #lect: the script axis (P60-0, owner-ruled D60-a/b) -------------------
  #
  # ~script claims the script of the text AS HELD (the canonical surface,
  # machine-checkable from the bytes) — never the artifact's original
  # writing system, which is a separate catalog-side field. Tags resolve
  # against the registry's GLOBAL scripts table (not per-anchor: digraphia
  # is open-ended; attestation is a collection fact).

  def test_a_script_qualified_lect_resolves_against_the_global_table
    san = lects.lect("san~latn")
    assert_equal "san", san.anchor
    assert_equal "latn", san.script
    assert_nil san.stage
    assert_equal "Sanskrit in Latin script", san.name
    assert_equal :attested, san.mode
  end

  def test_script_composes_with_every_other_axis_in_strict_order
    full = lects.lect("lat:late/ecc~latn")
    assert_equal "late", full.stage
    assert_equal "ecc", full.variety
    assert_equal "latn", full.script
    assert_equal "Late Latin — Ecclesiastical Latin in Latin script", full.name
    assert_equal [200, 600], full.band, "stage facts ride through the script qualifier"
    assert_nil lects.lect("lat~latn:late"), "axis order is strict — ~ after : and /"
    assert_nil lects.lect("jpn:mod@kyu~jpan"), "~ comes BEFORE @, never after"
  end

  def test_an_unregistered_or_malformed_script_tag_is_nil
    assert_nil lects.lect("san~qqqq"), "qqqq is not in the scripts table"
    assert_nil lects.lect("san~Latn"), "ids are lowercase — the canonical spelling lives in the row"
    assert_nil lects.lect("san~lat"), "script tags are exactly 4 letters (ISO 15924 shape)"
  end

  def test_parse_id_captures_the_script_axis
    match = Nabu::Lects.parse_id("sga~ogam")
    assert_equal "sga", match[:anchor]
    assert_equal "ogam", match[:script]
    assert_nil match[:stage]
  end

  # --- #lect: nil for the unparseable and the undefined ---------------------

  def test_malformed_grammar_is_nil
    assert_nil lects.lect("LAT")
    assert_nil lects.lect("lat::med")
    assert_nil lects.lect("l")
    assert_nil lects.lect("")
  end

  def test_an_undefined_anchor_is_nil
    assert_nil lects.lect("zzz")
    assert_nil lects.lect("zzz:pro")
  end

  def test_an_undefined_stage_variety_or_ortho_is_nil
    assert_nil lects.lect("lat:xyz"), "lat has no xyz stage"
    assert_nil lects.lect("lat/xyz"), "lat has no xyz variety"
    assert_nil lects.lect("jpn:mod@xyz"), "jpn has no xyz ortho"
  end

  # --- #reconstructed? -------------------------------------------------------

  def test_reconstructed_predicate_reads_the_stage_mode_field
    assert lects.reconstructed?("ine:pro")
    refute lects.reconstructed?("gmq:run")
    refute lects.reconstructed?("lat"), "a bare anchor (no stage) is never reconstructed"
  end

  def test_reconstructed_predicate_is_false_not_raising_on_bad_ids
    refute lects.reconstructed?("totally not a lect id")
    refute lects.reconstructed?(nil)
  end

  # --- #resolve: precedence ---------------------------------------------------

  def test_an_unmapped_code_resolves_to_itself
    assert_equal "srd", lects.resolve("srd")
  end

  def test_a_codemap_key_resolves_to_its_universal_default
    assert_equal "grc:byz", lects.resolve("gkm")
    assert_equal "lat/vul", lects.resolve("la-vul")
  end

  # The class-doc precedence chain, all four tiers on one code (the real
  # ratified P57-3 overrides): per-document overlay > per-source override >
  # codemap > identity.
  def test_resolve_precedence_overlay_over_source_over_codemap_over_identity
    overlay = { "urn:nabu:derom:test:1" => { "la-vul" => "lat:arch" } }
    overlaid = Nabu::Lects.load(FIXTURES, overrides_path: LECT_OVERRIDES_PATH, overlay: overlay)

    assert_equal "lat/vul", overlaid.resolve("la-vul"), "no source, no urn -> the universal codemap default"
    assert_equal "roa:pro", overlaid.resolve("la-vul", source: "derom"),
                 "the ratified derom override wins over the codemap default"
    assert_equal "lat:arch", overlaid.resolve("la-vul", source: "derom", urn: "urn:nabu:derom:test:1"),
                 "the per-document overlay wins over the per-source override"
    assert_equal "roa:pro", overlaid.resolve("la-vul", source: "derom", urn: "urn:nabu:derom:test:2"),
                 "a urn absent from the overlay falls through to the per-source override"
  end

  def test_the_second_ratified_override_rundata_gmq_pro
    assert_equal "gmq:pro", lects.resolve("gmq-pro"), "the universal default is the reconstructed proto stage"
    assert_equal "gmq:run", lects.resolve("gmq-pro", source: "rundata"),
                 "rundata's urnordisk inscriptions are attested epigraphy, not the reconstruction"
  end

  def test_a_source_with_no_override_falls_through_to_the_codemap
    assert_equal "gmq:pro", lects.resolve("gmq-pro", source: "some-other-source")
  end

  def test_resolve_without_an_overrides_path_never_applies_any_override
    bare = Nabu::Lects.load(FIXTURES)
    assert_equal "lat/vul", bare.resolve("la-vul", source: "derom"),
                 "no overrides_path loaded -> the source override never fires"
  end

  # P71-0 (owner-ruled overlay-merge): overrides_path may be the
  # [project, local] pair — per-source maps merge, the local row winning
  # its slug while project-only slugs stay.
  def test_overrides_path_pair_merges_with_local_precedence
    Dir.mktmpdir do |dir|
      local = File.join(dir, "lect_overrides.yml")
      File.write(local, <<~YAML)
        sources:
          rundata:
            gmq-pro: gmq:pro
      YAML
      merged = Nabu::Lects.load(FIXTURES, overrides_path: [LECT_OVERRIDES_PATH, local])
      assert_equal "gmq:pro", merged.resolve("gmq-pro", source: "rundata"),
                   "the local overlay wins its slug"
      assert_equal "roa:pro", merged.resolve("la-vul", source: "derom"),
                   "project-only slugs keep their project override"
    end
  end

  # --- #resolution: the with-basis variant (P81 U-5) --------------------------

  def test_resolution_reports_the_precedence_basis
    overlay = { "urn:nabu:derom:test:1" => { "la-vul" => "lat:arch" } }
    overlaid = Nabu::Lects.load(FIXTURES, overrides_path: LECT_OVERRIDES_PATH, overlay: overlay)

    assert_equal Nabu::Lects::Resolution.new(id: "grc:byz", basis: "codemap"),
                 overlaid.resolution("gkm")
    assert_equal Nabu::Lects::Resolution.new(id: "roa:pro", basis: "override:derom"),
                 overlaid.resolution("la-vul", source: "derom")
    assert_equal Nabu::Lects::Resolution.new(id: "lat:arch", basis: "overlay"),
                 overlaid.resolution("la-vul", source: "derom", urn: "urn:nabu:derom:test:1"),
                 "a plain-hash overlay carries no journal basis — the generic word, honestly"
    assert_equal Nabu::Lects::Resolution.new(id: "srd", basis: nil),
                 overlaid.resolution("srd"), "identity makes no claim — no basis"
    assert_equal overlaid.resolve("la-vul", source: "derom"),
                 overlaid.resolution("la-vul", source: "derom").id,
                 "resolve delegates — one walk, never two answers"
  end

  def test_resolution_reads_the_journal_basis_through_the_overlay
    Dir.mktmpdir do |root|
      seed_module_tree(root)
      config = journal_config(root)
      db = Nabu::Store::LectJournal.open!(config.lects_journal_path)
      Nabu::Store::LectJournal.assign!(db, urn: "urn:nabu:x:1", code: "lat", lect_id: "lat:med",
                                           basis: "rule:akk-period")
      db.disconnect

      live = Nabu::Lects.load_default(config: config)
      resolution = live.resolution("lat", urn: "urn:nabu:x:1")
      assert_equal "lat:med", resolution.id
      assert_equal "rule:akk-period", resolution.basis,
                   "the journal-backed overlay reports the row's own basis verbatim"
    end
  end

  # --- override tier machine fields (P81 U-5) ---------------------------------

  def test_an_override_row_may_carry_a_promoted_tier_field
    Dir.mktmpdir do |dir|
      path = File.join(dir, "lect_overrides.yml")
      File.write(path, <<~YAML)
        sources:
          etcsl:
            sux: { lect: "sux:post", tier: approximation }
          sblgnt:
            grc: "grc:koi"
      YAML
      lects = Nabu::Lects.load(FIXTURES, overrides_path: path)
      assert_equal "sux:post", lects.resolve("sux", source: "etcsl"),
                   "a hash row resolves exactly like the bare string shape"
      assert_equal "approximation", lects.override_tier("etcsl", "sux")
      assert_nil lects.override_tier("sblgnt", "grc"), "a bare string row states no tier"
      assert_nil lects.override_tier("nobody", "sux")

      assert_equal({ "etcsl" => { "sux" => "approximation" } },
                   Nabu::Lects.override_tiers([path]),
                   "the class-level reader serves render surfaces without a registry instance")
    end
  end

  def test_the_live_overrides_file_carries_the_promoted_tiers
    assert_equal "approximation", lects.override_tier("etcsl", "sux"),
                 "№1's stated source-grain tier, machine-readable since P81 U-5"
    assert_equal "certain", lects.override_tier("elephantine", "arc"), "D58-d's certain row"
  end

  # --- #parent_of: the descent walk -------------------------------------------

  def test_a_root_anchor_has_no_parent
    assert_nil lects.parent_of("ine")
  end

  def test_a_family_anchor_chains_to_its_parent_bare
    assert_equal "ine", lects.parent_of("gem")
    assert_equal "gem", lects.parent_of("gmw")
  end

  def test_a_staged_lect_inherits_its_anchors_parent
    assert_equal "gem", lects.parent_of("gmw:pro"),
                 "gmw:pro declares no parent of its own -> inherits gmw's anchor-level parent"
  end

  def test_a_lect_with_a_staged_parent_edge
    assert_equal "itc:pro", lects.parent_of("lat")
  end

  # non's own parent is the ATTESTED runic stage (most-specific-ancestor
  # rule); isl's stages inherit non's parent via the same walk.
  def test_the_most_specific_ancestor_and_its_stage_inheritance
    assert_equal "gmq:run", lects.parent_of("non")
    assert_equal "non", lects.parent_of("isl")
    assert_equal "non", lects.parent_of("isl:old"),
                 "isl:old declares no parent of its own -> inherits isl's anchor-level parent"
  end

  def test_parent_of_is_nil_for_the_unparseable_and_the_undefined
    assert_nil lects.parent_of("zzz")
    assert_nil lects.parent_of("lat:xyz")
    assert_nil lects.parent_of("not a lect id")
  end

  # --- #stages_of --------------------------------------------------------------

  # P58 rider (the owner's zho probe): registered varieties are ladder
  # content too — zho/lit is the wenyan register, not "unstaged".
  def test_varieties_of_returns_records_in_registry_order
    varieties = lects.varieties_of("zho")
    assert_equal ["zho/lit"], varieties.map(&:id)
    assert_equal "lit", varieties.first.variety
  end

  def test_varieties_of_is_empty_for_an_anchor_without_varieties_or_undefined
    assert_empty lects.varieties_of("grc")
    assert_empty lects.varieties_of("zzz")
  end

  def test_stages_of_are_ord_sorted
    assert_equal %w[lat:arch lat:cla lat:late lat:med lat:ren lat:new],
                 lects.stages_of("lat").map(&:id)
    assert_equal %w[gmq:pro gmq:run], lects.stages_of("gmq").map(&:id)
  end

  def test_stages_of_is_empty_for_an_anchor_with_no_stages_or_undefined
    assert_empty lects.stages_of("ang")
    assert_empty lects.stages_of("zzz")
  end

  # --- loading shapes ------------------------------------------------------------

  def test_a_missing_module_tree_loads_empty
    Dir.mktmpdir do |dir|
      empty = Nabu::Lects.load(dir)
      assert_nil empty.lect("ine")
      assert_equal "srd", empty.resolve("srd")
      assert_equal "la-vul", empty.resolve("la-vul"), "an empty codemap resolves every code to itself"
    end
  end

  def test_load_default_feature_detects_the_canonical_tree
    Dir.mktmpdir do |root|
      # A real (if bare) config_path — so config.lect_overrides_path resolves
      # UNDER this tmp root, never CWD (unlike the "(test)" placeholder the
      # form_lemma/cldf_spine siblings use, which have no file at that path
      # to begin with).
      config = Nabu::Config.new(canonical_dir: File.join(root, "canonical"),
                                db_dir: File.join(root, "db"),
                                sources_path: File.join(root, "sources.yml"),
                                config_path: File.join(root, "config", "nabu.yml"))
      assert_nil Nabu::Lects.load_default(config: config),
                 "no canonical/nabu-lects tree -> nil (the cldf-spine/nabu-data posture)"
      dest = File.join(root, "canonical", "nabu-lects")
      FileUtils.mkdir_p(dest)
      FileUtils.cp_r(Dir[File.join(FIXTURES, "*")], dest)

      live = Nabu::Lects.load_default(config: config)
      refute_nil live
      assert_equal "Indo-European", live.lect("ine").name
      assert_equal "lat/vul", live.resolve("la-vul", source: "derom"),
                   "no config/lect_overrides.yml under this tmp root -> the codemap default only"
    end
  end

  def test_load_default_reads_the_real_lect_overrides_path
    Dir.mktmpdir do |root|
      FileUtils.mkdir_p(File.join(root, "config"))
      FileUtils.cp(LECT_OVERRIDES_PATH, File.join(root, "config", "lect_overrides.yml"))
      config = Nabu::Config.new(canonical_dir: File.join(root, "canonical"), db_dir: File.join(root, "db"),
                                sources_path: File.join(root, "sources.yml"),
                                config_path: File.join(root, "config", "nabu.yml"))
      dest = File.join(root, "canonical", "nabu-lects")
      FileUtils.mkdir_p(dest)
      FileUtils.cp_r(Dir[File.join(FIXTURES, "*")], dest)

      live = Nabu::Lects.load_default(config: config)
      assert_equal "roa:pro", live.resolve("la-vul", source: "derom")
    end
  end

  # --- the journal overlay wiring (P58-1) ---------------------------------------

  def journal_config(root)
    Nabu::Config.new(canonical_dir: File.join(root, "canonical"), db_dir: File.join(root, "db"),
                     sources_path: File.join(root, "sources.yml"),
                     config_path: File.join(root, "config", "nabu.yml"))
  end

  def seed_module_tree(root)
    dest = File.join(root, "canonical", "nabu-lects")
    FileUtils.mkdir_p(dest)
    FileUtils.cp_r(Dir[File.join(FIXTURES, "*")], dest)
  end

  def test_load_default_wires_the_journal_overlay_when_the_file_exists
    Dir.mktmpdir do |root|
      seed_module_tree(root)
      config = journal_config(root)
      db = Nabu::Store::LectJournal.open!(config.lects_journal_path)
      Nabu::Store::LectJournal.assign!(db, urn: "urn:nabu:x:1", code: "lat", lect_id: "lat:med",
                                           basis: "owner")
      db.disconnect

      live = Nabu::Lects.load_default(config: config)
      assert_equal "lat:med", live.resolve("lat", urn: "urn:nabu:x:1"),
                   "the journal is the overlay tier — highest precedence"
      assert_equal "lat", live.resolve("lat", urn: "urn:nabu:other"),
                   "an unassigned urn falls through to identity"
    end
  end

  def test_load_default_without_a_journal_file_behaves_byte_identically
    Dir.mktmpdir do |root|
      seed_module_tree(root)
      live = Nabu::Lects.load_default(config: journal_config(root))
      assert_equal "lat", live.resolve("lat", urn: "urn:nabu:x:1"),
                   "no db/lects.sqlite3 -> no overlay, the P57-3 posture unchanged"
    end
  end

  def test_an_explicit_overlay_argument_beats_the_journal
    Dir.mktmpdir do |root|
      seed_module_tree(root)
      config = journal_config(root)
      db = Nabu::Store::LectJournal.open!(config.lects_journal_path)
      Nabu::Store::LectJournal.assign!(db, urn: "urn:nabu:x:1", code: "lat", lect_id: "lat:med",
                                           basis: "owner")
      db.disconnect

      live = Nabu::Lects.load_default(config: config, overlay: {})
      assert_equal "lat", live.resolve("lat", urn: "urn:nabu:x:1"),
                   "an explicit overlay: argument (tests, callers with their own seam) wins over the journal"
    end
  end

  def test_stage_and_variety_tags_admit_trailing_digits
    match = Nabu::Lects.parse_id("sux:ur3")
    assert_equal "ur3", match[:stage], "P58-5 grammar: the field's own periodization names (Ur III)"
    assert_nil Nabu::Lects.parse_id("sux:3ur"), "digits never lead a tag"
  end

  # --- Nabu::Lects.parse_id: the grammar utility --------------------------------

  def test_parse_id_captures_every_axis
    match = Nabu::Lects.parse_id("lat:late/ecc@foo1")
    assert_equal "lat", match[:anchor]
    assert_equal "late", match[:stage]
    assert_equal "ecc", match[:variety]
    assert_equal "foo1", match[:ortho]
  end

  def test_parse_id_is_nil_for_ungrammatical_input
    assert_nil Nabu::Lects.parse_id("LAT")
    assert_nil Nabu::Lects.parse_id("lat/med:foo")
  end

  # --- feature-detection conformance (P57-3 point 6) ----------------------------

  # The absence contract, stated directly: no canonical/nabu-lects tree ->
  # nil, never raises. (test_load_default_feature_detects_the_canonical_tree
  # above exercises the same fact as its opening assertion; this pins it as
  # its own named contract per the packet.)
  def test_load_default_returns_nil_without_raising_when_canonical_absent
    Dir.mktmpdir do |root|
      config = Nabu::Config.new(canonical_dir: File.join(root, "canonical"), db_dir: File.join(root, "db"),
                                sources_path: File.join(root, "sources.yml"),
                                config_path: File.join(root, "config", "nabu.yml"))
      assert_nil Nabu::Lects.load_default(config: config)
    end
  end

  # P57-4 wires the first consumers (the etym recon predicate/display
  # mapping, the language stage ladder, the search --lect filter) — this
  # guard now pins the ALLOWLIST of production callsites rather than a zero
  # count (the P57-3 posture it superseded). A callsite appearing outside
  # this set is very likely accidental early wiring of some future packet —
  # exactly the drift this test caught before; update the allowlist
  # deliberately when it is not.
  def test_only_the_p57_4_consumers_call_lects_in_production
    lib_root = File.expand_path("../lib", __dir__)
    this_file = File.join(lib_root, "nabu", "lects.rb")
    pattern = /Nabu::Lects\.(load_default|load|new)\b/
    # P58-4 adds rebuild.rb deliberately (the lect-facet pipeline stage,
    # feature-detected); P58-6 adds query/define.rb (the "*" reconstruction
    # scope reads the registry mode through the same :auto contract);
    # P59-3 adds query/lect_filter.rb — the ONE shared dispatch module the
    # passage-serving queries (search/parallels, and define/cognates via
    # their own grains) now include instead of each opening the registry.
    # P70 adds store/lect_journal.rb — rederive! re-mints the journal from
    # config + rules + infer-dates, and infer-dates needs the registry —
    # and incremental_rebuild.rb: a dirty incremental re-derives the
    # journal + lect facets exactly as the full rebuild does.
    allowlist = %w[nabu/cli.rb nabu/query/etym.rb nabu/query/search.rb nabu/mcp/tools.rb
                   nabu/rebuild.rb nabu/query/define.rb nabu/query/lect_filter.rb
                   nabu/store/lect_journal.rb nabu/incremental_rebuild.rb]
                .map { |rel| File.join(lib_root, rel) }

    offenders = Dir[File.join(lib_root, "**", "*.rb")]
                .reject { |path| path == this_file || allowlist.include?(path) }
                .select { |path| File.read(path).match?(pattern) }
    assert_empty offenders, "a Nabu::Lects callsite appeared outside the P57-4 consumer " \
                            "allowlist (#{allowlist.join(', ')}) — update it deliberately if intentional"
  end
end

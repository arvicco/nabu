# frozen_string_literal: true

require "test_helper"

module Export
  # Nabu::Export::AlignPairs (`nabu export align`): verse pairs off the
  # alignment hub — the base witness against every other attesting
  # witness, per ref — each side with its passage urns, text, source and
  # effective license; --with-morph adds per-token form/lemma/feats where
  # the source stores gold morphology (decoded through the morph façade).
  class AlignPairsTest < Minitest::Test
    include StoreTestDB
    include AlignmentExportRig

    def setup = rig_setup
    def teardown = rig_teardown

    def table(registry, **)
      Nabu::Export::AlignPairs.new(catalog: @catalog, fulltext: @fulltext, registry: registry, **)
    end

    def test_columns_are_documented_and_morph_widens_them
      registry = seed_nt
      plain = table(registry, ref: "MARK 2.3").columns.map(&:name)
      morph = table(registry, ref: "MARK 2.3", with_morph: true).columns.map(&:name)
      assert_equal plain + %w[base_morph base_tokens witness_morph witness_tokens], morph
      assert_includes plain, "base_license_class"
      assert_includes plain, "witness_license_class"
      assert(table(registry, ref: "MARK 2.3", with_morph: true).columns.all? { |c| !c.description.to_s.empty? })
    end

    def test_one_pair_per_other_attesting_witness_against_the_registry_first_base
      registry = seed_nt
      rows = table_rows(table(registry, ref: "MARK 2.3"))
      assert_equal(%w[latin-nt sblgnt vulgate], rows.map { |row, _| row["witness"] })
      row, draws = rows.last
      assert_equal "nt", row["work"]
      assert_equal "MARK 2.3", row["ref"]
      assert_equal "greek-nt", row["base_witness"]
      assert_equal "urn:nabu:proiel:greek-nt:s0", row["base_urns"]
      assert_equal GREEK_PROIEL, row["base_text"]
      assert_equal %w[proiel nc], row.values_at("base_source", "base_license_class")
      assert_equal %w[vulgate open lat], row.values_at("witness_source", "witness_license_class", "witness_language")
      assert_equal LATIN_VULGATE, row["witness_text"]
      assert_equal [%w[proiel nc], %w[vulgate open]], draws, "a pair draws on both sides' licenses"
    end

    def test_base_override_and_witness_restriction
      registry = seed_nt
      rows = table_rows(table(registry, ref: "MARK 2.3", base: "vulgate", witnesses: %w[latin-nt]))
      assert_equal([%w[vulgate latin-nt]], rows.map { |row, _| row.values_at("base_witness", "witness") })
    end

    def test_unknown_labels_are_refused_naming_the_registered_set
      registry = seed_nt
      error = assert_raises(Nabu::Export::Error) { table_rows(table(registry, ref: "MARK 2.3", base: "nope")) }
      assert_match(/no witness "nope".*greek-nt, latin-nt, sblgnt, vulgate/, error.message)
    end

    def test_with_morph_carries_gold_tokens_decoded_and_null_where_the_source_has_none
      registry = seed_nt
      rows = table_rows(table(registry, ref: "MARK 2.3", with_morph: true)).map(&:first)
      latin = rows.find { |row| row["witness"] == "latin-nt" }
      assert_equal "gold", latin["base_morph"]
      assert_equal({ "form" => "ἔρχονται", "lemma" => "ἔρχομαι", "feats" => "person=3|number=plur|tense=pres|" \
                                                                            "mood=ind|voice=mid",
                     "citation" => "MARK 2.3" }, latin["base_tokens"].last)
      assert_equal({ "form" => "et", "lemma" => "et", "feats" => nil, "citation" => "MARK 2.3" },
                   latin["witness_tokens"].first)
      assert_equal "person=3|number=plur|tense=past|mood=ind", latin["witness_tokens"].last["feats"]
      vulgate = rows.find { |row| row["witness"] == "vulgate" }
      assert_nil vulgate["witness_morph"], "form-only tokens: no gold morphology to claim"
      assert_equal "Et", vulgate["witness_tokens"].first["form"]
      assert_nil vulgate["witness_tokens"].first["lemma"]
    end

    def test_whole_work_walk_and_refs_the_base_lacks_are_counted
      registry = seed_nt
      t = table(registry, work: "nt", base: "sblgnt")
      rows = table_rows(t).map(&:first)
      assert_equal(["MARK 2.3"] * 3, rows.map { |row| row["ref"] }, "MARK 2.4 has no sblgnt base")
      assert_equal 2, t.notes.fetch("refs")
      assert_equal 1, t.notes.fetch("refs_without_base")
      rows = table_rows(table(registry, work: "nt")).map(&:first)
      assert_equal((["MARK 2.3"] * 3) + ["MARK 2.4"], rows.map { |row| row["ref"] })
    end

    def test_a_missing_work_or_ref_is_refused
      registry = seed_nt
      error = assert_raises(Nabu::Export::Error) { table(registry, work: "ot") }
      assert_match(/unknown alignment work "ot"/, error.message)
      error = assert_raises(Nabu::Export::Error) { table_rows(table(registry, ref: "LUKE 9")) }
      assert_match(/no attested refs for LUKE 9/, error.message)
      unattested = table(registry, ref: "LUKE 9.9")
      assert_empty table_rows(unattested), "a single unattested ref exports honestly empty"
      assert_equal 1, unattested.notes.fetch("refs_without_base")
    end
  end
end

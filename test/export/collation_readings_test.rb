# frozen_string_literal: true

require "test_helper"

module Export
  # Nabu::Export::CollationReadings (`nabu export collation`): the
  # `align --collate` apparatus as rows — per anchor ref, every witness
  # reading with its passage urns, its (language, script) cell, its role
  # (base / variant / uncollated), the apparatus against the base, and its
  # source + effective license.
  class CollationReadingsTest < Minitest::Test
    include StoreTestDB
    include AlignmentExportRig

    def setup = rig_setup
    def teardown = rig_teardown

    def table(registry, **)
      Nabu::Export::CollationReadings.new(catalog: @catalog, fulltext: @fulltext, registry: registry, **)
    end

    def test_every_column_is_documented
      columns = table(seed_nt, ref: "MARK 2.3").columns
      assert_equal %w[work ref language script witness urns role base_witness reading agrees apparatus
                      collation source license_class], columns.map(&:name)
      assert(columns.all? { |column| !column.description.to_s.empty? })
    end

    def test_cells_become_base_and_variant_rows_with_their_apparatus
      rows = table_rows(table(seed_nt, ref: "MARK 2.3"))
      greek = rows.map(&:first).select { |row| row["language"] == "grc" }
      assert_equal(%w[greek-nt sblgnt], greek.map { |row| row["witness"] })
      base, variant = greek
      assert_equal ["base", nil, nil, "collated", "Greek"],
                   base.values_at("role", "agrees", "apparatus", "collation", "script")
      assert_equal "urn:nabu:proiel:greek-nt:s0", base["urns"]
      assert_equal GREEK_PROIEL, base["reading"], "the reading is the raw token stream"
      assert_equal "variant", variant["role"]
      assert_equal "greek-nt", variant["base_witness"]
      assert_equal false, variant["agrees"]
      assert_match(/φέροντες → ⸂φέροντες/, variant["apparatus"])
      assert_equal %w[sblgnt attribution], variant.values_at("source", "license_class")
      draws = rows.find { |row, _| row["witness"] == "sblgnt" }.last
      assert_equal [%w[sblgnt attribution], %w[proiel nc]], draws,
                   "a variant row quotes the base's tokens — it draws on both"
    end

    def test_a_lone_witness_is_an_uncollated_row
      seed_witness("urn:nabu:proiel:gothic-nt", slug: "proiel", license: "nc", language: "got",
                                                text: "jah qemun at imma")
      registry = rig_registry([["urn:nabu:proiel:gothic-nt", "gothic-nt"]])
      row, draws = table_rows(table(registry, ref: "MARK 2.3")).first
      assert_equal ["uncollated", "sole", "jah qemun at imma", nil], row.values_at("role", "collation", "reading",
                                                                                   "base_witness")
      assert_equal [%w[proiel nc]], draws
    end

    def test_whole_work_walk_and_missing_witnesses_counted
      t = table(seed_nt, work: "nt")
      rows = table_rows(t).map(&:first)
      assert_equal((["MARK 2.3"] * 4) + (["MARK 2.4"] * 2), rows.map { |row| row["ref"] })
      assert_equal 2, t.notes.fetch("refs")
      assert_equal({ "no_match" => 2 }, t.notes.fetch("missing_witnesses"))
    end

    def test_base_override_and_its_refusal
      registry = seed_nt
      rows = table_rows(table(registry, ref: "MARK 2.3", base: "vulgate")).map(&:first)
      latin = rows.select { |row| row["language"] == "lat" }
      assert_equal(%w[vulgate latin-nt], latin.map { |row| row["witness"] })
      error = assert_raises(Nabu::Export::Error) { table_rows(table(registry, ref: "MARK 2.3", base: "nope")) }
      assert_match(/no witness "nope"/, error.message)
    end
  end
end

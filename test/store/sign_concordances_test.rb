# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

# Store::SignConcordances: the never-parsed concordance assets in the held
# OSL repo's 00etc (Wikidata list concordances, the AKS oid table, MZL↔KWU,
# PGSL, eBL sign names, the Attinger / short-form / ŋ-less value maps)
# parsed, joined onto the OSL sign ids (@oid) and precompiled into the
# sign_concordances table. Every source row either joins or is censused
# with a reason — never silently dropped.
class SignConcordancesTest < Minitest::Test
  include StoreTestDB

  OSL = Nabu::TestSupport.fixtures("osl")
  ETC = File.join(OSL, "00etc")
  Builder = Nabu::Store::SignConcordances

  def setup
    @catalog = store_test_db
  end

  def with_canonical
    Dir.mktmpdir do |dir|
      osl = File.join(dir, "osl")
      FileUtils.mkdir_p(File.join(osl, "00lib"))
      FileUtils.cp(File.join(OSL, "osl.asl"), File.join(osl, "00lib", "osl.asl"))
      FileUtils.cp_r(ETC, osl)
      yield dir
    end
  end

  def rows_for(oid, scheme)
    @catalog[:sign_concordances].where(oid: oid, scheme: scheme)
                                .select_map(%i[key value]).sort_by { |pair| pair.map(&:to_s) }
  end

  def census(summary, asset)
    summary.assets.find { |entry| entry.asset == asset }
  end

  # -- per-asset parse ------------------------------------------------------

  def test_parses_the_wikidata_script_csv_list_columns
    rows = Builder::Parse.wikidata_script(File.join(ETC, "wikidata-script.csv"))
    assert_equal 8, rows.size, "every data row under the header"
    shesh = rows.find { |row| row.qid == "Q87556389" }
    assert_equal "𒋀  CUNEIFORM SIGN SHESH (U+122C0)", shesh.character
    assert_equal "331", shesh.lists["Labat"]
    assert_equal "182", shesh.lists["AKS"]
    assert_equal "246", shesh.lists["ATU1"]
    assert_equal "138,VI", shesh.lists["DP"], "a quoted comma survives"
    refute shesh.lists.key?("Char image"), "the image column carries no concordance (nbsp padding)"
    refute shesh.lists.key?("PI"), "empty cells are absent, never blank strings"
  end

  def test_parses_the_two_column_and_oid_tables
    assert_equal({ "Q87556614" => %w[o0000581 o0002834] },
                 Builder::Parse.q_to_oid(File.join(ETC, "wikidata", "Q-to-oid.tab")).slice("Q87556614"))
    assert_equal %w[Q87554995 U+12000],
                 Builder::Parse.columns(File.join(ETC, "wikidata.tsv")).first.first(2)
    aks = Builder::Parse.columns(File.join(ETC, "wikidata", "oid-aks-lref-name.tsv"))
    assert_equal %w[o0000000 232 vacat], aks[5], "the vacat row keeps its short shape"
    assert_equal %w[ses šeš], Builder::Parse.columns(File.join(ETC, "attinger.tab")).last
  end

  def test_parses_the_ebl_sign_names_json
    names = Builder::Parse.ebl_names(File.join(ETC, "ebl-sign-names.json"))
    assert_equal ["1(BAN₂)", "AK", "MIN", "|IGI.DIB|", "|UD.ŠEŠ.KI|", "|ŠEŠ.AB|", "|ŠEŠ.KI|", "ŠEŠ"], names
  end

  # -- the join -------------------------------------------------------------

  def test_a_known_sign_gains_its_concordance_numbers
    with_canonical do |dir|
      Builder.rebuild!(catalog: @catalog, canonical_dir: dir)
      assert_equal [[nil, "331"]], rows_for("o0002834", "Labat"), "ŠEŠ is Labat 331"
      assert_equal [[nil, "182"]], rows_for("o0002834", "AKS")
      assert_equal [[nil, "246"]], rows_for("o0002834", "ATU1")
      assert_equal [[nil, "007"]], rows_for("o0002834", "PGSL")
      assert_equal [%w[535 029,032]], rows_for("o0002834", "MZL-KWU")
      assert_equal [[nil, "ŠEŠ"]], rows_for("o0002834", "eBL")
      assert_equal [%w[ses šeš]], rows_for("o0002834", "attinger")
      assert_equal [%w[šes še₁₆], %w[šeš še₁₆]], rows_for("o0002834", "csf")
      assert_equal [[nil, "70"]], rows_for("o0000093", "AKS"), "AK is AKS 70"
      assert_equal [["731", nil]], rows_for("o0001487", "MZL-KWU"), "a bare KWU side stays NULL"
      assert_equal [[nil, "183"]], rows_for("o0002740", "AKS"), "the oid-keyed AKS table reaches |ŠEŠ.KI|"
    end
  end

  def test_a_multi_oid_wikidata_item_attaches_only_to_held_oids
    with_canonical do |dir|
      Builder.rebuild!(catalog: @catalog, canonical_dir: dir)
      qids = rows_for("o0002834", "Wikidata").map(&:last)
      assert_equal %w[Q87556389 Q87556614], qids, "URI3's item names ŠEŠ's oid too (upstream's own Q-to-oid row)"
      assert_equal 0, @catalog[:sign_concordances].where(oid: "o0000581").count
    end
  end

  def test_every_row_joins_or_is_censused_with_a_reason
    with_canonical do |dir|
      summary = Builder.rebuild!(catalog: @catalog, canonical_dir: dir)
      summary.assets.each do |entry|
        assert_equal entry.rows, entry.joined + entry.skipped.values.sum,
                     "#{entry.asset}: joined + skipped accounts for every row"
      end
      csv = census(summary, "wikidata-script.csv")
      assert_equal [8, 5], [csv.rows, csv.joined]
      assert_equal({ "no-join" => 2, "oid-not-held" => 1 }, csv.skipped)
      assert_equal({ "oid-not-held" => 2, "vacat" => 2 },
                   census(summary, "wikidata/oid-aks-lref-name.tsv").skipped)
      assert_equal({ "comment" => 2, "name-not-held" => 3, "no-sign-name" => 1 },
                   census(summary, "mzl-kwu.tsv").skipped)
      assert_equal({ "name-not-held" => 1, "no-sign-name" => 1, "separator" => 1 },
                   census(summary, "pgsl.tab").skipped)
      assert_equal({ "name-not-held" => 1 }, census(summary, "ebl-sign-names.json").skipped)
      assert_equal({ "ambiguous" => 1, "value-not-held" => 1 }, census(summary, "csf.tab").skipped,
                   "idₓ lives on two signs — no sign-level join, said plainly")
      assert_equal({ "value-not-held" => 2 }, census(summary, "eng.tab").skipped)
      assert_equal 4, census(summary, "wikidata.tsv").duplicates,
                   "the Q→codepoint table restates the item ids the csv already joined"
      assert_equal summary.rows, @catalog[:sign_concordances].count
    end
  end

  def test_name_join_names_its_lane
    list = Nabu::SignList.load(File.join(OSL, "osl.asl"))
    assert_equal(["|A.BARA₂|", "aka"], Builder.name_join(list, "|A.BARAG|").then { |r, via| [r.name, via] })
    assert_equal(%w[LAK433 form], Builder.name_join(list, "LAK433").then { |r, via| [r.name, via] })
    assert_equal "name", Builder.name_join(list, "ŠEŠ").last
    assert_nil Builder.name_join(list, "NOSUCH")
  end

  # -- lifecycle -------------------------------------------------------------

  def test_rebuild_is_idempotent
    with_canonical do |dir|
      first = Builder.rebuild!(catalog: @catalog, canonical_dir: dir)
      snapshot = @catalog[:sign_concordances].order(:oid, :scheme, :key, :value).all
      second = Builder.rebuild!(catalog: @catalog, canonical_dir: dir)
      assert_equal first.rows, second.rows
      assert_equal snapshot, @catalog[:sign_concordances].order(:oid, :scheme, :key, :value).all
    end
  end

  def test_an_absent_cone_is_the_honest_empty_table
    Dir.mktmpdir do |dir|
      summary = Builder.rebuild!(catalog: @catalog, canonical_dir: dir)
      assert_equal 0, summary.rows
      assert_empty summary.assets
    end
    assert_equal 0, Builder.rebuild!(catalog: @catalog, canonical_dir: nil).rows
  end
end

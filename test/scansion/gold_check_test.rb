# frozen_string_literal: true

require "test_helper"
require "json"

# The gold harness (P152): the scanner over every passage the held meter
# layer covers, compared with pedecerto / hypotactic line by line, the dev
# split reported apart. In-memory catalog; gold payload shapes copied from
# the live layer (pedecerto "DSSS" / "DS-|DD-", hypotactic "-uu --").
class ScansionGoldCheckTest < Minitest::Test
  GoldCheck = Nabu::Scansion::GoldCheck

  def test_decodes_pedecerto_patterns
    assert_equal [:hexameter, "DSSSD", nil], GoldCheck.decode("pedecerto", "meter" => "H", "pattern" => "DSSS")
    assert_equal [:hexameter, "DSSDS", nil], GoldCheck.decode("pedecerto", "meter" => "H", "pattern" => "DSSDS")
    assert_equal [:pentameter, "SD", nil], GoldCheck.decode("pedecerto", "meter" => "P", "pattern" => "SD-|DD-")
    assert_nil GoldCheck.decode("pedecerto", "meter" => "H", "pattern" => "not scanned")
    assert_nil GoldCheck.decode("pedecerto", "meter" => "G", "pattern" => "")
  end

  def test_decodes_hypotactic_quantity_strings
    gold = GoldCheck.decode("hypotactic", "meter" => "dactylic hexameter",
                                          "pattern" => "- uu -uu -u u-uu -uu --")
    assert_equal [:hexameter, "DDDDD"], gold.first(2)
    assert_equal "-uu-uu-uu-uu-uu--", gold[2]
    assert_equal :pentameter, GoldCheck.decode("hypotactic", "meter" => "dactylic pentameter",
                                                             "pattern" => "-- -uu- -uu -uu-")[0]
    assert_nil GoldCheck.decode("hypotactic", "meter" => "iambic trimeter (tragic)", "pattern" => "u-u-")
  end

  def test_the_dev_split_is_declared_by_work_and_book
    assert GoldCheck.dev?("urn:cts:latinLit:phi0690.phi003.perseus-lat2:1.1")
    refute GoldCheck.dev?("urn:cts:latinLit:phi0690.phi003.perseus-lat2:2.1")
    refute GoldCheck.dev?("urn:cts:latinLit:phi0690.phi002.perseus-lat2:1.1")
  end

  def test_runs_the_scanner_over_the_gold_layer_and_tallies_agreement
    with_catalog do |catalog, add|
      add.call("urn:cts:latinLit:phi0690.phi003.perseus-lat2:1.1", "lat",
               "Arma virumque cano, Troiae qui primus ab oris", "pedecerto", "meter" => "H", "pattern" => "DDSS")
      add.call("urn:cts:latinLit:phi0959.phi001.perseus-lat2:1.1.2", "lat",
               "edere, materia conveniente modis.", "pedecerto", "meter" => "P", "pattern" => "DD-|DD-")
      # held out, deliberately mismatched gold: counts as a disagreement
      add.call("urn:cts:latinLit:phi0959.phi001.perseus-lat2:2.1.1", "lat",
               "Arma gravi numero violentaque bella parabam", "pedecerto", "meter" => "H", "pattern" => "SDDD")
      add.call("urn:cts:greekLit:tlg0012.tlg002.perseus-grc2:1.1", "grc",
               "ἄνδρα μοι ἔννεπε, μοῦσα, πολύτροπον, ὃς μάλα πολλὰ", "hypotactic",
               "meter" => "dactylic hexameter", "pattern" => "-uu -uu -uu -u u-uu --")
      add.call("urn:cts:latinLit:phi0472.phi001.perseus-lat2:30.1", "lat", "Alfene immemor", "pedecerto",
               "meter" => "D", "pattern" => "")
      report = GoldCheck.new(catalog: catalog).run

      assert_equal 5, report.gold_rows
      assert_equal 1, report.skipped_rows, "non-dactylic gold is not this lane's test set"
      latin_dev = report.total(language: "lat", split: :dev)
      assert_equal [2, 2], [latin_dev.lines, latin_dev.agree]
      held = report.total(language: "lat", split: :held_out)
      assert_equal [1, 0, 1], [held.lines, held.agree, held.disagree]
      greek = report.total(language: "grc")
      assert_equal 1, greek.agree
      assert_equal 16, greek.syllables_compared
      assert_equal 16, greek.syllables_agree
      assert_in_delta 0.75, report.total.agreement
    end
  end

  def with_catalog
    catalog = Nabu::Store.connect("sqlite::memory:")
    Nabu::Store.migrate!(catalog)
    src = catalog[:sources].insert(slug: "perseus", name: "P", adapter_class: "X", license_class: "open")
    seq = 0
    add = lambda do |urn, language, text, model, payload|
      seq += 1
      doc = catalog[:documents].insert(source_id: src, urn: "#{urn}-doc", language: language, content_sha256: "x")
      passage = catalog[:passages].insert(document_id: doc, urn: urn, sequence: seq, language: language, text: text,
                                          text_normalized: text, content_sha256: "s#{seq}")
      catalog[:enrichments].insert(passage_id: passage, kind: "meter", model: model, model_version: "t",
                                   payload_json: JSON.generate(payload), at: Time.now)
    end
    yield catalog, add
  ensure
    catalog&.disconnect
  end
end

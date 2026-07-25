# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# Nabu::PedecertoScansions (P44-7) — the METER enrichment producer. Exercised
# against the two REAL trimmed fixtures (Vergil Georgics, hexameter with book
# divisions; Ovid Ibis, elegiac with none), resolving pedecerto citations onto
# seeded Perseus-Latin-shaped held passages. Proves: the parse round-trip, the
# citation→held-passage resolution, the honest matched/unmatched census, the
# language guard, and idempotency/rebuild-equivalence.
class PedecertoScansionsTest < Minitest::Test
  include StoreTestDB

  FIXTURES = Nabu::TestSupport.fixtures("pedecerto")

  # The two fixtures' crosswalk targets + citations (see the fixture files).
  GEOR = "phi0690.phi002" # Vergil, Georgics — VERG-geor
  GEOR_CITATIONS = %w[1.1 1.2 1.3 2.1 2.2].freeze
  IBIS = "phi0959.phi010" # Ovid, Ibis — OV-ibis (no division)
  IBIS_CITATIONS = %w[1 2 3].freeze

  def setup
    @catalog = store_test_db
    @source = Nabu::Store::Source.create(slug: "perseus-latin", name: "Perseus Latin",
                                         adapter_class: "X", license_class: "open")
  end

  def producer = Nabu::PedecertoScansions.new(catalog: @catalog)

  # Seed a held Perseus-Latin work: one document urn:cts:latinLit:<tg.work>.<ed>
  # (default language lat) with a passage per citation, urn "<doc>:<citation>".
  def hold_work(tg_work, citations:, edition: "perseus-lat2", language: "lat")
    doc_urn = "urn:cts:latinLit:#{tg_work}.#{edition}"
    document = Nabu::Store::Document.create(source_id: @source.id, urn: doc_urn,
                                            title: tg_work, language: language,
                                            content_sha256: "x", revision: 1, withdrawn: false)
    citations.each_with_index do |citation, index|
      Nabu::Store::Passage.create(document_id: document.id, urn: "#{doc_urn}:#{citation}",
                                  sequence: index, language: language, text: "verse #{citation}",
                                  text_normalized: "verse #{citation}", content_sha256: "x",
                                  revision: 1, withdrawn: false)
    end
  end

  def meter_rows = @catalog[:enrichments].where(kind: "meter").order(:id).all

  # --- the happy path: matched lines get their scansion --------------------

  def test_matched_lines_attach_the_verbatim_scansion
    hold_work(GEOR, citations: GEOR_CITATIONS)
    result = producer.run("pedecerto", workdir: FIXTURES)

    assert_equal 3, result.files, "all fixture files seen (including the malformed Ausonius)"
    assert_equal 8, result.lines_read, "5 Georgics lines + 3 Ibis lines"
    assert_equal 5, result.matched, "every held Georgics line matched"
    assert_equal 3, result.unmatched, "the unheld Ovid Ibis lines are counted, never silent"
    assert_equal 1, result.mapped_works, "Georgics resolved ≥1 line"
    assert_equal 1, result.unmapped_works, "Ibis: crosswalked but not held"

    rows = meter_rows
    assert_equal 5, rows.size
    row = rows.first
    assert_equal "meter", row[:kind]
    assert_equal "pedecerto", row[:model], "the producer id keys the (kind, model) supersede"
    assert_includes row[:model_version], "pedecerto-scansions/"

    payload = JSON.parse(row[:payload_json])
    assert_equal "H", payload["meter"], "Georgics 1.1 is a hexameter"
    assert_equal "DSDS", payload["pattern"], "the foot pattern verbatim"
    first_word = payload["words"].first
    assert_equal "Quid", first_word["text"]
    assert_equal "1A", first_word["sy"], "the syllable positions ride verbatim"
    assert_equal "CM", first_word["wb"]
  end

  # --- malformed upstream files are censused, never fatal (P44-i3b) --------
  # AVSON-appe.xml is REAL upstream bytes: raw <emph> markup inside a
  # division title attribute — 12 of the artifact's 469 files ship this way
  # (the whole Ausonius set + SEN-epig, verified 2026-07-25 in the owner's
  # landed first sync, which this producer then aborted on). One unreadable
  # file must never abort the other works' re-derivation: it is censused BY
  # NAME on the Result and contributes no lines and no works.
  def test_a_malformed_file_is_censused_and_the_rest_still_ingest
    hold_work(GEOR, citations: GEOR_CITATIONS)
    result = producer.run("pedecerto", workdir: FIXTURES)

    assert_equal ["AVSON-appe.xml"], result.malformed_files
    assert_equal 8, result.lines_read, "the malformed file contributes no lines"
    assert_equal 5, result.matched, "the readable works still ingest fully"
    assert_equal 2, result.mapped_works + result.unmapped_works,
                 "a malformed file is neither mapped nor unmapped — its own census bucket"
  end

  # The scansion attaches to exactly the right passage (citation resolution).
  def test_citation_resolves_to_the_held_passage_urn
    hold_work(GEOR, citations: GEOR_CITATIONS)
    producer.run("pedecerto", workdir: FIXTURES)

    passage = @catalog[:passages].first(urn: "urn:cts:latinLit:phi0690.phi002.perseus-lat2:2.1")
    row = @catalog[:enrichments].first(passage_id: passage[:id], kind: "meter")
    refute_nil row, "Georgics book 2 line 1 (division.line citation) carries its meter"
    assert_equal "H", JSON.parse(row[:payload_json])["meter"]
  end

  # A single-book work (Ovid Ibis, no <division>) cites by bare line number.
  def test_no_division_work_cites_by_bare_line
    hold_work(IBIS, citations: IBIS_CITATIONS)
    result = producer.run("pedecerto", workdir: FIXTURES)

    assert_equal 3, result.matched, "all three Ibis lines resolve on bare-line citation"
    ibis1 = @catalog[:passages].first(urn: "urn:cts:latinLit:phi0959.phi010.perseus-lat2:1")
    refute_nil @catalog[:enrichments].first(passage_id: ibis1[:id], kind: "meter")
    # Ibis is elegiac — line 2 is a pentameter (meter "P"): the meter code is
    # captured verbatim, not assumed hexameter.
    ibis2 = @catalog[:passages].first(urn: "urn:cts:latinLit:phi0959.phi010.perseus-lat2:2")
    payload = JSON.parse(@catalog[:enrichments].first(passage_id: ibis2[:id], kind: "meter")[:payload_json])
    assert_equal "P", payload["meter"]
  end

  # --- the honest census ---------------------------------------------------

  def test_partial_holdings_census_matched_and_unmatched_lines
    hold_work(GEOR, citations: %w[1.1 1.2]) # only two of the five Georgics lines held
    result = producer.run("pedecerto", workdir: FIXTURES)

    assert_equal 2, result.matched
    assert_equal 6, result.unmatched, "3 unheld Georgics lines + 3 Ibis lines"
    assert_equal 2, meter_rows.size
  end

  def test_a_work_with_no_crosswalk_entry_is_all_unmatched
    # Nothing held; the crosswalk maps both fixtures but neither is in catalog.
    result = producer.run("pedecerto", workdir: FIXTURES)

    assert_equal 0, result.matched
    assert_equal 8, result.unmatched, "every line counted even with zero holdings"
    assert_equal 0, result.mapped_works
    assert_equal 2, result.unmapped_works
    assert_empty meter_rows
  end

  # --- the language guard: never attach to an English translation ----------

  def test_english_translation_edition_is_not_matched
    hold_work(GEOR, edition: "perseus-eng2", citations: GEOR_CITATIONS, language: "eng")
    result = producer.run("pedecerto", workdir: FIXTURES)

    assert_equal 0, result.matched, "a shared textgroup.work in English must not carry Latin meter"
    assert_empty meter_rows
  end

  # --- idempotency / rebuild-equivalence -----------------------------------

  def test_rerun_supersedes_and_yields_byte_identical_rows
    hold_work(GEOR, citations: GEOR_CITATIONS)
    producer.run("pedecerto", workdir: FIXTURES)
    first = meter_rows.map { |r| r[:payload_json] }

    second = producer.run("pedecerto", workdir: FIXTURES)
    assert_equal 5, second.superseded, "the prior run's rows are superseded, not duplicated"
    assert_equal 5, meter_rows.size, "still exactly one row per matched line"
    assert_equal first, meter_rows.map { |r| r[:payload_json] }, "re-derivation is byte-identical"
  end

  # The rebuild seam: a fresh catalog + the same canonical corpus re-derives the
  # same enrichment set (db = f(canonical)).
  def test_fresh_catalog_rebuild_equivalence
    hold_work(GEOR, citations: GEOR_CITATIONS)
    producer.run("pedecerto", workdir: FIXTURES)
    original = meter_rows.map { |r| JSON.parse(r[:payload_json]) }

    fresh = store_test_db
    Nabu::Store::Source.create(slug: "perseus-latin", name: "Perseus Latin",
                               adapter_class: "X", license_class: "open")
    src = Nabu::Store::Source.first(slug: "perseus-latin")
    doc_urn = "urn:cts:latinLit:#{GEOR}.perseus-lat2"
    doc = fresh[:documents].insert(source_id: src.id, urn: doc_urn, title: "g", language: "lat",
                                   content_sha256: "x", revision: 1, withdrawn: false)
    GEOR_CITATIONS.each_with_index do |c, i|
      fresh[:passages].insert(document_id: doc, urn: "#{doc_urn}:#{c}", sequence: i, language: "lat",
                              text: "v", text_normalized: "v", content_sha256: "x", revision: 1, withdrawn: false)
    end
    Nabu::PedecertoScansions.new(catalog: fresh).run("pedecerto", workdir: FIXTURES)
    rebuilt = fresh[:enrichments].where(kind: "meter").order(:id).map { |r| JSON.parse(r[:payload_json]) }
    assert_equal original, rebuilt, "the same canonical corpus re-derives the same meter rows"
  end

  # --- the parse-only / absent-corpus no-op --------------------------------

  def test_absent_corpus_is_a_noop_that_supersedes_nothing
    hold_work(GEOR, citations: GEOR_CITATIONS)
    producer.run("pedecerto", workdir: FIXTURES)
    assert_equal 5, meter_rows.size

    Dir.mktmpdir do |empty|
      result = producer.run("pedecerto", workdir: empty)
      assert_equal 0, result.files
      assert_equal 0, result.superseded
    end
    assert_equal 5, meter_rows.size, "a corpus-less run leaves the standing meter layer intact"
  end
end

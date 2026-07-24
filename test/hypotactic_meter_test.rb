# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

# Nabu::HypotacticMeter (P44-6): the Greek METER enrichment producer — the
# SECOND producer on the P44-7 meter seam (kind="meter", model="hypotactic",
# coexisting with pedecerto's Latin rows under the same kind). Reads the
# canonical tsv/ tree and writes ONE enrichments row per line matched (by
# folded grc text, not citation) against a held passage of the mapped work.
# Exercised against the REAL staged TSV (HHAphrodite, retrieved 2026-07-24)
# laid out as the canonical tree stores it, with in-memory grc passages seeded
# to match.
class HypotacticMeterTest < Minitest::Test
  include StoreTestDB

  FIXTURES = Nabu::TestSupport.fixtures("hypotactic")

  # The Homeric Hymn to Aphrodite's held Perseus grc edition (Hymn 5 =
  # tlg0013.tlg005 — see HypotacticMeter::WORK_MAP evidence).
  WORK_URN = "urn:cts:greekLit:tlg0013.tlg005.perseus-grc2"

  # Three real HHAphrodite lines, VERBATIM from the fixture, with their line
  # numbers as the passage citation. L1/L2 are dactylic hexameter; L9 is the
  # one "lyric" line and carries NO caesura (the empty-4th-column case).
  L1 = "μοῦσά μοι ἔννεπε ἔργα πολυχρύσου Ἀφροδίτης,"
  L2 = "Κύπριδος, ἥτε θεοῖσιν ἐπὶ γλυκὺν ἵμερον ὦρσε"
  L9 = "οὐ γὰρ οἱ εὔαδεν ἔργα πολυχρύσου Ἀφροδίτης,"
  L1_URN = "#{WORK_URN}:1".freeze
  L2_URN = "#{WORK_URN}:2".freeze
  L9_URN = "#{WORK_URN}:9".freeze

  def setup
    @catalog = store_test_db
  end

  def producer
    Nabu::HypotacticMeter.new(catalog: @catalog)
  end

  # --- TSV parse on the real fixture -----------------------------------------

  def test_parses_every_line_of_the_real_tsv
    parsed = producer.send(:parse_tsv, File.join(FIXTURES, "tsv", "HHAphrodite.tsv"))
    assert_equal 293, parsed.size, "the whole HHAphrodite scansion, one row per line"
    assert_equal L1, parsed.first[:text]
    assert_equal "-u u -uu -u u--- uu--", parsed.first[:scansion]
    assert_equal "dactylic hexameter", parsed.first[:meter]
    assert_equal "feminine penthemimeral", parsed.first[:caesura]
    # line 9 is the lyric line with an empty caesura column
    assert_equal "lyric", parsed[8][:meter]
    assert_equal "", parsed[8][:caesura], "the 4th column can be empty (verified against bytes)"
  end

  def test_a_malformed_row_raises_parse_error
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "tsv"))
      File.write(File.join(dir, "tsv", "HHAphrodite.tsv"), "onecol\tscansion\tmeter\n")
      error = assert_raises(Nabu::ParseError) { producer.run("hypotactic", workdir: dir) }
      assert_match(/4 TAB columns/, error.message)
    end
  end

  # --- fold-based matching: the HIT ------------------------------------------

  def test_matches_lines_by_folded_text_and_writes_meter_rows
    seed_hymn!(L1_URN => L1, L2_URN => L2, L9_URN => L9)
    result = producer.run("hypotactic", workdir: FIXTURES)

    assert_equal 1, result.files
    assert_equal 293, result.lines_read
    assert_equal 1, result.mapped_works
    assert_equal 0, result.unmapped_works
    assert_equal 3, result.matched, "the three seeded lines matched by text"
    assert_equal 3, @catalog[:enrichments].count
    assert_equal [%w[meter hypotactic]],
                 @catalog[:enrichments].select_map(%i[kind model]).uniq,
                 "the shared meter kind, this producer's own model"

    payload = meter_payload(L1_URN)
    assert_equal "dactylic hexameter", payload["meter"]
    assert_equal "-u u -uu -u u--- uu--", payload["pattern"],
                 "the scansion stored as pattern — the shared show line renders it verbatim"
    assert_equal "feminine penthemimeral", payload["caesura"]
    assert_equal "Hypotactic (D. Chamberlain, hypotactic.com)", payload["credit"],
                 "the Chamberlain reference rides every payload (the mirror README's ask)"
  end

  def test_the_lyric_line_omits_caesura_from_the_payload
    seed_hymn!(L9_URN => L9)
    producer.run("hypotactic", workdir: FIXTURES)

    payload = meter_payload(L9_URN)
    assert_equal "lyric", payload["meter"]
    refute payload.key?("caesura"), "an empty caesura column stores NO key — an honest absence"
  end

  def test_matches_are_robust_to_elision_and_punctuation_spelling
    # Perseus spells elision with U+2019 and a following space and ends the line
    # with a Greek ano teleia; the fold reduces both editions to bare letters.
    perseus_l2 = "Κύπριδος, ἥτε θεοῖσιν ἐπὶ γλυκὺν ἵμερον ὦρσε·"
    seed_hymn!(L2_URN => perseus_l2)
    result = producer.run("hypotactic", workdir: FIXTURES)
    assert_equal 1, result.matched, "the differently-punctuated held line still matches"
    refute_nil meter_payload(L2_URN)
  end

  # --- the MISS + honest census ----------------------------------------------

  def test_unmatched_lines_are_censused_never_forced
    seed_hymn!(L1_URN => L1) # hold only one of the 293 lines
    result = producer.run("hypotactic", workdir: FIXTURES)

    assert_equal 1, result.matched
    assert_equal 292, result.unmatched, "the 292 unheld lines are censused, not guessed"
    assert_equal 1, @catalog[:enrichments].count
  end

  def test_a_mapped_work_with_no_held_passages_censuses_all_lines
    # WORK_MAP knows HHAphrodite → tlg0013.tlg005, but nothing is held: the
    # file counts as an unmapped work (the pedecerto rule — a mapped work is
    # one that resolved at least one line).
    result = producer.run("hypotactic", workdir: FIXTURES)
    assert_equal 0, result.mapped_works
    assert_equal 1, result.unmapped_works
    assert_equal 0, result.matched
    assert_equal 293, result.unmatched
    assert_equal 0, @catalog[:enrichments].count
  end

  def test_an_unmapped_tsv_is_censused_as_an_unmapped_work
    seed_hymn!(L1_URN => L1)
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "tsv"))
      # a file whose stem is NOT in WORK_MAP — two valid 4-column lines
      File.write(File.join(dir, "tsv", "HHDionysus.tsv"),
                 "τάδε\t-u\tdactylic hexameter\t\nκαί\t-u\tlyric\t\n")
      result = producer.run("hypotactic", workdir: dir)
      assert_equal 0, result.mapped_works
      assert_equal 1, result.unmapped_works, "no WORK_MAP entry → an unmapped work, censused"
      assert_equal 2, result.unmatched
      assert_equal 0, @catalog[:enrichments].count, "an unmapped work mints nothing — never guessed"
    end
  end

  # --- the consumer: the shared show meter line ------------------------------

  def test_meter_surfaces_on_the_shared_show_line
    seed_hymn!(L1_URN => L1, L2_URN => L2)
    producer.run("hypotactic", workdir: FIXTURES)

    result = Nabu::Query::Show.new(catalog: @catalog).run(L1_URN)
    meter = result.meter
    refute_nil meter, "a scanned passage carries the meter enrichment on its show card"
    assert_equal "dactylic hexameter", meter.meter
    assert_equal "-u u -uu -u u--- uu--", meter.pattern
    assert_equal "hypotactic", meter.producer, "the shared line names this producer as the model"
  end

  def test_an_unscanned_passage_shows_no_meter
    seed_hymn!(L1_URN => L1, "#{WORK_URN}:999" => "οὐδέν τι τοιοῦτον")
    producer.run("hypotactic", workdir: FIXTURES)

    result = Nabu::Query::Show.new(catalog: @catalog).run("#{WORK_URN}:999")
    assert_nil result.meter, "no scansion, no meter line — byte-identical absence"
  end

  # --- the (kind, model) coexistence with pedecerto --------------------------

  def test_supersede_is_scoped_to_this_model_pedecerto_rows_survive
    seed_hymn!(L1_URN => L1)
    passage_id = @catalog[:passages].where(urn: L1_URN).get(:id)
    # a pedecerto row on the SAME passage under the same kind (the Latin
    # overlap cannot happen live — the lanes split by language — but the
    # supersede scope must still be (kind, model), never kind-wide)
    Nabu::Store::Enrichment.write!(@catalog, passage_id: passage_id, kind: "meter",
                                             model: "pedecerto", model_version: "test",
                                             payload: { "meter" => "H", "pattern" => "DSDS" })
    producer.run("hypotactic", workdir: FIXTURES)
    producer.run("hypotactic", workdir: FIXTURES)

    assert_equal 1, @catalog[:enrichments].where(model: "pedecerto").count,
                 "supersede is scoped to (kind=meter, model=hypotactic) — pedecerto rows untouched"
    assert_equal 1, @catalog[:enrichments].where(model: "hypotactic").count
  end

  # --- idempotency / rebuild-equivalence -------------------------------------

  def test_rerun_supersedes_and_yields_identical_rows
    seed_hymn!(L1_URN => L1, L2_URN => L2, L9_URN => L9)
    first = producer.run("hypotactic", workdir: FIXTURES)
    before = meter_rows
    second = producer.run("hypotactic", workdir: FIXTURES)

    assert_equal first.matched, second.matched
    assert_equal 3, second.superseded, "the prior run's rows are superseded, not duplicated"
    assert_equal before, meter_rows, "a rerun re-derives identical rows"
    assert_equal 3, @catalog[:enrichments].count
  end

  # The rebuild seam: a fresh catalog + the same canonical corpus re-derives
  # the identical meter layer (Rebuild#replay_enrichments drives exactly this).
  def test_fresh_catalog_rebuild_equivalence
    seed_hymn!(L1_URN => L1, L2_URN => L2, L9_URN => L9)
    producer.run("hypotactic", workdir: FIXTURES)
    before = meter_rows

    @catalog = store_test_db
    seed_hymn!(L1_URN => L1, L2_URN => L2, L9_URN => L9)
    producer.run("hypotactic", workdir: FIXTURES)

    assert_equal before, meter_rows, "identical rows re-derived from canonical + the fresh catalog"
  end

  def test_absent_corpus_is_a_noop_that_supersedes_nothing
    seed_hymn!(L1_URN => L1)
    producer.run("hypotactic", workdir: FIXTURES)
    count = @catalog[:enrichments].count
    Dir.mktmpdir do |empty|
      result = producer.run("hypotactic", workdir: empty)
      assert_equal 0, result.matched
      assert_equal 0, result.superseded, "a parse-only sync before the fetch must not wipe the layer"
    end
    assert_equal count, @catalog[:enrichments].count
  end

  private

  # The stored payload for the passage at +urn+, or nil.
  def meter_payload(urn)
    passage_id = @catalog[:passages].where(urn: urn).get(:id)
    row = @catalog[:enrichments].where(passage_id: passage_id, kind: "meter", model: "hypotactic").first
    row && JSON.parse(row[:payload_json])
  end

  # Every hypotactic meter row keyed by passage URN (id-independent, so
  # rebuild-equivalence compares across catalogs whose ids differ).
  def meter_rows
    @catalog[:enrichments]
      .join(:passages, id: Sequel[:enrichments][:passage_id])
      .where(kind: "meter", model: "hypotactic")
      .select_map([Sequel[:passages][:urn], Sequel[:enrichments][:payload_json]])
      .sort
  end

  # A held Perseus grc document with one passage per { urn => verbatim text }.
  def seed_hymn!(passages)
    source = Nabu::Store::Source.create(slug: "perseus", name: "Perseus",
                                        adapter_class: "Nabu::Adapters::Perseus", license_class: "attribution")
    doc = Nabu::Store::Document.create(source_id: source.id, urn: WORK_URN,
                                       title: "Hymn 5 To Aphrodite", language: "grc",
                                       metadata_json: "{}", content_sha256: "x", revision: 1, withdrawn: false)
    passages.each_with_index do |(urn, text), i|
      Nabu::Store::Passage.create(
        document_id: doc.id, urn: urn, sequence: i, language: "grc",
        text: text, text_normalized: Nabu::Normalize.search_form(text, language: "grc"),
        content_sha256: "x", revision: 1, withdrawn: false
      )
    end
  end
end

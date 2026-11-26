# frozen_string_literal: true

require "test_helper"
require "tmpdir"

module Store
  # Nabu::Store::TimelineBuilder::UdSentenceDates: the UD treebanks'
  # sentence-comment dates (birchbark date_created, rnc/ruthenian created
  # and date, egyptian-pc's dynasty dates + place) → passage-grain runs and
  # a document-grain envelope, projected from the catalog after the real
  # fixtures load through the adapter.
  class UdSentenceDatesTest < Minitest::Test
    include StoreTestDB

    FIXTURES = File.expand_path("../../fixtures/ud", __dir__)
    BIRCHBARK = "urn:nabu:ud:old-east-slavic-birchbark:orv_birchbark-ud-test-head50"
    RNC = "urn:nabu:ud:old-east-slavic-rnc:orv_rnc-ud-test-head50"
    EGYPTIAN = "urn:nabu:ud:egyptian-pc:egy_pc-ud-test-head50"
    RUTHENIAN = "urn:nabu:ud:old-east-slavic-ruthenian:orv_ruthenian-ud-test-head50"

    def lane = Nabu::Store::TimelineBuilder::UdSentenceDates

    # The four treebanks these claims live in (a workdir of links to the
    # real fixture dirs — the whole tree would load ~30 more documents).
    TREEBANKS = %w[old-east-slavic-birchbark old-east-slavic-rnc old-east-slavic-ruthenian egyptian-pc].freeze

    def load_fixtures
      @db = store_test_db
      source = Nabu::Store::Source.create(slug: "ud", name: "UD", adapter_class: "T", license_class: "nc")
      Dir.mktmpdir do |workdir|
        TREEBANKS.each { |slug| File.symlink(File.join(FIXTURES, slug), File.join(workdir, slug)) }
        Nabu::Store::Loader.new(db: @db, source: source)
                           .load_from(Nabu::Adapters::UniversalDependencies.new, workdir: workdir, full: true)
      end
    end

    def rows_for(urn)
      id = @db[:documents].where(urn: urn).get(:id)
      @db[:document_axes].where(document_id: id).order(:id).all
    end

    # Every birchbark letter (newdoc) keeps its own date as one run; the
    # document grain spans the earliest and latest letters.
    def test_birchbark_letters_become_runs_under_one_envelope
      load_fixtures
      counts = lane.build(catalog: @db)
      envelope, *runs = rows_for(BIRCHBARK)
      assert_equal [1160, 1430, "range", "1160-1180 … 1420-1430"],
                   envelope.values_at(:not_before, :not_after, :precision, :date_raw)
      assert_nil envelope[:passage_seq_from], "document grain"
      assert_equal 12, runs.size, "one run per dated letter in the head-50 trim"
      first = runs.first
      assert_equal [1360, 1380, "range", "1360-1380", 0], first.values_at(:not_before, :not_after, :precision,
                                                                          :date_raw, :passage_seq_from)
      assert(runs.all? { |row| row[:axis_source] == "ud-sentences" && row[:date_class].nil? })
      assert_operator counts[:documents], :>=, 3
    end

    # rnc's created dates: an ISO day reads at year grain, the day riding raw.
    def test_rnc_creation_dates_read_at_year_grain
      load_fixtures
      lane.build(catalog: @db)
      envelope, *runs = rows_for(RNC)
      assert_equal [1637, 1698], envelope.values_at(:not_before, :not_after)
      assert_equal([[1698, 1698, "1698-05-02"], [1637, 1637, "1637"]],
                   runs.map { |row| row.values_at(:not_before, :not_after, :date_raw) })
    end

    # egyptian-pc's head-50 is all Unas: one claim covering every sentence
    # is the document's claim — the envelope alone, banded by the TLA
    # dynasty node, placed at Saqqara.
    def test_a_single_claim_over_the_whole_document_rows_once
      load_fixtures
      lane.build(catalog: @db)
      rows = rows_for(EGYPTIAN)
      assert_equal 1, rows.size
      assert_equal [-2520, -2364, "dynasty", "5th Dynasty", "Saqqara"],
                   rows.first.values_at(:not_before, :not_after, :precision, :date_raw, :place_name)
    end

    def test_undated_treebanks_mint_nothing
      load_fixtures
      lane.build(catalog: @db)
      assert_empty rows_for(RUTHENIAN), "the head-50 trim carries titles but no date comments"
    end

    def test_refresh_replaces_only_this_lane
      load_fixtures
      other = @db[:documents].where(urn: RUTHENIAN).get(:id)
      @db[:document_axes].insert(document_id: other, not_before: 1, not_after: 2, axis_source: "elsewhere")
      lane.build(catalog: @db)
      before = @db[:document_axes].where(axis_source: "ud-sentences").count
      assert_equal before, lane.refresh_source!(catalog: @db, slug: "ud")
      assert_equal before, @db[:document_axes].where(axis_source: "ud-sentences").count, "idempotent"
      assert_equal 1, @db[:document_axes].where(axis_source: "elsewhere").count
      assert_equal 0, lane.refresh_source!(catalog: @db, slug: "cdli")
    end

    def test_the_full_timeline_rebuild_runs_the_lane
      load_fixtures
      Dir.mktmpdir do |empty_canonical|
        summary = Nabu::Store::TimelineBuilder.rebuild!(catalog: @db, canonical_dir: empty_canonical)
        assert_equal 3, summary.ud_sentences[:documents], "birchbark · rnc · egyptian-pc"
        assert_equal summary.ud_sentences[:documents], summary.total
      end
    end

    # The treebank-level claims (UD v2.19): treebanks whose sentences carry
    # no date comment but whose upstream ids state one, or whose every
    # sentence is one dated, placed object.
    DERIVED = %w[ukrainian-zhelekhivka swedish-modern prakrit-dipi manchu-gdud].freeze
    ZHELEKHIVKA = "urn:nabu:ud:ukrainian-zhelekhivka:uk_zhelekhivka-ud-test-slices"
    SWEDISH = "urn:nabu:ud:swedish-modern:sv_modern-ud-test-head20"
    PRAKRIT = "urn:nabu:ud:prakrit-dipi:pra_dipi-ud-test"
    MANCHU = "urn:nabu:ud:manchu-gdud:mnc_gdud-ud-test"

    def load_derived_fixtures
      @db = store_test_db
      source = Nabu::Store::Source.create(slug: "ud", name: "UD", adapter_class: "T", license_class: "nc")
      Dir.mktmpdir do |workdir|
        DERIVED.each { |slug| File.symlink(File.join(FIXTURES, slug), File.join(workdir, slug)) }
        Nabu::Store::Loader.new(db: @db, source: source)
                           .load_from(Nabu::Adapters::UniversalDependencies.new, workdir: workdir, full: true)
      end
    end

    # Zhelekhivka's newdoc ids end in the article's year — each of the three
    # articles becomes a year-grain run under a 1892…1921 envelope.
    def test_zhelekhivka_articles_date_by_their_newdoc_year
      load_derived_fixtures
      lane.build(catalog: @db)
      envelope, *runs = rows_for(ZHELEKHIVKA)
      assert_equal [1892, 1921, "range"], envelope.values_at(:not_before, :not_after, :precision)
      columns = %i[not_before not_after precision passage_seq_from passage_seq_to]
      assert_equal([[1892, 1892, "year", 0, 4], [1921, 1921, "year", 5, 9], [1917, 1917, "year", 10, 14]],
                   runs.map { |row| row.values_at(*columns) })
      assert_equal "Vischovannja_pro_XX_vik_1892", runs.first[:date_raw], "the raw is upstream's own id"
    end

    # Swedish-Modern's one newdoc names the 1526 New Testament: one claim
    # over the whole document → the envelope alone.
    def test_swedish_modern_dates_by_the_1526_testament
      load_derived_fixtures
      lane.build(catalog: @db)
      rows = rows_for(SWEDISH)
      assert_equal 1, rows.size
      assert_equal [1526, 1526, "year", "NT1526:MRK [Markus]"],
                   rows.first.values_at(:not_before, :not_after, :precision, :date_raw)
    end

    # DIPI: every sentence is an Ashokan edict (README: "under the reign of
    # Ashoka (r. 268--232 BCE)"), its sent_id prefix the inscription's site —
    # one run per site, all inside the reign band.
    def test_ashokan_edicts_place_by_site_inside_the_reign
      load_derived_fixtures
      lane.build(catalog: @db)
      envelope, *runs = rows_for(PRAKRIT)
      assert_equal [-268, -232, "reign"], envelope.values_at(:not_before, :not_after, :precision)
      assert_equal "Girnar; Shahbazgarhi; Kalsi; Mansehra; Jaugada; Dhauli", envelope[:place_name]
      assert_equal([["Girnar", 0, 42], ["Shahbazgarhi", 43, 56], ["Kalsi", 57, 64],
                    ["Mansehra", 65, 72], ["Jaugada", 73, 80], ["Dhauli", 81, 83]],
                   runs.map { |row| row.values_at(:place_name, :passage_seq_from, :passage_seq_to) })
      assert(runs.all? { |row| row.values_at(:not_before, :not_after) == [-268, -232] })
    end

    def test_grammar_examples_stay_undated
      load_derived_fixtures
      lane.build(catalog: @db)
      assert_empty rows_for(MANCHU), "reference-grammar examples state no date or place"
    end

    # The censused claim grammar.
    def test_claim_grammar
      assert_equal [1430, 1450, "range"], lane.claim_bounds("1430-1450")
      assert_equal [1630, 1635, "range"], lane.claim_bounds("1630—1635")
      assert_equal [1652, 1652, "year"], lane.claim_bounds("1652")
      assert_equal [1391, 1600, "range"], lane.claim_bounds("1391.08.25;1500-1600"),
                   "alternatives (an original's day; its copy's century) envelope"
      assert_equal [1400, nil, "range"], lane.claim_bounds("after 1400")
      assert_equal [nil, 1300, "range"], lane.claim_bounds("before 1300")
      assert_equal [-2363, -2233, "dynasty"], lane.claim_bounds("6th Dynasty")
      assert_nil lane.claim_bounds("1450-1400"), "a backwards range is not guessed"
      assert_nil lane.claim_bounds("Middle Kingdom"), "an unruled label mints no bounds"
      assert_nil lane.claim_bounds("1363-1389;sometime"), "every alternative must read"
    end
  end
end

# frozen_string_literal: true

require "test_helper"

module Store
  # Nabu::Store::TimelineBuilder::OpenmghCharterDates: the openMGH
  # Diplomata charters' structured dating lines (not_before/not_after/
  # place annotations, minted at parse by OpenmghCharterDate) become
  # PASSAGE-grain axis rows — one per bounded charter, its issuing place
  # beside it — plus one document-grain envelope per volume (the
  # ChronicleAnnals mold). Seeded by loading the REAL fixture volumes
  # through the adapter: DD Rudolf. (charters 1–3: "878 März 25.",
  # "Saint-Prex (885) August 13.", "Uabre villa 888 Juni 10.") and DD
  # F. II. Band 3 (bare <date/> on every charter).
  class OpenmghCharterDatesTest < Minitest::Test
    include StoreTestDB

    LANE = Nabu::Store::TimelineBuilder::OpenmghCharterDates
    RUDOLFINGER = "urn:nabu:openmgh:bsb00000361"
    FRIDERICI = "urn:nabu:openmgh:bsb00002026"
    EINHARD = "urn:nabu:openmgh:bsb00000728"

    def setup
      @db = store_test_db
      source = Nabu::Store::Source.create(slug: "openmgh", name: "openMGH", adapter_class: "Nabu::Adapters::Openmgh",
                                          license_class: "attribution")
      Nabu::Store::Loader.new(db: @db, source: source)
                         .load_from(Nabu::Adapters::Openmgh.new, workdir: Nabu::TestSupport.fixtures("openmgh"))
    end

    def teardown = @db&.disconnect

    def rows_for(urn)
      document_id = @db[:documents].where(urn: urn).get(:id)
      @db[:document_axes].where(document_id: document_id).order(:id).all
    end

    def test_each_bounded_charter_becomes_one_passage_grain_row_with_its_place
      LANE.build(catalog: @db)
      _envelope, *charters = rows_for(RUDOLFINGER)

      assert_equal([[878, 878, nil, 0], [885, 885, "Saint-Prex", 1], [888, 888, "Uabre villa", 2]],
                   charters.map { |r| [r[:not_before], r[:not_after], r[:place_name], r[:passage_seq_from]] })
      assert(charters.all? { |r| r[:passage_seq_from] == r[:passage_seq_to] }, "one charter = one passage")
      assert_equal ["878 März 25.", "Saint-Prex (885) August 13.", "Uabre villa 888 Juni 10."],
                   charters.map { |r| r[:date_raw] }, "the dating line rides verbatim"
      assert(charters.all? { |r| r[:axis_source] == "openmgh-charters" && r[:precision] == "year" })
      assert(charters.all? { |r| r[:date_class].nil? },
             "the charter's own issue date — the artifact class, never 'edition'")
    end

    def test_the_volume_gains_a_document_grain_envelope_of_its_charters
      LANE.build(catalog: @db)
      envelope = rows_for(RUDOLFINGER).first

      assert_nil envelope[:passage_seq_from], "document grain"
      assert_equal [878, 888], [envelope[:not_before], envelope[:not_after]]
      assert_equal "range", envelope[:precision]
      assert_equal "878 März 25. – Uabre villa 888 Juni 10.", envelope[:date_raw]
      assert_nil envelope[:place_name], "a volume issues from many places — the envelope claims none"
    end

    def test_undated_charters_and_scriptores_volumes_mint_nothing_and_are_counted
      summary = LANE.build(catalog: @db)

      assert_empty rows_for(FRIDERICI), "every DD F. II. charter ships a bare <date/>"
      assert_empty rows_for(EINHARD), "a Scriptores volume carries no charter lines"
      assert_equal({ documents: 1, charters: 3, unbounded: 0, undated: 3 }, summary)
    end

    def test_refresh_source_is_idempotent_and_leaves_other_lanes_alone
      document_id = @db[:documents].where(urn: RUDOLFINGER).get(:id)
      @db[:document_axes].insert(document_id: document_id, not_before: 1977, not_after: 1977,
                                 precision: "year", date_raw: "1977", axis_source: "openmgh",
                                 date_class: "edition")
      2.times { LANE.refresh_source!(catalog: @db, slug: "openmgh") }

      assert_equal 5, rows_for(RUDOLFINGER).size, "the edition row + envelope + 3 charters"
      assert_equal 0, LANE.refresh_source!(catalog: @db, slug: "dta"), "another slug refreshes nothing"
    end

    def test_withdrawn_documents_never_row
      @db[:documents].where(urn: RUDOLFINGER).update(withdrawn: true)
      LANE.build(catalog: @db)
      assert_empty rows_for(RUDOLFINGER)
    end
  end
end

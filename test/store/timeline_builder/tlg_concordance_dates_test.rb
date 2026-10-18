# frozen_string_literal: true

require "test_helper"
require "json"

module Store
  # The TLG concordance lane: glaux and diorisis key their per-work
  # composition dates by the same TLG author.work ids the Perseus/First1K
  # CTS urns carry, so a Greek edition whose own header dates only its
  # print source joins an in-library composition envelope by urn — a
  # derived row, labeled (axis_source "tlg-concordance", date_class
  # "composition", date_raw naming the witness and the key).
  class TlgConcordanceDatesTest < Minitest::Test
    include StoreTestDB

    LANE = Nabu::Store::TimelineBuilder::TlgConcordanceDates

    def setup
      @db = store_test_db
    end

    def seed(slug, urn, metadata: {}, language: "grc")
      source = Nabu::Store::Source.where(slug: slug).first ||
               Nabu::Store::Source.create(slug: slug, name: slug, adapter_class: "T",
                                          license_class: "attribution")
      Nabu::Store::Document.create(
        source_id: source.id, urn: urn, title: urn, language: language,
        content_sha256: urn, revision: 1, withdrawn: false,
        metadata_json: JSON.generate(metadata)
      )
    end

    def rows_for(urn)
      doc = @db[:documents].where(urn: urn).first
      @db[:document_axes].where(document_id: doc.fetch(:id), axis_source: LANE::AXIS_SOURCE).all
    end

    def test_glaux_envelope_dates_the_perseus_edition_by_urn
      seed("glaux", "urn:nabu:glaux:0012-001", metadata: { "start_date" => "-800", "end_date" => "-701" })
      seed("perseus-greek", "urn:cts:greekLit:tlg0012.tlg001.perseus-grc2")
      counts = LANE.build(catalog: @db)
      row = rows_for("urn:cts:greekLit:tlg0012.tlg001.perseus-grc2").fetch(0)
      assert_equal [-800, -701], [row[:not_before], row[:not_after]]
      assert_equal "composition", row[:date_class]
      assert_equal "dated by the glaux concordance (tlg0012.tlg001): -800–-701", row[:date_raw]
      assert_equal 1, counts.fetch("perseus-greek")
    end

    def test_diorisis_answers_when_glaux_holds_no_row_and_glaux_wins_when_it_does
      seed("diorisis", "urn:nabu:diorisis:0001:001", metadata: { "creation_date" => "-245" })
      seed("diorisis", "urn:nabu:diorisis:0012:001", metadata: { "creation_date" => "-750" })
      seed("glaux", "urn:nabu:glaux:0012-001", metadata: { "start_date" => "-800", "end_date" => "-701" })
      seed("first1k-greek", "urn:cts:greekLit:tlg0001.tlg001.1st1K-grc1")
      seed("perseus-greek", "urn:cts:greekLit:tlg0012.tlg001.perseus-grc2")
      LANE.build(catalog: @db)
      apollonius = rows_for("urn:cts:greekLit:tlg0001.tlg001.1st1K-grc1").fetch(0)
      assert_equal [-245, -245], [apollonius[:not_before], apollonius[:not_after]]
      assert_equal "dated by the diorisis concordance (tlg0001.tlg001): -245", apollonius[:date_raw]
      iliad = rows_for("urn:cts:greekLit:tlg0012.tlg001.perseus-grc2")
      assert_equal 1, iliad.size, "one concordance row per edition"
      assert_equal [-800, -701], [iliad[0][:not_before], iliad[0][:not_after]]
    end

    # glaux splits some works into lettered parts (0007-051a / 0007-051b);
    # the parts envelope onto the one TLG work they share.
    def test_lettered_glaux_parts_envelope_onto_the_shared_work
      seed("glaux", "urn:nabu:glaux:0007-051a", metadata: { "start_date" => "100", "end_date" => "120" })
      seed("glaux", "urn:nabu:glaux:0007-051b", metadata: { "start_date" => "110", "end_date" => "125" })
      seed("perseus-greek", "urn:cts:greekLit:tlg0007.tlg051.perseus-grc1")
      LANE.build(catalog: @db)
      row = rows_for("urn:cts:greekLit:tlg0007.tlg051.perseus-grc1").fetch(0)
      assert_equal [100, 125], [row[:not_before], row[:not_after]]
    end

    def test_translations_unmatched_and_non_tlg_editions_mint_nothing
      seed("glaux", "urn:nabu:glaux:0012-001", metadata: { "start_date" => "-800", "end_date" => "-701" })
      seed("perseus-greek", "urn:cts:greekLit:tlg0012.tlg001.perseus-eng4", language: "eng")
      seed("perseus-greek", "urn:cts:greekLit:tlg0099.tlg001.perseus-grc1")
      seed("first1k-greek", "urn:cts:greekLit:tlg2200.tlg00406.opp-grc1")
      assert_equal({ "perseus-greek" => 0, "first1k-greek" => 0 }, LANE.build(catalog: @db))
      assert_equal 0, @db[:document_axes].count
    end

    def test_refresh_replaces_the_lane_for_targets_and_witnesses_only
      seed("glaux", "urn:nabu:glaux:0012-001", metadata: { "start_date" => "-800", "end_date" => "-701" })
      seed("perseus-greek", "urn:cts:greekLit:tlg0012.tlg001.perseus-grc2")
      LANE.build(catalog: @db)
      assert_equal 1, LANE.refresh_source!(catalog: @db, slug: "glaux")
      assert_equal 1, @db[:document_axes].where(axis_source: LANE::AXIS_SOURCE).count, "refresh never duplicates"
      assert_equal 0, LANE.refresh_source!(catalog: @db, slug: "edh")
      assert_equal 1, @db[:document_axes].count
    end

    # The full timeline rebuild runs the lane (and counts it).
    def test_the_timeline_rebuild_runs_the_lane
      seed("glaux", "urn:nabu:glaux:0012-001", metadata: { "start_date" => "-800", "end_date" => "-701" })
      seed("perseus-greek", "urn:cts:greekLit:tlg0012.tlg001.perseus-grc2")
      summary = Nabu::Store::TimelineBuilder.rebuild!(catalog: @db, canonical_dir: Dir.pwd)
      assert_equal 1, summary.tlg_concordance.fetch("perseus-greek")
      assert_equal 1, rows_for("urn:cts:greekLit:tlg0012.tlg001.perseus-grc2").size
    end
  end
end

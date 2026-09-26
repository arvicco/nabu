# frozen_string_literal: true

require "test_helper"

module Store
  # Nabu::Store::TimelineBuilder::KanripoDates (P104-1, №R-70 grade 2):
  # the KR-Catalog attribution-era lane. Each catalog entry's FIRST 人物
  # person block is the primary attribution (the byline order — the
  # author leads, commentators follow); explicit :DATES: mint an
  # author-life envelope, a :DYNASTY: without dates bands through the
  # ruled period_bands.yml sinological rows. Either way the claim is a
  # composition-era ATTRIBUTION, never a typed date — precision "era",
  # the ruling's distinct honestly-labeled class. Texts without a
  # parseable first-person claim are counted undated, never guessed.
  class KanripoDatesTest < Minitest::Test
    include StoreTestDB

    FIXTURES = File.dirname(Nabu::TestSupport.fixtures("kanripo"))

    def setup
      @db = store_test_db
      @source = Nabu::Store::Source.create(
        slug: "kanripo", name: "Kanripo", adapter_class: "T", license_class: "attribution"
      )
    end

    def make_document(kr_id, withdrawn: false)
      urn = "urn:nabu:kanripo:#{kr_id}"
      Nabu::Store::Document.create(
        source_id: @source.id, urn: urn, title: urn, language: "lzh",
        content_sha256: urn, revision: 1, withdrawn: withdrawn
      )
    end

    def timeline_for(kr_id)
      doc = @db[:documents].where(urn: "urn:nabu:kanripo:#{kr_id}").first
      @db[:document_axes].where(document_id: doc.fetch(:id)).first
    end

    def build!
      Nabu::Store::TimelineBuilder::KanripoDates.build(catalog: @db, canonical_dir: FIXTURES)
    end

    def test_first_person_dates_mint_an_author_life_envelope
      make_document("KR2a0001") # 史記 — 司馬遷 (漢, 撰, ca. -145 - ca. -86), commentators after
      counts = build!
      row = timeline_for("KR2a0001")
      assert_equal(-145, row.fetch(:not_before))
      assert_equal(-86, row.fetch(:not_after))
      assert_equal "era", row.fetch(:precision), "an attribution, not a typed date"
      assert_equal "人物 司馬遷 (漢) ca. -145 - ca. -86", row.fetch(:date_raw)
      assert_equal "kanripo", row.fetch(:axis_source)
      assert_equal 1, counts[:documents]
    end

    def test_the_first_person_wins_over_later_commentators
      make_document("KR2a0001")
      build!
      row = timeline_for("KR2a0001")
      assert_operator row.fetch(:not_after), :<, 0,
                      "the 唐/清 commentator blocks never overwrite the Han author's claim"
      assert_equal 1, @db[:document_axes].count, "one claim per text"
    end

    def test_dates_only_person_block_mints_without_a_dynasty
      make_document("KR5c0091") # 道德真經註 — 吳澄, :DATES: 1249 - 1333 (no DYNASTY in the block)
      build!
      row = timeline_for("KR5c0091")
      assert_equal 1249, row.fetch(:not_before)
      assert_equal 1333, row.fetch(:not_after)
      assert_equal "人物 吳澄 1249 - 1333", row.fetch(:date_raw)
    end

    def test_an_entry_own_clean_date_outranks_the_person_ladder
      make_document("KR2g0007") # 杜工部年譜 — :DATE: 1091 beside a 宋 person block
      build!
      row = timeline_for("KR2g0007")
      assert_equal 1091, row.fetch(:not_before)
      assert_equal 1091, row.fetch(:not_after)
      assert_equal "year", row.fetch(:precision), "the catalog's own year is a typed claim"
      assert_equal "DATE 1091", row.fetch(:date_raw)
    end

    def test_floruit_dates_mint_an_attested_activity_envelope
      make_document("KR3g0023") # 青囊奧語 — 楊筠松, :DATES: fl. 874 - 888
      build!
      row = timeline_for("KR3g0023")
      assert_equal 874, row.fetch(:not_before)
      assert_equal 888, row.fetch(:not_after)
      assert_equal "era", row.fetch(:precision)
      assert_equal "人物 楊筠松 (唐) fl. 874 - 888", row.fetch(:date_raw)
    end

    def test_an_era_name_date_mints_nothing
      make_document("KR5a0001") # :DATE: ca. 400 — not a clean year, no person claim
      counts = build!
      assert_nil timeline_for("KR5a0001"), "regnal/approximate DATE strings are never guessed"
      assert_equal 1, counts[:undated]
    end

    # The dynasty-band rung as a pure ladder check: a person block with a
    # ruled seat and no dates bands to the dynasty's own span.
    def test_person_dynasty_bands_when_dates_are_absent
      claim = Nabu::Store::TimelineBuilder::KanripoDates.person_claim(
        { "DYNASTY" => "唐", "NAME" => "張守節" }
      )
      assert_equal 618, claim[:not_before]
      assert_equal 907, claim[:not_after]
      assert_equal "era", claim[:precision]
      assert_equal "人物 張守節 (唐)", claim[:raw]
      assert_nil Nabu::Store::TimelineBuilder::KanripoDates.person_claim(
        { "DYNASTY" => "元 or 明", "NAME" => "x" }
      ), "a compound seat has no ruled band — nothing minted"
    end

    def test_a_person_without_dates_or_dynasty_counts_undated
      make_document("KR1a0170") # 易緯坤靈圖 — the trimmed 鄭玄 block carries no properties
      counts = build!
      assert_nil timeline_for("KR1a0170")
      assert_equal 1, counts[:undated]
    end

    def test_unheld_catalog_entries_and_withdrawn_documents_mint_nothing
      make_document("KR2a0001", withdrawn: true)
      counts = build!
      assert_equal 0, counts[:documents]
      assert_equal 0, @db[:document_axes].count
    end

    def test_absent_catalog_tree_is_the_honest_zero
      make_document("KR2a0001")
      counts = Nabu::Store::TimelineBuilder::KanripoDates.build(
        catalog: @db, canonical_dir: "/nonexistent"
      )
      assert_equal({ documents: 0, undated: 0 }, counts)
    end
  end
end

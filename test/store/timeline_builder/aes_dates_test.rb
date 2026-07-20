# frozen_string_literal: true

require "test_helper"

module Store
  # Nabu::Store::TimelineBuilder::AesDates (P28-0): document dates and findspots
  # from the AES sentence metadata, run against the REAL adapter fixtures
  # (test/fixtures/aes). The corpus dates texts with SIX coarse values only
  # (censused whole, 2026-07-18): "OK & FIP" / "MK & SIP" / "NK" /
  # "TIP - Roman times" / "unknown" / the degenerate "k" (2 sentences) —
  # the four real periods map to conventional Egyptological year envelopes,
  # the rest are counted undated, never guessed. Findspot is one of 8 coarse
  # regions, ridden verbatim as place_name ("unknown" is not a place).
  class AesDatesTest < Minitest::Test
    include StoreTestDB

    FIXTURES_ROOT = File.expand_path("../../fixtures", __dir__)

    TUEB_URN = "urn:nabu:aes:tuebingerstelen:3F5KUVWQG5EPBM7GMQ6ZFVO5OQ"
    ARCH_URN = "urn:nabu:aes:bbawarchive:26BP5JT5RZEDHDDU2R5TMUBD24"
    ARCH_K_URN = "urn:nabu:aes:bbawarchive:IMLY3YQIZFHHNJUGOZXVPOJTGU"

    def setup
      @db = store_test_db
      @source = Nabu::Store::Source.create(
        slug: "aes", name: "AES", adapter_class: "A", license_class: "attribution"
      )
    end

    def seed(urn, language: "egy")
      Nabu::Store::Document.create(
        source_id: @source.id, urn: urn, language: language,
        content_sha256: urn, revision: 1, withdrawn: false
      )
    end

    def build!
      Nabu::Store::TimelineBuilder::AesDates.build(catalog: @db, canonical_dir: FIXTURES_ROOT)
    end

    def test_nk_text_becomes_a_period_envelope_row_with_findspot
      tueb = seed(TUEB_URN)
      outcome = build!
      assert_equal 1, outcome[:documents]
      row = @db[:document_axes].where(document_id: tueb.id).first
      assert_equal(-1550, row[:not_before])
      assert_equal(-1069, row[:not_after])
      assert_equal "period", row[:precision], "a period is an envelope, never a midpoint"
      assert_equal "NK", row[:date_raw], "the corpus's own value, verbatim"
      assert_equal "Upper Egypt (South of Assiut)", row[:place_name]
      assert_equal "aes", row[:axis_source]
    end

    def test_ok_fip_text_maps_the_old_kingdom_envelope
      arch = seed(ARCH_URN)
      build!
      row = @db[:document_axes].where(document_id: arch.id).first
      assert_equal(-2686, row[:not_before])
      assert_equal(-2025, row[:not_after])
      assert_equal "OK & FIP", row[:date_raw]
      assert_equal "Middle Egypt (from Kairo to Assiut)", row[:place_name]
    end

    def test_degenerate_date_with_unknown_findspot_is_counted_undated_never_guessed
      seed(ARCH_K_URN)
      outcome = build!
      assert_equal 0, outcome[:documents]
      assert_equal 1, outcome[:undated], "the real \"k\" text: no period, no place, honestly counted"
      assert_equal 0, @db[:document_axes].count
    end

    def test_de_siblings_never_get_timeline_rows
      seed("#{TUEB_URN}-de", language: "ger")
      outcome = build!
      assert_equal 0, outcome[:documents]
      assert_equal 0, @db[:document_axes].count,
                   "the extractor mints only original text urns — siblings inherit nothing here"
    end

    def test_documents_we_do_not_hold_contribute_nothing
      outcome = build!
      assert_equal 0, outcome[:documents]
      assert_equal 0, outcome[:undated], "undated counts only texts we hold"
      assert_equal 0, @db[:document_axes].count
    end

    # The frozen-minting drift pin: the extractor's urn mint (subcorpus +
    # text id from the JSON) must equal the adapter's discover mint over the
    # shared fixture set, or timeline rows silently stop joining.
    def test_extractor_urn_mint_matches_the_adapter
      adapter_urns = Nabu::Adapters::Aes.new
                                        .discover(File.join(FIXTURES_ROOT, "aes"))
                                        .map(&:id).sort
      extractor_urns = Nabu::Store::TimelineBuilder::AesDates
                       .text_urns(File.join(FIXTURES_ROOT, "aes")).sort
      assert_equal adapter_urns, extractor_urns
    end
  end
end

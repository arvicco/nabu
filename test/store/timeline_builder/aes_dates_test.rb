# frozen_string_literal: true

require "test_helper"
require "tmpdir"

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

    # -- the AED header grain (canonical/aed beside canonical/aes) ---------

    NS6_URN = "urn:nabu:aes:bbawarchive:NS6BAIQRENELJM2A2LDNHIYK6E"
    SAWLIT_URN = "urn:nabu:aes:sawlit:2PD2OKCZCRELBGQD6NCAMOFEWA"

    def build_with_aed!
      Dir.mktmpdir do |dir|
        File.symlink(File.join(FIXTURES_ROOT, "aes"), File.join(dir, "aes"))
        File.symlink(File.join(FIXTURES_ROOT, "aes", "aed"), File.join(dir, "aed"))
        Nabu::Store::TimelineBuilder::AesDates.build(catalog: @db, canonical_dir: dir)
      end
    end

    def test_the_aed_header_supersedes_the_coarse_period_with_reign_bounds_and_site
      arch = seed(ARCH_URN)
      outcome = build_with_aed!
      assert_equal 1, outcome[:documents]
      assert_equal 1, outcome[:aed], "one row took the AED header grain"
      rows = @db[:document_axes].where(document_id: arch.id).all
      assert_equal 1, rows.size, "ONE row per text — the tighter claim replaces the coarse one"
      row = rows.first
      assert_equal [-2421, -2384], [row[:not_before], row[:not_after]]
      assert_equal "reign", row[:precision]
      assert_equal "Djedkare Asosi", row[:date_raw]
      assert_equal "Abusir", row[:place_name], "site grain, not the corpus's coarse region"
      assert_equal "ths:O5AYJCUXENDODEGUIMCH2YWXWM", row[:place_ref]
      assert_equal "aes", row[:axis_source]
      assert_nil row[:date_class], "an object dating (artifact class), not a composition era"
    end

    def test_dynasty_grain_and_joined_labels
      tueb = seed(TUEB_URN)
      sawlit = seed(SAWLIT_URN)
      build_with_aed!
      t = @db[:document_axes].first(document_id: tueb.id)
      assert_equal ["18. Dyn.", "dynasty", -1550, -1293, "Abydos"],
                   [t[:date_raw], t[:precision], t[:not_before], t[:not_after], t[:place_name]]
      s = @db[:document_axes].first(document_id: sawlit.id)
      assert_equal "19. Dyn. – 20. Dyn.", s[:date_raw]
      assert_equal "westliches Ufer", s[:place_name]
    end

    def test_placeholder_header_falls_back_to_the_coarse_lane
      seed(ARCH_K_URN)
      outcome = build_with_aed!
      assert_equal 0, outcome[:documents], "0001 bounds + the find-spot root carry nothing"
      assert_equal 1, outcome[:undated]
    end

    def test_qubbet_el_hawa_text_takes_the_dynasty_envelope
      ns6 = seed(NS6_URN)
      build_with_aed!
      row = @db[:document_axes].first(document_id: ns6.id)
      assert_equal ["6. Dyn.", -2363, -2233], [row[:date_raw], row[:not_before], row[:not_after]]
      assert_equal "Qubbet el Hawa", row[:place_name]
    end

    # Each axis falls back independently: a header with no usable dating
    # keeps the corpus period; a header with no site keeps the region.
    def test_date_and_place_fall_back_to_the_coarse_lane_independently
      header = Nabu::AedTextHeaders::Header
      sentence = { "date" => "NK", "findspot" => "Delta" }
      site_only = header.new(text_id: "X", title: nil, not_before: nil, not_after: nil, date_raw: nil,
                             precision: nil, place_name: "Tanis", place_ref: "ths:SH6XJRRRJNCI5EAMNJSPU5QZ3A")
      row = Nabu::Store::TimelineBuilder::AesDates.extract(sentence, site_only)
      assert_equal ["NK", "period", "Tanis", "ths:SH6XJRRRJNCI5EAMNJSPU5QZ3A"],
                   row.values_at(:date_raw, :precision, :place_name, :place_ref)

      date_only = header.new(text_id: "X", title: nil, not_before: -1279, not_after: -1214,
                             date_raw: "Ramses II.", precision: "reign", place_name: nil, place_ref: nil)
      row = Nabu::Store::TimelineBuilder::AesDates.extract(sentence, date_only)
      assert_equal ["Ramses II.", "reign", "Delta", nil],
                   row.values_at(:date_raw, :precision, :place_name, :place_ref)
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

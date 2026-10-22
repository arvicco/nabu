# frozen_string_literal: true

require "test_helper"
require "support/adapter_conformance"
require "tmpdir"

module Adapters
  # sigla: SigLA, the Linear A sign database (Salgarella & Castellan).
  # Fixture (retrieved 2026-10-22, see test/fixtures/sigla/README.md):
  # database.js with the `signs` payload byte-verbatim and the `data`
  # payload cut to seven inscriptions and re-encoded through the
  # family's byte-faithful writer — ARKH 1a (words + logograms + an
  # unreadable in-word sign), HT 10a (transaction sign, fractions,
  # erasures), HT 22 (composite logograms, a read erasure), HT 79+83
  # (uncertain + unclassified readings), HT 99a (homophone ra₂, Latin-
  # named logograms with a variant), PH Wc 37a (an MM II roundel with
  # its CMS seal) and KH 56 (no sign attestation — the skipped-by-rule
  # specimen); plus document/ARKH 1a/index.html, the rendered-page
  # grain's specimen.
  class SiglaTest < Minitest::Test
    include AdapterConformance

    FIXTURES = Nabu::TestSupport.fixtures("sigla")

    def conformance_adapter = Nabu::Adapters::Sigla.new
    def conformance_workdir = FIXTURES
    def conformance_expected_source_id = "sigla"

    def documents
      @documents ||= conformance_adapter.discover(FIXTURES).map { |ref| conformance_adapter.parse(ref) }
    end

    def doc(id) = documents.find { |d| d.urn == "urn:nabu:sigla:#{id}" } || flunk("#{id} missing")

    def texts(document) = document.passages.map(&:text)

    def citations(document) = document.passages.map { |p| p.urn.delete_prefix("#{document.urn}:") }

    # -- discovery ---------------------------------------------------------

    def test_one_document_per_inscription_with_attestations
      assert_equal(%w[ARKH_1a HT_10a HT_22 HT_79+83 HT_99a PH_Wc_37a],
                   conformance_adapter.discover(FIXTURES).map { |ref| ref.id.delete_prefix("urn:nabu:sigla:") })
    end

    def test_rejected_grains_are_counted_by_rule_never_dropped
      skips = conformance_adapter.discovery_skips(FIXTURES)
      assert_equal 2, skips.skipped_by_rule
      assert_equal 0, skips.unrecognized
      assert_includes skips.notes, "no sign attestation recorded: KH 56"
      assert(skips.notes.any? { |note| note.include?("rendered page grain") && note.include?("ARKH 1a/index.html") })
    end

    def test_a_stray_file_is_unrecognized
      Dir.mktmpdir do |dir|
        FileUtils.cp(File.join(FIXTURES, "database.js"), dir)
        File.write(File.join(dir, "notes.txt"), "x")
        skips = conformance_adapter.discovery_skips(dir)
        assert_equal 1, skips.unrecognized
        assert_includes skips.notes, "non-corpus file: notes.txt"
      end
    end

    def test_an_empty_workdir_discovers_nothing
      Dir.mktmpdir { |dir| assert_empty conformance_adapter.discover(dir).to_a }
    end

    # -- the passage grain -------------------------------------------------

    # The site's own rendering of ARKH 1a (the pinned page): ta pi AB16
    # ki a ra a su mi *118 AB24 a pa [?] mi ki sa ne — words and
    # standalone logograms in attestation order.
    def test_sign_groups_in_attestation_order_cited_by_first_sign
      d = doc("ARKH_1a")
      assert_equal %w[ta-pi AB16 ki a-ra a-su-mi-AB118 AB24 a-pa-? mi-ki-sa-ne], texts(d)
      assert_equal %w[1 3 4 5 7 11 12 15], citations(d)
      assert_equal(%w[word logogram word word word logogram word word], d.passages.map { |p| p.annotations["kind"] })
      assert_equal "lab", d.language
      assert_equal "ARKH 1a", d.title
    end

    def test_sign_level_data_rides_the_signs_annotation
      word = doc("ARKH_1a").passages.find { |p| p.text == "a-pa-?" }
      first, _, unread = word.annotations["signs"]
      assert_equal({ "n" => 12, "role" => "syllabogram", "sign" => "AB08", "value" => "a",
                     "reading" => "a", "bbox" => [363, 907, 135, 198] }, first)
      assert_equal "unreadable", unread["status"]
      assert_nil unread["sign"]
      assert_equal 4, word.annotations["word_index"]
      assert_equal({ "word" => [0, 2] }, word.annotations["flags"], "the word's flag pair rides raw")
    end

    def test_transaction_signs_fractions_and_erasures
      d = doc("HT_10a")
      assert_equal ["ku-ni-su", "sa-ma", "AB03", "da-re", "J", "u-A325-za", "⟦?⟧", "A301",
                    "u-A325-za", "⟦?⟧", "A305-ru", "J", "da-ri-da", "me-za", "⟦?⟧"], texts(d)
      transaction = d.passages[2]
      assert_equal "transaction", transaction.annotations["kind"]
      assert_equal "pa", transaction.annotations["signs"].first["value"], "the value rides even where the name shows"
      erasure = d.passages[6].annotations["signs"].first
      assert_equal "erasure", erasure["role"]
      assert_equal({ "role" => 1, "f4" => 1 }, erasure["flags"], "uninterpreted flags ride raw")
    end

    def test_composites_and_a_read_erasure
      d = doc("HT_22")
      assert_equal %w[A585 A643 ⟦A330⟧], texts(d)
      assert_equal "*120 || L2", d.passages.first.annotations["signs"].first["composition"]
    end

    def test_uncertain_and_unclassified_readings
      d = doc("HT_79+83")
      assert_equal "i?", texts(d).first, "SigLA's own unsure-reading suffix"
      assert_equal false, d.passages.first.annotations["signs"].first["certain"]
      unclassified = d.passages.find { |p| p.text == "tu-?" }.annotations["signs"].last
      assert_equal "unclassified", unclassified["status"]
    end

    def test_homophones_subscript_and_latin_names_carry_variants
      d = doc("HT_99a")
      assert_equal %w[a-du sa-ra₂ A303 FIC VINa H A578], texts(d)
      vin = d.passages.find { |p| p.text == "VINa" }.annotations["signs"].first
      assert_equal({ "sign" => "AB131", "latin" => "VIN", "variant" => "a" }, vin.slice("sign", "latin", "variant"))
    end

    # -- metadata and axes -------------------------------------------------

    def test_metadata_mines_period_place_object_and_dimensions
      meta = doc("ARKH_1a").metadata
      assert_equal "LM I", meta["period"]
      assert_equal({ "ancient" => "Arkhanes" }, meta["place"])
      assert_equal "Tablet", meta["object"]
      assert_equal [6.0, 8.0, 0.95], meta["dimensions_cm"]
      assert_equal 18, meta["sign_count"]
      assert_equal 6, meta["word_count"]
      assert_equal "https://sigla.phis.me/document/ARKH%201a/", meta["permalink"]
      assert_match(%r{\Ahttps://cefael\.efa\.gr/}, meta["corpus_url"])
      assert_equal({ "object" => { "values" => ["Tablet"] }, "site" => { "values" => ["Arkhanes"] } }, meta["facets"])
    end

    def test_a_roundel_carries_its_seal
      meta = doc("PH_Wc_37a").metadata
      assert_equal "MM II", meta["period"]
      assert_equal({ "impressions" => 1, "cms" => "CMS II,5 no. 220", "motif" => "rosette" }, meta["seal"])
      assert_equal "Roundel", meta["object"]
    end

    # The period label bands through the ruled Aegean rows — the same
    # table MetadataDates :period_label reads.
    def test_the_period_labels_band_through_the_ruled_table
      bands = Nabu::PeriodBands.default
      assert_equal [-1600, -1450], bands.lookup(doc("ARKH_1a").metadata["period"])
      assert_equal [-1500, -1450], bands.lookup(doc("HT_10a").metadata["period"])
      assert_equal [-1800, -1700], bands.lookup(doc("PH_Wc_37a").metadata["period"])
    end

    # -- the container -----------------------------------------------------

    def test_a_non_byte_literal_payload_is_refused
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, "database.js"), "var data = '\"\\\\132x\"';\n")
        ref = Nabu::DocumentRef.new(source_id: "sigla", id: "urn:nabu:sigla:X", path: File.join(dir, "database.js"),
                                    metadata: { "id" => "X" })
        assert_raises(Nabu::ParseError) { conformance_adapter.parse(ref) }
      end
    end

    def test_fetch_pins_the_single_database_file
      Dir.mktmpdir do |dir|
        body = File.binread(File.join(FIXTURES, "database.js"))
        stub_request(:get, Nabu::Adapters::Sigla::DATABASE_URL)
          .to_return(status: 200, body: body, headers: { "Last-Modified" => "Fri, 26 Jun 2026 06:18:15 GMT" })
        report = conformance_adapter.fetch(dir)
        assert_equal Digest::SHA256.hexdigest(body), report.sha
        assert_equal 6, conformance_adapter.discover(dir).count
      end
    end
  end
end

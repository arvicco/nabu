# frozen_string_literal: true

require "test_helper"
require "tmpdir"

module Adapters
  # Nabu::Adapters::Bhsa (P30-4) — the ETCBC BHSA over the text-fabric
  # family: second Masoretic witness, first constituency data. Fixtures are
  # byte-verbatim tf/2021 slices (Jona + Ruth whole, Haggai 2:4-5 for the
  # one small cross-verse clause, Daniel 2:4-7 for the Aramaic lane) at
  # upstream commit 4db00e21 — see test/fixtures/bhsa/README.md for the
  # trim recipe.
  class BhsaTest < Minitest::Test
    include AdapterConformance
    include StoreTestDB

    FIXTURES = Nabu::TestSupport.fixtures("bhsa")

    def conformance_adapter
      Nabu::Adapters::Bhsa.new
    end

    def conformance_workdir
      FIXTURES
    end

    def conformance_expected_source_id
      "bhsa"
    end

    # -- registry / manifest --------------------------------------------------

    def test_registry_resolves_bhsa_disabled_until_first_real_sync
      registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
      entry = registry["bhsa"]
      refute_nil entry, "bhsa must be registered in config/sources.yml"
      refute entry.enabled, "enabled: false until the owner-fired first real sync (checklist §6)"
      assert_equal "manual", entry.sync_policy
      assert_equal "bhsa", entry.adapter_class.manifest.id
    end

    def test_manifest_is_nc_with_the_data_license_verbatim
      manifest = Nabu::Adapters::Bhsa.manifest
      assert_equal "nc", manifest.license_class, "CC BY-NC 4.0 data grant → nc, the proiel/gretil posture"
      assert_includes manifest.license, "Attribution-NonCommercial 4.0 International (CC BY-NC 4.0)"
      assert_includes manifest.license, "10.17026/dans-z6y-skyh", "attribution = citing the DANS DOI"
      assert_includes manifest.license, "MIT badge covers code only",
                      "the GitHub MIT badge must never be mistaken for the data license"
      assert_equal "text-fabric", manifest.parser_family
    end

    # -- discover -------------------------------------------------------------

    def test_discover_yields_one_ref_per_book_with_osis_urns
      refs = conformance_adapter.discover(FIXTURES).to_a
      assert_equal %w[
        urn:nabu:bhsa:dan
        urn:nabu:bhsa:hag
        urn:nabu:bhsa:jonah
        urn:nabu:bhsa:ruth
      ], refs.map(&:id), "urns ride the fixed OSIS table — the same stems oshb mints"
      assert_equal(%w[Daniel Haggai Jona Ruth], refs.map { |ref| ref.metadata["book"] })
    end

    def test_discover_yields_nothing_from_a_workdir_without_the_pinned_dataset
      Dir.mktmpdir { |dir| assert_empty conformance_adapter.discover(dir).to_a }
    end

    # -- documents and passages ----------------------------------------------

    def test_documents_carry_the_corpus_verse_grain
      assert_equal 85, parse_urn("urn:nabu:bhsa:ruth").size, "Ruth has 85 Masoretic verses"
      assert_equal 48, parse_urn("urn:nabu:bhsa:jonah").size
      assert_equal 2, parse_urn("urn:nabu:bhsa:hag").size, "the Haggai fixture slice is 2:4-5"
      assert_equal 4, parse_urn("urn:nabu:bhsa:dan").size, "the Daniel fixture slice is 2:4-7"
    end

    def test_ruth_1_1_is_the_ketiv_rendering_byte_verbatim
      passage = passage_at("urn:nabu:bhsa:ruth", "urn:nabu:bhsa:ruth:1.1")
      assert passage.text.start_with?("וַיְהִ֗י"), "text-orig-full-ketiv: {g_word_utf8}{trailer_utf8}"
      assert passage.text.end_with?("׃"), "sof pasuq rides the trailer; trailing whitespace stripped"
      refute passage.text.unicode_normalized?(:nfc),
             "BHSA pointing keeps the Masoretic mark order the NFC exemption protects"
      assert_equal "hbo", passage.language
    end

    def test_tokens_carry_lexeme_gloss_frequency_language_and_morphology
      passage = passage_at("urn:nabu:bhsa:ruth", "urn:nabu:bhsa:ruth:1.8")
      token = passage.annotations["tokens"].find { |t| t.key?("qere") }
      refute_nil token, "Ruth 1:8 carries the fixture's canonical ketiv/qere"
      assert_equal "<FH[", token["lex"], "the ETCBC transliterated lexeme id, verbatim"
      assert_equal "make", token["gloss"], "the per-lexeme English gloss rides the word"
      assert_equal 2629, token["freq_lex"], "freq_lex is an Integer (valueType int)"
      assert_equal "hbo", token["lang"]
      assert_equal "verb", token["sp"]
      assert_equal "qal", token["vs"]
      assert_equal "impf", token["vt"]
    end

    def test_ketiv_qere_agrees_with_the_oshb_shape_and_the_p27_contract
      passage = passage_at("urn:nabu:bhsa:ruth", "urn:nabu:bhsa:ruth:1.8")
      token = passage.annotations["tokens"].find { |t| t.key?("qere") }
      assert_includes passage.text, token["form"], "the stored verse text carries the KETIV"
      qere = token["qere"]
      assert_kind_of Array, qere, "the oshb qere shape: a list of word hashes"
      assert_equal "יַ֣עַשׂ", qere.first["form"]
      refute_includes passage.text, qere.first["form"], "the qere is apparatus, not running text"
      assert_equal "\u05D9\u05B7\u05A3\u05E2\u05B7\u05E9\u05C2\u05D4", token["kq_hybrid"],
                   "the ETCBC hybrid layer rides beside the qere verbatim"
    end

    def test_the_shipped_qere_display_policy_substitutes_bhsa_tokens
      passage = passage_at("urn:nabu:bhsa:ruth", "urn:nabu:bhsa:ruth:1.8")
      config = File.expand_path("../../config/display.yml", __dir__)
      rendered = Nabu::Display.render(
        passage.text, language: "hbo", mode: Nabu::Display.mode("reading"),
                      policies: Nabu::Display.load_policies(config), source: "bhsa",
                      annotations: passage.annotations,
                      source_policies: Nabu::Display.load_source_policies(config)
      )
      assert_includes rendered.applied, "qere",
                      "config/display.yml ships bhsa: qere_display: qere — the P27 contract applies unchanged"
      refute_includes rendered.text, "\u05D9\u05E2\u05E9\u05C2\u05D4",
                      "the ketiv is substituted away under qere display"
    end

    def test_empty_form_slots_keep_their_token_place
      passage = passage_at("urn:nabu:bhsa:jonah", "urn:nabu:bhsa:jonah:1.5")
      elided = passage.annotations["tokens"].reject { |t| t.key?("form") }
      refute_empty elided, "Jona 1:5 carries an elided-article slot (empty g_word_utf8) — real upstream"
      assert elided.all? { |t| t.key?("lex") }, "a surfaceless token still carries its lexeme"
    end

    # -- constituency spans (the P30-4 design note, pinned) -------------------

    def test_clause_and_phrase_spans_ride_passage_annotations
      passage = passage_at("urn:nabu:bhsa:jonah", "urn:nabu:bhsa:jonah:1.1")
      spans = passage.annotations["spans"]
      clauses = spans.select { |s| s["type"] == "clause" }
      assert_equal [[[0, 7]], [[8, 9]]], clauses.map { |s| s["ranges"] },
                   "token-index ranges are passage-relative and inclusive"
      assert_equal(%w[VC VC], clauses.map { |s| s["kind"] })
      phrases = spans.select { |s| s["type"] == "phrase" }
      assert_equal %w[Conj Pred Subj Cmpl Pred], phrases.map { |s| s["function"] }.first(5),
                   "phrase functions ride the spans verbatim"
      assert_equal [[[0, 0]], [[1, 1]], [[2, 3]], [[4, 7]], [[8, 9]]],
                   phrases.map { |s| s["ranges"] }.first(5)
      assert(spans.none? { |s| s["partial"] }, "Jona 1:1's constituents are verse-contained")
      assert_equal spans.map { |s| [s["ranges"].first.first, s["type"] == "clause" ? 0 : 1] },
                   spans.map { |s| [s["ranges"].first.first, s["type"] == "clause" ? 0 : 1] }.sort,
                   "spans order by first token, clause before phrase"
    end

    def test_discontinuous_clause_keeps_both_pieces_as_ranges
      passage = passage_at("urn:nabu:bhsa:jonah", "urn:nabu:bhsa:jonah:1.5")
      clause = passage.annotations["spans"].find { |s| s["node"] == 487_432 }
      assert_equal [[9, 13], [18, 20]], clause["ranges"],
                   "a discontinuous BHSA clause is a LIST of index ranges, never flattened"
      refute clause["partial"], "discontinuous within one verse is not partial"
    end

    def test_cross_verse_clause_is_clipped_per_passage_and_flagged_partial
      document = parse_urn("urn:nabu:bhsa:hag")
      first, second = document.passages
      assert_equal %w[urn:nabu:bhsa:hag:2.4 urn:nabu:bhsa:hag:2.5], [first.urn, second.urn]
      here = first.annotations["spans"].find { |s| s["node"] == 488_879 }
      there = second.annotations["spans"].find { |s| s["node"] == 488_879 }
      assert_equal [[23, 24]], here["ranges"], "Hag 2:4 carries its clipped side of clause 488879"
      assert_equal [[0, 2]], there["ranges"], "Hag 2:5 carries the continuation"
      assert here["partial"], "both sides flag partial"
      assert there["partial"]
      assert_equal here["node"], there["node"], "the shared TF node id joins the pieces"
    end

    # -- languages ------------------------------------------------------------

    def test_language_rides_the_corpus_own_h_a_layer
      daniel = parse_urn("urn:nabu:bhsa:dan")
      assert_equal "arc", daniel.language, "the Dan 2:4-7 slice votes Aramaic by token majority"
      first = daniel.passages.first
      assert_equal "urn:nabu:bhsa:dan:2.4", first.urn
      assert_equal "arc", first.language, "Dan 2:4 flips mid-verse: 11 Aramaic vs 8 Hebrew tokens"
      langs = first.annotations["tokens"].map { |t| t["lang"] }
      assert_equal %w[hbo arc], langs.uniq.sort.reverse, "token grain keeps both languages"
      assert_equal "hbo", parse_urn("urn:nabu:bhsa:ruth").language
    end

    # -- idempotency ----------------------------------------------------------

    def test_double_load_is_idempotent
      catalog = store_test_db
      source = bhsa_source
      first = Nabu::Store::Loader.new(db: catalog, source: source)
                                 .load_from(conformance_adapter, workdir: FIXTURES, full: true)
      assert_equal 4, first.added
      assert_equal 0, first.errored

      counts = [catalog[:documents].count, catalog[:passages].count]
      revisions = catalog[:documents].select_hash(:urn, :revision)
      Nabu::Store::Loader.new(db: catalog, source: source)
                         .load_from(conformance_adapter, workdir: FIXTURES, full: true)
      assert_equal counts, [catalog[:documents].count, catalog[:passages].count]
      assert_equal revisions, catalog[:documents].select_hash(:urn, :revision),
                   "unchanged BHSA books must not fake content revisions"
    end

    private

    def parse_urn(urn)
      adapter = conformance_adapter
      ref = adapter.discover(FIXTURES).find { |r| r.id == urn }
      adapter.parse(ref)
    end

    def passage_at(document_urn, passage_urn)
      passage = parse_urn(document_urn).find { |p| p.urn == passage_urn }
      refute_nil passage, "expected #{passage_urn} in #{document_urn}"
      passage
    end

    def bhsa_source
      Nabu::Store::Source.create(
        slug: "bhsa", name: "BHSA (ETCBC)",
        adapter_class: "Nabu::Adapters::Bhsa", license_class: "nc"
      )
    end
  end
end

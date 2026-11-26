# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"
require "support/adapter_conformance"

module Adapters
  # hrcak-marulana — Colloquia Maruliana full text from Hrčak: one document
  # per OAI article record, one passage per page of each of its PDFs.
  # Fixtures (test/fixtures/hrcak-marulana, laid out as canonical/ holds
  # them): six real records (both OAI formats), five of their PDFs and the
  # RECORDED mutool text layers — four documents (an OCR'd Latin edition,
  # a slot-font article + its English summary PDF, a Unicode book review,
  # a CC BY-NC greeting), one in-copyright record (skipped by rule) and one
  # record whose PDF is not checked in (a fetch hole).
  class HrcakMarulanaTest < Minitest::Test
    include AdapterConformance
    include StoreTestDB

    FIXTURES = Nabu::TestSupport.fixtures("hrcak-marulana")
    KLASS = Nabu::Adapters::HrcakMarulana
    URN = "urn:nabu:hrcak-marulana"

    # The recorded text layers (mutool 1.28 on the cutting box) — the suite
    # never depends on mutool; the guarded live test pins agreement.
    RECORDED = lambda do |path|
      layer = File.join(FIXTURES, "textlayers", "#{File.basename(path, '.pdf')}.txt")
      pages = File.read(layer, encoding: "UTF-8").split("\f", -1)
      pages.pop if pages.last.to_s.strip.empty?
      pages
    end

    def conformance_adapter = KLASS.new(pdf_text: RECORDED, delay: 0)
    def conformance_workdir = FIXTURES
    def conformance_expected_source_id = "hrcak-marulana"

    def documents
      @documents ||= conformance_adapter.discover(FIXTURES).map { |ref| conformance_adapter.parse(ref) }
    end

    def doc(id) = documents.find { |d| d.urn == "#{URN}:#{id}" } || flunk("#{id} missing")

    def test_discovers_licensed_records_whose_pdfs_are_held_in_id_order
      assert_equal %W[#{URN}:8030 #{URN}:9874 #{URN}:23933 #{URN}:277980],
                   conformance_adapter.discover(FIXTURES).map(&:id)
    end

    def test_the_in_copyright_record_is_skipped_by_rule_and_the_fetch_hole_is_unrecognized
      skips = conformance_adapter.discovery_skips(FIXTURES)
      assert_equal 1, skips.skipped_by_rule, "277999 carries rightsstatements.org InC"
      assert_equal 1, skips.unrecognized, "9875's PDF (file 15233) is not held"
      assert(skips.notes.any? { |n| n.include?("record 9875") && n.include?("15233") }, skips.notes.inspect)
      assert(skips.notes.any? { |n| n.include?("in-copyright") && n.include?("277999") }, skips.notes.inspect)
    end

    def test_a_record_without_its_oai_dc_twin_is_unrecognized
      Dir.mktmpdir do |dir|
        FileUtils.cp_r(Dir.glob(File.join(FIXTURES, "*")), dir)
        File.delete(File.join(dir, "records", "23933.oai_dc.xml"))
        adapter = conformance_adapter
        refute_includes adapter.discover(dir).map(&:id), "#{URN}:23933"
        skips = adapter.discovery_skips(dir)
        assert_equal 2, skips.unrecognized
        assert(skips.notes.any? { |n| n.include?("23933") && n.include?("oai_dc") })
      end
    end

    def test_one_passage_per_non_blank_page_of_each_pdf_keyed_by_file_id
      article = doc("8030")
      assert_equal (1..8).map { |n| "#{URN}:8030:f12183:p#{n}" } + ["#{URN}:8030:f12184:p1"],
                   article.passages.map(&:urn)
      assert_equal (1..9).to_a, article.passages.map(&:sequence)
      assert_equal({ "pdf_file" => "12184", "pdf_page" => 1 }, article.passages.last.annotations)
      assert_equal (1..3).map { |n| "#{URN}:9874:f15232:p#{n}" }, doc("9874").passages.map(&:urn)
    end

    def test_each_pdf_claims_the_language_its_record_pairs_with_it
      article = doc("8030")
      assert_equal "hrv", article.language
      assert_equal (%w[hrv] * 8) + %w[eng], article.passages.map(&:language)
      assert_equal "lat", doc("9874").language
      assert(doc("9874").passages.all? { |p| p.language == "lat" })
    end

    def test_languages_listed_beyond_the_pdfs_ride_as_inner_languages
      # The fixture records list exactly one language per PDF; the spill
      # case (386 records: hrv+eng with one PDF) is pinned in
      # hrcak_record_test on a real record.
      refute(documents.any? { |d| d.metadata.key?("inner_languages") })
    end

    def test_the_slot_font_layer_is_repaired_per_pdf_and_named
      article = doc("8030")
      first = article.passages.first.text
      expected = "UTEMELJENOST METAFORIČKOGA ODREĐENJA:\nMARULIĆ flOTAC UMJETNOGA HRVATSKOG PJESNIŠTVA«*"
      assert first.start_with?(expected), first[0, 120]
      refute_match(/[ÊË∆π]/, article.passages.map(&:text).join)
      assert_includes article.passages.last.text, "MARULIĆ"
      assert_equal({ "12183" => "whole", "12184" => "whole" }, article.metadata["legacy_font_repairs"])
    end

    def test_unicode_and_ocr_layers_are_kept_verbatim
      review = doc("23933")
      assert_includes review.passages.first.text, "L™kös István", "upstream's own glyph loss stays"
      refute review.metadata.key?("legacy_font_repairs")
      latin = doc("9874").passages.first.text
      assert latin.start_with?("PRILOG\nVenanti Honori Clementiani Fortunati\nAD FELICEM EPISCOPUM DE PASCHA\n" \
                               "Tempora florigero rutilant distincta sereno"), latin[0, 120]
    end

    def test_legacy_font_detection_and_repair
      legacy = KLASS::LegacyFont
      sample = "MARULI∆ U HRVATSKOJ KNJIÆEVNOJ, πto je ËitajuÊi, ODRE–ENJA, METAFORI»KOGA, str. 63‡66, " \
               "»Globusovu« izdanje, me\u{F8FF}u, PJESNI©TVA"
      assert legacy.legacy?(sample)
      assert_equal "MARULIĆ U HRVATSKOJ KNJIŽEVNOJ, što je čitajući, ODREĐENJA, METAFORIČKOGA, str. 63–66, " \
                   "»Globusovu« izdanje, među, PJESNIŠTVA", legacy.repair(sample)
      refute legacy.legacy?("Marulić, ËÊ∆ — real letters present"), "a real Croatian letter vetoes"
      refute legacy.legacy?("Ê only once and Ë"), "below the signature floor"
      assert_equal "πρόσωπον", legacy.repair("πρόσωπον"), "π inside a Greek word stays"
      assert_equal "Kačić; odriši", legacy.repair("KaËiÊ; odriπi")
    end

    # A MIXED PDF (vol. 14, file 4696, page 1 — the recorded layer): a
    # Unicode body (Marulića, značajan) under a slot-font heading and
    # footnotes (MARULI∆EVA, MargetiÊ, Knjiænica). Only the in-word slots
    # are repaired; æ © » stay verbatim.
    def test_a_mixed_pdf_gets_only_the_in_word_repair
      legacy = KLASS::LegacyFont
      page = File.read(File.join(FIXTURES, "textlayers", "4696-p1.txt"), encoding: "UTF-8").split("\f").first
      refute legacy.legacy?(page), "real Croatian letters veto the whole-table repair"
      fixed, mode = legacy.repair_pdf([page])
      assert_equal "in-word", mode
      text = fixed.first
      assert text.start_with?("MARULIĆEVA OPORUKA"), text[0, 40]
      assert_includes text, "Lujo Margetić\n821.163.42-05 Marulić, M."
      assert_includes text, "flO oporuci Marka Marulića  kao i o najstarijim"
      assert_includes text, "flKnjiænica Marka Marulića«", "æ stays verbatim in a mixed PDF"
      assert_includes text, "© e g v i Ê", "a letterspaced slot (no Latin neighbour) stays"
      assert_includes text, "Oporuka Marka Marulića kao značajan dokument", "the Unicode body is untouched"
      clean = RECORDED.call("37682.pdf")
      assert_equal [clean, nil], legacy.repair_pdf(clean), "a clean Unicode PDF is untouched and unnamed"
    end

    def test_record_metadata_is_mined
      meta = doc("23933").metadata
      assert_equal "23933", meta["hrcak_id"]
      assert_equal "https://hrcak.srce.hr/23933", meta["landing_url"]
      assert_equal ["17", "17", "2008-04-22", "book review"],
                   meta.values_at("volume", "issue", "issued", "resource_type")
      assert_equal ["Tomasović, Mirko"], meta["authors"]
      assert_equal [{ "name" => "Tomasović, Mirko",
                      "affiliations" => ["Filozofski fakultet Sveučilišta u Zagrebu, Zagreb, Hrvatska"] }],
                   meta["creators"]
      assert_equal [{ "file_id" => "37682", "url" => "https://hrcak.srce.hr/file/37682", "language" => "hrv",
                      "journal_pages" => "337–338" }], meta["pdfs"]
      assert_equal({ "genre" => { "value" => "book review" } }, meta["facets"])
      assert_equal 2008, meta.dig("date", "not_before")
      assert_equal "edition", meta.dig("date", "class")
      assert_match(/\AMarko Marulić, Zsuzsána/, doc("23933").title)
    end

    def test_titles_and_abstracts_in_every_language
      meta = doc("8030").metadata
      assert_equal [{ "lang" => "hrv",
                      "text" => "Utemeljenost metaforičkoga određenja: Marulić «otac umjetnoga hrvatskog pjesništva»" },
                    { "lang" => "eng", "text" => "On the Making of a Metaphor: Father of FCroatian Art of Poetry" }],
                   meta["titles"], "upstream's own typo (FCroatian) kept"
      assert_equal %w[hrv eng], meta["languages"]
      assert_equal(%w[12183 12184], meta["pdfs"].map { |p| p["file_id"] })
    end

    def test_the_journal_grant_and_the_record_licence_conditions
      assert_nil doc("8030").license_override, "no licence condition: the journal's CC BY 4.0"
      assert_includes doc("8030").metadata["rights"], "Creative Commons Attribution 4.0 International License"
      greeting = doc("277980")
      assert_equal "nc", greeting.license_override
      assert_equal "Attribution-NonCommercial 4.0 International (CC BY-NC 4.0)", greeting.metadata["rights"]
      assert_equal "http://creativecommons.org/licenses/by-nc/4.0/", greeting.metadata["license_uri"]
    end

    def test_manifest_is_attribution_and_quotes_the_journal_statement
      manifest = KLASS.manifest
      assert_equal "attribution", manifest.license_class
      assert_includes manifest.license, "Authors retain unrestricted copyright to their published works."
      assert_equal "hrcak-oai-pdf", manifest.parser_family
    end

    def test_registry_row_is_registered_wired_and_manual
      registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources", __dir__))
      entry = registry["hrcak-marulana"]
      refute_nil entry
      assert entry.wired, "wired: true — first sync verified 2026-11-25 (644 docs / 9,757 passages)"
      assert_equal "manual", entry.sync_policy
    end

    def test_an_unreadable_pdf_is_a_parse_error
      broken = KLASS.new(pdf_text: ->(_path) { raise Nabu::PdfText::Error, "mutool exploded" }, delay: 0)
      ref = broken.discover(FIXTURES).first
      assert_raises(Nabu::ParseError) { broken.parse(ref) }
    end

    def test_fetch_failure_is_a_fetch_error
      stub_request(:get, Nabu::Adapters::HrcakMarulanaFetch.list_url("oai_openaire")).to_return(status: 500)
      Dir.mktmpdir do |dir|
        error = assert_raises(Nabu::FetchError) { KLASS.new(delay: 0).fetch(File.join(dir, "hrcak-marulana")) }
        assert_includes error.message, "HTTP 500"
      end
    end

    def test_load_twice_is_idempotent
      db = store_test_db
      source = Nabu::Store::Source.create(slug: "hrcak-marulana", name: "Colloquia Maruliana",
                                          adapter_class: KLASS.name, license_class: "attribution")
      first = Nabu::Store::Loader.new(db: db, source: source).load_from(conformance_adapter, workdir: FIXTURES)
      assert_equal 4, first.added
      passages = db[:passages].count
      assert_equal 9 + 3 + 2 + 2, passages
      second = Nabu::Store::Loader.new(db: db, source: source).load_from(conformance_adapter, workdir: FIXTURES)
      assert_equal 4, second.skipped
      assert_equal passages, db[:passages].count
    ensure
      db&.disconnect
    end

    # -- live mutool (present on the owner's box, absent in CI) ------------

    def test_real_mutool_extraction_agrees_with_the_recorded_layers
      skip "mutool not on PATH — the recorded-extraction tests carry the suite" unless mutool_available?

      Dir.glob(File.join(FIXTURES, "files", "*.pdf")).each do |pdf|
        live = Nabu::PdfText.pages(pdf)
        assert_equal RECORDED.call(pdf).map { |p| p.split("\n").map(&:rstrip) },
                     live.map { |p| p.split("\n").map(&:rstrip) },
                     "#{File.basename(pdf)}: the checked-in layer must stay what mutool extracts"
      end
    end

    private

    def mutool_available?
      ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).any? do |dir|
        File.executable?(File.join(dir, "mutool"))
      end
    end
  end
end

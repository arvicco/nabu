# frozen_string_literal: true

require "test_helper"
require "support/adapter_conformance"

module Adapters
  # ms-wikisource (P120-3): the Jawi manuscript cone. Fixture envelopes are
  # real api.php captures (2026-10-12): Hikayat Aceh (Leiden Or. 1954 —
  # one level-1 page of 142 transcluded, header year "abad ke-17"),
  # Hikayat Pelanduk Jenaka (Or. 1932 — Index Year 1718, mixed levels),
  # Syair Perahu (MSS Malay A2 — Rencong + Latin transliteration), and the
  # WM ID 010 0014 tafsir (root year=1949 → tainted; a subpage → the
  # series-wide Syakur exclusion).
  class MsWikisourceTest < Minitest::Test
    include AdapterConformance
    include StoreTestDB

    FIXTURES = Nabu::TestSupport.fixtures("ms-wikisource")

    def conformance_adapter = Nabu::Adapters::MsWikisource.new
    def conformance_workdir = FIXTURES
    def conformance_expected_source_id = "ms-wikisource"

    def documents
      @documents ||= conformance_adapter.discover(FIXTURES).map { |ref| conformance_adapter.parse(ref) }
    end

    def doc(pageid) = documents.find { |d| d.urn.end_with?(":#{pageid}") } || flunk("#{pageid} missing")

    def envelope(pageid) = JSON.parse(File.read(File.join(FIXTURES, "pages", "#{pageid}.json")))

    def test_discovery_census
      assert_equal %w[urn:nabu:ms-wikisource:1928 urn:nabu:ms-wikisource:4196 urn:nabu:ms-wikisource:6478],
                   conformance_adapter.discover(FIXTURES).map(&:id).sort
      notes = conformance_adapter.discovery_skips(FIXTURES).notes
      assert(notes.any? { |note| note.start_with?("1 page(s) excluded by EDITION_TAINT_POST_1930") })
      assert(notes.any? { |note| note.start_with?("1 page(s) transcluding a censused excluded Index") })
    end

    def test_a_post_1930_header_year_taints_and_shelfmarks_never_do
      assert_equal :edition_taint, conformance_adapter.page_class(envelope(6916)), "the 1949 tafsir root"
      aceh = envelope(1928)
      assert_equal [1700], conformance_adapter.envelope_edition_years(aceh),
                   "Or. 1954 in the Index name is a shelfmark, never a year"
      assert_equal :excluded_index, conformance_adapter.page_class(envelope(6918))
    end

    def test_the_ratchet_records_level_one_text
      aceh = doc(1928)
      assert_equal "msa-Arab", aceh.language
      assert_equal({ "levels" => { "1" => 2, "missing" => 140 }, "lowest_text_level" => 1 }, aceh.metadata["proofread"])
      assert_equal 1, aceh.passages.size
      assert aceh.passages.first.text.start_with?("اين حكايت راج آچه")
      refute_match(/Laman:/, aceh.passages.first.text, "missing-page placeholders never leak")
    end

    def test_the_manuscript_date_reads_centuries_years_and_the_index_fallback
      assert_equal({ "not_before" => 1601, "not_after" => 1700, "raw" => "year: abad ke-17 (header)" },
                   doc(1928).metadata["date"])
      assert_equal [1718, 1718], doc(4196).metadata["date"].values_at("not_before", "not_after")
      adapter = conformance_adapter
      assert_equal [1778, 1804], adapter.manuscript_date("1778–1804")
      assert_nil adapter.manuscript_date("1344 H"), "a Hijri year is never converted by guess"
      assert_equal :structured, Nabu::Store::TimelineBuilder::MetadataDates::SHAPES["ms-wikisource"]
    end

    def test_script_is_measured_per_page
      assert_equal "Arab", doc(4196).metadata["script"]
      perahu = doc(6478)
      assert_equal "mixed: Latn+Rjng", perahu.metadata["script"], "Rencong lines beside their transliteration"
      assert_equal "msa", perahu.language
      assert_equal "ms", perahu.metadata["index_language"]
      assert_equal({ "author" => "Hamzah Fansuri", "year" => "1700" }, perahu.metadata["header"])
    end

    def test_an_uncensused_index_language_quarantines
      adapter = conformance_adapter
      foreign = envelope(4196)
      foreign["indexes"].first["fields"]["Language"] = "jv"
      Dir.mktmpdir do |dir|
        FileUtils.mkdir_p(File.join(dir, "pages"))
        File.write(File.join(dir, "pages", "4196.json"), JSON.generate(foreign))
        error = assert_raises(Nabu::ParseError) { adapter.parse(adapter.discover(dir).first) }
        assert_match(/not censused/, error.message)
      end
    end

    def test_double_load_is_idempotent
      catalog = store_test_db
      source = Nabu::Store::Source.create(slug: "ms-wikisource", name: "Malay Wikisource",
                                          adapter_class: "Nabu::Adapters::MsWikisource", license_class: "attribution")
      load = -> { Nabu::Store::Loader.new(db: catalog, source: source).load_from(conformance_adapter, workdir: FIXTURES, full: true) }
      assert_equal 3, load.call.added
      counts = [catalog[:documents].count, catalog[:passages].count]
      revisions = catalog[:documents].select_hash(:urn, :revision)
      load.call
      assert_equal counts, [catalog[:documents].count, catalog[:passages].count]
      assert_equal revisions, catalog[:documents].select_hash(:urn, :revision)
    end
  end
end

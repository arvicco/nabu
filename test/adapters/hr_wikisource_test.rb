# frozen_string_literal: true

require "json"
require "tmpdir"
require "test_helper"
require "support/adapter_conformance"
require "support/store_test_db"

module Adapters
  # hr-wikisource (P116-2): the Croatian premodern century cone. Fixture
  # envelopes are real api.php captures (2026-10-10) — see the README.
  class HrWikisourceTest < Minitest::Test
    include AdapterConformance
    include StoreTestDB

    FIXTURES = Nabu::TestSupport.fixtures("hr-wikisource")
    API = "https://hr.wikisource.org/w/api.php"

    def conformance_adapter = Nabu::Adapters::HrWikisource.new
    def conformance_workdir = FIXTURES
    def conformance_expected_source_id = "hr-wikisource"

    def documents
      @documents ||= conformance_adapter.discover(FIXTURES).map { |ref| conformance_adapter.parse(ref) }
    end

    def doc(pageid) = documents.find { |d| d.urn == "urn:nabu:hr-wikisource:#{pageid}" } || flunk("#{pageid} missing")

    def test_judita_is_croatian_verse_banded_to_the_sixteenth_century
      d = doc(5889)
      assert_equal "hrv", d.language
      assert_equal "S tom vojsko(m) prejako(m) Oloferne greduć,", d.passages.first.text
      assert_equal "Marko Marulić", d.metadata["author"]
      band = d.metadata["era_band"]
      assert_equal [1501, 1600, "Hrvatsko 16. stoljeće"], [band["not_before"], band["not_after"], band["raw"]]
    end

    def test_two_century_author_spans_both_bands
      band = doc(12_823).metadata["era_band"]
      assert_equal [1501, 1700], [band["not_before"], band["not_after"]],
                   "Bunić Vučić is filed under 16. AND 17. stoljeće — the honest envelope spans both"
      assert_equal ["Hrvatsko 16. stoljeće", "Hrvatsko 17. stoljeće"], doc(12_823).metadata["eras"]
    end

    def test_medieval_charter_takes_the_conventional_band
      d = doc(13_006)
      assert d.passages.first.text.start_with?("V jime Otca i Sina i Svetago Duha!")
      assert_equal [1000, 1500], d.metadata["era_band"].values_at("not_before", "not_after")
      assert_match(/hrvatskom ćirilicom/, d.metadata["notes"], "the header's bilješke ride as notes")
    end

    def test_prose_letter_and_drama_shapes
      assert_equal "prose", doc(16_190).metadata["grain"]
      assert_equal "Groff Zrini Petar", doc(16_190).passages.last.text,
                   "a trailing centered line is the letter's signature — text, never a heading"
      drama = doc(11_930)
      assert_equal "VLAHO, MIHO, DŽIVO PEŠICA", drama.passages.first.annotations["section"]
      assert_equal "Sta largo, ne srti, er te sad štropijah!", drama.passages[1].text
    end

    def test_translator_header_skips_by_rule
      adapter = conformance_adapter
      envelope = JSON.parse(File.read(File.join(FIXTURES, "pages", "16190.json")))
      translated = envelope.merge("wikitext" => envelope["wikitext"].sub("| prevoditelj = ", "| prevoditelj = N.N."))
      assert_match(/translation/, adapter.send(:compute_skip_reason, translated))
    end

    def test_fetch_walks_the_cone_and_writes_category_bearing_envelopes
      stub_request(:get, /#{Regexp.escape(API)}.*list=categorymembers/).to_return do |request|
        title = URI.decode_www_form(URI(request.uri.to_s).query).to_h.fetch("cmtitle")
        members = title == "Kategorija:Hrvatsko 16. stoljeće" ? [{ "ns" => 0, "title" => "Judita/Libro drugo" }] : []
        { body: JSON.generate("query" => { "categorymembers" => members }) }
      end
      page = JSON.parse(File.read(File.join(FIXTURES, "pages", "5889.json")))
      stub_request(:get, /#{Regexp.escape(API)}.*prop=revisions/).to_return(
        { body: JSON.generate("continue" => { "clcontinue" => "5889|X", "continue" => "||" },
                              "query" => { "pages" => { "5889" => {
                                "pageid" => 5889, "ns" => 0, "title" => "Judita/Libro drugo",
                                "revisions" => [{ "revid" => page["revid"], "timestamp" => page["timestamp"],
                                                  "slots" => { "main" => { "*" => page["wikitext"] } } }],
                                "categories" => [{ "title" => "Kategorija:Judita" }]
                              } } }) },
        { body: JSON.generate("query" => { "pages" => { "5889" => {
                                "pageid" => 5889, "ns" => 0, "title" => "Judita/Libro drugo",
                                "categories" => [{ "title" => "Kategorija:Hrvatska poezija" }]
                              } } }) }
      )
      Dir.mktmpdir do |workdir|
        report = Nabu::Adapters::HrWikisource.new(delay: 0).fetch(workdir)
        envelope = JSON.parse(File.read(File.join(workdir, "pages", "5889.json")))
        assert_equal ["Hrvatsko 16. stoljeće"], envelope["cone"]
        assert_equal ["Kategorija:Hrvatska poezija", "Kategorija:Judita"], envelope["categories"],
                     "category lists merge across the clcontinue continuation"
        assert_equal page["wikitext"], envelope["wikitext"]
        assert_match(/\A\h{64}\z/, report.sha)
      end
    end

    def test_double_load_is_idempotent
      catalog = store_test_db
      source = Nabu::Store::Source.create(slug: "hr-wikisource", name: "hr", license_class: "attribution",
                                          adapter_class: "Nabu::Adapters::HrWikisource")
      first = Nabu::Store::Loader.new(db: catalog, source: source)
                                 .load_from(conformance_adapter, workdir: FIXTURES, full: true)
      assert_equal 5, first.added
      counts = [catalog[:documents].count, catalog[:passages].count]
      revisions = catalog[:documents].select_hash(:urn, :revision)
      Nabu::Store::Loader.new(db: catalog, source: source)
                         .load_from(conformance_adapter, workdir: FIXTURES, full: true)
      assert_equal counts, [catalog[:documents].count, catalog[:passages].count]
      assert_equal revisions, catalog[:documents].select_hash(:urn, :revision)
    end
  end
end

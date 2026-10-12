# frozen_string_literal: true

require "test_helper"
require "support/adapter_conformance"
require "tmpdir"

module Adapters
  # uk-wikisource (P116-3, under the base-edition rule): the chronicles of
  # Категорія:Літописи. Fixture envelopes are real api.php captures
  # (2026-10-10): Сборникъ лѣтописей/Добромильская лѣтопись (the 1888
  # Kyiv edition, a ProofreadPage transclusion — ADMITTED), Львівський
  # літопис (a {{версії}} shell), its 1971 edition page (Бевзо — the
  # EDITION_TAINT_POST_1930 case), Про князя Олега (a modern retelling —
  # a censused exclusion).
  class UkWikisourceTest < Minitest::Test
    include AdapterConformance
    include StoreTestDB

    FIXTURES = Nabu::TestSupport.fixtures("uk-wikisource")
    API = "https://uk.wikisource.org/w/api.php"

    def conformance_adapter = Nabu::Adapters::UkWikisource.new
    def conformance_workdir = FIXTURES
    def conformance_expected_source_id = "uk-wikisource"

    def documents
      @documents ||= conformance_adapter.discover(FIXTURES).map { |ref| conformance_adapter.parse(ref) }
    end

    def envelope(pageid) = JSON.parse(File.read(File.join(FIXTURES, "pages", "#{pageid}.json")))

    def test_discovery_census
      assert_equal %w[urn:nabu:uk-wikisource:40746], conformance_adapter.discover(FIXTURES).map(&:id)
      skips = conformance_adapter.discovery_skips(FIXTURES)
      assert_equal 3, skips.skipped_by_rule
      assert_equal :versions, conformance_adapter.page_class(envelope(48_952))
      assert_equal :edition_taint, conformance_adapter.page_class(envelope(50_958))
      assert_equal :excluded, conformance_adapter.page_class(envelope(9072))
    end

    def test_the_1888_chronicle_parses_as_orv_with_its_section_year
      chronicle = documents.first
      assert_equal "orv", chronicle.language
      assert(chronicle.passages.any? { |p| p.text.start_with?("Азъ іерей Семеонъ Коростенский") })
      refute(chronicle.passages.any? { |p| p.text == "1648 — 1700." }, "a number-only heading is not text")
      assert_equal "рік: 1888 · index: Сборник летописей, относящихся к истории Южной и Западной Руси 1888.pdf",
                   chronicle.metadata["base_edition"]
      assert_equal({ "not_before" => 1700, "not_after" => 1700, "raw" => "рік_секції: 1700" },
                   chronicle.metadata["era_band"])
    end

    def test_the_1971_edition_page_taints
      page = envelope(50_958)
      assert_includes conformance_adapter.edition_years(page["title"], page["wikitext"]), 1971
    end

    def test_double_load_is_idempotent
      catalog = store_test_db
      source = Nabu::Store::Source.create(slug: "uk-wikisource", name: "Ukrainian Wikisource",
                                          adapter_class: "Nabu::Adapters::UkWikisource", license_class: "attribution")
      load = -> { Nabu::Store::Loader.new(db: catalog, source: source).load_from(conformance_adapter, workdir: FIXTURES, full: true) }
      assert_equal 1, load.call.added
      counts = [catalog[:documents].count, catalog[:passages].count]
      revisions = catalog[:documents].select_hash(:urn, :revision)
      load.call
      assert_equal counts, [catalog[:documents].count, catalog[:passages].count]
      assert_equal revisions, catalog[:documents].select_hash(:urn, :revision)
    end

    # -- fetch (the family choreography, WebMock) ----------------------------

    def api_page(pageid, title, wikitext)
      { "pageid" => pageid, "ns" => 0, "title" => title,
        "revisions" => [{ "revid" => pageid * 10, "timestamp" => "2026-10-10T00:00:00Z",
                          "slots" => { "main" => { "*" => wikitext } } }] }
    end

    def stub_api(pages)
      stub_request(:get, API).with(query: hash_including("list" => "categorymembers"))
                             .to_return(status: 200, body: JSON.generate(
                               "query" => { "categorymembers" => [
                                 { "ns" => 0, "title" => "Хмільницький літопис" },
                                 { "ns" => 0, "title" => "Про князя Олега" }
                               ] }
                             ))
      stub_request(:get, API).with(query: hash_including("prop" => "revisions")).to_return do |request|
        titles = URI.decode_www_form(request.uri.query).to_h.fetch("titles").split("|")
        found = pages.select { |page| titles.include?(page["title"]) }
        { status: 200, body: JSON.generate("query" => { "pages" => found.to_h { |p| [p["pageid"].to_s, p] } }) }
      end
      rendering = '<div class="mw-parser-output"><p>Лѣта 1648.</p></div>'
      stub_request(:get, API).with(query: hash_including("action" => "parse"))
                             .to_return(status: 200, body: JSON.generate("parse" => { "text" => { "*" => rendering } }))
    end

    def test_fetch_follows_versions_shells_and_renders_only_admitted_pages
      stub_api([
                 api_page(1, "Хмільницький літопис",
                          "{{версії\n| автор =\n}}\n* [[Лѣтопись Самовидца/Хмельницкая лѣтопись|Хмельницкая]]\n" \
                          "== Див. також ==\n* [[Автор:Хтось]] [[Інша сторінка]]"),
                 api_page(2, "Про князя Олега", "{{Про_текст\n| Джерело = x\n}}\nІ жив Олег"),
                 api_page(3, "Лѣтопись Самовидца/Хмельницкая лѣтопись",
                          "{{заголовок\n | рік = 1878\n}}\n<pages index=\"Летопись 1878.pdf\" from=1 to=2 />")
               ])
      Dir.mktmpdir do |dir|
        report = Nabu::Adapters::UkWikisource.new(delay: 0).fetch(dir)
        assert_match(/\A\h{64}\z/, report.sha)
        pages = Dir.glob(File.join(dir, "pages", "*.json")).map { |path| JSON.parse(File.read(path)) }
        assert_equal ["Лѣтопись Самовидца/Хмельницкая лѣтопись", "Про князя Олега", "Хмільницький літопис"],
                     pages.map { |page| page["title"] }.sort,
                     "the shell's edition link (before its first heading) joined the cone; the see-also did not"
        followed = pages.find { |page| page["pageid"] == 3 }
        assert_equal ["versions:Хмільницький літопис"], followed["cone"]
        rendered = pages.select { |page| page["html"] }.map { |page| page["title"] }
        assert_equal ["Лѣтопись Самовидца/Хмельницкая лѣтопись"], rendered,
                     "only the admitted page costs a parse call"
        assert_requested :get, API, query: hash_including("action" => "parse", "oldid" => "30"), times: 1
        assert File.exist?(File.join(dir, ".uk-wikisource-fetch.json"))
        refs = Nabu::Adapters::UkWikisource.new.discover(dir).to_a
        assert_equal ["urn:nabu:uk-wikisource:3"], refs.map(&:id)
      end
    end

    def test_fetch_failure_is_a_fetch_error
      stub_request(:get, /uk\.wikisource\.org/).to_return(status: 503)
      Dir.mktmpdir do |dir|
        assert_raises(Nabu::FetchError) { Nabu::Adapters::UkWikisource.new(delay: 0).fetch(dir) }
      end
    end
  end
end

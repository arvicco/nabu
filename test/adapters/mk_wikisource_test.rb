# frozen_string_literal: true

require "json"
require "tmpdir"
require "test_helper"
require "support/adapter_conformance"
require "support/store_test_db"

module Adapters
  # mk-wikisource (P116-2): the Macedonian 19th-century cone. Fixture
  # envelopes are real api.php captures (2026-10-10) — see the README.
  class MkWikisourceTest < Minitest::Test
    include AdapterConformance
    include StoreTestDB

    FIXTURES = Nabu::TestSupport.fixtures("mk-wikisource")

    def conformance_adapter = Nabu::Adapters::MkWikisource.new
    def conformance_workdir = FIXTURES
    def conformance_expected_source_id = "mk-wikisource"

    def documents
      @documents ||= conformance_adapter.discover(FIXTURES).map { |ref| conformance_adapter.parse(ref) }
    end

    def doc(pageid) = documents.find { |d| d.urn == "urn:nabu:mk-wikisource:#{pageid}" } || flunk("#{pageid} missing")

    API = "https://mk.wikisource.org/w/api.php"

    # The live-sync 414 (2026-10-10): 50 long Cyrillic titles in one GET
    # percent-encode past the server's URI limit. Batches must bound by
    # ENCODED URL length, and every cone page must still land.
    def test_fetch_batches_long_cyrillic_titles_under_the_url_cap
      titles = (1..60).map do |n|
        "Зборник на Миладиновци/Марко Крале и Муса Кеседжија се бореле три дена и три ноќи бр. #{n}"
      end
      root = Nabu::Adapters::MkWikisource::CONE.first.category
      stub_request(:get, /#{Regexp.escape(API)}.*list=categorymembers/).to_return do |request|
        title = URI.decode_www_form(URI(request.uri.to_s).query).to_h.fetch("cmtitle")
        members = title == root ? titles.map { |t| { "ns" => 0, "title" => t } } : []
        { body: JSON.generate("query" => { "categorymembers" => members }) }
      end
      revision_urls = []
      stub_request(:get, /#{Regexp.escape(API)}.*prop=revisions/).to_return do |request|
        revision_urls << request.uri.to_s
        batch = URI.decode_www_form(URI(request.uri.to_s).query).to_h.fetch("titles").split("|")
        { body: JSON.generate("query" => { "pages" => batch.to_h { |t| revision_page(t, 10_000 + titles.index(t)) } }) }
      end
      Dir.mktmpdir do |workdir|
        Nabu::Adapters::MkWikisource.new(delay: 0).fetch(workdir)
        assert_equal 60, Dir.glob(File.join(workdir, "pages", "*.json")).size, "every cone page lands"
      end
      assert_operator revision_urls.size, :>, 2, "the long titles force several batches"
      cap = Nabu::Adapters::SlavicWikisource::URL_BYTE_CAP
      revision_urls.each do |url|
        assert_operator url.bytesize, :<=, cap, "a batch URL exceeds the cap (#{url.bytesize} bytes)"
      end
    end

    def test_a_414_still_aborts_the_fetch
      stub_request(:get, /#{Regexp.escape(API)}.*list=categorymembers/).to_return(status: 414, body: "")
      Dir.mktmpdir do |workdir|
        error = assert_raises(Nabu::FetchError) { Nabu::Adapters::MkWikisource.new(delay: 0).fetch(workdir) }
        assert_match(/HTTP 414/, error.message)
      end
    end

    def revision_page(title, id)
      [id.to_s, { "pageid" => id, "ns" => 0, "title" => title,
                  "revisions" => [{ "revid" => id, "timestamp" => "2026-10-10T00:00:00Z",
                                    "slots" => { "main" => { "*" => "текст" } } }] }]
    end

    def test_author_pages_and_modern_duplicates_skip_by_rule
      ids = conformance_adapter.discover(FIXTURES).map(&:id).sort
      assert_equal %w[urn:nabu:mk-wikisource:3453 urn:nabu:mk-wikisource:3686 urn:nabu:mk-wikisource:7691], ids
      notes = conformance_adapter.discovery_skips(FIXTURES).notes.join("\n")
      assert_match(/author page/, notes, "Браќа Миладиновци is a biography page")
      assert_match(/modern-orthography duplicate/, notes, "Слогница речовска (современ правопис)")
    end

    def test_miladinov_songs_declare_their_modernized_orthography
      d = doc(3686)
      assert_equal "mkd", d.language
      assert_equal "modernized", d.metadata["orthography"], "the wiki's own забелешки, never silent"
      assert_equal "на современ македонски правопис", d.metadata["notes"]
      assert_equal "Браќа Миладиновци", d.metadata["author"]
      assert_equal "Цуцуљ пасит гојада", d.passages.first.text
      assert_equal "verse", d.metadata["grain"]
    end

    def test_pulevski_keeps_the_original_orthography
      d = doc(7691)
      assert_equal "original", d.metadata["orthography"]
      assert(d.passages.any? { |p| p.text.start_with?("Притяжательнихъ сказаниы") }, "yers and ы verbatim")
      refute(d.passages.any? { |p| p.text.include?("на стар правопис") }, "the Поврзано list is apparatus")
      assert_equal "25%", d.metadata["textquality"]
    end

    def test_krcovski_prose_carries_its_print_note
      d = doc(3453)
      assert_equal "modernized", d.metadata["orthography"]
      assert_match(/Издадена е во 1817/, d.metadata["notes"])
      assert_equal [1817, 1817], d.metadata["date"].values_at("not_before", "not_after"),
                   "the stated print year is mined as a typed date"
      assert_nil doc(3686).metadata["date"], "no stated year, no envelope"
      assert_equal "ЧУДО 11", d.passages.first.text
      assert_equal "prose", d.metadata["grain"]
    end

    def test_double_load_is_idempotent
      catalog = store_test_db
      source = Nabu::Store::Source.create(slug: "mk-wikisource", name: "mk", license_class: "attribution",
                                          adapter_class: "Nabu::Adapters::MkWikisource")
      first = Nabu::Store::Loader.new(db: catalog, source: source)
                                 .load_from(conformance_adapter, workdir: FIXTURES, full: true)
      assert_equal 3, first.added
      counts = [catalog[:documents].count, catalog[:passages].count]
      revisions = catalog[:documents].select_hash(:urn, :revision)
      Nabu::Store::Loader.new(db: catalog, source: source)
                         .load_from(conformance_adapter, workdir: FIXTURES, full: true)
      assert_equal counts, [catalog[:documents].count, catalog[:passages].count]
      assert_equal revisions, catalog[:documents].select_hash(:urn, :revision)
    end
  end
end

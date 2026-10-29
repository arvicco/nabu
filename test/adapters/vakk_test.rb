# frozen_string_literal: true

require "test_helper"
require "support/adapter_conformance"
require "tmpdir"
require "fileutils"
require "zlib"

module Adapters
  # vakk: VAKK, the Corpus of Old Written Estonian (vakk.ut.ee). Fixtures
  # (retrieved 2026-10-21 by the adapter's own crawl, narrowed to six
  # texts; pages gzip-stored verbatim): the 1510 postil notes (one-page
  # manuscript), the 1535 Wanradt–Koell catechism (ten pages) and its
  # German afterword (a metatext), Gutslaff's 1644 report (South
  # Estonian inside German, sparse page values), Horn's 1665 decree (a
  # secular print) and a Kahkva parish-court protocol of 1866 — plus the
  # text list trimmed to those six rows.
  class VakkTest < Minitest::Test
    include AdapterConformance

    FIXTURES = Nabu::TestSupport.fixtures("vakk")
    INDEX = "https://vakk.ut.ee/tekstid.php"
    FIRST = "https://vakk.ut.ee/tekstid.php?kood=%s"
    PAGE = "https://vakk.ut.ee/tekstid.php?lk=%s&kood=%s"
    INFO = "https://vakk.ut.ee/tekstid.php?lk=info&kood=%s"
    KOODS = %w[1510-postilla 1535-Koell 1535-Wanradt-Koell 1644-Gutslaff 1665-Horn 1866-Kahkva-0001].freeze

    def conformance_adapter = Nabu::Adapters::Vakk.new
    def conformance_workdir = FIXTURES
    def conformance_expected_source_id = "vakk"

    def documents
      @documents ||= conformance_adapter.discover(FIXTURES).map { |ref| conformance_adapter.parse(ref) }
    end

    def doc(kood) = documents.find { |d| d.urn == "urn:nabu:vakk:#{kood}" } || flunk("#{kood} missing")

    def gz(kood, file) = Zlib::GzipReader.open(File.join(FIXTURES, "texts", kood, file), &:read)

    def index_body = File.read(File.join(FIXTURES, "map", "tekstid.html"))

    def quiet_adapter(**) = Nabu::Adapters::Vakk.new(delay: 0, backoff: 0, **)

    # -- documents ---------------------------------------------------------

    def test_discovers_one_document_per_complete_text
      assert_equal(KOODS.map { |k| "urn:nabu:vakk:#{k}" }, conformance_adapter.discover(FIXTURES).map(&:id))
    end

    def test_one_passage_per_sentence_cited_page_dot_sentence
      koell = doc("1535-Koell")
      assert_equal 68, koell.size
      assert_equal "urn:nabu:vakk:1535-Koell:1.1", koell.passages.first.urn
      assert(koell.passages.map(&:urn).last.start_with?("urn:nabu:vakk:1535-Koell:10."), "ten pages, in order")
      assert_equal "Lehekülg 1", koell.passages.first.annotations["page"]
      assert_equal ["urn:nabu:vakk:1510-postilla:1.1", "surnud"],
                   [doc("1510-postilla").passages.first.urn, doc("1510-postilla").passages.first.text]
      assert_equal(%w[49 258 362 363], doc("1644-Gutslaff").passages.map do |p|
        p.urn.split(":").last.split(".").first
      end.uniq)
    end

    def test_tokens_ride_with_estonian_lemmas_only_on_estonian_tokens
      tokens = doc("1510-postilla").passages[1].annotations["tokens"]
      assert_equal({ "form" => "tha", "lemma" => "tahtma", "pos" => "v", "morph" => "pers.ind.pr.sg.1.",
                     "lang" => "eesti" }, tokens[2])
      german = doc("1535-Wanradt-Koell").passages.flat_map { |p| p.annotations["tokens"] }
                                                 .select { |t| t["lang"] == "saksa" }
      refute_empty german
      assert(german.none? { |t| t.key?("lemma") }, "a German token's headword never feeds the et lemma index")
    end

    def test_passage_language_follows_the_majority_of_tagged_words
      assert_equal ["de"], doc("1535-Wanradt-Koell").passages.map(&:language).uniq
      assert_equal %w[de et], doc("1644-Gutslaff").passages.map(&:language).uniq.sort,
                   "Gutslaff's Estonian charms inside his German report"
      assert_equal ["et"], doc("1535-Koell").passages.map(&:language).uniq
      assert_equal "et", doc("1535-Koell").language
    end

    def test_index_and_info_mine_the_axes
      koell = doc("1535-Koell")
      assert_equal "Wanradti-Koelli katekismus", koell.title
      assert_equal({ "not_before" => 1535, "not_after" => 1535, "raw" => "VAKK text list: 1535" },
                   koell.metadata["date"])
      assert_equal ["Koell, Johann (tlk)", "V - vaimulik", "North Estonian", "print"],
                   koell.metadata.values_at("author", "class", "dialect", "medium")
      assert_match(/\AEpp Ehasalu, Külli Habicht/, koell.metadata["source_edition"])
      assert_equal "958 / 958 / 931", koell.metadata["token_counts"]
      ranged = conformance_adapter.send(:date_for, "1485-1495")
      assert_equal [1485, 1495], ranged.values_at("not_before", "not_after")
    end

    def test_the_court_protocol_names_its_commune_and_record
      kahkva = doc("1866-Kahkva-0001")
      assert_equal ["Kahkva", "1866", "42", "K - kohtuprotokoll", "South Estonian", "manuscript"],
                   kahkva.metadata.values_at("place", "court_date", "protocol_number", "class", "dialect", "medium")
      assert_equal "Kahkva vallakohus", kahkva.metadata["author"]
      assert_match(/\AMichel Musting/, kahkva.metadata["judges"])
    end

    def test_registered_with_metadata_dates
      assert_equal :structured, Nabu::Store::TimelineBuilder::MetadataDates::SHAPES["vakk"]
    end

    # -- the index ---------------------------------------------------------

    def test_index_rows_carry_the_list_columns
      rows = conformance_adapter.send(:parse_index, index_body)
      assert_equal KOODS.sort, rows.map(&:kood).sort
      horn = rows.find { |r| r.kood == "1665-Horn" }
      assert_equal %w[1665 eP I T], [horn.year, horn.dialect, horn.klass, horn.medium]
    end

    def test_the_crawl_order_puts_the_court_protocols_last
      order = conformance_adapter.send(:crawl_order, conformance_adapter.send(:parse_index, index_body))
      assert_equal "1866-Kahkva-0001", order.last.kood
    end

    # -- skips -------------------------------------------------------------

    def test_an_incomplete_text_skips_by_rule_and_a_stray_directory_is_unrecognized
      Dir.mktmpdir do |dir|
        FileUtils.cp_r(Dir.glob(File.join(FIXTURES, "*")), dir)
        FileUtils.rm(File.join(dir, "texts", "1535-Koell", "p7.html.gz"))
        FileUtils.mkdir_p(File.join(dir, "texts", "1999-nowhere"))
        skips = conformance_adapter.discovery_skips(dir)
        assert_equal [1, 1], [skips.skipped_by_rule, skips.unrecognized]
        assert_includes skips.notes, "crawl incomplete: 1535-Koell"
        assert_includes skips.notes, "text directory not in the index: 1999-nowhere"
        refute_includes conformance_adapter.discover(dir).map(&:id), "urn:nabu:vakk:1535-Koell"
      end
    end

    # -- fetch (WebMock only) ----------------------------------------------

    def stub_text(kood)
      stub_request(:get, format(INFO, kood)).to_return(status: 200, body: gz(kood, "info.html.gz"))
      stub_request(:get, format(FIRST, kood)).to_return(status: 200, body: gz(kood, "first.html.gz"))
      Dir.glob(File.join(FIXTURES, "texts", kood, "p*.html.gz")).each do |path|
        value = File.basename(path, ".html.gz").delete_prefix("p")
        stub_request(:get, format(PAGE, value, kood)).to_return(status: 200, body: gz(kood, File.basename(path)))
      end
    end

    def test_fetch_crawls_index_info_and_every_page_then_resumes_at_the_file_grain
      stub_request(:get, INDEX).to_return(status: 200, body: index_body)
      KOODS.each { |kood| stub_text(kood) }
      Dir.mktmpdir do |dir|
        first = quiet_adapter(slice: 5).fetch(dir)
        assert_match(/slice limit reached/, first.notes)
        report = quiet_adapter.fetch(dir)
        assert_match(%r{crawl at 6/6 text\(s\) complete}, report.notes)
        assert_equal KOODS.size, conformance_adapter.discover(dir).count
        koell = Dir.children(File.join(dir, "texts", "1535-Koell")).sort
        assert_equal Dir.children(File.join(FIXTURES, "texts", "1535-Koell")).sort, koell
        assert_equal gz("1535-Koell", "p7.html.gz"), Zlib::GzipReader.open(File.join(dir, "texts", "1535-Koell",
                                                                                     "p7.html.gz"), &:read)
        again = quiet_adapter.fetch(dir)
        assert_match(/\+0 request/, again.notes, "a complete crawl asks for nothing but the index")
        assert_equal report.sha, again.sha
      end
    end

    def test_a_missing_text_is_ledgered_and_never_retried
      stub_request(:get, INDEX).to_return(status: 200, body: index_body)
      stub_request(:get, format(INFO, "1510-postilla")).to_return(status: 404)
      gone = stub_request(:get, format(FIRST, "1510-postilla")).to_return(status: 404)
      Dir.mktmpdir do |dir|
        quiet_adapter(koods: ["1510-postilla"]).fetch(dir)
        quiet_adapter(koods: ["1510-postilla"]).fetch(dir)
        assert_requested gone, times: 1
        ledger = JSON.parse(File.read(File.join(dir, ".vakk-crawl.json")))
        assert_equal ["1510-postilla"], ledger["texts"]
      end
    end

    def test_a_non_reading_view_answer_is_refused
      stub_request(:get, INDEX).to_return(status: 200, body: index_body)
      stub_text("1866-Kahkva-0001")
      stub_request(:get, format(FIRST, "1866-Kahkva-0001")).to_return(status: 200, body: "<html>avaleht</html>")
      Dir.mktmpdir do |dir|
        quiet_adapter(koods: ["1866-Kahkva-0001"]).fetch(dir)
        refute File.exist?(File.join(dir, "texts", "1866-Kahkva-0001", "first.html.gz"))
        assert_empty conformance_adapter.discover(dir).to_a
      end
    end

    def test_a_persistent_server_error_aborts_the_sync
      stub_request(:get, INDEX).to_return(status: 200, body: index_body)
      stub_request(:get, format(INFO, "1665-Horn")).to_return(status: 503)
      Dir.mktmpdir do |dir|
        assert_raises(Nabu::FetchError) { quiet_adapter(koods: ["1665-Horn"]).fetch(dir) }
      end
    end

    def test_an_empty_index_aborts
      stub_request(:get, INDEX).to_return(status: 200,
                                          body: "<html><table id=\"tekstid\"><tbody></tbody></table></html>")
      Dir.mktmpdir { |dir| assert_raises(Nabu::FetchError) { quiet_adapter.fetch(dir) } }
    end

    def test_registry_row
      entry = YAML.safe_load_file(File.join(Nabu::Config::PROJECT_ROOT, "config", "sources.yml"))["vakk"]
      assert_equal "Nabu::Adapters::Vakk", entry["adapter"]
      assert_equal true, entry["wired"], "wired 2026-10-28: crawl complete, first full parse on census"
      assert_equal "manual", entry["sync_policy"]
      assert_equal %w[baltic], entry["axes"]
      assert_equal "silver", entry["lemma_tier"]
      assert_equal "nc", Nabu::Adapters::Vakk.manifest.license_class
      assert_includes Nabu::Adapters::Vakk.manifest.license, "Licence CC - BY - NC"
    end
  end
end

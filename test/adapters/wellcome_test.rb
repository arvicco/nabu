# frozen_string_literal: true

require "test_helper"
require "support/adapter_conformance"
require "tmpdir"
require "zlib"

module Adapters
  # wellcome: the Wellcome Collection's digitised printed books over the
  # keyless per-volume text zips, census from the catalogue snapshot, the
  # pre-1800 Latin-led cone. Fixtures (test/fixtures/wellcome/README.md):
  # three real text zips (one whole, two member-trimmed), a real 12-line
  # cut of the catalogue snapshot, and the census.tsv the adapter derives
  # from it.
  class WellcomeTest < Minitest::Test
    include AdapterConformance

    FIXTURES = Nabu::TestSupport.fixtures("wellcome")
    W = Nabu::Adapters::Wellcome
    ZIP = "https://api.wellcomecollection.org/text/v1/%s.zip"

    def conformance_adapter = W.new
    def conformance_workdir = FIXTURES
    def conformance_expected_source_id = "wellcome"

    def documents
      @documents ||= conformance_adapter.discover(FIXTURES).map { |ref| conformance_adapter.parse(ref) }
    end

    def doc(volume) = documents.find { |d| d.urn == "urn:nabu:wellcome:#{volume}" } || flunk("#{volume} missing")

    def quiet_adapter(slice: 10, http: Nabu::ZipFetch.default_http)
      W.new(delay: 0, slice: slice, timeout_backoff: 0, http: http)
    end

    # -- documents ------------------------------------------------------------

    def test_one_document_per_volume_member_named_by_the_manifestation_id
      assert_equal %w[urn:nabu:wellcome:b30765808 urn:nabu:wellcome:b30773490 urn:nabu:wellcome:b33275154_0001],
                   conformance_adapter.discover(FIXTURES).map(&:id).sort,
                   "a single-volume zip holds <bnumber>.txt; a multi-part work's holds <bnumber>_0001.txt …"
    end

    def test_a_latin_dissertation_carries_the_catalogue_axes
      d = doc("b30773490")
      assert_equal "lat", d.language
      meta = d.metadata
      assert_equal({ "not_before" => 1719, "not_after" => 1719, "raw" => "M D CCXIX. [1719]", "class" => "edition" },
                   meta["date"], "the print year, class edition — never a composition claim")
      assert_equal "Trajecti ad Rhenum", meta["place"], "the imprint place as the catalogue names it"
      assert_equal({ "values" => ["Academic dissertations"] }, meta.dig("facets", "genre"))
      assert_equal "machine-ocr", meta["text_nature"]
      assert_equal "https://wellcomecollection.org/works/cdhzsjf3", meta["permalink"]
      assert_equal "https://iiif.wellcomecollection.org/presentation/v3/b30773490", meta["manifest"]
      assert_equal %w[digukmhl], meta["digcodes"]
      assert_match(/\ADisputatio anatomico-medica inauguralis, de origine lymphae/, d.title)
    end

    def test_marc_gre_on_a_cone_print_claims_grc_and_every_code_rides
      d = doc("b30765808")
      assert_equal "grc", d.language, "MARC gre on a ≤1799 print is the legacy all-periods Greek code"
      assert_equal %w[gre lat], d.metadata["languages_marc"]
      assert_equal %w[grc lat], d.metadata["languages"]
      assert_equal "ell", W.language_for(%w[gre], not_before: 1850), "after the cone gre is Modern Greek"
      assert_equal "fra", W.language_for(%w[fre], not_before: 1745), "639-2/B maps to the 639-3 tag"
      assert_equal "und", W.language_for([], not_before: 1700), "no language field claims und"
    end

    def test_passages_are_segments_with_offsets_never_pages
      d = doc("b33275154_0001")
      assert_operator d.passages.size, :>=, 3
      first = d.passages.first
      assert_equal "#{d.urn}:1", first.urn
      assert_equal({ "segment" => 1, "offset" => 0 }, first.annotations)
      assert d.passages.all? { |p| p.text.length <= W::SEGMENT_CHARS }, "a segment never exceeds the size"
      assert_includes d.passages.map(&:text).join(" "), "EXERCITATIONES"
      assert_match(/never pages/, d.metadata["ocr_note"])
    end

    def test_segments_cut_at_whitespace_and_count_letterless_ordinals
      text = "  #{'alpha ' * 30}12345 678 #{'beta ' * 5}"
      segments = W.segments(text, size: 50)
      assert_equal (1..segments.size).to_a, segments.map(&:first)
      assert_equal 2, segments.first[1], "the offset of the first non-space"
      assert(segments.all? { |_, _, s| s.length <= 50 && s == s.strip })
      assert_equal text.split.join(" "), segments.map(&:last).join(" "), "cuts only at whitespace"
      assert_equal segments, W.segments(text, size: 50), "deterministic"
      assert_equal [[1, 0, "x" * 50], [2, 50, "x" * 10]], W.segments("x" * 60, size: 50),
                   "a whitespace-less run hard-cuts at the size"
    end

    # -- the year reading ------------------------------------------------------

    def test_label_years_read_the_catalogue_shapes
      {
        "1694" => [1694], "M D CCXIX. [1719]" => [1719], "1650 [i.e. 1651]" => [1651],
        "1302 [1886]" => [1886], "An X = 1082 [i.e. 1802]" => [1802], "1791-1082" => [1791],
        "L'an de l'hegyre 1168-1170 [1754-1756]" => [1754, 1756], "M.DCC.XLV" => [1745],
        "MDCCLXXXV" => [1785], "[188?]" => [1880, 1889], "17--" => [1700, 1799], "[18-?]" => [1800, 1899],
        "[date of publication not identified]" => [], "An VI" => [], "" => []
      }.each { |label, years| assert_equal years, W.label_years(label), label }
    end

    # -- the census -----------------------------------------------------------

    def test_the_census_derives_from_the_snapshot_exactly_as_held
      Dir.mktmpdir do |dir|
        tsv = File.join(dir, "census.tsv")
        quiet_adapter.send(:derive_census!, File.join(FIXTURES, "works.json.gz"), tsv, nil)
        assert_equal File.read(File.join(FIXTURES, "census.tsv")), File.read(tsv),
                     "the fixture census.tsv is the adapter's own derivation"
      end
    end

    def test_the_census_scope_rejects_by_rule
      table = W.census_table(File.join(FIXTURES, "census.tsv"))
      assert_equal %w[b14583288 b20391109 b28749029 b30095852 b30765808 b30773490 b31973073 b33275154],
                   table.keys.sort
      refute table.key?("b30251151"), "a cc-by licence is out of scope"
      refute table.key?("b15813733"), "a non-book workType is out of scope"
      assert_equal %w[1886 1886], table["b30095852"].values_at("not_before", "not_after"),
                   "the Hijri year drops; its CE bracket answers"
      assert_equal "1745", table["b31973073"]["not_before"], "a Roman-numeral imprint year"
      lines = Zlib::GzipReader.open(File.join(FIXTURES, "works.json.gz"), &:readlines)
      assert_equal 11, lines.size, "the specimen: 8 in scope + cc-by + non-book + undated"
    end

    def test_the_cone_is_pre_1800_latin_first_then_greek_then_the_rest_by_year
      table = W.census_table(File.join(FIXTURES, "census.tsv"))
      assert_equal %w[b33275154 b30773490 b30765808 b31973073 b14583288], W.cone_order(table),
                   "Latin 1694, 1719; Greek 1680; then French 1745 — the 1850s/1880s/1890s rows wait, " \
                   "and the ProQuest Galen (1543, no text served) waits at the cone's tail"
      assert W.deferred?(table["b14583288"])
      refute W.deferred?(table["b30765808"])
    end

    # -- the crawl ------------------------------------------------------------

    def fixture_zip(bnumber) = File.binread(File.join(FIXTURES, "zips", "#{bnumber}.zip"))

    def test_the_crawl_ledgers_every_refusal_class_and_holds_the_zips
      stub_request(:get, format(ZIP, "b10000011")).to_return(status: 404,
                                                             body: "No text resource found for b10000011.zip")
      stub_request(:get, format(ZIP, "b10000022")).to_return(status: 200, body: fixture_zip("b30773490"))
      stub_request(:get, format(ZIP, "b10000033")).to_return(status: 403, body: "Forbidden")
      stub_request(:get, format(ZIP, "b10000044")).to_return(status: 200, body: "<html>not a zip</html>")
      stuck = stub_request(:get, format(ZIP, "b10000055")).to_raise(Net::ReadTimeout)
      ledger = quiet_adapter.send(:read_ledger, "/nonexistent")
      Dir.mktmpdir do |dir|
        order = %w[b10000011 b10000022 b10000033 b10000044 b10000055]
        tally = quiet_adapter.send(:crawl_slice!, dir, order, ledger, nil)
        assert_requested stuck, times: W::TIMEOUT_ATTEMPTS
        assert_equal [1, 1, 1, 1, 1], tally.values_at(:ok, :missing, :denied, :malformed, :timeout)
        assert File.file?(File.join(dir, "zips", "b10000022.zip")), "the zip is held verbatim"
        on_disk = JSON.parse(File.read(File.join(dir, ".wellcome-crawl.json")))
        assert_equal({ "missing" => ["b10000011"], "denied" => ["b10000033"], "empty" => [],
                       "malformed" => ["b10000044"], "timeout-stuck" => ["b10000055"] },
                     on_disk.slice(*W::LEDGER_CLASSES))
        assert_equal({ "cone" => 5, "done" => 1, "ledgered" => 4 }, on_disk["position"])
        assert_equal ["b10000022"], on_disk["done"]
      end
    end

    def test_a_ledgered_or_held_bnumber_is_never_retried_and_the_slice_bounds_attempts
      adapter = quiet_adapter(slice: 2)
      asked = []
      adapter.define_singleton_method(:fetch_zip!) do |_workdir, bnumber|
        asked << bnumber
        :missing
      end
      Dir.mktmpdir do |dir|
        FileUtils.mkdir_p(File.join(dir, "zips"))
        File.binwrite(File.join(dir, "zips", "b10000022.zip"), "held")
        ledger = { "missing" => ["b10000011"], "denied" => [], "empty" => [], "malformed" => [], "timeout-stuck" => [] }
        adapter.send(:crawl_slice!, dir, %w[b10000011 b10000022 b10000033 b10000044 b10000055], ledger, nil)
        assert_equal %w[b10000033 b10000044], asked, "ledgered and held skip; the slice stops at 2 attempts"
      end
    end

    # The empty answer is real: b33011564 (a 1741 French print) serves a zip
    # whose one member is 0 bytes.
    def test_a_zip_without_letters_is_empty_and_a_429_stops_the_slice_cleanly
      Dir.mktmpdir do |dir|
        stub_request(:get, format(ZIP, "b10000099")).to_return(status: 200, body: fixture_zip("b33011564"))
        stub_request(:get, format(ZIP, "b10000088")).to_return(status: 429, body: "slow down")
        never = stub_request(:get, format(ZIP, "b10000077"))
        ledger = quiet_adapter.send(:read_ledger, dir)
        tally = quiet_adapter.send(:crawl_slice!, dir, %w[b10000099 b10000088 b10000077], ledger, nil)
        assert_equal ["b10000099"], ledger["empty"]
        assert tally[:rate_limited]
        assert_not_requested never
        refute_includes ledger.values.flatten, "b10000088", "a rate limit is never ledgered — the next sync resumes"
      end
    end

    def test_a_server_error_stays_fatal
      stub_request(:get, format(ZIP, "b10000011")).to_return(status: 500)
      Dir.mktmpdir do |dir|
        assert_raises(Nabu::FetchError) { quiet_adapter.send(:crawl_slice!, dir, %w[b10000011], quiet_adapter.send(:read_ledger, dir), nil) }
      end
    end

    def test_the_pace_is_thirty_seconds_and_the_slice_honest
      assert_equal 30.0, W::DELAY, "the IIIF host's robots Request-rate 1/30s — never lower"
      assert_equal 240, W::SLICE
      assert_equal 2.0, W::SLICE * W::DELAY / 3600, "one slice is two hours of pace"
    end

    # -- the census refresh ---------------------------------------------------

    CENSUS = W::CENSUS_URL

    def test_fetch_downloads_the_snapshot_derives_and_crawls_the_cone_head
      body = File.binread(File.join(FIXTURES, "works.json.gz"))
      stub_request(:get, CENSUS).to_return(status: 200, body: body, headers: { "ETag" => '"abc"' })
      stub_request(:get, format(ZIP, "b33275154")).to_return(status: 200, body: fixture_zip("b33275154"))
      stub_request(:get, format(ZIP, "b30773490")).to_return(status: 404)
      Dir.mktmpdir do |dir|
        report = quiet_adapter(slice: 2).fetch(dir)
        assert_equal File.read(File.join(FIXTURES, "census.tsv")), File.read(File.join(dir, "census.tsv"))
        assert_equal '"abc"', JSON.parse(File.read(File.join(dir, ".wellcome-census.json")))["etag"]
        assert_match(%r{crawl at 1/5 cone volume\(s\) held, 1 ledgered}, report.notes)
        assert_equal 0, quiet_adapter.discovery_skips(dir).unrecognized, "census, dump and zips are no strays"
      end
    end

    def test_a_fresh_snapshot_is_not_refetched_and_a_stale_one_revalidates_on_its_etag
      Dir.mktmpdir do |dir|
        FileUtils.cp(File.join(FIXTURES, "works.json.gz"), dir)
        FileUtils.cp(File.join(FIXTURES, "census.tsv"), dir)
        state = File.join(dir, ".wellcome-census.json")
        File.write(state, JSON.generate("etag" => '"abc"', "fetched_at" => Time.now.utc.iso8601))
        quiet_adapter.send(:ensure_census!, dir, nil)
        assert_not_requested :get, CENSUS

        File.write(state, JSON.generate("etag" => '"abc"', "fetched_at" => (Time.now - (40 * 86_400)).utc.iso8601))
        revalidate = stub_request(:get, CENSUS).with(headers: { "If-None-Match" => '"abc"' }).to_return(status: 304)
        quiet_adapter.send(:ensure_census!, dir, nil)
        assert_requested revalidate
        assert_equal File.binread(File.join(FIXTURES, "works.json.gz")), File.binread(File.join(dir, "works.json.gz")),
                     "a 304 keeps the held snapshot"
        assert_operator Time.iso8601(JSON.parse(File.read(state))["fetched_at"]), :>, Time.now - 60
        refute File.exist?(File.join(dir, "works.json.gz.part"))
      end
    end

    # -- discovery ------------------------------------------------------------

    def test_the_fixture_tree_is_clean_and_a_stray_is_named
      assert_predicate conformance_adapter.discovery_skips(FIXTURES), :clean?
      Dir.mktmpdir do |dir|
        FileUtils.mkdir_p(File.join(dir, "zips"))
        File.write(File.join(dir, "zips", "notes.txt"), "x")
        skips = conformance_adapter.discovery_skips(dir)
        assert_equal 1, skips.unrecognized
        assert_equal ["non-corpus file: zips/notes.txt"], skips.notes
      end
    end

    def test_census_tsv_is_a_declared_materialization
      assert_equal ["census.tsv"], W.materialized_paths
    end

    def test_a_zero_byte_volume_member_skips_by_rule
      skips = conformance_adapter.discovery_skips(FIXTURES)
      assert_equal 1, skips.skipped_by_rule
      assert_equal ["empty volume text (upstream serves a 0-byte member) skipped by rule: b33011564.zip:b33011564.txt"],
                   skips.notes
      refute_includes conformance_adapter.discover(FIXTURES).map(&:id), "urn:nabu:wellcome:b33011564"
    end
  end
end

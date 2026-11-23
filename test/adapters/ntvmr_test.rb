# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"
require "json"

# NTVMR — the INTF New Testament Virtual Manuscript Room. Fixture ground
# truth (retrieved 2026-11-23, test/fixtures/ntvmr/README.md): liste.xml is
# the real Liste answer trimmed to 24 records (its count="7772" kept
# verbatim — upstream's own advertised total): 14 GA manuscripts in scope
# and 10 non-GA records (versional, edition, project-copy, family and test
# records — the rejected grain). transcripts/ holds three real transcript/get
# answers (10052 P52 and 20189 0189 whole-manuscript pageID=ALL; 20001 01
# cut to Philemon by indexContent) and the rejected-grain specimen
# 20059.xml — the real "No Transcription Available" error answer for 059.
class NtvmrTest < Minitest::Test
  include StoreTestDB
  include AdapterConformance

  SLUG = "ntvmr"
  ADAPTER = Nabu::Adapters::Ntvmr
  FIXTURES = File.expand_path("../fixtures/ntvmr", __dir__)
  URN = "urn:nabu:ntvmr:"
  API = "https://ntvmr.uni-muenster.de/community/vmr/api"
  # The real 200 answers for an uncatalogued docID and an untranscribed
  # manuscript (2026-11-23), verbatim.
  NOT_FOUND_BODY = '<error code="300" message="docID: 34000 not found"/>'
  NO_TRANSCRIPT_BODY = '<error code="1" message="No Transcription Available for GA: L500 page: ALL"/>'

  def conformance_adapter = adapter
  def conformance_workdir = FIXTURES
  def conformance_expected_source_id = SLUG

  def adapter(**knobs) = ADAPTER.new(delay: 0, sleeper: ->(_seconds) {}, **knobs)

  # The crawl as it will run once the INTF lifts the suspension.
  def live(**knobs) = adapter(honor_suspension: false, **knobs)

  def document(slug)
    ref = adapter.discover(FIXTURES).find { |r| r.id == "#{URN}#{slug}" }
    refute_nil ref, "no ref for #{slug}"
    adapter.parse(ref)
  end

  # --- manifest + declarations -------------------------------------------------

  def test_manifest_is_cc_by_attribution_and_credits_the_intf
    manifest = ADAPTER.manifest
    assert_equal SLUG, manifest.id
    assert_equal "attribution", manifest.license_class
    assert_match(%r{Creative Commons Attribution 4\.0.*creativecommons\.org/licenses/by/4\.0}, manifest.license)
    assert_match(/images .* not used/i, manifest.license, "the restricted images are out of scope")
    assert_includes manifest.credit, "Institut für Neutestamentliche Textforschung"
    assert_equal "ntvmr-tei", manifest.parser_family
  end

  def test_the_lane_is_suspended_by_the_robots_disallow_and_paces_conservatively
    spec = ADAPTER::TRANSCRIPT_CRAWL
    assert spec.schedule.suspended?
    assert_match(%r{robots\.txt disallows /community/vmr/api/}, spec.schedule.suspended)
    assert_operator spec.delay, :>=, 10.0, "never below the robots Crawl-delay"
    assert_in_delta 30.0, spec.delay, 0.001
    assert_equal 60, spec.slice
    assert_equal %w[denied not-found malformed no-transcript textless timeout-stuck server-error], spec.class_names
    assert_equal [spec.schedule], Nabu::PacedCrawl.schedules_of(ADAPTER)
  end

  def test_fetch_refuses_while_suspended_and_asks_nothing
    Dir.mktmpdir do |dir|
      error = assert_raises(Nabu::FetchError) { adapter.fetch(dir) }
      assert_match(/SUSPENDED/, error.message)
      assert_not_requested :get, /ntvmr\.uni-muenster\.de/
      assert_empty Dir.children(dir)
    end
  end

  def test_the_liveness_probe_never_walks_the_disallowed_api
    targets = ADAPTER.http_probe_targets
    assert_equal ["https://ntvmr.uni-muenster.de/"], targets.map(&:zip_url)
  end

  # --- census --------------------------------------------------------------------

  def test_the_census_splits_ga_manuscripts_from_the_rejected_records
    census = adapter.census(FIXTURES)
    assert_equal 7772, census[:count], "upstream's own advertised total rides verbatim"
    assert_equal 24, census[:records].size
    assert_equal 14, census[:in_scope].size
    assert_equal %w[papyrus majuscule minuscule lectionary],
                 census[:in_scope].map(&:category).uniq
    assert_equal ["MS Syriac 99", "", "Var1", "sa 1", "Test", "Erasmus 1516", "19", "yo2", "03", "f1 1"],
                 census[:rejected].map(&:ga), "every non-GA docID class is the rejected grain, by rule"
    assert_equal %w[10001 10046 10052], census[:in_scope].first(3).map(&:doc_id), "Liste order is crawl order"
  end

  def test_ga_slugs_downcase_and_drop_whitespace
    assert_equal "l102a", ADAPTER.ga_slug("l 102a")
    assert_equal "p52", ADAPTER.ga_slug("P52")
    assert_equal "l500", ADAPTER.ga_slug("L500")
  end

  def test_the_century_field_reads_into_an_envelope
    cases = {
      "III" => [201, 300], "IV/V" => [301, 500], "E III - A IV" => [201, 400], "II (M)" => [101, 200],
      "XI-XII" => [1001, 1200], "r: XII; ap: XIII" => [1101, 1300], "XIIi/XIV" => [1201, 1400],
      "1292" => [1292, 1292], "1291/92" => [1291, 1292], "ca. 1043-55" => [1043, 1055],
      "861/62?" => [861, 862], "1364 /1463" => [1364, 1463], "XVI (1537)?" => [1537, 1537]
    }
    cases.each do |raw, bounds|
      date = ADAPTER.date_for(raw)
      assert_equal bounds, [date["not_before"], date["not_after"]], raw
      assert_equal raw, date["raw"]
    end
    ["", "?", "[reserved]"].each { |raw| assert_nil ADAPTER.date_for(raw), raw.inspect }
  end

  # --- discover --------------------------------------------------------------------

  def test_discover_yields_the_transcribed_manuscripts_and_skips_the_error_answer_by_rule
    refs = adapter.discover(FIXTURES).to_a
    assert_equal %W[#{URN}p52 #{URN}01 #{URN}0189], refs.map(&:id)
    assert_equal({ "doc_id" => "10052", "ga" => "P52" }, refs.first.metadata)
    skips = adapter.discovery_skips(FIXTURES)
    assert_equal 1, skips.skipped_by_rule
    assert_equal 0, skips.unrecognized
    assert_match(%r{transcripts/20059\.xml: an upstream error answer .* skipped by rule}, skips.notes.first)
  end

  def test_non_ga_and_unknown_docids_on_disk_are_counted_never_dropped
    staged do |dir|
      FileUtils.cp(File.join(dir, "transcripts", "10052.xml"), File.join(dir, "transcripts", "620001.xml"))
      FileUtils.cp(File.join(dir, "transcripts", "10052.xml"), File.join(dir, "transcripts", "34000.xml"))
      File.write(File.join(dir, "notes.txt"), "x")
      skips = adapter.discovery_skips(dir)
      assert_equal 2, skips.skipped_by_rule
      assert_equal 2, skips.unrecognized
      assert(skips.notes.any? { |n| n.include?("620001.xml") && n.include?("non-GA") })
      assert(skips.notes.any? { |n| n.include?("34000.xml") && n.include?("not in the held Liste") })
      assert(skips.notes.any? { |n| n.include?("notes.txt") })
      assert_equal 3, adapter.discover(dir).count
    end
  end

  def test_an_empty_workdir_yields_nothing
    Dir.mktmpdir do |dir|
      assert_empty adapter.discover(dir).to_a
      assert_empty adapter.census(dir)[:records]
    end
  end

  # --- parse -------------------------------------------------------------------------

  def test_p52_parses_one_passage_per_verse
    doc = document("p52")
    assert_equal "grc", doc.language
    assert_equal "GA P52 (Manchester, John Rylands University Library of Manchester, Gr. P. 457)", doc.title
    assert_equal %w[john.18.31 john.18.32 john.18.33 john.18.37 john.18.38].map { |t| "#{URN}p52:#{t}" },
                 doc.map(&:urn)
    assert_equal "οι ιουδαιοι ημειν ουκ εξεστιν αποκτειναι ουδενα", doc.first.text
    assert_equal "JOHN 18.31", doc.first.annotations["tokens"].first["citation_part"],
                 "the nt hub join is declared on every verse token"
  end

  def test_metadata_mines_the_liste_and_the_header
    meta = document("p52").metadata
    assert_equal({ "not_before" => 101, "not_after" => 200, "raw" => "II (M)" }, meta["date"])
    assert_equal "papyrus", meta["category"]
    assert_equal({ "values" => ["papyrus"] }, meta.dig("facets", "category"))
    assert_equal ["United Kingdom", "Manchester", "John Rylands University Library of Manchester", "Gr. P. 457"],
                 meta.values_at("country", "settlement", "repository", "idno")
    refute meta.key?("place"), "the holding library is not an origin claim"
    assert_equal "https://creativecommons.org/licenses/by/4.0/", meta["license_url"]
    assert_equal "https://ntvmr.uni-muenster.de/manuscript-workspace?docID=10052", meta["permalink"]
    assert_equal %w[john], meta["books"]
    assert_equal 5, meta["verses"]
  end

  def test_sinaiticus_carries_its_correctors
    doc = document("01")
    assert_equal 25, doc.size
    assert_equal %w[firsthand corrector2 corrector2a corrector2b], doc.metadata["hands"]
    assert_equal({ "not_before" => 301, "not_after" => 400, "raw" => "IV" }, doc.metadata["date"])
    assert(doc.any? { |p| p.annotations["corrections"] })
  end

  def test_a_transcript_without_the_cc_by_statement_is_not_admitted
    staged do |dir|
      path = File.join(dir, "transcripts", "10052.xml")
      File.write(path, File.read(path).sub("creativecommons.org/licenses/by/4.0/", "example.org/terms"))
      ref = adapter.discover(dir).find { |r| r.id == "#{URN}p52" }
      error = assert_raises(Nabu::ParseError) { adapter.parse(ref) }
      assert_match(/no Creative Commons Attribution statement/, error.message)
    end
  end

  # --- fetch (WebMock, no network; the suspension lifted by knob) ------------------

  def test_fetch_censuses_then_crawls_one_slice_and_ledgers_the_classes
    Dir.mktmpdir do |dir|
      stub_liste
      stub_transcript("10001", NO_TRANSCRIPT_BODY)
      stub_transcript("10046", NOT_FOUND_BODY)
      stub_transcript("10052", File.read(File.join(FIXTURES, "transcripts", "10052.xml")))
      lane = live(slice: 3, clock: -> { Time.utc(2026, 11, 23) })
      report = lane.fetch(dir)
      assert File.file?(File.join(dir, "transcripts", "10052.xml"))
      assert File.file?(File.join(dir, "liste.xml"))
      ledger = JSON.parse(File.read(File.join(dir, ".ntvmr-crawl.json")))
      assert_equal %w[10001], ledger["no-transcript"]
      assert_equal %w[10046], ledger["not-found"]
      state = JSON.parse(File.read(File.join(dir, ".ntvmr-census.json")))
      assert_equal({ "url" => "#{API}/metadata/liste/get/", "fetched_on" => "2026-11-23", "count" => 24 },
                   state.slice("url", "fetched_on", "count"))
      assert_match(/census 24 Liste record\(s\) \(upstream count 24\) = 14 GA manuscripts \+ 10 non-GA/,
                   report.notes)
      assert_match(/census 14 = held 1 .* reconciles/, report.notes)
      assert_equal ["#{URN}p52"], lane.discover(dir).map(&:id)
    end
  end

  def test_a_held_liste_is_reused_and_the_crawl_resumes
    Dir.mktmpdir do |dir|
      stub_liste
      stub_request(:get, %r{#{Regexp.escape(API)}/transcript/get/}).to_return(status: 200, body: NO_TRANSCRIPT_BODY)
      live(slice: 2).fetch(dir)
      WebMock.reset!
      stub_request(:get, %r{#{Regexp.escape(API)}/transcript/get/}).to_return(status: 200, body: NO_TRANSCRIPT_BODY)
      report = live(slice: 2).fetch(dir)
      assert_not_requested :get, "#{API}/metadata/liste/get/"
      assert_match(/held Liste reused/, report.notes)
      ledger = JSON.parse(File.read(File.join(dir, ".ntvmr-crawl.json")))
      assert_equal %w[10001 10046 10052 20001], ledger["no-transcript"]
    end
  end

  # The fixture itself IS a truncated answer: count="7772" over 24 records.
  def test_a_truncated_liste_aborts_before_it_lands
    Dir.mktmpdir do |dir|
      stub_request(:get, "#{API}/metadata/liste/get/")
        .to_return(status: 200, body: File.read(File.join(FIXTURES, "liste.xml")))
      error = assert_raises(Nabu::FetchError) { live.fetch(dir) }
      assert_match(/TRUNCATED/, error.message)
      refute File.exist?(File.join(dir, "liste.xml"))
    end
  end

  def test_transcript_answers_classify_into_the_ledger_classes
    tei = File.read(File.join(FIXTURES, "transcripts", "20189.xml"))
    assert_equal [:ok, nil], ADAPTER.transcript_verdict(tei)
    assert_equal [:empty, nil], ADAPTER.transcript_verdict(NO_TRANSCRIPT_BODY)
    assert_equal [:denied, "not-found"], ADAPTER.transcript_verdict(NOT_FOUND_BODY)
    assert_equal [:denied, nil], ADAPTER.transcript_verdict('<error code="-4" message="docID cannot be null"/>')
    assert_equal [:denied, "malformed"], ADAPTER.transcript_verdict("<html><body>Service unavailable</body></html>")
    textless = tei.gsub(%r{<ab\b.*?</ab>}m, "")
    assert_equal [:empty, "textless"], ADAPTER.transcript_verdict(textless)
  end

  def test_http_429_is_a_clean_stop_and_ledgers_nothing
    Dir.mktmpdir do |dir|
      stub_request(:get, "#{API}/transcript/get/?docID=10001&pageID=ALL&format=teiraw")
        .to_return(status: 429, body: "Too Many Requests")
      outcome = live.send(:fetch_transcript!, dir, "10001")
      assert outcome.halt?
      refute File.exist?(File.join(dir, "transcripts", "10001.xml"))
    end
  end

  def test_an_upstream_outage_aborts_the_slice_unledgered
    Dir.mktmpdir do |dir|
      stub_liste
      stub_request(:get, %r{#{Regexp.escape(API)}/transcript/get/}).to_return(status: 503, body: "down")
      error = assert_raises(Nabu::FetchError) { live(slice: 5, timeout_backoff: 0).fetch(dir) }
      assert_match(/upstream outage/, error.message)
      ledger = JSON.parse(File.read(File.join(dir, ".ntvmr-crawl.json")))
      assert_empty ledger["server-error"].to_a
    end
  end

  # --- idempotency + registry ----------------------------------------------------------

  def test_double_load_is_idempotent
    catalog = store_test_db
    source = Nabu::Store::Source.create(slug: SLUG, name: "NTVMR", adapter_class: "Nabu::Adapters::Ntvmr",
                                        license_class: "attribution")
    first = Nabu::Store::Loader.new(db: catalog, source: source).load_from(adapter, workdir: FIXTURES, full: true)
    assert_equal 3, first.added
    assert_equal 0, first.errored
    counts = [catalog[:documents].count, catalog[:passages].count]
    assert_equal [3, 49], counts
    revisions = catalog[:documents].select_hash(:urn, :revision)
    Nabu::Store::Loader.new(db: catalog, source: source).load_from(adapter, workdir: FIXTURES, full: true)
    assert_equal counts, [catalog[:documents].count, catalog[:passages].count]
    assert_equal revisions, catalog[:documents].select_hash(:urn, :revision)
  end

  def test_registry_resolves_ntvmr_unwired_and_deferred
    registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources", __dir__))
    entry = registry[SLUG]
    refute_nil entry
    assert_equal ADAPTER, entry.adapter_class
    refute entry.wired, "unwired until the INTF lifts the suspension and a first sync is verified"
    assert entry.index_deferred?, "a paced-crawl citizen indexes once per wave"
  end

  private

  # A scratch copy of the fixture tree.
  def staged
    Dir.mktmpdir("ntvmr-test") do |dir|
      FileUtils.cp_r(File.join(FIXTURES, "."), dir)
      yield dir
    end
  end

  # The trimmed Liste with its count attribute matched to the 24 records it
  # keeps (the fixture keeps upstream's count="7772" verbatim, which the
  # truncation defense rightly refuses as a live answer).
  def stub_liste
    body = File.read(File.join(FIXTURES, "liste.xml")).sub('count="7772"', 'count="24"')
    stub_request(:get, "#{API}/metadata/liste/get/").to_return(status: 200, body: body)
  end

  def stub_transcript(doc_id, body)
    stub_request(:get, "#{API}/transcript/get/?docID=#{doc_id}&pageID=ALL&format=teiraw")
      .to_return(status: 200, body: body)
  end
end

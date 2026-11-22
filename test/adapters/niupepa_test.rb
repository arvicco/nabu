# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"
require "json"

# Niupepa — Māori Newspapers (the New Zealand Digital Library's Greenstone 3
# collection, University of Waikato) under the research_private posture: the
# granted terms are a personal single-user research library, local only,
# nothing redistributed — so the fixture bytes live under the gitignored
# local/fixtures/niupepa/ and every data-bearing case SKIPs when they are
# absent (the seal/aclt mold); CI and public clones pass without the bytes.
#
# Fixture ground truth (retrieved 2026-11-21, local/fixtures/niupepa/
# README.md): canonical/ is the crawl's tree — map/CL1.html (the series
# classifier, trimmed to four real series rows: CL1.1 Te Karere O Nui
# Tireni, CL1.6 Te Waka o Te Iwi, CL1.14 Te Waka Maori o Ahuriri, CL1.34 Te
# Toa Takitini) + those four listings whole; issues/ holds three real issues
# (01_1_1 1842 — 4 pages; 16_1_1 1863 — 4 pages; 41__1 1921 — 12 pages) and
# the two rejected-grain specimens (01commentary, 01_1_1abstract).
# specimens/09_1_1.xml is a real text-less issue answer (every page hastxt
# 0), the no-text ledger class's evidence.
class NiupepaTest < Minitest::Test
  include StoreTestDB
  include AdapterConformance

  SLUG = "niupepa"
  ADAPTER = Nabu::Adapters::Niupepa
  ROOT = Nabu::TestSupport.local_fixtures(SLUG)
  FIXTURES = File.join(ROOT, "canonical")
  URN = "urn:nabu:niupepa:"
  BASE = "https://www.greenstone.org/greenstone3/library/collection/niupepa"

  def conformance_adapter = adapter
  def conformance_expected_source_id = SLUG

  def conformance_workdir
    require_fixtures!
    FIXTURES
  end

  def adapter(**knobs) = ADAPTER.new(delay: 0, sleeper: ->(_seconds) {}, **knobs)

  def document(oid)
    ref = adapter.discover(conformance_workdir).find { |r| r.id == "#{URN}#{oid}" }
    refute_nil ref, "no ref for #{oid}"
    adapter.parse(ref)
  end

  # --- manifest + declarations (run everywhere, no bytes) ----------------------

  def test_manifest_is_research_private_and_credits_the_collection
    manifest = ADAPTER.manifest
    assert_equal SLUG, manifest.id
    assert_equal "research_private", manifest.license_class,
                 "personal single-user research, local only, nothing redistributed"
    assert_match(/nothing redistributed/i, manifest.license)
    assert_match(/held locally only/i, manifest.license)
    refute_match(/\b20\d\d-\d\d-\d\d\b|by e-?mail|Keegan/i, manifest.license,
                 "terms + credit only — never who granted it, when, or how")
    assert_includes manifest.credit, "Niupepa"
    assert_includes manifest.credit, "New Zealand Digital Library, University of Waikato"
    assert_equal BASE, manifest.upstream_url
  end

  def test_the_lane_paces_at_robots_crawl_delay_and_declares_its_schedule
    spec = ADAPTER::ISSUE_CRAWL
    assert_in_delta 10.0, spec.delay, 0.001, "robots.txt Crawl-delay: 10 binds every agent"
    assert_equal 150, spec.slice
    assert_equal Nabu::PacedCrawl::Schedule.new(cadence: :per_phase, slices_per_phase: 3, stop_after_zero_slices: 3),
                 spec.schedule
    assert_equal %w[denied no-text timeout-stuck server-error], spec.class_names
  end

  def test_issue_oids_cover_every_censused_shape_and_refuse_the_rejected_grains
    %w[01_1_1 06a_1_1 41__1 19_2_ 21__ 36b_1_3 40__24-25].each do |oid|
      assert_match ADAPTER::ISSUE_ID, oid
    end
    %w[01commentary 06acommentary 01_1_1abstract].each { |oid| refute_match ADAPTER::ISSUE_ID, oid }
  end

  # --- census ----------------------------------------------------------------

  def test_the_series_classifier_states_each_series_count
    series = ADAPTER.series_list(File.read(File.join(conformance_workdir, "map", "CL1.html")))
    assert_equal %w[1 6 14 34], series.map(&:index)
    assert_equal [49, 3, 136, 116], series.map(&:count)
    assert_equal "Te Karere O Nui Tireni 1842-1846", series.first.label
  end

  def test_the_held_census_splits_issues_from_commentaries
    census = adapter.census(conformance_workdir)
    assert_equal 4, census[:series].size
    assert_equal 49 + 3 + 136 + 116, census[:issues].size + census[:commentaries].size,
                 "every listed document is an issue or a commentary"
    assert_equal %w[01commentary 09commentary 16commentary], census[:commentaries].sort
    assert_equal 301, census[:issues].size
    assert_includes census[:issues], "41__1"
  end

  # --- discover ----------------------------------------------------------------

  def test_discover_yields_the_issues_and_skips_the_rejected_grains_by_rule
    refs = adapter.discover(conformance_workdir).to_a
    assert_equal %W[#{URN}01_1_1 #{URN}16_1_1 #{URN}41__1], refs.map(&:id)
    skips = adapter.discovery_skips(conformance_workdir)
    assert_equal 2, skips.skipped_by_rule, "the commentary + the abstract specimens"
    assert_equal 0, skips.unrecognized
    assert(skips.notes.any? { |n| n.include?("01commentary.xml") && n.include?("skipped by rule") })
    assert(skips.notes.any? { |n| n.include?("01_1_1abstract.xml") && n.include?("skipped by rule") })
  end

  def test_a_stray_file_is_unrecognized_loudly
    staged do |dir|
      File.write(File.join(dir, "notes.txt"), "x")
      skips = adapter.discovery_skips(dir)
      assert_equal 1, skips.unrecognized
      assert(skips.notes.any? { |n| n.include?("notes.txt") })
    end
  end

  def test_an_unfetched_workdir_yields_nothing
    Dir.mktmpdir do |dir|
      assert_empty adapter.discover(dir).to_a
      assert_nil adapter.census(dir)
    end
  end

  # --- parse -------------------------------------------------------------------

  def test_the_first_issue_parses_one_passage_per_page
    doc = document("01_1_1")
    assert_equal "mri", doc.language
    assert_equal "Te Karere O Nui Tireni — Volume 1, Number 1 (1842-01-01)", doc.title
    assert_equal %W[#{URN}01_1_1:p1 #{URN}01_1_1:p2 #{URN}01_1_1:p3 #{URN}01_1_1:p4], doc.map(&:urn)
    assert doc.first.text.start_with?("He pukapuka hou tenei  katahi ka taia")
    assert_equal({ "page" => "1" }, doc.first.annotations)
  end

  def test_period_orthography_and_ocr_ride_verbatim
    text = document("01_1_1").map(&:text).join("\n")
    assert_includes text, "wakaaro", "the early prints write w for wh — canonical, never corrected"
    assert_includes text, "E wakaaro ana te tokomaha 0 nga Pakeha", "the OCR's 0 for o rides as served"
    refute_includes text, "<pre>", "the page's HTML wrapper is not text"
  end

  def test_metadata_mines_the_issue_record
    meta = document("01_1_1").metadata
    assert_equal({ "not_before" => 1842, "not_after" => 1842, "raw" => "1842-01-01" }, meta["date"])
    assert_equal "18420101", meta["date_raw"]
    assert_equal "Te Karere O Nui Tireni 1842-1846", meta["series"]
    assert_equal "Te Karere O Nui Tireni", meta["series_title"]
    assert_equal "1842-1846", meta["series_run"]
    assert_equal %w[1 1], [meta["volume"], meta["number"]]
    assert_equal 4, meta["pages"]
    assert_nil meta["pages_without_text"]
    assert_equal "01_1_1abstract", meta["abstract_oid"]
    assert_equal "01commentary", meta["commentary_oid"]
    assert_equal "#{BASE}/document/01_1_1", meta["permalink"]
    assert_equal "machine-ocr", meta["text_nature"]
    assert_equal({ "values" => ["Te Karere O Nui Tireni"] }, meta.dig("facets", "series"))
  end

  def test_a_volumeless_issue_of_the_twentieth_century
    doc = document("41__1")
    assert_equal 12, doc.size
    assert_equal "Te Toa Takitini — Number 1 (1921-08-31)", doc.title
    assert_nil doc.metadata["volume"]
    assert_equal "1", doc.metadata["number"]
    assert_equal 1921, doc.metadata.dig("date", "not_before")
  end

  def test_a_month_grain_date_keeps_its_month_raw
    staged do |dir|
      path = File.join(dir, "issues", "01_1_1.xml")
      File.write(path, File.read(path).sub("<metadata name=\"Date\">18420101</metadata>",
                                           "<metadata name=\"Date\">185710</metadata>"))
      ref = adapter.discover(dir).find { |r| r.id == "#{URN}01_1_1" }
      assert_equal({ "not_before" => 1857, "not_after" => 1857, "raw" => "1857-10" },
                   adapter.parse(ref).metadata["date"])
    end
  end

  def test_a_textless_page_mints_no_passage_and_is_counted
    staged do |dir|
      path = File.join(dir, "issues", "16_1_1.xml")
      xml = Nokogiri::XML(File.read(path))
      xml.at_xpath("//documentNode[@nodeID='16_1_1.3']/nodeContent").content = "\n<pre>\n</pre>\n"
      File.write(path, xml.to_xml)
      ref = adapter.discover(dir).find { |r| r.id == "#{URN}16_1_1" }
      doc = adapter.parse(ref)
      assert_equal %W[#{URN}16_1_1:p1 #{URN}16_1_1:p2 #{URN}16_1_1:p4], doc.map(&:urn)
      assert_equal 1, doc.metadata["pages_without_text"]
    end
  end

  def test_an_issue_without_any_page_text_is_damage
    staged do |dir|
      FileUtils.cp(File.join(ROOT, "specimens", "09_1_1.xml"), File.join(dir, "issues", "09_1_1.xml"))
      ref = adapter.discover(dir).find { |r| r.id == "#{URN}09_1_1" }
      assert_raises(Nabu::ParseError) { adapter.parse(ref) }
    end
  end

  # --- fetch (WebMock, no network) -----------------------------------------------

  def test_fetch_censuses_then_crawls_one_slice_and_ledgers_the_refusals
    Dir.mktmpdir do |dir|
      stub_census
      stub_request(:get, %r{#{Regexp.escape(BASE)}/document/}).to_return(status: 404, body: "Not Found")
      stub_issue("01_1_1", File.join(FIXTURES, "issues", "01_1_1.xml"))
      lane = adapter(slice: 3)
      report = lane.fetch(dir)
      assert File.file?(File.join(dir, "issues", "01_1_1.xml"))
      %w[CL1.html CL1.1.html CL1.6.html CL1.14.html CL1.34.html].each do |name|
        assert File.file?(File.join(dir, "map", name)), "#{name} lands in map/"
      end
      ledger = JSON.parse(File.read(File.join(dir, ".niupepa-crawl.json")))
      assert_equal %w[01_1_2 01_1_3], ledger["denied"]
      assert_match(%r{census 4 series / 304 listed documents = 301 issues \+ 3 commentaries}, report.notes)
      assert_match(/census 301 = held 1 .* reconciles/, report.notes)
      assert_equal 1, lane.discover(dir).count
    end
  end

  def test_a_held_census_is_reused_and_the_crawl_resumes
    Dir.mktmpdir do |dir|
      stub_census
      stub_request(:get, %r{#{Regexp.escape(BASE)}/document/}).to_return(status: 404, body: "Not Found")
      adapter(slice: 2).fetch(dir)
      WebMock.reset!
      stub_request(:get, %r{#{Regexp.escape(BASE)}/document/}).to_return(status: 404, body: "Not Found")
      report = adapter(slice: 2).fetch(dir)
      assert_not_requested :get, "#{BASE}/browse/CL1"
      assert_match(/held census reused/, report.notes)
      ledger = JSON.parse(File.read(File.join(dir, ".niupepa-crawl.json")))
      assert_equal 4, ledger["denied"].size, "the second slice starts where the first stopped"
    end
  end

  def test_a_truncated_listing_aborts_before_it_lands
    Dir.mktmpdir do |dir|
      stub_census(overrides: { "6" => File.join(FIXTURES, "map", "CL1.1.html") })
      error = assert_raises(Nabu::FetchError) { adapter.fetch(dir) }
      assert_match(/TRUNCATED/, error.message)
      refute File.exist?(File.join(dir, "map", "CL1.6.html"))
      assert File.file?(File.join(dir, "map", "CL1.1.html")), "the listings that passed stay held"
    end
  end

  def test_a_textless_issue_answers_no_text_and_stores_nothing
    Dir.mktmpdir do |dir|
      stub_issue("09_1_1", File.join(ROOT, "specimens", "09_1_1.xml"))
      outcome = adapter.send(:fetch_issue!, dir, "09_1_1")
      assert_equal :empty, outcome.status
      refute File.exist?(File.join(dir, "issues", "09_1_1.xml"))
    end
  end

  def test_an_answer_for_another_issue_is_denied
    Dir.mktmpdir do |dir|
      stub_issue("01_1_2", File.join(FIXTURES, "issues", "01_1_1.xml"))
      assert_equal :denied, adapter.send(:fetch_issue!, dir, "01_1_2").status
      refute File.exist?(File.join(dir, "issues", "01_1_2.xml"))
    end
  end

  def test_an_upstream_outage_aborts_the_slice_unledgered
    Dir.mktmpdir do |dir|
      stub_census
      stub_request(:get, %r{#{Regexp.escape(BASE)}/document/}).to_return(status: 503, body: "down")
      error = assert_raises(Nabu::FetchError) { adapter(slice: 5, timeout_backoff: 0).fetch(dir) }
      assert_match(/upstream outage/, error.message)
      ledger = JSON.parse(File.read(File.join(dir, ".niupepa-crawl.json")))
      assert_empty ledger["server-error"].to_a
    end
  end

  # --- idempotency + registry ------------------------------------------------------

  def test_double_load_is_idempotent
    catalog = store_test_db
    source = Nabu::Store::Source.create(slug: SLUG, name: "Niupepa", adapter_class: "Nabu::Adapters::Niupepa",
                                        license_class: "research_private")
    first = Nabu::Store::Loader.new(db: catalog, source: source)
                               .load_from(adapter, workdir: conformance_workdir, full: true)
    assert_equal 3, first.added
    assert_equal 0, first.errored
    counts = [catalog[:documents].count, catalog[:passages].count]
    assert_equal [3, 20], counts
    revisions = catalog[:documents].select_hash(:urn, :revision)
    Nabu::Store::Loader.new(db: catalog, source: source).load_from(adapter, workdir: conformance_workdir, full: true)
    assert_equal counts, [catalog[:documents].count, catalog[:passages].count]
    assert_equal revisions, catalog[:documents].select_hash(:urn, :revision)
  end

  def test_registry_resolves_niupepa_wired_and_grant_gated
    registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
    entry = registry[SLUG]
    refute_nil entry
    assert_equal ADAPTER, entry.adapter_class
    assert entry.wired, "wired after the verified first slices (134 issues / 1,313 pages, 2026-11-21)"
    assert entry.grant_required?, "a granted source arms the sync-time grant gate"
    assert entry.index_deferred?, "a paced-crawl citizen indexes once per wave"
  end

  private

  def require_fixtures!
    return if Nabu::TestSupport.local_fixtures?(SLUG)

    skip "#{SLUG} local fixtures absent (the grant forbids redistribution — bytes live in local/fixtures/, " \
         "never in git)"
  end

  # A scratch copy of the canonical fixture tree.
  def staged
    require_fixtures!
    Dir.mktmpdir("niupepa-test") do |dir|
      FileUtils.cp_r(File.join(FIXTURES, "."), dir)
      yield dir
    end
  end

  def stub_census(overrides: {})
    require_fixtures!
    stub_request(:get, "#{BASE}/browse/CL1").to_return(status: 200,
                                                       body: File.read(File.join(
                                                                         FIXTURES, "map", "CL1.html"
                                                                       )))
    %w[1 6 14 34].each do |n|
      body = File.read(overrides.fetch(n, File.join(FIXTURES, "map", "CL1.#{n}.html")))
      stub_request(:get, "#{BASE}/browse/CL1/#{n}?excerptid=divCL1.#{n}").to_return(status: 200, body: body)
    end
  end

  def stub_issue(oid, path)
    require_fixtures!
    stub_request(:get, "#{BASE}/document/#{oid}?ed=1&o=xml").to_return(status: 200, body: File.read(path))
  end
end

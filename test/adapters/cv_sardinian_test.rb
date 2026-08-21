# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# CvSardinian adapter tests (P80-6): the Common Voice Sardinian sentence
# text — server/data/sc/sentence-collector.txt in the common-voice repo
# (5,237 sentences censused 2026-08-19), CC0 (server/data/LICENSE is the
# full CC0 1.0 text — the TEXT side only, no audio, ever). The fixtures
# pin the line-number identity, the no-trailing-newline tail (the final
# sentence must still mint a passage), and the idempotent double-load.
# No network: fetch runs against a WebMock stub of the real raw URL.
class CvSardinianTest < Minitest::Test
  include AdapterConformance
  include StoreTestDB

  FIXTURES = Nabu::TestSupport.fixtures("cv-sardinian")

  URL = "https://raw.githubusercontent.com/common-voice/common-voice/" \
        "main/server/data/sc/sentence-collector.txt"
  URN = "urn:nabu:cv-sardinian:sentence-collector"

  def conformance_adapter
    Nabu::Adapters::CvSardinian.new
  end

  def conformance_workdir
    FIXTURES
  end

  def conformance_expected_source_id
    "cv-sardinian"
  end

  # --- manifest ---------------------------------------------------------------

  def test_manifest_identifies_the_cv_sardinian_source
    manifest = Nabu::Adapters::CvSardinian.manifest
    assert_equal "cv-sardinian", manifest.id
    assert_match(/CC0 1\.0/, manifest.license, "server/data/LICENSE is the full CC0 text")
    assert_match(/text side only/i, manifest.license, "the no-audio-ever scope travels with the grant")
    assert_equal "open", manifest.license_class
    assert_equal "https://github.com/common-voice/common-voice", manifest.upstream_url
    assert_equal "sentence-lines", manifest.parser_family
  end

  # --- discover ---------------------------------------------------------------

  def test_discover_mints_the_one_sentence_collector_ref
    refs = Nabu::Adapters::CvSardinian.new.discover(FIXTURES).to_a
    assert_equal [URN], refs.map(&:id)
    assert_equal "cv-sardinian", refs.first.source_id
  end

  def test_discover_of_an_unfetched_workdir_yields_nothing
    Dir.mktmpdir do |dir|
      assert_empty Nabu::Adapters::CvSardinian.new.discover(dir).to_a
    end
  end

  # --- parse ------------------------------------------------------------------

  def test_parse_mints_one_sardinian_passage_per_line_numbered_from_one
    document = parse_document
    assert_equal "srd", document.language
    assert_equal 11, document.size
    assert_equal %w[1 2 3 4 5 6 7 8 9 10 11], document.map { |p| p.urn.split(":").last },
                 "identity is the 1-based line number — upstream ships no sentence ids"
    assert_equal (0..10).to_a, document.map(&:sequence)
  end

  def test_passage_text_is_the_sentence_verbatim
    passage = parse_document.first
    assert_equal "\"Fortza Vitzi, fortza Sardigna\" est su messàgiu publicadu in is canales sotziales.",
                 passage.text
  end

  def test_the_final_line_without_trailing_newline_still_mints_a_passage
    document = parse_document
    assert_equal "Ùndighi.", document.to_a.last.text,
                 "the artifact ends without a newline (censused) — the last sentence is real"
  end

  # --- parse: damage is loud --------------------------------------------------

  def test_malformed_utf8_raises_parse_error
    Dir.mktmpdir do |dir|
      File.binwrite(File.join(dir, "sentence-collector.txt"), "bona\n\xFFmala\n".b)
      adapter = Nabu::Adapters::CvSardinian.new
      ref = adapter.discover(dir).first
      refute_nil ref
      error = assert_raises(Nabu::ParseError) { adapter.parse(ref) }
      assert_match(/line 2/, error.message)
    end
  end

  def test_an_empty_file_raises_parse_error
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "sentence-collector.txt"), "\n\n")
      adapter = Nabu::Adapters::CvSardinian.new
      ref = adapter.discover(dir).first
      assert_raises(Nabu::ParseError) { adapter.parse(ref) }
    end
  end

  # --- fetch (WebMock only, no network) ---------------------------------------

  def test_fetch_downloads_the_sentence_file_via_file_fetch
    stub_request(:get, URL).to_return(
      status: 200, body: File.binread(File.join(FIXTURES, "sentence-collector.txt")),
      headers: { "Content-Type" => "text/plain" }
    )
    Dir.mktmpdir do |workdir|
      adapter = Nabu::Adapters::CvSardinian.new
      report = adapter.fetch(workdir)
      assert_instance_of Nabu::FetchReport, report
      assert_match(/\A\h{64}\z/, report.sha)
      assert_equal [URN], adapter.discover(workdir).map(&:id),
                   "the file lands in place and discover sees it"
    end
  end

  def test_fetch_wraps_http_failure_in_fetch_error
    stub_request(:get, URL).to_return(status: 500)
    Dir.mktmpdir do |workdir|
      assert_raises(Nabu::FetchError) { Nabu::Adapters::CvSardinian.new.fetch(workdir) }
    end
  end

  # --- remote-health probe shape ----------------------------------------------

  def test_probe_heads_the_raw_url
    assert_equal :http_zip, Nabu::Adapters::CvSardinian.remote_probe_strategy
    targets = Nabu::Adapters::CvSardinian.http_probe_targets
    assert_equal [URL], targets.map(&:zip_url)
    assert_equal [""], targets.map(&:state_subdir)
    assert_equal [Nabu::FileFetch::STATE_FILE], targets.map(&:state_file).uniq
    assert(targets.all? { |t| t.metadata_url.nil? },
           "the license lives in server/data/LICENSE, no probe-shaped endpoint")
  end

  # --- store: idempotent double-load ------------------------------------------

  def test_loads_idempotently_into_the_store
    catalog = store_test_db
    source = create_source
    adapter = Nabu::Adapters::CvSardinian.new
    first = Nabu::Store::Loader.new(db: catalog, source: source)
                               .load_from(adapter, workdir: FIXTURES, full: true)
    assert_equal 1, first.added
    assert_equal 0, first.errored
    assert_equal 11, catalog[:passages].count

    second = Nabu::Store::Loader.new(db: catalog, source: source)
                                .load_from(adapter, workdir: FIXTURES, full: true)
    assert_equal 0, second.errored
    assert_equal 1, second.skipped, "a byte-identical reload skips the document"
    assert_equal [1], catalog[:passages].distinct.select_map(:revision),
                 "a byte-identical reload bumps no revisions"
  end

  # --- registry round-trip ----------------------------------------------------

  def test_registry_resolves_cv_sardinian_and_manifest_agrees
    registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
    entry = registry["cv-sardinian"]
    refute_nil entry, "cv-sardinian must be registered in config/sources.yml"
    assert_equal Nabu::Adapters::CvSardinian, entry.adapter_class
    assert entry.wired, "flipped 2026-08-21 — first sync owner-round-verified (5,237 sentences)"
    assert_equal Nabu::Adapters::CvSardinian.manifest, entry.manifest
  end

  private

  def parse_document
    adapter = Nabu::Adapters::CvSardinian.new
    ref = adapter.discover(FIXTURES).first
    refute_nil ref
    adapter.parse(ref)
  end

  def create_source
    Nabu::Store::Source.create(slug: "cv-sardinian", name: "Common Voice Sardinian text",
                               adapter_class: "Nabu::Adapters::CvSardinian",
                               license_class: "open")
  end
end

# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "json"
require "fileutils"

# VKS adapter tests: Vanhan kirjasuomen korpus (Kotus via Kielipankki Korp,
# EUPL v1.2) — one document per landed Korp text file. Fixtures: four texts
# in the KorpFetch landing shape built from real kwic rows recorded
# 2026-10-21 (Agricola's Abckiria whole, Frosterus' opening, John 19–21 of
# the 1642 Bible, a decree window crossing 1805→1806), plus the recorded
# API responses the fetch tests stub. No network.
class VksTest < Minitest::Test
  include AdapterConformance

  FIXTURES = Nabu::TestSupport.fixtures("vks")
  BASE = "https://www.kielipankki.fi/korp/api8"
  DOC_URNS = %w[urn:nabu:vks:agricola.agri1_abc1543 urn:nabu:vks:biblia.ut1_ev urn:nabu:vks:frosterus.jafro1791
                urn:nabu:vks:lait.as1800].freeze

  # The adapter with the harvest narrowed to the two recorded corpora.
  class NarrowVks < Nabu::Adapters::Vks
    private

    def fetch_options = { corpora: %w[VKS_FROSTERUS VKS_LPETRI], page_size: 2, pause: 0 }
  end

  def conformance_adapter = Nabu::Adapters::Vks.new
  def conformance_workdir = FIXTURES
  def conformance_expected_source_id = "vks"

  def test_manifest_records_the_eupl_grant_and_its_share_alike_rider
    manifest = Nabu::Adapters::Vks.manifest
    assert_equal "vks", manifest.id
    assert_equal "attribution", manifest.license_class, "the 2026-10-21 ruling: EUPL → attribution + share-alike"
    assert_match(/EUPL v\. 1\.2/, manifest.license)
    assert_match(/Euroopan unionin yleinen lisenssi v\. 1\.2 \(EUPL\)/, manifest.license)
    assert_match(/share-alike/, manifest.license)
    assert_equal "korp-jsonl", manifest.parser_family
  end

  def test_discover_mints_one_ref_per_landed_text
    assert_equal DOC_URNS, Nabu::Adapters::Vks.new.discover(FIXTURES).map(&:id)
  end

  def test_a_corpus_outside_the_scope_is_unrecognized
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "texts", "VKS_ELSEWHERE"))
      skips = Nabu::Adapters::Vks.new.discovery_skips(dir)
      assert_equal 1, skips.unrecognized
      assert_equal ["corpus outside the VKS scope: VKS_ELSEWHERE"], skips.notes
    end
    assert_equal 0, Nabu::Adapters::Vks.new.discovery_skips(FIXTURES).unrecognized
  end

  def test_text_metadata_mines_title_author_date_and_facsimile
    metadata = parse_urn("urn:nabu:vks:agricola.agri1_abc1543").metadata
    assert_equal "Mikael Agricola", metadata["author"]
    assert_equal 1543, metadata.dig("date", "not_before")
    assert_match(/näköispainos/, metadata["facsimile"])
    assert_equal "VKS_AGRICOLA", metadata["korp_corpus"]
  end

  def test_a_bible_title_names_no_author
    document = parse_urn("urn:nabu:vks:biblia.ut1_ev")
    refute document.metadata.key?("author"), "\"Biblia, Se on: …\" is a title, not an author head"
    assert_equal 1642, document.metadata.dig("date", "not_after")
  end

  def test_a_collection_file_dates_by_its_elements_envelope
    metadata = parse_urn("urn:nabu:vks:lait.as1800").metadata
    assert_equal({ "not_before" => 1805, "not_after" => 1806 }, metadata["date"].slice("not_before", "not_after"))
    assert_equal ["As"], metadata["text_authors"]
  end

  def test_passages_are_finnish_and_cite_the_corpus_codes
    document = parse_urn("urn:nabu:vks:biblia.ut1_ev")
    assert(document.all? { |p| p.language == "fi" })
    assert_equal "urn:nabu:vks:biblia.ut1_ev:Jh-19.38-623c", document.first.urn
  end

  def test_fetch_harvests_and_discovers
    stub_api
    Dir.mktmpdir do |workdir|
      adapter = NarrowVks.new
      report = adapter.fetch(workdir)
      assert_match(/\A\h{64}\z/, report.sha)
      assert_includes report.notes, "harvested 6 sentences / 2 texts"
      assert_equal %w[urn:nabu:vks:frosterus.jafro1791 urn:nabu:vks:lpetri.lpet1644a],
                   adapter.discover(workdir).map(&:id)
    end
  end

  def test_fetch_wraps_api_failure_in_fetch_error
    stub_request(:get, "#{BASE}/corpus_info").with(query: hash_including({})).to_return(status: 503)
    Dir.mktmpdir { |workdir| assert_raises(Nabu::FetchError) { NarrowVks.new.fetch(workdir) } }
  end

  def test_probe_checks_the_api_liveness_only
    targets = Nabu::Adapters::Vks.http_probe_targets
    assert_equal 1, targets.size
    assert targets.first.liveness_only
    assert_match(%r{/korp/api8/corpus_info\?corpus=VKS_AGRICOLA,}, targets.first.zip_url)
  end

  def test_registry_resolves_vks_and_manifest_agrees
    registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
    entry = registry["vks"]
    refute_nil entry, "vks must be registered in config/sources.yml"
    assert_equal Nabu::Adapters::Vks, entry.adapter_class
    assert_equal Nabu::Adapters::Vks.manifest, entry.manifest
    refute entry.wired, "wired: false until the first real harvest is verified"
  end

  private

  def parse_urn(urn)
    adapter = Nabu::Adapters::Vks.new
    ref = adapter.discover(FIXTURES).find { |r| r.id == urn }
    refute_nil ref, "expected discover to yield #{urn}"
    adapter.parse(ref)
  end

  def recorded(name) = JSON.parse(File.read(File.join(FIXTURES, "korp", name)))

  # The recorded pages verbatim; the corpus totals restated to the six
  # sentences served (see test/korp_fetch_test.rb).
  def stub_api
    info = recorded("corpus_info.json")
    info["corpora"]["VKS_FROSTERUS"]["info"]["Sentences"] = "4"
    info["corpora"]["VKS_LPETRI"]["info"]["Sentences"] = "2"
    stub_request(:get, "#{BASE}/corpus_info").with(query: hash_including({}))
                                             .to_return(status: 200, body: JSON.generate(info))
    { ["VKS_FROSTERUS", 0] => ["query_frosterus_0-1.json", 4], ["VKS_FROSTERUS", 2] => ["query_frosterus_2-3.json", 4],
      ["VKS_LPETRI", 0] => ["query_lpetri_0-1.json", 2] }.each do |(corpus, start), (file, total)|
      stub_request(:get, "#{BASE}/query")
        .with(query: hash_including("corpus" => corpus, "start" => start.to_s))
        .to_return(status: 200, body: JSON.generate(recorded(file).merge("hits" => total)))
    end
  end
end

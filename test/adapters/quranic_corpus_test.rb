# frozen_string_literal: true

require "test_helper"
require "digest"
require "fileutils"
require "tmpdir"

# Nabu::Adapters::QuranicCorpus — the Quranic Arabic Corpus morphology
# v0.4 (Kais Dukes, University of Leeds) as one document per sura, one
# passage per verse, one token per segment. Includes the shared
# AdapterConformance suite against the trimmed real file (both copyright
# blocks + the column header verbatim, suras 1, 109 and 112 whole). No
# network: fetch runs against WebMock.
class QuranicCorpusTest < Minitest::Test
  include AdapterConformance

  ADAPTER = Nabu::Adapters::QuranicCorpus
  FIXTURES = Nabu::TestSupport.fixtures("quranic-corpus")
  FILE = File.join(FIXTURES, "quranic-corpus-morphology-0.4.txt")
  URL = "https://raw.githubusercontent.com/q-ran/quran/8abbbb2942f4479a8f314c04192d0c6f575ead15/" \
        "sources/1.0/quranic-corpus-morphology-0.4.txt"
  URNS = %w[urn:nabu:quranic-corpus:1 urn:nabu:quranic-corpus:109 urn:nabu:quranic-corpus:112].freeze

  def conformance_adapter = ADAPTER.new

  def conformance_workdir = FIXTURES

  def conformance_expected_source_id = "quranic-corpus"

  def adapter = ADAPTER.new

  def document(urn)
    a = adapter
    a.parse(a.discover(FIXTURES).find { |ref| ref.id == urn })
  end

  def verse(urn) = document(urn.sub(/:\d+\z/, "")).find { |p| p.urn == urn }

  # --- manifest ---------------------------------------------------------------

  def test_manifest_records_the_terms_verbatim_and_the_strict_class
    manifest = ADAPTER.manifest
    assert_equal "quranic-corpus", manifest.id
    assert_equal "research_private", manifest.license_class
    assert_includes manifest.license, "Permission is granted to copy and distribute verbatim copies " \
                                      "of this file, but CHANGING IT IS NOT ALLOWED."
    assert_includes manifest.license, "License: GNU General Public License"
    assert_includes manifest.license, "Creative Commons BY-ND 3.0 Unported"
    assert_includes manifest.credit, "Quranic Arabic Corpus"
    assert_includes manifest.credit, "http://corpus.quran.com"
    assert_includes manifest.credit, "http://tanzil.info"
    assert_equal "quranic-corpus-tsv", manifest.parser_family
    assert_equal URL, ADAPTER::FILE_URL
  end

  def test_nothing_is_materialized_beside_the_fetched_file
    assert_empty ADAPTER.materialized_paths
  end

  # --- discover ---------------------------------------------------------------

  def test_discover_mints_one_ref_per_sura
    refs = adapter.discover(FIXTURES).to_a
    assert_equal URNS, refs.map(&:id)
    assert(refs.all? { |ref| ref.source_id == "quranic-corpus" && ref.path == File.expand_path(FILE) })
    assert_equal([1, 109, 112], refs.map { |ref| ref.metadata.fetch("sura") })
  end

  def test_discover_of_an_unfetched_workdir_yields_nothing
    Dir.mktmpdir { |dir| assert_empty adapter.discover(dir).to_a }
  end

  def test_a_sura_out_of_upstream_order_is_a_loud_parse_error
    Dir.mktmpdir do |dir|
      lines = File.binread(FILE).lines
      verse7 = lines.select { |l| l.start_with?("(1:7:") }
      File.binwrite(File.join(dir, ADAPTER::FILENAME), (lines - verse7 + verse7).join)
      error = assert_raises(Nabu::ParseError) { adapter.discover(dir).to_a }
      assert_match(/sura 1 is not contiguous/, error.message)
    end
  end

  def test_the_fixture_tree_holds_no_skips_and_a_stray_file_is_unrecognized
    skips = adapter.discovery_skips(FIXTURES)
    assert_equal [0, 0], [skips.skipped_by_rule, skips.unrecognized], "README/manifest are fixture furniture"
    Dir.mktmpdir do |dir|
      FileUtils.cp(FILE, dir)
      File.write(File.join(dir, Nabu::FileFetch::STATE_FILE), "{}")
      File.write(File.join(dir, "quran-uthmani.xml"), "<quran/>")
      skips = adapter.discovery_skips(dir)
      assert_equal 0, skips.skipped_by_rule
      assert_equal 1, skips.unrecognized, "the FileFetch state file is bookkeeping, never counted"
      assert(skips.notes.any? { |note| note.include?("quran-uthmani.xml") })
    end
  end

  # --- parse ------------------------------------------------------------------

  def test_a_sura_document_is_titled_and_carries_its_metadata
    doc = document("urn:nabu:quranic-corpus:1")
    assert_equal "ara-Latn", doc.language
    assert_equal "Sura 1 — Al-Faatiha (The Opening)", doc.title
    assert_equal({ "sura" => 1, "work" => "Quran", "sura_name" => "Al-Faatiha",
                   "sura_name_en" => "The Opening", "revelation_type" => "Meccan" }, doc.metadata)
    assert_equal "Sura 112 — Al-Ikhlaas (Sincerity)", document("urn:nabu:quranic-corpus:112").title
  end

  def test_passages_are_the_verses_cited_by_verse_number
    assert_equal (1..7).map { |n| "urn:nabu:quranic-corpus:1:#{n}" }, document("urn:nabu:quranic-corpus:1").map(&:urn)
    assert_equal 6, document("urn:nabu:quranic-corpus:109").size
    assert_equal 4, document("urn:nabu:quranic-corpus:112").size
  end

  def test_verse_text_is_upstreams_forms_verbatim
    assert_equal "bisomi {ll~ahi {lr~aHoma`ni {lr~aHiymi", verse("urn:nabu:quranic-corpus:1:1").text
    assert_equal "qulo huwa {ll~ahu >aHadN", verse("urn:nabu:quranic-corpus:112:1").text
    assert_equal "lakumo diynukumo waliYa diyni", verse("urn:nabu:quranic-corpus:109:6").text,
                 "the empty-FORM suffix adds nothing"
  end

  def test_tokens_are_the_segments_with_tag_lemma_root_and_features
    tokens = verse("urn:nabu:quranic-corpus:1:1").annotations.fetch("tokens")
    assert_equal(%w[1:1:1:1 1:1:1:2 1:1:2:1 1:1:3:1 1:1:3:2 1:1:4:1 1:1:4:2], tokens.map { |t| t["id"] })
    assert_equal({ "id" => "1:1:3:2", "form" => "r~aHoma`ni", "tag" => "ADJ",
                   "features" => "STEM|POS:ADJ|LEM:r~aHoma`n|ROOT:rHm|MS|GEN",
                   "lemma" => "r~aHoma`n", "root" => "rHm" }, tokens[4])
    assert_equal tokens.map { |t| t["form"] }.join, verse("urn:nabu:quranic-corpus:1:1").text.delete(" ")
  end

  def test_the_stored_text_is_ascii_so_nfc_is_a_no_op
    %w[1 109 112].each do |sura|
      document("urn:nabu:quranic-corpus:#{sura}").each do |passage|
        assert passage.text.ascii_only?, passage.urn
        assert_equal passage.text, Nabu::Normalize.nfc(passage.text), passage.urn
      end
    end
  end

  def test_the_whole_fixture_row_census
    docs = adapter.discover(FIXTURES).map { |ref| adapter.parse(ref) }
    assert_equal 17, docs.sum(&:size)
    assert_equal(105, docs.sum { |doc| doc.sum { |p| p.annotations["tokens"].size } })
  end

  # The Tanzil metadata's per-sura verse count is the reconciliation guard:
  # a sura whose verses do not run 1..N for its N is a different file.
  def test_a_sura_short_of_its_verse_count_is_a_parse_error
    Dir.mktmpdir do |dir|
      lines = File.binread(FILE).lines.reject { |l| l.start_with?("(112:4:") }
      File.binwrite(File.join(dir, ADAPTER::FILENAME), lines.join)
      a = adapter
      ref = a.discover(dir).find { |r| r.id.end_with?(":112") }
      error = assert_raises(Nabu::ParseError) { a.parse(ref) }
      assert_match(/sura 112: verses 1\.\.3, expected 1\.\.4/, error.message)
    end
  end

  def test_the_sura_table_is_the_whole_quran
    table = Nabu::Adapters::QuranicCorpusSuras::TABLE
    assert_equal (1..114).to_a, table.keys
    assert_equal 6236, table.values.sum(&:first)
    assert_equal %w[Meccan Medinan], table.values.map(&:last).uniq.sort
  end

  # --- dating: the ruled per-work era ------------------------------------------

  def test_the_timeline_reads_the_work_era_row
    assert_equal :work_era, Nabu::Store::TimelineBuilder::MetadataDates::SHAPES.fetch("quranic-corpus")
    eras = Nabu::WorkEras.default
    assert_equal "work", eras.key_for("quranic-corpus")
    assert_equal [610, 632], eras.lookup("quranic-corpus", "Quran").band
  end

  # --- registry ----------------------------------------------------------------

  def test_registry_row_is_unwired_and_manual
    entry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources", __dir__))["quranic-corpus"]
    refute_nil entry, "config/sources/ must register quranic-corpus"
    assert_equal ADAPTER, entry.adapter_class
    refute entry.wired, "wired only after the verified first sync"
    assert_equal "manual", entry.sync_policy
  end

  # --- fetch (WebMock only) ---------------------------------------------------

  def body = @body ||= File.binread(FILE)

  def test_fetch_lands_the_file_byte_for_byte_and_verifies_the_pin
    stub_request(:get, URL).to_return(status: 200, body: body)
    Dir.mktmpdir do |dir|
      report = ADAPTER.new(sha256: Digest::SHA256.hexdigest(body)).fetch(dir)
      assert_equal body, File.binread(File.join(dir, ADAPTER::FILENAME))
      assert_equal Digest::SHA256.hexdigest(body), report.sha
    end
  end

  def test_fetch_refuses_a_different_file_with_the_tree_untouched
    stub_request(:get, URL).to_return(status: 200, body: body)
    Dir.mktmpdir do |dir|
      error = assert_raises(Nabu::FetchError) { ADAPTER.new.fetch(dir) }
      assert_match(/sha256.*re-pin/, error.message)
      refute File.exist?(File.join(dir, ADAPTER::FILENAME))
    end
  end

  def test_the_pin_and_the_census_are_the_fixture_readmes
    readme = File.read(File.join(FIXTURES, "README.md"))
    assert_includes readme, ADAPTER::FILE_SHA256
    assert_includes readme, ADAPTER::COMMIT_SHA
    %w[6,236 77,429 128,219 4,832 1,642].each { |figure| assert_includes readme, figure }
  end
end

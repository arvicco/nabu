# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

# SCAT adapter tests: the St. Petersburg Corpus of Hagiographic Texts
# (vintagentleman/scat-content release 1.2.0, CC BY-SA 4.0) — 24 Russian
# saints' lives of the 16th–18th c. in TEI, one document per text, one
# passage per folio side. Fixtures: three trimmed real release files (one
# per century slice), the release's metadata.csv cut to their rows, and one
# real specimen of each rejected TXM-portal grain. No network: fetch runs
# against a WebMock stub of the release-asset URL.
class ScatTest < Minitest::Test
  include AdapterConformance

  FIXTURES = Nabu::TestSupport.fixtures("scat")
  ZIP_URL = "https://github.com/vintagentleman/scat-content/releases/download/1.2.0/scat-content-120.zip"

  DOC_URNS = %w[urn:nabu:scat:akush urn:nabu:scat:dmprlc urn:nabu:scat:thdttm].freeze

  def conformance_adapter = Nabu::Adapters::Scat.new
  def conformance_workdir = FIXTURES
  def conformance_expected_source_id = "scat"

  # --- manifest -----------------------------------------------------------------

  def test_manifest_records_the_share_alike_grant_and_credit
    manifest = Nabu::Adapters::Scat.manifest
    assert_equal "scat", manifest.id
    assert_equal "attribution", manifest.license_class, "CC BY-SA 4.0 — the share-alike glaux precedent"
    assert_match(/CC BY-SA 4\.0/, manifest.license)
    assert_match(/St\. Petersburg Corpus of Hagiographic Texts/, manifest.license)
    assert_match(/scat-content/, manifest.upstream_url)
    assert_equal "scat-tei", manifest.parser_family
  end

  # --- discover -------------------------------------------------------------------

  def test_discover_mints_one_ref_per_tei_text
    refs = Nabu::Adapters::Scat.new.discover(FIXTURES).to_a
    assert_equal DOC_URNS, refs.map(&:id)
    assert(refs.all? { |r| r.metadata["language"] == "chu" })
  end

  def test_discover_reads_the_release_catalog
    ref = Nabu::Adapters::Scat.new.discover(FIXTURES).find { |r| r.id == "urn:nabu:scat:dmprlc" }
    assert_equal "Житие Димитрия Прилуцкого", ref.metadata["title"]
    assert_equal "16", ref.metadata["century"]
    assert_equal true, ref.metadata["morphology"]
    assert_equal true, ref.metadata["text_structure"]
  end

  def test_the_rejected_txm_portal_grains_skip_by_rule
    skips = Nabu::Adapters::Scat.new.discovery_skips(FIXTURES)
    assert_equal 3, skips.skipped_by_rule,
                 "Documentation.jsp, css/SCAT.css, the xsl stylesheet — TXM portal furniture, never text"
    assert_equal 0, skips.unrecognized
    assert(skips.notes.any? { |n| n.include?("Documentation.jsp") })
    assert(skips.notes.any? { |n| n.include?("css/SCAT.css") })
  end

  def test_a_catalog_row_without_its_tei_is_unrecognized
    Dir.mktmpdir do |dir|
      FileUtils.cp(File.join(FIXTURES, "metadata.csv"), dir)
      FileUtils.cp(File.join(FIXTURES, "AKush.xml"), dir)
      skips = Nabu::Adapters::Scat.new.discovery_skips(dir)
      assert_equal 2, skips.unrecognized, "DmPrlc + ThdTtm advertised by the catalog, absent from the tree"
      assert(skips.notes.any? { |n| n.include?("DmPrlc") })
    end
  end

  def test_discover_of_an_unfetched_workdir_yields_nothing
    Dir.mktmpdir { |dir| assert_empty Nabu::Adapters::Scat.new.discover(dir).to_a }
  end

  # --- parse ----------------------------------------------------------------------------

  def test_parse_yields_one_passage_per_folio_side
    document = parse_urn("urn:nabu:scat:akush")
    assert_equal(%w[f.371r f.371v f.372r], document.map { |p| p.urn.split(":").last })
    assert(document.all? { |p| p.language == "chu" })
    assert_equal "Житие Александра Куштского", document.title
  end

  def test_the_century_becomes_a_dated_envelope
    metadata = parse_urn("urn:nabu:scat:thdttm").metadata
    assert_equal({ "not_before" => 1701, "not_after" => 1800, "raw" => "18th century (SCAT catalog)" },
                 metadata["date"])
    assert_equal "18", metadata["century"]
  end

  def test_passage_text_is_the_manuscript_surface
    first = parse_urn("urn:nabu:scat:akush").first
    assert first.text.start_with?(Nabu::Normalize.nfc("м҇ⷭца июнѧ, въ ѳ҃ ⷣⷩꙺ. житїе и подвизи"))
  end

  def test_annotated_texts_carry_lemma_tokens
    tokens = parse_urn("urn:nabu:scat:dmprlc").first.annotations["tokens"]
    assert_equal "месяць", tokens.first["lemma"]
  end

  def test_page_annotations_carry_folio_corrections_and_quotations
    page = parse_urn("urn:nabu:scat:dmprlc").find { |p| p.urn.end_with?(":f.202r") }
    assert_equal "202", page.annotations["folio"]
    assert_equal [Nabu::Normalize.nfc("растѧщѹ")], page.annotations["corrections"]
    assert_includes page.annotations["quotations"], { "source" => "BQ:LUK11:20", "type" => "modified" }
  end

  def test_a_repeated_folio_label_keeps_both_sides
    urns = parse_urn("urn:nabu:scat:thdttm").map { |p| p.urn.split(":").last }
    assert_equal %w[f.51v f.52r f.52v f.53r f.53r.2], urns
  end

  # --- fetch (WebMock only, no network) ---------------------------------------------------

  def test_fetch_downloads_and_unpacks_the_release_zip
    stub_zip
    Dir.mktmpdir do |workdir|
      adapter = Nabu::Adapters::Scat.new
      report = adapter.fetch(workdir)
      assert_match(/\A\h{64}\z/, report.sha)
      assert_equal DOC_URNS, adapter.discover(workdir).map(&:id)
    end
  end

  def test_fetch_wraps_http_failure_in_fetch_error
    stub_request(:get, ZIP_URL).to_return(status: 500)
    Dir.mktmpdir do |workdir|
      assert_raises(Nabu::FetchError) { Nabu::Adapters::Scat.new.fetch(workdir) }
    end
  end

  def test_probe_heads_the_release_asset
    assert_equal :http_zip, Nabu::Adapters::Scat.remote_probe_strategy
    targets = Nabu::Adapters::Scat.http_probe_targets
    assert_equal [ZIP_URL], targets.map(&:zip_url)
  end

  # --- registry round-trip -----------------------------------------------------------------

  def test_registry_resolves_scat_and_manifest_agrees
    registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
    entry = registry["scat"]
    refute_nil entry, "scat must be registered in config/sources.yml"
    assert_equal Nabu::Adapters::Scat, entry.adapter_class
    assert_equal Nabu::Adapters::Scat.manifest, entry.manifest
    assert entry.wired, "live: first sync verified 2026-10-20 (24 docs / 2,446 passages)"
  end

  private

  def parse_urn(urn)
    adapter = Nabu::Adapters::Scat.new
    ref = adapter.discover(FIXTURES).find { |r| r.id == urn }
    refute_nil ref, "expected discover to yield #{urn}"
    adapter.parse(ref)
  end

  # The release zip is flat (texts + metadata.csv + TXM furniture at the
  # root) — the fixture tree zipped as-is.
  def stub_zip
    Dir.mktmpdir do |dir|
      zip_path = File.join(dir, "scat-content-120.zip")
      Nabu::Shell.run("zip", "-q", "-r", zip_path, ".", "-x", "README.md", "manifest.yml", chdir: FIXTURES)
      stub_request(:get, ZIP_URL).to_return(
        status: 200, body: File.binread(zip_path),
        headers: { "Content-Type" => "application/zip", "Last-Modified" => "Sun, 24 Oct 2021 08:36:43 GMT" }
      )
    end
  end
end

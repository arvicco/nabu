# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# Imp adapter tests (P13-9): the IMP digital library and corpus of
# historical Slovene (CLARIN.SI hdl 11356/1031, CC BY-SA 4.0) — goo300k's
# full-text SILVER sibling on the same imp-tei family. The fixtures pin the
# owner's silver decision (text only — the automatic reg/lemma/MSD layer is
# NOT ingested, no lemma-index rows), the per-tag counter citations
# (un-id'd <p>/<head>), and the alt-edition relationship to goo300k (same
# upstream sigil, distinct source urns). No network: fetch runs against a
# WebMock stub of the real CLARIN.SI bitstream URL.
class ImpTest < Minitest::Test
  include AdapterConformance

  FIXTURES = Nabu::TestSupport.fixtures("imp")

  ZIP_URL = "https://www.clarin.si/repository/xmlui/bitstream/handle/11356/1031/IMP-corpus-tei.zip"

  DOC_URNS = %w[
    urn:nabu:imp:wiki00290-1855
    urn:nabu:imp:zrc_00001-1584
  ].freeze

  def conformance_adapter
    Nabu::Adapters::Imp.new
  end

  def conformance_workdir
    FIXTURES
  end

  def conformance_expected_source_id
    "imp"
  end

  # --- manifest ---------------------------------------------------------------

  def test_manifest_identifies_the_imp_source
    manifest = Nabu::Adapters::Imp.manifest
    assert_equal "imp", manifest.id
    assert_match(/CC BY-SA 4\.0/, manifest.license)
    assert_match(/Creative Commons - Attribution-ShareAlike 4\.0 International/, manifest.license,
                 "the deposit-page grant, verbatim")
    assert_equal "attribution", manifest.license_class
    assert_equal ZIP_URL, manifest.upstream_url
    assert_equal "imp-tei", manifest.parser_family
  end

  # --- discover ---------------------------------------------------------------

  def test_discover_mints_one_ref_per_ana_file
    refs = Nabu::Adapters::Imp.new.discover(FIXTURES).to_a
    assert_equal DOC_URNS, refs.map(&:id), "sigil-year identity, lowercased, sorted"
    assert(refs.all? { |r| r.source_id == "imp" && r.metadata["language"] == "sl" })
  end

  def test_discover_titles_come_from_the_sourcedesc_bibl
    titles = Nabu::Adapters::Imp.new.discover(FIXTURES).to_h { |r| [r.id, r.metadata["title"]] }
    assert_equal "Kaznovana tercialka — Jenko, Simon, 1855", titles["urn:nabu:imp:wiki00290-1855"]
    assert_equal "Biblija (vzorec) — Dalmatin, Jurij, 1584", titles["urn:nabu:imp:zrc_00001-1584"]
  end

  def test_discover_of_an_unfetched_workdir_yields_nothing
    Dir.mktmpdir do |dir|
      assert_empty Nabu::Adapters::Imp.new.discover(dir).to_a
    end
  end

  # --- parse: the silver decision -----------------------------------------------

  def test_parse_yields_text_only_passages_with_counter_citations
    document = parse_urn("urn:nabu:imp:zrc_00001-1584")
    assert_equal %w[head.1 p.1 p.2], document.map { |p| p.urn.split(":").last },
                 "IMP's <head>/<p> carry no xml:ids — per-tag document-order counters"
    assert(document.all? { |p| !p.annotations.key?("tokens") },
           "the automatic annotation layer is NOT ingested (owner decision 2026-07-11): " \
           "no tokens, hence no passage_lemmas rows — the lemma index stays gold-only")
    assert_equal(%w[pb.001 pb.001 pb.001], document.map { |p| p.annotations["page"] })
  end

  def test_the_full_text_is_the_alt_edition_of_the_goo300k_sample
    document = parse_urn("urn:nabu:imp:zrc_00001-1584")
    assert_equal "X. CAP.", document.find { |p| p.urn.end_with?(":head.1") }.text
    assert document.find { |p| p.urn.end_with?(":p.1") }.text.start_with?("INu on je ſvoje dvanajſt Iogre"),
           "the same Dalmatin 1584 Biblia goo300k samples — distinct source urn, " \
           "alt-edition by design (conventions §3), never a dedupe"
  end

  def test_parse_the_post_bohoric_document
    document = parse_urn("urn:nabu:imp:wiki00290-1855")
    assert_equal 1, document.size
    passage = document.first
    assert_equal "urn:nabu:imp:wiki00290-1855:p.1", passage.urn
    assert passage.text.start_with?("Neka tercjalka je študente, ki so pri nji stanovali,")
    assert_includes passage.text, "v cerkev šla."
    assert_includes passage.text_normalized, "neka tercjalka je studente",
                    "haček letters fall to the generic mark strip"
  end

  # --- fetch (WebMock only, no network) --------------------------------------------

  def test_fetch_downloads_and_unpacks_the_single_zip
    stub_zip
    Dir.mktmpdir do |workdir|
      adapter = Nabu::Adapters::Imp.new
      report = adapter.fetch(workdir)
      assert_instance_of Nabu::FetchReport, report
      assert_match(/\A\h{64}\z/, report.sha)
      assert_equal DOC_URNS, adapter.discover(workdir).map(&:id),
                   "the unpacked tree is discoverable in place"
    end
  end

  def test_fetch_wraps_http_failure_in_fetch_error
    stub_request(:get, ZIP_URL).to_return(status: 500)
    Dir.mktmpdir do |workdir|
      assert_raises(Nabu::FetchError) { Nabu::Adapters::Imp.new.fetch(workdir) }
    end
  end

  # --- remote-health probe shape -------------------------------------------------------

  def test_probe_heads_the_bitstream_with_no_metadata_endpoint
    assert_equal :http_zip, Nabu::Adapters::Imp.remote_probe_strategy
    targets = Nabu::Adapters::Imp.http_probe_targets
    assert_equal 1, targets.size
    assert_equal ZIP_URL, targets[0].zip_url
    assert_nil targets[0].metadata_url
    assert_equal Nabu::ZipFetch::STATE_FILE, targets[0].state_file
  end

  # --- registry round-trip ----------------------------------------------------------------

  def test_registry_resolves_imp_and_manifest_agrees
    registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
    entry = registry["imp"]
    refute_nil entry, "imp must be registered in config/sources.yml"
    assert_equal Nabu::Adapters::Imp, entry.adapter_class
    refute entry.enabled, "imp stays disabled until the owner-fired first real sync (150 MB GET)"
    assert_equal Nabu::Adapters::Imp.manifest, entry.manifest
  end

  private

  def parse_urn(urn)
    adapter = Nabu::Adapters::Imp.new
    ref = adapter.discover(FIXTURES).find { |r| r.id == urn }
    refute_nil ref, "expected discover to yield #{urn}"
    adapter.parse(ref)
  end

  # Zip the checked-in fixture files under the upstream's single top-level
  # dir (IMP-corpus-tei/) and stub the bitstream URL.
  def stub_zip
    Dir.mktmpdir do |dir|
      staging = File.join(dir, "IMP-corpus-tei")
      FileUtils.mkdir_p(staging)
      FileUtils.cp_r(Dir.glob(File.join(FIXTURES, "*.xml")), staging)
      zip_path = File.join(dir, "IMP-corpus-tei.zip")
      Nabu::Shell.run("zip", "-q", "-r", zip_path, "IMP-corpus-tei", chdir: dir)
      stub_request(:get, ZIP_URL).to_return(
        status: 200, body: File.binread(zip_path),
        headers: { "Content-Type" => "application/zip", "Last-Modified" => "Fri, 22 May 2015 15:23:00 GMT" }
      )
    end
  end
end

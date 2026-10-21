# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

# SENIE adapter tests: the Corpus of Early Written Latvian (CLARIN-LV
# hdl:20.500.12574/141, CC BY-SA 4.0) — one 61 MB teiCorpus file; one
# document per text-bearing leaf TEI (the three Bible containers skip by
# rule). Fixture: the real release file trimmed to six leaves (a Latin–
# Latvian–German–Estonian–Polish agenda, a manuscript sermon with a date
# span, a catechism window with a duplicated page number, a container with
# two of its New Testament children, a law print in sections). No network:
# fetch runs against a WebMock stub of the bitstream URL.
class SenieTest < Minitest::Test
  include AdapterConformance

  FIXTURES = Nabu::TestSupport.fixtures("senie")
  ZIP_URL = "https://repository.clarin.lv/repository/xmlui/bitstream/handle/20.500.12574/141/" \
            "SENIE_Unicode.tei.xml.zip?sequence=2&isAllowed=y"

  DOC_URNS = %w[urn:nabu:senie:ap1622 urn:nabu:senie:depk1681_90_ms urn:nabu:senie:ench1586
                urn:nabu:senie:jt1685.2j urn:nabu:senie:jt1685.prolog_tit urn:nabu:senie:skl1696_kb].freeze

  def conformance_adapter = Nabu::Adapters::Senie.new
  def conformance_workdir = FIXTURES
  def conformance_expected_source_id = "senie"

  # The documented search-form derivation (conventions §9): print-line
  # hyphenation rejoined, recomputable from the stored text.
  def conformance_search_source(passage)
    Nabu::Adapters::SenieTeiParser.search_source(passage.text, passage.annotations)
  end

  # --- manifest -----------------------------------------------------------------

  def test_manifest_records_the_share_alike_grant_and_credit
    manifest = Nabu::Adapters::Senie.manifest
    assert_equal "senie", manifest.id
    assert_equal "attribution", manifest.license_class, "CC BY-SA 4.0 — the share-alike glaux/scat precedent"
    assert_match(/Attribution-ShareAlike 4\.0 International/, manifest.license)
    assert_match(/Corpus of Early Written Latvian/, manifest.license)
    assert_equal "https://hdl.handle.net/20.500.12574/141", manifest.upstream_url
    assert_equal "senie-tei", manifest.parser_family
  end

  # --- discover -------------------------------------------------------------------

  def test_discover_mints_one_ref_per_leaf_tei
    assert_equal DOC_URNS, Nabu::Adapters::Senie.new.discover(FIXTURES).map(&:id)
  end

  def test_the_container_tei_skips_by_rule
    skips = Nabu::Adapters::Senie.new.discovery_skips(FIXTURES)
    assert_equal 1, skips.skipped_by_rule, "JT1685 holds the New Testament books; it carries no text itself"
    assert_equal 0, skips.unrecognized
    assert_equal ["container TEI (its books are the documents): JT1685"], skips.notes
  end

  def test_discover_of_an_unfetched_workdir_yields_nothing
    Dir.mktmpdir { |dir| assert_empty Nabu::Adapters::Senie.new.discover(dir).to_a }
  end

  # --- parse: metadata ---------------------------------------------------------------

  def test_the_header_mines_date_genre_author_and_medium
    metadata = parse_urn("urn:nabu:senie:depk1681_90_ms").metadata
    assert_equal({ "not_before" => 1681, "not_after" => 1690, "raw" => "1681_90" }, metadata["date"])
    assert_equal "manuscript", metadata["medium"]
    assert_equal "Liborijs Depkins", metadata["author"]
    assert_equal "Garīgie teksti; lūgšanas", metadata["genre"]
    assert_equal "religious", metadata["domain_type"]
    refute metadata.key?("byte_offset"), "the read coordinates stay on the ref"
  end

  def test_an_unknown_author_rides_as_no_author
    metadata = parse_urn("urn:nabu:senie:ap1622").metadata
    refute metadata.key?("author"), "upstream's nezināms (unknown) is not a name"
    assert_equal "print", metadata["medium"]
  end

  def test_container_children_carry_the_collection
    document = parse_urn("urn:nabu:senie:jt1685.2j")
    assert_equal "Jahņa ta Apustuļa ohtra Grahmata uhs wisseem rakstita", document.title
    assert_equal "JT1685", document.metadata["collection_id"]
    assert_equal "Tas Jauns Testaments", document.metadata["collection_title"]
    assert_equal "Ernsts Gliks", document.metadata["author"]
  end

  def test_the_document_language_is_the_majority_language
    assert_equal "lv", parse_urn("urn:nabu:senie:skl1696_kb").language
    agenda = parse_urn("urn:nabu:senie:ap1622")
    assert_equal "lat", agenda.language, "the 1622 Agenda Parva is a Latin rite with vernacular formulas"
    assert_equal %w[de et lat lv], agenda.metadata["languages"].keys
  end

  # --- parse: passages ------------------------------------------------------------------

  def test_passage_urns_follow_the_three_grains
    assert_equal "urn:nabu:senie:ap1622:p.6", parse_urn("urn:nabu:senie:ap1622").to_a[1].urn
    assert_equal "urn:nabu:senie:jt1685.2j:1.1", parse_urn("urn:nabu:senie:jt1685.2j").to_a[2].urn
    assert_equal "urn:nabu:senie:skl1696_kb:s.5.6", parse_urn("urn:nabu:senie:skl1696_kb").to_a.last.urn
  end

  def test_passage_language_follows_its_runs
    page = parse_urn("urn:nabu:senie:jt1685.prolog_tit").first
    assert_equal "lv", page.language
    assert_includes page.annotations["foreign"],
                    { "lang" => "lat", "text" => "Cum Gratia & Privilegio S.R.M. Sueciae." }
  end

  def test_the_search_form_rejoins_the_print_lines
    verse = parse_urn("urn:nabu:senie:jt1685.2j").find { |p| p.urn.end_with?(":1.1") }
    assert_includes verse.text, "Gaſpa-\nſchai"
    assert_includes verse.text_normalized, "gaſpaſchai"
  end

  # --- fetch (WebMock only, no network) ---------------------------------------------------

  def test_fetch_downloads_and_unpacks_the_bitstream
    stub_zip
    Dir.mktmpdir do |workdir|
      adapter = Nabu::Adapters::Senie.new
      report = adapter.fetch(workdir)
      assert_match(/\A\h{64}\z/, report.sha)
      assert_equal DOC_URNS, adapter.discover(workdir).map(&:id)
    end
  end

  def test_fetch_wraps_http_failure_in_fetch_error
    stub_request(:get, ZIP_URL).to_return(status: 500)
    Dir.mktmpdir do |workdir|
      assert_raises(Nabu::FetchError) { Nabu::Adapters::Senie.new.fetch(workdir) }
    end
  end

  def test_probe_heads_the_bitstream
    assert_equal :http_zip, Nabu::Adapters::Senie.remote_probe_strategy
    assert_equal [ZIP_URL], Nabu::Adapters::Senie.http_probe_targets.map(&:zip_url)
  end

  # --- registry round-trip -----------------------------------------------------------------

  def test_registry_resolves_senie_and_manifest_agrees
    registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
    entry = registry["senie"]
    refute_nil entry, "senie must be registered in config/sources.yml"
    assert_equal Nabu::Adapters::Senie, entry.adapter_class
    assert_equal Nabu::Adapters::Senie.manifest, entry.manifest
    assert entry.wired, "wired since the verified first sync (2026-10-21)"
  end

  private

  def parse_urn(urn)
    adapter = Nabu::Adapters::Senie.new
    ref = adapter.discover(FIXTURES).find { |r| r.id == urn }
    refute_nil ref, "expected discover to yield #{urn}"
    adapter.parse(ref)
  end

  # The bitstream zip holds the one corpus file at its root.
  def stub_zip
    Dir.mktmpdir do |dir|
      zip_path = File.join(dir, "SENIE_Unicode.tei.xml.zip")
      Nabu::Shell.run("zip", "-q", zip_path, "SENIE_Unicode.tei.xml", chdir: FIXTURES)
      stub_request(:get, ZIP_URL).to_return(
        status: 200, body: File.binread(zip_path),
        headers: { "Content-Type" => "application/zip", "Last-Modified" => "Thu, 27 Nov 2025 10:00:00 GMT" }
      )
    end
  end
end

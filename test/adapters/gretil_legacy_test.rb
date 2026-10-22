# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

# Nabu::Adapters::GretilLegacy: GRETIL's pre-TEI e-texts from three
# per-language download zips (2_prakrt, 3_nia, 4_drav), parser family
# gretil-legacy, physical-line grain. Fixtures: trimmed-real members of
# all three zips laid out as ZipFetch lands them, one specimen per
# rejected grain (test/fixtures/gretil-legacy/README.md). Fetch runs
# against WebMock stubs of the three zips built from the fixture tree.
class GretilLegacyTest < Minitest::Test
  include AdapterConformance

  FIXTURES = Nabu::TestSupport.fixtures("gretil-legacy")
  BASE = "https://gretil.sub.uni-goettingen.de/gretil"
  ZIPS = %w[2_prakrt 3_nia 4_drav].freeze

  URNS = %w[
    urn:nabu:gretil-legacy:dasaveyu
    urn:nabu:gretil-legacy:halsatsu
    urn:nabu:gretil-legacy:jyotsniu
    urn:nabu:gretil-legacy:kutmir_u
  ].freeze
  QUARANTINED = %w[urn:nabu:gretil-legacy:jyotsniu].freeze

  # Jyotsnika admits since the ml anchor landed (2026-10-22; formerly the lect
  # registry); the conformance sweep runs over the parseable fixtures
  # (the sii-clean pattern).
  def conformance_adapter
    adapter = Nabu::Adapters::GretilLegacy.new
    original = adapter.method(:discover)
    adapter.define_singleton_method(:discover) do |workdir, &block|
      return enum_for(:discover, workdir) unless block

      original.call(workdir) { |ref| block.call(ref) unless QUARANTINED.include?(ref.id) }
    end
    adapter
  end

  def conformance_workdir = FIXTURES

  def conformance_expected_source_id = "gretil-legacy"

  def adapter = Nabu::Adapters::GretilLegacy.new

  def parse(urn)
    adapter.parse(adapter.discover(FIXTURES).find { |ref| ref.id == urn })
  end

  # -- manifest -------------------------------------------------------------------

  def test_manifest_records_the_gretil_terms_and_the_nc_class
    manifest = Nabu::Adapters::GretilLegacy.manifest
    assert_equal "gretil-legacy", manifest.id
    assert_equal "nc", manifest.license_class
    assert_includes manifest.license, "THIS GRETIL TEXT FILE IS FOR REFERENCE PURPOSES ONLY!"
    assert_includes manifest.license, "COPYRIGHT AND TERMS OF USAGE AS FOR SOURCE FILE."
    assert_equal "gretil-legacy", manifest.parser_family
  end

  # -- discover + the grain census --------------------------------------------------

  def test_discover_mints_one_ref_per_admitted_etext_sorted
    assert_equal URNS, adapter.discover(FIXTURES).map(&:id),
                 "urn:nabu:gretil-legacy:<GRETIL file stem>, across the three zips"
  end

  def test_every_rejected_grain_skips_by_rule_with_its_reason
    skips = adapter.discovery_skips(FIXTURES)
    assert_equal 0, skips.unrecognized, skips.notes.join("; ")
    assert_equal 9, skips.skipped_by_rule
    notes = skips.notes.join("\n")
    assert_match(%r{home/mmehner/Spiegel_P/2_prakrt/dasaveyu\.htm: .*packaging duplicate}, notes)
    assert_match(%r{tamil/pm/pm001__u\.htm: .*Project Madurai.*madurai source}, notes)
    assert_match(/ta-sa_periyavaccanpillai-perumaltiromolivyAkhyAnam\.xml: .*gretil TEI/, notes)
    assert_match(%r{tei/transformations/plaintext/.*\.txt: .*rendition}, notes)
    assert_match(%r{tei/transformations/html/style/html_style\.css: .*rendition}, notes)
    assert_match(/bacmadhu\.htm: .*modern/, notes)
    assert_match(/bardhkcu\.htm: .*CSX/, notes)
  end

  def test_an_unknown_member_is_counted_loud
    Dir.mktmpdir do |dir|
      FileUtils.cp_r(File.join(FIXTURES, "3_nia"), dir)
      File.write(File.join(dir, "3_nia", "hindi", "newtext_u.htm"), "<html></html>")
      File.write(File.join(dir, "3_nia", ".zip-fetch.json"), "{}")
      skips = adapter.discovery_skips(dir)
      assert_equal 1, skips.unrecognized
      assert_match(/newtext_u\.htm: unrecognized/, skips.notes.join(" "))
      assert_equal ["urn:nabu:gretil-legacy:kutmir_u"], adapter.discover(dir).map(&:id)
    end
  end

  def test_discover_of_an_unfetched_workdir_yields_nothing
    Dir.mktmpdir { |dir| assert_empty adapter.discover(dir).to_a }
  end

  # -- parse ----------------------------------------------------------------------

  def test_an_agama_parses_on_the_ardhamagadhi_node
    document = parse("urn:nabu:gretil-legacy:dasaveyu")
    assert_equal "Dasaveyaliya", document.title
    assert_equal "pka-Latn", document.language
    assert_equal "urn:nabu:gretil-legacy:dasaveyu:1", document.passages.first.urn
    assert_equal "1 prathamamadhyayanam (dumapupphiyā.) /", document.passages.first.text
    assert_equal (0...document.passages.size).to_a, document.passages.map(&:sequence)
  end

  def test_header_metadata_is_mined
    metadata = parse("urn:nabu:gretil-legacy:halsatsu").metadata
    assert_equal "halsatsu", metadata["work"], "the work_eras key"
    assert_equal "2_prakrt", metadata["collection"]
    assert_equal ["Input by Andrew Ollett"], metadata["input"]
    assert_match(/\ABased on the edition by Albrecht Weber/, metadata["edition"])
    assert_includes metadata["gretil_header"], "Input by Andrew Ollett"
    assert_equal ["THIS GRETIL TEXT FILE IS FOR REFERENCE PURPOSES ONLY!",
                  "COPYRIGHT AND TERMS OF USAGE AS FOR SOURCE FILE."], metadata["gretil_notice"]
    assert_equal "line-ordinal", metadata["addressing"]
  end

  def test_the_sattasai_stays_on_the_coarse_prakrit_anchor
    assert_equal "pra-Latn", parse("urn:nabu:gretil-legacy:halsatsu").language
  end

  def test_the_mirigavati_reads_awadhi_as_its_edition_states
    document = parse("urn:nabu:gretil-legacy:kutmir_u")
    assert_equal "awa-Latn", document.language
    assert_match(/Avadhii text/, document.metadata["edition"])
    assert_equal "3_nia", document.metadata["collection"]
  end

  def test_the_manipravalam_jyotsnika_admits_now_that_the_registry_carries_malayalam
    ref = adapter.discover(FIXTURES).find { |r| r.id == "urn:nabu:gretil-legacy:jyotsniu" }
    document = adapter.parse(ref)
    assert_equal "mal-Latn", document.language
    assert_equal "4_drav", document.metadata["collection"]
  end

  # -- the dating lane: the ruled per-work era table --------------------------------

  def test_every_admitted_work_has_a_ruled_era_row
    eras = Nabu::WorkEras.default
    assert_equal "work", eras.key_for("gretil-legacy")
    quarantined = Nabu::Adapters::GretilLegacy::QUARANTINED_LANGUAGES
    admitted = Nabu::Adapters::GretilLegacy::LANGUAGES.reject { |_stem, tag| quarantined.key?(tag) }.keys
    assert_equal admitted.sort, eras.works("gretil-legacy").sort,
                 "every admitted work carries its ruled era row (a contested one with no band)"
    refute_nil eras.lookup("gretil-legacy", "jna1-16u")
    assert_equal [1290, 1290], eras.lookup("gretil-legacy", "jna1-16u").band
  end

  def test_the_timeline_reads_the_work_era_table
    shape = Nabu::Store::TimelineBuilder::MetadataDates::SHAPES.fetch("gretil-legacy")
    assert_equal :work_era, shape
  end

  # -- fetch: three zips, two-phase -------------------------------------------------

  def test_fetch_lands_the_three_zips_in_their_collection_subdirs
    ZIPS.each do |zip|
      stub_request(:get, "#{BASE}/#{zip}.zip").to_return(status: 200, body: stub_zip(zip), headers: zip_headers)
    end
    Dir.mktmpdir do |workdir|
      report = adapter.fetch(workdir)
      assert_instance_of Nabu::FetchReport, report
      assert_equal URNS, adapter.discover(workdir).map(&:id)
      assert_equal 9, adapter.discovery_skips(workdir).skipped_by_rule
      assert_path_exists File.join(workdir, "3_nia", "marathi", "kutmir_u.htm"),
                         "a single-top-dir zip lands with its top dir stripped"
      assert_path_exists File.join(workdir, "2_prakrt", "2_prakrt", "dasaveyu.htm"),
                         "2_prakrt.zip carries two top dirs, so both stay"
    end
  end

  def test_fetch_wraps_http_failure_in_fetch_error
    stub_request(:get, "#{BASE}/2_prakrt.zip").to_return(status: 500)
    stub_request(:get, "#{BASE}/3_nia.zip").to_return(status: 200, body: stub_zip("3_nia"), headers: zip_headers)
    stub_request(:get, "#{BASE}/4_drav.zip").to_return(status: 200, body: stub_zip("4_drav"), headers: zip_headers)
    Dir.mktmpdir do |workdir|
      assert_raises(Nabu::FetchError) { adapter.fetch(workdir) }
      assert_empty Dir.children(workdir).reject { |name| name.start_with?(".") }.flat_map { |sub|
        Dir.glob("**/*", base: File.join(workdir, sub)).select { |rel| rel.end_with?(".htm") }
      }, "a failed zip aborts before any tree lands"
    end
  end

  def test_probe_heads_the_three_zips
    assert_equal :http_zip, Nabu::Adapters::GretilLegacy.remote_probe_strategy
    assert_equal ZIPS.map { |zip| "#{BASE}/#{zip}.zip" },
                 Nabu::Adapters::GretilLegacy.http_probe_targets.map(&:zip_url)
  end

  private

  def zip_headers
    { "Content-Type" => "application/zip", "Last-Modified" => "Fri, 05 Jun 2020 12:36:23 GMT" }
  end

  # The fixture subdir re-zipped in upstream's shape: 2_prakrt.zip with its
  # two top dirs as they are; 3_nia/4_drav under their single top dir.
  def stub_zip(zip)
    Dir.mktmpdir do |dir|
      if zip == "2_prakrt"
        FileUtils.cp_r(File.join(FIXTURES, zip, "."), dir)
      else
        FileUtils.cp_r(File.join(FIXTURES, zip), dir)
      end
      zip_path = File.join(Dir.tmpdir, "gretil-legacy-#{zip}-#{Process.pid}.zip")
      FileUtils.rm_f(zip_path)
      Nabu::Shell.run("zip", "-qr", zip_path, *Dir.children(dir).sort, chdir: dir)
      body = File.binread(zip_path)
      FileUtils.rm_f(zip_path)
      return body
    end
  end
end

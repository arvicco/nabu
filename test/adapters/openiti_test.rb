# frozen_string_literal: true

require "test_helper"
require "fileutils"
require "tmpdir"

# OpenITI adapter tests (P41-2): the Open Islamicate Texts Initiative —
# premodern Arabic + Persian in OpenITI mARkdown, release 2025.1.9 (Zenodo
# record 17767721). Discovery is INDEX-DRIVEN off the central metadata TSV
# (the aozora precedent); the D41-e first wave is status == "pri" minus the
# MSS sub-corpus. Fixtures: six real texts + a stratified TSV trim
# (test/fixtures/openiti/README.md). The conformance workdir is ASSEMBLED
# per test into the canonical layout (data/<author>/<book>/<file> + the TSV)
# because the fixture dir keeps its files flat for the parser tests.
class OpenitiTest < Minitest::Test
  include AdapterConformance

  FIXTURES = Nabu::TestSupport.fixtures("openiti")
  SAMPLE_TSV = File.join(FIXTURES, "OpenITI_metadata_2025-1-9.sample.tsv")

  FIXTURE_FILES = [
    "0001AbuTalibCabdManaf.Diwan.JK007501-ara1",
    "0390AbuFarajCukbari.Hadith.ShamAY0032805-ara1",
    "0428IbnSina.RisalaJudiya.AOCP202502141162-per1",
    "0500Anonymous.ZiyadatMakhtutatTarikhJurjan.Shamela0011077BK2-ara1.mARkdown",
    "0646IbnNamawarKhunaji.JumalFiMantiq.JK010719-ara1",
    "0792Hafiz.Muntasab.PDL00074-per1"
  ].freeze

  # The urn keeps upstream's version URI verbatim — WITHOUT the .mARkdown
  # status extension, which is a filename fact (local_path), not identity.
  DOC_URNS = %w[
    urn:nabu:openiti:0001AbuTalibCabdManaf.Diwan.JK007501-ara1
    urn:nabu:openiti:0390AbuFarajCukbari.Hadith.ShamAY0032805-ara1
    urn:nabu:openiti:0428IbnSina.RisalaJudiya.AOCP202502141162-per1
    urn:nabu:openiti:0500Anonymous.ZiyadatMakhtutatTarikhJurjan.Shamela0011077BK2-ara1
    urn:nabu:openiti:0646IbnNamawarKhunaji.JumalFiMantiq.JK010719-ara1
    urn:nabu:openiti:0792Hafiz.Muntasab.PDL00074-per1
  ].freeze

  # The sample TSV split, awk-verified against the fixture (297 data rows):
  # 214 pri (122 ara + 70 per + 22 MSS) + 83 sec. In scope: pri AND not MSS.
  SAMPLE_IN_SCOPE = 192
  SAMPLE_SKIPPED = 105 # 83 sec + 22 MSS-with-status-pri

  def setup
    @workdir = Dir.mktmpdir("openiti-test")
    build_workdir(@workdir, FIXTURE_FILES)
  end

  # P41-i1 (live first-sync incident, 2026-07-22): the release zip roots at
  # `data/` ITSELF, so ZipFetch's single-top-dir collapse leaves the
  # per-author tree at the workdir root — every verbatim local_path join
  # (data/<author>/…) then missed, quarantining all 9,106 in-scope docs and
  # counting every real file unrecognized. Discovery must resolve BOTH
  # layouts: verbatim when workdir/data exists, first-component-stripped
  # when collapsed.
  def test_discover_resolves_the_collapsed_data_root_layout
    Dir.mktmpdir("openiti-collapsed") do |dir|
      rows = rows_for(FIXTURE_FILES)
      write_tsv(dir, rows)
      rows.each do |row|
        collapsed = row[15].split("/", 2).last
        target = File.join(dir, collapsed)
        FileUtils.mkdir_p(File.dirname(target))
        FileUtils.cp(File.join(FIXTURES, File.basename(row[15])), target)
      end

      refs = Nabu::Adapters::Openiti.new.discover(dir).to_a
      assert_equal DOC_URNS, refs.map(&:id).sort
      assert(refs.all? { |ref| File.exist?(ref.path) },
             "every ref path must resolve on the collapsed layout")
      skips = Nabu::Adapters::Openiti.new.discovery_skips(dir)
      assert_equal 0, skips.unrecognized,
                   "real version files must be accounted, not counted as strays"
    end
  end

  def teardown
    FileUtils.remove_entry(@workdir)
    super
  end

  def conformance_adapter
    Nabu::Adapters::Openiti.new
  end

  def conformance_workdir
    @workdir
  end

  def conformance_expected_source_id
    "openiti"
  end

  # --- manifest ---------------------------------------------------------------

  def test_manifest_identifies_the_openiti_source
    manifest = Nabu::Adapters::Openiti.manifest
    assert_equal "openiti", manifest.id
    assert_equal "nc", manifest.license_class
    assert_match(/Creative Commons Attribution Non Commercial Share Alike 4\.0 International/,
                 manifest.license, "the Zenodo record's grant, verbatim")
    assert_match(/no LICENSE file/i, manifest.license,
                 "D41-b: the discrepancy is recorded — the grant rests on the Zenodo record alone")
    assert_equal "https://zenodo.org/records/17767721", manifest.upstream_url
    assert_equal "openiti-markdown", manifest.parser_family
  end

  # --- discover (index-driven, D41-e) -----------------------------------------

  def test_discover_mints_one_ref_per_in_scope_tsv_row
    refs = Nabu::Adapters::Openiti.new.discover(@workdir).to_a
    assert_equal DOC_URNS, refs.map(&:id), "urn:nabu:openiti:<version_uri>, sorted"
    assert(refs.all? { |ref| ref.source_id == "openiti" })
    markdown_ref = refs.find { |ref| ref.id.end_with?("Shamela0011077BK2-ara1") }
    assert markdown_ref.path.end_with?(".mARkdown"),
           "the path carries the status extension (local_path); the urn never does"
  end

  def test_discover_mints_ara_and_fas_from_the_uri_language_suffix
    languages = Nabu::Adapters::Openiti.new.discover(@workdir)
                                       .to_h { |ref| [ref.id, ref.metadata["language"]] }
    assert_equal "ara", languages["urn:nabu:openiti:0001AbuTalibCabdManaf.Diwan.JK007501-ara1"]
    # The P41-3 catch: -per* mints "fas", NEVER "per" — LANGUAGE_FOLDS keys
    # on the stored tag, and a per-tagged document would silently skip the
    # Arabic-script fold. fas is the house ISO 639-3 resolution target.
    assert_equal "fas", languages["urn:nabu:openiti:0792Hafiz.Muntasab.PDL00074-per1"]
    assert_equal "fas", languages["urn:nabu:openiti:0428IbnSina.RisalaJudiya.AOCP202502141162-per1"]
  end

  def test_discover_carries_the_tsv_metadata_lanes
    ref = discover_ref("urn:nabu:openiti:0792Hafiz.Muntasab.PDL00074-per1")
    assert_equal "Muntasab", ref.metadata["title"]
    assert_equal "Hafiz :: Šams al-Dīn Muḥammad Ḥāfiẓ Šīrāzī", ref.metadata["author_lat"]
    assert_equal 792, ref.metadata["death_ah"]
    assert_equal "pri", ref.metadata["status"]
  end

  def test_discover_against_the_full_sample_tsv_pins_the_scope_split
    # The fixture dir itself: full sample TSV, no data/ tree — discovery is
    # pure index arithmetic (paths are minted, not probed).
    refs = Nabu::Adapters::Openiti.new.discover(FIXTURES).to_a
    assert_equal SAMPLE_IN_SCOPE, refs.size, "in scope: status pri AND subcorpus != MSS"
    tally = refs.map { |ref| ref.metadata["language"] }.tally
    assert_equal({ "ara" => 122, "fas" => 70 }, tally,
                 "the 22 MSS rows (ALL status=pri in the sample) are excluded by rule")
  end

  def test_discovery_skips_census_the_sec_and_mss_rows
    skips = Nabu::Adapters::Openiti.new.discovery_skips(FIXTURES)
    assert_equal SAMPLE_SKIPPED, skips.skipped_by_rule, "83 sec + 22 MSS rows, censused never silent"
    assert_equal 0, skips.unrecognized
    assert_empty skips.notes
  end

  def test_a_version_file_with_no_index_row_is_unrecognized
    stray = File.join(@workdir, "data", "0001AbuTalibCabdManaf",
                      "0001AbuTalibCabdManaf.Diwan", "0001AbuTalibCabdManaf.Diwan.XX999-ara1")
    File.write(stray, "stray")
    skips = Nabu::Adapters::Openiti.new.discovery_skips(@workdir)
    assert_equal 1, skips.unrecognized
    assert_match(/no index row/, skips.notes.first)
    sidecar_free = File.join(File.dirname(stray), "0001AbuTalibCabdManaf.Diwan.yml")
    File.write(sidecar_free, "00#BOOK#URI######: x")
    assert_equal 1, Nabu::Adapters::Openiti.new.discovery_skips(@workdir).unrecognized,
                 ".yml sidecars are accounted by rule, never strays"
  end

  def test_discover_of_an_unfetched_workdir_yields_nothing
    Dir.mktmpdir do |dir|
      assert_empty Nabu::Adapters::Openiti.new.discover(dir).to_a, "no TSV = the day-one pre-fetch state"
    end
  end

  # --- parse: units → passages, the ref grammar --------------------------------

  def test_passage_counts_per_fixture_file
    counts = parse_all.transform_values(&:size)
    expected = {
      "urn:nabu:openiti:0001AbuTalibCabdManaf.Diwan.JK007501-ara1" => 30,
      "urn:nabu:openiti:0390AbuFarajCukbari.Hadith.ShamAY0032805-ara1" => 10,
      "urn:nabu:openiti:0428IbnSina.RisalaJudiya.AOCP202502141162-per1" => 7,
      "urn:nabu:openiti:0500Anonymous.ZiyadatMakhtutatTarikhJurjan.Shamela0011077BK2-ara1" => 22,
      "urn:nabu:openiti:0646IbnNamawarKhunaji.JumalFiMantiq.JK010719-ara1" => 14,
      "urn:nabu:openiti:0792Hafiz.Muntasab.PDL00074-per1" => 20
    }
    assert_equal expected, counts
  end

  def test_ref_grammar_is_volume_page_ordinal
    document = parse_urn("urn:nabu:openiti:0792Hafiz.Muntasab.PDL00074-per1")
    refs = document.map { |passage| passage.urn.split(":").last }
    assert_equal %w[1.1.1 1.1.2 1.1.3], refs.first(3),
                 "<volume>.<page>.<n>: the unit's retro-assigned start page + intra-page ordinal"
    assert_includes refs, "1.2.1", "a new page restarts the ordinal"
  end

  def test_units_after_the_last_page_marker_take_the_unplaced_tail_refs
    document = parse_urn("urn:nabu:openiti:0646IbnNamawarKhunaji.JumalFiMantiq.JK010719-ara1")
    refs = document.map { |passage| passage.urn.split(":").last }
    assert_equal "x.1", refs.first, "the trim carries no page markers — every unit is honestly unplaced"
    assert_equal "x.14", refs.last
    assert_equal refs.size, refs.uniq.size
  end

  def test_verse_passages_join_hemistichs_and_ride_them_in_annotations
    document = parse_urn("urn:nabu:openiti:0792Hafiz.Muntasab.PDL00074-per1")
    first = document.first
    # Byte pin (Persian orthography: farsi yeh U+06CC, keheh U+06A9 — the
    # P41-3 fold evidence); text = the hemistich single-space join.
    assert_equal "ما برفتیم تو دانی و دل غمخور ما بخت بد تا به کجا می برد آبشخور ما", first.text
    assert_equal "verse", first.annotations["kind"]
    assert_equal ["ما برفتیم تو دانی و دل غمخور ما", "بخت بد تا به کجا می برد آبشخور ما"],
                 first.annotations["hemistichs"]
    assert_equal 1, first.annotations["verse_number"]
  end

  def test_legacy_arabic_verse_notation_parses_too
    document = parse_urn("urn:nabu:openiti:0001AbuTalibCabdManaf.Diwan.JK007501-ara1")
    verse = document.find { |passage| passage.urn.end_with?(":1.1.2") }
    assert_equal "verse", verse.annotations["kind"]
    assert_equal 2, verse.annotations["verse_number"]
    assert_equal ["تطاول ليلي بهم وصب", "ودمع كسح السقاء السرب"], verse.annotations["hemistichs"]
  end

  def test_section_headers_are_their_own_passages
    # RULING (documented in the adapter): a section header is a PASSAGE of
    # its own (kind section_header) — headers are real searchable canonical
    # text (chapter titles); section_path rides only the header passage.
    document = parse_urn("urn:nabu:openiti:0390AbuFarajCukbari.Hadith.ShamAY0032805-ara1")
    header = document.first
    assert_equal "section_header", header.annotations["kind"]
    assert_equal 1, header.annotations["level"]
    assert_equal "الجزء من حديث", header.text
    assert_equal ["الجزء من حديث"], header.annotations["section_path"]
    assert header.annotations["auto"], "the upstream AUTO flag rides verbatim"
    prose = document.to_a[1]
    refute prose.annotations.key?("kind"), "prose is the unmarked default"
    refute prose.annotations.key?("section_path"), "the path rides the header passage only"
  end

  def test_nested_section_headers_carry_their_path
    document = parse_urn("urn:nabu:openiti:0500Anonymous.ZiyadatMakhtutatTarikhJurjan.Shamela0011077BK2-ara1")
    level2 = document.find { |passage| passage.annotations["level"] == 2 }
    refute_nil level2, "the Ziyadat trim keeps ### || second-level headers"
    assert_equal 2, level2.annotations["section_path"].size, "the path chains the enclosing level-1 header"
  end

  def test_page_breaks_and_milestones_ride_annotations
    document = parse_urn("urn:nabu:openiti:0390AbuFarajCukbari.Hadith.ShamAY0032805-ara1")
    last = document.to_a.last
    assert_equal [[1, 1]], last.annotations["page_breaks"], "PageV01P001 closes inside the final unit"
    assert_equal ["ms1"], last.annotations["milestones"]
    first = document.first
    refute first.annotations.key?("page_breaks"), "absent, never an empty list"
  end

  def test_parser_census_surfaces_in_document_metadata
    document = parse_urn("urn:nabu:openiti:0428IbnSina.RisalaJudiya.AOCP202502141162-per1")
    assert_equal({ "image" => 2 }, document.metadata["census"],
                 "the OCR page-image refs are censused loud (the aozora pattern), never silent")
    clean = parse_urn("urn:nabu:openiti:0792Hafiz.Muntasab.PDL00074-per1")
    refute clean.metadata.key?("census"), "an empty census stays absent"
  end

  def test_document_metadata_carries_tsv_lanes_and_the_meta_block
    document = parse_urn("urn:nabu:openiti:0792Hafiz.Muntasab.PDL00074-per1")
    assert_equal "fas", document.language
    assert_equal "Muntasab", document.title
    assert_equal 792, document.metadata["death_ah"]
    assert_equal "Hafiz :: Šams al-Dīn Muḥammad Ḥāfiẓ Šīrāzī", document.metadata["author_lat"]
    assert_equal "pri", document.metadata["status"]
    assert_equal "#META# title: montasab", document.metadata["meta_lines"].first,
                 "the opaque #META# block rides verbatim as provenance"
  end

  def test_yml_sidecar_issues_ride_verbatim_when_present
    urn = "urn:nabu:openiti:0792Hafiz.Muntasab.PDL00074-per1"
    ref = discover_ref(urn)
    File.write("#{ref.path}.yml",
               "00#VERS#LENGTH###: 2700\n90#VERS#ISSUES###: PRIMARY_VERSION\n")
    document = conformance_adapter.parse(ref)
    assert_equal "PRIMARY_VERSION", document.metadata["version_issues"]
    plain = parse_urn("urn:nabu:openiti:0001AbuTalibCabdManaf.Diwan.JK007501-ara1")
    refute plain.metadata.key?("version_issues"), "no sidecar → no key, no machinery"
  end

  # --- parse: quarantines -------------------------------------------------------

  def test_a_missing_in_scope_file_quarantines_loudly
    ref = discover_ref("urn:nabu:openiti:0792Hafiz.Muntasab.PDL00074-per1")
    FileUtils.rm(ref.path)
    error = assert_raises(Nabu::ParseError) { conformance_adapter.parse(ref) }
    assert_match(/missing/, error.message)
  end

  def test_a_header_only_body_quarantines
    # In-scope means the TSV promised text (tok_length > 0 on every in-scope
    # row, P41-g groundwork) — an empty body is damage, never a skip.
    ref = discover_ref("urn:nabu:openiti:0390AbuFarajCukbari.Hadith.ShamAY0032805-ara1")
    lines = File.read(ref.path).lines
    header_end = lines.index { |line| line.start_with?("#META#Header#End#") }
    File.write(ref.path, lines[0..header_end].join)
    error = assert_raises(Nabu::ParseError) { conformance_adapter.parse(ref) }
    assert_match(/promised text/, error.message)
  end

  def test_an_unmappable_language_suffix_quarantines_rather_than_guesses
    # Doctored drill: a real MSS row (multi-language suffix -per1ara1) forced
    # in scope by rewriting its subcorpus column — the guard the D41-e brief
    # demands for any in-scope row whose suffix cannot mint cleanly.
    Dir.mktmpdir do |dir|
      uri = "MS0972JerusalemNLI.Heb8333_113Recto.IEDC1277-per1ara1"
      row = sample_rows.find { |fields| fields[0] == uri }
      row[2] = "per" # subcorpus MSS → per: now pri AND not MSS
      write_tsv(dir, [row])
      place_file(dir, row, source: File.join(FIXTURES, FIXTURE_FILES.last))
      adapter = Nabu::Adapters::Openiti.new
      refs = adapter.discover(dir).to_a
      assert_equal 1, refs.size
      error = assert_raises(Nabu::ParseError) { adapter.parse(refs.first) }
      assert_match(/language suffix/, error.message)
    end
  end

  # --- fetch (WebMock only, no network) ----------------------------------------

  ZIP_URL = "https://zenodo.org/api/records/17767721/files/OpenITI_data_2025-1-9.zip/content"
  TSV_URL = "https://zenodo.org/api/records/17767721/files/OpenITI_metadata_2025-1-9.tsv/content"

  def test_fetch_downloads_verifies_both_md5_pins_and_unpacks
    zip_body = stub_zip_body
    tsv_body = File.read(SAMPLE_TSV)
    stub_request(:get, ZIP_URL).to_return(status: 200, body: zip_body,
                                          headers: { "Last-Modified" => "Tue, 30 Dec 2025 12:00:00 GMT" })
    stub_request(:get, TSV_URL).to_return(status: 200, body: tsv_body)
    Dir.mktmpdir do |workdir|
      adapter = Nabu::Adapters::Openiti.new(zip_md5: Digest::MD5.hexdigest(zip_body),
                                            tsv_md5: Digest::MD5.hexdigest(tsv_body))
      report = adapter.fetch(workdir)
      assert_instance_of Nabu::FetchReport, report
      assert_equal Digest::SHA256.hexdigest(zip_body), report.sha,
                   "the zip sha256 is recorded in the ledger at first fetch — the future re-pin"
      assert_match(/md5 pin verified/, report.notes)
      assert_match(/sha256 #{Digest::SHA256.hexdigest(zip_body)}/, report.notes)
      tsv_path = File.join(workdir, "metadata", Nabu::Adapters::Openiti::TSV_FILENAME)
      assert File.file?(tsv_path), "the TSV lands under metadata/, protected from the zip tree swap"
      assert_equal SAMPLE_IN_SCOPE, adapter.discover(workdir).count,
                   "the extracted data/ tree + TSV are discoverable in place"
    end
  end

  def test_fetch_aborts_on_a_zip_md5_mismatch_with_the_tree_untouched
    stub_request(:get, ZIP_URL).to_return(status: 200, body: stub_zip_body)
    Dir.mktmpdir do |workdir|
      error = assert_raises(Nabu::FetchError) { Nabu::Adapters::Openiti.new.fetch(workdir) }
      assert_match(/md5 pin/, error.message)
      assert_match(/re-pin/, error.message, "the abort names the recovery move")
      assert_empty Dir.children(workdir), "a pin miss aborts BEFORE any tree mutation"
    end
  end

  def test_fetch_aborts_on_a_tsv_md5_mismatch_with_the_tree_untouched
    zip_body = stub_zip_body
    stub_request(:get, ZIP_URL).to_return(status: 200, body: zip_body)
    stub_request(:get, TSV_URL).to_return(status: 200, body: "tampered")
    Dir.mktmpdir do |workdir|
      adapter = Nabu::Adapters::Openiti.new(zip_md5: Digest::MD5.hexdigest(zip_body))
      error = assert_raises(Nabu::FetchError) { adapter.fetch(workdir) }
      assert_match(/metadata TSV/, error.message)
      assert_empty Dir.children(workdir), "both artifacts verify before EITHER tree mutates"
    end
  end

  def test_fetch_wraps_http_failure_in_fetch_error
    stub_request(:get, ZIP_URL).to_return(status: 500)
    Dir.mktmpdir do |workdir|
      assert_raises(Nabu::FetchError) { Nabu::Adapters::Openiti.new.fetch(workdir) }
    end
  end

  # --- remote-health probe shape ------------------------------------------------

  def test_probe_heads_both_zenodo_artifacts
    assert_equal :http_zip, Nabu::Adapters::Openiti.remote_probe_strategy
    targets = Nabu::Adapters::Openiti.http_probe_targets
    assert_equal 2, targets.size
    assert_equal ZIP_URL, targets[0].zip_url
    assert_nil targets[0].metadata_url, "the license lives on the Zenodo record page only (D41-b)"
    assert_equal Nabu::ZipFetch::STATE_FILE, targets[0].state_file
    assert_equal TSV_URL, targets[1].zip_url
    assert_equal "metadata", targets[1].state_subdir
    assert_equal Nabu::FileFetch::STATE_FILE, targets[1].state_file
  end

  # --- registry round-trip ------------------------------------------------------

  def test_registry_resolves_openiti_and_manifest_agrees
    registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
    entry = registry["openiti"]
    refute_nil entry, "openiti must be registered in config/sources.yml"
    assert_equal Nabu::Adapters::Openiti, entry.adapter_class
    assert entry.enabled, "flipped 2026-07-23 after the owner-verified first sync (9,079 docs)"
    assert_equal Nabu::Adapters::Openiti.manifest, entry.manifest
  end

  private

  def discover_ref(urn, adapter: conformance_adapter, workdir: @workdir)
    ref = adapter.discover(workdir).find { |candidate| candidate.id == urn }
    refute_nil ref, "expected discover to yield #{urn}"
    ref
  end

  def parse_urn(urn)
    adapter = conformance_adapter
    adapter.parse(discover_ref(urn, adapter: adapter))
  end

  def parse_all
    adapter = conformance_adapter
    adapter.discover(@workdir).to_h { |ref| [ref.id, adapter.parse(ref)] }
  end

  # -- canonical-layout assembly (real rows + real files, machine-trimmed) ----

  def sample_rows
    @sample_rows ||= File.readlines(SAMPLE_TSV, chomp: true).map { |line| line.split("\t", -1) }
  end

  def sample_header
    sample_rows.first
  end

  def rows_for(basenames)
    names = basenames.to_set
    sample_rows.drop(1).select { |fields| names.include?(File.basename(fields[15])) }
  end

  def write_tsv(dir, rows)
    File.write(File.join(dir, "OpenITI_metadata.fixture.tsv"),
               ([sample_header] + rows).map { |fields| fields.join("\t") }.join("\n"))
  end

  def place_file(dir, row, source:)
    destination = File.join(dir, row[15])
    FileUtils.mkdir_p(File.dirname(destination))
    FileUtils.cp(source, destination)
  end

  def build_workdir(dir, basenames)
    rows = rows_for(basenames)
    assert_equal basenames.size, rows.size, "every fixture file must have its TSV row"
    write_tsv(dir, rows)
    rows.each { |row| place_file(dir, row, source: File.join(FIXTURES, File.basename(row[15]))) }
  end

  # Zip the assembled canonical tree under the release's single top-level
  # dir (the Zenodo artifact shape ZipFetch collapses).
  def stub_zip_body
    Dir.mktmpdir do |dir|
      staging = File.join(dir, "OpenITI_data_2025-1-9")
      FileUtils.mkdir_p(staging)
      rows_for(FIXTURE_FILES).each do |row|
        place_file(staging, row, source: File.join(FIXTURES, File.basename(row[15])))
      end
      zip_path = File.join(dir, "openiti.zip")
      Nabu::Shell.run("zip", "-q", "-r", zip_path, "OpenITI_data_2025-1-9", chdir: dir)
      return File.binread(zip_path)
    end
  end
end

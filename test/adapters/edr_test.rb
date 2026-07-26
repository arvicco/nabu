# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# EDR adapter tests (P46-4): discovery over the nine-range zip tree, the
# edr-epidoc line grain (upstream <lb n> numbers, textpart-relative), the
# per-edition xml:lang language minting (la→lat / grc — the root tag lies),
# the Leiden reading-text policies (choice corr>sic, surplus braces, g text,
# expanded abbreviations with <am> dropped), the whole-inscription :text
# fallback for gap-only editions, and the three quarantine classes (malformed
# XML, in-file licence drift, localID drift). Includes the shared
# AdapterConformance suite; fixtures are 5 whole real records — the malformed
# one under quarantine/, outside the one-level discover glob
# (test/fixtures/edr/README.md).
class EdrTest < Minitest::Test
  include AdapterConformance
  include StoreTestDB

  FIXTURES = Nabu::TestSupport.fixtures("edr")

  ZIP_URL = Nabu::Adapters::Edr::ZIP_URL

  ALL_URNS = %w[
    urn:nabu:edr:edr000002 urn:nabu:edr:edr006167 urn:nabu:edr:edr123437
    urn:nabu:edr:edr125195 urn:nabu:edr:edr200440
  ].freeze

  def conformance_adapter
    Nabu::Adapters::Edr.new
  end

  def conformance_workdir
    FIXTURES
  end

  def conformance_expected_source_id
    "edr"
  end

  # aEDR123437's edition is a single self-closed <g type="fulmen"/> — a
  # symbol-only carving with no letters, marked by the parser itself
  # ("text_layer" => "none", the isicily/ogham precedent), never a blanket
  # override.
  def conformance_metadata_only?(document)
    document.metadata["text_layer"] == "none"
  end

  # --- manifest ---------------------------------------------------------------

  def test_manifest_records_both_license_layers
    manifest = Nabu::Adapters::Edr.manifest
    assert_equal "edr", manifest.id
    assert_equal "attribution", manifest.license_class
    assert_match(/CC BY 4\.0/, manifest.license, "the Zenodo deposit-level grant")
    assert_match(%r{10\.5281/zenodo\.18468635}, manifest.license, "the versioned deposit DOI")
    assert_match(/Reserved Rights - Free access/, manifest.license,
                 "the EAGLE-era in-file <licence>, recorded verbatim beside the grant")
    assert_equal "edr-epidoc", manifest.parser_family
    assert_equal "https://zenodo.org/records/18468635", manifest.upstream_url
  end

  def test_remote_probe_heads_the_zenodo_artifact
    assert_equal :http_zip, Nabu::Adapters::Edr.remote_probe_strategy
    targets = Nabu::Adapters::Edr.http_probe_targets
    assert_equal 1, targets.size
    assert_equal ZIP_URL, targets.first.zip_url
    assert_nil targets.first.metadata_url, "the license travels on the record page, not an endpoint"
  end

  # --- discover ---------------------------------------------------------------

  def test_discover_mints_one_ref_per_record_file_sorted
    refs = Nabu::Adapters::Edr.new.discover(FIXTURES).to_a
    assert_equal ALL_URNS, refs.map(&:id)
    refs.each { |ref| assert_equal "edr", ref.source_id }
  end

  def test_discover_of_an_unfetched_workdir_yields_nothing
    Dir.mktmpdir do |dir|
      assert_empty Nabu::Adapters::Edr.new.discover(dir).to_a
    end
  end

  def test_discover_ignores_non_record_files_in_the_tree
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "000001-025000"))
      FileUtils.cp(File.join(FIXTURES, "000001-025000", "aEDR000002.xml"),
                   File.join(dir, "000001-025000", "aEDR000002.xml"))
      File.write(File.join(dir, "000001-025000", "notes.xml"), "<TEI/>")
      File.write(File.join(dir, ".zip-fetch.json"), "{}")
      assert_equal ["urn:nabu:edr:edr000002"],
                   Nabu::Adapters::Edr.new.discover(dir).to_a.map(&:id)
    end
  end

  # --- the Latin exemplar (choice, surplus, g, expansions) ---------------------

  def test_latin_record_reads_the_edited_leiden_text
    document = parse("urn:nabu:edr:edr000002")
    assert_equal "lat", document.language
    assert_equal "Inscription from Roma", document.title
    assert_equal %w[1 2 3 4].map { |n| "urn:nabu:edr:edr000002:#{n}" }, document.map(&:urn)
    assert_equal "Valeria Marci et", document.first.text,
                 "choice reads corr over sic; expan reads abbr+ex expanded"
    assert_equal "mulieris liberta Philumina.", document.to_a[1].text,
                 "<g type=\"mulieris\"> keeps its text — upstream spells the symbol out"
    assert_equal "{In fronte p(edes) IX, in ag(ro) p(edes)}", document.to_a[2].text,
                 "surplus wraps in Leiden braces (CelticLeiden)"
    assert_equal "In fronte pedes IX, in agro pedes XIIX.", document.to_a.last.text
  end

  def test_latin_record_metadata_layers
    metadata = parse("urn:nabu:edr:edr000002").metadata
    assert_equal "261492", metadata["tm_nr"]
    facets = metadata["facets"]
    assert_equal({ "value" => "sepulcralis", "ref" => "http://www.eagle-network.eu/voc/typeins/lod/92" },
                 facets["genre"])
    assert_equal "Roma", facets["region"]["value"]
    assert_equal({ "value" => "lapis", "ref" => "http://www.eagle-network.eu/voc/material/lod/2" },
                 facets["material"])
    assert_equal({ "value" => "cippus", "ref" => "http://www.eagle-network.eu/voc/objtyp/lod/85" },
                 facets["object_type"])
    assert_equal({ "ancient" => "Roma" }, metadata["place"])
    assert_equal "Roma, via Livenza (sepolcreto Salario)", metadata["findspot"]
    assert_equal "Roma, Antiquarium Comunale del Celio, senza inv.", metadata["repository"]
    assert_equal({ "not_before" => -50, "not_after" => 1, "raw" => "-50 BC - 1 AD" },
                 metadata["date"])
  end

  # --- the Greek exemplar (edition xml:lang, corr-only choice) -----------------

  def test_greek_record_language_comes_from_the_edition_div
    document = parse("urn:nabu:edr:edr125195")
    assert_equal "grc", document.language,
                 "the root TEI xml:lang says \"la\" on every record — the edition div is the truth"
    assert_equal (1..8).map { |n| "urn:nabu:edr:edr125195:#{n}" }, document.map(&:urn)
    assert_equal "Τῇδε θανόντα", document.first.text
    assert_equal "λεία Νεῖλον τὸν ἀσ", document.to_a[3].text,
                 "a corr-only <choice> (no sic branch) still reads corr"
    assert_equal "κερὸν παρὰ Λήθην", document.to_a.last.text
    document.each { |passage| assert_equal "grc", passage.language }
    assert_equal 11, document.first.annotations["leiden"]["supplied_chars"]
    refute metadata_has_date?(document), "an empty origDate mints no date key"
  end

  def metadata_has_date?(document)
    document.metadata.key?("date")
  end

  # Bilinguals: a Greek-script line inside a la-tagged edition takes grc
  # per passage (the EDH script rule; 721 such records at the 2026-07-26
  # census). Exercised on a doctored copy — no small whole fixture carries
  # the mix.
  def test_greek_script_line_in_a_latin_edition_takes_grc_per_passage
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "000001-025000"))
      doctored = File.read(File.join(FIXTURES, "000001-025000", "aEDR000002.xml"))
                     .sub("In <expan><abbr>fro</abbr><ex>nte</ex></expan>", "χαῖρε καὶ σύ")
      File.write(File.join(dir, "000001-025000", "aEDR000002.xml"), doctored)
      adapter = Nabu::Adapters::Edr.new
      document = adapter.parse(adapter.discover(dir).first)
      assert_equal "lat", document.language
      assert_equal "grc", document.to_a.last.language
      assert_equal "lat", document.first.language
    end
  end

  # --- textparts ---------------------------------------------------------------

  def test_textpart_records_join_the_textpart_n_into_the_urn
    document = parse("urn:nabu:edr:edr200440")
    assert_equal "lat", document.language
    assert_equal %w[1:1 1:2 1:3 1:4 1:5 1:6 2:2].map { |ref| "urn:nabu:edr:edr200440:#{ref}" },
                 document.map(&:urn),
                 "line numbers RESTART per textpart (both start at 1), so the textpart @n joins " \
                 "the urn; textpart 1's empty trailing <lb n=\"7\"/> and textpart 2's empty " \
                 "<lb n=\"1\"/> mint nothing"
    assert_equal "[…]um sibi et Lucio C[…].", document.to_a.last.text
    assert_equal "Cornelia", document.to_a[1].text
    leiden = document.to_a[1].annotations["leiden"]
    assert_equal 2, leiden["supplied_chars"]
    assert_equal 1, leiden["unclear_chars"]
    assert_equal "Tro[…]", document.to_a[4].text
    assert_equal 1, document.to_a[4].annotations["leiden"]["gaps"].size
  end

  def test_duplicate_line_numbers_take_the_house_b2_disambiguator
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "000001-025000"))
      doctored = File.read(File.join(FIXTURES, "000001-025000", "aEDR000002.xml"))
                     .sub('<lb n="4"/>', '<lb n="3"/>')
      File.write(File.join(dir, "000001-025000", "aEDR000002.xml"), doctored)
      adapter = Nabu::Adapters::Edr.new
      document = adapter.parse(adapter.discover(dir).first)
      assert_equal %w[1 2 3 3:b2].map { |ref| "urn:nabu:edr:edr000002:#{ref}" },
                   document.map(&:urn)
    end
  end

  # --- the whole-inscription fallback ------------------------------------------

  def test_gap_only_edition_falls_back_to_one_text_passage
    document = parse("urn:nabu:edr:edr006167")
    assert_equal ["urn:nabu:edr:edr006167:text"], document.map(&:urn),
                 "an edition of lost lines is catalogued, not quarantined (the EDH :text precedent)"
    assert_equal "[…] […][…][…] […]", document.first.text,
                 "the per-line extractions joined — the record's own lacuna notation"
    assert_equal 5, document.first.annotations["leiden"]["gaps"].size
    assert_equal "267805", document.metadata["tm_nr"]
  end

  # A symbol-only edition (self-closed <g/>, nothing extractable at all —
  # 88 records at the 2026-07-26 full-tree parse: fulmen, christogramma,
  # phallus…) is a catalogued carving, not a defect: metadata-only
  # document, zero passages, never a quarantine.
  def test_symbol_only_edition_is_a_metadata_only_document
    document = parse("urn:nabu:edr:edr123437")
    assert_empty document.to_a
    assert_equal "none", document.metadata["text_layer"]
    assert_equal "lat", document.language
  end

  # --- quarantines -------------------------------------------------------------

  def test_malformed_xml_quarantines_with_a_parse_error
    quarantine_dir = File.join(FIXTURES, "quarantine")
    adapter = Nabu::Adapters::Edr.new
    refs = adapter.discover(quarantine_dir).to_a
    assert_equal ["urn:nabu:edr:edr188615"], refs.map(&:id)
    error = assert_raises(Nabu::ParseError) { adapter.parse(refs.first) }
    assert_match(/malformed XML/, error.message,
                 "aEDR188615's <supplied> crosses <l> boundaries — a real upstream converter defect")
  end

  def test_licence_drift_quarantines_the_document
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "000001-025000"))
      doctored = File.read(File.join(FIXTURES, "000001-025000", "aEDR000002.xml"))
                     .sub("Reserved Rights - Free access via Epigraphic Database Roma",
                          "All rights reserved")
      File.write(File.join(dir, "000001-025000", "aEDR000002.xml"), doctored)
      adapter = Nabu::Adapters::Edr.new
      error = assert_raises(Nabu::ParseError) { adapter.parse(adapter.discover(dir).first) }
      assert_match(/licence/i, error.message)
    end
  end

  def test_local_id_drift_quarantines_the_document
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "000001-025000"))
      doctored = File.read(File.join(FIXTURES, "000001-025000", "aEDR000002.xml"))
                     .sub('<idno type="localID">EDR000002</idno>',
                          '<idno type="localID">EDR999999</idno>')
      File.write(File.join(dir, "000001-025000", "aEDR000002.xml"), doctored)
      adapter = Nabu::Adapters::Edr.new
      error = assert_raises(Nabu::ParseError) { adapter.parse(adapter.discover(dir).first) }
      assert_match(/localID/, error.message)
    end
  end

  # --- fetch (WebMock only, no network) ----------------------------------------

  def test_fetch_downloads_verifies_the_pin_and_unpacks
    body = stub_zip_body
    stub_request(:get, ZIP_URL).to_return(
      status: 200, body: body,
      headers: { "Content-Type" => "application/zip", "Last-Modified" => "Sat, 31 Jan 2026 12:00:00 GMT" }
    )
    Dir.mktmpdir do |workdir|
      adapter = Nabu::Adapters::Edr.new(pin: Digest::SHA256.hexdigest(body))
      report = adapter.fetch(workdir)
      assert_instance_of Nabu::FetchReport, report
      assert_equal Digest::SHA256.hexdigest(body), report.sha
      assert_equal ALL_URNS, adapter.discover(workdir).map(&:id),
                   "the unpacked range dirs are discoverable in place"
    end
  end

  def test_fetch_aborts_on_a_sha_pin_mismatch_with_the_tree_untouched
    body = stub_zip_body
    stub_request(:get, ZIP_URL).to_return(status: 200, body: body)
    Dir.mktmpdir do |workdir|
      error = assert_raises(Nabu::FetchError) { Nabu::Adapters::Edr.new.fetch(workdir) }
      assert_match(/sha256 pin/, error.message)
      assert_empty Dir.children(workdir), "a pin miss aborts BEFORE any tree mutation"
    end
  end

  def test_fetch_wraps_http_failure_in_fetch_error
    stub_request(:get, ZIP_URL).to_return(status: 500)
    Dir.mktmpdir do |workdir|
      assert_raises(Nabu::FetchError) { Nabu::Adapters::Edr.new.fetch(workdir) }
    end
  end

  # --- idempotency (load twice, counts unchanged) -------------------------------

  def test_loading_the_fixture_set_twice_is_idempotent
    db = store_test_db
    source = Nabu::Store::Source.create(slug: "edr", name: "EDR",
                                        adapter_class: "Nabu::Adapters::Edr",
                                        license_class: "attribution")
    first = Nabu::Store::Loader.new(db: db, source: source)
                               .load_from(Nabu::Adapters::Edr.new, workdir: FIXTURES)
    assert_equal 5, first.added
    assert_equal 0, first.errored
    assert_equal 20, db[:passages].count,
                 "4 + 8 + 7 lines + 1 :text fallback + 0 from the symbol-only record"

    second = Nabu::Store::Loader.new(db: db, source: source)
                                .load_from(Nabu::Adapters::Edr.new, workdir: FIXTURES)
    assert_equal 0, second.errored
    assert_equal 5, second.skipped, "a byte-identical reload skips every document"
    assert_equal 20, db[:passages].count
    assert_equal [1], db[:passages].distinct.select_map(:revision),
                 "a byte-identical reload bumps no revisions"
  end

  private

  def parse(urn)
    adapter = Nabu::Adapters::Edr.new
    ref = adapter.discover(FIXTURES).find { |candidate| candidate.id == urn }
    refute_nil ref, "expected discover to yield #{urn}"
    adapter.parse(ref)
  end

  # Zip the checked-in well-formed fixtures under the upstream layout
  # (nine range dirs at the zip ROOT — no single top dir) and return the
  # zip bytes.
  def stub_zip_body
    Dir.mktmpdir do |dir|
      staging = File.join(dir, "staging")
      %w[000001-025000 100001-125000 125001-150000 200001-225000].each do |range|
        FileUtils.mkdir_p(File.join(staging, range))
        Dir.glob(File.join(FIXTURES, range, "aEDR*.xml")).each do |path|
          FileUtils.cp(path, File.join(staging, range, File.basename(path)))
        end
      end
      zip_path = File.join(dir, "edr.zip")
      Nabu::Shell.run("zip", "-q", "-r", zip_path, ".", chdir: staging)
      return File.binread(zip_path)
    end
  end
end

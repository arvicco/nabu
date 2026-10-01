# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# ReM adapter tests (P40-5): the Reference Corpus of Middle High German
# (1050-1350), v2.1 TEI from Zenodo record 13982324, CC BY-SA 4.0 — the
# first cora-tei registrant (ReA/ReN ride the family when their licenses
# confirm). Fixtures are two whole zip members (test/fixtures/rem/README.md);
# fetch runs against a WebMock stub of the Zenodo artifact URL with the sha
# pin overridden to the stub zip's own sha (the iecor drill).
class RemTest < Minitest::Test
  include AdapterConformance
  include StoreTestDB
  include ParseTreeDigest

  FIXTURES = Nabu::TestSupport.fixtures("rem")

  ZIP_URL = "https://zenodo.org/api/records/13982324/files/ReM-v2.1_tei.zip/content"
  CORA_URL = "https://zenodo.org/api/records/13982324/files/ReM-v2.1_coraxml.zip/content"

  # The whole-tree parse digest of the TEI-only fixture tree (no coraxml/),
  # minted by the PRE-sibling adapter (commit f8466602) — the absent-zip
  # parity pin: today's canonical state must parse byte-identically.
  PRE_CORAXML_DIGEST = "3a6c589def3dbaf7893fd66f406360d0dcc2858c3a8a842a485ab8ebe5142bf6"

  DOC_URNS = %w[
    urn:nabu:rem:m058
    urn:nabu:rem:m218b
    urn:nabu:rem:m242
    urn:nabu:rem:m345
  ].freeze

  def conformance_adapter
    Nabu::Adapters::Rem.new
  end

  def conformance_workdir
    FIXTURES
  end

  def conformance_expected_source_id
    "rem"
  end

  # --- manifest ---------------------------------------------------------------

  def test_manifest_identifies_the_rem_source
    manifest = Nabu::Adapters::Rem.manifest
    assert_equal "rem", manifest.id
    assert_match(/Creative Commons Attribution-ShareAlike 4\.0 International/, manifest.license,
                 "the in-file <licence> grant, verbatim")
    assert_equal "attribution", manifest.license_class
    assert_equal "https://zenodo.org/records/13982324", manifest.upstream_url
    assert_equal "cora-tei", manifest.parser_family
  end

  # --- discover ---------------------------------------------------------------

  def test_discover_mints_one_ref_per_text_file
    refs = Nabu::Adapters::Rem.new.discover(FIXTURES).to_a
    assert_equal DOC_URNS, refs.map(&:id),
                 "urn:nabu:rem:<textid downcased>, sorted; README and non-M files never match"
    assert(refs.all? { |r| r.source_id == "rem" && r.metadata["language"] == "gmh" })
  end

  def test_discover_titles_come_from_the_header
    titles = Nabu::Adapters::Rem.new.discover(FIXTURES).to_h { |r| [r.id, r.metadata["title"]] }
    assert_equal "Sangspruchstrophe MF 'Namenlos IV'", titles["urn:nabu:rem:m058"]
    assert_equal "St. Galler Schularbeit, Exzerpt", titles["urn:nabu:rem:m218b"]
  end

  def test_discover_of_an_unfetched_workdir_yields_nothing
    Dir.mktmpdir do |dir|
      assert_empty Nabu::Adapters::Rem.new.discover(dir).to_a
    end
  end

  # --- parse -------------------------------------------------------------------

  def test_passages_are_manuscript_lines_cited_page_dot_line
    document = parse_urn("urn:nabu:rem:m058")
    assert_equal "gmh", document.language
    assert_equal %w[100v.5 100v.6], document.map { |p| p.urn.split(":").last },
                 "the primary (ed=1) lb milestones are the corpus's own layout grain"
  end

  def test_genre_code_projects_as_a_labeled_facet
    facets = parse_urn("urn:nabu:rem:m058").metadata["facets"]
    assert_equal({ "value" => "V", "raw" => "Vers" }, facets["genre"],
                 "P109-4 (№R-70): the ReM genre code reaches the facet lane")
  end

  def test_passage_text_is_the_diplomatic_layer_nfc_byte_pinned
    document = parse_urn("urn:nabu:rem:m058")
    line = document.find { |p| p.urn.end_with?(":100v.6") }
    # NFC byte pin: ſ is U+017F, uͦ is u + U+0366 (no precomposition exists,
    # so NFC keeps the combining mark) — canonical means canonical, the
    # diplomatic transcription is the witness. The normalized layer rides
    # the token lane, never the passage text.
    assert_equal "ginge wol uerwerden. ſin ere muͦz erſterben.", line.text
    assert line.text.unicode_normalized?(:nfc)
  end

  def test_the_gmh_fold_makes_diplomatic_text_findable_by_modern_spelling
    line = parse_urn("urn:nabu:rem:m058").find { |p| p.urn.end_with?(":100v.6") }
    assert_includes line.text_normalized, "sin ere muz ersterben",
                    "ſ folds to s (the sl precedent) and uͦ falls to the mark strip"
    refute_includes line.text_normalized, "ſ"
  end

  def test_gold_norm_and_lemma_ride_in_token_annotations
    Dir.mktmpdir do |dir|
      copy_tree_without(FIXTURES, dir, excluded: "coraxml")
      adapter = Nabu::Adapters::Rem.new
      ref = adapter.discover(dir).find { |r| r.id == "urn:nabu:rem:m058" }
      line = adapter.parse(ref).find { |p| p.urn.end_with?(":100v.5") }
      grimme = line.annotations["tokens"].find { |t| t["lemma"] == "grimme" }
      assert_equal({ "id" => "t5_m1", "form" => "grínme", "norm" => "grinme", "lemma" => "grimme" },
                   grimme, "without the sibling zip the TEI export is honestly norm+lemma")
    end
  end

  # --- the CorA-XML sibling zip: pos/msd --------------------------------------
  # Two real ReM-v2.1_coraxml.zip members (M058, M218B) ride the fixture
  # tree at the canonical layout (coraxml/cora-xml/M*.xml); the M242/M345
  # trims have no sibling — exactly today's per-document absence.

  def test_coraxml_pos_and_msd_merge_into_the_tei_token_records
    line = parse_urn("urn:nabu:rem:m058").find { |p| p.urn.end_with?(":100v.5") }
    grimme = line.annotations["tokens"].find { |t| t["id"] == "t5_m1" }
    assert_equal({ "id" => "t5_m1", "form" => "grínme", "norm" => "grinme", "lemma" => "grimme",
                   "pos" => "NA", "msd" => "Dat.Sg" }, grimme,
                 "joined on the upstream token id; CorA's <pos> and <infl> tags verbatim " \
                 "(infl rides as msd — the ReN sibling's key for the same lane)")
  end

  def test_coraxml_null_placeholders_never_ride
    tokens = parse_urn("urn:nabu:rem:m058").flat_map { |p| p.annotations["tokens"] }
    under = tokens.find { |t| t["id"] == "t9_m2" }
    assert_equal "PAVAP", under["pos"]
    refute under.key?("msd"), '"--" is CorA\'s null — dropped, never a value'
    stop = tokens.find { |t| t["id"] == "t7_m1" }
    assert_equal "$_", stop["pos"], "punctuation carries pos and no infl element at all"
    refute stop.key?("msd")
    assert(tokens.all? { |t| t.key?("pos") }, "every M058 token joins (censused: 2,579,276/2,579,276)")
  end

  def test_documents_without_a_coraxml_sibling_parse_unchanged
    tokens = parse_urn("urn:nabu:rem:m242").flat_map { |p| p.annotations["tokens"] }
    refute(tokens.any? { |t| t.key?("pos") || t.key?("msd") })
  end

  def test_unmatched_tei_tokens_are_censused_loudly
    Dir.mktmpdir do |dir|
      copy_tree_without(FIXTURES, dir, excluded: "nothing")
      path = File.join(dir, "coraxml", "cora-xml", "M058.xml")
      File.write(path, File.read(path).sub('<tok_anno id="t5_m1"', '<tok_anno id="t5_m9"'))
      adapter = Nabu::Adapters::Rem.new
      document = adapter.parse(adapter.discover(dir).find { |r| r.id == "urn:nabu:rem:m058" })
      assert_equal 1, document.metadata["coraxml_unmatched_tokens"],
                   "an id drift is a loud census, never a quarantine"
      tokens = document.flat_map { |p| p.annotations["tokens"] }
      refute tokens.find { |t| t["id"] == "t5_m1" }.key?("pos")
    end
  end

  def test_a_tree_without_the_coraxml_zip_parses_exactly_as_before
    Dir.mktmpdir do |dir|
      copy_tree_without(FIXTURES, dir, excluded: "coraxml")
      assert_equal PRE_CORAXML_DIGEST, tree_digest(Nabu::Adapters::Rem.new, dir),
                   "today's canonical state (no sibling zip) — zero diff, pinned from the " \
                   "pre-sibling adapter"
    end
  end

  def test_the_merge_adds_only_the_pos_and_msd_keys
    Dir.mktmpdir do |dir|
      copy_tree_without(FIXTURES, dir, excluded: "coraxml")
      adapter = Nabu::Adapters::Rem.new
      bare = adapter.discover(dir).to_h { |r| [r.id, adapter.parse(r)] }
      adapter.discover(FIXTURES).each do |ref|
        merged = adapter.parse(ref)
        before = bare.fetch(ref.id)
        assert_equal before.metadata, merged.metadata, ref.id
        assert_equal before.map(&:text), merged.map(&:text), ref.id
        stripped = merged.map do |p|
          p.annotations.merge("tokens" => p.annotations["tokens"].map { |t| t.except("pos", "msd") })
        end
        assert_equal before.map(&:annotations), stripped, ref.id
      end
    end
  end

  def test_the_coraxml_tree_never_mints_documents
    assert_equal DOC_URNS, Nabu::Adapters::Rem.new.discover(FIXTURES).map(&:id),
                 "coraxml/cora-xml/M058.xml matches the M*.xml name but is a sibling, not a text"
  end

  def test_coraxml_is_a_declared_materialization
    assert_equal ["coraxml"], Nabu::Adapters::Rem.materialized_paths
  end

  def test_loading_twice_is_idempotent
    catalog = store_test_db
    source = Nabu::Store::Source.create(slug: "rem", name: "ReM", adapter_class: "Nabu::Adapters::Rem",
                                        license_class: "attribution")
    loader = Nabu::Store::Loader.new(db: catalog, source: source)
    loader.load_from(Nabu::Adapters::Rem.new, workdir: FIXTURES, full: true)
    before = [catalog[:documents].select_map(%i[urn revision]).sort, catalog[:passages].count]
    loader.load_from(Nabu::Adapters::Rem.new, workdir: FIXTURES, full: true)
    assert_equal before, [catalog[:documents].select_map(%i[urn revision]).sort,
                          catalog[:passages].count]
  end

  def test_column_broken_lines_cite_folio_column_line
    document = parse_urn("urn:nabu:rem:m242")
    refs = document.map { |p| p.urn.split(":").last }
    assert_includes refs, "5ra.1"
    assert_includes refs, "5rb.1",
                    "two-column codices cite folio+column (5ra/5rb) — line numbers restart per column"
    refute_includes refs, "5r.1", "the bare folio ref would collide between the columns"
    assert_equal refs.size, refs.uniq.size
  end

  def test_line_number_restarts_take_the_positional_disambiguator
    document = parse_urn("urn:nabu:rem:m345")
    refs = document.map { |p| p.urn.split("urn:nabu:rem:m345:").last }
    assert_includes refs, "1"
    assert_includes refs, "1:b2",
                    "M345's per-entry line restarts (no upstream container) take the " \
                    "house :b2 positional disambiguator — never quarantine, never merge"
    assert_equal refs.size, refs.uniq.size, "every passage urn in the document is unique"
  end

  def test_edition_lineation_rides_passage_annotations
    document = parse_urn("urn:nabu:rem:m218b")
    third = document.find { |p| p.urn.end_with?(":96v.3") }
    assert_equal ["08"], third.annotations["edition_lines"]
    m058 = parse_urn("urn:nabu:rem:m058")
    refute(m058.any? { |p| p.annotations.key?("edition_lines") },
           "M058 carries no secondary lineation — the key is absent, never an empty list")
  end

  def test_document_metadata_carries_the_classification_lanes
    document = parse_urn("urn:nabu:rem:m058")
    assert_equal %w[mhd oberdeutsch ostoberdeutsch bairisch], document.metadata["dialects"],
                 "the langUsage localization chain — the future timeline/place lane"
    assert_equal "V", document.metadata["genre"]
    assert_equal "Poesie", document.metadata["topic"]
    assert_equal "Spruchdichtung", document.metadata["text_type"]
    assert_equal "Wien, Österr. Nationalbibl.", document.metadata["repository"]
    assert_equal "Cod. 160", document.metadata["ms_idno"]
    assert_equal 23, document.metadata["token_count"]
    refute document.metadata.key?("orig_date"),
           "both fixtures carry the '--' placeholder — no invented dating (isicily discipline)"
  end

  def test_a_translation_text_records_its_derivation
    assert_equal "latein", parse_urn("urn:nabu:rem:m218b").metadata["derived_from"]
  end

  def test_unrecognized_elements_ride_the_document_census
    Dir.mktmpdir do |dir|
      doctored = File.read(File.join(FIXTURES, "M058.xml"))
                     .sub("<w xml:id=\"t3_m1\"", "<seg>x</seg><w xml:id=\"t3_m1\"")
      File.write(File.join(dir, "M058.xml"), doctored)
      adapter = Nabu::Adapters::Rem.new
      document = adapter.parse(adapter.discover(dir).first)
      assert_equal({ "#text" => 1, "seg" => 1 }, document.metadata["unrecognized_elements"],
                   "loud census, not quarantine — the aozora precedent")
    end
  end

  def test_license_drift_quarantines_the_document
    Dir.mktmpdir do |dir|
      doctored = File.read(File.join(FIXTURES, "M058.xml"))
                     .sub("Creative Commons Attribution-ShareAlike 4.0 International (CC-BY-SA)",
                          "All rights reserved")
      File.write(File.join(dir, "M058.xml"), doctored)
      adapter = Nabu::Adapters::Rem.new
      error = assert_raises(Nabu::ParseError) { adapter.parse(adapter.discover(dir).first) }
      assert_match(/licence/i, error.message)
    end
  end

  def test_a_non_gmh_language_ident_quarantines_the_document
    Dir.mktmpdir do |dir|
      doctored = File.read(File.join(FIXTURES, "M058.xml"))
                     .sub("<language ident=\"gmh\">mhd</language>",
                          "<language ident=\"goh\">ahd</language>")
      File.write(File.join(dir, "M058.xml"), doctored)
      adapter = Nabu::Adapters::Rem.new
      assert_raises(Nabu::ParseError) { adapter.parse(adapter.discover(dir).first) }
    end
  end

  # --- the gold lemma flow ------------------------------------------------------

  def test_gold_lemmas_reach_the_passage_lemmas_index
    catalog = store_test_db
    fulltext = Nabu::Store.connect_fulltext("sqlite::memory:")
    source = Nabu::Store::Source.create(slug: "rem", name: "ReM",
                                        adapter_class: "Nabu::Adapters::Rem",
                                        license_class: "attribution")
    Nabu::Store::Loader.new(db: catalog, source: source)
                       .load_from(Nabu::Adapters::Rem.new, workdir: FIXTURES, full: true)
    Nabu::Store::Indexer.rebuild!(catalog: catalog, fulltext: fulltext)

    rows = fulltext[Nabu::Store::Indexer::LEMMA_TABLE].where(lemma_folded: "grimme").all
    assert_equal 1, rows.size, "the gold lemma grimme is indexed for gmh"
    assert_equal "grínme", rows[0][:surface_forms], "attested by the pristine diplomatic surface"
    assert rows[0][:urn].end_with?(":100v.5")
  ensure
    fulltext&.disconnect
  end

  # --- fetch (WebMock only, no network) ----------------------------------------
  # Two immutable Zenodo artifacts: the TEI zip (the text) + the CorA-XML
  # zip (pos/msd), both sha-pinned BEFORE any tree mutation (the openiti
  # two-arm choreography).

  def test_fetch_downloads_both_artifacts_verifies_both_pins_and_unpacks
    tei = stub_zip_body
    cora = stub_cora_zip_body
    stub_artifacts(tei, cora)
    Dir.mktmpdir do |workdir|
      adapter = Nabu::Adapters::Rem.new(pin: sha(tei), cora_pin: sha(cora))
      report = adapter.fetch(workdir)
      assert_instance_of Nabu::FetchReport, report
      assert_equal sha(tei), report.sha, "the text artifact's sha is the ledger pin"
      assert_match(/coraxml sha pin verified/, report.notes)
      assert File.file?(File.join(workdir, "coraxml", "cora-xml", "M058.xml")),
             "the ReM-v2.1_coraxml/ top dir strips into the declared coraxml/ materialization"
      assert_equal DOC_URNS, adapter.discover(workdir).map(&:id),
                   "the unpacked tei/ tree is discoverable in place; coraxml/ mints no documents"
      m058 = adapter.parse(adapter.discover(workdir).first)
      assert_equal "NA", m058.first.annotations["tokens"].find { |t| t["id"] == "t5_m1" }["pos"]
    end
  end

  def test_a_refetch_keeps_the_sibling_tree_out_of_the_deletion_set
    tei = stub_zip_body
    cora = stub_cora_zip_body
    stub_artifacts(tei, cora)
    Dir.mktmpdir do |workdir|
      adapter = Nabu::Adapters::Rem.new(pin: sha(tei), cora_pin: sha(cora))
      adapter.fetch(workdir)
      adapter.fetch(workdir)
      refute Dir.exist?(File.join(workdir, Nabu::Adapter::ATTIC_DIRNAME)),
             "neither arm's tree swap dooms the other's files"
    end
  end

  def test_fetch_aborts_on_a_sha_pin_mismatch_with_the_tree_untouched
    stub_artifacts(stub_zip_body, stub_cora_zip_body)
    Dir.mktmpdir do |workdir|
      error = assert_raises(Nabu::FetchError) { Nabu::Adapters::Rem.new.fetch(workdir) }
      assert_match(/sha256 pin/, error.message)
      assert_empty Dir.children(workdir), "a pin miss aborts BEFORE any tree mutation"
    end
  end

  def test_a_coraxml_pin_miss_aborts_with_the_tree_untouched
    tei = stub_zip_body
    stub_artifacts(tei, stub_cora_zip_body)
    Dir.mktmpdir do |workdir|
      error = assert_raises(Nabu::FetchError) { Nabu::Adapters::Rem.new(pin: sha(tei)).fetch(workdir) }
      assert_match(/ReM-v2\.1_coraxml\.zip.*sha256 pin/, error.message)
      assert_empty Dir.children(workdir), "both arms verify BEFORE either tree mutates"
    end
  end

  def test_fetch_wraps_http_failure_in_fetch_error
    stub_request(:get, ZIP_URL).to_return(status: 500)
    stub_request(:get, CORA_URL).to_return(status: 500)
    Dir.mktmpdir do |workdir|
      assert_raises(Nabu::FetchError) { Nabu::Adapters::Rem.new.fetch(workdir) }
    end
  end

  # --- remote-health probe shape ------------------------------------------------

  def test_probe_heads_both_zenodo_artifacts_with_no_metadata_endpoint
    assert_equal :http_zip, Nabu::Adapters::Rem.remote_probe_strategy
    targets = Nabu::Adapters::Rem.http_probe_targets
    assert_equal [ZIP_URL, CORA_URL], targets.map(&:zip_url)
    assert(targets.all? { |t| t.metadata_url.nil? }, "the license lives in-file and on the record page")
    assert_equal ["", "coraxml"], targets.map(&:state_subdir)
    assert(targets.all? { |t| t.state_file == Nabu::ZipFetch::STATE_FILE })
  end

  # --- registry round-trip ------------------------------------------------------

  def test_registry_resolves_rem_and_manifest_agrees
    registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
    entry = registry["rem"]
    refute_nil entry, "rem must be registered in config/sources.yml"
    assert_equal Nabu::Adapters::Rem, entry.adapter_class
    assert entry.wired, "first sync verified + owner-flipped 2026-07-22"
    assert_equal Nabu::Adapters::Rem.manifest, entry.manifest
  end

  private

  def parse_urn(urn)
    adapter = Nabu::Adapters::Rem.new
    ref = adapter.discover(FIXTURES).find { |r| r.id == urn }
    refute_nil ref, "expected discover to yield #{urn}"
    adapter.parse(ref)
  end

  def sha(body)
    Digest::SHA256.hexdigest(body)
  end

  def stub_artifacts(tei, cora)
    headers = { "Content-Type" => "application/zip", "Last-Modified" => "Mon, 28 Oct 2024 12:00:00 GMT" }
    stub_request(:get, ZIP_URL).to_return(status: 200, body: tei, headers: headers)
    stub_request(:get, CORA_URL).to_return(status: 200, body: cora, headers: headers)
  end

  # Zip the checked-in CorA-XML members under the upstream layout
  # (ReM-v2.1_coraxml/cora-xml/M*.xml + README).
  def stub_cora_zip_body
    Dir.mktmpdir do |dir|
      FileUtils.cp_r(File.join(FIXTURES, "coraxml"), File.join(dir, "ReM-v2.1_coraxml"))
      File.write(File.join(dir, "ReM-v2.1_coraxml", "README"), "Reference Corpus of Middle High German\n")
      zip_path = File.join(dir, "cora.zip")
      Nabu::Shell.run("zip", "-q", "-r", zip_path, "ReM-v2.1_coraxml", chdir: dir)
      return File.binread(zip_path)
    end
  end

  # Zip the checked-in fixtures under the upstream layout
  # (ReM-v2.1_tei/tei/M*.xml + README) and return the zip bytes.
  def stub_zip_body
    Dir.mktmpdir do |dir|
      staging = File.join(dir, "ReM-v2.1_tei")
      FileUtils.mkdir_p(File.join(staging, "tei"))
      Dir.glob(File.join(FIXTURES, "M*.xml")).each do |path|
        FileUtils.cp(path, File.join(staging, "tei", File.basename(path)))
      end
      File.write(File.join(staging, "README"), "Reference Corpus of Middle High German\n")
      zip_path = File.join(dir, "rem.zip")
      Nabu::Shell.run("zip", "-q", "-r", zip_path, "ReM-v2.1_tei", chdir: dir)
      return File.binread(zip_path)
    end
  end
end

# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

# The local-library adapter (P19-4): the second local shelf, and — unlike
# the dossier shelf — a DOCUMENT-shaped source, so the FULL shared
# conformance suite applies (with the metadata-only hook for its declared
# textless scans/images). PDF extraction is injected (FAKE_PDF_TEXT) so the
# suite never depends on mutool being installed; the fake carries the text
# the constructed fixture PDF verifiably holds (PDFKit-extracted at fixture
# construction — fixtures README), and a guarded live test exercises real
# mutool when present.
class LocalLibraryTest < Minitest::Test
  include AdapterConformance
  include StoreTestDB

  WORKDIR = File.join(Nabu::TestSupport.fixtures("local-library"), "shelf")

  LESKIEN_P1 = <<~PAGE
    Handbuch der altbulgarischen (altkirchenslavischen) Sprache.
    Grammatik. Texte. Glossar. Von A. Leskien. Weimar, 1871.
    Die altbulgarische Sprache ist die aelteste schriftlich
    ueberlieferte Form des Slavischen. Ihre Denkmaeler stammen
    aus dem Kreise der Uebersetzungen, welche Kyrill und Method
    und ihre Schueler im neunten Jahrhundert begonnen haben.
  PAGE

  LESKIEN_P2 = <<~PAGE
    Erster Abschnitt. Lautlehre.
    Das Alphabet der altbulgarischen Denkmaeler ist ein
    doppeltes: das glagolitische und das kyrillische. Die
    Handschriften des aeltesten Typus, Zographensis und
    Marianus, sind glagolitisch geschrieben.
  PAGE

  # What mutool would extract from the two fixture PDFs (whitespace
  # normalized; the guarded live test pins substrings, not bytes).
  PDF_PAGES = {
    "leskien-1871-handbuch.pdf" => [LESKIEN_P1, LESKIEN_P2],
    "scan-plate.pdf" => [""]
  }.freeze

  FAKE_PDF_TEXT = ->(path) { PDF_PAGES.fetch(File.basename(path)) }

  URN_PREFIX = "urn:nabu:local-library:slavistics"

  def adapter = Nabu::Adapters::LocalLibrary.new(pdf_text: FAKE_PDF_TEXT)

  # -- conformance hooks -------------------------------------------------------

  def conformance_adapter = adapter
  def conformance_workdir = WORKDIR
  def conformance_expected_source_id = "local-library"

  # Zero passages are honest ONLY for documents carrying the shelf's own
  # marker (a textless scan/image awaiting HTR) — never blanket-allowed.
  def conformance_metadata_only?(document)
    document.metadata["text_layer"] == "none"
  end

  # -- identity and routing ----------------------------------------------------

  def test_manifest_is_valid_with_the_research_private_default
    manifest = adapter.manifest
    assert_kind_of Nabu::SourceManifest, manifest
    assert_equal "local-library", manifest.id
    assert_equal "research_private", manifest.license_class,
                 "acquired scholarly PDFs are mostly copyrighted — the shelf class is the conservative one"
    assert_equal "library-manifest", manifest.parser_family
  end

  def test_content_kind_stays_passages_and_reference_edges_is_declared
    assert_equal :passages, Nabu::Adapters::LocalLibrary.content_kind,
                 "articles parse to Document+Passage — the :passages content shape; " \
                 "article-ness is document metadata, not loader routing"
    assert Nabu::Adapters::LocalLibrary.reference_edges?
    refute Nabu::Adapter.reference_edges?, "the capability defaults off"
    assert_empty Nabu::Adapters::LocalLibrary.upstream_repo_urls
  end

  def test_discover_yields_manifest_entries_with_files_on_disk_in_manifest_order
    assert_equal ["#{URN_PREFIX}:leskien-1871-handbuch", "#{URN_PREFIX}:jagic-notes",
                  "#{URN_PREFIX}:scan-plate", "#{URN_PREFIX}:codex-plate"],
                 adapter.discover(WORKDIR).map(&:id),
                 "the missing-notes.txt entry (manifested but absent) must yield no ref"
  end

  # -- the census: every gap is loud --------------------------------------------

  def test_census_reports_missing_and_unmanifested_files
    skips = adapter.discovery_skips(WORKDIR)
    assert_equal 0, skips.skipped_by_rule, "nothing on this shelf skips by rule — the manifest is the record"
    assert_equal 2, skips.unrecognized
    refute_predicate skips, :clean?
    assert(skips.notes.any? { |note| note.match?(%r{slavistics/missing-notes\.txt: manifested but MISSING}) })
    assert(skips.notes.any? { |note| note.match?(%r{slavistics/stray-unfiled\.txt: unmanifested}) })
  end

  def test_census_reports_uncataloged_collections_and_malformed_manifests
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "drop"))
      File.write(File.join(dir, "drop", "a.pdf"), "x")
      FileUtils.mkdir_p(File.join(dir, "bad"))
      File.write(File.join(dir, "bad", "manifest.yml"), "file: not-a-list\n")
      File.write(File.join(dir, "loose.pdf"), "x")
      skips = adapter.discovery_skips(dir)
      assert_equal 3, skips.unrecognized
      assert(skips.notes.any? { |note| note.match?(%r{drop/: no manifest\.yml}) })
      assert(skips.notes.any? { |note| note.match?(%r{bad/manifest\.yml:}) })
      assert(skips.notes.any? { |note| note.match?(/loose\.pdf: loose file outside any collection/) })
      assert_empty adapter.discover(dir).to_a, "nothing catalogued, nothing discovered"
    end
  end

  # -- parsing: the honest failure ladder ---------------------------------------

  def test_pdf_with_text_layer_mints_page_grain_passages
    document = parse_urn("#{URN_PREFIX}:leskien-1871-handbuch")
    assert_equal ["#{document.urn}:p1", "#{document.urn}:p2"], document.map(&:urn),
                 "page grain — the only citation unit a PDF keeps stable"
    assert_equal [1, 2], document.map(&:sequence)
    assert_includes document.passages[1].text, "Lautlehre"
    assert_equal "pages", document.metadata["text_layer"]
    assert_equal "deu", document.language
  end

  def test_default_license_entry_inherits_the_source_class_via_nil_override
    document = parse_urn("#{URN_PREFIX}:leskien-1871-handbuch")
    assert_nil document.license_override,
               "no manifest license_class → inherit the shelf's research_private, visibly from the source row"
  end

  def test_an_explicit_open_entry_becomes_a_license_override
    document = parse_urn("#{URN_PREFIX}:jagic-notes")
    assert_equal "open", document.license_override
  end

  def test_manifest_metadata_rides_into_the_document_the_edh_persons_way
    metadata = parse_urn("#{URN_PREFIX}:leskien-1871-handbuch").metadata
    assert_equal "article", metadata["kind"]
    assert_equal "slavistics", metadata["collection"]
    assert_equal "A. Leskien", metadata["creator"]
    assert_equal 1871, metadata["year"]
    assert_equal %w[grammar ocs], metadata["tags"]
    assert_equal ["urn:nabu:local-library:slavistics:jagic-notes", "chu"], metadata["related"]
    assert_match(/public domain/, metadata["provenance"])
  end

  def test_source_url_lane_rides_into_document_metadata_when_present
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "inbox"))
      File.write(File.join(dir, "inbox", "notes.txt"), "Ein Absatz.\n")
      File.write(File.join(dir, "inbox", "manifest.yml"), <<~YAML)
        - file: notes.txt
          source_url: https://archive.org/download/x/notes.txt
      YAML
      document = adapter.parse(adapter.discover(dir).first)
      assert_equal "https://archive.org/download/x/notes.txt", document.metadata["source_url"],
                   "a url ingest's provenance lane is queryable downstream"
      assert_nil parse_urn("#{URN_PREFIX}:jagic-notes").metadata["source_url"],
                 "local ingests carry no such lane"
    end
  end

  def test_text_file_mints_paragraph_passages_nfc_clean
    document = parse_urn("#{URN_PREFIX}:jagic-notes")
    assert_equal ["#{document.urn}:1", "#{document.urn}:2"], document.map(&:urn)
    assert_includes document.passages[1].text, "зачѧло"
    document.each { |passage| assert passage.text.unicode_normalized?(:nfc) }
    assert_nil document.metadata["text_layer"], "born-digital text needs no extraction marker"
  end

  def test_textless_scan_pdf_is_metadata_only_marked_never_quarantined
    document = parse_urn("#{URN_PREFIX}:scan-plate")
    assert_predicate document, :empty?
    assert_equal "none", document.metadata["text_layer"]
  end

  def test_image_is_metadata_only_awaiting_the_htr_era
    document = parse_urn("#{URN_PREFIX}:codex-plate")
    assert_predicate document, :empty?
    assert_equal "none", document.metadata["text_layer"]
    assert_equal "Codex plate photograph", document.title
  end

  def test_genuinely_corrupt_pdf_quarantines_via_parse_error
    broken = lambda do |path|
      raise Nabu::PdfText::Error, "mutool text extraction failed for #{path} (bad xref)"
    end
    with_collection("broken.pdf" => "not really a pdf") do |dir|
      ref = Nabu::Adapters::LocalLibrary.new(pdf_text: broken).discover(dir).first
      error = assert_raises(Nabu::ParseError) { Nabu::Adapters::LocalLibrary.new(pdf_text: broken).parse(ref) }
      assert_match(/bad xref/, error.message)
    end
  end

  def test_undecodable_text_file_quarantines_via_parse_error
    with_collection("notes.txt" => "pre \xC3 post".b) do |dir|
      ref = adapter.discover(dir).first
      assert_raises(Nabu::ParseError) { adapter.parse(ref) }
    end
  end

  # -- fetch: the LocalFetch pin/vanished/attic story (P19-1, verbatim) ---------

  def test_fetch_scans_and_pins_every_file_manifests_and_strays_included
    with_tree_copy do |tree|
      report = adapter.fetch(tree)
      assert_kind_of Nabu::FetchReport, report
      assert_equal 6, report.repos.size, "manifest.yml + 4 content files + the unmanifested stray all pin"
      assert report.repos.key?("local:slavistics/manifest.yml")
      assert report.repos.key?("local:slavistics/stray-unfiled.txt")
      assert_nil report.notes
    end
  end

  def test_fetch_keeps_a_vanished_files_pin_and_says_so
    with_tree_copy do |tree|
      adapter.fetch(tree)
      FileUtils.rm(File.join(tree, "slavistics", "jagic-notes.txt"))
      report = adapter.fetch(tree)
      assert report.repos.key?("local:slavistics/jagic-notes.txt"), "the pin lingers at its last-known sha"
      assert_match(/VANISHED/, report.notes)
    end
  end

  def test_fetch_on_a_missing_tree_names_the_shelfs_own_front_door
    error = assert_raises(Nabu::FetchError) { adapter.fetch(File.join(Dir.mktmpdir, "empty")) }
    assert_match(/no local tree/, error.message)
    assert_match(/manifest\.yml/, error.message)
  end

  def test_atticked_file_rediscovers_as_retained_with_passages_intact
    with_tree_copy do |tree|
      adapter.fetch(tree) # first scan records the state "retired" is judged against
      attic = File.join(tree, Nabu::Adapter::ATTIC_DIRNAME, "slavistics")
      FileUtils.mkdir_p(attic)
      FileUtils.mv(File.join(tree, "slavistics", "jagic-notes.txt"), File.join(attic, "jagic-notes.txt"))
      report = adapter.fetch(tree)
      assert_match(/1 file\(s\) retired/, report.notes)

      retained = adapter.discover(tree).find { |ref| ref.id == "#{URN_PREFIX}:jagic-notes" }
      assert retained.metadata[Nabu::Adapter::RETAINED_KEY], "the retired file is rediscovered retained"
      document = adapter.parse(retained)
      assert_equal 2, document.size, "the retired document's passages persist from the attic copy"
      census = adapter.discovery_skips(tree)
      assert(census.notes.none? { |note| note.include?("jagic-notes") }, "atticked is retired, not missing")
    end
  end

  # -- loader round-trip: idempotency, the missing entry, metadata-only rows ----

  def test_loads_idempotently_with_metadata_only_documents_and_no_ghost_for_missing
    db = store_test_db
    source = Nabu::Store::Source.create(slug: "local-library", name: "L", adapter_class: "X",
                                        license_class: "research_private")
    loader = Nabu::Store::Loader.new(db: db, source: source)
    first = loader.load_from(adapter, workdir: WORKDIR)
    assert_equal 4, first.added
    assert_equal 0, first.errored
    assert_equal 4, Nabu::Store::Document.count
    assert_equal 4, Nabu::Store::Passage.count, "2 pages + 2 paragraphs; metadata-only docs add none"
    assert_nil Nabu::Store::Document.first(urn: "#{URN_PREFIX}:missing-notes"),
               "a manifested-but-missing entry never mints a catalog row"

    second = loader.load_from(adapter, workdir: WORKDIR)
    assert_equal 4, second.skipped
    assert_equal 0, second.added + second.updated + second.withdrawn
  end

  # -- live mutool (present on the owner's box, absent in CI-ish rigs) ----------

  def test_real_mutool_extraction_agrees_with_the_constructed_fixture
    skip "mutool not on PATH — the injected-extractor tests carry the suite" unless mutool_available?

    pages = Nabu::PdfText.pages(File.join(WORKDIR, "slavistics", "leskien-1871-handbuch.pdf"))
    assert_equal 2, pages.size
    assert_includes pages[0], "altbulgarischen"
    assert_includes pages[1], "Lautlehre"
    assert_empty Nabu::PdfText.pages(File.join(WORKDIR, "slavistics", "scan-plate.pdf")).join.strip,
                 "the constructed scan PDF must stay textless"
  end

  private

  def parse_urn(urn)
    ref = adapter.discover(WORKDIR).find { |candidate| candidate.id == urn }
    refute_nil ref, "no ref for #{urn}"
    adapter.parse(ref)
  end

  def with_tree_copy
    Dir.mktmpdir do |dir|
      tree = File.join(dir, "local-library")
      FileUtils.cp_r(WORKDIR, tree)
      yield tree
    end
  end

  # A tmpdir shelf with one collection whose manifest lists +files+ (written
  # with the given bodies). The manifest format is nabu's own, so writing one
  # in a test is legitimate (the local-language precedent).
  def with_collection(files)
    Dir.mktmpdir do |dir|
      collection = File.join(dir, "c")
      FileUtils.mkdir_p(collection)
      manifest = +""
      files.each do |name, body|
        File.binwrite(File.join(collection, name), body)
        manifest << "- file: #{name}\n"
      end
      File.write(File.join(collection, "manifest.yml"), manifest)
      yield dir
    end
  end

  def mutool_available?
    ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).any? do |dir|
      File.executable?(File.join(dir, "mutool"))
    end
  end
end

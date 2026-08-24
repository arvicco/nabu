# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

# Nabu::Adapters::Cme (P82-2): the Corpus of Middle English Prose and Verse —
# the Middle English Compendium's text corpus (University of Michigan),
# ~297 Middle English texts as TCP-schema XML, fetched from the corpus
# editors' own companion site (medictionary.info /texts/ autoindex — the
# May-2026 normalization, grant №77-2 P.F. Schaffner 2026-08-20). First
# rider of the tcp-xml family; the adapter composes the family and owns
# none of it (the EEBO-TCP reuse design).
#
# Fixtures: four WHOLE real corpus files (test/fixtures/cme/texts/,
# retrieved 2026-08-23) covering the format's main shapes — Phase-3 prose
# (CME301), Phases-1-2 verse with front matter (tenwives), dialogue with
# SP/SPEAKER (CME00011), and the nested-TEXT surprise (CME00121). See the
# fixture README.
#
# THE LICENSE: open — the downloads page verbatim ("available for free
# downloading, with no restrictions on use or reuse") + the per-file
# AVAILABILITY public-domain statement (identical across all 297 files,
# censused 2026-08-23) + the personal grant №77-2. Credit rides the
# manifest credit seam (appreciated, not insisted — carried anyway).
class CmeTest < Minitest::Test
  include AdapterConformance
  include StoreTestDB

  CATECHISM = "urn:nabu:cme:CME00011"
  CAROLS = "urn:nabu:cme:CME00121"
  HEMATOSCOPY = "urn:nabu:cme:CME301"
  TENWIVES = "urn:nabu:cme:tenwives"

  def conformance_adapter = Nabu::Adapters::Cme.new

  def conformance_workdir = Nabu::TestSupport.fixtures("cme")

  def conformance_expected_source_id = "cme"

  def adapter = conformance_adapter

  def workdir = conformance_workdir

  # -- discover ---------------------------------------------------------------

  def test_discover_yields_one_ref_per_text_file_sorted_by_urn
    refs = adapter.discover(workdir).to_a
    assert_equal [CATECHISM, CAROLS, HEMATOSCOPY, TENWIVES], refs.map(&:id),
                 "one document per texts/<name>.xml, urn urn:nabu:cme:<name> (filename verbatim — " \
                 "the IDG id is a shared placeholder, never an identity), sorted"
    assert(refs.all? { |ref| ref.source_id == "cme" })
    assert(refs.all? { |ref| ref.id == adapter.parse(ref).urn },
           "ref.id IS the document urn (the sync-breaker identity)")
  end

  def test_discover_never_yields_the_fetch_listing_or_the_state_file
    Dir.mktmpdir do |dir|
      texts = File.join(dir, "texts")
      FileUtils.mkdir_p(texts)
      FileUtils.cp(File.join(workdir, "texts", "CME301.xml"), texts)
      File.write(File.join(dir, Nabu::CmeFetch::STATE_FILE), "{}")
      File.write(File.join(texts, "notes.txt"), "not a record")
      assert_equal [HEMATOSCOPY], adapter.discover(dir).map(&:id)
    end
  end

  # -- parse: language, grain, provenance -------------------------------------

  def test_every_passage_is_middle_english
    document = adapter.parse(ref_for(TENWIVES))
    assert_equal "enm", document.language
    assert(document.all? { |p| p.language == "enm" },
           "the corpus's own definition is the claim — upstream LANGUSAGE declarations " \
           "are inconsistent (censused: some files declare only their FOREIGN languages)")
  end

  def test_verse_parses_at_line_grain_and_prose_at_block_grain
    assert_equal 124, adapter.parse(ref_for(TENWIVES)).count, "3 title-page blocks + head + 120 lines"
    assert_equal 64, adapter.parse(ref_for(HEMATOSCOPY)).count, "2 heads + 62 prose blocks"
    line = adapter.parse(ref_for(TENWIVES)).to_a[8]
    assert_equal "#{TENWIVES}:d2.l5", line.urn
    assert_equal "Howe .x. wyffys satt at þe nale,", line.text,
                 "yogh/thorn and superscript <HI> survive verbatim, NFC"
  end

  def test_the_speaker_annotation_reaches_the_stored_shape
    document = adapter.parse(ref_for(CATECHISM))
    assert_equal "Clerk:", document.to_a[2].annotations["speaker"]
  end

  def test_header_provenance_rides_document_metadata
    metadata = adapter.parse(ref_for(TENWIVES)).metadata
    assert_equal "tenwives", metadata["idno"]
    assert_equal "1871", metadata["source_date"]
    assert_includes metadata["availability"], "public domain"
  end

  def test_no_per_document_license_override_the_source_class_governs
    adapter.discover(workdir).each do |ref|
      assert_nil adapter.parse(ref).license_override,
                 "#{ref.id}: the AVAILABILITY statement is one uniform PD text across the " \
                 "corpus (censused) — the source-level open class already says it; " \
                 "no per-document override machinery to drift"
    end
  end

  # -- manifest + probe -------------------------------------------------------

  def test_manifest_records_the_grant_and_the_open_terms_verbatim
    manifest = adapter.manifest
    assert_equal "cme", manifest.id
    assert_equal "open", manifest.license_class
    assert_equal "tcp-xml", manifest.parser_family
    assert_includes manifest.license, "no restrictions on use or reuse"
    assert_includes manifest.license, "№77-2"
    assert_includes manifest.credit, "Corpus of Middle English",
                    "credit appreciated-not-insisted — carried anyway (the grant's spirit)"
    assert_includes manifest.credit, "University of Michigan"
  end

  def test_remote_probe_is_a_liveness_only_head_of_the_autoindex
    assert_equal :http_zip, Nabu::Adapters::Cme.remote_probe_strategy
    targets = Nabu::Adapters::Cme.http_probe_targets
    assert_equal 1, targets.size
    target = targets.first
    assert target.liveness_only, "a crawl fetch whose state file pins an aggregate sha — " \
                                 "liveness is the honest verdict"
    assert_equal "http://www.medictionary.info/texts/", target.zip_url
    assert_equal Nabu::CmeFetch::STATE_FILE, target.state_file
  end

  # -- fetch wiring -----------------------------------------------------------

  def test_fetch_delegates_to_the_crawl_and_reports_the_census
    listing = File.binread(File.join(workdir, "fetch", "texts-index.html"))
    xml = File.binread(File.join(workdir, "texts", "CME301.xml"))
    stub_request(:get, "http://www.medictionary.info/texts/")
      .to_return(status: 200, body: listing, headers: { "Content-Type" => "text/html" })
    stub_request(:get, %r{http://www\.medictionary\.info/texts/.+\.xml\z})
      .to_return(status: 200, body: xml, headers: { "Content-Type" => "text/xml" })
    Dir.mktmpdir do |dir|
      report = Nabu::Adapters::Cme.new(delay: 0).fetch(dir)
      assert_kind_of Nabu::FetchReport, report
      assert_match(/6 texts listed, 6 fetched/, report.notes)
      assert_equal 6, Dir.children(File.join(dir, "texts")).grep(/\.xml\z/).size
    end
  end

  def test_fetch_failures_abort_the_sync_as_fetch_error
    stub_request(:get, "http://www.medictionary.info/texts/")
      .to_return(status: 200, body: "<html>outage</html>")
    Dir.mktmpdir do |dir|
      error = assert_raises(Nabu::FetchError) { Nabu::Adapters::Cme.new(delay: 0).fetch(dir) }
      assert_match(/cme fetch failed/, error.message)
    end
  end

  # -- store: idempotent load -------------------------------------------------

  def test_loads_idempotently_into_the_store
    db = store_test_db
    source = create_source(db)
    first = Nabu::Store::Loader.new(db: db, source: source).load_from(adapter, workdir: workdir)
    assert_equal 4, first.added
    assert_equal 0, first.errored
    assert_equal 467, db[:passages].count, "64 + 124 + 125 + 154 across the four fixture texts"

    second = Nabu::Store::Loader.new(db: db, source: source).load_from(adapter, workdir: workdir)
    assert_equal 0, second.errored
    assert_equal 4, second.skipped, "a byte-identical reload skips every document"
    assert_equal 467, db[:passages].count
    assert_equal [1], db[:passages].distinct.select_map(:revision)
  ensure
    db&.disconnect
  end

  private

  def ref_for(urn)
    adapter.discover(workdir).to_a.find { |ref| ref.id == urn } || flunk("no ref #{urn}")
  end

  def create_source(_db)
    Nabu::Store::Source.create(
      slug: "cme", name: "Corpus of Middle English", adapter_class: "Nabu::Adapters::Cme",
      license_class: "open"
    )
  end
end

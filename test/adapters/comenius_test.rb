# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# Nabu::Adapters::Comenius: the twelve LINDAT TEI editions of Komenský's
# devotional writings on the DJAK 3 text (CC BY 4.0). Fixtures: three whole
# real files — Pres boží (1624), Listové do nebe (1619) and the Dutch
# Bazuine des genaden jaar (1632) — in their handle subdirectories (the
# fetch layout). No network: fetch runs against WebMock stubs.
class ComeniusTest < Minitest::Test
  include AdapterConformance
  include StoreTestDB

  FIXTURES = Nabu::TestSupport.fixtures("comenius")
  PRES = "urn:nabu:comenius:pres-bozi"
  LISTOVE = "urn:nabu:comenius:listove"
  BAZUINE = "urn:nabu:comenius:bazuine"
  DOC_URNS = [BAZUINE, LISTOVE, PRES].freeze

  def conformance_adapter = Nabu::Adapters::Comenius.new

  def conformance_workdir = FIXTURES

  def conformance_expected_source_id = "comenius"

  def adapter = conformance_adapter

  def parse(urn) = adapter.parse(adapter.discover(FIXTURES).find { |ref| ref.id == urn })

  def test_manifest_records_the_cc_by_items
    manifest = Nabu::Adapters::Comenius.manifest
    assert_equal "attribution", manifest.license_class
    assert_match(/Creative Commons - Attribution 4\.0 International \(CC BY 4\.0\)/, manifest.license)
    assert_equal "comenius-tei", manifest.parser_family
    assert_equal 12, Nabu::Adapters::Comenius::ITEMS.size, "one bitstream per LINDAT item"
  end

  def test_discover_mints_one_document_per_work_file
    refs = adapter.discover(FIXTURES).to_a
    assert_equal DOC_URNS, refs.map(&:id)
    assert_equal "20.500.12800/1-6288", refs.find { |ref| ref.id == PRES }.metadata["handle"]
    Dir.mktmpdir { |dir| assert_empty adapter.discover(dir).to_a }
  end

  def test_slugs_come_from_the_filename_work_part
    assert_equal "pres-bozi", Nabu::Adapters::Comenius.slug_for("06_DJAK_03_Pres_Bozi.xml")
    assert_equal "truchlivy-iv", Nabu::Adapters::Comenius.slug_for("01_DJAK_03_Truchlivy_IV.xml")
    assert_nil Nabu::Adapters::Comenius.slug_for("DJAK.xsl")
  end

  def test_the_text_reads_the_lemma_and_the_witness_readings_ride_the_apparatus
    document = parse(PRES)
    assert_equal "cs", document.language
    assert_equal 27, document.size
    salutation = document.passages[1]
    assert_equal "#{PRES}:2", salutation.urn
    assert_equal "Má důvěrně laskavá paní,", salutation.text, "the DJAK lemma, never the print's Ma"
    assert_equal [{ "lem" => "Má", "wit" => "#St", "rdg" => "Ma" }], salutation.annotations["apparatus"]
    assert_equal "417", salutation.annotations["page"], "the DJAK 3 page the block starts on"
  end

  def test_footnote_glosses_and_marginalia_never_enter_the_text
    document = parse(PRES)
    heading = document.first
    assert_equal "UROZENÉ, ŠLECHETNÉ A BOHOBOJNÉ PANÍ, PANÍ N. N. z N. etc.", heading.text
    assert_equal "head", heading.annotations["block"]
    assert_match(/Nejmenovanou adresátku/, heading.annotations["notes"].first)
    marginal = document.find { |passage| passage.annotations["marginalia"] }
    refute_nil marginal, "the print's margin notes ride annotations"
    marginal.annotations["marginalia"].each { |note| refute_includes marginal.text, note }
    document.each { |passage| refute_match(/Srov\. /, passage.text, "#{passage.urn}: an editor's gloss leaked") }
  end

  def test_the_historic_print_page_rides_beside_the_edition_page
    passage = parse(PRES).passages[2]
    assert_equal({ "n" => "A2", "ed" => "#St" }, passage.annotations["print_page"])
  end

  def test_the_header_is_mined_for_title_date_and_edition
    metadata = parse(LISTOVE).metadata
    assert_equal "LISTOVÉ DO NEBE", parse(LISTOVE).title
    assert_equal({ "not_before" => 1619, "not_after" => 1619, "raw" => "LÉTA PÁNĚ MDCXIX" }, metadata["date"])
    assert_equal "DJAK 3", metadata["edition"]
    assert_equal "Jan Amos Komenský", metadata["author"]
    assert_equal "Tomáš Havelka", metadata["tei_encoding"]
    assert_match(/\ALISTOVÉ DO NEBE/i, metadata["title_page"])
  end

  def test_the_editorial_back_matter_stays_out
    document = parse(PRES)
    document.each { |passage| refute_match(/INFORMACE O DÍLE|Spisek Pres boží byl napsán/, passage.text) }
  end

  def test_the_dutch_work_and_latin_blocks_take_their_own_language
    bazuine = parse(BAZUINE)
    assert_equal "nl", bazuine.language
    assert(bazuine.passages.any? { |passage| passage.language == "nl" })
    languages = [PRES, LISTOVE, BAZUINE].flat_map { |urn| parse(urn).map(&:language) }.uniq.sort
    assert_empty languages - %w[cs lat nl], "xml:lang la reads as the house lat"
  end

  def test_comenius_is_registered_for_the_structured_metadata_dates_shape
    assert_equal :structured, Nabu::Store::TimelineBuilder::MetadataDates::SHAPES["comenius"]
  end

  def test_loads_idempotently_into_the_store
    db = store_test_db
    source = Nabu::Store::Source.create(slug: "comenius", name: "Comenius", adapter_class: "Nabu::Adapters::Comenius",
                                        license_class: "attribution")
    first = Nabu::Store::Loader.new(db: db, source: source).load_from(adapter, workdir: FIXTURES)
    assert_equal 3, first.added
    assert_equal 0, first.errored
    total = db[:passages].count
    assert_equal 27 + parse(LISTOVE).size + parse(BAZUINE).size, total
    second = Nabu::Store::Loader.new(db: db, source: source).load_from(adapter, workdir: FIXTURES)
    assert_equal 3, second.skipped
    assert_equal total, db[:passages].count
  ensure
    db&.disconnect
  end

  def test_fetch_lands_each_item_in_its_handle_directory
    Nabu::Adapters::Comenius::ITEMS.each do |handle, (uuid, filename)|
      fixture = File.join(FIXTURES, handle, filename)
      body = if File.exist?(fixture)
               File.binread(fixture)
             else
               File.binread(Dir.glob(File.join(FIXTURES, "*",
                                               "*.xml")).first)
             end
      stub_request(:get, format(Nabu::Adapters::Comenius::BITSTREAM_URL, uuid))
        .to_return(status: 200, body: body, headers: { "Last-Modified" => "Thu, 22 Oct 2026 09:41:26 GMT" })
    end
    Dir.mktmpdir do |workdir|
      report = adapter.fetch(workdir)
      assert_match(/\A\h{64}\z/, report.sha)
      assert_equal 12, adapter.discover(workdir).count
      assert File.exist?(File.join(workdir, "1-6288", "06_DJAK_03_Pres_Bozi.xml"))
    end
  end

  def test_fetch_wraps_http_failure_in_fetch_error
    stub_request(:get, /lindat\.mff\.cuni\.cz/).to_return(status: 503)
    Dir.mktmpdir { |workdir| assert_raises(Nabu::FetchError) { adapter.fetch(workdir) } }
  end
end

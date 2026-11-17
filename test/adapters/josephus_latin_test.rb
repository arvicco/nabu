# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# The Latin Josephus adapter: the latinjosephus.org v3.0 Zenodo core
# deposit (record 24120761), Latin books only. Fixtures are trimmed real
# deposit files (test/fixtures/josephus-latin/README.md) — eight accepted
# Latin books plus one pinned specimen of every rejected grain, the
# AI-drafted De excidio English among them. Fetch runs against a WebMock
# stub of the Zenodo artifact URL with the sha pin overridden to the stub
# zip's own sha (the ReF drill, zip flavor).
class JosephusLatinTest < Minitest::Test
  include AdapterConformance

  FIXTURES = Nabu::TestSupport.fixtures("josephus-latin")

  ZIP_URL = "https://zenodo.org/api/records/24120761/files/" \
            "Latin_Josephus_v3.0_Corrected_XML_ZENODO_RC.zip/content"

  DOC_URNS = %w[
    urn:nabu:josephus-latin:antiquities.book-01
    urn:nabu:josephus-latin:antiquities.book-03
    urn:nabu:josephus-latin:antiquities.book-09
    urn:nabu:josephus-latin:antiquities.book-11
    urn:nabu:josephus-latin:antiquities.preface
    urn:nabu:josephus-latin:bellum.book-07
    urn:nabu:josephus-latin:contra-apionem.book-02
    urn:nabu:josephus-latin:deh.book-02
  ].freeze

  def conformance_adapter
    Nabu::Adapters::JosephusLatin.new
  end

  def conformance_workdir
    FIXTURES
  end

  def conformance_expected_source_id
    "josephus-latin"
  end

  # --- manifest ---------------------------------------------------------------

  def test_manifest_identifies_the_source_and_its_mixed_terms
    manifest = Nabu::Adapters::JosephusLatin.manifest
    assert_equal "josephus-latin", manifest.id
    assert_equal "attribution", manifest.license_class
    assert_match(/CC BY-NC-SA 3\.0 Italy/, manifest.license)
    assert_match(%r{10\.5281/zenodo\.24120761}, manifest.license)
    assert_equal "https://zenodo.org/records/24120761", manifest.upstream_url
    assert_equal "josephus-latin-tei", manifest.parser_family
  end

  # --- discover: grains -------------------------------------------------------

  def test_discover_mints_one_ref_per_latin_book_file
    refs = Nabu::Adapters::JosephusLatin.new.discover(FIXTURES).to_a
    assert_equal DOC_URNS, refs.map(&:id)
    assert_equal "Antiquitates Judaicae (Latin), Proem",
                 refs.find { |r| r.id.end_with?("preface") }.metadata["title"]
  end

  def test_every_rejected_grain_is_counted_by_rule_never_dropped_silently
    skips = Nabu::Adapters::JosephusLatin.new.discovery_skips(FIXTURES)
    assert skips.clean?, skips.notes.inspect
    assert_equal 8, skips.skipped_by_rule,
                 "Greek, Whiston, Lodge, AI English, paratext, registry + the two registers"
    assert_includes skips.notes, "1 De excidio English (AI-drafted translation per upstream) file(s) skipped by rule"
    assert_includes skips.notes, "1 Niese Greek (Perseus, held by perseus-greek) file(s) skipped by rule"
    assert_includes skips.notes, "1 Whiston English (Perseus, held by perseus-greek) file(s) skipped by rule"
    assert_includes skips.notes, "1 Lodge 1602 English (EEBO-TCP A04680, held by eebo-tcp) file(s) skipped by rule"
    assert_includes skips.notes, "1 capitula paratext file(s) skipped by rule"
    assert_includes skips.notes, "1 Niese citation registry file(s) skipped by rule"
    assert_includes skips.notes, "2 structural register file(s) skipped by rule"
  end

  def test_the_ai_drafted_english_never_becomes_a_document
    english = File.join(FIXTURES, "assets/xml/deh/English/book-02.xml")
    assert File.exist?(english), "the specimen stays pinned in the fixture tree"
    refs = Nabu::Adapters::JosephusLatin.new.discover(FIXTURES).to_a
    refute(refs.any? { |r| r.path.include?("/English/") || r.path.include?("/Greek/") })
  end

  def test_an_unexpected_file_is_unrecognized_not_skipped
    Dir.mktmpdir do |dir|
      FileUtils.cp_r(File.join(FIXTURES, "."), dir)
      FileUtils.mkdir_p(File.join(dir, "assets/xml/vita/Latin/x"))
      File.write(File.join(dir, "assets/xml/vita/Latin/x/book-01.xml"), "")
      skips = Nabu::Adapters::JosephusLatin.new.discovery_skips(dir)
      assert_equal 1, skips.unrecognized
      assert_includes skips.notes, "unrecognized file under assets/xml: vita/Latin/x/book-01.xml"
    end
  end

  def test_discover_of_an_unfetched_workdir_yields_nothing
    Dir.mktmpdir { |dir| assert_empty Nabu::Adapters::JosephusLatin.new.discover(dir).to_a }
  end

  # --- parse ------------------------------------------------------------------

  def test_parse_reads_the_antiquities_book_with_its_annotation_layers
    doc = parse("urn:nabu:josephus-latin:antiquities.book-01")
    assert_equal "Antiquitates Judaicae (Latin), Book 1", doc.title
    assert_equal "lat", doc.language
    refs = doc.passages.map { |p| p.urn.split(":").last }
    assert_equal %w[p1 num27 num34 trailer1], refs
    num27 = doc.passages[1]
    assert_equal "urn:nabu:josephus-latin:antiquities.book-01:num27", num27.urn
    assert num27.text.start_with?("In principio creauit deus caelum et terram."), num27.text
    assert_equal "I.i.27", num27.annotations["citation"]
    assert_equal %w[28 29 30 31 32 33], num27.annotations["niese"]
    assert_equal 4, num27.annotations["ms_annotations"].size
    assert_equal "p", num27.annotations["unit"]
  end

  def test_document_metadata_carries_work_witness_rights_and_both_datings
    meta = parse("urn:nabu:josephus-latin:antiquities.book-01").metadata
    assert_equal "Antiquitates Judaicae", meta["work"]
    assert_equal "1", meta["book"]
    assert_equal "Flavius Josephus", meta["author"]
    assert_equal "Bamberg Msc. Class. 78", meta["witness"]
    assert_equal({ "not_before" => 530, "not_after" => 570, "class" => "composition",
                   "raw" => "mid-6th century: the Latin translation made under Cassiodorus" }, meta["date"])
    assert_equal "Greek, published 93–94 CE", meta["original"], "the Greek original rides apart, undated"
    assert_equal ["https://creativecommons.org/publicdomain/mark/1.0/",
                  "https://creativecommons.org/licenses/by/4.0/"], meta["licence_uris"]
    assert_equal({ "genre" => { "value" => "Antiquitates Judaicae" } }, meta["facets"])
    assert_equal "AJ Latin", meta["edition"]
  end

  def test_de_excidio_carries_the_noncommercial_override_and_its_own_author
    doc = parse("urn:nabu:josephus-latin:deh.book-02")
    assert_equal "nc", doc.license_override, "the digilibLT layer is CC BY-NC-SA 3.0 Italy"
    assert_equal "Pseudo-Hegesippus", doc.metadata["author"]
    assert_equal 360, doc.metadata["date"]["not_before"]
    assert_equal "II.1.1", doc.passages[1].annotations["citation"]
    assert_nil parse("urn:nabu:josephus-latin:bellum.book-07").license_override
    assert_nil parse("urn:nabu:josephus-latin:contra-apionem.book-02").license_override,
               "CC BY-SA 4.0 is the attribution class"
  end

  def test_contra_apionem_and_bellum_read_their_own_shapes
    apion = parse("urn:nabu:josephus-latin:contra-apionem.book-02")
    assert_equal "Boysen, CSEL 37 (1898), Contra Apionem Book 2.", apion.metadata["witness"]
    assert apion.passages.first.text.start_with?("Priori quidem uolumine, karissime mihi Epaphrodite")
    bellum = parse("urn:nabu:josephus-latin:bellum.book-07")
    assert bellum.passages.first.text.start_with?("[1] CAP. I. POSTQUAM vero quos occideret"),
           "Cardwell's inline section labels are the edition's own text"
  end

  def test_a_file_without_a_licence_row_quarantines
    Dir.mktmpdir do |dir|
      FileUtils.cp_r(File.join(FIXTURES, "."), dir)
      rows = File.readlines(File.join(dir, "FILE_LICENCE_MANIFEST.csv"))
      File.write(File.join(dir, "FILE_LICENCE_MANIFEST.csv"),
                 rows.reject { |l| l.start_with?("assets/xml/bellum/Latin/book-07.xml") }.join)
      adapter = Nabu::Adapters::JosephusLatin.new
      ref = adapter.discover(dir).find { |r| r.id.end_with?("bellum.book-07") }
      error = assert_raises(Nabu::ParseError) { adapter.parse(ref) }
      assert_match(/never guessed/, error.message)
    end
  end

  def test_an_unknown_licence_uri_quarantines
    Dir.mktmpdir do |dir|
      FileUtils.cp_r(File.join(FIXTURES, "."), dir)
      path = File.join(dir, "FILE_LICENCE_MANIFEST.csv")
      lines = File.readlines(path).map do |line|
        next line unless line.start_with?("assets/xml/bellum/Latin/book-07.xml")

        line.sub(",https://creativecommons.org/licenses/by/4.0/,", ",https://example.org/terms/,")
      end
      File.write(path, lines.join)
      adapter = Nabu::Adapters::JosephusLatin.new
      ref = adapter.discover(dir).find { |r| r.id.end_with?("bellum.book-07") }
      assert_raises(Nabu::ParseError) { adapter.parse(ref) }
    end
  end

  # --- fetch (the ReF drill, zip flavor) -----------------------------------------

  def test_fetch_downloads_verifies_the_pin_and_unpacks_at_the_root
    body = zip_body
    stub_request(:get, ZIP_URL).to_return(status: 200, body: body,
                                          headers: { "Content-Type" => "application/zip" })
    Dir.mktmpdir do |dir|
      adapter = Nabu::Adapters::JosephusLatin.new(pin: Digest::SHA256.hexdigest(body))
      report = adapter.fetch(dir)
      assert_equal Digest::SHA256.hexdigest(body), report.sha
      assert File.exist?(File.join(dir, "assets/xml/deh/Latin/book-02.xml"))
      assert_equal ["urn:nabu:josephus-latin:deh.book-02"], adapter.discover(dir).map(&:id)
    end
  end

  def test_fetch_rejects_a_sha_drift_loudly
    stub_request(:get, ZIP_URL).to_return(status: 200, body: zip_body,
                                          headers: { "Content-Type" => "application/zip" })
    Dir.mktmpdir do |dir|
      error = assert_raises(Nabu::FetchError) { Nabu::Adapters::JosephusLatin.new.fetch(dir) }
      assert_match(/pin/, error.message)
      assert_empty Dir.children(dir), "a failed pin never touches the tree"
    end
  end

  def test_the_pin_is_the_records_own_sha256
    assert_equal "cfaf269a6fcbd7eb61754573449304dc1ed9d59bd5c6c0a7f5e9c8ec44d67106",
                 Nabu::Adapters::JosephusLatin::RELEASE_SHA256
    assert_equal ZIP_URL, Nabu::Adapters::JosephusLatin::ZIP_URL
  end

  private

  def parse(urn)
    adapter = Nabu::Adapters::JosephusLatin.new
    adapter.parse(adapter.discover(FIXTURES).find { |r| r.id == urn })
  end

  # A real-fixture zip shaped like the deposit (no top dir): the manifest
  # + one Latin book.
  def zip_body
    Dir.mktmpdir do |staging|
      FileUtils.mkdir_p(File.join(staging, "assets/xml/deh/Latin"))
      FileUtils.cp(File.join(FIXTURES, "assets/xml/deh/Latin/book-02.xml"),
                   File.join(staging, "assets/xml/deh/Latin"))
      FileUtils.cp(File.join(FIXTURES, "FILE_LICENCE_MANIFEST.csv"), staging)
      zip = File.join(staging, "core.zip")
      Nabu::Shell.run("zip", "-q", "-r", zip, "assets", "FILE_LICENCE_MANIFEST.csv", chdir: staging)
      File.binread(zip)
    end
  end
end

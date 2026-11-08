# frozen_string_literal: true

require "test_helper"
require "support/adapter_conformance"
require "digest"
require "fileutils"
require "tmpdir"
require "zlib"

# Blbooks adapter tests: the British Library's Digitised Books c.1510–
# c.1900 (BL Labs JSONL release), pre-1800 cone. Fixtures (retrieved
# 2026-11-08 from the BL repository bitstreams; README in the fixture dir)
# are real per-book files trimmed to their leading page rows, upstream's
# bytes per line verbatim: three cone books, the cone's one all-empty book,
# and one book each from an 1800s decade and the undated unk tarball (the
# rejected grains). No network: fetch runs against WebMock stubs of the
# real bitstream URLs with the sha pins swapped for the stub tarballs'.
class BlbooksTest < Minitest::Test
  include AdapterConformance

  FIXTURES = Nabu::TestSupport.fixtures("blbooks")
  ADAPTER = Nabu::Adapters::Blbooks
  PLUTARCH = "urn:nabu:blbooks:002938347"
  HORACE = "urn:nabu:blbooks:001734097"
  SONGS = "urn:nabu:blbooks:000744225"

  def conformance_adapter = ADAPTER.new
  def conformance_workdir = FIXTURES
  def conformance_expected_source_id = "blbooks"

  def documents
    @documents ||= ADAPTER.new.then { |adapter| adapter.discover(FIXTURES).to_h { |ref| [ref.id, adapter.parse(ref)] } }
  end

  # --- manifest -----------------------------------------------------------------

  def test_manifest_is_open_with_both_upstream_license_statements
    manifest = ADAPTER.manifest
    assert_equal "blbooks", manifest.id
    assert_equal "open", manifest.license_class
    assert_match(/CC0 1\.0/, manifest.license)
    assert_match(/Public Domain Mark 1\.0/, manifest.license)
    assert_equal "blbooks-jsonl", manifest.parser_family
    assert_match(%r{10\.23636/r7w6-zy15}, manifest.credit)
  end

  def test_the_cone_is_the_two_pre_1800_tarballs_declared_as_materialized
    assert_equal %w[1510_1699 1700_1799], ADAPTER::CONE.keys
    assert_equal ADAPTER::CONE.keys, ADAPTER.materialized_paths
    assert_equal 137_458_060, ADAPTER::CONE.values.sum(&:bytes), "the cone's declared fetch size"
  end

  # --- discovery ----------------------------------------------------------------

  def test_discovers_the_cone_books_in_period_then_file_order
    assert_equal [PLUTARCH, HORACE, SONGS], documents.keys
  end

  def test_rejected_grains_skip_by_rule_and_are_counted
    skips = ADAPTER.new.discovery_skips(FIXTURES)
    assert_equal 3, skips.skipped_by_rule
    assert_equal 0, skips.unrecognized
    assert_includes skips.notes, "1700_1799: 1 book(s) with no OCR on any page"
    assert_includes skips.notes, "1800_1809: 1 book(s) outside the pre-1800 cone"
    assert_includes skips.notes, "unk: 1 book(s) outside the pre-1800 cone"
  end

  def test_a_stray_file_in_a_cone_period_is_unrecognized
    Dir.mktmpdir do |dir|
      FileUtils.cp_r(File.join(FIXTURES, "1510_1699"), dir)
      File.write(File.join(dir, "1510_1699", "notes.txt"), "stray")
      skips = ADAPTER.new.discovery_skips(dir)
      assert_equal 1, skips.unrecognized
      assert_includes skips.notes, "1510_1699/notes.txt: not a book file"
    end
  end

  def test_an_unfetched_workdir_yields_nothing
    Dir.mktmpdir { |dir| assert_empty ADAPTER.new.discover(dir).to_a }
  end

  # --- passages -----------------------------------------------------------------

  def test_one_passage_per_page_with_text_cited_by_page_number
    plutarch = documents.fetch(PLUTARCH)
    assert_equal(%w[5 6 7 8], plutarch.map { |p| p.urn.delete_prefix("#{PLUTARCH}:") })
    assert_equal 8, plutarch.metadata["page_count"]
    assert_equal 4, plutarch.metadata["empty_pages"]
    assert plutarch.to_a[1].text.start_with?("Plutarchi Cheronei . RaphaelRegiusIoanniLubrancio"),
           plutarch.to_a[1].text[0, 40]
    assert_equal(%w[3 5 8 9], documents.fetch(HORACE).map { |p| p.urn.delete_prefix("#{HORACE}:") })
  end

  def test_each_page_carries_its_ocr_word_confidence
    page = documents.fetch(PLUTARCH).first
    assert_equal({ "page" => 5, "ocr_mean_wc" => 0.211, "ocr_std_wc" => 0.057 }, page.annotations)
  end

  # --- axes ---------------------------------------------------------------------

  def test_the_catalogue_record_mines_the_axes
    meta = documents.fetch(HORACE).metadata
    assert_equal "machine-ocr", meta["text_nature"]
    assert_equal "001734097", meta["bl_record_id"]
    assert_equal "1700_1799", meta["bl_period"]
    assert_equal({ "not_before" => 1753, "not_after" => 1753, "raw" => "1753", "class" => "edition" }, meta["date"])
    assert_equal "London", meta["place"]
    assert_equal "England", meta["country"]
    assert_equal "Horace", meta["author"]
    assert_equal [{ "name" => "Popple, William, the Younger", "kind" => "person" },
                  { "name" => "Horace", "kind" => "person" }], meta["names"]
    assert_equal({ "values" => ["Popple, William, the Younger", "Horace"] }, meta.dig("facets", "author"))
    assert_equal "Horace's Art of Poetry. Translated by W. Popple [With the original text.]",
                 documents.fetch(HORACE).title
  end

  def test_a_raw_date_range_widens_the_envelope
    meta = documents.fetch(SONGS).metadata
    assert_equal({ "not_before" => 1780, "not_after" => 1790, "raw" => "1780-1790", "class" => "edition" },
                 meta["date"])
    assert_equal "Salisbury", meta["place"]
    assert_equal "Fowler", meta["publisher"]
    assert_equal "1 volume (8°)", meta["extent"]
    assert_nil meta["names"], "no names on the record — none invented"
  end

  def test_the_title_form_noun_rides_the_genre_facet
    assert_equal "Song", documents.fetch(SONGS).metadata.dig("facets", "genre", "value")
    assert_equal "Poem", documents.fetch(HORACE).metadata.dig("facets", "genre", "value"),
                 "\"Art of Poetry\" — the title's own form word"
    assert_nil documents.fetch(PLUTARCH).metadata.dig("facets", "genre"), "no form word, no claim"
  end

  # --- language -----------------------------------------------------------------

  def test_language_1_maps_onto_registry_codes_with_every_slot_kept
    horace = documents.fetch(HORACE)
    assert_equal "en", horace.language
    assert_equal %w[en lat], horace.metadata["languages"]
    assert horace.metadata["multi_language"]
    assert(horace.all? { |p| p.language == "en" })
  end

  def test_the_errata_table_corrects_a_continental_imprint_catalogued_english
    plutarch = documents.fetch(PLUTARCH)
    assert_equal "lat", plutarch.language
    assert_equal "English", plutarch.metadata["bl_language"]
    assert_match(/Paris 1510: Latin/, plutarch.metadata["language_erratum"])
    assert_equal "Paris", plutarch.metadata["place"]
    assert_nil plutarch.metadata["country"], "the record carries no country"
  end

  # --- the rejected grains, parsed directly ---------------------------------------

  def test_the_all_empty_book_would_quarantine_and_its_nan_place_reads_as_absent
    error = assert_raises(Nabu::ParseError) { parse_file("1700_1799", "1778_001370315.jsonl.gz", "001370315") }
    assert_match(/no page carries OCR text/, error.message)
  end

  def test_an_undated_unk_book_carries_no_date_and_no_place
    document = parse_file("unk", "UNKOWN_000188981.jsonl.gz", "000188981")
    assert_nil document.metadata["date"]
    assert_nil document.metadata["place"], "upstream's NaN place is no place"
    assert_equal(%w[7 9], document.map { |p| p.urn.split(":").last })
  end

  # --- fetch ----------------------------------------------------------------------

  def test_fetch_downloads_every_cone_tarball_verifies_pins_and_unpacks
    cone, bodies = stub_cone
    Dir.mktmpdir do |dir|
      report = ADAPTER.new(cone: cone).fetch(dir)
      assert_equal Digest::SHA256.hexdigest(bodies.values.map { |b| Digest::SHA256.hexdigest(b) }.join("\n")),
                   report.sha
      assert File.file?(File.join(dir, "1510_1699", "1510_002938347.jsonl.gz")), "the top period dir strips"
      assert File.file?(File.join(dir, "1700_1799", "1753_001734097.jsonl.gz"))
      assert_equal [PLUTARCH, HORACE, SONGS], ADAPTER.new(cone: cone).discover(dir).map(&:id)
      assert_match(/1510_1699: sha pin verified/, report.notes)
    end
  end

  def test_fetch_rejects_a_pin_drift_before_touching_the_tree
    cone, = stub_cone
    drifted = cone.merge("1700_1799" => cone["1700_1799"].with(sha256: "0" * 64))
    Dir.mktmpdir do |dir|
      error = assert_raises(Nabu::FetchError) { ADAPTER.new(cone: drifted).fetch(dir) }
      assert_match(/1700_1799\.tar\.gz misses its sha256 pin/, error.message)
      assert_empty Dir.children(dir), "a failed pin never touches the tree — not even the good period"
    end
  end

  # --- helpers ----------------------------------------------------------------------

  def parse_file(period, name, record_id)
    ref = Nabu::DocumentRef.new(source_id: "blbooks", id: "#{ADAPTER::URN_PREFIX}#{record_id}",
                                path: File.join(FIXTURES, period, name),
                                metadata: { "period" => period, "record_id" => record_id })
    ADAPTER.new.parse(ref)
  end

  # Stub each cone bitstream with a tarball of the fixture period, shaped
  # like the deposit (<period>/<year>_<record>.jsonl.gz); the cone's pins
  # become the stub bodies' own.
  def stub_cone
    bodies = ADAPTER::CONE.keys.to_h { |period| [period, period_tarball(period)] }
    cone = ADAPTER::CONE.to_h do |period, entry|
      stub_request(:get, format(ADAPTER::BITSTREAM_URL, entry.bitstream))
        .to_return(status: 200, body: bodies[period],
                   headers: { "Content-Type" => "application/octet-stream",
                              "Last-Modified" => "Tue, 14 Jul 2026 17:27:18 GMT" })
      [period, entry.with(sha256: Digest::SHA256.hexdigest(bodies[period]))]
    end
    [cone, bodies]
  end

  def period_tarball(period)
    Dir.mktmpdir do |staging|
      FileUtils.cp_r(File.join(FIXTURES, period), staging)
      tarball = File.join(staging, "#{period}.tar.gz")
      Nabu::Shell.run("tar", "-czf", tarball, period, chdir: staging)
      File.binread(tarball)
    end
  end
end

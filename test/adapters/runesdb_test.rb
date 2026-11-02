# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

# Nabu::Adapters::Runesdb: the RuneS-DB TEI deposit (Zenodo 21788307,
# CC BY-SA 4.0) — one TEI file per runic find, passage = sequence, text =
# the glyphs' main transliterations verbatim. Fixtures: four real finds
# (one trimmed) + the rejected-grain specimen (an untransliterated find).
# No network: fetch runs against a WebMock stub of the record's zip URL.
class RunesdbTest < Minitest::Test
  include AdapterConformance
  include StoreTestDB

  FIXTURES = Nabu::TestSupport.fixtures("runesdb")
  ZIP_URL = "https://zenodo.org/records/21788307/files/runes_tei.zip"

  MANUSCRIPT = "urn:nabu:runesdb:200143" # AM 623 4to, 12r — one manuscript rune
  HACKNESS = "urn:nabu:runesdb:629"      # OE-GB-30, two sequences
  HOGEBEINTUM = "urn:nabu:runesdb:720"   # bind-rune read through its components
  RUNE_ROW = "urn:nabu:runesdb:9982"     # AM 748 I b 4to — repeated sequence ids
  DOC_URNS = [MANUSCRIPT, HACKNESS, HOGEBEINTUM, RUNE_ROW].sort.freeze

  def conformance_adapter = Nabu::Adapters::Runesdb.new

  def conformance_workdir = FIXTURES

  def conformance_expected_source_id = "runesdb"

  def adapter = conformance_adapter

  def parse(urn) = adapter.parse(adapter.discover(FIXTURES).find { |ref| ref.id == urn })

  # -- manifest -----------------------------------------------------------------

  def test_manifest_records_the_by_sa_deposit
    manifest = Nabu::Adapters::Runesdb.manifest
    assert_equal "runesdb", manifest.id
    assert_equal "attribution", manifest.license_class
    assert_match(/CC BY-SA 4\.0/, manifest.license)
    assert_match(/zenodo\.21788307/, manifest.license, "the citation names the DOI")
    assert_equal "runesdb-tei", manifest.parser_family
  end

  # -- discover + the rejected grain ---------------------------------------------

  def test_discover_yields_the_transliterated_finds_sorted_by_urn
    refs = adapter.discover(FIXTURES).to_a
    assert_equal DOC_URNS, refs.map(&:id)
    assert(refs.all? { |ref| ref.source_id == "runesdb" })
  end

  def test_an_untransliterated_find_is_skipped_by_rule_and_counted
    skips = adapter.discovery_skips(FIXTURES)
    assert_equal 1, skips.skipped_by_rule
    assert_equal 0, skips.unrecognized
    assert_equal ["runes_find-166.tei.xml: untransliterated find (signs recorded geometrically only, " \
                  "no glyph transliteration)"], skips.notes
    refute_includes adapter.discover(FIXTURES).map(&:id), "urn:nabu:runesdb:166"
  end

  def test_an_unfetched_workdir_yields_nothing
    Dir.mktmpdir { |dir| assert_empty adapter.discover(dir).to_a }
  end

  # -- text + identity ---------------------------------------------------------------

  def test_passage_text_is_the_transliteration_verbatim_with_runological_sigla
    document = parse(HACKNESS)
    assert_equal "gem", document.language
    assert_equal "Stein von Hackness (OE-GB-30)", document.title, "the constant Inschrift: label dropped"
    assert_equal([["#{HACKNESS}:A-1", "?rmcd"], ["#{HACKNESS}:A-2", "[...]œn[...]g"]],
                 document.map { |passage| [passage.urn, passage.text] })
  end

  def test_glyph_records_ride_the_annotations
    passage = parse(HACKNESS).first
    first, second = passage.annotations["glyphs"]
    assert_equal({ "id" => "g-3773", "translit" => "?", "separator" => true }, first)
    assert_equal "r", second["translit"]
    assert_equal "raidō, rād, rāt, ræið/ reið", second["rune_name"]
    assert second["uncertain"], "upstream's graphTypeUncertain flag"
    assert_equal "A", passage.annotations["side"]
    assert_equal "cut", passage.annotations["technique"]
    assert_match %r{\Ahttps://www\.runesdb\.de/image-service/}, passage.annotations["facs"]
  end

  def test_a_bind_rune_without_its_own_transliteration_reads_through_its_components
    passage = parse(HOGEBEINTUM).first
    assert_equal "d^*^d", passage.text, "upstream's own bind-rune notation (a^r)"
    glyph = passage.annotations["glyphs"].first
    assert_equal %w[d * d], glyph["ligature"]
    assert glyph["composed"]
    assert_equal 1, passage.annotations["glyphs"].size, "ligature components never become reading glyphs"
  end

  def test_repeated_upstream_sequence_ids_take_the_positional_disambiguator
    document = parse(RUNE_ROW)
    assert_equal ["#{RUNE_ROW}:recto-1", "#{RUNE_ROW}:verso-1", "#{RUNE_ROW}:recto-1:b2"],
                 document.map(&:urn)
    assert_equal %w[u f o], document.map(&:text), "the rune row in document order"
  end

  # -- metadata + facets ---------------------------------------------------------------

  def test_find_metadata_carries_the_siglum_family_facet_and_the_lido_pointer
    metadata = parse(HACKNESS).metadata
    assert_equal "629", metadata["find_id"]
    assert_equal "OE-GB-30", metadata["siglum"]
    assert_equal "OE-GB", metadata["siglum_family"]
    assert_equal({ "siglum_family" => { "value" => "OE-GB" } }, metadata["facets"])
    assert_equal "https://www.runesdb.de/lido/629", metadata["lido_url"]
    assert_equal "https://creativecommons.org/licenses/by-sa/4.0/", metadata["license_url"]
    assert_equal "AM", parse(MANUSCRIPT).metadata["siglum_family"]
  end

  def test_the_siglum_family_strips_the_running_number
    family = ->(siglum) { Nabu::Adapters::Runesdb.siglum_family(siglum) }
    assert_equal "OE-GB", family.call("OE-GB-30")
    assert_equal "N KJ", family.call("N KJ38")
    assert_equal "MJy", family.call("MJy 74")
    assert_equal "Holm B", family.call("Holm B 59 4to, 25v")
    assert_equal "PreOFris/EROFris-NL", family.call("PreOFris/EROFris-NL-19")
    assert_nil family.call("123")
    assert_nil family.call(nil)
  end

  def test_the_per_file_licence_gate
    assert_nil Nabu::Adapters::Runesdb.license_override_for("CC BY-SA 4.0 - Attribution-ShareAlike 4.0 International")
    assert_equal "restricted", Nabu::Adapters::Runesdb.license_override_for("All rights reserved")
    assert_equal "restricted", Nabu::Adapters::Runesdb.license_override_for(nil)
    assert(adapter.discover(FIXTURES).all? { |ref| adapter.parse(ref).license_override.nil? })
  end

  def test_a_find_without_any_transliteration_quarantines_if_reached
    ref = Nabu::DocumentRef.new(source_id: "runesdb", id: "urn:nabu:runesdb:166",
                                path: File.join(FIXTURES, "runes_find-166.tei.xml"), metadata: {})
    assert_raises(Nabu::ParseError) { adapter.parse(ref) }
  end

  # -- store ---------------------------------------------------------------------------

  def test_loads_idempotently_into_the_store
    db = store_test_db
    source = create_source(db)
    first = Nabu::Store::Loader.new(db: db, source: source).load_from(adapter, workdir: FIXTURES)
    assert_equal 4, first.added
    assert_equal 0, first.errored
    assert_equal 7, db[:passages].count, "1 + 2 + 1 + 3"
    second = Nabu::Store::Loader.new(db: db, source: source).load_from(adapter, workdir: FIXTURES)
    assert_equal 4, second.skipped
    assert_equal 7, db[:passages].count
    assert_equal [1], db[:passages].distinct.select_map(:revision)
  ensure
    db&.disconnect
  end

  # -- fetch ---------------------------------------------------------------------------

  def test_fetch_downloads_and_unpacks_the_flat_zip
    stub_zip
    Dir.mktmpdir do |workdir|
      report = adapter.fetch(workdir)
      assert_match(/\A\h{64}\z/, report.sha)
      assert_equal DOC_URNS, adapter.discover(workdir).map(&:id)
    end
  end

  def test_fetch_wraps_http_failure_in_fetch_error
    stub_request(:get, ZIP_URL).to_return(status: 500)
    Dir.mktmpdir do |workdir|
      assert_raises(Nabu::FetchError) { adapter.fetch(workdir) }
    end
  end

  private

  def create_source(_db)
    Nabu::Store::Source.create(slug: "runesdb", name: "RuneS-DB", adapter_class: "Nabu::Adapters::Runesdb",
                               license_class: "attribution")
  end

  def stub_zip
    Dir.mktmpdir do |dir|
      zip_path = File.join(dir, "runes_tei.zip")
      files = Dir.glob(File.join(FIXTURES, "*.xml")).map { |path| File.basename(path) }
      Nabu::Shell.run("zip", "-q", zip_path, *files, chdir: FIXTURES)
      stub_request(:get, ZIP_URL).to_return(
        status: 200, body: File.binread(zip_path),
        headers: { "Content-Type" => "application/octet-stream", "Last-Modified" => "Sat, 01 Aug 2026 00:00:00 GMT" }
      )
    end
  end
end

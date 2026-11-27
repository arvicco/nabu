# frozen_string_literal: true

require "test_helper"
require "digest"
require "fileutils"
require "json"
require "tmpdir"

# Nabu::Adapters::Dbbe — the Database of Byzantine Book Epigrams archive
# (Ghent University; Zenodo concept record 19435533, CC0): the epigram
# OCCURRENCE (the text as one manuscript carries it, verse by verse) and the
# normalized TYPE as documents, the type's translations as -tr<id> siblings.
# Runs against a schema-intact trim of the real dbbe_archive.sqlite (eight
# occurrences, nine types, eleven translations — the README's recipe) plus a
# trimmed recording of the Zenodo latest-version API response. Includes the
# shared AdapterConformance suite.
class DbbeTest < Minitest::Test
  include AdapterConformance

  FIXTURES = Nabu::TestSupport.fixtures("dbbe")
  ARCHIVE = File.join(FIXTURES, "dbbe_archive.sqlite")
  ADAPTER = Nabu::Adapters::Dbbe

  OCCURRENCE_URNS = %w[16897 17332 18852 20028 24315 24466 28432]
                    .map { |id| "urn:nabu:dbbe:occurrence-#{id}" }.freeze
  TYPE_URNS = %w[1865 1931 2095 2175 3753 3993 4494 6043 6372]
              .map { |id| "urn:nabu:dbbe:type-#{id}" }.freeze
  TRANSLATION_URNS = %w[
    1865-tr1866 1865-tr28726 1865-tr28727 1865-tr28728 1931-tr33867 2095-tr2096
    2095-tr28995 2175-tr30910 6043-tr6044 6372-tr31672 6372-tr31673
  ].map { |tail| "urn:nabu:dbbe:type-#{tail}" }.freeze

  def conformance_adapter
    # translations: true — the registry row's posture; the siblings must
    # pass conformance too.
    ADAPTER.new(translations: true)
  end

  def conformance_workdir = FIXTURES

  def conformance_expected_source_id = "dbbe"

  def documents
    @documents ||= conformance_adapter.then do |adapter|
      adapter.discover(FIXTURES).to_h { |ref| [ref.id, adapter.parse(ref)] }
    end
  end

  # --- manifest ---------------------------------------------------------------

  def test_manifest_is_cc0_open_with_the_zenodo_concept_record
    manifest = ADAPTER.manifest
    assert_equal "dbbe", manifest.id
    assert_equal "open", manifest.license_class
    assert_match(/CC0/, manifest.license)
    assert_match(/cc-zero/, manifest.license, "the record's own license id rides verbatim")
    assert_equal "https://zenodo.org/records/19435533", manifest.upstream_url
    assert_equal "dbbe-sqlite", manifest.parser_family
    assert_match(/Database of Byzantine Book Epigrams/, manifest.credit)
    assert_includes manifest.credit, "10.5281/zenodo.19435533"
  end

  def test_remote_probe_heads_the_latest_version_endpoint
    assert_equal :http_zip, ADAPTER.remote_probe_strategy
    target = ADAPTER.http_probe_targets.first
    assert_equal ADAPTER::LATEST_URL, target.zip_url
    assert_equal Nabu::FileFetch::STATE_FILE, target.state_file
  end

  def test_nothing_is_materialized_beside_the_archive
    assert_equal [], ADAPTER.materialized_paths
  end

  # --- discover / grains --------------------------------------------------------

  def test_discover_mints_occurrences_types_and_translation_siblings_sorted
    ids = conformance_adapter.discover(FIXTURES).map(&:id)
    assert_equal (OCCURRENCE_URNS + TYPE_URNS + TRANSLATION_URNS).sort, ids
  end

  def test_discover_without_translations_mints_the_greek_only
    ids = ADAPTER.new.discover(FIXTURES).map(&:id)
    assert_equal (OCCURRENCE_URNS + TYPE_URNS).sort, ids
  end

  def test_discover_yields_nothing_before_the_first_fetch
    Dir.mktmpdir { |dir| assert_empty ADAPTER.new.discover(dir).to_a }
  end

  def test_a_textless_occurrence_is_skipped_by_rule_and_counted
    skips = ADAPTER.new.discovery_skips(FIXTURES)
    assert_equal 1, skips.skipped_by_rule
    assert_equal 0, skips.unrecognized
    assert(skips.notes.any? { |note| note.include?("occurrence 17280") && note.include?("no transcribed text") })
    refute_includes ADAPTER.new.discover(FIXTURES).map(&:id), "urn:nabu:dbbe:occurrence-17280"
  end

  def test_discovery_skips_name_the_record_grains_that_are_not_documents
    notes = ADAPTER.new.discovery_skips(FIXTURES).notes.join("\n")
    assert_match(/8 manuscripts.*metadata/, notes)
    assert_match(/persons.*metadata/, notes)
    assert_match(/bibliograph/, notes)
  end

  def test_a_stray_sqlite_file_is_unrecognized
    Dir.mktmpdir do |dir|
      FileUtils.cp(ARCHIVE, File.join(dir, ADAPTER::FILENAME))
      FileUtils.cp(ARCHIVE, File.join(dir, "old_copy.sqlite"))
      skips = ADAPTER.new.discovery_skips(dir)
      assert_equal 1, skips.unrecognized
      assert(skips.notes.any? { |note| note.start_with?("old_copy.sqlite") })
    end
  end

  # --- the occurrence document -----------------------------------------------

  def test_occurrence_passages_are_the_verses_byte_pinned
    document = documents.fetch("urn:nabu:dbbe:occurrence-24315")
    assert_equal "grc", document.language
    assert_equal 5, document.size
    first = document.passages.first
    assert_equal "urn:nabu:dbbe:occurrence-24315:1", first.urn
    assert_equal "ἄκουε δα(υί)δ τοῦ παρ' ἡμῖν ὀρφέως:", first.text
    assert_equal({ "verse_id" => 30_477, "verse_group" => 15_428 }, first.annotations)
    assert_equal "πρὸς θηρεώδης ἐκτρεπῆ δυσμορφί(ας):", document.passages.last.text
    assert_equal "ἄκουε δα(υί)δ τοῦ παρ' ἡμῖν ὀρφέως (MESSINA - Biblioteca Universitaria - S. Salv. 117, f. 239r)",
                 document.title
  end

  def test_a_blank_verse_is_an_honest_gap_and_numbering_follows_upstream_order
    document = documents.fetch("urn:nabu:dbbe:occurrence-17332")
    assert_equal 16, document.size, "17 verses upstream, verse 7 blank"
    urns = document.passages.map(&:urn)
    refute_includes urns, "urn:nabu:dbbe:occurrence-17332:7"
    assert_includes urns, "urn:nabu:dbbe:occurrence-17332:8"
    assert_equal "τὸν ἰκέτην σου τόνδε  χ(ριστ)ε καὶ λάτριν·", document.passages[1].text,
                 "edge whitespace trimmed; the inner double space is upstream's"
    assert_equal({ "verse_id" => 2196 }, document.passages.first.annotations, "no verse group, no key")
  end

  def test_occurrence_metadata_mines_every_axis_field
    meta = documents.fetch("urn:nabu:dbbe:occurrence-24315").metadata
    assert_equal "occurrence", meta["record"]
    assert_equal 24_315, meta["dbbe_id"]
    assert_equal "https://www.dbbe.ugent.be/occurrences/24315", meta["url"]
    assert_equal({ "not_before" => 1116, "not_after" => 1116, "raw" => "1116-01-01/1116-12-31" }, meta["date"])
    assert_equal "Calabria, Southern Italy, Italy", meta["place"]
    assert_equal "MESSINA - Biblioteca Universitaria - S. Salv. 117", meta["manuscript"]
    assert_equal "https://www.dbbe.ugent.be/manuscripts/14362", meta["manuscript_url"]
    assert_equal "f. 239r", meta["location_in_ms"]
    assert_equal "Biblioteca Universitaria", meta["repository"]
    assert_equal({ "diktyon" => ["40778"], "rahlfs" => ["1100"] }, meta["manuscript_identifiers"])
    assert_equal ["Author-related epigram"], meta["genre"]
    assert_equal ["Dodecasyllable"], meta["metre"]
    assert_equal %w[David Music Orpheus Psalter], meta["keywords"].sort
    assert_equal "Text completely known", meta["text_status"]
    assert_equal({ "Scribe" => ["Leon"] }, meta["persons"])
    assert_equal ["Ignatios Methymnaeos"], meta["authors"], "the type's Poet credits its witnesses"
    assert_equal ["urn:nabu:dbbe:type-1865"], meta["types"]
    assert_equal true, meta["is_dbbe"]
    assert_match(/Fifth of a series of epigrams/, meta["contextual_info"])
    refute meta.key?("private_comment")
  end

  def test_an_undated_occurrence_carries_no_date_and_a_multitype_one_lists_both
    refute documents.fetch("urn:nabu:dbbe:occurrence-20028").metadata.key?("date")
    meta = documents.fetch("urn:nabu:dbbe:occurrence-28432").metadata
    assert_equal %w[urn:nabu:dbbe:type-2175 urn:nabu:dbbe:type-3753], meta["types"]
    assert_equal({ "not_before" => 1001, "not_after" => 1125, "raw" => "1001-01-01/1125-12-31" }, meta["date"])
    assert_equal "Istanbul, Turkey", meta["place"]
    assert_equal %w[Konstantinoupolis Turkey], meta["place_historical"]
  end

  def test_a_month_precise_date_bands_by_its_years
    meta = documents.fetch("urn:nabu:dbbe:occurrence-17332").metadata
    assert_equal({ "not_before" => 1057, "not_after" => 1058, "raw" => "1057-09-01/1058-08-31" }, meta["date"])
  end

  # --- the type document --------------------------------------------------------

  def test_type_passages_are_the_normalized_lines
    document = documents.fetch("urn:nabu:dbbe:type-1865")
    assert_equal "grc", document.language
    assert_equal 5, document.size
    assert_equal "urn:nabu:dbbe:type-1865:1", document.passages.first.urn
    assert_equal "Ἄκουε Δαβὶδ τοῦ παρ' ἡμῖν Ὀρφέως·", document.passages.first.text
    assert_equal "Ἄκουε Δαβὶδ τοῦ παρ' ἡμῖν Ὀρφέως (type 1865)", document.title
  end

  def test_type_metadata_carries_poet_function_and_its_occurrences
    meta = documents.fetch("urn:nabu:dbbe:type-1865").metadata
    assert_equal "type", meta["record"]
    assert_equal "https://www.dbbe.ugent.be/types/1865", meta["url"]
    assert_equal ["Ignatios Methymnaeos"], meta["authors"]
    assert_equal({ "Poet" => ["Ignatios Methymnaeos"] }, meta["persons"])
    assert_equal ["Praise of the author", "Spiritual value of the book"], meta["tags"].sort
    assert_equal ["urn:nabu:dbbe:occurrence-24315"], meta["occurrences"]
    assert_equal({ "vassis_2005" => ["25"], "vassis_2011" => ["200"] }, meta["identifiers"])
    assert_match(/spiritual valour of David/, meta["public_comment"])
    refute meta.key?("date"), "a type carries no date of its own"
  end

  def test_a_type_without_held_occurrences_still_loads
    document = documents.fetch("urn:nabu:dbbe:type-4494")
    assert_equal [], document.metadata["occurrences"]
    assert_equal "Πόνημα Φιλαγάθου τοῦ φιλοσόφου.", document.passages.first.text
  end

  # --- translations -----------------------------------------------------------

  def test_translations_are_language_coded_siblings_line_by_line
    english = documents.fetch("urn:nabu:dbbe:type-1865-tr1866")
    assert_equal "eng", english.language
    assert_equal 5, english.size
    assert_equal "'Listen to David, our own Orpheus.", english.passages.first.text
    assert_equal({ "kind" => "translation", "translation_of" => "urn:nabu:dbbe:type-1865",
                   "dbbe_translation_id" => 1866, "translation_language" => "English" }, english.metadata)
    assert_equal "Ἄκουε Δαβὶδ τοῦ παρ' ἡμῖν Ὀρφέως (type 1865) — English translation", english.title
    assert_equal "lat", documents.fetch("urn:nabu:dbbe:type-1865-tr28727").language
    assert_equal "deu", documents.fetch("urn:nabu:dbbe:type-2095-tr2096").language
  end

  def test_upstreams_greek_translation_label_is_modern_greek
    document = documents.fetch("urn:nabu:dbbe:type-6372-tr31673")
    assert_equal "ell", document.language
    assert_equal "Greek", document.metadata["translation_language"], "upstream's label rides verbatim"
  end

  def test_crlf_translation_lines_split_clean
    document = documents.fetch("urn:nabu:dbbe:type-6043-tr6044")
    assert_equal 3, document.size
    document.each { |passage| refute_includes passage.text, "\r" }
  end

  # --- reader hygiene -----------------------------------------------------------

  def test_reading_never_touches_the_canonical_directory
    Dir.mktmpdir do |dir|
      FileUtils.cp(ARCHIVE, File.join(dir, ADAPTER::FILENAME))
      adapter = ADAPTER.new(translations: true)
      adapter.discover(dir).each { |ref| adapter.parse(ref) }
      assert_equal [ADAPTER::FILENAME], Dir.children(dir),
                   "the WAL-mode archive opens immutable — no -wal/-shm beside it"
    end
  end

  def test_a_non_database_raises_a_parse_error_naming_the_file
    Dir.mktmpdir do |dir|
      path = File.join(dir, ADAPTER::FILENAME)
      File.write(path, "not a database")
      error = assert_raises(Nabu::ParseError) { ADAPTER.new.discover(dir).to_a }
      assert_includes error.message, path
    end
  end

  # --- fetch (WebMock'd Zenodo latest-version resolve + md5 pin) ----------------

  def latest_json(md5:, content_url: CONTENT_URL)
    record = JSON.parse(File.read(File.join(FIXTURES, "zenodo-latest.json")))
    record["files"].first["checksum"] = "md5:#{md5}"
    record["files"].first["links"]["self"] = content_url
    JSON.generate(record)
  end

  CONTENT_URL = "https://zenodo.org/api/records/23008642/files/dbbe_archive.sqlite/content"

  def stub_latest(md5: Digest::MD5.file(ARCHIVE).hexdigest, body: File.binread(ARCHIVE))
    stub_request(:get, ADAPTER::LATEST_URL)
      .to_return(status: 200, body: latest_json(md5: md5), headers: { "Content-Type" => "application/json" })
    stub_request(:get, CONTENT_URL)
      .to_return(status: 200, body: body, headers: { "Last-Modified" => "Mon, 16 Nov 2026 10:42:29 GMT" })
  end

  def test_fetch_resolves_the_latest_version_and_lands_the_md5_verified_archive
    stub_latest
    Dir.mktmpdir do |dir|
      report = ADAPTER.new.fetch(dir)
      target = File.join(dir, ADAPTER::FILENAME)
      assert_equal File.binread(ARCHIVE), File.binread(target)
      assert_equal Digest::SHA256.file(ARCHIVE).hexdigest, report.sha
      assert_match(/record 23008642/, report.notes)
      assert_match(/2026-09-28/, report.notes)
      assert_match(/md5 verified/, report.notes)
      state = JSON.parse(File.read(File.join(dir, Nabu::FileFetch::STATE_FILE)))
      assert_equal CONTENT_URL, state.fetch("url")
    end
  end

  def test_an_unchanged_archive_is_not_downloaded_again
    Dir.mktmpdir do |dir|
      FileUtils.cp(ARCHIVE, File.join(dir, ADAPTER::FILENAME))
      stub_request(:get, ADAPTER::LATEST_URL)
        .to_return(status: 200, body: latest_json(md5: Digest::MD5.file(ARCHIVE).hexdigest))
      report = ADAPTER.new.fetch(dir)
      assert_match(/already current/, report.notes)
      assert_not_requested :get, CONTENT_URL
      assert_equal Digest::SHA256.file(ARCHIVE).hexdigest, report.sha
    end
  end

  def test_an_md5_mismatch_aborts_with_the_tree_untouched
    stub_latest(md5: "0" * 32)
    Dir.mktmpdir do |dir|
      error = assert_raises(Nabu::FetchError) { ADAPTER.new.fetch(dir) }
      assert_match(/md5/, error.message)
      assert_empty Dir.children(dir)
    end
  end

  def test_a_record_without_the_archive_file_fails_loudly
    record = JSON.parse(File.read(File.join(FIXTURES, "zenodo-latest.json")))
    record["files"].first["key"] = "something_else.zip"
    stub_request(:get, ADAPTER::LATEST_URL).to_return(status: 200, body: JSON.generate(record))
    Dir.mktmpdir do |dir|
      error = assert_raises(Nabu::FetchError) { ADAPTER.new.fetch(dir) }
      assert_match(/dbbe_archive\.sqlite/, error.message)
    end
  end
end

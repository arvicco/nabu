# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

# Nabu::Adapters::DharmaMdt (P118-4): the DHARMA text-metadata CSVs
# (github.com/erc-dharma/mdt-texts) as a METADATA-ROW source — one
# zero-passage document per INS<Corpus>NNNNN row (the rsti/ebl
# metadata-only precedent), carrying the dating, typology, physical,
# bibliographic and location fields, keyed for the join onto the DHARMA
# edition sources. Fixtures: trimmed real CSVs with the row-3 header
# intact (test/fixtures/dharma-mdt/README.md).
class DharmaMdtTest < Minitest::Test
  include AdapterConformance

  FIXTURES = Nabu::TestSupport.fixtures("dharma-mdt")

  def conformance_adapter = Nabu::Adapters::DharmaMdt.new

  def conformance_workdir = FIXTURES

  def conformance_expected_source_id = "dharma-mdt"

  # Every document is an honest metadata record — no text in the asset.
  def conformance_metadata_only?(document) = document.metadata["text_layer"] == "none"

  def adapter = conformance_adapter

  def parse(id)
    ref = adapter.discover(FIXTURES).find { |r| r.id == "urn:nabu:dharma-mdt:#{id}" }
    refute_nil ref, "no ref for #{id}"
    adapter.parse(ref)
  end

  # -- manifest ---------------------------------------------------------------

  def test_manifest_records_the_row_cc0_and_the_repo_licence
    manifest = Nabu::Adapters::DharmaMdt.manifest
    assert_equal "dharma-mdt", manifest.id
    assert_equal "attribution", manifest.license_class
    assert_includes manifest.license, "CC0"
    assert_includes manifest.license, "CC BY 4.0"
    assert_equal "dharma-mdt-csv", manifest.parser_family
    assert_match(/DHARMA/, manifest.credit)
  end

  # -- discover ---------------------------------------------------------------

  def test_discover_yields_one_ref_per_substantive_row_sorted
    ids = adapter.discover(FIXTURES).map { |r| r.id.delete_prefix("urn:nabu:dharma-mdt:") }
    assert_equal %w[INSDaksinaKosala00001 INSDaksinaKosala00002 INSPallava00001 INSPallava00002
                    INSPallava00155 INSSomavamsin00001 INSSomavamsin00002 INSTelugu00001
                    INSTelugu00002 INSTelugu00004 INSTelugu00023], ids,
                 "urn:nabu:dharma-mdt:<Identifier of the text> verbatim; placeholder rows excluded"
  end

  def test_placeholder_rows_are_censused_skip_by_rule
    skips = adapter.discovery_skips(FIXTURES)
    assert_equal 2, skips.skipped_by_rule,
                 "INSDaksinaKosala00047 and INSSomavamsin00049 carry ids + rights only"
    assert_equal 0, skips.unrecognized
    assert_match(/INSDaksinaKosala00047/, skips.notes.join(" "))
  end

  def test_the_header_is_row_three_and_the_description_row_never_mints
    refs = adapter.discover(FIXTURES).to_a
    refute(refs.any? { |r| r.id.include?("Digital identifier") || r.id.include?("Identifier") })
  end

  # -- the join key -------------------------------------------------------------

  def test_the_join_key_is_the_dharma_edition_stem
    metadata = parse("INSPallava00155").metadata
    assert_equal "INSPallava00155", metadata["dharma_text_id"]
    assert_equal "DHARMA_INSPallava00155", metadata["dharma_edition_stem"],
                 "the DHARMA edition file stem — DharmaBase mints urn:nabu:<slug>:<stem sans DHARMA_>, " \
                 "so the join walks dharma_text_id == the edition urn's last segment"
    assert_equal metadata["dharma_text_id"],
                 metadata["dharma_edition_stem"].delete_prefix(Nabu::Adapters::DharmaBase::FILE_PREFIX)
  end

  # -- dating -------------------------------------------------------------------

  def test_a_date_ce_point_becomes_a_one_year_envelope
    date = parse("INSTelugu00001").metadata["date"]
    assert_equal({ "not_before" => 849, "not_after" => 849, "raw" => "849", "evidence" => "reign" }, date)
  end

  def test_a_date_range_carries_its_certainty
    date = parse("INSTelugu00002").metadata["date"]
    assert_equal 849, date["not_before"]
    assert_equal 891, date["not_after"]
    assert_equal "849-891", date["raw"]
    assert_equal "low", date["certainty"]
  end

  def test_a_range_written_in_the_date_ce_column_parses_as_a_range
    date = parse("INSTelugu00023").metadata["date"]
    assert_equal [625, 675], [date["not_before"], date["not_after"]]
  end

  def test_an_undated_row_carries_no_date
    assert_nil parse("INSTelugu00004").metadata["date"]
  end

  def test_the_pallava_dated_row
    date = parse("INSPallava00155").metadata["date"]
    assert_equal [850, 900, "internal date"], [date["not_before"], date["not_after"], date["evidence"]]
  end

  # -- the rest of the row --------------------------------------------------------

  def test_document_shape_title_language_and_text_layer
    document = parse("INSTelugu00004")
    assert_equal "Image of Viṣṇu probably donated by Cōḷaṟaviti", document.title
    assert_equal "tel", document.language
    assert document.empty?, "a metadata row mints no passages"
    assert_equal "none", document.metadata["text_layer"]
    assert_equal "Telugu", document.metadata["corpus"]
    assert_equal "CC0", document.metadata["metadata_license"]
    assert_equal "CC-BY-SA", document.metadata["edition_license"]
  end

  def test_comma_tokens_decode_and_dollar_cells_split
    metadata = parse("INSTelugu00001").metadata
    assert_equal "Lakhsmana Rao 1927-1928: 271-275 (EI XIX, 47)", metadata["origin_of_metadata"],
                 "upstream escapes commas as the literal token COMMA"
    primary = metadata.dig("bibliography", "primary")
    assert_kind_of Array, primary
    assert_includes primary, "Lakshmana Rao 1927-1928: 271-275 (EI XIX, 47)"
    assert_match(/Vijayāditya II whose first year was 849 CE/, metadata["remarks"])
    assert_equal "On a stone lying in a field at Addanki", metadata["artefact_location"],
                 "location prose rides verbatim — never minted as a place claim"
    assert_equal ["ARTTelugu000001"], metadata["artefact_ids"]
  end

  def test_languages_scripts_and_text_types
    metadata = parse("INSPallava00155").metadata
    assert_equal %w[Sanskrit Tamil], metadata["languages"]
    assert_equal "san", parse("INSPallava00155").language, "the first listed language governs"
    assert_equal ["donative - religious_land_grant"], metadata["text_types"]
    assert_equal "brahmi_and_derivatives - southern_class_brahmi - grantha", metadata["scripts"].first["classification"]
  end

  def test_a_row_with_no_language_is_und
    assert_equal "und", parse("INSPallava00001").language
  end

  def test_an_unknown_language_name_quarantines
    with_doctored("DHARMA_mdt_Telugu_v01.csv", ",Telugu,brahmi", ",Klingon,brahmi") do |dir|
      ref = adapter.discover(dir).find { |r| r.id.end_with?("INSTelugu00001") }
      error = assert_raises(Nabu::ParseError) { adapter.parse(ref) }
      assert_match(/Klingon/, error.message)
    end
  end

  def test_a_non_cc0_metadata_row_quarantines
    with_doctored("DHARMA_mdt_Telugu_v01.csv", "Telugu,CC0,INSTelugu00001", "Telugu,CC BY-NC,INSTelugu00001") do |dir|
      ref = adapter.discover(dir).find { |r| r.id.end_with?("INSTelugu00001") }
      error = assert_raises(Nabu::ParseError) { adapter.parse(ref) }
      assert_match(/CC BY-NC/, error.message)
    end
  end

  def test_an_unparseable_date_rides_raw_only
    with_doctored("DHARMA_mdt_Telugu_v01.csv", ",849,,,,reign,", ",9th century,,,,reign,") do |dir|
      ref = adapter.discover(dir).find { |r| r.id.end_with?("INSTelugu00001") }
      metadata = adapter.parse(ref).metadata
      assert_nil metadata["date"], "never a guessed bound"
      assert_equal "9th century", metadata["date_raw"]
    end
  end

  # -- fetch (local git only, no network) -----------------------------------------

  def test_fetch_sparse_clones_only_the_csv_cone
    Dir.mktmpdir("nabu-mdt-fetch") do |root|
      upstream = File.join(root, "upstream")
      build_upstream_repo(upstream)
      work = File.join(root, "canonical")
      mdt = adapter
      mdt.define_singleton_method(:repo_url) { upstream }
      report = mdt.fetch(work)
      assert_match(/\A[0-9a-f]{40}\z/, report.sha)
      assert File.file?(File.join(work, "LICENCE.txt"))
      refute File.exist?(File.join(work, "output")), "the per-surrogate XML output is outside the cone"
      assert_equal adapter.discover(FIXTURES).count, mdt.discover(work).count
    end
  end

  private

  def with_doctored(name, from, to)
    Dir.mktmpdir do |dir|
      FileUtils.cp_r(File.join(FIXTURES, "csv"), dir)
      path = File.join(dir, "csv", name)
      text = File.read(path, encoding: "UTF-8")
      assert_includes text, from, "the doctoring pattern must match the fixture"
      File.write(path, text.sub(from, to))
      yield dir
    end
  end

  def build_upstream_repo(upstream)
    FileUtils.mkdir_p(File.join(upstream, "output"))
    FileUtils.cp_r(File.join(FIXTURES, "csv"), upstream)
    File.write(File.join(upstream, "LICENCE.txt"), "Attribution 4.0 International\n")
    File.write(File.join(upstream, "README.md"), "# mdt-texts\nDHARMA textual metadata\n")
    File.write(File.join(upstream, "output", "DHARMA_mdt_INSTelugu00001_d1e1.xml"), "<x/>")
    git = ->(*args) { Nabu::Shell.run("git", "-C", upstream, *args) }
    Nabu::Shell.run("git", "init", "-q", upstream)
    git.call("add", ".")
    git.call("-c", "user.email=test@test", "-c", "user.name=test", "commit", "-q", "-m", "seed")
  end
end

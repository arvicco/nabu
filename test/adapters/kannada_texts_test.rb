# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

# kannada-texts (P118-3): the Kannada Digital Texts Project's TEI tree
# (github.com/aso2101/kannada_texts) composing the `ollett-tei` family.
# Fixtures: four trimmed real files (test/fixtures/kannada-texts/README.md).
class KannadaTextsTest < Minitest::Test
  include AdapterConformance
  include StoreTestDB

  FIXTURES = Nabu::TestSupport.fixtures("kannada-texts")

  HONNAMMA = "urn:nabu:kannada-texts:honnamma-hadibadeyadharma-iso-s1-9"
  JANNA = "urn:nabu:kannada-texts:janna-anantanāthapurāṇaṁ-a1"
  KABHABHU = "urn:nabu:kannada-texts:nāgavarma-karṇāṭakabhāṣābhūṣaṇam-s1-4"
  PAMPA = "urn:nabu:kannada-texts:pampa-ādipurāṇaṁ-a1"

  def conformance_adapter
    Nabu::Adapters::KannadaTexts.new
  end

  def conformance_workdir
    FIXTURES
  end

  def conformance_expected_source_id
    "kannada-texts"
  end

  def test_manifest
    manifest = Nabu::Adapters::KannadaTexts.manifest
    assert_equal "kannada-texts", manifest.id
    assert_equal "attribution", manifest.license_class
    assert_equal "ollett-tei", manifest.parser_family
    assert_equal "https://github.com/aso2101/kannada_texts", manifest.upstream_url
    assert_includes manifest.license, "Distributed under a Creative Commons Attribution-ShareAlike 4.0 license."
    assert_includes manifest.license, "Unless specified otherwise, the data provided in this repository is " \
                                      "made available under a CC-BY 4.0 license."
  end

  def test_discover_mints_nfc_stem_urns_in_order
    refs = conformance_adapter.discover(FIXTURES).to_a
    assert_equal [HONNAMMA, JANNA, KABHABHU, PAMPA], refs.map(&:id)
    refs.each { |ref| assert ref.id.unicode_normalized?(:nfc), ref.id }
    assert_equal "tei/Pampa/pampa-ādipurāṇaṁ-a1.xml", refs.last.metadata["repo_path"]
    assert_predicate conformance_adapter.discovery_skips(FIXTURES), :clean?
    assert_equal 0, conformance_adapter.discovery_skips(FIXTURES).skipped_by_rule
  end

  def test_in_file_grant_recorded_verbatim
    doc = parsed(PAMPA)
    assert_equal "CC BY-SA 4.0", doc.metadata["license"]
    assert_equal "Kannada Digital Texts Project. Distributed under a Creative Commons " \
                 "Attribution-ShareAlike 4.0 license.", doc.metadata["license_statement"]
  end

  def test_readme_dates_ride_as_composition_envelopes_by_siglum
    pampa = parsed(PAMPA).metadata
    assert_equal "Ādi", pampa["siglum"]
    assert_equal({ "not_before" => 941, "not_after" => 941,
                   "raw" => "941 (the repository README's date for the work)" }, pampa["date"])
    assert_equal "ca. 1042 (the repository README's date for the work)", parsed(KABHABHU).metadata.dig("date", "raw")
    assert_nil parsed(JANNA).metadata["date"], "the README dates no Janna — never guessed"
  end

  def test_honnamma_text_tag_is_repaired_and_noted
    doc = parsed(HONNAMMA)
    assert_equal "kan-Latn", doc.language
    assert_match(/reads san-Latn; the work is Kannada/, doc.metadata["language_repair"])
    assert_equal({ "kan-Latn" => 12, "san-Latn" => 1 }, doc.metadata["text_languages"])
    assert_nil doc.metadata["source_edition"], "the commented-out sourceDesc is no claim"
  end

  def test_sanskrit_grammar_keeps_its_declared_language
    doc = parsed(KABHABHU)
    assert_equal "san-Latn", doc.language
    assert_equal "R. Narasimhachar", doc.metadata.dig("source_edition", "editors", 0)
  end

  def test_passage_shape
    doc = parsed(PAMPA)
    first = doc.passages.first
    assert_equal "#{PAMPA}:1.1", first.urn
    assert_equal "kan-Latn", first.language
    assert_equal "śārdūlavikrīḍitaṁ", first.annotations["met"]
    assert_equal "#{PAMPA}:tr1", doc.passages.last.urn
    assert_equal "ādipurāṇaṁ sampūrṇaṁ", doc.passages.last.text
  end

  def test_double_load_is_idempotent
    catalog = store_test_db
    source = Nabu::Store::Source.create(slug: "kannada-texts", name: "Kannada Texts",
                                        adapter_class: "Nabu::Adapters::KannadaTexts", license_class: "attribution")
    first = Nabu::Store::Loader.new(db: catalog, source: source).load_from(conformance_adapter, workdir: FIXTURES,
                                                                                                full: true)
    assert_equal 4, first.added
    assert_equal 0, first.errored
    counts = [catalog[:documents].count, catalog[:passages].count]
    revisions = catalog[:documents].select_hash(:urn, :revision)
    Nabu::Store::Loader.new(db: catalog, source: source).load_from(conformance_adapter, workdir: FIXTURES, full: true)
    assert_equal counts, [catalog[:documents].count, catalog[:passages].count]
    assert_equal revisions, catalog[:documents].select_hash(:urn, :revision)
  end

  def test_fetch_sparse_clones_only_the_tei_cone_and_readme
    Dir.mktmpdir("nabu-kannada-fetch") do |root|
      upstream = File.join(root, "upstream")
      FileUtils.mkdir_p(upstream)
      FileUtils.cp_r(File.join(FIXTURES, "tei"), upstream)
      File.write(File.join(upstream, "README.md"), "# Kannada Texts Project\n")
      FileUtils.mkdir_p(File.join(upstream, "raw", "Pampa"))
      File.write(File.join(upstream, "raw", "Pampa", "ocr.txt"), "outside the cone")
      Nabu::Shell.run("git", "init", "-q", upstream)
      Nabu::Shell.run("git", "-C", upstream, "add", ".")
      Nabu::Shell.run("git", "-C", upstream, "-c", "user.email=t@t", "-c", "user.name=t", "commit", "-q", "-m", "seed")

      adapter = conformance_adapter
      adapter.define_singleton_method(:repo_url) { upstream }
      work = File.join(root, "canonical")
      report = adapter.fetch(work)
      assert_match(/\A[0-9a-f]{40}\z/, report.sha)
      assert File.file?(File.join(work, "README.md"))
      refute File.exist?(File.join(work, "raw")), "raw/ OCR inputs never materialize"
      assert_equal 4, adapter.discover(work).count
    end
  end

  def test_fetch_wraps_shell_failure_in_fetch_error
    Dir.mktmpdir do |root|
      adapter = conformance_adapter
      adapter.define_singleton_method(:repo_url) { File.join(root, "missing") }
      assert_raises(Nabu::FetchError) { adapter.fetch(File.join(root, "work")) }
    end
  end

  def test_registered_unwired
    registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
    entry = registry["kannada-texts"]
    refute_nil entry
    assert_equal Nabu::Adapters::KannadaTexts, entry.adapter_class
    refute entry.wired, "wired: false until the first real sync is verified"
  end

  private

  def parsed(urn)
    adapter = conformance_adapter
    adapter.parse(adapter.discover(FIXTURES).find { |ref| ref.id == urn } || flunk("no ref #{urn}"))
  end
end

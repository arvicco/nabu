# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# Aranese adapter tests (P80-6): the ES-OC (Spanish–Aranese) Parallel
# Corpus — projecte-aina/ES-OC_Parallel_Corpus on Hugging Face (BSC,
# WMT24; 419,908 line-aligned pairs, CC BY-SA 4.0 on the card; MAINLY
# SYNTHETIC per the card's own words — recorded honestly, never hidden).
# The fixtures pin the line-number identity, the two-file line-alignment
# damage contract, the shared non-NFC line (77,909 upstream, both sides),
# the -es Spanish siblings, and the idempotent double-load. No network:
# fetch runs against WebMock stubs of the two real resolve URLs.
class AraneseTest < Minitest::Test
  include AdapterConformance
  include StoreTestDB

  FIXTURES = Nabu::TestSupport.fixtures("aranese")

  ARN_URL = "https://huggingface.co/datasets/projecte-aina/ES-OC_Parallel_Corpus/resolve/main/" \
            "es-arn_corpus.arn"
  ES_URL = "https://huggingface.co/datasets/projecte-aina/ES-OC_Parallel_Corpus/resolve/main/" \
           "es-arn_corpus.es"
  URN = "urn:nabu:aranese:corpus"

  def conformance_adapter
    Nabu::Adapters::Aranese.new(translations: true)
  end

  def conformance_workdir
    FIXTURES
  end

  def conformance_expected_source_id
    "aranese"
  end

  # --- manifest ---------------------------------------------------------------

  def test_manifest_identifies_the_aranese_source
    manifest = Nabu::Adapters::Aranese.manifest
    assert_equal "aranese", manifest.id
    assert_match(/Attribution-Share Alike 4\.0/, manifest.license, "the card's grant, verbatim")
    assert_match(/mainly synthetic/i, manifest.license,
                 "the provenance caveat travels beside the grant — never hidden")
    assert_equal "attribution", manifest.license_class
    assert_equal "https://huggingface.co/datasets/projecte-aina/ES-OC_Parallel_Corpus",
                 manifest.upstream_url
    assert_equal "sentence-lines", manifest.parser_family
  end

  # --- discover ---------------------------------------------------------------

  def test_discover_mints_the_corpus_ref_plus_es_sibling
    refs = Nabu::Adapters::Aranese.new(translations: true).discover(FIXTURES).to_a
    assert_equal [URN, "#{URN}-es"], refs.map(&:id)
    assert(refs.all? { |r| r.source_id == "aranese" })
  end

  def test_discover_without_translations_yields_the_aranese_side_only
    refs = Nabu::Adapters::Aranese.new.discover(FIXTURES).to_a
    assert_equal [URN], refs.map(&:id)
  end

  def test_discover_of_an_unfetched_workdir_yields_nothing
    Dir.mktmpdir do |dir|
      assert_empty Nabu::Adapters::Aranese.new(translations: true).discover(dir).to_a
    end
  end

  # --- parse: the Aranese original --------------------------------------------

  def test_parse_mints_one_occitan_passage_per_line_numbered_from_one
    document = parse_urn(URN)
    assert_equal "oci", document.language
    assert_equal 6, document.size
    assert_equal %w[1 2 3 4 5 6], document.map { |p| p.urn.split(":").last },
                 "identity is the 1-based line number — upstream ships no sentence ids"
  end

  def test_passage_text_is_the_aranese_sentence
    passage = parse_urn(URN).first
    assert_equal "Elègi de l’ensenhament actiu?", passage.text
  end

  def test_the_synthetic_caveat_rides_the_document_metadata
    document = parse_urn(URN)
    assert_match(/mainly synthetic/i, document.metadata["provenance"],
                 "the card's own provenance words ride every parse — the honesty is structural")
  end

  def test_non_nfc_upstream_line_is_normalized_at_the_boundary
    passage = parse_urn(URN).to_a[5]
    assert passage.text.unicode_normalized?(:nfc),
           "upstream line 77,909 carries a decomposed accent on both sides"
  end

  # --- parse: the -es sibling -------------------------------------------------

  def test_es_sibling_mints_one_spanish_passage_per_line
    document = parse_urn("#{URN}-es")
    assert_equal "spa", document.language
    assert_equal "suprime la actividad enzimática?", document.first.text
    assert_equal "#{URN}-es:1", document.first.urn
  end

  def test_es_citations_align_with_the_original_for_parallel
    original = parse_urn(URN)
    translation = parse_urn("#{URN}-es")
    assert_equal original.map { |p| p.urn.split(":").last },
                 translation.map { |p| p.urn.split(":").last },
                 "suffix-for-suffix alignment — the Query::Parallel contract"
  end

  # --- parse: damage is loud --------------------------------------------------

  def test_misaligned_line_counts_raise_parse_error
    Dir.mktmpdir do |dir|
      write_pair(dir, arn: "ua\ndues\n", spanish: "una\n")
      adapter = Nabu::Adapters::Aranese.new
      error = assert_raises(Nabu::ParseError) { adapter.parse(adapter.discover(dir).first) }
      assert_match(/aligned/, error.message,
                   "equal line counts ARE the format (censused 419,908 = 419,908) — a mismatch is damage")
    end
  end

  def test_a_lone_aranese_file_parses_without_the_sibling_check
    Dir.mktmpdir do |dir|
      write_pair(dir, arn: "ua\ndues\n", spanish: nil)
      adapter = Nabu::Adapters::Aranese.new
      document = adapter.parse(adapter.discover(dir).first)
      assert_equal 2, document.size, "the alignment guard needs both files present"
    end
  end

  # --- fetch (WebMock only, no network) ---------------------------------------

  def test_fetch_downloads_both_sides_via_file_fetch
    stub_sides
    Dir.mktmpdir do |workdir|
      adapter = Nabu::Adapters::Aranese.new(translations: true)
      report = adapter.fetch(workdir)
      assert_instance_of Nabu::FetchReport, report
      assert_match(/\A\h{64}\z/, report.sha)
      assert_match(/arn/, report.notes)
      assert_equal [URN, "#{URN}-es"], adapter.discover(workdir).map(&:id),
                   "both files land in place and discover sees the pair"
    end
  end

  def test_fetch_wraps_http_failure_in_fetch_error
    stub_request(:get, ARN_URL).to_return(status: 500)
    stub_request(:get, ES_URL).to_return(status: 500)
    Dir.mktmpdir do |workdir|
      assert_raises(Nabu::FetchError) { Nabu::Adapters::Aranese.new.fetch(workdir) }
    end
  end

  # --- remote-health probe shape ----------------------------------------------

  def test_probe_heads_both_resolve_urls
    assert_equal :http_zip, Nabu::Adapters::Aranese.remote_probe_strategy
    targets = Nabu::Adapters::Aranese.http_probe_targets
    assert_equal [ARN_URL, ES_URL], targets.map(&:zip_url)
    assert_equal %w[arn es], targets.map(&:state_subdir)
    assert_equal [Nabu::FileFetch::STATE_FILE], targets.map(&:state_file).uniq
    assert(targets.all? { |t| t.metadata_url.nil? },
           "the license lives on the dataset card, no probe-shaped endpoint")
  end

  # --- store: idempotent double-load ------------------------------------------

  def test_loads_idempotently_into_the_store
    catalog = store_test_db
    source = create_source
    adapter = Nabu::Adapters::Aranese.new(translations: true)
    first = Nabu::Store::Loader.new(db: catalog, source: source)
                               .load_from(adapter, workdir: FIXTURES, full: true)
    assert_equal 2, first.added
    assert_equal 0, first.errored
    assert_equal 12, catalog[:passages].count, "6 Aranese + 6 Spanish"

    second = Nabu::Store::Loader.new(db: catalog, source: source)
                                .load_from(adapter, workdir: FIXTURES, full: true)
    assert_equal 0, second.errored
    assert_equal 2, second.skipped, "a byte-identical reload skips both documents"
    assert_equal [1], catalog[:passages].distinct.select_map(:revision),
                 "a byte-identical reload bumps no revisions"
  end

  # --- registry round-trip ----------------------------------------------------

  def test_registry_resolves_aranese_and_manifest_agrees
    registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
    entry = registry["aranese"]
    refute_nil entry, "aranese must be registered in config/sources.yml"
    assert_equal Nabu::Adapters::Aranese, entry.adapter_class
    refute entry.wired, "wired flips only after the owner-verified first real sync"
    assert entry.translations, "the Spanish side is the point of a parallel corpus — -es rides"
    assert_equal Nabu::Adapters::Aranese.manifest, entry.manifest
  end

  private

  def parse_urn(urn)
    adapter = Nabu::Adapters::Aranese.new(translations: true)
    ref = adapter.discover(FIXTURES).find { |r| r.id == urn }
    refute_nil ref, "expected discover to yield #{urn}"
    adapter.parse(ref)
  end

  def create_source
    Nabu::Store::Source.create(slug: "aranese", name: "ES-OC Parallel Corpus (Aranese)",
                               adapter_class: "Nabu::Adapters::Aranese",
                               license_class: "attribution")
  end

  def write_pair(dir, arn:, spanish:)
    FileUtils.mkdir_p(File.join(dir, "arn"))
    File.write(File.join(dir, "arn", "es-arn_corpus.arn"), arn)
    return if spanish.nil?

    FileUtils.mkdir_p(File.join(dir, "es"))
    File.write(File.join(dir, "es", "es-arn_corpus.es"), spanish)
  end

  def stub_sides
    { ARN_URL => %w[arn es-arn_corpus.arn], ES_URL => %w[es es-arn_corpus.es] }.each do |url, (subdir, name)|
      stub_request(:get, url).to_return(
        status: 200, body: File.binread(File.join(FIXTURES, subdir, name)),
        headers: { "Content-Type" => "text/plain" }
      )
    end
  end
end

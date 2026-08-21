# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# Salom adapter tests (P80-6): the Şalom Ladino articles text corpus —
# collectivat/salom-ladino-articles on Hugging Face (10,685 sentences from
# 397 Judeo-Espanyol press articles, segmented and shuffled; CC BY 4.0 on
# the card). The fixtures pin the line-number identity, the upstream
# `\n\n` tail (the one blank line mints NO passage while numbering stays
# physical), and the idempotent double-load. No network: fetch runs
# against a WebMock stub of the real resolve URL.
class SalomTest < Minitest::Test
  include AdapterConformance
  include StoreTestDB

  FIXTURES = Nabu::TestSupport.fixtures("salom")

  URL = "https://huggingface.co/datasets/collectivat/salom-ladino-articles/resolve/main/" \
        "Salom-ladino-2022-01-ext-04_segmented_shuffled.txt"
  URN = "urn:nabu:salom:articles-2022"

  def conformance_adapter
    Nabu::Adapters::Salom.new
  end

  def conformance_workdir
    FIXTURES
  end

  def conformance_expected_source_id
    "salom"
  end

  # --- manifest ---------------------------------------------------------------

  def test_manifest_identifies_the_salom_source
    manifest = Nabu::Adapters::Salom.manifest
    assert_equal "salom", manifest.id
    assert_match(/cc-by-4\.0/, manifest.license, "the dataset card's frontmatter grant, verbatim")
    assert_match(/EURALI/, manifest.license, "the card's requested citation travels with the grant")
    assert_equal "attribution", manifest.license_class
    assert_equal "https://huggingface.co/datasets/collectivat/salom-ladino-articles",
                 manifest.upstream_url
    assert_equal "sentence-lines", manifest.parser_family
  end

  # --- discover ---------------------------------------------------------------

  def test_discover_mints_the_one_articles_ref
    refs = Nabu::Adapters::Salom.new.discover(FIXTURES).to_a
    assert_equal [URN], refs.map(&:id)
    assert_equal "salom", refs.first.source_id
  end

  def test_discover_of_an_unfetched_workdir_yields_nothing
    Dir.mktmpdir do |dir|
      assert_empty Nabu::Adapters::Salom.new.discover(dir).to_a
    end
  end

  # --- parse ------------------------------------------------------------------

  def test_parse_mints_one_ladino_passage_per_line_numbered_from_one
    document = parse_document
    assert_equal "lad", document.language
    assert_equal 8, document.size,
                 "8 sentences — the fixture's trailing blank line (upstream's own tail) mints nothing"
    assert_equal %w[1 2 3 4 5 6 7 8], document.map { |p| p.urn.split(":").last },
                 "identity is the 1-based line number — upstream ships no sentence ids"
    assert_equal (0..7).to_a, document.map(&:sequence)
  end

  def test_passage_text_is_the_sentence_verbatim
    passage = parse_document.first
    assert_equal "En Marso de 1942, los partizanos se vyeron ovligados a reorganizarsen " \
                 "i trokar de taktika despues de munchas desfechas",
                 passage.text
  end

  def test_blank_lines_mint_no_passage_but_keep_numbering
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, Nabu::Adapters::Salom::FILENAME),
                 "Una frase.\n\nOtra frase.\n")
      adapter = Nabu::Adapters::Salom.new
      document = adapter.parse(adapter.discover(dir).first)
      assert_equal ["#{URN}:1", "#{URN}:3"], document.map(&:urn),
                   "an upstream blank can never re-flow every following urn"
    end
  end

  # --- parse: damage is loud --------------------------------------------------

  def test_malformed_utf8_raises_parse_error
    Dir.mktmpdir do |dir|
      File.binwrite(File.join(dir, Nabu::Adapters::Salom::FILENAME), "bueno\n\xFFmalo\n".b)
      adapter = Nabu::Adapters::Salom.new
      error = assert_raises(Nabu::ParseError) { adapter.parse(adapter.discover(dir).first) }
      assert_match(/line 2/, error.message)
    end
  end

  def test_an_empty_file_raises_parse_error
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, Nabu::Adapters::Salom::FILENAME), "\n")
      adapter = Nabu::Adapters::Salom.new
      assert_raises(Nabu::ParseError) { adapter.parse(adapter.discover(dir).first) }
    end
  end

  # --- fetch (WebMock only, no network) ---------------------------------------

  def test_fetch_downloads_the_articles_file_via_file_fetch
    stub_request(:get, URL).to_return(
      status: 200, body: File.binread(File.join(FIXTURES, Nabu::Adapters::Salom::FILENAME)),
      headers: { "Content-Type" => "text/plain" }
    )
    Dir.mktmpdir do |workdir|
      adapter = Nabu::Adapters::Salom.new
      report = adapter.fetch(workdir)
      assert_instance_of Nabu::FetchReport, report
      assert_match(/\A\h{64}\z/, report.sha)
      assert_equal [URN], adapter.discover(workdir).map(&:id),
                   "the file lands in place and discover sees it"
    end
  end

  def test_fetch_wraps_http_failure_in_fetch_error
    stub_request(:get, URL).to_return(status: 500)
    Dir.mktmpdir do |workdir|
      assert_raises(Nabu::FetchError) { Nabu::Adapters::Salom.new.fetch(workdir) }
    end
  end

  # --- remote-health probe shape ----------------------------------------------

  def test_probe_heads_the_resolve_url
    assert_equal :http_zip, Nabu::Adapters::Salom.remote_probe_strategy
    targets = Nabu::Adapters::Salom.http_probe_targets
    assert_equal [URL], targets.map(&:zip_url)
    assert_equal [""], targets.map(&:state_subdir)
    assert_equal [Nabu::FileFetch::STATE_FILE], targets.map(&:state_file).uniq
    assert(targets.all? { |t| t.metadata_url.nil? },
           "the license lives on the dataset card, no probe-shaped endpoint")
  end

  # --- store: idempotent double-load ------------------------------------------

  def test_loads_idempotently_into_the_store
    catalog = store_test_db
    source = create_source
    adapter = Nabu::Adapters::Salom.new
    first = Nabu::Store::Loader.new(db: catalog, source: source)
                               .load_from(adapter, workdir: FIXTURES, full: true)
    assert_equal 1, first.added
    assert_equal 0, first.errored
    assert_equal 8, catalog[:passages].count

    second = Nabu::Store::Loader.new(db: catalog, source: source)
                                .load_from(adapter, workdir: FIXTURES, full: true)
    assert_equal 0, second.errored
    assert_equal 1, second.skipped, "a byte-identical reload skips the document"
    assert_equal [1], catalog[:passages].distinct.select_map(:revision),
                 "a byte-identical reload bumps no revisions"
  end

  # --- registry round-trip ----------------------------------------------------

  def test_registry_resolves_salom_and_manifest_agrees
    registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
    entry = registry["salom"]
    refute_nil entry, "salom must be registered in config/sources.yml"
    assert_equal Nabu::Adapters::Salom, entry.adapter_class
    assert entry.wired, "flipped 2026-08-21 — first sync owner-round-verified (10,685 sentences)"
    assert_equal Nabu::Adapters::Salom.manifest, entry.manifest
  end

  private

  def parse_document
    adapter = Nabu::Adapters::Salom.new
    ref = adapter.discover(FIXTURES).first
    refute_nil ref
    adapter.parse(ref)
  end

  def create_source
    Nabu::Store::Source.create(slug: "salom", name: "Şalom Ladino articles",
                               adapter_class: "Nabu::Adapters::Salom",
                               license_class: "attribution")
  end
end

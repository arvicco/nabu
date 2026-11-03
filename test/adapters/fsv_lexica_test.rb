# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# fsv-lexica: Språkbanken's three Old Swedish dictionaries (Söderwall,
# Söderwall's supplement, Schlyter) as three shelves of one source.
# Trimmed-real fixtures: 3 + 2 + 3 LexicalEntry blocks byte-verbatim
# (test/fixtures/fsv-lexica/README.md). A dictionary source serves
# entries, not passages, so this mirrors AdapterConformance for the
# dictionary shape (the DefinitionsShelfChecks stance).
class FsvLexicaTest < Minitest::Test
  include StoreTestDB

  ADAPTER = Nabu::Adapters::FsvLexica

  def fixtures = Nabu::TestSupport.fixtures("fsv-lexica")

  def documents
    @documents ||= begin
      adapter = ADAPTER.new
      adapter.discover(fixtures).to_h { |ref| [ref.metadata.fetch("dictionary"), adapter.parse(ref)] }
    end
  end

  def test_manifest_carries_the_verbatim_license
    manifest = ADAPTER.manifest
    assert_equal "fsv-lexica", manifest.id
    assert_match(/CC-BY-4\.0/, manifest.license)
    assert_equal "attribution", manifest.license_class
    assert_equal "spraakbanken-lmf", manifest.parser_family
    assert_equal :dictionary, ADAPTER.content_kind
  end

  def test_discover_yields_the_three_dictionaries_in_order_and_nothing_before_a_fetch
    refs = ADAPTER.new.discover(fixtures).to_a
    assert_equal(%w[soederwall soederwall-supp schlyter], refs.map { |r| r.metadata.fetch("dictionary") })
    assert_equal %w[soederwall:soederwall.xml soederwall-supp:soederwall-supp.xml schlyter:schlyter.xml], refs.map(&:id)
    assert(refs.all? { |r| r.source_id == "fsv-lexica" })
    Dir.mktmpdir { |empty| assert_empty ADAPTER.new.discover(empty).to_a }
  end

  def test_parse_yields_one_sv_dictionary_document_per_file
    assert_equal({ "soederwall" => 3, "soederwall-supp" => 2, "schlyter" => 3 }, documents.transform_values(&:size))
    documents.each do |slug, document|
      assert_equal slug, document.slug
      assert_equal "sv", document.language
    end
    assert_match(/Söderwall/, documents["soederwall"].title)
    assert_match(/Schlyter/, documents["schlyter"].title)
  end

  def test_a_known_entry_reads_with_its_swedish_gloss
    avisning = documents["schlyter"].entries.find { |e| e.entry_id == "fsvm--avisning..nn.1" }
    assert_equal "avisning", avisning.headword
    assert_equal "anvisning, hänvisning", avisning.gloss
  end

  def test_entry_ids_are_unique_and_stable_across_independent_passes
    snapshot = lambda do
      adapter = ADAPTER.new
      adapter.discover(fixtures).flat_map { |ref| adapter.parse(ref).map(&:entry_id) }
    end
    first = snapshot.call
    assert_equal first, snapshot.call
    documents.each_value { |d| assert_equal d.map(&:entry_id).uniq, d.map(&:entry_id) }
  end

  def test_entry_output_is_nfc_and_non_empty
    documents.each_value do |document|
      document.each do |entry|
        assert entry.headword.unicode_normalized?(:nfc)
        assert entry.body.unicode_normalized?(:nfc)
        refute_empty entry.body
      end
    end
  end

  def test_loading_the_fixture_twice_is_idempotent_with_stable_urns
    db = store_test_db
    source = Nabu::Store::Source.create(
      slug: "fsv-lexica", name: "fsv-lexica", adapter_class: ADAPTER.name,
      license: ADAPTER.manifest.license, license_class: "attribution"
    )
    load = -> { Nabu::Store::DictionaryLoader.new(db: db, source: source).load_from(ADAPTER.new, workdir: fixtures) }
    load.call
    urns = db[:dictionary_entries].order(:urn).select_map(%i[urn revision])
    load.call
    assert_equal urns, db[:dictionary_entries].order(:urn).select_map(%i[urn revision])
    assert_equal 8, urns.size
    assert(urns.any? { |urn, _| urn.start_with?("urn:nabu:dict:schlyter:") })
  end

  def test_probe_heads_each_lmf_file
    targets = ADAPTER.http_probe_targets
    urls = %w[soederwall soederwall-supp schlyter].map { |r| "https://svn.spraakbanken.gu.se/sb-arkiv/pub/lmf/#{r}/#{r}.xml" }
    assert_equal urls, targets.map(&:zip_url)
    assert_equal %w[soederwall soederwall-supp schlyter], targets.map(&:state_subdir)
  end

  def test_registry_row_exists_unwired_with_manual_sync_policy
    entry = Nabu::SourceRegistry.load(File.join(Nabu::Config::PROJECT_ROOT, "config", "sources.yml"))["fsv-lexica"]
    refute_nil entry
    assert_equal ADAPTER, entry.adapter_class
    assert_equal "manual", entry.sync_policy
  end
end

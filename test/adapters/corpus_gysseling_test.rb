# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# Corpus Gysseling adapter tests (P84-7): the Early Middle Dutch (dum) gold
# lemma+POS corpus over the .fromdb coding scheme, under the research_private
# posture (INT non-commercial, no redistribution grant → strictest reading).
# As with Corpus Oudnederlands the bytes NEVER enter the public repo: fixtures
# live under the gitignored local/fixtures/, data-bearing cases SKIP when
# absent. The MCP tests are the exclusion EVIDENCE; the token tests pin the
# scheme decode (abbreviations expanded, foreign <q> form-only, portmanteau
# lemmata joined with '+', place codes resolved via plaats.txt/regio.txt).
class CorpusGysselingTest < Minitest::Test
  include AdapterConformance
  include StoreTestDB

  SLUG = "corpus-gysseling"
  D0003 = "urn:nabu:corpus-gysseling:0003"

  def conformance_adapter
    Nabu::Adapters::CorpusGysseling.new
  end

  def conformance_workdir
    require_fixtures!
    Nabu::TestSupport.local_fixtures(SLUG)
  end

  def conformance_expected_source_id
    SLUG
  end

  # --- manifest / Manual Adapter contract (run in CI, no bytes) ----------------

  def test_manifest_is_research_private_gold_lemma_pos
    manifest = Nabu::Adapters::CorpusGysseling.manifest
    assert_equal SLUG, manifest.id
    assert_equal "research_private", manifest.license_class
    assert_match(/never redistributed/i, manifest.license)
    assert_equal "gysseling-fromdb", manifest.parser_family
  end

  def test_manual_acquisition_spec_names_the_zip
    spec = Nabu::Adapters::CorpusGysseling.manual_acquisition
    assert_equal ["corpus-gysseling.zip"], spec.files.map(&:name)
    assert_match(/taalmaterialen\.ivdnt\.org/, spec.upstream_url)
  end

  def test_sync_prints_the_acquisition_card_while_no_drop_is_present
    Dir.mktmpdir do |root|
      workdir = File.join(root, "canonical", SLUG)
      FileUtils.mkdir_p(workdir)
      error = assert_raises(Nabu::ManualDrop::AwaitingAcquisition) do
        Nabu::Adapters::CorpusGysseling.new.fetch(workdir)
      end
      assert_match("corpus-gysseling.zip", error.message)
      assert_match("incoming/corpus-gysseling", error.message.tr(File::SEPARATOR, "/"))
    end
  end

  # --- discover / parse: the coding scheme decoded (data-bearing) --------------

  def test_discover_ids_are_the_docid_filename_stems
    require_fixtures!
    ids = Nabu::Adapters::CorpusGysseling.new.discover(fixtures).map(&:id)
    assert_includes ids, D0003, "0003.fromdb → docId 0003 → urn suffix"
  end

  def test_a_line_becomes_a_passage_with_gold_lemma_pos_tokens
    require_fixtures!
    document = parse_urn(D0003)
    assert_equal "dum", document.language
    passage = document.first
    assert_equal "#{D0003}:20.28", passage.urn, "urn suffix is the page.line coordinate"
    assert_equal "Dit es de regle der gandser brodre ende sustre uander lazerze", passage.text
    tokens = passage.annotations.fetch("tokens")
    assert_equal({ "form" => "Dit", "lemma" => "DIT", "pos" => "410" }, tokens.first)
    regle = tokens.find { |t| t["form"] == "regle" }
    assert_equal "REGEL", regle.fetch("lemma"), "the VMNW citation lemma, not the surface form"
  end

  def test_portmanteau_token_keeps_joined_lemmata_and_tags
    require_fixtures!
    token = parse_urn(D0003).flat_map { |p| p.annotations.fetch("tokens") }
                            .find { |t| t["form"] == "uander" }
    assert_equal "DE+VAN", token.fetch("lemma"), "joined exactly as upstream writes the portmanteau"
    assert_equal "475+700", token.fetch("pos")
  end

  def test_foreign_matrix_words_are_form_only_tokens
    require_fixtures!
    # 0002B is a Latin charter — its words are <q> foreign, no dum lemmata.
    document = parse_urn("urn:nabu:corpus-gysseling:0002B")
    tokens = document.first.annotations.fetch("tokens")
    assert(tokens.any? { |t| t["foreign"] && !t.key?("lemma") },
           "Latin matrix words are kept in the text but seed no dum lemma")
  end

  def test_dating_and_atlas_place_codes_resolve_into_document_metadata
    require_fixtures!
    meta = parse_urn(D0003).metadata
    assert_equal 1236, meta["not_before"]
    assert_equal 1236, meta["not_after"]
    assert_equal "41", meta["plaats_code"]
    assert_equal "Gent", meta["place"], "plaats.txt resolves code 41 → Gent"
    assert_equal "Oost-Vlaanderen", meta["region"], "regio.txt resolves code 9"
  end

  # --- MCP exclusion EVIDENCE ---------------------------------------------------

  def test_research_private_gold_lemmas_are_hidden_by_default_and_opt_in_reveals
    require_fixtures!
    with_loaded_corpus do |tools|
      hidden = JSON.parse(tools.call("nabu_search", { "query" => "regle" })[:content][0][:text])
      assert_empty hidden.fetch("matches"), "research_private is default-excluded"

      shown = JSON.parse(tools.call("nabu_search",
                                    { "query" => "regle", "include_restricted" => true })[:content][0][:text])
      urns = shown.fetch("matches").map { |h| h.fetch("urn") }
      assert_includes urns, "#{D0003}:20.28"
    end
  end

  # --- registry round-trip ------------------------------------------------------

  def test_registry_resolves_the_source_unwired
    registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
    entry = registry[SLUG]
    refute_nil entry, "#{SLUG} must be registered in config/sources.yml"
    assert_equal Nabu::Adapters::CorpusGysseling, entry.adapter_class
    refute entry.wired
    assert_equal "manual", entry.sync_policy
  end

  private

  def require_fixtures!
    return if Nabu::TestSupport.local_fixtures?(SLUG)

    skip "#{SLUG} local fixtures absent (INT-NC, no-redistribution — bytes never in git)"
  end

  def fixtures
    Nabu::TestSupport.local_fixtures(SLUG)
  end

  def parse_urn(urn)
    adapter = Nabu::Adapters::CorpusGysseling.new
    ref = adapter.discover(fixtures).find { |r| r.id == urn }
    refute_nil ref, "expected discover to yield #{urn}"
    adapter.parse(ref)
  end

  def with_loaded_corpus
    catalog = store_test_db
    fulltext = Nabu::Store.connect_fulltext("sqlite::memory:")
    source = Nabu::Store::Source.create(
      slug: SLUG, name: "Corpus Gysseling", adapter_class: "Nabu::Adapters::CorpusGysseling",
      license_class: Nabu::Adapters::CorpusGysseling.manifest.license_class, enabled: true
    )
    Nabu::Store::Loader.new(db: catalog, source: source)
                       .load_from(Nabu::Adapters::CorpusGysseling.new, workdir: fixtures, full: true)
    Nabu::Store::Indexer.rebuild!(catalog: catalog, fulltext: fulltext)
    yield Nabu::MCP::Tools.new(catalog: catalog, fulltext: fulltext)
  ensure
    fulltext&.disconnect
  end
end

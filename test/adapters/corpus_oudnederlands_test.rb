# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# Corpus Oudnederlands adapter tests (P84-7): the Old-Dutch (odt) corpus under
# the research_private posture (INT non-commercial, no redistribution grant →
# strictest reading, owner standing rule). The corpus bytes MUST NOT enter the
# public repo, so the fixtures live under the gitignored local/fixtures/ and
# every data-bearing case SKIPs when they are absent — CI and other users pass
# without the bytes, the owner's local suite tests against reality. The MCP
# tests are the packet's exclusion EVIDENCE: research_private wired through the
# source row → indexer → tools, default-hidden, include_restricted opt-in
# (the freising precedent).
class CorpusOudnederlandsTest < Minitest::Test
  include AdapterConformance
  include StoreTestDB

  SLUG = "corpus-oudnederlands"
  TOORNWERD = "urn:nabu:corpus-oudnederlands:runeninscriptie_toornwerd"

  # --- conformance hooks (data-bearing → skip when the local fixtures absent) --

  def conformance_adapter
    Nabu::Adapters::CorpusOudnederlands.new
  end

  def conformance_workdir
    require_fixtures!
    Nabu::TestSupport.local_fixtures(SLUG)
  end

  def conformance_expected_source_id
    SLUG
  end

  # --- manifest: the research_private posture (runs in CI, no bytes needed) ----

  def test_manifest_is_research_private_non_commercial
    manifest = Nabu::Adapters::CorpusOudnederlands.manifest
    assert_equal SLUG, manifest.id
    assert_equal "research_private", manifest.license_class,
                 "INT-NC with no redistribution grant → strictest reading, never redistributed"
    assert_match(/non-commercial/i, manifest.license)
    assert_match(/never redistributed/i, manifest.license)
    assert_equal "onw-tei", manifest.parser_family
  end

  # --- the Manual Adapter contract (the card runs without any bytes) -----------

  def test_manual_acquisition_spec_names_the_zip_and_the_portal
    spec = Nabu::Adapters::CorpusOudnederlands.manual_acquisition
    assert_equal SLUG, spec.slug
    assert_equal ["corpus-oudnederlands.zip"], spec.files.map(&:name)
    assert spec.files.first.required
    assert_match(/taalmaterialen\.ivdnt\.org/, spec.upstream_url)
  end

  def test_sync_prints_the_acquisition_card_while_no_drop_is_present
    Dir.mktmpdir do |root|
      workdir = File.join(root, "canonical", SLUG)
      FileUtils.mkdir_p(workdir)
      error = assert_raises(Nabu::ManualDrop::AwaitingAcquisition) do
        Nabu::Adapters::CorpusOudnederlands.new.fetch(workdir)
      end
      assert_match("corpus-oudnederlands.zip", error.message)
      assert_match("incoming/corpus-oudnederlands", error.message.tr(File::SEPARATOR, "/"))
    end
  end

  # --- discover / parse (data-bearing) -----------------------------------------

  def test_discover_mints_one_ref_per_tei_member_from_the_filename
    require_fixtures!
    ids = Nabu::Adapters::CorpusOudnederlands.new.discover(fixtures).map(&:id)
    assert_includes ids, TOORNWERD, "sourceID onw_<id> = filename stem = urn suffix"
    assert(ids.all? { |id| id.start_with?("urn:nabu:corpus-oudnederlands:") })
  end

  def test_a_citation_becomes_a_passage_with_gold_lemma_and_pos_tokens
    require_fixtures!
    document = parse_urn(TOORNWERD)
    assert_equal "odt", document.language
    assert_equal "Kam van Toornwerd", document.title
    passage = document.first
    assert_equal "#{TOORNWERD}:1", passage.urn
    assert_equal "kobu", passage.text, "the <w>/<seg> reading of the runic attestation"
    token = passage.annotations.fetch("tokens").first
    assert_equal "KAM", token.fetch("lemma"), "the upstream CAPS citation lemma"
    assert_equal "kobu", token.fetch("form")
    assert_match(/NOU-C/, token.fetch("pos"))
    assert_equal "Met deze kam.", passage.annotations["translation"]
  end

  def test_the_teiheader_date_and_place_ride_as_document_metadata
    require_fixtures!
    document = parse_urn(TOORNWERD)
    assert_equal 701, document.metadata["not_before"]
    assert_equal 800, document.metadata["not_after"]
    assert_equal "Toornwerd", document.metadata["place"]
    assert_equal "onw_runeninscriptie_toornwerd", document.metadata["source_id"]
  end

  def test_a_foreign_word_contributes_a_form_only_token_no_lemma
    require_fixtures!
    document = parse_urn("urn:nabu:corpus-oudnederlands:groningse_psalmglossen_cg")
    foreign = document.flat_map { |p| p.annotations.fetch("tokens") }
                      .find { |t| t["form"].start_with?("[descendit]") }
    refute_nil foreign, "the bracketed Latin gloss is kept in the reading text"
    refute foreign.key?("lemma"), "a foreign RES word must not seed the odt lemma index"
  end

  # --- MCP exclusion EVIDENCE (research_private, end to end) --------------------

  def test_research_private_is_hidden_from_search_by_default_and_opt_in_reveals
    require_fixtures!
    with_loaded_corpus do |tools|
      hidden = JSON.parse(tools.call("nabu_search", { "query" => "kobu" })[:content][0][:text])
      assert_empty hidden.fetch("matches"), "research_private is default-excluded from search"

      shown = JSON.parse(tools.call("nabu_search",
                                    { "query" => "kobu", "include_restricted" => true })[:content][0][:text])
      urns = shown.fetch("matches").map { |h| h.fetch("urn") }
      assert_includes urns, "#{TOORNWERD}:1"
      hit = shown.fetch("matches").find { |h| h.fetch("urn") == "#{TOORNWERD}:1" }
      assert_equal "research_private", hit.fetch("license_class")
    end
  end

  def test_nabu_show_withholds_by_default_and_reveals_on_opt_in
    require_fixtures!
    with_loaded_corpus do |tools|
      withheld = tools.call("nabu_show", { "urn" => "#{TOORNWERD}:1" })
      assert_match(/research_private/, withheld[:content][0][:text])
      refute_match(/kobu/, withheld[:content][0][:text], "the odt text itself does not leak")

      body = JSON.parse(tools.call("nabu_show",
                                   { "urn" => "#{TOORNWERD}:1", "include_restricted" => true })[:content][0][:text])
      assert_equal "kobu", body.fetch("text")
    end
  end

  # --- registry round-trip (runs in CI) ----------------------------------------

  def test_registry_resolves_the_source_unwired
    registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
    entry = registry[SLUG]
    refute_nil entry, "#{SLUG} must be registered in config/sources.yml"
    assert_equal Nabu::Adapters::CorpusOudnederlands, entry.adapter_class
    refute entry.wired, "wired flips only after the owner's first real sync + eyeball"
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
    adapter = Nabu::Adapters::CorpusOudnederlands.new
    ref = adapter.discover(fixtures).find { |r| r.id == urn }
    refute_nil ref, "expected discover to yield #{urn}"
    adapter.parse(ref)
  end

  def with_loaded_corpus
    catalog = store_test_db
    fulltext = Nabu::Store.connect_fulltext("sqlite::memory:")
    source = Nabu::Store::Source.create(
      slug: SLUG, name: "Corpus Oudnederlands", adapter_class: "Nabu::Adapters::CorpusOudnederlands",
      license_class: Nabu::Adapters::CorpusOudnederlands.manifest.license_class, enabled: true
    )
    Nabu::Store::Loader.new(db: catalog, source: source)
                       .load_from(Nabu::Adapters::CorpusOudnederlands.new, workdir: fixtures, full: true)
    Nabu::Store::Indexer.rebuild!(catalog: catalog, fulltext: fulltext)
    yield Nabu::MCP::Tools.new(catalog: catalog, fulltext: fulltext)
  ensure
    fulltext&.disconnect
  end
end

# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# Corpus Oudfries adapter tests: the Old Frisian (ofs) corpus under the
# research_private posture (INT non-commercial, no redistribution grant →
# strictest reading — the corpus-oudnederlands/gysseling posture). The
# corpus bytes MUST NOT enter the public repo: the fixtures live under the
# gitignored local/fixtures/, and every data-bearing case skips when they are
# absent (a FAILURE on the owner's box — StrictSkips). The MCP cases are the
# exclusion evidence: research_private is default-hidden end to end.
class CorpusOudfriesTest < Minitest::Test
  include AdapterConformance
  include StoreTestDB

  SLUG = "corpus-oudfries"
  K17 = "urn:nabu:corpus-oudfries:R1-K17"
  HAV = "urn:nabu:corpus-oudfries:E1-Hav"

  # --- conformance hooks (data-bearing → skip when the local fixtures absent) --

  def conformance_adapter
    Nabu::Adapters::CorpusOudfries.new
  end

  def conformance_workdir
    require_fixtures!
    fixtures
  end

  def conformance_expected_source_id
    SLUG
  end

  # --- manifest + the Manual Adapter contract (no bytes needed) ----------------

  def test_manifest_is_research_private_non_commercial
    manifest = Nabu::Adapters::CorpusOudfries.manifest
    assert_equal SLUG, manifest.id
    assert_equal "research_private", manifest.license_class
    assert_match(/non-commercial/i, manifest.license)
    assert_match(/never redistributed/i, manifest.license)
    assert_equal "oudfries-tei", manifest.parser_family
    assert_equal "https://taalmaterialen.ivdnt.org/download/corpus-oudfries-download/", manifest.upstream_url
  end

  def test_manual_acquisition_spec_names_upstreams_own_zip
    spec = Nabu::Adapters::CorpusOudfries.manual_acquisition
    assert_equal SLUG, spec.slug
    assert_equal ["CorpusOudfries1.0.zip"], spec.files.map(&:name), "the download's own filename — no rename step"
    assert spec.files.first.required
  end

  def test_sync_prints_the_acquisition_card_while_no_drop_is_present
    Dir.mktmpdir do |root|
      workdir = File.join(root, "canonical", SLUG)
      FileUtils.mkdir_p(workdir)
      error = assert_raises(Nabu::ManualDrop::AwaitingAcquisition) do
        Nabu::Adapters::CorpusOudfries.new.fetch(workdir)
      end
      assert_match("CorpusOudfries1.0.zip", error.message)
      assert_match("incoming/corpus-oudfries", error.message.tr(File::SEPARATOR, "/"))
    end
  end

  def test_the_sniff_refuses_a_zip_without_witness_members
    Dir.mktmpdir do |dir|
      page = File.join(dir, "login.html")
      File.write(page, "<html>Log in om te downloaden</html>")
      assert_match(/not a readable ZIP/, Nabu::Adapters::CorpusOudfries.zip_complaint(page))
    end
    require_fixtures!
    assert_nil Nabu::Adapters::CorpusOudfries.zip_complaint(File.join(fixtures, "CorpusOudfries1.0.zip"))
  end

  # --- discover: the grain census (data-bearing) --------------------------------

  def test_discover_mints_one_ref_per_witness_from_the_filename_stem
    require_fixtures!
    ids = Nabu::Adapters::CorpusOudfries.new.discover(fixtures).map(&:id)
    assert_equal %w[B2-BrBb E1-Bro E1-Hav R1-K17 R1-Mrk].map { |s| "urn:nabu:#{SLUG}:#{s}" }, ids,
                 "stem before the first dot: E1-Hav.tei.3.exported.xml → E1-Hav, R1-K17.data.xml → R1-K17"
  end

  def test_the_readme_member_is_a_counted_skip_never_a_document
    require_fixtures!
    skips = Nabu::Adapters::CorpusOudfries.new.discovery_skips(fixtures)
    assert_equal 1, skips.skipped_by_rule
    assert_equal 0, skips.unrecognized
    assert_match(/README\.txt/, skips.notes.join)
  end

  # --- parse (data-bearing) -----------------------------------------------------

  def test_the_seventeen_statutes_open_with_the_known_old_frisian_line
    document = parse_urn(K17)
    assert_equal "ofs", document.language
    assert_equal "Seventeen Statutes — R1-K17", document.title
    passage = document.first
    assert_equal "#{K17}:1", passage.urn
    assert_equal "Thit is thiv forme liodkest. and thes kyning-kerles ieft. and londriuch allera frisona.", passage.text
    assert_equal "1", passage.annotations["n"]
    token = passage.annotations.fetch("tokens").first
    assert_equal({ "form" => "Thit", "lemma" => "thit", "pos" => "PRON" }, token)
  end

  def test_witness_dates_ride_the_timeline_keys_and_composition_dates_their_own
    meta = parse_urn(K17).metadata
    assert_equal 1250, meta["not_before"], "manuscript_year_from — the witness (artifact) date"
    assert_equal 1300, meta["not_after"]
    assert_equal "1250-1300", meta["date_raw"]
    assert_equal 1000, meta["composition_not_before"], "text_year_from — the attributed composition era"
    assert_equal 1100, meta["composition_not_after"]
  end

  def test_region_dialect_manuscript_and_genre_are_mined
    meta = parse_urn(HAV).metadata
    assert_equal "Emsingo", meta["region"]
    assert_equal "East Old Frisian", meta["dialect"]
    assert_equal "First Emsingo Manuscript", meta["manuscript"]
    assert_equal "E1", meta["manuscript_code"]
    assert_equal ["land law", "penal"], meta["genre"], "text_category_1..3, empty slots dropped"
    assert_equal "645", meta["gerbenzon_number"]
    assert_equal "OTR 4: V 18", meta["edition"]
    assert_equal "Drie Hoofddaden", meta["title_nl"]
  end

  def test_the_header_sigil_rides_beside_the_filename_urn
    meta = parse_urn("urn:nabu:corpus-oudfries:B2-BrBb").metadata
    assert_equal "B2-BrbB", meta["sigil"], "upstream's header title differs in case from its filename"
  end

  def test_an_empty_text_year_mints_no_composition_claim
    meta = parse_urn("urn:nabu:corpus-oudfries:E1-Bro").metadata
    refute meta.key?("composition_not_before")
    refute meta.key?("composition_not_after")
    assert_equal 1375, meta["not_before"], "the witness date still rides"
  end

  # --- the axes wiring (shipped config) -----------------------------------------

  def test_the_genre_ladder_folds_through_the_shipped_kind_map
    kinds = Nabu::Kinds.load(
      classes_path: File.join(Nabu::Config::PROJECT_ROOT, "config", "kind_classes.yml"),
      map_path: File.join(Nabu::Config::PROJECT_ROOT, "config", "kind_map.yml")
    )
    assert_equal ["legal/law"], kinds.normalize(SLUG, "pan-frisian")
    assert_equal ["legal/law"], kinds.normalize(SLUG, "compensation")
    assert_equal ["legal"], kinds.normalize(SLUG, "oaths/formulas")
    assert_equal ["literary/poetry"], kinds.normalize(SLUG, "poetry")
    assert_empty kinds.normalize(SLUG, "Frisian matter"), "a thematic strand is a declared non-claim"
    require_fixtures!
    adapter = Nabu::Adapters::CorpusOudfries.new
    genres = adapter.discover(fixtures).flat_map { |ref| adapter.parse(ref).metadata.fetch("genre") }.uniq
    genres.each do |genre|
      fold = kinds.fold(SLUG, genre)
      assert_empty fold.uncovered, "#{genre.inspect} must be mapped or declared"
    end
  end

  def test_the_metadata_dates_lane_is_registered
    assert_equal :bounds_keys, Nabu::Store::TimelineBuilder::MetadataDates::SHAPES[SLUG]
    assert_equal "region", Nabu::Store::TimelineBuilder::MetadataDates::PLACE_KEYS[SLUG]
  end

  # --- MCP exclusion EVIDENCE (research_private, end to end) --------------------

  def test_research_private_is_hidden_from_search_by_default_and_opt_in_reveals
    require_fixtures!
    with_loaded_corpus do |tools|
      hidden = JSON.parse(tools.call("nabu_search", { "query" => "liodkest" })[:content][0][:text])
      assert_empty hidden.fetch("matches"), "research_private is default-excluded from search"

      shown = JSON.parse(tools.call("nabu_search",
                                    { "query" => "liodkest", "include_restricted" => true })[:content][0][:text])
      hit = shown.fetch("matches").find { |h| h.fetch("urn") == "#{K17}:1" }
      refute_nil hit
      assert_equal "research_private", hit.fetch("license_class")
    end
  end

  # --- registry round-trip (runs in CI) ----------------------------------------

  def test_registry_resolves_the_source_wired_after_the_first_sync
    registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
    entry = registry[SLUG]
    refute_nil entry, "#{SLUG} must be registered in config/sources.yml"
    assert_equal Nabu::Adapters::CorpusOudfries, entry.adapter_class
    assert entry.wired, "wired flipped at the first sync: 177 docs / 14,136 passages, exactly on the census"
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
    require_fixtures!
    adapter = Nabu::Adapters::CorpusOudfries.new
    ref = adapter.discover(fixtures).find { |r| r.id == urn }
    refute_nil ref, "expected discover to yield #{urn}"
    adapter.parse(ref)
  end

  def with_loaded_corpus
    catalog = store_test_db
    fulltext = Nabu::Store.connect_fulltext("sqlite::memory:")
    source = Nabu::Store::Source.create(
      slug: SLUG, name: "Corpus Oudfries", adapter_class: "Nabu::Adapters::CorpusOudfries",
      license_class: Nabu::Adapters::CorpusOudfries.manifest.license_class, enabled: true
    )
    Nabu::Store::Loader.new(db: catalog, source: source)
                       .load_from(Nabu::Adapters::CorpusOudfries.new, workdir: fixtures, full: true)
    Nabu::Store::Indexer.rebuild!(catalog: catalog, fulltext: fulltext)
    yield Nabu::MCP::Tools.new(catalog: catalog, fulltext: fulltext)
  ensure
    fulltext&.disconnect
  end
end

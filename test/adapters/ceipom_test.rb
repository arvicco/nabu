# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# Nabu::Adapters::Ceipom (P29-1): CEIPoM — the Corpus of the Epigraphy of
# the Italian Peninsula in the 1st Millennium BCE (Pitts, KU Leuven; Zenodo
# 6475427 v1.3, CC BY-SA 4.0). Five relational UTF-16 CSVs: texts /
# sentences / tokens / analysis / links. Document = the TEXT (3,875
# upstream), passage = the SENTENCE (5,303) on upstream's globally-unique
# sentence ids.
#
# THE ENCODING FIRST, pinned with real bytes: every upstream CSV is
# UTF-16LE with a BOM (FF FE) — decoded at the adapter boundary, never
# stored un-decoded; the fixture files preserve the BOM byte-verbatim.
#
# LANGUAGE MAPPING (the P29-1 census set, closed): Latin→lat (variety
# Faliscan→xfa; the mixed "Faliscan / Latin" variety STAYS lat), Oscan→osc,
# Messapic→cms, Venetic→xve, Umbrian→xum (incl. the Volscian variety),
# Old Sabellic→spx (incl. Old Samnite), Greek→grc. Varieties ride verbatim
# in metadata; an unmapped language value quarantines loudly.
#
# THE LEMMA REALITY (deviation from the packet brief, censused): analysis
# `Lemma` is an opaque lemma ID ("12444a"), NOT a citation form — so tokens
# carry `lemma_id` verbatim and NO "lemma" key is minted (the indexer's
# contract says a lemma is a dictionary form; an ID would poison the lemma
# surfaces). Zero passage_lemmas rows, stated honestly.
class CeipomTest < Minitest::Test
  include AdapterConformance
  include StoreTestDB

  FIBULA_URN = "urn:nabu:ceipom:2"
  DUENOS_URN = "urn:nabu:ceipom:5"
  IGUVINE_URN = "urn:nabu:ceipom:995"

  # The 16 parseable fixture texts (17 minus the sentence-less 793),
  # urn-sorted (lexicographic — the stable discover order).
  EXPECTED_URNS = %w[
    2 5 9 719 819 871 896 954 995 1795 2390 2584 2747 2756 3106 15171
  ].map { |id| "urn:nabu:ceipom:#{id}" }.sort.freeze

  def conformance_adapter
    Nabu::Adapters::Ceipom.new
  end

  def conformance_workdir
    Nabu::TestSupport.fixtures("ceipom")
  end

  def conformance_expected_source_id
    "ceipom"
  end

  def adapter = conformance_adapter

  def workdir = conformance_workdir

  # -- the UTF-16 BOM pin ------------------------------------------------------

  def test_fixture_csvs_are_utf16le_with_bom_byte_verbatim
    %w[texts/texts.csv sentences/sentences.csv tokens/tokens.csv
       analysis/analysis.csv links/links.csv].each do |rel|
      bytes = File.binread(File.join(workdir, rel), 2)
      assert_equal "\xFF\xFE".b, bytes, "#{rel} must keep the upstream UTF-16LE BOM byte-verbatim"
    end
  end

  # -- discover ----------------------------------------------------------------

  def test_discover_yields_one_ref_per_text_with_sentences_sorted_by_urn
    assert_equal EXPECTED_URNS, adapter.discover(workdir).map(&:id)
  end

  def test_sentence_less_texts_are_skipped_by_rule_and_censused
    refute_includes adapter.discover(workdir).map(&:id), "urn:nabu:ceipom:793",
                    "a text with no sentence row has nothing citable — discover must not mint it"
    skips = adapter.discovery_skips(workdir)
    assert_equal 1, skips.skipped_by_rule, "the fixture's one sentence-less text (793)"
    assert_predicate skips, :clean?
  end

  # -- parse: the showpieces ---------------------------------------------------

  def test_fibula_praenestina_parses_to_its_famous_sentence
    document = adapter.parse(ref_for(FIBULA_URN))
    assert_equal "lat", document.language
    assert_equal "Fibula Praenestina", document.title
    assert_equal "CIL XIV 4123", document.metadata["reference"]
    assert_equal ["tm:256173"], document.metadata["related"]
    assert_equal 1, document.size
    passage = document.first
    assert_equal "urn:nabu:ceipom:2:2", passage.urn, "upstream's own sentence id 2"
    assert_equal "Manios med fhefhaked Numasioi", passage.text
  end

  def test_duenos_inscription_parses_to_three_sentences_in_position_order
    document = adapter.parse(ref_for(DUENOS_URN))
    assert_equal "Duenos inscription", document.title
    assert_equal 3, document.size
    assert_equal "urn:nabu:ceipom:5:5", document.first.urn
    assert_match(/\AIovesat deivos qoi med mitat/, document.first.text)
    assert_equal (0..2).to_a, document.map(&:sequence)
  end

  def test_iguvine_tables_carry_their_table_sections
    document = adapter.parse(ref_for(IGUVINE_URN))
    assert_equal "xum", document.language
    assert_equal "Iguvine Tables", document.title
    sections = document.map { |passage| passage.annotations["section"] }
    assert_equal ["Table 1a (native Umbrian alphabet)", "Table 1b (native Umbrian alphabet)",
                  "Table 6a (Latin alphabet)"], sections
  end

  # -- language mapping (the closed census set) --------------------------------

  def test_language_mapping_covers_the_censused_language_and_variety_space
    expected = {
      "9" => "lat",       # archaic Latin stays lat
      "3106" => "lat",    # variety "Faliscan / Latin" (mixed) stays lat
      "2747" => "xfa",    # variety Faliscan
      "954" => "osc",
      "1795" => "cms",
      "2390" => "xve",
      "995" => "xum",
      "871" => "spx",     # Old Sabellic / South Picene
      "896" => "spx",     # Old Sabellic / Old Samnite
      "15171" => "grc"
    }
    expected.each do |text_id, code|
      document = adapter.parse(ref_for("urn:nabu:ceipom:#{text_id}"))
      assert_equal code, document.language, "text #{text_id}"
      document.each { |passage| assert_equal code, passage.language }
    end
  end

  def test_variety_and_family_ride_verbatim_in_metadata
    document = adapter.parse(ref_for("urn:nabu:ceipom:896"))
    assert_equal "Old Sabellic", document.metadata["language"]
    assert_equal "Old Samnite", document.metadata["language_variety"]
    assert_equal "Indo-European::Italic::Latino-Sabellic::Sabellic", document.metadata["language_family"]
  end

  def test_an_unmapped_language_value_quarantines_loudly
    error = assert_raises(Nabu::ParseError) do
      adapter.send(:language_of, { "Language" => "Etruscan", "Language_variety" => "Etruscan",
                                   "Text_ID" => "x" })
    end
    assert_match(/Etruscan/, error.message)
  end

  # -- the script facet (P17-2 pattern) ----------------------------------------

  def test_single_scripts_become_facets_with_the_verbatim_raw
    facet = adapter.parse(ref_for("urn:nabu:ceipom:954")).metadata["facets"]["script"]
    assert_equal({ "value" => "oscan", "raw" => "Oscan" }, facet)
    facet = adapter.parse(ref_for("urn:nabu:ceipom:871")).metadata["facets"]["script"]
    assert_equal({ "value" => "south-picene", "raw" => "South Picene" }, facet)
  end

  def test_mixed_scripts_facet_as_mixed_with_the_verbatim_raw
    facet = adapter.parse(ref_for(IGUVINE_URN)).metadata["facets"]["script"]
    assert_equal({ "value" => "mixed", "raw" => "Umbrian/Latin" }, facet,
                 "the spacing-less upstream variant is still a mixed value")
    facet = adapter.parse(ref_for("urn:nabu:ceipom:2747")).metadata["facets"]["script"]
    assert_equal({ "value" => "mixed", "raw" => "Etruscan / Latin" }, facet)
  end

  # -- tokens + analysis annotations -------------------------------------------

  def test_tokens_merge_dependency_and_analysis_layers
    passage = adapter.parse(ref_for(FIBULA_URN)).first
    tokens = passage.annotations["tokens"]
    assert_equal(%w[manios med fhefhaked numasioi], tokens.map { |t| t["form"] })
    med = tokens[1]
    assert_equal "OBJ", med["relation"]
    assert_equal 165_254, med["head"]
    assert_equal "12444a", med["lemma_id"], "the corpus's opaque lemma ID, verbatim"
    assert_equal "pronoun", med["pos"]
    assert_equal "I", med["meaning"]
    assert_equal "ego", med["latin_equivalent"]
    assert_equal "me", med["latin_form"]
    pred = tokens[2]
    assert_equal "PRED", pred["relation"]
    assert_equal 0, pred["head"], "0 is the root pointer, kept"
    assert_equal "facio", pred["latin_equivalent"]
  end

  def test_no_lemma_key_is_ever_minted_from_the_id_space
    adapter.discover(workdir).each do |ref|
      adapter.parse(ref).each do |passage|
        Array(passage.annotations["tokens"]).each do |token|
          refute token.key?("lemma"),
                 "Lemma is an opaque ID upstream — minting it as a lemma form would poison " \
                 "the lemma index (the honest deviation, class note)"
        end
      end
    end
  end

  def test_null_dashes_are_omitted_not_stored
    passage = adapter.parse(ref_for(FIBULA_URN)).first
    passage.annotations["tokens"].each do |token|
      token.each_value { |value| refute_equal "-", value }
    end
  end

  def test_the_double_analysis_token_keeps_its_alternative
    document = adapter.parse(ref_for(IGUVINE_URN))
    passage = document.find { |p| p.urn.end_with?(":1129") }
    with_alt = passage.annotations["tokens"].select { |t| t.key?("alternatives") }
    assert_equal 1, with_alt.size, "the trim's one multi-analysis token (censused: 12 corpus-wide)"
    assert_equal 1, with_alt.first["alternatives"].size
  end

  def test_token_clean_rides_only_when_it_differs
    document = adapter.parse(ref_for("urn:nabu:ceipom:719"))
    tokens = document.flat_map { |passage| passage.annotations["tokens"] }
    bracketed = tokens.find { |t| t["form"] == "[h]once" }
    assert_equal "honce", bracketed["clean"], "editorial marks stripped upstream ride as clean"
    tokens.each { |t| refute_equal t["form"], t["clean"], "clean rides only when it differs" }
  end

  # -- NFC at the boundary -----------------------------------------------------

  def test_decomposed_combining_marks_compose_at_the_boundary
    document = adapter.parse(ref_for("urn:nabu:ceipom:896"))
    assert_includes document.first.text, "ạ", "a + combining dot-below composes to U+1EA1"
    assert document.first.text.unicode_normalized?(:nfc)
  end

  def test_greek_codepoints_survive_the_utf16_decode
    document = adapter.parse(ref_for("urn:nabu:ceipom:15171"))
    assert_equal "grc", document.language
    assert_includes document.first.text, "νωλαιων"
  end

  # -- reference edges (Trismegistos) ------------------------------------------

  def test_texts_carry_tm_related_targets_including_multi_id_texts
    assert_equal %w[tm:496141 tm:832355], adapter.parse(ref_for("urn:nabu:ceipom:719")).metadata["related"]
    assert_nil adapter.parse(ref_for("urn:nabu:ceipom:2584")).metadata["related"],
               "no links row — no related key, never an empty list"
  end

  def test_reference_producer_is_the_shared_seam_under_the_ceipom_name
    assert Nabu::Adapters::Ceipom.reference_edges?
    producer = Nabu::Adapters::Ceipom.reference_producer(catalog: nil, journal: nil)
    assert_instance_of Nabu::LibraryReferences, producer
    assert_equal "ceipom", producer.producer
  end

  # -- dates/places ride verbatim in metadata (the axis reads canonical) -------

  def test_dates_and_coordinates_ride_verbatim_as_upstream_spells_them
    metadata = adapter.parse(ref_for(FIBULA_URN)).metadata
    assert_equal "-675.0", metadata["date_after"]
    assert_equal "-625.0", metadata["date_before"]
    assert_equal "41.8279573", metadata["latitude"]
    assert_equal "Praeneste (Palestrina)", metadata["provenance"]
  end

  # -- manifest ----------------------------------------------------------------

  def test_manifest_names_the_zenodo_deposit_and_the_share_alike_rider
    manifest = Nabu::Adapters::Ceipom.manifest
    assert_equal "attribution", manifest.license_class
    assert_match(/CC BY-SA 4\.0/, manifest.license)
    assert_match(/zenodo/i, manifest.upstream_url)
    assert_equal "ceipom-csv", manifest.parser_family
  end

  # -- fetch (WebMock only, no network) ----------------------------------------

  def test_fetch_downloads_all_five_csvs_via_file_fetch
    stub_csvs
    Dir.mktmpdir do |dir|
      report = adapter.fetch(dir)
      assert_instance_of Nabu::FetchReport, report
      assert_match(/\A\h{64}\z/, report.sha)
      assert_match(/texts\.csv/, report.notes)
      assert_equal EXPECTED_URNS, adapter.discover(dir).map(&:id),
                   "all five files land in place and discover sees the texts"
    end
  end

  def test_fetch_wraps_http_failure_in_fetch_error
    Nabu::Adapters::Ceipom::FILES.each_value do |file|
      stub_request(:get, file.fetch(:url)).to_return(status: 500)
    end
    Dir.mktmpdir do |dir|
      assert_raises(Nabu::FetchError) { adapter.fetch(dir) }
    end
  end

  # -- remote-health probe shape -----------------------------------------------

  def test_probe_heads_all_five_download_urls
    assert_equal :http_zip, Nabu::Adapters::Ceipom.remote_probe_strategy
    targets = Nabu::Adapters::Ceipom.http_probe_targets
    assert_equal 5, targets.size
    assert_equal %w[texts sentences tokens analysis links], targets.map(&:state_subdir)
    assert_equal [Nabu::FileFetch::STATE_FILE], targets.map(&:state_file).uniq
    assert(targets.all? { |t| t.metadata_url.nil? })
  end

  # -- store: idempotent double-load -------------------------------------------

  def test_loads_idempotently_into_the_store
    catalog = store_test_db
    source = Nabu::Store::Source.create(
      slug: "ceipom", name: "CEIPoM", adapter_class: "Nabu::Adapters::Ceipom",
      license_class: "attribution"
    )
    first = Nabu::Store::Loader.new(db: catalog, source: source)
                               .load_from(adapter, workdir: workdir, full: true)
    assert_equal 16, first.added
    assert_equal 0, first.errored
    assert_equal 26, catalog[:passages].count, "the fixture's 26 sentences"

    second = Nabu::Store::Loader.new(db: catalog, source: source)
                                .load_from(adapter, workdir: workdir, full: true)
    assert_equal 0, second.added
    assert_equal 16, second.skipped
    assert_equal [1], catalog[:documents].select_map(:revision).uniq
  end

  # -- registry ----------------------------------------------------------------

  def test_registry_row_exists_disabled_with_frozen_sync_policy
    registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
    entry = registry["ceipom"]
    refute_nil entry, "config/sources.yml must register ceipom"
    assert_equal Nabu::Adapters::Ceipom, entry.adapter_class
    refute entry.enabled, "enabled: false until the owner-fired first real sync (checklist §6)"
    assert_equal "frozen", entry.sync_policy, "Zenodo versions are immutable — a frozen deposit"
    assert_equal "gold", entry.lemma_tier,
                 "the registry default; NB zero lemma rows mint in v1 (lemma IDs upstream, class note)"
  end

  private

  def ref_for(urn)
    adapter.discover(workdir).find { |ref| ref.id == urn } or
      flunk "no ref #{urn} in the fixture discover set"
  end

  def stub_csvs
    Nabu::Adapters::Ceipom::FILES.each do |name, file|
      stub_request(:get, file.fetch(:url)).to_return(
        status: 200,
        body: File.binread(File.join(workdir, file.fetch(:subdir), "#{name}.csv")),
        headers: { "Last-Modified" => "Thu, 21 Apr 2022 00:00:00 GMT" }
      )
    end
  end
end

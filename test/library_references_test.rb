# frozen_string_literal: true

require "test_helper"
require "json"

# Nabu::LibraryReferences (P19-4): manifest related: urns → kind=reference
# edges in the links journal; language codes stay metadata (no dossier urns
# exist to point at); reruns supersede — the journal always holds the
# current manifests' assertions.
class LibraryReferencesTest < Minitest::Test
  include StoreTestDB

  def setup
    @catalog = store_test_db
    @journal = Nabu::Store::LinksJournal.migrate!(Nabu::Store::LinksJournal.connect("sqlite::memory:"))
    @source = Nabu::Store::Source.create(
      slug: "local-library", name: "Local library", adapter_class: "X", license_class: "research_private"
    )
  end

  def teardown
    @journal.disconnect
  end

  def make_document(urn:, related: nil, collection: "slavistics", withdrawn: false)
    metadata = { "kind" => "article", "collection" => collection }
    metadata["related"] = related if related
    Nabu::Store::Document.create(
      source_id: @source.id, urn: urn, title: urn, language: "und",
      metadata_json: JSON.generate(metadata), content_sha256: "x", revision: 1, withdrawn: withdrawn
    )
  end

  def producer
    Nabu::LibraryReferences.new(catalog: @catalog, journal: @journal)
  end

  def test_mints_reference_edges_from_related_urns_with_manifest_provenance
    make_document(urn: "urn:nabu:local-library:slavistics:leskien",
                  related: ["urn:nabu:local-library:slavistics:jagic", "urn:nabu:ccmh:mar:mt"])
    result = producer.run("local-library")

    assert_equal 2, result.edges_written
    assert_equal 0, result.skipped_codes
    edges = @journal[:links].order(:to_urn).all
    assert_equal(%w[reference reference], edges.map { |edge| edge[:kind] })
    assert_equal ["urn:nabu:local-library:slavistics:leskien"], edges.map { |edge| edge[:from_urn] }.uniq
    assert_nil edges.first[:score], "a manifest assertion carries no fake similarity score"
    assert_equal "manifest local-library/slavistics/manifest.yml", edges.first[:detail],
                 "provenance = the manifest that asserted the edge"
    run = @journal[:link_runs].first(id: result.run_id)
    assert_equal "library", run[:producer]
    assert_equal "local-library", run[:scope]
  end

  def test_language_codes_stay_metadata_counted_never_edges
    make_document(urn: "urn:nabu:local-library:slavistics:leskien", related: %w[chu zle-ort])
    result = producer.run("local-library")

    assert_equal 0, result.edges_written
    assert_equal 2, result.skipped_codes, "P19-1 minted no dossier urns — an edge to an invented urn " \
                                          "would sit permanently unresolved"
    assert_equal 0, @journal[:links].count
  end

  # P25-1: a scheme-bearing target names a stable external id space and
  # mints an edge; only bare ":"-less codes stay metadata.
  def test_external_stable_id_targets_mint_edges
    make_document(urn: "urn:nabu:local-library:slavistics:leskien",
                  related: ["https://dil.ie/18492", "rig:G593", "chu"])
    result = producer.run("local-library")

    assert_equal 2, result.edges_written
    assert_equal 1, result.skipped_codes
    assert_equal ["https://dil.ie/18492", "rig:G593"],
                 @journal[:links].order(:to_urn).select_map(:to_urn)
  end

  # P25-1: the producer parameter keeps independent asserters over the same
  # id space apart — supersession stays scoped to (producer, scope).
  def test_producer_override_runs_supersede_independently
    make_document(urn: "urn:nabu:local-library:slavistics:leskien", related: ["https://dil.ie/18492"])
    library_run = producer.run("local-library")
    ogham_run = producer.run("local-library", producer: "ogham")

    assert_equal "library", @journal[:link_runs].first(id: library_run.run_id)[:producer]
    assert_equal "ogham", @journal[:link_runs].first(id: ogham_run.run_id)[:producer]
    assert_equal 0, ogham_run.superseded_runs, "another producer's run is never clobbered"
    rerun = producer.run("local-library", producer: "ogham")
    assert_equal 1, rerun.superseded_runs, "its OWN prior run is"
  end

  def test_rerun_supersedes_dropped_entries_drop_their_edges
    doc = make_document(urn: "urn:nabu:local-library:slavistics:leskien",
                        related: ["urn:nabu:ccmh:mar:mt", "urn:nabu:ccmh:zog:mt"])
    first = producer.run("local-library")
    assert_equal 2, first.edges_written

    doc.update(metadata_json: JSON.generate({ "collection" => "slavistics",
                                              "related" => ["urn:nabu:ccmh:mar:mt"] }))
    second = producer.run("local-library")
    assert_equal 1, second.edges_written
    assert_equal 1, second.superseded_runs
    assert_equal 2, second.superseded_edges
    assert_equal ["urn:nabu:ccmh:mar:mt"], @journal[:links].select_map(:to_urn),
                 "the dropped manifest entry's edge is gone — the journal holds the CURRENT assertions"
  end

  def test_withdrawn_documents_and_other_sources_contribute_nothing
    make_document(urn: "urn:nabu:local-library:slavistics:gone",
                  related: ["urn:nabu:ccmh:mar:mt"], withdrawn: true)
    other = Nabu::Store::Source.create(slug: "other", name: "O", adapter_class: "X", license_class: "open")
    Nabu::Store::Document.create(
      source_id: other.id, urn: "urn:other:doc", title: "t", language: "und",
      metadata_json: JSON.generate({ "related" => ["urn:nabu:ccmh:mar:mt"] }),
      content_sha256: "x", revision: 1, withdrawn: false
    )
    result = producer.run("local-library")
    assert_equal 0, result.edges_written
    assert_equal 0, @journal[:links].count
  end
end

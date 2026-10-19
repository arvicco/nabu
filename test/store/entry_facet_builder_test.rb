# frozen_string_literal: true

require "test_helper"
require "json"

module Store
  # Nabu::Store::EntryFacetBuilder: the dictionary-entry grain of the facet
  # surface — config/facet_map.yml entry_fields projected from the loaded
  # entries' annotations_json into the dictionary-encoded entry_facet_values
  # / entry_facets pair. The PassageFacetBuilder rules at entry grain:
  # values verbatim, arrays one row per element, {"value", "ref"} objects
  # carry their ref, absence mints nothing; wholesale per source,
  # idempotent, withdrawn entries excluded.
  class EntryFacetBuilderTest < Minitest::Test
    include StoreTestDB

    def setup
      @db = store_test_db
      @edrdg = make_source("edrdg")
      @wold = make_source("wold")
      @dictionaries = {}
      @sequence = 0
    end

    def make_source(slug)
      Nabu::Store::Source.create(slug: slug, name: slug, adapter_class: "T", license_class: "attribution")
    end

    def dictionary(source, slug)
      @dictionaries[slug] ||= Nabu::Store::Dictionary.create(source_id: source.id, slug: slug, title: slug,
                                                             language: "jpn")
    end

    # Brace-less string-keyed annotations arrive through **fields; an
    # explicit nil is an unannotated entry.
    def make_entry(source, annotations = :fields, slug: source.slug, withdrawn: false, **fields)
      annotations = fields if annotations == :fields
      @sequence += 1
      Nabu::Store::DictionaryEntry.create(
        dictionary_id: dictionary(source, slug).id, urn: "urn:nabu:dict:#{slug}:#{@sequence}",
        entry_id: @sequence.to_s, key_raw: "k", headword: "h", headword_folded: "h", body: "b",
        content_sha256: "x", revision: 1, withdrawn: withdrawn,
        annotations_json: annotations && JSON.generate(annotations)
      )
    end

    MAP = Nabu::FacetMap.new("sources" => {
                               "edrdg" => { "entry_fields" => { "field" => "domain", "misc" => "usage" } },
                               "wold" => { "entry_fields" => { "semantic_field" => "semantic_field" } }
                             })

    def pairs_for(entry_id)
      @db[:entry_facets].join(:entry_facet_values, id: :value_id)
                        .where(entry_id: entry_id)
                        .order(:facet, :value)
                        .select_map(%i[facet value ref])
    end

    def test_projects_labels_one_pair_per_distinct_value
      entry = make_entry(@edrdg, "field" => %w[medicine computing medicine], "misc" => "archaic")
      summary = Nabu::Store::EntryFacetBuilder.rebuild!(catalog: @db, facet_map: MAP)

      assert_equal 1, summary.entries
      assert_equal 3, summary.rows
      assert_equal 3, summary.values
      assert_equal([["domain", "computing", nil], ["domain", "medicine", nil], ["usage", "archaic", nil]],
                   pairs_for(entry.id))
    end

    def test_values_are_a_shared_per_source_dictionary
      make_entry(@edrdg, "field" => %w[law Buddhism])
      make_entry(@edrdg, "field" => %w[law])
      make_entry(@wold, "semantic_field" => "The body")
      summary = Nabu::Store::EntryFacetBuilder.rebuild!(catalog: @db, facet_map: MAP)

      assert_equal 4, summary.rows
      assert_equal 3, summary.values, "the repeated label folds to one dictionary row"
      assert_equal 2, @db[:entry_facet_values].where(source_id: @edrdg.id).count
      assert_equal 1, @db[:entry_facet_values].where(source_id: @wold.id).count
    end

    # The TLS shape: a concept name with its uuid as the ref.
    def test_ref_objects_carry_their_ref
      map = Nabu::FacetMap.new("sources" => { "tls" => { "entry_fields" => { "concept" => "concept" } } })
      tls = make_source("tls")
      entry = make_entry(tls, "concept" => [{ "value" => "WORLD", "ref" => "uuid-1" }, { "value" => "SKY" }])
      Nabu::Store::EntryFacetBuilder.rebuild!(catalog: @db, facet_map: map)
      assert_equal([["concept", "SKY", nil], %w[concept WORLD uuid-1]], pairs_for(entry.id))
    end

    def test_unannotated_withdrawn_and_unruled_entries_contribute_nothing
      make_entry(@edrdg, nil)
      make_entry(@edrdg, { "field" => ["law"] }, withdrawn: true)
      make_entry(@edrdg, "pos" => ["noun"])
      make_entry(make_source("lexica"), "field" => ["law"])
      summary = Nabu::Store::EntryFacetBuilder.rebuild!(catalog: @db, facet_map: MAP)
      assert_equal 0, summary.rows
      assert_equal 0, @db[:entry_facet_values].count, "no value without a live pair"
    end

    def test_nil_facet_map_is_lane_off_and_clears_the_tables
      make_entry(@edrdg, "field" => ["law"])
      Nabu::Store::EntryFacetBuilder.rebuild!(catalog: @db, facet_map: MAP)
      summary = Nabu::Store::EntryFacetBuilder.rebuild!(catalog: @db, facet_map: nil)
      assert_equal 0, summary.rows
      assert_equal 0, @db[:entry_facets].count
      assert_equal 0, @db[:entry_facet_values].count
    end

    def test_rebuild_is_idempotent
      make_entry(@edrdg, "field" => %w[law Buddhism])
      Nabu::Store::EntryFacetBuilder.rebuild!(catalog: @db, facet_map: MAP)
      before = [@db[:entry_facets].count, @db[:entry_facet_values].count]
      Nabu::Store::EntryFacetBuilder.rebuild!(catalog: @db, facet_map: MAP)
      assert_equal before, [@db[:entry_facets].count, @db[:entry_facet_values].count]
    end

    # Entries page through in id-keyed batches — the million-entry shelves
    # never land in memory at once; a tiny page proves the walk is whole.
    def test_paged_walk_covers_every_entry
      ids = Array.new(7) { make_entry(@edrdg, "field" => ["f#{_1 % 3}"]).id }
      summary = Nabu::Store::EntryFacetBuilder.rebuild!(catalog: @db, facet_map: MAP, page: 2)
      assert_equal 7, summary.entries
      assert_equal 3, summary.values
      assert_equal ids.sort, @db[:entry_facets].distinct.select_map(:entry_id).sort
    end

    # The per-source seam: a source's slice drops and re-projects, other
    # sources untouched; a source ruled OUT of the config drops its slice.
    def test_refresh_source_is_wholesale_per_source
      make_entry(@edrdg, "field" => ["law"])
      make_entry(@wold, "semantic_field" => "Kinship")
      Nabu::Store::EntryFacetBuilder.rebuild!(catalog: @db, facet_map: MAP)

      make_entry(@edrdg, "field" => ["Buddhism"])
      rows = Nabu::Store::EntryFacetBuilder.refresh_source!(catalog: @db, slug: "edrdg", facet_map: MAP)
      assert_equal 2, rows
      assert_equal 3, @db[:entry_facets].count
      assert_equal 1, @db[:entry_facet_values].where(source_id: @wold.id).count, "wold untouched"

      rows = Nabu::Store::EntryFacetBuilder.refresh_source!(
        catalog: @db, slug: "edrdg", facet_map: Nabu::FacetMap.new("sources" => {})
      )
      assert_equal 0, rows
      assert_equal 0, @db[:entry_facet_values].where(source_id: @edrdg.id).count
      assert_equal 1, @db[:entry_facets].count
    end

    def test_refresh_of_an_unknown_source_is_a_no_op
      assert_equal 0, Nabu::Store::EntryFacetBuilder.refresh_source!(catalog: @db, slug: "nope", facet_map: MAP)
    end
  end
end

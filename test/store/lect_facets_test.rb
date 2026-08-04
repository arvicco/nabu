# frozen_string_literal: true

require "test_helper"

module Store
  # Store::LectFacets (P58-4): the materialized resolution — one
  # document_facets row (facet "lect") per document whose lect resolution
  # differs from its bare stored code (D58-e: identity documents carry no
  # row; "no row" MEANS "resolves to itself", which is what makes the facet
  # the query path). f(catalog, registry, journal) — recomputed wholesale,
  # rebuild-safe by construction.
  class LectFacetsTest < Minitest::Test
    FIXTURES = Nabu::TestSupport.fixtures("nabu-lects")
    LECT_OVERRIDES_PATH = File.join(Nabu::Config::PROJECT_ROOT, "config", "lect_overrides.yml")

    def setup
      @catalog = Nabu::Store.connect("sqlite::memory:")
      Nabu::Store.migrate!(@catalog)
      derom = @catalog[:sources].insert(slug: "derom", name: "D", adapter_class: "X", license_class: "nc")
      plain = @catalog[:sources].insert(slug: "plain", name: "P", adapter_class: "X", license_class: "open")
      @docs = {}
      { ["urn:m:codemap", plain] => "la-med",   # codemap: -> lat:med
        ["urn:m:override", derom] => "la-vul",  # derom override: -> roa:pro
        ["urn:m:identity", plain] => "lat",     # identity: no row
        ["urn:m:journal", plain] => "grc" }.each do |(urn, source_id), language|
        @docs[urn] = @catalog[:documents].insert(source_id: source_id, urn: urn, language: language,
                                                 content_sha256: "x")
      end
    end

    def teardown
      @catalog.disconnect
    end

    def registry(overlay: {})
      Nabu::Lects.load(FIXTURES, overrides_path: LECT_OVERRIDES_PATH, overlay: overlay)
    end

    def lect_rows
      @catalog[:document_facets].where(facet: "lect").order(:document_id)
                                .select_hash(:document_id, :value)
    end

    def test_rebuild_materializes_every_non_identity_resolution_and_only_those
      count = Nabu::Store::LectFacets.rebuild!(catalog: @catalog, registry: registry)
      assert_equal 2, count
      assert_equal({ @docs["urn:m:codemap"] => "lat:med", @docs["urn:m:override"] => "roa:pro" },
                   lect_rows)
    end

    def test_rebuild_carries_the_per_document_overlay_through
      overlay = { "urn:m:journal" => { "grc" => "grc:koi" } }
      Nabu::Store::LectFacets.rebuild!(catalog: @catalog, registry: registry(overlay: overlay))
      assert_equal "grc:koi", lect_rows[@docs["urn:m:journal"]]
    end

    def test_rebuild_replaces_stale_rows_wholesale
      @catalog[:document_facets].insert(document_id: @docs["urn:m:identity"], facet: "lect",
                                        value: "stale:row")
      Nabu::Store::LectFacets.rebuild!(catalog: @catalog, registry: registry)
      refute_includes lect_rows.values, "stale:row"
    end

    def test_rebuild_without_a_registry_drops_all_rows_and_writes_none
      Nabu::Store::LectFacets.rebuild!(catalog: @catalog, registry: registry)
      count = Nabu::Store::LectFacets.rebuild!(catalog: @catalog, registry: nil)
      assert_equal 0, count
      assert_empty lect_rows
    end

    def test_refresh_document_updates_exactly_one_document
      Nabu::Store::LectFacets.rebuild!(catalog: @catalog, registry: registry)
      overlay = { "urn:m:journal" => { "grc" => "grc:koi" } }
      Nabu::Store::LectFacets.refresh_document!(catalog: @catalog, registry: registry(overlay: overlay),
                                                urn: "urn:m:journal")
      rows = lect_rows
      assert_equal "grc:koi", rows[@docs["urn:m:journal"]]
      assert_equal "lat:med", rows[@docs["urn:m:codemap"]], "other documents untouched"

      # And a refresh back to identity REMOVES the row.
      Nabu::Store::LectFacets.refresh_document!(catalog: @catalog, registry: registry,
                                                urn: "urn:m:journal")
      refute_includes lect_rows.keys, @docs["urn:m:journal"]
    end

    def test_materialized_predicate
      refute Nabu::Store::LectFacets.materialized?(@catalog)
      Nabu::Store::LectFacets.rebuild!(catalog: @catalog, registry: registry)
      assert Nabu::Store::LectFacets.materialized?(@catalog)
    end
  end
end

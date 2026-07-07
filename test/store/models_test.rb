# frozen_string_literal: true

require "test_helper"

module Store
  class ModelsTest < Minitest::Test
    include StoreTestDB

    def setup
      @db = store_test_db
    end

    def test_associations_round_trip
      source = Nabu::Store::Source.create(
        slug: "perseus-greek", name: "Perseus Greek", adapter_class: "Nabu::Adapters::Perseus",
        license_class: "open"
      )
      document = Nabu::Store::Document.create(
        source_id: source.id, urn: "urn:cts:greekLit:tlg0012.tlg001",
        content_sha256: "deadbeef"
      )
      passage = Nabu::Store::Passage.create(
        document_id: document.id, urn: "urn:cts:greekLit:tlg0012.tlg001:1.1",
        sequence: 1, text: "μῆνιν", text_normalized: "μηνιν", content_sha256: "cafef00d"
      )
      enrichment = Nabu::Store::Enrichment.create(
        passage_id: passage.id, kind: "machine_gloss", at: Time.now
      )

      # Read back through associations.
      assert_equal [document.id], source.documents.map(&:id)
      assert_equal [passage.id], document.passages.map(&:id)
      assert_equal source.id, document.source.id
      assert_equal document.id, passage.document.id
      assert_equal [enrichment.id], passage.enrichments.map(&:id)
    end

    # P7-1: runs and per-repo pins moved to the history ledger, keyed by slug
    # and (slug, repo_url) — no catalog associations (ids re-mint on rebuild).
    # Their model coverage lives in ledger_test.rb.

    def test_passage_has_many_provenance
      source = Nabu::Store::Source.create(slug: "s", name: "S", adapter_class: "X", license_class: "open")
      document = Nabu::Store::Document.create(source_id: source.id, urn: "urn:doc", content_sha256: "a")
      passage = Nabu::Store::Passage.create(
        document_id: document.id, urn: "urn:p", sequence: 1,
        text: "x", text_normalized: "x", content_sha256: "b"
      )
      prov = Nabu::Store::Provenance.create(passage_id: passage.id, event: "loaded", at: Time.now)

      assert_equal [prov.id], passage.provenance.map(&:id)
      assert_equal passage.id, prov.passage.id
    end

    def test_schema_defaults
      source = Nabu::Store::Source.create(slug: "s", name: "S", adapter_class: "X", license_class: "open")
      document = Nabu::Store::Document.create(source_id: source.id, urn: "urn:doc", content_sha256: "a")

      refute source.enabled
      assert_equal 1, document.revision
      refute document.withdrawn
    end

    def test_fresh_db_per_test_is_isolated
      # A source created here must not leak into other tests' fresh dbs.
      Nabu::Store::Source.create(slug: "only-here", name: "S", adapter_class: "X", license_class: "open")
      assert_equal 1, Nabu::Store::Source.count
    end
  end
end

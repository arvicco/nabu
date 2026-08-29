# frozen_string_literal: true

require "test_helper"

# P87-3 (Q52a) — the fulltext stage stamps: derivation-version tokens per
# heavy stage, minted by the reference rebuild and reconciled surgically
# by the incremental path. A version bump re-derives exactly its own
# stage; unreconcilable stages refuse loudly; a pre-P87 index no-ops with
# an honest note.
module Store
  class StageStampsTest < Minitest::Test
    include StoreTestDB

    def setup
      @catalog = store_test_db
      @fulltext = Nabu::Store.connect_fulltext("sqlite::memory:")
      @source = Nabu::Store::Source.create(
        slug: "s", name: "S", adapter_class: "TestAdapter", license_class: "open"
      )
      doc = Nabu::Store::Document.create(
        source_id: @source.id, urn: "urn:d:1", title: "t", language: "grc",
        content_sha256: "x", revision: 1, withdrawn: false
      )
      Nabu::Store::Passage.create(
        document_id: doc.id, urn: "urn:d:1:1", sequence: 0, language: "grc",
        text: "μῆνιν ἄειδε", text_normalized: "μῆνιν ἄειδε", content_sha256: "x",
        revision: 1, withdrawn: false, annotations_json: "{}"
      )
    end

    def teardown
      @fulltext.disconnect
    end

    def rebuild! = Nabu::Store::Indexer.rebuild!(catalog: @catalog, fulltext: @fulltext)

    def test_the_reference_rebuild_stamps_every_stage_at_current_versions
      rebuild!
      stamps = @fulltext[:stage_stamps].select_hash(:stage, :version)
      assert_equal Nabu::Store::Indexer::STAGE_VERSIONS, stamps
      assert_empty Nabu::Store::Indexer.stale_stages(@fulltext)
    end

    def test_a_version_bump_re_derives_exactly_its_own_stage
      rebuild!
      # Simulate the P86-3 class of change: the index was built under an
      # OLDER char_postings derivation.
      @fulltext[:stage_stamps].where(stage: "char_postings").update(version: "han-only-v0")
      @fulltext[:char_postings].delete

      redone, refusal, note = Nabu::Store::Indexer.reconcile_stages!(
        catalog: @catalog, fulltext: @fulltext
      )
      assert_nil refusal
      assert_nil note
      assert_equal %w[char_postings], redone
      assert_operator @fulltext[:char_postings].exclude(source_id: -1).count, :>, 0,
                      "the stage re-derived against the kept catalog"
      assert_empty Nabu::Store::Indexer.stale_stages(@fulltext), "the stamp advanced"
    end

    def test_an_unreconcilable_stale_stage_refuses_loudly
      rebuild!
      @fulltext[:stage_stamps].where(stage: "fts_lemma").update(version: "v0")
      _redone, refusal, = Nabu::Store::Indexer.reconcile_stages!(
        catalog: @catalog, fulltext: @fulltext
      )
      assert_match(/fts_lemma/, refusal)
      assert_match(/full rebuild is required/, refusal)
    end

    def test_a_pre_p87_index_noops_with_the_honest_note
      redone, refusal, note = Nabu::Store::Indexer.reconcile_stages!(
        catalog: @catalog, fulltext: @fulltext
      )
      assert_empty redone
      assert_nil refusal
      assert_match(/unstamped .pre-P87/, note)
    end

    def test_trust_stages_mints_without_rederiving
      redone, refusal, note = Nabu::Store::Indexer.reconcile_stages!(
        catalog: @catalog, fulltext: @fulltext, trust: true
      )
      assert_empty redone
      assert_nil refusal
      assert_match(/--trust-stages/, note)
      assert_empty Nabu::Store::Indexer.stale_stages(@fulltext)
    end
  end
end

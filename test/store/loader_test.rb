# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"
require "json"

module Store
  class LoaderTest < Minitest::Test
    include StoreTestDB

    FIXTURES = File.expand_path("../fixtures/test_adapter", __dir__)

    # TestAdapter variant whose parse fails for one specific ref — the
    # quarantine path's rig.
    class QuarantiningAdapter < TestAdapter
      def parse(document_ref)
        raise Nabu::ParseError, "deliberately corrupt document" if document_ref.id == "urn:nabu:test_adapter:beta"

        super
      end
    end

    # Fetch-level failures (here: discover) must abort the batch, not
    # quarantine.
    class BrokenDiscoverAdapter < TestAdapter
      def discover(_workdir)
        raise Nabu::FetchError, "upstream listing unavailable"
      end
    end

    # TestAdapter variant whose parse DECLINES one ref by rule (P11-7): a
    # Nabu::DocumentSkipped is not a quarantine — the loader counts it
    # skipped-by-rule and never journals or errors it.
    class SkippingAdapter < TestAdapter
      def parse(document_ref)
        if document_ref.id == "urn:nabu:test_adapter:beta"
          raise Nabu::DocumentSkipped.new("no content", reason: "catalog-only (no content)")
        end

        super
      end
    end

    def setup
      @ledger = ledger_test_db
      @db = store_test_db
      @source = Nabu::Store::Source.create(
        slug: "test_adapter", name: "Conformance Test Adapter",
        adapter_class: "TestAdapter", license_class: "open"
      )
      @loader = Nabu::Store::Loader.new(db: @db, source: @source, ledger: @ledger)
    end

    # -- helpers -------------------------------------------------------------

    # passages: array of [urn_suffix, text] pairs; sequence is the array index.
    def build_document(slug, passages, title: "Document #{slug}", annotations: {}, license_override: nil,
                       metadata: {})
      document = Nabu::Document.new(
        urn: doc_urn(slug), language: "grc", title: title,
        canonical_path: "/canonical/test_adapter/#{slug}.txt", license_override: license_override,
        metadata: metadata
      )
      passages.each_with_index do |(suffix, text), index|
        document << Nabu::Passage.new(
          urn: "#{doc_urn(slug)}:#{suffix}", language: "grc",
          text: text, text_normalized: text.downcase,
          annotations: annotations, sequence: index
        )
      end
      document
    end

    def doc_urn(slug) = "urn:nabu:test:#{slug}"

    def doc_row(slug) = Nabu::Store::Document.first(urn: doc_urn(slug))

    def passage_row(slug, suffix) = Nabu::Store::Passage.first(urn: "#{doc_urn(slug)}:#{suffix}")

    def provenance_events(**filter) = Nabu::Store::Provenance.where(**filter).order(:id).all

    def revisions(**filter)
      dataset = filter.empty? ? Nabu::Store::Revision.dataset : Nabu::Store::Revision.where(**filter)
      dataset.order(:id).all
    end

    def snapshot(model) = model.order(:id).all.map(&:values)

    def alpha(title: "Document alpha")
      build_document("alpha", [%w[1 μῆνιν], %w[2 ἄειδε]], title: title)
    end

    def beta = build_document("beta", [%w[1 ἄνδρα]])

    def assert_report(report, added: 0, updated: 0, skipped: 0, withdrawn: 0, errored: 0,
                      skipped_by_rule: 0, collided: 0, revised: 0)
      # index_delta (P112-1) is a collection, not a count — asserted by the
      # delta tests, excluded from the counts comparison.
      assert_equal(
        { added: added, updated: updated, skipped: skipped, withdrawn: withdrawn,
          errored: errored, skipped_by_rule: skipped_by_rule, collided: collided,
          revised: revised },
        report.to_h.except(:index_delta)
      )
    end

    # The delta's id sets resolved to urn suffix labels ("alpha:1"), so
    # assertions read as content, not row ids.
    def delta_labels(ids)
      ids.to_a.sort.map do |id|
        Nabu::Store::Passage.with_pk!(id).urn.sub("urn:nabu:test:", "")
      end
    end

    # -- insertion -----------------------------------------------------------

    def test_load_adds_new_documents_with_provenance
      report = @loader.load([alpha, beta])

      assert_instance_of Nabu::Store::LoadReport, report
      assert_predicate report, :frozen?
      assert_report report, added: 2

      row = doc_row("alpha")
      assert_equal 1, row.revision
      refute row.withdrawn
      assert_equal @source.id, row.source_id
      assert_equal "Document alpha", row.title
      assert_match(/\A\h{64}\z/, row.content_sha256)

      passage = passage_row("alpha", "1")
      assert_equal 1, passage.revision
      assert_equal 0, passage.sequence
      assert_equal "μῆνιν", passage.text
      assert_match(/\A\h{64}\z/, passage.content_sha256)

      assert_equal 1, provenance_events(document_id: row.id, event: "loaded").size
      # P112-2 (Q113): no per-passage "loaded" breadcrumb — at corpus scale
      # the constant row was 95% of the provenance table; the passage's
      # existence is its own witness, and the document-grain event remains.
      assert_empty provenance_events(passage_id: passage.id, event: "loaded")
      assert_equal 2, Nabu::Store::Provenance.count # the 2 documents only
    end

    # -- idempotency ---------------------------------------------------------

    def test_loading_twice_is_idempotent
      @loader.load([alpha, beta])
      documents_before = snapshot(Nabu::Store::Document)
      passages_before = snapshot(Nabu::Store::Passage)
      provenance_before = snapshot(Nabu::Store::Provenance)

      # Freshly built value objects: idempotency must hold on content equality,
      # not object identity.
      report = @loader.load([alpha, beta])

      assert_report report, skipped: 2
      assert_equal documents_before, snapshot(Nabu::Store::Document)
      assert_equal passages_before, snapshot(Nabu::Store::Passage)
      assert_equal provenance_before, snapshot(Nabu::Store::Provenance)
    end

    def test_annotations_key_order_does_not_change_content_hash
      scrambled = build_document("alpha", [%w[1 μῆνιν]],
                                 annotations: { "b" => { "y" => 2, "x" => 1 }, "a" => [1, "two"] })
      sorted = build_document("alpha", [%w[1 μῆνιν]],
                              annotations: { "a" => [1, "two"], "b" => { "x" => 1, "y" => 2 } })

      @loader.load([scrambled])
      report = @loader.load([sorted])

      assert_report report, skipped: 1
      assert_equal 1, doc_row("alpha").revision
    end

    # -- license override (P10-4) --------------------------------------------
    #
    # A per-document license_override (adapter → Document → documents.license_
    # override) lets one treebank in an nc source be labelled attribution
    # without touching the source class. It is METADATA, never content: it must
    # not enter content_sha256 and relabelling must not bump the revision.

    def test_load_persists_license_override_on_create
      report = @loader.load([build_document("alpha", [%w[1 μῆνιν]], license_override: "attribution")])

      assert_report report, added: 1
      row = doc_row("alpha")
      assert_equal "attribution", row.license_override
      assert_equal 1, row.revision
    end

    def test_no_override_leaves_license_override_null
      @loader.load([alpha])
      assert_nil doc_row("alpha").license_override
    end

    def test_relabel_on_reload_is_metadata_only_no_revision_bump_no_content_change
      @loader.load([alpha])
      row = doc_row("alpha")
      assert_nil row.license_override
      sha_before = row.content_sha256
      passages_before = snapshot(Nabu::Store::Passage)

      # Same content, override newly declared upstream → relabel in place.
      report = @loader.load([alpha.tap { |d| d.instance_variable_set(:@license_override, "attribution") }])

      assert_report report, updated: 1
      row = doc_row("alpha")
      assert_equal "attribution", row.license_override
      assert_equal 1, row.revision, "a license relabel must not bump the revision"
      assert_equal sha_before, row.content_sha256, "a license relabel must not fake a content change"
      assert_equal passages_before, snapshot(Nabu::Store::Passage)
    end

    def test_reload_with_same_override_is_idempotent
      overridden = -> { build_document("alpha", [%w[1 μῆνιν], %w[2 ἄειδε]], license_override: "attribution") }
      @loader.load([overridden.call])
      documents_before = snapshot(Nabu::Store::Document)

      report = @loader.load([overridden.call])

      assert_report report, skipped: 1
      assert_equal documents_before, snapshot(Nabu::Store::Document)
    end

    def test_override_removed_upstream_reverts_to_null_on_next_load
      @loader.load([build_document("alpha", [%w[1 μῆνιν]], license_override: "attribution")])
      assert_equal "attribution", doc_row("alpha").license_override

      report = @loader.load([build_document("alpha", [%w[1 μῆνιν]])]) # override gone from the map

      assert_report report, updated: 1
      row = doc_row("alpha")
      assert_nil row.license_override, "an override removed upstream must revert to NULL"
      assert_equal 1, row.revision
    end

    def test_content_revision_carries_the_current_override
      @loader.load([build_document("alpha", [%w[1 μῆνιν]], license_override: "attribution")])

      # Content changes AND the override is (still) present: the revised row
      # keeps the override.
      report = @loader.load([build_document("alpha", [%w[1 θεά]], license_override: "attribution")])

      assert_report report, updated: 1, revised: 1
      row = doc_row("alpha")
      assert_equal 2, row.revision
      assert_equal "attribution", row.license_override
    end

    # -- document metadata (P17-2) --------------------------------------------
    #
    # Adapter-emitted Document#metadata (persons prosopography, crosswalk ids,
    # facets — edh-survey §4.5/§4.6) persists into documents.metadata_json.
    # Same discipline as license_override: METADATA, never content — it stays
    # out of content_sha256, and a metadata-only change reconciles in place
    # without a revision bump.

    def test_load_persists_document_metadata_on_create
      metadata = { "tm_nr" => "251193", "persons" => [{ "nomen" => "Nonia" }] }
      report = @loader.load([build_document("alpha", [%w[1 μῆνιν]], metadata: metadata)])

      assert_report report, added: 1
      row = doc_row("alpha")
      assert_equal metadata, JSON.parse(row.metadata_json)
      assert_equal 1, row.revision
    end

    def test_empty_metadata_stores_the_empty_object
      @loader.load([alpha])
      assert_equal "{}", doc_row("alpha").metadata_json
    end

    def test_metadata_change_is_metadata_only_no_revision_bump_no_content_change
      @loader.load([alpha])
      sha_before = doc_row("alpha").content_sha256

      report = @loader.load([build_document("alpha", [%w[1 μῆνιν], %w[2 ἄειδε]], metadata: { "tm_nr" => "9" })])

      assert_report report, updated: 1
      row = doc_row("alpha")
      assert_equal({ "tm_nr" => "9" }, JSON.parse(row.metadata_json))
      assert_equal 1, row.revision, "a metadata change must not bump the revision"
      assert_equal sha_before, row.content_sha256, "metadata must never fake a content change"
    end

    # -- the revised counter (P110-1, the P109-5 FTS-storm root fix) ---------

    # `revised` counts only documents whose PASSAGE-VISIBLE state changed
    # (content sha revisions and restores); metadata/license/retirement
    # reconciles stay outside it, so a metadata-only re-parse of a big
    # source can skip the whole-slice FTS rewrite (`passages_changed?`).

    def test_metadata_only_update_implies_no_passage_change
      @loader.load([alpha])

      report = @loader.load([build_document("alpha", [%w[1 μῆνιν], %w[2 ἄειδε]],
                                            metadata: { "bu" => "史部" })])

      assert_report report, updated: 1
      refute report.passages_changed?, "a metadata-only reconcile must not demand a reindex"
    end

    def test_content_revision_counts_revised_and_passages_changed
      @loader.load([alpha])

      report = @loader.load([build_document("alpha", [%w[1 μῆνιν], %w[2 θεά]])])

      assert_report report, updated: 1, revised: 1
      assert report.passages_changed?
    end

    def test_idempotent_reload_implies_no_passage_change
      @loader.load([alpha])

      report = @loader.load([alpha])

      assert_report report, skipped: 1
      refute report.passages_changed?
    end

    def test_withdrawal_implies_passages_changed
      @loader.load([alpha, beta])

      report = @loader.load([alpha], full: true)

      assert_equal 1, report.withdrawn
      assert report.passages_changed?, "a withdrawal removes rows from the live set"
    end

    def test_load_report_sum_carries_revised
      a = Nabu::Store::LoadReport.new(added: 1, updated: 2, skipped: 0, withdrawn: 0, errored: 0, revised: 2)
      b = Nabu::Store::LoadReport.new(added: 0, updated: 1, skipped: 3, withdrawn: 0, errored: 0, revised: 1)

      assert_equal 3, (a + b).revised
    end

    def test_reload_with_same_metadata_is_idempotent
      with_metadata = -> { build_document("alpha", [%w[1 μῆνιν]], metadata: { "tm_nr" => "9" }) }
      @loader.load([with_metadata.call])
      documents_before = snapshot(Nabu::Store::Document)

      report = @loader.load([with_metadata.call])

      assert_report report, skipped: 1
      assert_equal documents_before, snapshot(Nabu::Store::Document)
    end

    def test_content_revision_carries_the_current_metadata
      @loader.load([build_document("alpha", [%w[1 μῆνιν]], metadata: { "tm_nr" => "9" })])

      report = @loader.load([build_document("alpha", [%w[1 θεά]], metadata: { "tm_nr" => "10" })])

      assert_report report, updated: 1, revised: 1
      row = doc_row("alpha")
      assert_equal 2, row.revision
      assert_equal({ "tm_nr" => "10" }, JSON.parse(row.metadata_json))
    end

    def test_invalid_license_override_is_rejected_before_any_write
      error = assert_raises(Nabu::ValidationError) do
        Nabu::Document.new(urn: doc_urn("x"), language: "grc",
                           canonical_path: "/c/x.txt", license_override: "totally-free")
      end
      assert_match(/license_class/, error.message)
    end

    # -- revisions -----------------------------------------------------------

    def test_changed_passage_bumps_revisions_and_journals_old_sha
      @loader.load([alpha, beta])
      old_doc_sha = doc_row("alpha").content_sha256
      old_passage_sha = passage_row("alpha", "2").content_sha256
      untouched_passage = passage_row("alpha", "1").values

      changed = build_document("alpha", [%w[1 μῆνιν], %w[2 θεά]])
      report = @loader.load([changed, beta])

      assert_report report, updated: 1, skipped: 1, revised: 1

      row = doc_row("alpha")
      assert_equal 2, row.revision
      refute_equal old_doc_sha, row.content_sha256

      passage = passage_row("alpha", "2")
      assert_equal 2, passage.revision
      assert_equal "θεά", passage.text
      refute_equal old_passage_sha, passage.content_sha256

      # The unchanged sibling passage is byte-identical, revision untouched.
      assert_equal untouched_passage, passage_row("alpha", "1").values

      doc_event = provenance_events(document_id: row.id, event: "revised").last
      assert_equal({ "old_sha" => old_doc_sha, "new_sha" => row.content_sha256 },
                   JSON.parse(doc_event.params_json))
      passage_event = provenance_events(passage_id: passage.id, event: "revised").last
      assert_equal({ "old_sha" => old_passage_sha, "new_sha" => passage.content_sha256 },
                   JSON.parse(passage_event.params_json))
    end

    def test_document_field_change_alone_counts_as_updated
      @loader.load([alpha])
      passages_before = snapshot(Nabu::Store::Passage)

      report = @loader.load([alpha(title: "Document alpha, corrected")])

      assert_report report, updated: 1, revised: 1
      row = doc_row("alpha")
      assert_equal 2, row.revision
      assert_equal "Document alpha, corrected", row.title
      assert_equal passages_before, snapshot(Nabu::Store::Passage)
    end

    def test_sequence_reorder_is_a_safe_revision
      @loader.load([alpha])

      swapped = build_document("alpha", [%w[2 ἄειδε], %w[1 μῆνιν]])
      report = @loader.load([swapped])

      assert_report report, updated: 1, revised: 1
      assert_equal 0, passage_row("alpha", "2").sequence
      assert_equal 1, passage_row("alpha", "1").sequence
      assert_equal [2, 2], [passage_row("alpha", "1").revision, passage_row("alpha", "2").revision]
    end

    # -- within-pass collision (P39-4) ---------------------------------------

    # The discriminator these tests pin: DIFFERENT content under one urn is a
    # legitimate revision ACROSS runs (test above) but a COLLISION within a
    # single pass — two canonical files claiming one urn, which must be
    # deterministic keep-first, never silent last-writer-wins.
    def collides_with_alpha
      build_document("alpha", [%w[1 μῆνιν], %w[2 θεά]]) # alpha's passage 2 is ἄειδε
    end

    def test_within_pass_collision_keeps_first_and_flags_loudly
      report = @loader.load([alpha, collides_with_alpha, beta])

      assert_report report, added: 2, collided: 1

      # The FIRST file's content is kept: no revision, no last-writer overwrite.
      row = doc_row("alpha")
      assert_equal 1, row.revision
      assert_equal "ἄειδε", passage_row("alpha", "2").text
      assert_equal 1, passage_row("alpha", "2").revision

      # Loud: a "collision" provenance breadcrumb naming both shas, and no
      # spurious "revised" event for the kept document.
      collision = provenance_events(event: "collision").last
      refute_nil collision, "the rejected duplicate is journaled loudly"
      params = JSON.parse(collision.params_json)
      assert_equal doc_urn("alpha"), params.fetch("urn")
      assert_equal row.content_sha256, params.fetch("kept_sha")
      refute_equal params.fetch("kept_sha"), params.fetch("rejected_sha")
      assert_empty provenance_events(document_id: row.id, event: "revised"),
                   "a collision never bumps the kept document's revision"
    end

    def test_within_pass_identical_duplicate_is_an_idempotent_skip
      report = @loader.load([alpha, alpha, beta])

      assert_report report, added: 2, skipped: 1
      assert_equal 1, doc_row("alpha").revision
      assert_empty provenance_events(event: "collision"),
                   "a byte-identical in-pass duplicate is harmless, not a collision"
    end

    # THE LINE, held from the other side: the same different-content document,
    # loaded in a SEPARATE pass, is a normal revision — the collision seam only
    # fires within one pass, so legitimate upstream updates still revise.
    def test_across_run_revision_is_untouched_by_the_collision_seam
      @loader.load([alpha])
      report = @loader.load([collides_with_alpha])

      assert_report report, updated: 1, revised: 1
      assert_equal 2, doc_row("alpha").revision
      assert_equal "θεά", passage_row("alpha", "2").text
      assert_empty provenance_events(event: "collision")
    end

    # The owner's incident path: `nabu rebuild` loads in tx_batch mode, so the
    # collision seam must hold when both colliding files land in one batch
    # transaction (the earlier savepoint's insert is visible to the later one).
    def test_collision_seam_holds_in_batch_mode
      batched = Nabu::Store::Loader.new(db: @db, source: @source, ledger: @ledger, tx_batch: 10)
      report = batched.load([alpha, collides_with_alpha])

      assert_report report, added: 1, collided: 1
      assert_equal 1, doc_row("alpha").revision
      assert_equal "ἄειδε", passage_row("alpha", "2").text
    end

    # -- withdrawal ----------------------------------------------------------

    def test_full_load_withdraws_absent_documents
      @loader.load([alpha, beta])
      beta_revision = doc_row("beta").revision

      report = @loader.load([alpha], full: true)

      assert_report report, skipped: 1, withdrawn: 1
      row = doc_row("beta")
      assert row.withdrawn
      assert_equal beta_revision, row.revision # withdrawal is not a revision
      # P93-2 (№R-16): the sweep stamps WHY and WHEN — both on the catalog
      # row and on the durable ledger event (the record that survives
      # rebuild).
      assert_equal "upstream-gone", row.withdrawn_reason
      refute_nil row.withdrawn_at
      assert_equal "upstream-gone",
                   revisions(urn: row.urn, event: "withdrawn").first.reason
      assert_equal 1, provenance_events(document_id: row.id, event: "withdrawn").size
      # Document-level withdrawal does not touch the passages.
      refute passage_row("beta", "1").withdrawn

      # Already-withdrawn documents stay withdrawn silently: no second event.
      report = @loader.load([alpha], full: true)
      assert_report report, skipped: 1
      assert_equal 1, provenance_events(document_id: row.id, event: "withdrawn").size
    end

    def test_partial_load_never_withdraws
      @loader.load([alpha, beta])

      report = @loader.load([alpha], full: false)

      assert_report report, skipped: 1
      refute doc_row("beta").withdrawn
      assert_empty provenance_events(event: "withdrawn")
    end

    def test_withdrawn_document_reappearing_is_restored
      @loader.load([alpha, beta])
      @loader.load([alpha], full: true)

      report = @loader.load([alpha, beta])

      assert_report report, skipped: 1, updated: 1, revised: 1
      row = doc_row("beta")
      refute row.withdrawn
      assert_nil row.withdrawn_reason, "a restore clears the reason (P93-2)"
      assert_nil row.withdrawn_at
      assert_equal 1, row.revision # content unchanged: restore is not a revision
      assert_equal 1, provenance_events(document_id: row.id, event: "restored").size
      assert_empty provenance_events(document_id: row.id, event: "revised")
    end

    def test_withdrawn_document_reappearing_changed_is_restored_and_revised
      @loader.load([alpha, beta])
      @loader.load([alpha], full: true)

      changed_beta = build_document("beta", [%w[1 πολύτροπον]])
      report = @loader.load([alpha, changed_beta])

      assert_report report, skipped: 1, updated: 1, revised: 1
      row = doc_row("beta")
      refute row.withdrawn
      assert_equal 2, row.revision
      assert_equal 1, provenance_events(document_id: row.id, event: "restored").size
      assert_equal 1, provenance_events(document_id: row.id, event: "revised").size
    end

    def test_passage_withdrawal_and_restoration_within_revised_document
      wide = build_document("alpha", [%w[1 μῆνιν], %w[2 ἄειδε], %w[3 θεά]])
      @loader.load([wide])

      # Passage 2 vanishes from the new parse; 3 shifts up a sequence slot.
      narrow = build_document("alpha", [%w[1 μῆνιν], %w[3 θεά]])
      report = @loader.load([narrow])

      assert_report report, updated: 1, revised: 1
      vanished = passage_row("alpha", "2")
      assert vanished.withdrawn
      assert_equal 1, vanished.revision
      assert_equal 1, provenance_events(passage_id: vanished.id, event: "withdrawn").size
      # P93-2: a passage withdrawal is definitionally revision pruning —
      # the durable event says so (no catalog column at passage grain).
      assert_equal "revision-pruned",
                   revisions(urn: vanished.urn, event: "withdrawn").first.reason
      assert_equal 1, passage_row("alpha", "3").sequence

      # Idempotency after passage withdrawal: same load again is a full skip.
      report = @loader.load([build_document("alpha", [%w[1 μῆνιν], %w[3 θεά]])])
      assert_report report, skipped: 1
      assert_equal 1, provenance_events(passage_id: vanished.id, event: "withdrawn").size

      # The passage reappears with identical content: restored, no bump —
      # but the DOCUMENT sha changes (its passage-hash sequence regrew), so
      # the load is content-bearing for the index (revised).
      report = @loader.load([build_document("alpha", [%w[1 μῆνιν], %w[2 ἄειδε], %w[3 θεά]])])
      assert_report report, updated: 1, revised: 1
      restored = passage_row("alpha", "2")
      refute restored.withdrawn
      assert_equal 1, restored.revision
      assert_equal 1, provenance_events(passage_id: restored.id, event: "restored").size
    end

    # -- quarantine / error isolation ----------------------------------------

    def test_parse_error_quarantines_document_and_batch_continues
      report = @loader.load_from(QuarantiningAdapter.new, workdir: FIXTURES)

      assert_report report, added: 2, errored: 1
      refute_nil Nabu::Store::Document.first(urn: "urn:nabu:test_adapter:alpha")
      refute_nil Nabu::Store::Document.first(urn: "urn:nabu:test_adapter:gamma")
      assert_nil Nabu::Store::Document.first(urn: "urn:nabu:test_adapter:beta")

      events = provenance_events(event: "quarantined")
      assert_equal 1, events.size
      params = JSON.parse(events.first.params_json)
      assert_equal "urn:nabu:test_adapter:beta", params.fetch("ref_id")
      assert_equal "deliberately corrupt document", params.fetch("error")
    end

    # -- skipped-by-rule (P11-7 fix 3) ---------------------------------------

    def test_document_skipped_is_counted_by_rule_not_quarantined
      report = @loader.load_from(SkippingAdapter.new, workdir: FIXTURES)

      # alpha + gamma load; beta is a by-rule skip, NOT an error/quarantine.
      assert_report report, added: 2, skipped_by_rule: 1
      assert_equal 0, report.errored
      assert_nil Nabu::Store::Document.first(urn: "urn:nabu:test_adapter:beta")
      # a by-rule skip journals nothing (the 0-byte stance) — no quarantine row.
      assert_empty provenance_events(event: "quarantined")
    end

    # P37-r2 — the KR5-wave incident: a held document whose files STOP
    # parsing (a stricter parser, upstream corruption) quarantines loudly,
    # but must NEVER be withdrawn by the full-sync sweep — the text is still
    # present upstream; recognition failed, not the text. The held revision
    # stays served untouched.
    def test_quarantined_ref_shields_its_held_row_from_the_withdrawal_sweep
      @loader.load_from(TestAdapter.new, workdir: FIXTURES)
      row = Nabu::Store::Document.first(urn: "urn:nabu:test_adapter:beta")
      held_revision = row.revision
      held_sha = row.content_sha256

      report = @loader.load_from(QuarantiningAdapter.new, workdir: FIXTURES, full: true)

      assert_equal 1, report.errored
      assert_equal 0, report.withdrawn, "a quarantined ref is present upstream — never withdrawn"
      row.refresh
      refute row.withdrawn, "quarantine must not withdraw the held document"
      assert_equal held_revision, row.revision, "quarantine must not touch the held revision"
      assert_equal held_sha, row.content_sha256, "quarantine must not touch the held content"
      assert_empty provenance_events(event: "withdrawn")
      # The quarantine itself is journaled loudly, as before.
      assert_equal 1, provenance_events(event: "quarantined").size
    end

    def test_skipped_ref_shields_its_row_from_the_withdrawal_sweep
      # Load beta as a real document first (via the plain adapter), then a full
      # load where beta is skipped-by-rule must NOT withdraw the existing row.
      @loader.load_from(TestAdapter.new, workdir: FIXTURES)
      report = @loader.load_from(SkippingAdapter.new, workdir: FIXTURES, full: true)

      assert_equal 0, report.withdrawn, "a skipped ref is present upstream — never withdrawn"
      assert_equal 1, report.skipped_by_rule
    end

    # -- progress ticks (P2-6) -----------------------------------------------

    def test_on_document_ticks_once_per_document_with_running_counts
      ticks = []
      report = @loader.load([alpha, beta], on_document: ->(processed, errored) { ticks << [processed, errored] })

      assert_report report, added: 2
      assert_equal [[1, 0], [2, 0]], ticks
    end

    def test_on_document_ticks_for_quarantined_documents_too
      # QuarantiningAdapter's fixture dir has alpha, beta, gamma; beta quarantines.
      ticks = []
      report = @loader.load_from(QuarantiningAdapter.new, workdir: FIXTURES,
                                                          on_document: ->(p, e) { ticks << [p, e] })

      assert_report report, added: 2, errored: 1
      # alpha loads (errored 0), beta quarantines (errored ticks to 1), gamma
      # loads (running errored stays 1) — one tick per document, quarantines
      # included, errored count cumulative.
      assert_equal [[1, 0], [2, 1], [3, 1]], ticks
    end

    def test_on_document_is_optional_and_nil_is_a_no_op
      report = @loader.load([alpha, beta]) # no on_document
      assert_report report, added: 2
    end

    def test_load_from_is_idempotent_through_the_adapter
      @loader.load_from(TestAdapter.new, workdir: FIXTURES)
      documents_before = snapshot(Nabu::Store::Document)
      passages_before = snapshot(Nabu::Store::Passage)

      report = @loader.load_from(TestAdapter.new, workdir: FIXTURES)

      assert_report report, skipped: 3
      assert_equal documents_before, snapshot(Nabu::Store::Document)
      assert_equal passages_before, snapshot(Nabu::Store::Passage)
    end

    def test_fetch_level_errors_propagate_and_abort
      assert_raises(Nabu::FetchError) do
        @loader.load_from(BrokenDiscoverAdapter.new, workdir: FIXTURES)
      end
      assert_equal 0, Nabu::Store::Document.count
    end

    # -- retention: the canonical attic (P5-2) -------------------------------

    def write(workdir, relpath, content)
      path = File.join(workdir, relpath)
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, content)
    end

    # A tmp TestAdapter workdir with one live doc and one attic doc.
    def with_retention_workdir
      Dir.mktmpdir do |workdir|
        write(workdir, "alpha.txt", "Alpha\nμῆνιν\n")
        write(workdir, ".attic/ghost.txt", "Ghost\nεἴδωλον\n")
        write(workdir, ".attic/.attic.json", JSON.generate("ghost.txt" => "cafe1234"))
        yield workdir
      end
    end

    def ghost_row = Nabu::Store::Document.first(urn: "urn:nabu:test_adapter:ghost")

    def test_attic_document_loads_live_with_retired_flag_and_provenance
      with_retention_workdir do |workdir|
        report = @loader.load_from(TestAdapter.new, workdir: workdir)

        assert_report report, added: 2
        row = ghost_row
        assert row.retired_upstream
        refute row.withdrawn, "retired is not withdrawn: the document stays live"
        assert_includes row.canonical_path, "/.attic/"
        refute Nabu::Store::Passage.first(urn: "urn:nabu:test_adapter:ghost:1").withdrawn
        events = provenance_events(document_id: row.id, event: "retired")
        assert_equal 1, events.size
        assert_equal({ "upstream_sha" => "cafe1234" }, JSON.parse(events.first.params_json))

        # Idempotent: a second identical load writes nothing.
        provenance_before = snapshot(Nabu::Store::Provenance)
        assert_report @loader.load_from(TestAdapter.new, workdir: workdir), skipped: 2
        assert_equal provenance_before, snapshot(Nabu::Store::Provenance)
        assert ghost_row.retired_upstream
      end
    end

    def test_live_document_moving_to_the_attic_is_retired_not_withdrawn
      Dir.mktmpdir do |workdir|
        write(workdir, "alpha.txt", "Alpha\nμῆνιν\n")
        write(workdir, "ghost.txt", "Ghost\nεἴδωλον\n")
        @loader.load_from(TestAdapter.new, workdir: workdir)
        refute ghost_row.retired_upstream

        # Upstream scraps ghost.txt; the fetch layer atticked it.
        FileUtils.mkdir_p(File.join(workdir, ".attic"))
        FileUtils.mv(File.join(workdir, "ghost.txt"), File.join(workdir, ".attic", "ghost.txt"))
        report = @loader.load_from(TestAdapter.new, workdir: workdir, full: true)

        # canonical_path moved into the attic → a revision, plus retirement.
        assert_report report, updated: 1, skipped: 1, revised: 1
        row = ghost_row
        assert row.retired_upstream
        refute row.withdrawn
        assert_equal 2, row.revision
        assert_equal 1, provenance_events(document_id: row.id, event: "retired").size
        # No sha available without an attic manifest: journaled without params.
        assert_nil provenance_events(document_id: row.id, event: "retired").first.params_json
        assert_empty provenance_events(event: "withdrawn")
      end
    end

    def test_retired_document_reappearing_live_is_unretired_and_attic_copy_superseded
      with_retention_workdir do |workdir|
        @loader.load_from(TestAdapter.new, workdir: workdir)
        assert ghost_row.retired_upstream

        # Upstream restores the document; the attic copy stays (first copy wins).
        # The attic→live move changes canonical_path, which is in the doc sha,
        # so the unretirement rides a content revision (revised: 1).
        write(workdir, "ghost.txt", "Ghost\nεἴδωλον\n")
        report = @loader.load_from(TestAdapter.new, workdir: workdir)

        assert_report report, updated: 1, skipped: 1, revised: 1
        row = ghost_row
        refute row.retired_upstream, "a urn discovered live again flips back"
        refute row.withdrawn
        assert_equal 1, provenance_events(document_id: row.id, event: "unretired").size
        superseded = provenance_events(document_id: row.id, event: "superseded")
        assert_equal 1, superseded.size
        assert_includes JSON.parse(superseded.first.params_json).fetch("attic_path"), "/.attic/"

        # Steady state stays silent: no superseded/unretired spam per load.
        assert_report @loader.load_from(TestAdapter.new, workdir: workdir), skipped: 2
        assert_equal 1, provenance_events(document_id: row.id, event: "superseded").size
        assert_equal 1, provenance_events(document_id: row.id, event: "unretired").size
      end
    end

    def test_plain_document_loads_never_retire
      @loader.load([alpha])
      refute doc_row("alpha").retired_upstream
    end

    # -- the durable revisions ledger (P7-1) ----------------------------------
    #
    # Catalog provenance is derived-run journaling: it resets with the catalog
    # on rebuild. Content TRANSITIONS of existing rows additionally land in the
    # ledger's urn-keyed revisions table, which survives rebuilds. Fresh
    # inserts (including every rebuild replay, which only inserts into a fresh
    # catalog) write NOTHING durable — so a rebuild leaves the ledger intact
    # and un-spammed.

    def test_fresh_inserts_write_no_durable_revisions
      @loader.load([alpha, beta])
      assert_empty revisions, "loaded is per-load noise; only transitions go durable"
    end

    def test_idempotent_reload_writes_no_durable_revisions
      @loader.load([alpha, beta])
      @loader.load([alpha, beta])
      assert_empty revisions
    end

    def test_revised_content_journals_durable_revisions_by_urn
      @loader.load([alpha])
      old_doc_sha = doc_row("alpha").content_sha256
      old_passage_sha = passage_row("alpha", "2").content_sha256

      @loader.load([build_document("alpha", [%w[1 μῆνιν], %w[2 θεά]])])

      doc_rev = revisions(urn: doc_urn("alpha"), event: "revised").last
      assert_equal old_doc_sha, doc_rev.old_sha
      assert_equal doc_row("alpha").content_sha256, doc_rev.new_sha
      refute_nil doc_rev.at

      passage_rev = revisions(urn: "#{doc_urn('alpha')}:2", event: "revised").last
      assert_equal old_passage_sha, passage_rev.old_sha
      assert_equal passage_row("alpha", "2").content_sha256, passage_rev.new_sha
      assert_empty revisions(urn: "#{doc_urn('alpha')}:1"), "the unchanged sibling stays silent"
    end

    def test_withdrawal_and_restore_transitions_are_durable
      @loader.load([alpha, beta])
      beta_sha = doc_row("beta").content_sha256

      @loader.load([alpha], full: true) # beta withdrawn
      withdrawn = revisions(urn: doc_urn("beta"), event: "withdrawn")
      assert_equal 1, withdrawn.size
      assert_equal beta_sha, withdrawn.first.old_sha

      @loader.load([alpha], full: true) # already withdrawn: silent
      assert_equal 1, revisions(urn: doc_urn("beta"), event: "withdrawn").size

      @loader.load([alpha, beta]) # beta reappears unchanged: restored
      restored = revisions(urn: doc_urn("beta"), event: "restored")
      assert_equal 1, restored.size
      assert_equal beta_sha, restored.first.new_sha
    end

    def test_passage_withdrawal_within_a_revised_document_is_durable
      @loader.load([build_document("alpha", [%w[1 μῆνιν], %w[2 ἄειδε], %w[3 θεά]])])
      vanished_sha = passage_row("alpha", "2").content_sha256

      @loader.load([build_document("alpha", [%w[1 μῆνιν], %w[3 θεά]])])

      withdrawn = revisions(urn: "#{doc_urn('alpha')}:2", event: "withdrawn")
      assert_equal 1, withdrawn.size
      assert_equal vanished_sha, withdrawn.first.old_sha
    end

    def test_retirement_transitions_are_durable_but_attic_inserts_are_not
      with_retention_workdir do |workdir|
        @loader.load_from(TestAdapter.new, workdir: workdir)
        # ghost was INSERTED retired (the rebuild-replay shape): not a
        # transition, nothing durable.
        assert_empty revisions(urn: "urn:nabu:test_adapter:ghost", event: "retired")

        # Upstream restores it live: unretired IS a transition.
        write(workdir, "ghost.txt", "Ghost\nεἴδωλον\n")
        @loader.load_from(TestAdapter.new, workdir: workdir)
        assert_equal 1, revisions(urn: "urn:nabu:test_adapter:ghost", event: "unretired").size

        # And scrapping it again journals a durable retirement.
        FileUtils.rm(File.join(workdir, "ghost.txt"))
        @loader.load_from(TestAdapter.new, workdir: workdir, full: true)
        assert_equal 1, revisions(urn: "urn:nabu:test_adapter:ghost", event: "retired").size
      end
    end

    def test_loader_without_a_ledger_journals_catalog_provenance_only
      loader = Nabu::Store::Loader.new(db: @db, source: @source, ledger: nil)
      loader.load([alpha])
      loader.load([build_document("alpha", [%w[1 μῆνιν], %w[2 θεά]])])

      assert_equal 2, doc_row("alpha").revision
      assert_empty revisions
    end

    def test_constraint_violation_is_isolated_per_document
      good = alpha
      # Shares a passage urn with alpha: violates the passages.urn unique index.
      clash = Nabu::Document.new(
        urn: doc_urn("clash"), language: "grc", title: "Clash",
        canonical_path: "/canonical/test_adapter/clash.txt"
      )
      clash << Nabu::Passage.new(
        urn: "#{doc_urn('alpha')}:1", language: "grc",
        text: "δόλος", text_normalized: "δόλος", sequence: 0
      )

      report = @loader.load([good, clash, beta])

      assert_report report, added: 2, errored: 1
      assert_nil doc_row("clash") # rolled back whole, not half-written
      refute_nil doc_row("beta") # the batch continued
      events = provenance_events(event: "quarantined")
      assert_equal 1, events.size
      params = JSON.parse(events.first.params_json)
      assert_equal doc_urn("clash"), params.fetch("urn")
    end

    # -- rebuild batch transactions (P36-2) ----------------------------------

    # tx_batch (rebuild only) collapses many per-document transactions into one
    # per batch; the persisted result must be identical to the per-document
    # path. A batch of 2 forces a mid-stream flush (alpha, beta) then a trailing
    # flush (a lone third) — every boundary exercised.
    def test_tx_batch_persists_identically_to_per_document
      batched = Nabu::Store::Loader.new(db: @db, source: @source, ledger: @ledger, tx_batch: 2)
      report = batched.load([alpha, beta, build_document("gamma", [%w[1 πόλις]])])

      assert_report report, added: 3
      assert_equal 1, doc_row("alpha").revision
      assert_equal 1, doc_row("gamma").revision
      assert_equal "μῆνιν", passage_row("alpha", "1").text
      # 3 documents journaled "loaded" (P112-2: passages never are), exactly
      # as per-document.
      assert_equal 3, Nabu::Store::Provenance.count
    end

    # A savepoint per document means a constraint violation still rolls back
    # ONLY itself inside a shared batch transaction — its siblings, committed
    # together in the same transaction, survive (the per-document isolation the
    # sync path gets from a top-level transaction). tx_batch 10 holds all three
    # in one transaction, so only the savepoint can save the siblings.
    def test_tx_batch_isolates_a_constraint_violation_via_savepoint
      batched = Nabu::Store::Loader.new(db: @db, source: @source, ledger: @ledger, tx_batch: 10)
      clash = Nabu::Document.new(
        urn: doc_urn("clash"), language: "grc", title: "Clash",
        canonical_path: "/canonical/test_adapter/clash.txt"
      )
      clash << Nabu::Passage.new(
        urn: "#{doc_urn('alpha')}:1", language: "grc",
        text: "δόλος", text_normalized: "δόλος", sequence: 0
      )

      report = batched.load([alpha, clash, beta])

      assert_report report, added: 2, errored: 1
      assert_nil doc_row("clash")   # savepoint rolled back just this document
      refute_nil doc_row("alpha")   # committed with the batch
      refute_nil doc_row("beta")    # committed with the batch
      assert_equal 1, provenance_events(event: "quarantined").size
    end

    # The batch grain is row-aware (P37-7): tx_batch caps DOCUMENTS per
    # transaction, tx_batch_rows caps buffered PASSAGE rows — whichever fills
    # first flushes. Mega-document sources (kanripo/cbeta shape: thousands of
    # passages per document) otherwise pile GBs into one transaction, and the
    # per-document savepoints' statement journal — held in RAM under the
    # rebuild pragmas' temp_store=MEMORY — grows with the whole transaction
    # (the measured P36-2 mega-source load regression). Transaction boundaries
    # are observed via the SQL log: each flush is one COMMIT.
    def test_tx_batch_rows_caps_buffered_passages_per_transaction
      io = StringIO.new
      @db.loggers << Logger.new(io)
      batched = Nabu::Store::Loader.new(db: @db, source: @source, ledger: @ledger,
                                        tx_batch: 10, tx_batch_rows: 3)
      # Four 2-passage documents, cumulative rows 2/4/2/4: the row cap (3)
      # flushes after delta and after zeta; the doc cap (10) never fills.
      report = batched.load(
        [build_document("gamma", [%w[1 πόλις], %w[2 θεός]]),
         build_document("delta", [%w[1 λόγος], %w[2 μῦθος]]),
         build_document("epsilon", [%w[1 ἔργον], %w[2 νόμος]]),
         build_document("zeta", [%w[1 δῆμος], %w[2 ξένος]])]
      )
      @db.loggers.clear

      assert_report report, added: 4
      # 2 row-capped batch flushes + the withdrawal sweep = 3 transactions.
      commits = io.string.lines.count { |line| line.include?("COMMIT") }

      assert_equal 3, commits
      # Persisted result identical to any other grain: 4 docs journaled
      # (P112-2: passages never are).
      assert_equal 4, Nabu::Store::Provenance.count
    end

    # The P2-6 progress contract survives batching: one running-count tick per
    # document, in input order, ticked only AFTER the document actually lands.
    def test_tx_batch_ticks_once_per_document_in_order
      batched = Nabu::Store::Loader.new(db: @db, source: @source, ledger: @ledger, tx_batch: 2)
      ticks = []
      batched.load([alpha, beta, build_document("gamma", [%w[1 πόλις]])],
                   on_document: ->(processed, errored) { ticks << [processed, errored] })

      assert_equal [[1, 0], [2, 0], [3, 0]], ticks
    end

    # -- the index delta (P112-1, Q112) --------------------------------------
    # The loader emits the changed passage id/urn sets on the LoadReport so
    # the indexer can refresh exactly what changed instead of the whole
    # slice. The sets must cover every row that moved in or out of the LIVE
    # passage set — and nothing else.

    def test_first_load_delta_upserts_every_passage
      report = @loader.load([alpha, beta])
      delta = report.index_delta

      refute_nil delta
      refute_predicate delta, :overflowed?
      assert_equal %w[alpha:1 alpha:2 beta:1], delta_labels(delta.upserted_ids)
      assert_empty delta.removed_ids
      assert_equal 3, delta.upserted_urns.size
    end

    def test_idempotent_reload_delta_is_empty
      @loader.load([alpha, beta])
      report = fresh_loader.load([alpha, beta])

      assert_predicate report.index_delta, :empty?
    end

    def test_revision_delta_carries_only_the_changed_passage
      @loader.load([alpha])
      report = fresh_loader.load([collides_with_alpha]) # alpha with passage 2 reworded

      delta = report.index_delta

      assert_equal %w[alpha:2], delta_labels(delta.upserted_ids),
                   "the unchanged sibling passage must stay out of the delta"
      assert_empty delta.removed_ids
    end

    def test_passage_withdrawal_delta_reports_removed
      @loader.load([alpha])
      shrunk = build_document("alpha", [%w[1 μῆνιν]]) # passage 2 vanished
      report = fresh_loader.load([shrunk])

      delta = report.index_delta

      assert_equal %w[alpha:2], delta_labels(delta.removed_ids)
      assert_empty delta.upserted_ids, "passage 1 is byte-identical — not re-upserted"
    end

    def test_document_sweep_delta_removes_all_its_live_passages
      @loader.load([alpha, beta])
      report = fresh_loader.load([beta]) # full load: alpha swept withdrawn

      delta = report.index_delta

      assert_equal %w[alpha:1 alpha:2], delta_labels(delta.removed_ids)
      assert_empty delta.upserted_ids
    end

    def test_same_content_document_restore_delta_upserts_its_passages
      @loader.load([alpha, beta])
      fresh_loader.load([beta]) # alpha withdrawn
      report = fresh_loader.load([alpha, beta]) # alpha restored, byte-identical

      delta = report.index_delta

      assert_equal %w[alpha:1 alpha:2], delta_labels(delta.upserted_ids),
                   "a restored document's passages re-enter the live set — all must re-index"
      assert_empty delta.removed_ids
    end

    def test_withdrawn_document_revision_delta_upserts_all_live_passages
      @loader.load([alpha, beta])
      fresh_loader.load([beta]) # alpha withdrawn
      # alpha returns REVISED: passage 2 reworded, passage 1 byte-identical.
      # Both left the index at withdrawal, so both must come back — the
      # unchanged-sibling rule yields to the re-entry rule here.
      report = fresh_loader.load([collides_with_alpha, beta])

      delta = report.index_delta

      assert_equal %w[alpha:1 alpha:2], delta_labels(delta.upserted_ids)
    end

    def test_metadata_only_reconcile_delta_is_empty
      @loader.load([alpha])
      relabeled = build_document("alpha", [%w[1 μῆνιν], %w[2 ἄειδε]], license_override: "open")
      report = fresh_loader.load([relabeled])

      assert_report report, updated: 1
      assert_predicate report.index_delta, :empty?,
                       "a metadata reconcile moves nothing in or out of the live set"
    end

    def test_constraint_violation_contributes_nothing_to_the_delta
      clash = Nabu::Document.new(
        urn: doc_urn("clash"), language: "grc", title: "Clash",
        canonical_path: "/canonical/test_adapter/clash.txt"
      )
      clash << Nabu::Passage.new(
        urn: "#{doc_urn('alpha')}:1", language: "grc",
        text: "δόλος", text_normalized: "δόλος", sequence: 0
      )

      report = @loader.load([alpha, clash, beta])

      assert_report report, added: 2, errored: 1
      assert_equal %w[alpha:1 alpha:2 beta:1], delta_labels(report.index_delta.upserted_ids),
                   "the rolled-back document's staged rows must be discarded"
    end

    def test_within_pass_collision_contributes_nothing_to_the_delta
      report = @loader.load([alpha, collides_with_alpha])

      assert_report report, added: 1, collided: 1
      assert_equal %w[alpha:1 alpha:2], delta_labels(report.index_delta.upserted_ids),
                   "the kept row was written once; the rejected duplicate adds nothing"
    end

    def test_delta_overflow_clears_the_sets_and_flags
      capped = Nabu::Store::Loader.new(db: @db, source: @source, ledger: @ledger,
                                       index_delta_cap: 2)
      report = capped.load([alpha, beta]) # 3 passages > cap 2

      delta = report.index_delta

      assert_predicate delta, :overflowed?
      assert_empty delta.upserted_ids, "an overflowed delta frees its sets — the fallback is the slice rewrite"
      refute_predicate delta, :empty?, "overflowed is not empty — the caller must not skip"
    end

    def test_delta_rides_frozen_on_the_report
      report = @loader.load([alpha])

      assert_predicate report.index_delta, :frozen?
      assert_raises(FrozenError) { report.index_delta.upserted_ids << 999 }
    end

    def test_tx_batch_mode_collects_the_same_delta
      batched = Nabu::Store::Loader.new(db: @db, source: @source, ledger: @ledger, tx_batch: 2)
      report = batched.load([alpha, beta, build_document("gamma", [%w[1 πόλις]])])

      assert_equal %w[alpha:1 alpha:2 beta:1 gamma:1],
                   delta_labels(report.index_delta.upserted_ids)
    end

    # A second load on the SAME loader instance starts a fresh delta — the
    # report's sets describe one load, never an accumulation.
    def test_each_load_gets_a_fresh_delta
      @loader.load([alpha, beta])
      report = @loader.load([alpha, beta])

      assert_predicate report.index_delta, :empty?
    end

    def fresh_loader
      Nabu::Store::Loader.new(db: @db, source: @source, ledger: @ledger)
    end

    # -- catalog slimming (P112-2, Q113) -------------------------------------
    # text_normalized measured byte-identical to text on the vast majority
    # of rows (the CJK-dominated corpus folds to itself): the loader stores
    # "" when equal (the column is NOT NULL on the standing table
    # generation), and every reader coalesces through the text_search
    # generated column (migration 037).

    # build_document derives text_normalized by downcasing, so Han text —
    # caseless — exercises the identical path.
    def han_document
      build_document("han", [%w[1 王道蕩蕩], %w[2 不偏不黨]])
    end

    def test_identical_text_normalized_stores_the_empty_sentinel
      @loader.load([han_document])
      stored = @db[:passages].where(urn: "#{doc_urn('han')}:1").first

      assert_equal "", stored[:text_normalized], "byte-identical search form stores the sentinel"
      assert_equal "王道蕩蕩", stored[:text_search], "the generated column coalesces to text"
    end

    def test_distinct_text_normalized_still_stores
      # Capitalized Greek: the downcased search form differs from the text.
      @loader.load([build_document("caps", [%w[1 Μῆνιν]])])
      stored = @db[:passages].where(urn: "#{doc_urn('caps')}:1").first

      assert_equal "μῆνιν", stored[:text_normalized]
      assert_equal "μῆνιν", stored[:text_search]
      assert_equal "Μῆνιν", stored[:text], "the pristine text is untouched"
    end

    def test_revision_to_identical_form_stores_the_sentinel
      @loader.load([han_document])
      revised = build_document("han", [%w[1 王道蕩蕩], %w[2 大道甚夷]])
      report = fresh_loader.load([revised])

      assert_report report, updated: 1, revised: 1
      stored = @db[:passages].where(urn: "#{doc_urn('han')}:2").first

      assert_equal "", stored[:text_normalized]
      assert_equal "大道甚夷", stored[:text_search]
    end

    def test_sentinel_rows_stay_idempotent
      @loader.load([han_document])
      passages_before = snapshot(Nabu::Store::Passage)

      report = fresh_loader.load([han_document])

      assert_report report, skipped: 1
      assert_equal passages_before, snapshot(Nabu::Store::Passage)
    end
  end
end

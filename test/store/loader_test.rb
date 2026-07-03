# frozen_string_literal: true

require "test_helper"

module Store
  class LoaderTest < Minitest::Test
    include StoreTestDB

    FIXTURES = File.expand_path("../fixtures/test_adapter", __dir__)

    # TestAdapter variant whose parse fails for one specific ref — the
    # quarantine path's rig.
    class QuarantiningAdapter < TestAdapter
      def parse(document_ref)
        raise Nabu::ParseError, "deliberately corrupt document" if document_ref.id == "beta.txt"

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

    def setup
      @db = store_test_db
      @source = Nabu::Store::Source.create(
        slug: "test_adapter", name: "Conformance Test Adapter",
        adapter_class: "TestAdapter", license_class: "open"
      )
      @loader = Nabu::Store::Loader.new(db: @db, source: @source)
    end

    # -- helpers -------------------------------------------------------------

    # passages: array of [urn_suffix, text] pairs; sequence is the array index.
    def build_document(slug, passages, title: "Document #{slug}", annotations: {})
      document = Nabu::Document.new(
        urn: doc_urn(slug), language: "grc", title: title,
        canonical_path: "/canonical/test_adapter/#{slug}.txt"
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

    def snapshot(model) = model.order(:id).all.map(&:values)

    def alpha(title: "Document alpha")
      build_document("alpha", [%w[1 μῆνιν], %w[2 ἄειδε]], title: title)
    end

    def beta = build_document("beta", [%w[1 ἄνδρα]])

    def assert_report(report, added: 0, updated: 0, skipped: 0, withdrawn: 0, errored: 0)
      assert_equal(
        { added: added, updated: updated, skipped: skipped, withdrawn: withdrawn, errored: errored },
        report.to_h
      )
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
      assert_equal 1, provenance_events(passage_id: passage.id, event: "loaded").size
      assert_equal 5, Nabu::Store::Provenance.count # 2 documents + 3 passages
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

    # -- revisions -----------------------------------------------------------

    def test_changed_passage_bumps_revisions_and_journals_old_sha
      @loader.load([alpha, beta])
      old_doc_sha = doc_row("alpha").content_sha256
      old_passage_sha = passage_row("alpha", "2").content_sha256
      untouched_passage = passage_row("alpha", "1").values

      changed = build_document("alpha", [%w[1 μῆνιν], %w[2 θεά]])
      report = @loader.load([changed, beta])

      assert_report report, updated: 1, skipped: 1

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

      assert_report report, updated: 1
      row = doc_row("alpha")
      assert_equal 2, row.revision
      assert_equal "Document alpha, corrected", row.title
      assert_equal passages_before, snapshot(Nabu::Store::Passage)
    end

    def test_sequence_reorder_is_a_safe_revision
      @loader.load([alpha])

      swapped = build_document("alpha", [%w[2 ἄειδε], %w[1 μῆνιν]])
      report = @loader.load([swapped])

      assert_report report, updated: 1
      assert_equal 0, passage_row("alpha", "2").sequence
      assert_equal 1, passage_row("alpha", "1").sequence
      assert_equal [2, 2], [passage_row("alpha", "1").revision, passage_row("alpha", "2").revision]
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

      assert_report report, skipped: 1, updated: 1
      row = doc_row("beta")
      refute row.withdrawn
      assert_equal 1, row.revision # content unchanged: restore is not a revision
      assert_equal 1, provenance_events(document_id: row.id, event: "restored").size
      assert_empty provenance_events(document_id: row.id, event: "revised")
    end

    def test_withdrawn_document_reappearing_changed_is_restored_and_revised
      @loader.load([alpha, beta])
      @loader.load([alpha], full: true)

      changed_beta = build_document("beta", [%w[1 πολύτροπον]])
      report = @loader.load([alpha, changed_beta])

      assert_report report, skipped: 1, updated: 1
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

      assert_report report, updated: 1
      vanished = passage_row("alpha", "2")
      assert vanished.withdrawn
      assert_equal 1, vanished.revision
      assert_equal 1, provenance_events(passage_id: vanished.id, event: "withdrawn").size
      assert_equal 1, passage_row("alpha", "3").sequence

      # Idempotency after passage withdrawal: same load again is a full skip.
      report = @loader.load([build_document("alpha", [%w[1 μῆνιν], %w[3 θεά]])])
      assert_report report, skipped: 1
      assert_equal 1, provenance_events(passage_id: vanished.id, event: "withdrawn").size

      # The passage reappears with identical content: restored, no bump.
      report = @loader.load([build_document("alpha", [%w[1 μῆνιν], %w[2 ἄειδε], %w[3 θεά]])])
      assert_report report, updated: 1
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
      assert_equal "beta.txt", params.fetch("ref_id")
      assert_equal "deliberately corrupt document", params.fetch("error")
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
  end
end

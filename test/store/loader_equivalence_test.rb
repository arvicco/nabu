# frozen_string_literal: true

require "test_helper"
require "digest"
require "json"

module Store
  # The loader's OBSERVABLE output pinned byte for byte: real fixture
  # corpora (annotated treebanks included) loaded on both transaction
  # grains, then a synthetic revision walk (content revision, reorder,
  # passage withdrawal + restore, document sweep + restore, a constraint
  # quarantine). Every persisted row the loader writes — documents,
  # passages (ids included), provenance, source stats, the durable ledger —
  # plus each load's report and index delta is digested, wall-clock columns
  # excluded. The pinned digests were taken from the per-row loader before
  # its write path was batched; any drift in ids, column bytes, journal
  # order or report counts fails here.
  class LoaderEquivalenceTest < Minitest::Test
    include StoreTestDB

    FIXTURES = File.expand_path("../fixtures", __dir__)

    SOURCES = [
      ["perseus-greek", "Nabu::Adapters::Perseus", %w[perseus greekLit], { translations: true }],
      ["ud", "Nabu::Adapters::UniversalDependencies", %w[ud]],
      ["proiel", "Nabu::Adapters::Proiel", %w[proiel]],
      ["torot", "Nabu::Adapters::Torot", %w[torot]],
      ["papyri", "Nabu::Adapters::Papyri", %w[ddbdp]]
    ].freeze

    # Wall-clock columns and the release stamp: the only bytes allowed to
    # differ between runs (a version bump must not trip the pin).
    VOLATILE = %i[at updated_at withdrawn_at tool_version].freeze

    FIXTURE_DIGEST = "dfdd7367728320152fdecdc95af959eb7849b28534d710d3709d063dbbe010b8"
    WALK_DIGEST = "cf74dd259cfabc229a7828f6e8dc1c662aaf6eba4bb06dd3221af04eefe0fbcb"

    def test_fixture_corpora_load_byte_identically_on_both_grains
      per_row = fixture_digest(tx_batch: nil)
      assert_equal per_row, fixture_digest(tx_batch: 3),
                   "both transaction grains must persist byte-identically (shas included)"
      assert_equal FIXTURE_DIGEST, per_row.portable,
                   "the portable pin (document shas masked — they hash canonical_path, " \
                   "which is absolute, so the raw digest differs per checkout)"
    end

    def test_revision_walk_persists_byte_identically
      # Synthetic documents use fixed /canonical/ paths, so the full
      # digest is already portable here.
      assert_equal WALK_DIGEST, walk_digest.full
    end

    EquivalenceDigest = Data.define(:full, :portable) do
      def ==(other) = other.is_a?(self.class) ? super : full == other
    end

    private

    def fixture_digest(tx_batch:)
      db = store_test_db
      ledger = ledger_test_db
      reports = SOURCES.flat_map do |slug, class_name, path, options|
        adapter = Object.const_get(class_name).new(**(options || {}))
        source = Nabu::Store::Source.create(slug: slug, name: slug, adapter_class: class_name,
                                            license_class: adapter.manifest.license_class)
        loader = Nabu::Store::Loader.new(db: db, source: source, ledger: ledger, tx_batch: tx_batch)
        workdir = File.join(FIXTURES, *path)
        # The second pass is the idempotent replay: its report and empty
        # delta are part of the pinned output.
        Array.new(2) { loader.load_from(adapter, workdir: workdir, full: true) }
      end
      digest(db, ledger, reports)
    end

    def walk_digest
      db = store_test_db
      ledger = ledger_test_db
      source = Nabu::Store::Source.create(slug: "test_adapter", name: "Test", adapter_class: "TestAdapter",
                                          license_class: "open")
      loader = Nabu::Store::Loader.new(db: db, source: source, ledger: ledger)
      notes = { "lemma" => "μῆνις", "upos" => "NOUN", "feats" => { "Case" => "Acc", "Number" => "Sing" } }
      reports = [
        loader.load([document("alpha", [%w[1 μῆνιν], %w[2 ἄειδε], %w[3 θεὰ]], annotations: notes),
                     document("beta", [%w[1 ἄνδρα], %w[2 μοι]]), clash]),
        # alpha revised: passage 2 changed, 3 vanished, 4 new, 1 moved to
        # the end; beta absent from a full load is swept.
        loader.load([document("alpha", [%w[2 ἀείδω], %w[4 Πηληϊάδεω], %w[1 μῆνιν]], annotations: notes)]),
        # beta returns unchanged (restore); alpha's vanished passage 3
        # returns with its old content (passage restore within a revision).
        loader.load([document("alpha", [%w[2 ἀείδω], %w[4 Πηληϊάδεω], %w[1 μῆνιν], %w[3 θεὰ]],
                              annotations: notes),
                     document("beta", [%w[1 ἄνδρα], %w[2 μοι]])]),
        loader.load([document("gamma", [%w[1 πόλις]])], full: false)
      ]
      digest(db, ledger, reports)
    end

    def document(slug, passages, annotations: {})
      document = Nabu::Document.new(urn: "urn:nabu:test:#{slug}", language: "grc", title: "Document #{slug}",
                                    canonical_path: "/canonical/test_adapter/#{slug}.txt",
                                    metadata: { "kind" => "poem", "persons" => %w[b a] })
      passages.each_with_index do |(suffix, text), index|
        document << Nabu::Passage.new(urn: "urn:nabu:test:#{slug}:#{suffix}", language: "grc", text: text,
                                      annotations: annotations.merge("n" => suffix), sequence: index)
      end
      document
    end

    # A passage urn already held by alpha: the unique index quarantines it.
    def clash
      document = Nabu::Document.new(urn: "urn:nabu:test:clash", language: "grc", title: "Clash",
                                    canonical_path: "/canonical/test_adapter/clash.txt")
      document << Nabu::Passage.new(urn: "urn:nabu:test:alpha:1", language: "grc", text: "δόλος", sequence: 0)
      document
    end

    def digest(db, ledger, reports)
      payload = {
        "documents" => rows(db[:documents]),
        "passages" => rows(db[:passages]),
        "provenance" => rows(db[:provenance]),
        "source_stats" => rows(db[:source_stats]),
        "source_stats_languages" => db[:source_stats_languages].all.map { |row| row.to_a.sort_by(&:first) }
                                                               .sort_by(&:inspect),
        "revisions" => rows(ledger[:revisions]),
        "reports" => reports.map { |report| report_payload(report) }
      }
      # Two environment leaks, two treatments. (1) canonical_path and
      # report strings embed the checkout's absolute fixture paths —
      # normalized textually. (2) DOCUMENT shas hash canonical_path
      # (ContentHash.document), so they differ per checkout IRREDUCIBLY:
      # the full digest (shas included) backs the env-local grain
      # comparison, and the PORTABLE digest — document shas masked by a
      # stable per-document token — backs the cross-checkout pin.
      # Passage shas hash text+annotations only and stay in both.
      serialized = JSON.generate(payload).gsub(FIXTURES, "<fixtures>")
      doc_shas = db[:documents].order(:id).select_map(:content_sha256)
      portable = serialized.dup
      doc_shas.each_with_index { |sha, i| portable = portable.gsub(sha, "docsha:#{i}") }
      EquivalenceDigest.new(full: Digest::SHA256.hexdigest(serialized),
                            portable: Digest::SHA256.hexdigest(portable))
    end

    def rows(dataset)
      dataset.order(:id).all.map { |row| row.except(*VOLATILE).to_a }
    end

    def report_payload(report)
      delta = report.index_delta
      report.to_h.except(:index_delta).merge(
        upserted: [delta.upserted_ids.to_a.sort, delta.upserted_urns.to_a.sort],
        removed: [delta.removed_ids.to_a.sort, delta.removed_urns.to_a.sort],
        overflowed: delta.overflowed?
      ).to_a
    end
  end
end

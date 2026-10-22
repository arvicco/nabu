# frozen_string_literal: true

require "test_helper"
require "digest"
require "json"
require "tmpdir"
require "fileutils"

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

    # The parallel-grain corpus: the sources above plus the heaviest
    # replay shapes the forked parse pool is opted in for, so the pool is
    # refereed against real multi-passage TEI, JSONL and mandoku output.
    PARALLEL_SOURCES = SOURCES + [
      ["dta", "Nabu::Adapters::Dta", %w[dta]],
      ["eebo-tcp", "Nabu::Adapters::EeboTcp", %w[eebo-tcp], { classes: %w[phase1 phase2] }],
      ["okhc", "Nabu::Adapters::Okhc", %w[okhc]],
      ["kanripo", "Nabu::Adapters::Kanripo", %w[kanripo]],
      ["cbeta", "Nabu::Adapters::Cbeta", %w[cbeta]]
    ].freeze

    # Wall-clock columns and the release stamp: the only bytes allowed to
    # differ between runs (a version bump must not trip the pin).
    VOLATILE = %i[at updated_at withdrawn_at tool_version].freeze

    # Re-taken when the DDbDP parser gained its apparatus layer: the papyri
    # fixture passages carrying <app> now persist an "apparatus" annotation
    # (passage text and urns unchanged — pinned in ddbdp_parser_test).
    # Re-taken again when the ud fixture tree gained the Old Georgian GLC
    # and Middle Armenian ArmTDP treebanks (two new documents, 47
    # passages, the ArmTDP `doc_title` work titles riding as "title").
    FIXTURE_DIGEST = "3b183ea63cc5072a56f103348b16229501c00f930d666f78b87d304e490d4e3e"
    WALK_DIGEST = "cf74dd259cfabc229a7828f6e8dc1c662aaf6eba4bb06dd3221af04eefe0fbcb"

    def test_fixture_corpora_load_byte_identically_on_both_grains
      per_row = fixture_digest(tx_batch: nil)
      assert_equal per_row, fixture_digest(tx_batch: 3),
                   "both transaction grains must persist byte-identically (shas included)"
      assert_equal FIXTURE_DIGEST, per_row.portable,
                   "the portable pin (document shas masked — they hash canonical_path, " \
                   "which is absolute, so the raw digest differs per checkout)"
    end

    # The forked parse pool (parse_workers > 1) feeds the same writer in
    # parse order, so every grain persists exactly what the serial parse
    # does — ids, journal order, reports and deltas included.
    def test_parallel_parse_workers_persist_byte_identically
      serial = fixture_digest(tx_batch: 3, sources: PARALLEL_SOURCES)
      [2, 3, 5].each do |workers|
        assert_equal serial, fixture_digest(tx_batch: 3, sources: PARALLEL_SOURCES, parse_workers: workers),
                     "#{workers} parse workers must persist byte-identically to the serial parse"
      end
      assert_equal fixture_digest(tx_batch: nil, sources: PARALLEL_SOURCES),
                   fixture_digest(tx_batch: nil, sources: PARALLEL_SOURCES, parse_workers: 3),
                   "the per-document grain too"
    end

    # The interleavings the pool must replay slot for slot: attic
    # retained documents, a superseded attic duplicate (journaled between
    # documents), a parse quarantine, a rule skip, and a revision pass
    # over the catalog the first pass wrote.
    def test_parallel_parse_workers_replay_attic_quarantine_and_skip_interleavings
      Dir.mktmpdir("nabu-parallel-grain") do |workdir|
        serial = interleaving_digest(workdir, parse_workers: 1)
        [2, 4].each do |workers|
          assert_equal serial, interleaving_digest(workdir, parse_workers: workers),
                       "#{workers} parse workers must replay the interleavings byte-identically"
        end
      end
    end

    def test_revision_walk_persists_byte_identically
      # Synthetic documents use fixed /canonical/ paths, so the full
      # digest is already portable here.
      assert_equal WALK_DIGEST, walk_digest.full
    end

    EquivalenceDigest = Data.define(:full, :portable) do
      def ==(other) = other.is_a?(self.class) ? super : full == other
    end

    # TestAdapter's plain-text shape, plus a rule skip for "skip-*" files.
    class InterleavingAdapter < TestAdapter
      def parse(document_ref)
        if File.basename(document_ref.path).start_with?("skip-")
          raise Nabu::DocumentSkipped.new("catalog-only #{document_ref.id}", reason: "catalog-only")
        end

        super
      end
    end

    LIVE_FILES = {
      "alpha.txt" => "Alpha\nμῆνιν ἄειδε θεά\nΠηληϊάδεω Ἀχιλῆος\n",
      "beta.txt" => "Beta\nἄνδρα μοι ἔννεπε\n",
      "broken.txt" => "", # ParseError: no title line
      "delta.txt" => "Delta\nὃς πολλὰ πλάγχθη\n",
      "skip-catalog.txt" => "Catalog\nnothing here\n",
      "zeta.txt" => "Zeta\nἱερὸν πτολίεθρον\n"
    }.freeze

    ATTIC_FILES = {
      "beta.txt" => "Beta\nan older beta, superseded by the live file\n",
      "eta.txt" => "Eta\nretired upstream, kept live\n",
      "theta.txt" => "Theta\nretired too\n"
    }.freeze

    private

    def fixture_digest(tx_batch:, sources: SOURCES, parse_workers: 1)
      db = store_test_db
      ledger = ledger_test_db
      reports = sources.flat_map do |slug, class_name, path, options|
        adapter = Object.const_get(class_name).new(**(options || {}))
        source = Nabu::Store::Source.create(slug: slug, name: slug, adapter_class: class_name,
                                            license_class: adapter.manifest.license_class)
        loader = Nabu::Store::Loader.new(db: db, source: source, ledger: ledger, tx_batch: tx_batch,
                                         parse_workers: parse_workers)
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

    # Two passes over one tree: the first loads everything fresh, the
    # second revises alpha and sweeps zeta (its file gone).
    def interleaving_digest(workdir, parse_workers:)
      write_tree(workdir, LIVE_FILES)
      write_tree(File.join(workdir, ".attic"), ATTIC_FILES)
      db = store_test_db
      ledger = ledger_test_db
      source = Nabu::Store::Source.create(slug: "test_adapter", name: "Test", adapter_class: "TestAdapter",
                                          license_class: "open")
      loader = Nabu::Store::Loader.new(db: db, source: source, ledger: ledger, tx_batch: 2,
                                       parse_workers: parse_workers)
      adapter = InterleavingAdapter.new
      reports = [loader.load_from(adapter, workdir: workdir, full: true)]
      File.write(File.join(workdir, "alpha.txt"), "Alpha\nμῆνιν ἄειδε θεά\nνέος στίχος\n")
      File.delete(File.join(workdir, "zeta.txt"))
      reports << loader.load_from(adapter, workdir: workdir, full: true)
      digest(db, ledger, reports).full
    end

    def write_tree(dir, files)
      FileUtils.mkdir_p(dir)
      files.each { |name, body| File.write(File.join(dir, name), body) }
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

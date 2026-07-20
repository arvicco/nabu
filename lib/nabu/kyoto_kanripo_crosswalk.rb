# frozen_string_literal: true

module Nabu
  # Producer #8 for the links journal (P33-3): the Kyoto↔Kanripo crosswalk.
  # The UD Classical Chinese Kyoto treebank names its source texts by
  # Kanripo id in its own `# newdoc id` lines — `<KR-id>_<juan>`
  # (KR1h0004_001 = 論語 book 1) — so each treebank file's ids become
  # kind=reference edges treebank-document ↔ urn:nabu:kanripo:<KR-id>, and
  # `nabu links` serves the treebank↔corpus hop from either side.
  #
  # == The censused id map (upstream master, 2026-07-20; never guess)
  #
  # All 936 newdoc ids across the three real splits are KR-shaped — ten
  # distinct texts: KR1h0004 論語 (20 juan-docs), KR1h0001 孟子 (14),
  # KR1d0052 禮記 (50), KR2b0041 十八史略 (19), KR2e0003 戰國策 (501),
  # KR4a0001 楚辭 (9), KR4h0169 唐詩三百首 (320), and one juan each of the
  # three sutras KR6c0023 / KR6c0127 / KR6f0082. The newdoc ids are the
  # authoritative map — the README's per-split text listing is stale
  # against the data (it swaps the dev/train sutras: the data has KR6f0082
  # in dev and KR6c0023 in train). The sibling TueCL treebank carries NO
  # Kanripo ids (bare numeric sent_ids, no newdoc lines) — no edges, the
  # P19-4/P25-1 edge-worthiness rule.
  #
  # == Dangling-but-stable minting (the P32-6 precedent)
  #
  # Edges mint for every KR-shaped id whether or not the kanripo side is
  # synced (today: none are — wave 1 awaits the owner-fired sync); they
  # resolve the day the wave lands, and `nabu links` renders unminted
  # counterparts "(not in catalog)" honestly. Wave-1 (KR1/KR3/KR4) covers
  # 5 of the 10 texts (413/936 newdocs); KR2b0041/KR2e0003 resolve at the
  # P33-1 KR2 wave; the KR6 sutras stay dangling while KR6 is excluded
  # (CBETA is the scholarly Buddhist shelf — the P33-0 doctrine call).
  # ONE census caveat, recorded: KR4h0169 is absent from BOTH the
  # KR-Catalog (KR4h ends at 0168) and the kanripo org (repo 404, checked
  # 2026-07-20) — a Kyoto-local extension of the id space (their ud-kanbun
  # GitLab hosts kanripo/kR4h0169 themselves; same Kyoto IRH id
  # authority). It mints like the rest and stays dangling until Kanripo
  # publishes it. A newdoc id OUTSIDE the KR grammar mints nothing and is
  # counted (+skipped_unmapped+) so the summary stays honest.
  #
  # == Refresh mechanics (the standing producer contract)
  #
  # Edges are a pure function of (canonical conllu files, code): SyncRunner
  # re-runs this producer after every ud sync via the reference_producer
  # seam, superseding the prior (producer, scope) run atomically. Only the
  # `# newdoc id` lines are read (streamed — the real train split is
  # ~40 MB). A workdir without the kyoto treebank dir — every sync before
  # the owner first syncs the P32-0 treebanks — is a no-op that supersedes
  # NOTHING, so standing edges survive. Rebuild never touches the journal;
  # losing it costs one re-run.
  class KyotoKanripoCrosswalk
    PRODUCER = "ud-kanripo"
    KIND = "reference"
    CODE_VERSION = "kyoto-kanripo-crosswalk/1 nabu/#{VERSION}".freeze

    # The one treebank of the ud TREEBANKS map that carries Kanripo ids
    # (class note), and the urn prefixes FROZEN by P3-3 and P33-0.
    TREEBANK = "classical-chinese-kyoto"
    UD_URN_PREFIX = "urn:nabu:ud:#{TREEBANK}:".freeze
    KANRIPO_URN_PREFIX = "urn:nabu:kanripo:"

    NEWDOC = /^# newdoc id = (\S+)/
    # The censused newdoc grammar: <KR-id>_<juan digits>, nothing else.
    KR_NEWDOC = /\A(KR\d[a-z]\d{4})_\d+\z/

    # What one refresh did — the LibraryReferences::Result shape (so the
    # CLI sync tail renders every producer identically) plus the honesty
    # counter from the class note.
    Result = Data.define(:scope, :run_id, :edges_written, :edges_refreshed,
                         :superseded_runs, :superseded_edges, :skipped_unmapped)

    # +catalog+ rides the Adapter.reference_producer seam; edges mint for
    # unsynced kanripo texts too (class note), so only the journal is read
    # or written here.
    def initialize(catalog:, journal:)
      @catalog = catalog
      @journal = journal
    end

    # Re-derive every crosswalk edge from <workdir>/classical-chinese-kyoto/
    # *.conllu, superseding the prior (producer, scope) run. A workdir
    # without the treebank's files is the honest no-op (class note).
    def run(slug, workdir: nil)
      files = conllu_files(workdir)
      return absent_result(slug) if files.empty?

      counts = Hash.new(0)
      edges = files.flat_map { |path| file_edges(path, counts) }
      run_id = superseded = nil
      @journal.transaction do
        superseded = Store::LinksJournal.supersede!(@journal, producer: PRODUCER, scope: slug)
        run_id = Store::LinksJournal.record_run!(@journal, producer: PRODUCER, scope: slug,
                                                           params: { kind: KIND }, code_version: CODE_VERSION)
        write_edges(edges, run_id, counts)
      end
      Result.new(scope: slug, run_id: run_id,
                 edges_written: counts[:inserted], edges_refreshed: counts[:refreshed],
                 superseded_runs: superseded[0], superseded_edges: superseded[1],
                 skipped_unmapped: counts[:unmapped])
    end

    private

    def conllu_files(workdir)
      return [] unless workdir

      Dir.glob(File.join(workdir, TREEBANK, "*.conllu"))
    end

    def absent_result(slug)
      Result.new(scope: slug, run_id: nil, edges_written: 0, edges_refreshed: 0,
                 superseded_runs: 0, superseded_edges: 0, skipped_unmapped: 0)
    end

    # One edge per (conllu file, KR text) pair — document grain on BOTH
    # sides: the ud document is the split file (P3-3 minting), the kanripo
    # document is the text (P33-0 minting). The newdoc ids behind the pair
    # ride the detail as first…last span + exact count (juan sets are not
    # always contiguous upstream — train's 論語 skips the test/dev books).
    def file_edges(path, counts)
      stem = File.basename(path, ".conllu")
      newdoc_ids_by_text(path, counts).map do |text, ids|
        { from: "#{UD_URN_PREFIX}#{stem}", to: "#{KANRIPO_URN_PREFIX}#{text}",
          detail: detail_for(ids) }
      end
    end

    # { KR-id => sorted newdoc ids } from the file's `# newdoc id` lines
    # only, streamed. Non-KR ids are counted, never minted (class note).
    def newdoc_ids_by_text(path, counts)
      by_text = Hash.new { |ids, text| ids[text] = [] }
      File.foreach(path) do |line|
        next unless (id = line[NEWDOC, 1])

        if (text = id[KR_NEWDOC, 1])
          by_text[text] << id
        else
          counts[:unmapped] += 1
        end
      end
      by_text.transform_values { |ids| ids.uniq.sort }
    end

    def detail_for(ids)
      span = ids.size == 1 ? ids.first : "#{ids.first}…#{ids.last}"
      "newdoc #{span} · #{ids.size} juan"
    end

    def write_edges(edges, run_id, counts)
      edges.each do |edge|
        outcome = Store::LinksJournal.write_edge!(
          @journal, from_urn: edge[:from], to_urn: edge[:to],
                    kind: KIND, score: nil, run_id: run_id, detail: edge[:detail]
        )
        counts[outcome == :inserted ? :inserted : :refreshed] += 1
      end
    end
  end
end

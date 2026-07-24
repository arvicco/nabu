# frozen_string_literal: true

require "json"

module Nabu
  # Producer #9 for the links journal (P43-4): the KITAB Text Reuse instrument
  # over the held OpenITI corpus (pilot scope). KITAB's passim pipeline computes
  # pairwise text-reuse alignments across OpenITI and publishes them as TSV
  # files (`.csv` extension, TAB-separated) named `<book1-vid>_<book2-vid>.csv`
  # under one folder per book. The kitab feature module's fetch lands one held
  # book's complete pairwise fan under canonical/kitab/pairwise/<folder>/. This
  # producer reads that tree and mints ONE edge per alignment row, NEW kind
  # "reuse" — UPSTREAM-computed alignments, deliberately distinct from kind
  # "parallel" (nabu's own intertext detection). The links layer validates no
  # kind vocabulary (write_edge! and Query::Links group by whatever kind string
  # they are handed), so "reuse" is additive: it needs no registration and
  # renders as its own group in `nabu links`.
  #
  # == The alignment row → one reuse edge
  #
  # Each row carries character offsets (b/e), Arabic-word-token offsets (bw/ew),
  # and seq1/seq2 = the mARkdown MILESTONE number in each book. The edge runs
  # from book1's passage at milestone seq1 to book2's passage at milestone seq2;
  # the detail carries the offsets VERBATIM (seq1→seq2 · b/e char + word
  # offsets) so the reader can find the exact span. score is nil — an
  # upstream-computed alignment is not a mined similarity.
  #
  # Adjacent-milestone alignment runs (consecutive rows continuing one reuse
  # passage — the staged multi-row file's seq1=1,1,2 pattern) stay ONE EDGE PER
  # ROW for v1 (honest granularity; merging runs into passage-spanning edges is
  # a future refinement). NB write_edge! keeps at most one edge per unordered
  # pair per kind, so rows that resolve to the SAME (from, to) pair collapse to
  # one edge (refreshed in place) — most visibly the both-sides-downgraded rows,
  # which collapse to a single book↔book edge. Every row is still COUNTED
  # (rows_read) and the collapse is honest, not a silent drop.
  #
  # == vid → held openiti document (the urn derivation)
  #
  # A KITAB version id (`ALCorpus00001-ara2`) is the OpenITI version_uri's LAST
  # dotted segment — the openiti adapter mints urn:nabu:openiti:<version_uri>
  # (e.g. urn:nabu:openiti:0157AbuMikhnafAzdi.MaqtalHusayn.Shia003665-ara1), so
  # the held document is the catalog row whose urn ends `.<vid>`. A vid with no
  # such row (a partner book we do not hold, or one that quarantined at parse so
  # never minted a row) means the edge has no endpoint on that side: the whole
  # file is SKIPPED and counted (unheld_book_files), never a false edge.
  #
  # == seq → passage, and the document-grain downgrade
  #
  # A held openiti passage carries its raw msNN tokens in annotations
  # ("milestones" => ["ms1", …]); padding varies upstream (ms1 vs ms01), so the
  # map keys on the INTEGER value (delete the "ms" prefix, to_i). A seq that
  # resolves to no held passage (the milestone is outside our parse — a trimmed
  # tail, a page we did not reach) DOWNGRADES that side of the edge to the
  # book's DOCUMENT urn, with the milestone (and offsets) still in the detail —
  # counted in downgraded_rows, never dropped silently.
  #
  # == Refresh mechanics (the standing producer contract, the crosswalk shape)
  #
  # Edges are a pure function of (canonical pairwise tree, catalog, code):
  # SyncRunner re-runs this producer after every kitab sync via
  # Adapter.reference_producer, superseding the prior (producer, scope) run
  # atomically. A workdir WITHOUT the tree — every parse-only sync before the
  # first fetch — is a no-op that supersedes NOTHING, so standing edges survive.
  # Rebuild never touches the journal; losing it costs one re-run.
  # Derived-and-rebuildable: dropping links and re-running re-derives identical
  # edges (the rebuild-equivalence test).
  class KitabTextReuse
    PRODUCER = "kitab"
    KIND = "reuse"
    CODE_VERSION = "kitab-text-reuse/1 nabu/#{VERSION}".freeze

    # Where Adapters::Kitab#fetch lands the pairwise fans, under the source's
    # canonical workdir: pairwise/<folder>/<book1>_<book2>.csv.
    PAIRWISE_DIRNAME = "pairwise"

    OPENITI_URN_PREFIX = "urn:nabu:openiti:"
    # A milestone token as stored in openiti passage annotations (padding varies).
    MS_TOKEN = /\Ams(\d+)\z/

    # The TSV column order (verified upstream): b1 b2 bw1 bw2 e1 e2 ew1 ew2
    # seq1 seq2.
    COLUMNS = %w[b1 b2 bw1 bw2 e1 e2 ew1 ew2 seq1 seq2].freeze

    # What one refresh did — the crosswalk Result shape (so the CLI sync tail
    # renders every producer uniformly) plus this producer's census: rows_read,
    # downgraded_rows (a milestone fell back to document grain), and
    # unheld_book_files (a partner book with no held row → the file skipped).
    Result = Data.define(:scope, :run_id, :edges_written, :edges_refreshed,
                         :superseded_runs, :superseded_edges,
                         :rows_read, :downgraded_rows, :unheld_book_files, :files)

    def initialize(catalog:, journal:)
      @catalog = catalog
      @journal = journal
      @resolvers = {} # vid => BookResolver | nil (nil = not held), cached per run
    end

    # Re-derive every reuse edge from <workdir>/pairwise/*/*.csv, superseding
    # the prior (producer, scope) run. A missing tree is the honest no-op.
    def run(slug, workdir: nil)
      files = pairwise_files(workdir)
      return absent_result(slug) if files.empty?

      @resolvers = {}
      counts = Hash.new(0)
      run_id = superseded = nil
      @journal.transaction do
        superseded = Store::LinksJournal.supersede!(@journal, producer: PRODUCER, scope: slug)
        run_id = Store::LinksJournal.record_run!(@journal, producer: PRODUCER, scope: slug,
                                                           params: { kind: KIND }, code_version: CODE_VERSION)
        files.each { |path| write_file_edges(path, run_id, counts) }
      end
      Result.new(scope: slug, run_id: run_id,
                 edges_written: counts[:inserted], edges_refreshed: counts[:refreshed],
                 superseded_runs: superseded[0], superseded_edges: superseded[1],
                 rows_read: counts[:rows], downgraded_rows: counts[:downgraded],
                 unheld_book_files: counts[:unheld_files], files: files.size)
    end

    private

    def pairwise_files(workdir)
      return [] unless workdir

      Dir.glob(File.join(workdir, PAIRWISE_DIRNAME, "*", "*.csv"))
    end

    def absent_result(slug)
      Result.new(scope: slug, run_id: nil, edges_written: 0, edges_refreshed: 0,
                 superseded_runs: 0, superseded_edges: 0,
                 rows_read: 0, downgraded_rows: 0, unheld_book_files: 0, files: 0)
    end

    def write_file_edges(path, run_id, counts)
      vid1, vid2 = book_vids(path)
      book1 = resolver_for(vid1)
      book2 = resolver_for(vid2)
      if book1.nil? || book2.nil?
        counts[:unheld_files] += 1
        return
      end

      each_row(path) do |row|
        counts[:rows] += 1
        write_row_edge(book1, book2, row, run_id, counts)
      end
    end

    # `<book1-vid>_<book2-vid>.csv` (optionally `.completed.csv`). Neither vid
    # carries an underscore — the collection+number+language form has none — so
    # the separator is unambiguous.
    def book_vids(path)
      stem = File.basename(path).sub(/\.completed\.csv\z/, "").sub(/\.csv\z/, "")
      stem.split("_", 2)
    end

    def write_row_edge(book1, book2, row, run_id, counts)
      from, from_grain = book1.resolve(row[:seq1])
      to, to_grain = book2.resolve(row[:seq2])
      downgraded = from_grain == :document || to_grain == :document
      counts[:downgraded] += 1 if downgraded

      outcome = Store::LinksJournal.write_edge!(
        @journal, from_urn: from, to_urn: to, kind: KIND, score: nil,
                  run_id: run_id, detail: detail_for(row, from_grain, to_grain)
      )
      counts[outcome == :inserted ? :inserted : :refreshed] += 1
    end

    # The offsets verbatim + a note when a side fell back to document grain.
    def detail_for(row, from_grain, to_grain)
      base = "seq #{row[:seq1]}→#{row[:seq2]} · b1:b2 #{row[:b1]}:#{row[:b2]} · " \
             "e1:e2 #{row[:e1]}:#{row[:e2]} · bw1:bw2 #{row[:bw1]}:#{row[:bw2]} · " \
             "ew1:ew2 #{row[:ew1]}:#{row[:ew2]}"
      note = grain_note(from_grain, to_grain)
      note ? "#{base} · #{note}" : base
    end

    def grain_note(from_grain, to_grain)
      case [from_grain, to_grain]
      in [:document, :document] then "seq1+seq2 milestones unresolved → both at document grain"
      in [:document, _] then "seq1 milestone unresolved → from at document grain"
      in [_, :document] then "seq2 milestone unresolved → to at document grain"
      else nil
      end
    end

    # Stream the TSV; the header row (starts with "b1") is skipped. Each yielded
    # row is a symbol-keyed hash of the ten columns (values as strings, kept
    # verbatim for the detail; seq is compared as an integer downstream).
    def each_row(path)
      File.foreach(path, encoding: Encoding::UTF_8) do |line|
        fields = line.chomp.split("\t")
        next if fields.empty? || fields.first == COLUMNS.first
        next unless fields.size >= COLUMNS.size

        yield COLUMNS.each_with_index.to_h { |column, index| [column.to_sym, fields[index]] }
      end
    end

    # A held openiti document + its milestone→passage map, or nil when the vid
    # names no held document. Cached per run (book1 recurs across a whole fan).
    def resolver_for(vid)
      @resolvers.fetch(vid) { @resolvers[vid] = build_resolver(vid) }
    end

    def build_resolver(vid)
      doc = @catalog[:documents]
            .where(Sequel.like(:urn, "#{OPENITI_URN_PREFIX}%.#{vid}"))
            .select(:id, :urn).first
      return nil if doc.nil?

      BookResolver.new(doc[:urn], milestone_map(doc[:id]))
    end

    # { milestone integer => passage urn } for one document, from every
    # passage's annotations "milestones" list, normalized on the integer value.
    def milestone_map(document_id)
      map = {}
      @catalog[:passages].where(document_id: document_id)
                         .select(:urn, :annotations_json).each do |passage|
        milestones_of(passage[:annotations_json]).each do |value|
          map[value] ||= passage[:urn]
        end
      end
      map
    end

    def milestones_of(annotations_json)
      return [] if annotations_json.nil? || annotations_json.empty?

      tokens = JSON.parse(annotations_json)["milestones"]
      Array(tokens).filter_map { |token| token[MS_TOKEN, 1]&.to_i }
    rescue JSON::ParserError
      []
    end

    # Resolves a book's seq to [urn, grain]: the passage urn at that milestone,
    # else the document urn (:document grain — the downgrade).
    class BookResolver
      def initialize(document_urn, milestone_map)
        @document_urn = document_urn
        @milestone_map = milestone_map
      end

      def resolve(seq)
        passage = @milestone_map[seq.to_i]
        passage ? [passage, :passage] : [@document_urn, :document]
      end
    end
  end
end

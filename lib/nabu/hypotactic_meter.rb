# frozen_string_literal: true

require_relative "normalize"

module Nabu
  # The METER producer (P44-6): Hypotactic's Greek metrical scansions
  # (D. Chamberlain, hypotactic.com; mirror github.com/Urdatorn/hypotactic)
  # layered onto held Perseus lines. Registered on the `hypotactic` feature
  # module (kind: module) and run by SyncRunner after every hypotactic sync via
  # Adapter.reference_producer — the same post-sync "re-derive a pure function
  # of the loaded rows" seam the trismegistos/kitab instruments ride.
  #
  # == Placement: a links-journal kind="meter" edge, NOT a catalog enrichment
  #
  # Meter is a DERIVED per-passage analysis over lines nabu already holds from
  # ANOTHER source (Perseus). Three placements were weighed against the store:
  #
  #   - passages.annotations_json — WRONG: that row is Perseus's, written once
  #     through its own gateway at parse; a cross-source producer must never
  #     mutate it (CLAUDE.md's one-write-gateway rule), and it is rebuilt from
  #     Perseus's canonical XML, which carries no meter.
  #   - the enrichments table — semantically apt (a derived per-passage payload)
  #     but it lives IN the catalog, which `nabu rebuild` DROPS and regenerates
  #     from each source's own parse; no adapter parse re-derives cross-source
  #     meter, and rebuild's replay_enrichments hook is a no-op — so meter there
  #     would silently vanish on the next rebuild (the derived-must-stay-
  #     rebuildable invariant, broken).
  #   - the links journal — CHOSEN. It is the dedicated store for derived data
  #     that is "a function of (canonical, params, code) … must survive a
  #     rebuild … but a rerun legitimately REPLACES its edges" (LinksJournal's
  #     own header). rebuild never touches it; losing it costs one re-run. This
  #     is exactly meter's lifecycle, and the plan (P44-6) lists the links-edge
  #     placement explicitly.
  #
  # So each matched line mints ONE edge, kind="meter":
  #   from  the held Perseus passage urn (catalog-resident by construction —
  #         we only mint for a line we matched against a held passage)
  #   to    meter:<meter-name-slug>  (e.g. meter:dactylic-hexameter) — a
  #         descriptor node grouping every line of that meter; renders
  #         "(not in catalog)" honestly, the tm:/dict: external-node precedent
  #   detail  the scansion pattern + caesura + the Chamberlain attribution, so
  #           `nabu links` shows the full per-line evidence and `nabu show`'s
  #           footer counts it ("linked: N meter") for free.
  #
  # The attribution rides the edge detail (the README's ask: "if you make …
  # extensive use … you should reference me (David Chamberlain) and this site").
  # A feature module serves no passages of its own, so the source-level P43-2
  # `credit:` line has no card to render on — the per-edge detail IS the honest
  # attribution surface here.
  #
  # == Resolution: match by TEXT, never by citation, never fuzzy
  #
  # The TSVs carry the Greek line VERBATIM but no citation column — the file
  # NAME carries the work and line ORDER is the line number. Rather than trust
  # that ordering against a specific edition, we resolve by TEXT: fold each TSV
  # line with the house grc search-form fold (ς→σ, downcase, strip accents/
  # breathings/iota-subscript) reduced to letters only — so elision spelling
  # (δ᾽ vs δ’), spacing and final punctuation cannot split a match — and look it
  # up EXACTLY against the same fold of the held passages within the mapped
  # work. Exact-key equality only: no fuzzy matching, ever (the plan's rule),
  # so a mismatch is censused, never guessed into a false edge.
  #
  # == Census (HONEST, first-sync owner report)
  #
  # Result carries files, mapped_works/unmapped_works and matched_lines/
  # unmatched_lines. An UNMAPPED file (no WORK_MAP entry) and a mapped work
  # whose target is not held both census their whole line count as unmatched —
  # nothing is silently dropped. `unknown_ids` surfaces unmatched_lines in the
  # generic sync tail ("?N unknown upstream" = N upstream scansion lines the
  # held catalog cannot place), the trismegistos census precedent.
  #
  # == Refresh mechanics (the standing producer contract)
  #
  # Edges are a pure function of (canonical tsv/ tree, catalog, code): a rerun
  # supersedes the prior (producer, scope) run atomically; a workdir WITHOUT the
  # tree (every parse-only sync before the first fetch) is a no-op that
  # supersedes nothing. Dropping the journal and re-running re-derives identical
  # edges (the rebuild-equivalence test).
  class HypotacticMeter
    PRODUCER = "hypotactic"
    KIND = "meter"
    CODE_VERSION = "hypotactic-meter/1 nabu/#{VERSION}".freeze

    # Where Adapters::Hypotactic#fetch lands the per-work TSVs.
    DIRNAME = "tsv"

    # The held grc lines are Perseus's; fold BOTH sides identically.
    MATCH_LANGUAGE = "grc"

    # The attribution the README asks for, carried on every meter edge.
    CREDIT = "Hypotactic (D. Chamberlain, hypotactic.com)"

    # == The filename → held-work map (evidence-commented; unmapped = censused)
    #
    # The value is a CTS work id "tlg0013.tlgNNN"; the producer resolves it to
    # every held grc document whose urn is urn:cts:greekLit:<work>.<edition>
    # (perseus-grc1/grc2 — whichever the box holds), so it never hard-codes an
    # edition token. Seeded for the ONE clear case the staged bytes give us:
    #
    #   HHAphrodite = the Homeric Hymn to Aphrodite. The Homeric Hymns are TLG
    #   author group tlg0013, one work id per hymn in traditional numbering —
    #   confirmed by the held Perseus fixture, whose tlg0013.tlg013 is titled
    #   "Hymn 13 To Demeter" (tlgNNN == Hymn NNN). The Hymn to Aphrodite is
    #   Hymn 5, so tlg0013.tlg005.
    #
    # Every OTHER Hypotactic TSV (the full mirror ships one per work) is left
    # UNMAPPED on purpose: it is censused as an unmapped work, never guessed.
    # The owner extends this map as more works are confirmed against the held
    # canon (grep the greekLit urns; one evidence line per entry).
    WORK_MAP = {
      "HHAphrodite" => "tlg0013.tlg005"
    }.freeze

    # The LibraryReferences::Result-shaped value the sync tail renders, plus the
    # honesty census. edges_written/refreshed/superseded map to the reference
    # tail's counters; unknown_ids surfaces unmatched_lines (class note).
    Result = Data.define(:scope, :run_id, :edges_written, :edges_refreshed,
                         :superseded_runs, :superseded_edges,
                         :files, :mapped_works, :unmapped_works,
                         :matched_lines, :unmatched_lines) do
      def unknown_ids = unmatched_lines
    end

    def initialize(catalog:, journal:)
      @catalog = catalog
      @journal = journal
    end

    # Re-derive every meter edge from <workdir>/tsv/*.tsv, superseding the prior
    # run. A missing tree is the honest no-op (class note).
    def run(slug, workdir: nil)
      dir = workdir && File.join(workdir, DIRNAME)
      files = dir && File.directory?(dir) ? Dir.glob(File.join(dir, "*.tsv")) : []
      return absent_result(slug) if files.empty?

      counts = Hash.new(0)
      run_id = superseded = nil
      @journal.transaction do
        superseded = Store::LinksJournal.supersede!(@journal, producer: PRODUCER, scope: slug)
        run_id = Store::LinksJournal.record_run!(@journal, producer: PRODUCER, scope: slug,
                                                           params: { kind: KIND }, code_version: CODE_VERSION)
        files.each { |path| write_file_edges(path, run_id, counts) }
      end
      build_result(slug, run_id, superseded, files.size, counts)
    end

    private

    def build_result(slug, run_id, superseded, files, counts)
      Result.new(scope: slug, run_id: run_id,
                 edges_written: counts[:inserted], edges_refreshed: counts[:refreshed],
                 superseded_runs: superseded[0], superseded_edges: superseded[1],
                 files: files, mapped_works: counts[:mapped], unmapped_works: counts[:unmapped],
                 matched_lines: counts[:inserted] + counts[:refreshed], unmatched_lines: counts[:unmatched])
    end

    def absent_result(slug)
      Result.new(scope: slug, run_id: nil, edges_written: 0, edges_refreshed: 0,
                 superseded_runs: 0, superseded_edges: 0, files: 0,
                 mapped_works: 0, unmapped_works: 0, matched_lines: 0, unmatched_lines: 0)
    end

    # One TSV file → edges for every line that matches a held passage of the
    # mapped work. Census, three states kept distinct:
    #   - no WORK_MAP entry           → unmapped_works++, all lines unmatched
    #   - mapped but work not held    → mapped_works++,   all lines unmatched
    #   - mapped and held             → mapped_works++,   line-by-line match
    def write_file_edges(path, run_id, counts)
      rows = parse_tsv(path)
      work = WORK_MAP[File.basename(path, ".tsv")]
      if work.nil?
        counts[:unmapped] += 1
        counts[:unmatched] += rows.size
        return
      end
      counts[:mapped] += 1
      index = held_line_index(work)
      return counts[:unmatched] += rows.size if index.empty?

      rows.each { |row| match_row(row, index, run_id, counts) }
    end

    def match_row(row, index, run_id, counts)
      passage_urn = index[match_key(row[:text])]
      return counts[:unmatched] += 1 if passage_urn.nil?

      outcome = Store::LinksJournal.write_edge!(
        @journal, from_urn: passage_urn, to_urn: meter_node(row[:meter]),
                  kind: KIND, score: nil, run_id: run_id, detail: edge_detail(row)
      )
      counts[outcome == :inserted ? :inserted : :refreshed] += 1
    end

    # { fold-key => passage_urn } over the held grc passages of every edition of
    # the mapped work. First writer wins on a key collision (a repeated line in
    # one poem is vanishingly rare and either witness is a true attestation).
    def held_line_index(work)
      like = "urn:cts:greekLit:#{work}.%"
      rows = @catalog[:passages]
             .join(:documents, id: Sequel[:passages][:document_id])
             .where(Sequel.like(Sequel[:documents][:urn], like))
             .where(Sequel[:passages][:language] => MATCH_LANGUAGE)
             .select(Sequel[:passages][:urn].as(:urn), Sequel[:passages][:text].as(:text))
             .all
      index = {}
      rows.each do |row|
        key = match_key(row[:text])
        index[key] ||= row[:urn] unless key.empty?
      end
      index
    end

    # The house grc fold reduced to letters only: ς→σ, downcase, accents/
    # breathings/iota-subscript stripped, then every non-letter (space, comma,
    # colon, elision koronis/apostrophe) removed — so only the bare letter
    # sequence decides a match.
    def match_key(text)
      Normalize.search_form(text, language: MATCH_LANGUAGE).gsub(/[^[:alpha:]]/, "")
    end

    # meter:<slug> — the grouping descriptor node ("dactylic hexameter" →
    # meter:dactylic-hexameter, "lyric" → meter:lyric).
    def meter_node(meter)
      slug = meter.to_s.strip.downcase.gsub(/[^a-z0-9]+/, "-").gsub(/\A-|-\z/, "")
      "meter:#{slug.empty? ? 'unknown' : slug}"
    end

    # scansion · caesura · credit — caesura omitted when the line carries none
    # (the lyric lines and a few hexameters leave it blank).
    def edge_detail(row)
      parts = ["scansion #{row[:scansion]}"]
      parts << "caesura #{row[:caesura]}" unless row[:caesura].empty?
      parts << CREDIT
      parts.join(" · ")
    end

    # The four TAB columns — line text · scansion · meter · caesura — verbatim
    # (only trailing whitespace trimmed per field). The filename carries the
    # work; line order is the line number, but we resolve by text, not order.
    # A row without the four columns is a malformed file → loud ParseError.
    def parse_tsv(path)
      File.readlines(path, encoding: "UTF-8").filter_map.with_index do |line, i|
        stripped = line.chomp
        next if stripped.strip.empty?

        cols = stripped.split("\t", -1)
        unless cols.size >= 4
          raise ParseError, "#{path}:#{i + 1}: expected 4 TAB columns (text, scansion, meter, caesura), " \
                            "got #{cols.size}"
        end
        { text: cols[0].strip, scansion: cols[1].strip, meter: cols[2].strip, caesura: cols[3].strip }
      end
    end
  end
end

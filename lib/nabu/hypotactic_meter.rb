# frozen_string_literal: true

require_relative "normalize"

module Nabu
  # The Greek METER enrichment producer (P44-6): Hypotactic's metrical
  # scansions (D. Chamberlain, hypotactic.com; mirror
  # github.com/Urdatorn/hypotactic) layered onto held Perseus lines as
  # per-passage `enrichments` rows — the SECOND producer on the P44-7 meter
  # seam (PedecertoScansions is the first): kind="meter", model="hypotactic",
  # so the two coexist under one kind and each rerun supersedes only its own
  # (kind, model) rows. Registered on the `hypotactic` feature module (kind:
  # module) and driven by SyncRunner#refresh_enrichments after every
  # hypotactic sync and by Rebuild#replay_enrichments on every rebuild.
  #
  # == Placement: the enrichments table (the P44-7 seam), argued
  #
  # A scansion is a PROPERTY OF ONE PASSAGE, not a relation between two urns —
  # the enrichments table is its home (never passages.annotations_json: that
  # row is Perseus's, written once through its own gateway at parse). The
  # table lives in catalog.sqlite3 and keys on re-minted passage_ids, so it
  # does not survive a rebuild passively; it is RE-DERIVED instead —
  # Rebuild#replay_enrichments re-runs this producer against canonical + the
  # fresh catalog, so meter is genuinely db = f(canonical) (the
  # rebuildability invariant satisfied by construction, the pedecerto
  # pattern). An earlier draft of this packet minted links-journal
  # kind="meter" edges to meter:<slug> descriptor nodes; superseded by the
  # orchestrator's seam ruling — an edge needs a second urn, and a meter
  # descriptor node was a synthetic one.
  #
  # == The payload (the TSV columns, verbatim)
  #
  #   { "meter"   => "dactylic hexameter",          (column 3)
  #     "pattern" => "-u u -uu -u u--- uu--",       (column 2, the scansion)
  #     "caesura" => "feminine penthemimeral",      (column 4; ABSENT when the
  #                                                  line carries none)
  #     "credit"  => CREDIT }
  #
  # "pattern" (not "scansion") so the shared `show` meter line — which renders
  # payload["meter"] + payload["pattern"] + the model name — carries the
  # scansion with zero display changes: `meter: dactylic hexameter -u u -uu …
  # (hypotactic)`. The caesura and the Chamberlain credit ride the payload for
  # any richer consumer (the show line itself cannot carry them — recorded in
  # the sources.yml row and docs/02-sources.md).
  #
  # The credit honors the mirror README's ask ("if you make significant or
  # extensive use of it in published work you should reference me (David
  # Chamberlain) and this site (hypotactic.com)") — a feature module serves no
  # passages of its own, so the P43-2 source-level credit: seam has no card to
  # render on; the payload is where Hypotactic data actually lives.
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
  # so a mismatch is censused, never guessed into a false enrichment.
  #
  # == Census (HONEST, first-sync owner report)
  #
  # Result mirrors PedecertoScansions::Result — files, lines_read,
  # matched/unmatched (LINE counts), mapped_works/unmapped_works, superseded —
  # so the shared sync tail renders both meter producers identically ("meter N
  # lines matched, M unmatched (K works of L)"). An UNMAPPED file (no WORK_MAP
  # entry) and a mapped work with no held witness both census their whole line
  # count as unmatched — nothing is silently dropped.
  #
  # == Refresh mechanics (the standing producer contract)
  #
  # Rows are a pure function of (canonical tsv/ tree, catalog, code): a rerun
  # supersedes this producer's prior (kind, model) rows; a workdir WITHOUT the
  # tree (every parse-only sync before the first fetch) is a no-op that
  # supersedes nothing, so a standing meter layer survives. Superseding and
  # re-running yields identical rows (the rebuild-equivalence test).
  class HypotacticMeter
    PRODUCER = "hypotactic"
    KIND = "meter"
    MODEL = "hypotactic"
    CODE_VERSION = "hypotactic-meter/2 nabu/#{VERSION}".freeze

    # Where Adapters::Hypotactic#fetch lands the per-work TSVs.
    DIRNAME = "tsv"

    # The held grc lines are Perseus's; fold BOTH sides identically.
    MATCH_LANGUAGE = "grc"

    # The attribution the README asks for, carried in every payload.
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

    # One refresh's census — the PedecertoScansions::Result shape, field for
    # field, so the shared sync/rebuild tail renders both meter producers
    # identically. matched/unmatched are LINE counts.
    Result = Data.define(:scope, :files, :lines_read, :matched, :unmatched,
                         :mapped_works, :unmapped_works, :superseded) do
      def initialize(files: 0, lines_read: 0, matched: 0, unmatched: 0,
                     mapped_works: 0, unmapped_works: 0, superseded: 0, **rest)
        super
      end
    end

    def initialize(catalog:)
      @catalog = catalog
    end

    # Re-derive every hypotactic meter row from <workdir>/tsv/*.tsv,
    # superseding this producer's prior (kind, model) rows. A missing tree is
    # the honest no-op that supersedes nothing (class note).
    def run(scope, workdir: nil)
      files = corpus_files(workdir)
      return Result.new(scope: scope) if files.empty?

      counts = Hash.new(0)
      @catalog.transaction do
        counts[:superseded] = Store::Enrichment.supersede!(@catalog, kind: KIND, model: MODEL)
        files.each { |path| ingest_file(path, counts) }
      end
      Result.new(scope: scope, files: files.size,
                 lines_read: counts[:lines], matched: counts[:matched], unmatched: counts[:unmatched],
                 mapped_works: counts[:mapped_works], unmapped_works: counts[:unmapped_works],
                 superseded: counts[:superseded])
    end

    private

    def corpus_files(workdir)
      return [] unless workdir

      # Dir.glob returns a sorted list (Ruby 3+), so iteration order is stable.
      Dir.glob(File.join(workdir, DIRNAME, "*.tsv"))
    end

    # One TSV file → meter rows for every line matched against a held passage
    # of the mapped work. Census, three states kept distinct:
    #   - no WORK_MAP entry           → unmapped_works++, all lines unmatched
    #   - mapped but work not held    → unmapped_works++, all lines unmatched
    #     (the pedecerto rule: a "mapped work" is one that resolved ≥1 line)
    #   - mapped and held             → mapped_works++,   line-by-line match
    def ingest_file(path, counts)
      rows = parse_tsv(path)
      counts[:lines] += rows.size
      work = WORK_MAP[File.basename(path, ".tsv")]
      index = work ? held_line_index(work) : {}
      before = counts[:matched]
      rows.each do |row|
        passage_id = index[match_key(row[:text])]
        if passage_id
          write_meter(passage_id, row, counts)
        else
          counts[:unmatched] += 1
        end
      end
      counts[counts[:matched] > before ? :mapped_works : :unmapped_works] += 1
    end

    def write_meter(passage_id, row, counts)
      Store::Enrichment.write!(@catalog, passage_id: passage_id, kind: KIND, model: MODEL,
                                         model_version: CODE_VERSION, payload: payload_for(row))
      counts[:matched] += 1
    end

    # The stored payload (class note): meter + pattern feed the shared show
    # line verbatim; caesura only when the line carries one; the Chamberlain
    # credit always.
    def payload_for(row)
      payload = { "meter" => row[:meter], "pattern" => row[:scansion] }
      payload["caesura"] = row[:caesura] unless row[:caesura].empty?
      payload["credit"] = CREDIT
      payload
    end

    # { fold-key => passage_id } over the held grc passages of every edition of
    # the mapped work. First writer wins on a key collision (a repeated line in
    # one poem is vanishingly rare and either witness is a true attestation).
    def held_line_index(work)
      like = "urn:cts:greekLit:#{work}.%"
      rows = @catalog[:passages]
             .join(:documents, id: Sequel[:passages][:document_id])
             .where(Sequel.like(Sequel[:documents][:urn], like))
             .where(Sequel[:passages][:language] => MATCH_LANGUAGE)
             .select(Sequel[:passages][:id].as(:passage_id), Sequel[:passages][:text].as(:text))
             .all
      index = {}
      rows.each do |row|
        key = match_key(row[:text])
        index[key] ||= row[:passage_id] unless key.empty?
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

    # The four TAB columns — line text · scansion · meter · caesura — verbatim
    # (only surrounding whitespace trimmed per field). The filename carries the
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

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
    # Grown P45-5 to the full unambiguous held intersection. Three value
    # shapes, all resolved to every held grc EDITION via the urn prefix
    # urn:cts:greekLit:<value>. (never a hard-coded edition token):
    #
    #   "tlg0012.tlg001"    — one work; several files may share it (the
    #                         per-book iliadN/odysseyN files — resolution is
    #                         by TEXT, so the book split costs nothing);
    #   ["tlgA.tlgX", ...]  — one TSV spanning SEVERAL held works (nicander =
    #                         Theriaca + Alexipharmaca in one file);
    #   "tlg0013"           — a TEXTGROUP: one TSV spanning a whole collection
    #                         (HHymns = the Homeric Hymns not covered by the
    #                         four dedicated hymn files).
    #
    # EVIDENCE DISCIPLINE (P45-5): every entry was verified against the REAL
    # catalog on 2026-07-25 — the held document's title matches the filename's
    # work, recorded per entry. Text-matching means a wrong entry can only
    # census (no citation collision exists to mint a false row), but the
    # don't-guess doctrine still holds: an id whose identification is not
    # evident stays OUT (the censused-out note below).
    #
    # The original seed's evidence, still the naming key for the hymn files:
    # the Homeric Hymns are TLG group tlg0013, one work per hymn in
    # traditional numbering — the held tlg0013.tlg013 is titled "Hymn 13 to
    # Demeter" (tlgNNN == Hymn NNN).
    WORK_MAP = {
      # Homer — held "Iliad" tlg0012.tlg001 / "Odyssey" tlg0012.tlg002; the
      # mirror ships one TSV per book (iliad1..24, odyssey1..24).
      **(1..24).to_h { |n| ["iliad#{n}", "tlg0012.tlg001"] },
      **(1..24).to_h { |n| ["odyssey#{n}", "tlg0012.tlg002"] },
      "batmumach" => "tlg1220.tlg001", # held "Batrachomyomachia" (the frog-mouse battle)
      # The Homeric Hymns (group evidence above).
      "HHAphrodite" => "tlg0013.tlg005", # held "Hymn 5 to Aphrodite" (the long hymn)
      "HHApollo" => "tlg0013.tlg003",    # held "Hymn 3 to Delian and Pythian Apollo"
      "HHDemeter" => "tlg0013.tlg002",   # held "Hymn 2 to Demeter"
      "HHermes" => "tlg0013.tlg004",     # held "Hymn 4 to Hermes"
      "HHymns" => "tlg0013", # the collection file (its first line is Hymn 1 to
      #   Dionysus 1.1) — textgroup grain covers every held hymn; the shared
      #   closing formulae dedupe via the one-row-per-passage guard below
      # Hesiod — held under tlg0020.
      "theogony" => "tlg0020.tlg001",     # held "Theogony"
      "worksanddays" => "tlg0020.tlg002", # held "Works and Days"
      "scutum" => "tlg0020.tlg003",       # held "Shield of Heracles"
      # Aeschylus — held under tlg0085 (perseus-grc2 AND 1st1K-grc1 editions;
      # the urn-prefix resolution takes both).
      "persians" => "tlg0085.tlg002",   # held "Persians"
      "prometheus" => "tlg0085.tlg003", # held "Prometheus Bound"
      "seven" => "tlg0085.tlg004",      # held "Seven Against Thebes"
      # Pindar — held Olympian/Pythian/Nemean/Isthmean odes, line-grain.
      "olympians" => "tlg0033.tlg001", # held "Olympian"
      "pythians" => "tlg0033.tlg002",  # held "Pythian"
      "nemeans" => "tlg0033.tlg003",   # held "Nemean"
      "isthmians" => "tlg0033.tlg004", # held "Isthmean"
      # Hellenistic epos and didactic.
      **(1..4).to_h { |n| ["apollonius#{n}", "tlg0001.tlg001"] }, # held "Argonautica"
      #   (Apollonius Rhodius; one TSV per book)
      **(1..4).to_h { |n| ["theoc#{n}", "tlg0005.tlg001"] }, # held "Εἰδύλλια"
      #   (Theocritus' Idylls; the four files partition the collection)
      "nicander" => %w[tlg0022.tlg001 tlg0022.tlg002], # ONE file spans both held
      #   Nicander works: "Theriaca" + "Alexipharmaca" (1st1K editions)
      "ophal" => "tlg0023.tlg001", # held "Halieutica" (Oppian)
      "opcyn" => "tlg0024.tlg001", # held "Cynegetica" (ps.-Oppian of Apamea)
      # Callimachus — held hymns (perseus-grc4) and epigrams.
      "callimachusHymns" => %w[tlg0533.tlg015 tlg0533.tlg016 tlg0533.tlg017
                               tlg0533.tlg018 tlg0533.tlg019 tlg0533.tlg020],
      #   held "Hymn to Zeus/Apollo/Artemis/Delos/Athena/Demeter" — one TSV,
      #   six held works
      "callimachusEp" => %w[tlg0533.tlg003 tlg0533.tlg004], # held "Epigrams" +
      #   "Epigrams and Fragments" (two held editions-as-works)
      # Bucolic minora — one TSV per AUTHOR, several held works each.
      "bion" => "tlg0036", # held Bion: "Epitaphius Adonis", "Epithalamium
      #   Achillis et Deidameiae", "Fragmenta" — textgroup grain
      "moschus" => "tlg0035" # held Moschus: "Eros Drapeta", "Europa",
      #   "Epitaphius Bios", "Megara", "Fragmenta" — textgroup grain
    }.freeze

    # == Censused OUT (P45-5), so the next grower need not re-litigate ==
    #
    # Evaluated against the held canon and excluded — the works are simply
    # not held: aratus (no Phaenomena), cleanthes (no Hymn to Zeus),
    # colluthus, lycophron (tlg0082 in the catalog is Apollonius Dyscolus's
    # grammar, not the Alexandra), semonides, solon (tlg0007.tlg007 is
    # Plutarch's LIFE of Solon), theognis, tyrtaeus, tryph (Tryphiodorus).
    # They census as unmapped works until the canon grows.

    # One refresh's census — the PedecertoScansions::Result shape, field for
    # field, so the shared sync/rebuild tail renders both meter producers
    # identically. matched/unmatched are LINE counts.
    Result = Data.define(:scope, :files, :lines_read, :matched, :unmatched,
                         :mapped_works, :unmapped_works, :superseded, :malformed_files) do
      def initialize(files: 0, lines_read: 0, matched: 0, unmatched: 0,
                     mapped_works: 0, unmapped_works: 0, superseded: 0,
                     malformed_files: [], **rest)
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
      malformed = []
      @index_cache = {}   # WORK_MAP value => fold index, shared by per-book files
      @written_ids = {}   # passage_id => true, the one-row-per-passage guard
      @catalog.transaction do
        counts[:superseded] = Store::Enrichment.supersede!(@catalog, kind: KIND, model: MODEL)
        # The P44-i3b census (the pedecerto AVSON incident, symmetric): a
        # file that will not parse is censused BY NAME and skipped, never
        # fatal to the batch. parse_tsv reads the whole file before any
        # write, so a malformed file contributes no counts and no rows.
        files.each do |path|
          ingest_file(path, counts)
        rescue ParseError
          malformed << File.basename(path)
        end
      end
      Result.new(scope: scope, files: files.size,
                 lines_read: counts[:lines], matched: counts[:matched], unmatched: counts[:unmatched],
                 mapped_works: counts[:mapped_works], unmapped_works: counts[:unmapped_works],
                 superseded: counts[:superseded], malformed_files: malformed)
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

    # One meter row PER PASSAGE per run (P45-5): Homer repeats whole formulaic
    # lines verbatim (Il. 1.372-375 = 1.13-16), and with per-book files sharing
    # one work index — plus the HHymns collection overlapping the dedicated
    # hymn files on the shared closing formulae — a repeated line resolves to
    # the same first-occurrence passage more than once. The line still COUNTS
    # as matched (it did resolve, and the scansion of an identical line is
    # identical), but the passage keeps ONE row — never a duplicate under the
    # same (kind, model). Reset per run, so reruns stay byte-identical.
    def write_meter(passage_id, row, counts)
      counts[:matched] += 1
      return if @written_ids[passage_id]

      @written_ids[passage_id] = true
      Store::Enrichment.write!(@catalog, passage_id: passage_id, kind: KIND, model: MODEL,
                                         model_version: CODE_VERSION, payload: payload_for(row))
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

    # { fold-key => passage_id } over the held grc passages of every edition
    # of the mapped work(s) — a WORK_MAP value verbatim: one work id, an array
    # of them, or a bare textgroup (the urn LIKE prefix covers all three, the
    # WORK_MAP note). First occurrence wins on a key collision (a repeated
    # formulaic line — either witness is a true attestation of the same
    # text). Memoized per run under the map value, so the 24 per-book Homer
    # files build their shared work index once, not 24 times.
    def held_line_index(works)
      @index_cache[works] ||= begin
        index = {}
        held_line_rows(works).each do |row|
          key = match_key(row[:text])
          index[key] ||= row[:passage_id] unless key.empty?
        end
        index
      end
    end

    def held_line_rows(works)
      likes = Array(works).map { |work| Sequel.like(Sequel[:documents][:urn], "urn:cts:greekLit:#{work}.%") }
      @catalog[:passages]
        .join(:documents, id: Sequel[:passages][:document_id])
        .where(Sequel.|(*likes))
        .where(Sequel[:passages][:language] => MATCH_LANGUAGE)
        .select(Sequel[:passages][:id].as(:passage_id), Sequel[:passages][:text].as(:text))
        .all
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

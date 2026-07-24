# frozen_string_literal: true

require "nokogiri"

module Nabu
  # The METER enrichment producer (P44-7): pedecerto.eu's XML scansions of the
  # Latin verse corpus, attached as a per-passage meter layer onto the held
  # Perseus-Latin texts. The FIRST enricher to write the enrichments table
  # (kind="meter") — the reference-producer pattern (KitabTextReuse,
  # TrismegistosCrosswalk) applied to the enrichment seam instead of the links
  # journal, because a scansion is a PROPERTY OF ONE PASSAGE, not an edge
  # between two urns (a links edge needs from≠to; there is no second urn).
  #
  # == The upstream shape (fixture-verified)
  #
  # The pedecerto feature module's fetch unpacks allpedecertoscans.zip under
  # canonical/pedecerto/allpedecertoscans/<AUTHOR>-<work>.xml — one file per
  # author-work. Each is
  #
  #   <document><head><author/><title/>…</head>
  #     <body>
  #       <division title="1">                        (book; absent in single-book works)
  #         <line name="1" meter="H" pattern="DSDS">  (line number · meter code · foot pattern)
  #           <word sy="1A" wb="CM">Quid</word> …     (per-word syllable positions + boundary)
  #
  # meter "H" is hexameter (227,791 of ~300k lines); "P" pentameter (elegiac
  # second verse); ~20 other verse codes. The scansion we store per line is
  # {meter, pattern, words:[{text, sy, wb?}]} — verbatim, canonical-means-
  # canonical (the nc license's no-substantial-alteration duty).
  #
  # == Citation → held passage (the resolution, and why the live match is partial)
  #
  # pedecerto cites by book+line: division/@title is the book number, line/@name
  # the line within it, so the pedecerto citation is "book.line" (or bare "line"
  # for a single-book work). Perseus mints its passage urn as
  # "<edition urn>:<book.line>" (EpidocParser: "#{urn}:#{citation}"), so the
  # two citation schemes coincide EXACTLY — a held Vergil Georgics line 1.1 is
  # urn:cts:latinLit:phi0690.phi002.<edition>:1.1.
  #
  # What does NOT coincide is the WORK IDENTITY: pedecerto names works by its own
  # <AUTHOR>-<work> file id (VERG-geor), Perseus by CTS textgroup.work (phi0690.
  # phi002). No shared id exists in the data, so the bridge is an EXPLICIT
  # crosswalk (WORK_CROSSWALK below) — never fuzzy author/title matching (the
  # don't-guess doctrine). The crosswalk is a SEED of the major held hexameter
  # works, derived from the standard PHI/CTS numbering; the owner extends it.
  # Every entry is made SAFE by the resolution guard (the trismegistos
  # precedent): a wrong tg.work simply resolves to no held passage and is
  # CENSUSED as unmatched — it can never mint a false enrichment. So the live
  # match rate is bounded by (a) which crosswalked works the owner actually
  # holds in perseus-latin and (b) line-numbering alignment between the two
  # editions; both are reported honestly, never assumed.
  #
  # == Placement + rebuild-honesty (the enrichments table, re-derived)
  #
  # Rows land in the catalog's `enrichments` table, kind="meter", model=
  # "pedecerto" (the producer id — so a second meter producer coexists and a
  # rerun supersedes only its own rows). The table keys on passage_id (re-minted
  # every rebuild) and lives in catalog.sqlite3 (dropped every rebuild), so
  # unlike the urn-keyed links journal it does NOT survive a rebuild passively.
  # It is instead RE-DERIVED: SyncRunner runs this producer after every
  # pedecerto sync, and Rebuild#replay_enrichments re-runs it against canonical
  # + the fresh catalog — so meter is genuinely db = f(canonical), the
  # rebuildability invariant satisfied by construction. Idempotent: supersede
  # then re-insert yields byte-identical rows (the rebuild-equivalence test).
  class PedecertoScansions
    PRODUCER = "pedecerto"
    KIND = "meter"
    MODEL = "pedecerto"
    CODE_VERSION = "pedecerto-scansions/1 nabu/#{VERSION}".freeze

    # Where Adapters::Pedecerto's ZipFetch unpacks the corpus (the zip's single
    # top directory), under the source's canonical workdir.
    DIRNAME = "allpedecertoscans"

    # The Perseus-Latin CTS namespace every held Latin edition urn carries.
    CTS_PREFIX = "urn:cts:latinLit:"

    # A clean citation component — Perseus book/line numbers are bare integers.
    # A messier pedecerto line name ("1a", "[[1]]", "0-1", an epigraphic
    # concordance division) resolves to no Perseus passage and is censused.
    CLEAN = /\A\d+\z/

    # pedecerto <AUTHOR>-<work> file id → Perseus CTS "textgroup.work" — the
    # explicit bridge (class note). SEED: the major held hexameter (+ Ibis,
    # elegiac) works, standard PHI/CTS numbering, confirmed at first sync (a
    # wrong entry mints nothing — the resolution guard). Owner extends it.
    WORK_CROSSWALK = {
      "VERG-eclo" => "phi0690.phi001", # Vergil, Eclogues
      "VERG-geor" => "phi0690.phi002", # Vergil, Georgics
      "VERG-aene" => "phi0690.phi003", # Vergil, Aeneid
      "LVCR-rena" => "phi0472.phi001", # Lucretius, De Rerum Natura
      "OV-meta" => "phi0959.phi006", # Ovid, Metamorphoses
      "OV-fast" => "phi0959.phi007", # Ovid, Fasti
      "OV-ibis" => "phi0959.phi010", # Ovid, Ibis (elegiac — H/P couplets)
      "LVCAN-phar" => "phi0917.phi001", # Lucan, Bellum Civile (Pharsalia)
      "STAT-theb" => "phi1020.phi001", # Statius, Thebaid
      "STAT-achi" => "phi1020.phi002", # Statius, Achilleid
      "IVV-satu" => "phi1276.phi001", # Juvenal, Saturae
      "PERS-satu" => "phi0969.phi001", # Persius, Saturae
      "SIL-puni" => "phi1345.phi001" # Silius Italicus, Punica
    }.freeze

    # One refresh's census (the producer Result shape — a sync/rebuild tail
    # renders it like the links producers' Result). +matched+/+unmatched+ are
    # LINE counts (the honest coverage number the packet demands); +mapped_works+
    # are crosswalked files that resolved ≥1 line, +unmapped_works+ crosswalked
    # files present on disk with no held witness (or no crosswalk entry).
    Result = Data.define(:scope, :files, :lines_read, :matched, :unmatched,
                         :mapped_works, :unmapped_works, :superseded) do
      def initialize(files: 0, lines_read: 0, matched: 0, unmatched: 0,
                     mapped_works: 0, unmapped_works: 0, superseded: 0, **rest)
        super
      end
    end

    def initialize(catalog:)
      @catalog = catalog
      @doc_cache = {} # tg.work => [doc_urns] resolved from the catalog, per run
    end

    # Re-derive every meter enrichment from <workdir>/allpedecertoscans/*.xml,
    # superseding this producer's prior rows. A missing tree is the honest
    # no-op that supersedes nothing (every parse-only sync before the first
    # fetch, and any box without the corpus).
    def run(scope, workdir: nil)
      files = corpus_files(workdir)
      # A workdir WITHOUT the corpus (every parse-only sync before the first
      # fetch, any box that never synced) is the honest no-op: it supersedes
      # NOTHING, so a standing meter layer survives (the links-producer
      # contract). Only a real corpus re-derives, superseding the prior run.
      return Result.new(scope: scope) if files.empty?

      counts = Hash.new(0)
      @doc_cache = {}
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
      Dir.glob(File.join(workdir, DIRNAME, "*.xml"))
    end

    # One <AUTHOR>-<work>.xml → its lines' meter rows. A file with no crosswalk
    # entry, or one whose crosswalked work we do not hold, still has every line
    # COUNTED (unmatched) — coverage is never silently smaller than the corpus.
    def ingest_file(path, counts)
      file_id = File.basename(path, ".xml")
      tg_work = WORK_CROSSWALK[file_id]
      doc_urns = tg_work ? held_documents(tg_work) : []
      before = counts[:matched]

      each_line(path) do |citation, payload|
        counts[:lines] += 1
        passage_id = citation && resolve_passage(doc_urns, citation)
        if passage_id
          write_meter(passage_id, payload, counts)
        else
          counts[:unmatched] += 1
        end
      end
      counts[counts[:matched] > before ? :mapped_works : :unmapped_works] += 1
    end

    # Yield [citation, payload] for every <line> in one file. citation is
    # "book.line" under a numeric <division>, bare "line" with none, or nil when
    # either component is unclean (→ unmatched). One <AUTHOR>-<work>.xml parses
    # by DOM (the biggest, Statius' Thebaid, is 3.1 MB — under the ~5 MB
    # Reader threshold; each file's tree is freed before the next). A malformed
    # file raises ParseError (loud, per-file — the batch quarantines it, never a
    # silent drop) exactly like the adapters.
    def each_line(path)
      doc = Nokogiri::XML(File.read(path, encoding: "UTF-8"), &:strict)
      doc.xpath("//body//line").each do |line|
        division = line.at_xpath("ancestor::division")&.[]("title")
        yield citation_for(division, line["name"]), line_payload(line)
      end
    rescue Nokogiri::XML::SyntaxError => e
      raise ParseError, "#{path}: malformed pedecerto XML: #{e.message}"
    end

    # One <line> → {meter, pattern, words}. words carries each token's text
    # (verbatim, NFC at the boundary) with its syllable-position + word-boundary
    # attributes — the scansion, unaltered (the nc no-alteration duty).
    def line_payload(line)
      words = line.xpath("./word").map do |w|
        entry = { "text" => Normalize.nfc(w.text.to_s), "sy" => w["sy"].to_s }
        entry["wb"] = w["wb"] if w["wb"]
        entry["mf"] = w["mf"] if w["mf"]
        entry
      end
      { "meter" => line["meter"].to_s, "pattern" => line["pattern"].to_s, "words" => words }
    end

    # "book.line" / "line" when both components are clean integers, else nil.
    def citation_for(division, name)
      return nil unless name && CLEAN.match?(name)

      if division.nil?
        name
      elsif CLEAN.match?(division)
        "#{division}.#{name}"
      end
    end

    # Held Latin editions of a CTS "textgroup.work": catalog documents whose urn
    # starts urn:cts:latinLit:<tg.work>. and whose language is lat (never an
    # English translation that shares the textgroup). Cached per run.
    def held_documents(tg_work)
      @doc_cache.fetch(tg_work) do
        prefix = "#{CTS_PREFIX}#{tg_work}."
        @doc_cache[tg_work] = @catalog[:documents]
                              .where(Sequel.like(:urn, "#{prefix}%"))
                              .where(language: "lat")
                              .select_map(:urn)
      end
    end

    # The held passage_id for a citation across a work's editions, or nil when
    # no held edition carries that line (the citation-mismatch / unheld case).
    def resolve_passage(doc_urns, citation)
      doc_urns.each do |doc_urn|
        id = @catalog[:passages].where(urn: "#{doc_urn}:#{citation}").get(:id)
        return id if id
      end
      nil
    end

    def write_meter(passage_id, payload, counts)
      Store::Enrichment.write!(@catalog, passage_id: passage_id, kind: KIND, model: MODEL,
                                         model_version: CODE_VERSION, payload: payload)
      counts[:matched] += 1
    end
  end
end

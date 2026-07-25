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

    # pedecerto <AUTHOR>-<work> file id → the held Perseus CTS work — the
    # explicit bridge (class note), grown P45-5 to the full unambiguous held
    # intersection. Two value shapes:
    #
    #   "tg.work"           — the file's citations already meet Perseus's
    #                         (same depth: bare line, or division.line);
    #   ["tg.work", "book"] — a PER-BOOK file ("elegiae 1"): its divisions
    #                         number the POEMS of that book while Perseus
    #                         cites book.poem.line, so the book component
    #                         from the FILENAME is prepended to every
    #                         citation ("1" + "2.5" → "1.2.5").
    #
    # EVIDENCE DISCIPLINE (P45-5): every entry was verified against the REAL
    # catalog on 2026-07-25 — the held document's title matches the pedecerto
    # <author>/<title> head, AND the two citation schemes were confirmed to
    # meet by sampling live passage urns against the file's division/line
    # structure. The per-entry comment records the held title. An id whose
    # identification OR citation alignment could not be verified stays OUT
    # (the censused-out note below the map) — never guessed. A wrong entry
    # still mints nothing for works we do not hold (the resolution guard),
    # but a held-work entry with coinciding citation shapes CAN mint false
    # rows — the original seed's LVCR-rena → phi0472.phi001 did exactly that
    # (phi0472 is Catullus, whose poem.line citations collide with DRN's
    # book.line), which is why shape verification is part of the discipline.
    WORK_CROSSWALK = {
      # -- the original seed, two entries corrected against the catalog ------
      "VERG-eclo" => "phi0690.phi001", # held "Eclogues" (poem.line both sides)
      "VERG-geor" => "phi0690.phi002", # held "Georgics" (book.line both sides)
      "VERG-aene" => "phi0690.phi003", # held "Aeneid" (book.line both sides)
      "LVCR-rena" => "phi0550.phi001", # held "De Rerum Natura" — P45-5 FIX: the seed
      #   said phi0472.phi001, but the catalog titles that "Carmina" (Catullus);
      #   PHI numbers Lucretius 0550. The old entry minted false meter rows on
      #   Catullus poems 1-6 (colliding poem.line citations).
      "OV-meta" => "phi0959.phi006", # held "Metamorphoses" (book.line)
      "OV-fast" => "phi0959.phi007", # held "Fasti" (book.line)
      "OV-ibis" => "phi0959.phi010", # held "Ibis" (bare line, elegiac H/P)
      "LVCAN-phar" => "phi0917.phi001", # held "Civil War" (book.line)
      "STAT-theb" => "phi1020.phi001", # held "Thebais" (book.line)
      "STAT-achi" => "phi1020.phi003", # held "Achilleis" — P45-5 FIX: the seed said
      #   phi1020.phi002, but the catalog titles that "Silvae" (3-level citations,
      #   so the old entry matched nothing — censused, exactly as designed).
      "IVV-satu" => "phi1276.phi001", # held "Saturae" (Juvenal; satire.line)
      "PERS-satu" => "phi0969.phi001", # held "Saturae" (Persius; satire.line)
      "SIL-puni" => "phi1345.phi001", # held "Punica" (book.line)
      # -- P45-5 growth: same-depth citations, held title verified -----------
      "CATVLL-carm" => "phi0472.phi001", # held "Carmina" (Catullus; poem.line both)
      "OV-epis" => "phi0959.phi002", # held "Epistulae" (Heroides; file head "epistulae
      #   heroides"; poem.line both — Perseus phi0959.phi002 cites 1.1)
      "OV-medi" => "phi0959.phi003", # held "Medicamina faciei femineae" (bare line both)
      "OV-aram" => "phi0959.phi004", # held "Ars Amatoria" (book.line both)
      "OV-reme" => "phi0959.phi005", # held "Remedia amoris" (bare line both)
      "HOR-epod" => "phi0893.phi003", # held "Epodi" (epode.line both)
      "HOR-arpo" => "phi0893.phi006", # held "Ars Poetica" (file "arpo"; bare line both)
      "SEN-mede" => "phi1017.phi004", # held "Medea" (Seneca; bare line both)
      "SEN-oedi" => "phi1017.phi006", # held "Oedipus" (Seneca; bare line both)
      "VAL_FL-argo" => "phi1035.phi001", # held "Argonautica" (Valerius Flaccus; book.line both)
      "CLAVD-cami" => "stoa0089.stoa001", # held "Carminum minorum corpusculum" (poem.line both)
      "CLAVD-gild" => "stoa0089.stoa002", # held "de bello Gildonico" (one book; bare line both)
      "CLAVD-stil" => "stoa0089.stoa004", # held "de consulatu Stilichonis" (book.line both)
      "CLAVD-eutr" => "stoa0089.stoa008", # held "In Eutropium" (book.line both)
      "CLAVD-hon4" => "stoa0089.stoa011", # held "Panegyricus de quarto consulatu Honorii
      #   Augusti" (bare line both — unlike hon3/hon6, whose Perseus editions
      #   carry a praefatio middle level; see the censused-out note)
      "CLAVD-prob" => "stoa0089.stoa014", # held "Panegyricus dictus Probino et Olybrio
      #   consulibus" (bare line both)
      "PRVD-peri" => "stoa0238.stoa001", # held "Liber Peristephanon" (poem.line both)
      "PRVD-ditt" => "stoa0238.stoa008", # held "Dittochaeon" (bare line both)
      "AVSON-cupi" => "stoa0045.stoa005", # held "Cupido Cruciatus" (bare line both)
      "AVSON-epic" => "stoa0045.stoa009", # held "Epicedion in Patrem" (bare line both)
      "AVSON-gene" => "stoa0045.stoa013", # held "Genethliacon ad Ausonium Nepotem" (bare both)
      "AVSON-here" => "stoa0045.stoa006", # held "De Herediolo" (bare line both)
      "AVSON-ludu" => "stoa0045.stoa018", # held "Ludus Septem Sapientum" (bare line both)
      "AVSON-pasc" => "stoa0045.stoa027", # held "Versus Paschales Prosodic" (bare line both)
      # -- P45-5 growth: per-book files, [work, book-prefix] -----------------
      # Propertius — held "Elegiae" phi0620.phi001, Perseus cites book.poem.line;
      # the four files are "elegiae 1".."elegiae 4", divisions = poems.
      "PROP-ele1" => ["phi0620.phi001", "1"],
      "PROP-ele2" => ["phi0620.phi001", "2"],
      "PROP-ele3" => ["phi0620.phi001", "3"],
      "PROP-ele4" => ["phi0620.phi001", "4"],
      # Tibullus — held "Elegiae" phi0660.phi001 spans books 1-3 (book 3 = the
      # Corpus Tibullianum continuation, verified held); same 3-level scheme.
      "TIB-ele1" => ["phi0660.phi001", "1"],
      "TIB-ele2" => ["phi0660.phi001", "2"],
      "TIB-ele3" => ["phi0660.phi001", "3"],
      # Ovid, Amores — held phi0959.phi001, books 1-3 (the prefatory epigram is
      # OV-amo0, censused: the held edition has no matching component).
      "OV-amo1" => ["phi0959.phi001", "1"],
      "OV-amo2" => ["phi0959.phi001", "2"],
      "OV-amo3" => ["phi0959.phi001", "3"],
      # Ovid, Tristia — held phi0959.phi008. Book 2 is ONE poem: the file has
      # no divisions and Perseus cites it 2.1.line, so its prefix is "2.1".
      "OV-tri1" => ["phi0959.phi008", "1"],
      "OV-tri2" => ["phi0959.phi008", "2.1"],
      "OV-tri3" => ["phi0959.phi008", "3"],
      "OV-tri4" => ["phi0959.phi008", "4"],
      "OV-tri5" => ["phi0959.phi008", "5"],
      # Ovid, Epistulae ex Ponto — held "Ex Ponto" phi0959.phi009, books 1-4.
      "OV-pon1" => ["phi0959.phi009", "1"],
      "OV-pon2" => ["phi0959.phi009", "2"],
      "OV-pon3" => ["phi0959.phi009", "3"],
      "OV-pon4" => ["phi0959.phi009", "4"],
      # Horace, Odes — held "Odes" phi0893.phi001, book.poem.line. Upstream
      # ships only "carmina 1" and "carmina 4" (no car2/car3 files on disk).
      "HOR-car1" => ["phi0893.phi001", "1"],
      "HOR-car4" => ["phi0893.phi001", "4"],
      # Horace, Satires + Epistles — held "Satires" phi0893.phi004 and
      # "Epistulae" phi0893.phi005, book.poem.line; per-book files.
      "HOR-sat1" => ["phi0893.phi004", "1"],
      "HOR-sat2" => ["phi0893.phi004", "2"],
      "HOR-epi1" => ["phi0893.phi005", "1"],
      "HOR-epi2" => ["phi0893.phi005", "2"],
      # Martial — held "Epigrammata" phi1294.phi002, book.epigram.line, books
      # 1-14 all verified held (13 Xenia / 14 Apophoreta included; the Liber
      # Spectaculorum is NOT in the held edition — MART-spec censused).
      "MART-ep01" => ["phi1294.phi002", "1"],
      "MART-ep02" => ["phi1294.phi002", "2"],
      "MART-ep03" => ["phi1294.phi002", "3"],
      "MART-ep04" => ["phi1294.phi002", "4"],
      "MART-ep05" => ["phi1294.phi002", "5"],
      "MART-ep06" => ["phi1294.phi002", "6"],
      "MART-ep07" => ["phi1294.phi002", "7"],
      "MART-ep08" => ["phi1294.phi002", "8"],
      "MART-ep09" => ["phi1294.phi002", "9"],
      "MART-ep10" => ["phi1294.phi002", "10"],
      "MART-ep11" => ["phi1294.phi002", "11"],
      "MART-ep12" => ["phi1294.phi002", "12"],
      "MART-ep13" => ["phi1294.phi002", "13"],
      "MART-ep14" => ["phi1294.phi002", "14"],
      # Statius, Silvae — held "Silvae" phi1020.phi002, book.poem.line.
      "STAT-sil1" => ["phi1020.phi002", "1"],
      "STAT-sil2" => ["phi1020.phi002", "2"],
      "STAT-sil3" => ["phi1020.phi002", "3"],
      "STAT-sil4" => ["phi1020.phi002", "4"],
      "STAT-sil5" => ["phi1020.phi002", "5"]
    }.freeze

    # == Censused OUT (P45-5), so the next grower need not re-litigate ==
    #
    # The ~330 remaining files are works the catalog simply does not hold
    # (Ennius, Manilius, Nemesianus, the Anthologia, Venantius Fortunatus,
    # Corippus, Dracontius, the whole Christian-epic shelf, …) — censused by
    # absence, nothing to verify. The files below were EVALUATED against held
    # candidates and excluded for cause; they stay censused as unmapped:
    #
    #   Identity unverifiable from the catalog:
    #     VERG_APP-* (phi0692 is held but its documents carry NO titles — the
    #       Appendix Vergiliana poem↔phi asssignment cannot be evidenced);
    #     SER-medi (phi2003.phi001 held untitled); SIDON-epis (stoa0162.stoa004
    #       "Epistolae" names no author); AVSON-orat ("orat" abbreviates both
    #       the verse Oratio stoa020 and the prose Gratiarum Actio stoa014).
    #   Citation grain can never meet (identity clear, shapes refuted live):
    #     BOETH-cons (Perseus cites whole metra, 1.M1); PETRON-saty + SEN-apoc
    #       (Perseus chapter/section grain around the verse); COLVM-reru
    #       (Perseus 1.1.1 vs bare file lines); CLAVD-pros/-rufi (Perseus
    #       carries a praefatio middle level); CLAVD-goth/-nupt/-hon3/-hon6/
    #       -mall, PRVD-psyc/-apot/-hama/-prae/-symm, AVSON-caes/-ordo (one
    #       side has a division level the other lacks); AVSON-comm/-epit/-fast
    #       (division titles are edition concordances, "1 = XVI.2 Schenkl…" —
    #       non-numeric, and the reference numbering is unverified);
    #     MART-spec (the held Epigrammata has no Spectacula book);
    #     OV-amo0 (the Amores epigramma; no held component); LYGD-eleg
    #       (phi0660.phi003 is titled "Sulpicia Elegiae" — Lygdamus is not it).
    #   Malformed upstream (censused BY NAME at run time, P44-i3b):
    #     AVSON-appe/-biss/-eclo/-ephe/-epig/-epis/-frag/-ilia/-odys/-prae/
    #     -prec and SEN-epig — raw <emph> markup inside title attributes.

    # One refresh's census (the producer Result shape — a sync/rebuild tail
    # renders it like the links producers' Result). +matched+/+unmatched+ are
    # LINE counts (the honest coverage number the packet demands); +mapped_works+
    # are crosswalked files that resolved ≥1 line, +unmapped_works+ crosswalked
    # files present on disk with no held witness (or no crosswalk entry).
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
      malformed = []
      @doc_cache = {}
      @catalog.transaction do
        counts[:superseded] = Store::Enrichment.supersede!(@catalog, kind: KIND, model: MODEL)
        # A file that will not parse is censused BY NAME and skipped — one
        # unreadable upstream export (P44-i3b: 12 of the artifact's 469 files
        # ship raw <emph> markup inside title attributes) must never abort
        # the other works' re-derivation. The DOM parse happens before any
        # yield, so a malformed file contributes no counts and no rows.
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
      Dir.glob(File.join(workdir, DIRNAME, "*.xml"))
    end

    # One <AUTHOR>-<work>.xml → its lines' meter rows. A file with no crosswalk
    # entry, or one whose crosswalked work we do not hold, still has every line
    # COUNTED (unmatched) — coverage is never silently smaller than the corpus.
    # A [work, book] entry (the per-book files, P45-5) prepends the filename's
    # book component so a division-level citation meets Perseus's
    # book.poem.line scheme (the WORK_CROSSWALK note).
    def ingest_file(path, counts)
      tg_work, book = Array(WORK_CROSSWALK[File.basename(path, ".xml")])
      doc_urns = tg_work ? held_documents(tg_work) : []
      before = counts[:matched]

      each_line(path) do |citation, payload|
        counts[:lines] += 1
        citation = "#{book}.#{citation}" if book && citation
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
    # file raises ParseError at this grain; run rescues it per file into the
    # malformed_files census — loud in the sync tail, never a silent drop, and
    # never fatal to the batch.
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

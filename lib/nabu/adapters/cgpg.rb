# frozen_string_literal: true

require_relative "cgpg_vert_parser"
require_relative "cgpg_carve_plan"
require_relative "cgpg_title_genre"
require_relative "../zip_fetch"
require_relative "../file_fetch"

module Nabu
  module Adapters
    # CGPG — the Calfa/GREgORI Patrologia Graeca (P153; Zenodo 19915273):
    # the OCR of 33 Migne Patrologia Graeca volumes, the Greek column only,
    # lemmatized and POS-tagged by machine — ~6M tokens, the library's
    # first middle and late Byzantine shelf beyond First1K's handful:
    # Photius, Leo VI, Theophanes Continuatus / Genesius / Symeon Magister,
    # Constantine VII (De ceremoniis, De thematibus, De administrando
    # imperio), Oecumenius, Cedrenus + Skylitzes + Psellus, Theophylact of
    # Ohrid, Zonaras, Choniates, Nicephorus Callistus, Gregoras, Palamas,
    # Cantacuzene, Symeon of Thessalonica, Codinus + Doukas, Glykas — PG's
    # reprints of the Bonn-corpus historians among them — plus eleven
    # patristic volumes (Clement, Justin, Eusebius, Epiphanius, Cyril …).
    # A composition of the cgpg-vert family and the CGPG carve plan
    # (CgpgCarvePlan); the adapter owns identity, the per-volume table,
    # dating, license and the fetch.
    #
    # == Identity and grain: works, by an external carve plan
    #
    # The deposit itself has no work, chapter or Migne-column markup, and a
    # volume holds several authors (PG 109: Theophanes Continuatus, the Vita
    # Basilii, Cameniates, Symeon Magister, Genesius). The work boundaries
    # come from open-greek-corpus's curated carve plan (CgpgCarvePlan — its
    # loci ARE this deposit's PDF pages), materialized by #fetch under
    # carve/ and applied, never edited. Three grains:
    #
    #   work      urn:nabu:cgpg:<plan slug>         one plan work (photius.amphilochia)
    #             passage <urn>:pg<volume>:p<page>  (a work may span two volumes)
    #   residuum  urn:nabu:cgpg:pg<volume>-residuum every row of a carved volume no
    #             passage <urn>:p<page>             work claims, classed per passage
    #   volume    urn:nabu:cgpg:pg<volume>          a volume the plan does not carve
    #             passage <urn>:p<page>             (unplanned, or deferred: PG 3)
    #
    # - A work's key is the plan's slug — stable across parses because the
    #   pinned plan is. A slug the plan repeats WITHOUT append (PG 157's
    #   Patria and PG 122's copy of it) keys each copy by volume
    #   (<slug>-pg<n>); an appended continuation (Theophylact's John,
    #   PG 123 → 124) is the same document.
    # - rank rides metadata (carve_rank): "secondary" is the plan's own
    #   precedence call (the work is served from a better open edition
    #   elsewhere — First1K/Perseus TEI, byzantium.gr). Those are still
    #   carved, rank honest, so projection can treat them as non-competing
    #   witnesses; an absent rank is primary. secondary_reason, tlg,
    #   author (author_display), work_title and the planned ranges ride too.
    # - The residuum is never dropped text: residuum_class per passage —
    #   apparatus (the plan's residual: testimonia, prefaces, tables Migne
    #   assembles), duplicate (a rescan of a leaf served elsewhere,
    #   duplicate_of its original), uncarved (in no work and no residual:
    #   PG 122's Cedrenus pages, split upstream outside this plan; PG 113's
    #   two Delectus back-matter rows). A residuum carries no date (the
    #   volume's era label dates its works, not Migne's apparatus) and no
    #   kind claim: the apparatus is paratext's grain (the head ruled
    #   2026-11-07), but a residuum mixes it with rescans and uncarved
    #   text, so no one class holds the document.
    #
    # == Kind (the title fold)
    #
    # Neither upstream nor the plan carries a genre field, so a work's
    # genre is read off its plan title: CgpgTitleGenre cuts ONE keyword
    # head ("Expositio in", "Historia", "Epistulae", or a keywordless
    # "De <topic>" title whole) into facets.genre (raw = the title), and
    # config/kind_map.yml's cgpg section folds the heads — or leaves them
    # unmapped where no ruled class fits (bare fragments, court treatises).
    # A whole volume claims a kind only when it is single-genre and says
    # so in its contents label (VOLUMES genre: PG 71, 73 Cyril's
    # commentaries; PG 121, 148, 153 the histories; PG 21's apologetic
    # Praeparatio, claimable since the 2026-11-07 theology head); a mixed
    # volume (PG 8, 9, 16.3, 42), the deferred PG 3 and every residuum
    # make none.
    # - Incipit soft verification: each plan incipit_check whose page the
    #   box holds must carry the quoted opening (CgpgCarvePlan's folded-word
    #   score); a miss quarantines the work (ParseError) — the ranges are
    #   never shifted to fit.
    # - A work or residuum with no held row is DocumentSkipped by rule
    #   (discover reads only the plan, never the 700 MB of volumes).
    #
    # == Reconciliation (census 2026-11-05: the box's 33 volume files + the
    # pinned plan, through this adapter)
    #
    # The plan: 34 pass entries over 23 volumes, 210 works. 22 volumes carve
    # (PG 3 is deferred by the plan — its Dionysius and Pachymeres interleave
    # chapter by chapter); 10 volumes are not in the plan. Every plan volume
    # is held (0 discovery skips). 242 refs → 209 works (210 less the
    # appended John) + 12 residua + 11 volume documents = 232 documents,
    # plus 10 residua skipped by rule (PG 6, 67, 87.1, 112, 123, 126, 146,
    # 155, 157, 158 — every held row is a work's). Passages: 12,630 work +
    # 316 residuum (90 apparatus, 46 duplicate, 180 uncarved) + 5,755
    # volume = 18,701, exactly the deposit's page count; 6,779,355 tokens,
    # exactly the deposit's. Works: 181 primary, 28 secondary; all 227
    # incipit checks verified.
    #
    # == The volume table (VOLUMES)
    #
    # Transcribed from the GitHub README's "Works and Authors Dataset"
    # table (github.com/calfa-co/Patrologia-Graeca @5895ab90, read
    # 2026-11-02): PG number, the Dates label, Authors and Works (markdown
    # italics dropped), advertised word count. The table's edition-scan
    # links are NOT carried: two of them repeat another volume's link
    # (PG 21 = PG 8, PG 121 = PG 5), so they cannot be trusted per volume.
    #
    # == Dating
    #
    # The Dates label is upstream's attributed era for the volume →
    # metadata "date" {century envelope, class composition} through the
    # MetadataDates :structured lane ("14th century" → 1301–1400).
    # "Pre-Nicaean" (6 volumes) names no century but has a crisp right
    # edge, Nicaea (325): an open-start envelope (not_after 325 only,
    # the label raw, class composition — LABEL_BANDS).
    # Upstream's labels are transcribed, not corrected — two are known
    # loose: PG 3 (ps.-Dionysius, c. 500) sits under "Pre-Nicaean" by
    # Migne's traditional attribution, and PG 87.1 (Procopius of Gaza,
    # c. 465–528) is labeled "7th century".
    #
    # A carved work inherits its (lead) volume's label — declared coarse:
    # the label is upstream's era for the volume as a whole, so a work
    # Migne binds out of its century carries the volume's (PG 109's
    # Demetrius Cydones monody rides PG 109's "10th century"). The plan
    # carries no per-work date (its "date" is the plan's own research
    # date), so there is nothing finer to mine. Residua carry none.
    #
    # == Text and lemma tier
    #
    # Uncorrected machine OCR of nineteenth-century prints — declared on
    # every document (text_nature uncorrected-ocr + OCR_NOTE) — and
    # automatic lemma/POS: sources.yml lemma_tier silver (the GLAUx rule).
    #
    # == Fetch
    #
    # One immutable versioned-record file, PG.zip (103 MB, one top-level
    # PG/ dir → the workdir), streamed through ZipFetch under a hard
    # sha256 pin verified between download and any tree mutation.
    # sync_policy manual; a new Zenodo version is a new record the owner
    # re-pins. Beside it, the carve plan: one file GET from the
    # open-greek-corpus tag (CARVE_PLAN_URL, raw.githubusercontent.com)
    # through FileFetch into carve/, under its own sha256 pin, verified in
    # the same window; ZipFetch's sweep keeps carve/ and materialized_paths
    # declares it.
    #
    # == License (verified 2026-11-02)
    #
    # The Zenodo record's license field: cc-by-4.0; the companion GitHub
    # repo's README badge: "License: CC BY 4.0" (no LICENSE file there) →
    # attribution. The carve plan is open-greek-corpus's own project data,
    # CC BY 4.0 (credited in CARVE_PLAN_LABEL on every carved document).
    class Cgpg < Nabu::Adapter
      SLUG = "cgpg"
      LANGUAGE = "grc"
      URN_PREFIX = "urn:nabu:cgpg:"
      RESIDUUM_SUFFIX = "-residuum"
      RECORD_URL = "https://zenodo.org/records/19915273"
      ZIP_URL = "https://zenodo.org/api/records/19915273/files/PG.zip/content"

      # PG.zip as published (the record lists md5 0e9693c24bdf836997b9e912def7cc73;
      # the sha256 measured on the 2026-11-02 download agreed with it).
      RELEASE_SHA256 = "3df496869e56f93f9589ef46c7b279bd75a5af3452bee17ba95930a0833d166b"

      # The carve plan, materialized at <workdir>/carve/ (materialized_paths).
      CARVE_DIRNAME = "carve"
      CARVE_FILE = "cgpg_carve_plan.json"
      CARVE_PLAN_TAG = "corpus-2026-10-28.2"
      CARVE_PLAN_URL = "https://raw.githubusercontent.com/open-greek/open-greek-corpus/" \
                       "#{CARVE_PLAN_TAG}/data/#{CARVE_FILE}".freeze
      # The file at the tag as read 2026-11-05 (293 KB).
      CARVE_PLAN_SHA256 = "7c0fec3de35cfaa15c0d58abf283e782a3d85d7f22a37aa77269464da797228c"
      CARVE_PLAN_LABEL = "open-greek-corpus #{CARVE_PLAN_TAG} data/#{CARVE_FILE} (CC BY 4.0)".freeze

      # PG<nnn>[_<part>]_tagged_text.vert|.txt — the five .txt members are
      # the same vertical format.
      MEMBER = /\APG(\d{3})(?:_(\d+))?_tagged_text\.(?:vert|txt)\z/

      OCR_NOTE = "Uncorrected machine OCR of the Migne print (Greek column only), never proofread; " \
                 "lemma and POS are automatic. Words broken at line ends stay split."

      MANIFEST = Nabu::SourceManifest.new(
        id: SLUG,
        name: "CGPG — Calfa/GREgORI Patrologia Graeca (OCR, lemmatized)",
        license: "CC BY 4.0 (Zenodo record 19915273 license field cc-by-4.0, verified 2026-11-02; " \
                 "cite Vidal-Gorène & Kindt, \"The Patrologia Graeca Corpus\", LREC 2026)",
        license_class: "attribution",
        upstream_url: RECORD_URL,
        parser_family: "cgpg-vert",
        credit: "CGPG — Calfa GREgORI Patrologia Graeca (J.-M. Auwers, UCLouvain; GREgORI; Calfa), " \
                "Zenodo 19915273; Vidal-Gorène & Kindt, LREC 2026. Work carve: the open-greek-corpus " \
                "CGPG carve plan (CC BY 4.0)."
      )

      VOLUMES = {
        "3" => { period: "Pre-Nicaean", contents: "Dionysius the Areopagite (vol. 1)", words: 134_866 },
        "5" => { period: "Pre-Nicaean", contents: "Ignatius, Polycarp, Popes of 2nd c., Melito, others",
                 words: 46_164 },
        "6" => { period: "Pre-Nicaean", contents: "Justin, Tatian, Athenagoras, Theophilus, Hermias",
                 words: 170_482 },
        "8" => { period: "Pre-Nicaean", contents: "Clement of Alexandria (vol. 1); Cohortatio, Paedagogus, Stromata",
                 words: 168_277 },
        "9" => { period: "Pre-Nicaean",
                 contents: "Clement of Alexandria (vol. 2); Stromata, Quis dives, Excerpta, Eclogae, old " \
                           "scholia, diss. by Le Nourry",
                 words: 82_135 },
        "16.3" => { period: "Pre-Nicaean",
                    contents: "Origen (vol. 6.3); Hexapla (contd); Hippolytus, Philosophumena", words: 60_921 },
        "21" => { period: "4th century", contents: "Eusebius (vol. 3); Praeparatio Evangelica", words: 236_625,
                  genre: "Apologia" },
        "42" => { period: "4th century",
                  contents: "Epiphanius (vol. 2); Panarion (contd), Expositio fidei, Anacephalaeosis; " \
                            "Appendix: dissertations",
                  words: 161_237 },
        "67" => { period: "5th century",
                  contents: "Socrates, Historia Ecclesiastica; Sozomen, Historia Ecclesiastica", words: 170_445 },
        "71" => { period: "5th century",
                  contents: "Cyril of Alexandria (vol. 4): Commentaries on Hosea, Joel, Amos, Jonah, Abdiah, " \
                            "Micaiah, Nahum, Habakuk, Haggai, etc.",
                  words: 210_957, genre: "Commentarius" },
        "73" => { period: "5th century", contents: "Cyril of Alexandria (vol. 6): Commentary on John",
                  words: 191_303, genre: "Commentarius" },
        "87.1" => { period: "7th century",
                    contents: "Procopius of Gaza (vol. 1), Vetus Testamentum commentaries", words: 151_167 },
        "101" => { period: "9th century",
                   contents: "Photius (vol. 1): Exegetica: Quaestiones Amphilochiana, Commentary on Novum " \
                             "Testamentum",
                   words: 178_850 },
        "107" => { period: "10th century",
                   contents: "Leo the Emperor: Theologica: 19 homilies and panegyrics, Letter to Omar, king of " \
                             "the Saracens, Juridical and canonical works; Poems, Apologia, Epigrams, Tactica " \
                             "sive de re militaria, oracula",
                   words: 196_727 },
        "109" => { period: "10th century",
                   contents: "Historical works: continuation of Theophanes; Constantine Porphyrogenitus, De " \
                             "vita Basilii Macedonis; John Cameniates, Narratio de excidio Thessalonicae; " \
                             "Symeon Magister et Logothetes, Annales; Josephus Genesius, History of " \
                             "Constantinople; and others",
                   words: 148_584 },
        "112" => { period: "10th century", contents: "Constantine Porphyrogenitus (vol. 1): De ceremoniis",
                   words: 129_556 },
        "113" => { period: "10th century",
                   contents: "Constantine Porphyrogenitus (vol. 2): De thematibus, De administrando imperio, " \
                             "Vita Basilii Macedonis; Theodosius Diaconus, De expugnatione Cretae; and others",
                   words: 104_371 },
        "118" => { period: "10th century",
                   contents: "Oecumenius (vol. 1): Commentary on Acts, Commentary on Paul's letters, " \
                             "Commentary on the Catholic letters",
                   words: 208_448 },
        "121" => { period: "11th century", contents: "George Cedrenus (vol. 1): Compendium Historiarum",
                   words: 160_853, genre: "Historia" },
        "122" => { period: "11th century",
                   contents: "George Cedrenus (vol. 2): Compendium Historiarum (contd); John Scylitzes, " \
                             "Breviarium historicum; Michael Psellus, many works",
                   words: 150_647 },
        "123" => { period: "11th century",
                   contents: "Theophylact of Bulgaria (vol. 1): Ennaratio in Evangelium Matthaei / Marci / " \
                             "Lucae / Joannis",
                   words: 208_024 },
        "124" => { period: "11th century",
                   contents: "Theophylact of Bulgaria (vol. 2): Commentarius in Joannis Evangelium (contd); " \
                             "Commentary on Paul's letters",
                   words: 210_302 },
        "125" => { period: "11th century",
                   contents: "Theophylact of Bulgaria (vol. 3): Commentary on Paul's letters (contd); 1 and 2 " \
                             "Peter; alternative versions of commentaries",
                   words: 172_696 },
        "126" => { period: "11th century",
                   contents: "Theophylact of Bulgaria (vol. 4): More Novum Testamentum commentaries; Orations, " \
                             "Letters, Commentaries on minor prophets",
                   words: 164_706 },
        "134" => { period: "12th century", contents: "John Zonaras (vol. 1): Annales", words: 196_859 },
        "139" => { period: "13th century",
                   contents: "Isidore of Thessalonica, Sermons; Nicetas Maroneae; John of Citrus; Joel " \
                             "Chronographus, Chronologia compendiaria; Nicetas Choniates, Historia Byzantina " \
                             "(from John Comnenus to 1204), Thesaurus (books 1–5)",
                   words: 134_703 },
        "146" => { period: "14th century",
                   contents: "Nicephorus Callistus (vol. 2): Ecclesiastical History, books 8–14", words: 156_848 },
        "148" => { period: "14th century",
                   contents: "Nicephorus Gregoras (vol. 1): Historia Byzantina, books 1–24", words: 234_855,
                   genre: "Historia" },
        "151" => { period: "14th century", contents: "Gregory Palamas (vol. 2); Gregory Acindynus, Barlaam",
                   words: 399_518 },
        "153" => { period: "14th century",
                   contents: "John Cantacuzene (vol. 1): Historia Byzantina in 4 books (events from 1320–1354)",
                   words: 230_239, genre: "Historia" },
        "155" => { period: "15th century", contents: "Simeon of Thessalonica (1430 AD)", words: 175_482 },
        "157" => { period: "15th century",
                   contents: "George Codinus (1400–1462): works about Constantinople, De sepulchris " \
                             "imperatorem; Ducas, Historia Byzantina 1341–1462, Chronicon breve (contd to 1523)",
                   words: 95_020 },
        "158" => { period: "15th century", contents: "Michael Glyca (1448–1453): Annals, Letters; Others",
                   words: 163_148 }
      }.freeze

      CENTURY = /\A(\d{1,2})(?:st|nd|rd|th) century\z/

      def self.manifest = MANIFEST

      # The carve plan's directory: the one thing #fetch writes beside the
      # unpacked volumes (the declared-materializations rule).
      def self.materialized_paths = [CARVE_DIRNAME]

      def self.remote_probe_strategy = :http_zip

      def self.http_probe_targets
        [Nabu::Adapter::HttpProbeTarget.new(
          label: "PG.zip", zip_url: ZIP_URL, metadata_url: nil,
          state_subdir: "", state_file: Nabu::ZipFetch::STATE_FILE
        )]
      end

      # "PG087_1_tagged_text.vert" → "87.1"; nil outside the member shape.
      def self.volume_of(filename)
        match = File.basename(filename).match(MEMBER) or return nil
        [Integer(match[1], 10).to_s, match[2]].compact.join(".")
      end

      # Non-century labels with a stated edge. "Pre-Nicaean" (6 volumes)
      # names no century, but its right edge is crisp — the Council of
      # Nicaea, 325 — so it bands as an OPEN-START envelope (no lower
      # bound: the label claims "before Nicaea", nothing about how long
      # before).
      LABEL_BANDS = { "Pre-Nicaean" => [nil, 325].freeze }.freeze

      # A Dates label → [not_before, not_after]: a century label through
      # #century_band, a LABEL_BANDS label verbatim; nil for any other.
      def self.period_band(label)
        LABEL_BANDS[label.to_s] || century_band(label)
      end

      # "14th century" → [1301, 1400]; nil for any other label.
      def self.century_band(label)
        match = label.to_s.match(CENTURY) or return nil
        century = Integer(match[1], 10)
        [((century - 1) * 100) + 1, century * 100]
      end

      # +pin+ / +carve_pin+ override the release and carve-plan shas
      # (tests; a future re-pin drill).
      def initialize(pin: RELEASE_SHA256, carve_pin: CARVE_PLAN_SHA256)
        super()
        @pin = pin
        @carve_pin = carve_pin
        @plans = {}
        @volumes = {}
      end

      # PG order. A volume outside the plan (or deferred by it) is one
      # volume-grain document; a planned volume yields its works in page
      # order (a work continued in a later volume rides under the volume
      # it starts in), then its residuum. Discover reads only the plan —
      # whether a work or residuum holds any row is parse's question
      # (DocumentSkipped when none).
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        held = held_volumes(workdir)
        plan = plan_in(workdir)
        held.each do |volume, path|
          planned = plan&.volumes&.[](volume)
          if planned.nil? || planned.deferred?
            yield volume_ref(volume, path, planned)
          else
            carved_refs(plan, planned, held, workdir).each(&block)
          end
        end
      end

      # Every other PG* file in the tree is a grain not taken — the raw-OCR
      # text of the companion GitHub repo (PG<nnn>_text.txt) is the known
      # one — and a plan volume with no held file has nothing to carve;
      # both skipped by rule, each named.
      def discovery_skips(workdir)
        others = files(workdir).reject { |path| self.class.volume_of(path) }
        held = held_volumes(workdir)
        unheld = (plan_in(workdir)&.volumes || {}).reject { |volume, _| held.key?(volume) }
        notes = others.map do |path|
          "#{relative(workdir, path)}: not a tagged volume file (raw OCR text and other " \
            "artifacts are superseded by the tagged verticals)"
        end
        notes += unheld.map do |volume, planned|
          "PG #{volume}: in the carve plan (#{planned.works.size} work#{'s' unless planned.works.size == 1}) " \
            "but no volume file is held — nothing to carve"
        end
        Nabu::Adapter::DiscoverySkips.new(skipped_by_rule: others.size + unheld.size, notes: notes)
      end

      def parse(document_ref)
        case document_ref.metadata.fetch("carve")
        in "volume" then parse_volume(document_ref)
        in "work" then parse_work(document_ref)
        in "residuum" then parse_residuum(document_ref)
        end
      rescue Nabu::ValidationError => e
        raise ParseError, "#{document_ref.path}: #{e.message}"
      end

      # prepare both (the release zip, the carve plan) → verify both pins →
      # breaker over both → complete both (the rem rail): every pin check
      # runs BETWEEN download and any tree mutation, and the zip's sweep
      # keeps the plan's directory.
      def fetch(workdir, progress: nil, force: false)
        zip = Nabu::ZipFetch.new(url: ZIP_URL, dir: workdir, stream: true, keep: ["#{CARVE_DIRNAME}/"],
                                 attic_dir: File.join(workdir, ATTIC_DIRNAME), progress: progress)
        plan = Nabu::FileFetch.new(url: CARVE_PLAN_URL, dir: File.join(workdir, CARVE_DIRNAME),
                                   filename: CARVE_FILE, progress: progress,
                                   attic_dir: File.join(workdir, ATTIC_DIRNAME, CARVE_DIRNAME))
        begin
          zip.prepare!
          verify_pin!(zip)
          plan.prepare!
          verify_carve_pin!(plan)
          guard_mass_deletion!(workdir, zip.doomed_paths + plan.doomed_paths, force: force)
          zip.complete!
          plan.complete!
        ensure
          zip.cleanup!
        end
        Nabu::FetchReport.new(sha: zip.sha, fetched_at: Time.now, notes: fetch_notes(zip, plan))
      rescue ZipFetch::Error, FileFetch::Error, Nabu::Shell::Error => e
        raise Nabu::FetchError, "cgpg fetch failed into #{workdir}: #{e.message}"
      end

      private

      # --- discovery ------------------------------------------------------------

      def held_volumes(workdir)
        members(workdir).sort_by { |path, volume| [volume.to_f, path] }.to_h { |path, volume| [volume, path] }
      end

      def plan_in(workdir)
        path = File.join(workdir, CARVE_DIRNAME, CARVE_FILE)
        File.file?(path) ? plan_at(File.expand_path(path)) : nil
      end

      # Memoized per path + mtime: discover and every parse share one read.
      def plan_at(path)
        stamp = File.mtime(path)
        cached = @plans[path]
        return cached.last if cached&.first == stamp

        CgpgCarvePlan.load(path).tap { |plan| @plans[path] = [stamp, plan] }
      end

      def volume_ref(volume, path, planned)
        note = planned ? "deferred by the carve plan: #{planned.defer_reason}" : "not in the carve plan"
        Nabu::DocumentRef.new(
          source_id: SLUG, id: "#{URN_PREFIX}pg#{volume}", path: File.expand_path(path),
          metadata: { "carve" => "volume", "carve_note" => note, "filename" => File.basename(path),
                      "pg_volume" => volume }
        )
      end

      def carved_refs(plan, planned, held, workdir)
        plan_path = File.expand_path(File.join(workdir, CARVE_DIRNAME, CARVE_FILE))
        lead = plan.documents.select { |doc| lead_volume(doc, held) == planned.volume }
        works = lead.sort_by { |doc| [doc.parts.find { |part| held.key?(part.volume) }.loci.min || 0, doc.key] }
        works.map { |doc| work_ref(doc, held, plan_path) } << residuum_ref(planned.volume, held, plan_path)
      end

      # The first volume of the document the box holds.
      def lead_volume(doc, held)
        doc.volumes.find { |volume| held.key?(volume) }
      end

      def work_ref(doc, held, plan_path)
        volume = lead_volume(doc, held)
        Nabu::DocumentRef.new(
          source_id: SLUG, id: "#{URN_PREFIX}#{doc.key}", path: File.expand_path(held.fetch(volume)),
          metadata: { "carve" => "work", "carve_key" => doc.key, "plan_path" => plan_path, "pg_volume" => volume,
                      "volume_paths" => doc.volumes.select { |v| held.key?(v) }
                                           .to_h { |v| [v, File.expand_path(held.fetch(v))] } }
        )
      end

      def residuum_ref(volume, held, plan_path)
        Nabu::DocumentRef.new(
          source_id: SLUG, id: "#{URN_PREFIX}pg#{volume}#{RESIDUUM_SUFFIX}", path: File.expand_path(held.fetch(volume)),
          metadata: { "carve" => "residuum", "plan_path" => plan_path, "pg_volume" => volume }
        )
      end

      # --- the three grains -------------------------------------------------------

      def parse_volume(ref)
        volume = ref.metadata.fetch("pg_volume")
        entry = VOLUMES.fetch(volume, {})
        CgpgVertParser.new.parse(
          ref.path, urn: ref.id, language: LANGUAGE, title: title_for(volume, entry),
                    metadata: volume_metadata(volume, entry).merge("carve" => "volume",
                                                                   "carve_note" => ref.metadata["carve_note"]).compact
        )
      end

      def parse_work(ref)
        doc = plan_at(ref.metadata.fetch("plan_path")).documents.find { |d| d.key == ref.metadata.fetch("carve_key") }
        raise ParseError, "#{ref.id}: the carve plan no longer names #{ref.metadata['carve_key']}" if doc.nil?

        paths = ref.metadata.fetch("volume_paths")
        held_parts = doc.parts.select { |part| paths.key?(part.volume) }
        rows = held_parts.flat_map do |part|
          pages = volume_pages(paths.fetch(part.volume))
          verify_incipits!(ref.id, part, pages)
          part.loci.filter_map { |locus| pages[locus] && [part.volume, pages[locus]] }
        end
        skip!(ref, "work") if rows.empty?

        document = Nabu::Document.new(urn: ref.id, language: LANGUAGE, canonical_path: ref.path,
                                      title: work_title(held_parts),
                                      metadata: work_metadata(doc, held_parts, rows, paths))
        rows.each_with_index do |(volume, page), index|
          document << passage("#{ref.id}:pg#{volume}:p#{page.number}", index, volume, page)
        end
        document
      end

      def parse_residuum(ref)
        volume = ref.metadata.fetch("pg_volume")
        planned = plan_at(ref.metadata.fetch("plan_path")).volumes.fetch(volume)
        rows = volume_pages(ref.path).each_value.filter_map do |page|
          role, detail = planned.role_of(page.number)
          [page, role, detail] unless role == :work
        end
        skip!(ref, "residuum") if rows.empty?

        document = Nabu::Document.new(urn: ref.id, language: LANGUAGE, canonical_path: ref.path,
                                      title: "PG #{volume} — residuum: edition apparatus, rescans and uncarved rows",
                                      metadata: residuum_metadata(volume, planned, rows))
        rows.each_with_index do |(page, role, detail), index|
          extra = { "residuum_class" => role.to_s, "duplicate_of" => (detail if role == :duplicate) }.compact
          document << passage("#{ref.id}:p#{page.number}", index, volume, page, extra)
        end
        document
      end

      def passage(urn, sequence, volume, page, extra = {})
        Nabu::Passage.new(urn: urn, language: LANGUAGE, sequence: sequence, text: page.text,
                          annotations: { "pdf_page" => page.number, "pg_volume" => volume }
                                       .merge(extra, "tokens" => page.tokens))
      end

      def skip!(ref, grain)
        raise Nabu::DocumentSkipped.new("#{ref.id}: no held rows in its carve-plan loci",
                                        reason: "#{grain} with no held rows")
      end

      # Soft verification: each check whose page the box holds must carry
      # the plan's quoted opening (CgpgCarvePlan.incipit_score); a miss means
      # the ranges no longer fit this deposit — quarantine, never shift.
      def verify_incipits!(urn, part, pages)
        part.checks.each do |check|
          page = pages[check.locus] or next
          score = CgpgCarvePlan.incipit_score(check.text, page.text)
          next if score >= CgpgCarvePlan::INCIPIT_THRESHOLD

          raise ParseError, "#{urn}: incipit check at PG #{part.volume} locus #{check.locus} fails " \
                            "(score #{score.round(2)}): the plan quotes #{check.text[0, 60].inspect}, " \
                            "the page reads #{page.text[0, 60].inspect}"
        end
      end

      # The last two volumes read stay cached: a volume's works parse in a
      # row, and an appended work reaches back one volume.
      def volume_pages(path)
        pages = @volumes.delete(path) || CgpgVertParser.new.pages(path).pages
        @volumes[path] = pages
        @volumes.delete(@volumes.keys.first) while @volumes.size > 2
        pages
      end

      # --- titles and metadata ----------------------------------------------------

      def title_for(volume, entry)
        contents = entry[:contents]
        contents ? "PG #{volume} — #{contents}" : "PG #{volume}"
      end

      # The continuation's title states the whole work (PG 124's "complete
      # across two volumes"), so the last held part names the document.
      def work_title(parts)
        last = parts.last
        "PG #{parts.map(&:volume).join(', ')} — #{[last.author, last.title].compact.join(', ')}"
      end

      def work_metadata(doc, parts, rows, paths)
        lead = parts.first
        checks = parts.flat_map { |part| part.checks.map { |check| [part.volume, check.locus] } }
        held = checks.count { |volume, locus| volume_pages(paths.fetch(volume)).key?(locus) }
        volume_metadata(lead.volume, VOLUMES.fetch(lead.volume, {}), whole: false).merge(
          "carve" => "work", "carve_slug" => lead.slug, "carve_plan" => CARVE_PLAN_LABEL,
          "author" => lead.author, "work_title" => parts.last.title, "tlg" => parts.filter_map(&:tlg).first,
          "facets" => genre_facet(CgpgTitleGenre.head(parts.last.title), parts.last.title),
          "carve_rank" => lead.rank, "secondary_reason" => lead.secondary_reason,
          "pg_volumes" => (parts.map(&:volume) if parts.size > 1),
          "pg_volumes_unheld" => (doc.volumes - parts.map(&:volume)).then { |v| v unless v.empty? },
          "carve_ranges" => parts.map { |part| { "pg_volume" => part.volume, "ranges" => part.ranges } },
          "rows" => { "planned" => parts.sum { |part| part.loci.size }, "held" => rows.size },
          "incipit_checks" => { "verified" => held, "unverifiable" => checks.size - held },
          "empty_form_tokens" => rows.sum { |_, page| page.empty_form_tokens },
          "lost_tokens" => rows.sum { |_, page| page.lost_tokens }
        ).compact
      end

      # No date: the volume's era label dates the works it carries, not
      # Migne's apparatus (and an uncarved row's work is unknown).
      def residuum_metadata(volume, planned, rows)
        entry = VOLUMES.fetch(volume, {})
        {
          "carve" => "residuum", "carve_plan" => CARVE_PLAN_LABEL, "pg_volume" => volume,
          "contents" => entry[:contents], "residuum_rows" => rows.map { |_, role, _| role.to_s }.tally,
          "residual_note" => planned.residual_note,
          "text_nature" => "uncorrected-ocr", "ocr_note" => OCR_NOTE,
          "empty_form_tokens" => rows.sum { |page, _, _| page.empty_form_tokens },
          "lost_tokens" => rows.sum { |page, _, _| page.lost_tokens }
        }.compact
      end

      # A work inherits its volume's era label (upstream's attributed
      # composition era for the volume, a declared-coarse date) and names
      # the volume's contents as volume_contents; the advertised word count
      # is the volume's alone.
      def volume_metadata(volume, entry, whole: true)
        band = self.class.period_band(entry[:period])
        {
          "pg_volume" => volume, "period" => entry[:period],
          (whole ? "contents" : "volume_contents") => entry[:contents],
          "facets" => (genre_facet(entry[:genre], entry[:contents]) if whole),
          "words_advertised" => (entry[:words] if whole),
          "text_nature" => "uncorrected-ocr", "ocr_note" => OCR_NOTE,
          "date" => band && { "not_before" => band.first, "not_after" => band.last,
                              "raw" => entry[:period], "class" => "composition" }.compact
        }.compact
      end

      # The kind fold's facet: nil (no claim) without a head.
      def genre_facet(head, raw)
        head && { "genre" => { "value" => head, "raw" => raw } }
      end

      # --- the tree -----------------------------------------------------------------

      def members(workdir)
        files(workdir).filter_map do |path|
          volume = self.class.volume_of(path)
          volume && [path, volume]
        end
      end

      def files(workdir)
        paths = Dir.glob(File.join(workdir, "**", "PG*")).select { |path| File.file?(path) }
        paths.reject { |path| atticked?(workdir, path) }
      end

      def atticked?(workdir, path)
        relative(workdir, path).split(File::SEPARATOR).include?(ATTIC_DIRNAME)
      end

      def relative(workdir, path)
        path.delete_prefix(File.join(workdir, ""))
      end

      # --- fetch pins ---------------------------------------------------------------

      def verify_pin!(fetch)
        return if fetch.not_modified? || fetch.sha == @pin

        raise Nabu::FetchError,
              "cgpg: downloaded PG.zip sha #{fetch.sha} misses the release pin #{@pin} — Zenodo " \
              "record 19915273 is versioned-immutable; verify the record and re-pin only after reading it"
      end

      def verify_carve_pin!(fetch)
        return if fetch.not_modified? || fetch.sha == @carve_pin

        raise Nabu::FetchError,
              "cgpg: downloaded carve plan sha #{fetch.sha} misses the pin #{@carve_pin} — the URL names " \
              "the tag #{CARVE_PLAN_TAG}; a moved tag is a new plan, re-pin only after reading it"
      end

      def fetch_notes(zip, plan)
        [zip.not_modified? ? "PG.zip not modified (304)" : "zenodo 19915273 sha pin verified",
         plan.not_modified? ? "carve plan not modified (304)" : "carve plan #{CARVE_PLAN_TAG} sha pin verified"]
      end
    end
  end
end

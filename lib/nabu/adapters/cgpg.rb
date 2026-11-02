# frozen_string_literal: true

require_relative "cgpg_vert_parser"
require_relative "../zip_fetch"

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
    # A thin composition of the cgpg-vert family; the adapter owns
    # identity, the per-volume table, dating, license and the fetch.
    #
    # == Identity and grain (deliberately coarse, declared)
    #
    #   document urn  urn:nabu:cgpg:pg<volume>   (pg101, pg16.3, pg87.1)
    #   passage urn   <document-urn>:p<pdf-page> (the scanned volume's page image)
    #
    # A document is a VOLUME, not a work: the deposit has no work, chapter
    # or Migne-column markup, and a volume holds several authors (PG 109:
    # Theophanes Continuatus, the Vita Basilii, Cameniates, Symeon
    # Magister, Genesius). Carving to works needs an external carve plan
    # (a later packet); until then the volume's contents ride its title and
    # metadata, verbatim from upstream's table.
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
    # "Pre-Nicaean" (6 volumes) names no century and mints no envelope.
    # Upstream's labels are transcribed, not corrected — two are known
    # loose: PG 3 (ps.-Dionysius, c. 500) sits under "Pre-Nicaean" by
    # Migne's traditional attribution, and PG 87.1 (Procopius of Gaza,
    # c. 465–528) is labeled "7th century".
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
    # re-pins.
    #
    # == License (verified 2026-11-02)
    #
    # The Zenodo record's license field: cc-by-4.0; the companion GitHub
    # repo's README badge: "License: CC BY 4.0" (no LICENSE file there) →
    # attribution.
    class Cgpg < Nabu::Adapter
      SLUG = "cgpg"
      LANGUAGE = "grc"
      URN_PREFIX = "urn:nabu:cgpg:pg"
      RECORD_URL = "https://zenodo.org/records/19915273"
      ZIP_URL = "https://zenodo.org/api/records/19915273/files/PG.zip/content"

      # PG.zip as published (the record lists md5 0e9693c24bdf836997b9e912def7cc73;
      # the sha256 measured on the 2026-11-02 download agreed with it).
      RELEASE_SHA256 = "3df496869e56f93f9589ef46c7b279bd75a5af3452bee17ba95930a0833d166b"

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
                "Zenodo 19915273; Vidal-Gorène & Kindt, LREC 2026."
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
        "21" => { period: "4th century", contents: "Eusebius (vol. 3); Praeparatio Evangelica", words: 236_625 },
        "42" => { period: "4th century",
                  contents: "Epiphanius (vol. 2); Panarion (contd), Expositio fidei, Anacephalaeosis; " \
                            "Appendix: dissertations",
                  words: 161_237 },
        "67" => { period: "5th century",
                  contents: "Socrates, Historia Ecclesiastica; Sozomen, Historia Ecclesiastica", words: 170_445 },
        "71" => { period: "5th century",
                  contents: "Cyril of Alexandria (vol. 4): Commentaries on Hosea, Joel, Amos, Jonah, Abdiah, " \
                            "Micaiah, Nahum, Habakuk, Haggai, etc.",
                  words: 210_957 },
        "73" => { period: "5th century", contents: "Cyril of Alexandria (vol. 6): Commentary on John",
                  words: 191_303 },
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
                   words: 160_853 },
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
                   contents: "Nicephorus Gregoras (vol. 1): Historia Byzantina, books 1–24", words: 234_855 },
        "151" => { period: "14th century", contents: "Gregory Palamas (vol. 2); Gregory Acindynus, Barlaam",
                   words: 399_518 },
        "153" => { period: "14th century",
                   contents: "John Cantacuzene (vol. 1): Historia Byzantina in 4 books (events from 1320–1354)",
                   words: 230_239 },
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

      # "14th century" → [1301, 1400]; nil for any other label.
      def self.century_band(label)
        match = label.to_s.match(CENTURY) or return nil
        century = Integer(match[1], 10)
        [((century - 1) * 100) + 1, century * 100]
      end

      # +pin+ overrides the release sha (tests; a future re-pin drill).
      def initialize(pin: RELEASE_SHA256)
        super()
        @pin = pin
      end

      # One DocumentRef per volume member, in PG order.
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        members(workdir).sort_by { |path, volume| [volume.to_f, path] }.each do |path, volume|
          yield Nabu::DocumentRef.new(
            source_id: SLUG, id: "#{URN_PREFIX}#{volume}", path: File.expand_path(path),
            metadata: { "filename" => File.basename(path), "pg_volume" => volume }
          )
        end
      end

      # Every other PG* file in the tree is a grain not taken — the raw-OCR
      # text of the companion GitHub repo (PG<nnn>_text.txt) is the known
      # one — skipped by rule, each named.
      def discovery_skips(workdir)
        others = files(workdir).reject { |path| self.class.volume_of(path) }
        Nabu::Adapter::DiscoverySkips.new(
          skipped_by_rule: others.size,
          notes: others.map do |path|
            "#{relative(workdir, path)}: not a tagged volume file (raw OCR text and other " \
              "artifacts are superseded by the tagged verticals)"
          end
        )
      end

      def parse(document_ref)
        volume = document_ref.metadata.fetch("pg_volume")
        entry = VOLUMES.fetch(volume, {})
        CgpgVertParser.new.parse(
          document_ref.path, urn: document_ref.id, language: LANGUAGE,
                             title: title_for(volume, entry), metadata: metadata_for(volume, entry)
        )
      rescue Nabu::ValidationError => e
        raise ParseError, "#{document_ref.path}: #{e.message}"
      end

      # prepare → verify the sha pin → breaker → complete (the iecor rail).
      def fetch(workdir, progress: nil, force: false)
        fetch = Nabu::ZipFetch.new(url: ZIP_URL, dir: workdir, stream: true,
                                   attic_dir: File.join(workdir, ATTIC_DIRNAME), progress: progress)
        begin
          fetch.prepare!
          verify_pin!(fetch)
          guard_mass_deletion!(workdir, fetch.doomed_paths, force: force)
          fetch.complete!
        ensure
          fetch.cleanup!
        end
        Nabu::FetchReport.new(sha: fetch.sha, fetched_at: Time.now,
                              notes: [fetch.not_modified? ? "not modified (304)" : "zenodo 19915273 sha pin verified"])
      rescue ZipFetch::Error, Nabu::Shell::Error => e
        raise Nabu::FetchError, "cgpg fetch failed into #{workdir}: #{e.message}"
      end

      private

      def title_for(volume, entry)
        contents = entry[:contents]
        contents ? "PG #{volume} — #{contents}" : "PG #{volume}"
      end

      def metadata_for(volume, entry)
        band = self.class.century_band(entry[:period])
        {
          "pg_volume" => volume, "period" => entry[:period], "contents" => entry[:contents],
          "words_advertised" => entry[:words],
          "text_nature" => "uncorrected-ocr", "ocr_note" => OCR_NOTE,
          "date" => band && { "not_before" => band.first, "not_after" => band.last,
                              "raw" => entry[:period], "class" => "composition" }
        }.compact
      end

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

      def verify_pin!(fetch)
        return if fetch.not_modified? || fetch.sha == @pin

        raise Nabu::FetchError,
              "cgpg: downloaded PG.zip sha #{fetch.sha} misses the release pin #{@pin} — Zenodo " \
              "record 19915273 is versioned-immutable; verify the record and re-pin only after reading it"
      end
    end
  end
end

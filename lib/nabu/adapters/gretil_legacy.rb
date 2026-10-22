# frozen_string_literal: true

require_relative "../zip_fetch"
require_relative "gretil_legacy_parser"

module Nabu
  module Adapters
    # GRETIL's legacy (pre-TEI) e-texts beyond Sanskrit: the Prakrit, New
    # Indo-Aryan and Dravidian download zips of gretil.sub.uni-goettingen.de.
    # The held `gretil` source carries only the 784-file TEI conversion;
    # these collections never reached TEI and live only as the zipped
    # Unicode *.htm files GRETIL made of its older plain-text corpus. What
    # they add: the five Śvetāmbara Āgamas Ousaka and Yamazaki keyed (the
    # only licensed route to the canonical Jain texts), Hāla's Sattasaī,
    # Haribhadra's Dhuttakkhāṇa, Svayambhū's Apabhraṃśa Paumacariu, the
    # Jñāneśvarī (Old Marathi, 1290), Tulsidas's Rāmcaritmānas,
    # Kavitāvalī and Dohāvalī, Qutban's Awadhi Mirigāvatī, Svāmī
    # Haridās's Braj verses and Banārasīdās's Ardhakathānaka.
    #
    # == The three zips (census 2026-10-21)
    #
    #   2_prakrt.zip  1,477,038 B, Last-Modified 2020-06-05 — 8 *.htm under
    #                 2_prakrt/ PLUS a byte-identical second copy of all 8
    #                 under home/mmehner/Spiegel_P/2_prakrt/ (a packaging
    #                 slip: two top dirs, so ZipFetch keeps both).
    #   3_nia.zip     945,626 B, Last-Modified 2020-06-05 — 15 *.htm under
    #                 hindi/ and marathi/ (Qutban's Awadhi Mirigāvatī sits
    #                 in marathi/ in the zip, under Hindi in the index).
    #   4_drav.zip    8,753,197 B, Last-Modified 2020-06-26 — 199 Project
    #                 Madurai e-texts (tamil/pm/), 1 Malayalam e-text, the
    #                 one Tamil TEI file twice (top level and tei/) and its
    #                 tei/transformations/ html + plaintext + css renditions.
    #
    # Each zip lands in its own subdir of the workdir (one ZipFetch each,
    # two-phase: every zip is prepared and the breaker sees the combined
    # doomed set before any tree changes — the ccl/oracc choreography).
    #
    # == Grains: what is a document, what skips by rule
    #
    # A document is one e-text file, named by its GRETIL file stem
    # (urn:nabu:gretil-legacy:<stem>), admitted only through LANGUAGES —
    # the per-file language table. Everything else on disk is accounted
    # for in discovery_skips:
    #
    # - home/…/2_prakrt/*.htm — the packaging duplicate (8 files);
    # - tamil/pm/*.htm — Project Madurai's own e-texts, GRETIL's
    #   romanization of them (199 files): the madurai source holds Project
    #   Madurai in the original Tamil script under its ruled classical cone,
    #   so the romanized copies are not a second witness. Census against
    #   the madurai cone: 149 of the 199 fall inside it; the 50 outside are
    #   modern authors (Bharati, Bharatidasan, Kalki, Jeyakantan, …) bar
    #   four the genre rule missed (pm053 Mullaippāṭṭu with a modern
    #   commentary, pm119 Bharata Cēṉāpatīyam, pm132 Mahābhārata Cūḷāmaṇi,
    #   pm154 the Kampaṉ-attributed Ēr Eḻupatu) — a madurai-cone question,
    #   not this adapter's;
    # - *.xml and tei/** — the Tamil TEI file (Periyavāccāṉ Piḷḷai's
    #   Perumāḷ Tirumoḻi commentary), byte-identical to the one the gretil
    #   TEI source already holds, and GRETIL's renditions of it;
    # - SKIPPED — two NIA files by rule: Bachchan's Madhuśālā (1935; modern
    #   and in copyright) and the CSX-based Ardhakathānaka (bardhkcu, the
    #   twin of bardhkpu without the vocalic-ṛ/flap distinction — the CSX+
    #   file is the better witness of the same edition and input).
    #
    # Any other file is UNRECOGNIZED, counted loud. Reconciliation with
    # GRETIL's own index (gretil.html, 2026-10-21): Prakrit 8 entries = 8
    # files (+8 duplicates); NIA 15 = 15; Dravidian 200 Project Madurai
    # links + Jyotsnikā — 199 PM files in the zip (pm013, Vedānta Deśika,
    # is index-listed but absent from the zip) + 1. Admitted: 8 + 13 = 21
    # documents; Jyotsnikā quarantines (below).
    #
    # == Language (LANGUAGES — per file, romanized → -Latn)
    #
    # GRETIL labels only "Prakrit" / "Hindi" / "Marathi" / "Malayalam".
    # The Āgamas take pka (Ardhamāgadhī, the canon's language — the
    # registry node names them); Hāla, Haribhadra and Svayambhū stay on the
    # collective pra (Māhārāṣṭrī, Jain Māhārāṣṭrī and Apabhraṃśa have no
    # registry nodes — declared coarse). Tulsidas's Rāmcaritmānas and the
    # Mirigāvatī are Awadhi (the edition itself says "Avadhii text"; the awa
    # node names the Mānas); the Dohāvalī mixes Awadhi and Braj and rides
    # awa with the Mānas, declared coarse; Kavitāvalī, Haridās and the
    # Ardhakathānaka are Braj. The Jñāneśvarī is Marathi (mar → mr; Old
    # Marathi has no stage — declared coarse; the Gītā verses it embeds
    # ride inside its lines). Jyotsnikā, a Maṇipravāḷam (Malayalam +
    # Sanskrit) toxicology text, QUARANTINES: the registry holds no
    # Malayalam node (the ml anchor is a named mint candidate) — the sii
    # precedent, admitted once the node lands.
    #
    # == Grain, metadata, dating
    #
    # Passage = physical line (the gretil-legacy family), cited by ordinal
    # (<urn>:<n>), flagged "addressing" => "line-ordinal": the files' own
    # reference markers vary per file and stay in the text. Mined from the
    # header: the verbatim header lines, the input credits, the edition
    # statement, GRETIL's notice; plus the zip ("collection") and the work
    # key. Dating: the ruled per-work era table (config/work_eras.yml, key
    # "work" = the file stem) — the works' attributed composition eras;
    # the header's edition years are print years and mint nothing.
    #
    # == License
    #
    # Every file carries GRETIL's notice verbatim: "THIS GRETIL TEXT FILE IS
    # FOR REFERENCE PURPOSES ONLY! COPYRIGHT AND TERMS OF USAGE AS FOR SOURCE
    # FILE." — no open grant; the inputters' source sites are mostly
    # expired. Class nc, the gretil TEI precedent (local research,
    # searchable, never redistributed).
    class GretilLegacy < Nabu::Adapter
      SLUG = "gretil-legacy"
      URN_PREFIX = "urn:nabu:gretil-legacy:"
      BASE_URL = "https://gretil.sub.uni-goettingen.de/gretil"
      COLLECTIONS = %w[2_prakrt 3_nia 4_drav].freeze

      LICENSE = "GRETIL notice in every file, verbatim: \"THIS GRETIL TEXT FILE IS FOR REFERENCE " \
                "PURPOSES ONLY! COPYRIGHT AND TERMS OF USAGE AS FOR SOURCE FILE.\" — no open grant; " \
                "class nc (the gretil TEI precedent: local research, never redistributed)"

      MANIFEST = Nabu::SourceManifest.new(
        id: SLUG,
        name: "GRETIL legacy e-texts — Prakrit, New Indo-Aryan and Dravidian collections",
        license: LICENSE,
        license_class: "nc",
        upstream_url: "#{BASE_URL}.html",
        parser_family: "gretil-legacy",
        credit: "GRETIL — Göttingen Register of Electronic Texts in Indian Languages (SUB Göttingen); " \
                "inputters as credited in each file"
      )

      # The admitted e-texts: GRETIL file stem → language tag (class note).
      LANGUAGES = {
        # 2_prakrt — the Śvetāmbara canon (Ardhamāgadhī)
        "ayarangu" => "pka-Latn", # Āyāraṅga (Ācārāṅga), the first aṅga
        "suyagadu" => "pka-Latn", # Sūyagaḍa (Sūtrakṛtāṅga) I, the second aṅga
        "uttaraju" => "pka-Latn", # Uttarajjhāyā, a mūlasūtra (Charpentier's text)
        "dasaveyu" => "pka-Latn", # Dasaveyāliya, a mūlasūtra
        "isibhasu" => "pka-Latn", # Isibhāsiyāiṃ, a prakīrṇaka
        # 2_prakrt — kāvya and Apabhraṃśa on the collective anchor
        "halsatsu" => "pra-Latn", # Hāla's Sattasaī (Māhārāṣṭrī; Weber's text)
        "hadhut_u" => "pra-Latn", # Haribhadra's Dhuttakkhāṇa (Jain Māhārāṣṭrī)
        "spaucaru" => "pra-Latn", # Svayambhū's Paumacariu (Apabhraṃśa; Bhayani's text)
        # 3_nia
        "tulrcm1u" => "awa-Latn", # Rāmcaritmānas, Bālakāṇḍa
        "tulrcm2u" => "awa-Latn", # Ayodhyākāṇḍa
        "tulrcm3u" => "awa-Latn", # Araṇyakāṇḍa
        "tulrcm4u" => "awa-Latn", # Kiṣkindhākāṇḍa
        "tulrcm5u" => "awa-Latn", # Sundarakāṇḍa
        "tulrcm6u" => "awa-Latn", # Laṅkākāṇḍa
        "tulrcm7u" => "awa-Latn", # Uttarakāṇḍa
        "tuldoh_u" => "awa-Latn", # Dohāvalī (Awadhi/Braj mix — coarse, with the Mānas)
        "kutmir_u" => "awa-Latn", # Qutban's Mirigāvatī ("Avadhii text", Plukker)
        "tulkav_u" => "bra-Latn", # Kavitāvalī
        "hdas_u" => "bra-Latn", # Svāmī Haridās, Aṣṭādaśa Siddhānta
        "bardhkpu" => "bra-Latn", # Banārasīdās's Ardhakathānaka (CSX+ file)
        "jna1-16u" => "mar-Latn", # Jñāneśvarī, adhyāyas 1–16
        # 4_drav
        "jyotsniu" => "mal-Latn" # Jyotsnikā (Maṇipravāḷam) — QUARANTINED below
      }.freeze

      # Tags with no registry node: the document quarantines loudly.
      QUARANTINED_LANGUAGES = {
        "mal-Latn" => "no Malayalam node in the lect registry (the ml anchor is a named mint candidate)"
      }.freeze

      # Admitted collections' files skipped by rule, by stem.
      SKIPPED = {
        "bacmadhu" => "Bachchan's Madhuśālā (1935) — a modern work, in copyright",
        "bardhkcu" => "the CSX-based Ardhakathānaka — the CSX+ twin (bardhkpu) is the better witness"
      }.freeze

      ETEXT = ".htm"

      def self.manifest = MANIFEST

      def self.zip_url(collection) = "#{BASE_URL}/#{collection}.zip"

      def self.remote_probe_strategy = :http_zip

      def self.http_probe_targets
        COLLECTIONS.map do |collection|
          Nabu::Adapter::HttpProbeTarget.new(
            label: "#{collection}.zip", zip_url: zip_url(collection), metadata_url: nil,
            state_subdir: collection, state_file: Nabu::ZipFetch::STATE_FILE
          )
        end
      end

      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        documents = census(workdir).select { |entry| entry[:verdict] == :document }
        documents.sort_by { |entry| entry[:stem] }.each do |entry|
          yield Nabu::DocumentRef.new(
            source_id: SLUG, id: "#{URN_PREFIX}#{entry[:stem]}", path: File.expand_path(entry[:path]),
            metadata: { "work" => entry[:stem], "collection" => entry[:collection] }
          )
        end
      end

      def discovery_skips(workdir)
        entries = census(workdir).reject { |entry| entry[:verdict] == :document }
        skipped, unknown = entries.partition { |entry| entry[:verdict] == :skip }
        Nabu::Adapter::DiscoverySkips.new(
          skipped_by_rule: skipped.size, unrecognized: unknown.size,
          notes: skipped.map { |entry| "#{entry[:rel]}: #{entry[:reason]}" } +
                 unknown.map { |entry| "#{entry[:rel]}: unrecognized member" }
        )
      end

      def parse(document_ref)
        stem = document_ref.metadata.fetch("work")
        language = LANGUAGES.fetch(stem)
        if (reason = QUARANTINED_LANGUAGES[language])
          raise Nabu::ParseError, "#{SLUG}: #{stem}: #{language} — #{reason}"
        end

        etext = GretilLegacyParser.etext(SourceRead.utf8_file(document_ref.path, label: SLUG),
                                         path: document_ref.path)
        raise Nabu::ParseError, "#{SLUG}: #{stem}: no text lines after the GRETIL notice" if etext.lines.empty?

        document = Nabu::Document.new(
          urn: document_ref.id, language: language, canonical_path: document_ref.path,
          title: etext.title || stem, metadata: document_metadata(document_ref, etext)
        )
        etext.lines.each_with_index do |line, index|
          document << Nabu::Passage.new(urn: "#{document_ref.id}:#{index + 1}", language: language,
                                        text: line, sequence: index)
        end
        document
      rescue Nabu::ValidationError => e
        raise Nabu::ParseError, "#{document_ref.path}: #{e.message}"
      end

      # The three zips, two-phase: all prepared (live trees untouched), the
      # breaker over the combined doomed set, then all completed.
      def fetch(workdir, progress: nil, force: false)
        fetches = COLLECTIONS.to_h do |collection|
          [collection, Nabu::ZipFetch.new(
            url: self.class.zip_url(collection), dir: File.join(workdir, collection),
            attic_dir: File.join(workdir, ATTIC_DIRNAME, collection), progress: progress
          )]
        end
        begin
          fetches.each_value(&:prepare!)
          guard_mass_deletion!(workdir, fetches.values.flat_map(&:doomed_paths), force: force)
          fetches.each_value(&:complete!)
        ensure
          fetches.each_value(&:cleanup!)
        end
        Nabu::FetchReport.new(sha: fetches.values.last.sha, fetched_at: Time.now, notes: fetch_notes(fetches))
      rescue ZipFetch::Error, Nabu::Shell::Error => e
        raise Nabu::FetchError, "#{SLUG} fetch failed into #{workdir}: #{e.message}"
      end

      private

      # Every file under the three collection subdirs, with its verdict:
      # :document, :skip (with the rule's reason) or :unknown. Fetch state
      # files and the attic are infrastructure, never census.
      def census(workdir)
        COLLECTIONS.flat_map do |collection|
          root = File.join(workdir, collection)
          next [] unless Dir.exist?(root)

          Dir.glob("**/*", base: root).sort.filter_map do |rel|
            path = File.join(root, rel)
            next unless File.file?(path)

            classify(collection, rel).merge(collection: collection, rel: "#{collection}/#{rel}", path: path)
          end
        end
      end

      def classify(_collection, rel)
        stem = File.basename(rel, ".*")
        return { verdict: :skip, reason: "packaging duplicate (the zip's home/ mirror of 2_prakrt/)" } if
          rel.start_with?("home/")
        if rel.start_with?("tamil/pm/")
          return { verdict: :skip,
                   reason: "a Project Madurai e-text in GRETIL's romanization — held in Tamil script " \
                           "by the madurai source (its classical cone)" }
        end
        if rel.end_with?(".xml") && !rel.start_with?("tei/transformations/")
          return { verdict: :skip, reason: "the Tamil TEI file — held by the gretil TEI source (byte-identical)" }
        end
        if rel.start_with?("tei/transformations/")
          return { verdict: :skip, reason: "GRETIL's html/plaintext/css rendition of the TEI file" }
        end
        return { verdict: :skip, reason: SKIPPED.fetch(stem) } if SKIPPED.key?(stem)
        return { verdict: :document, stem: stem } if File.extname(rel) == ETEXT && LANGUAGES.key?(stem)

        { verdict: :unknown }
      end

      def document_metadata(document_ref, etext)
        {
          "work" => document_ref.metadata["work"],
          "collection" => document_ref.metadata["collection"],
          "gretil_header" => etext.header,
          "input" => GretilLegacyParser.input_credits(etext.header),
          "edition" => GretilLegacyParser.edition(etext.header),
          "gretil_notice" => etext.notice,
          "addressing" => "line-ordinal",
          "separator_lines" => etext.dropped
        }.reject { |_, value| value.nil? || value == [] }
      end

      def fetch_notes(fetches)
        fetches.map do |collection, fetch|
          "#{collection}.zip #{fetch.not_modified? ? 'not modified (304)' : "sha256 #{fetch.sha&.slice(0, 12)}"}"
        end.push(attic_notes(fetches.values.flat_map(&:atticked))).compact.join("; ")
      end
    end
  end
end

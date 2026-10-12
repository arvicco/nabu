# frozen_string_literal: true

require_relative "eltec_tei_parser"

module Nabu
  module Adapters
    # eltec-srp — ELTeC-srp, the Serbian novel collection of the European
    # Literary Text Collection (P117-2; COST Action CA16204 "Distant
    # Reading for European Literary History"; collection editor Cvetana
    # Krstev, JeRTeH & University of Belgrade; doi:10.5281/zenodo.3524056).
    # 100 novels at level 1 (the README's v0.9.0 release note says 90; the
    # repository holds 100 level-1 files and 100 metadata rows, censused
    # 2026-10-11 @355cea8f), first editions 1852–1920, in Serbian Cyrillic
    # (98) and Latin (2), OCR-corrected by the JeRTeH team and its partner
    # libraries.
    #
    # == Shape and fetch
    #
    # github.com/COST-ELTeC/ELTeC-srp: level1/ (the TEI the family reads,
    # 49 MB), level2/ (the 519 MB linguistically annotated twin — lemma/POS/
    # NER, out of this cone: a future silver lane), Orig/, Bounced/, the
    # metadata TSVs. A sparse GitFetch cone (level1 + README.md) keeps the
    # checkout at the text. The companion jerteh/srpELTeC-ijk (46 ijekavian
    # novels, ELTeC-plus encoding) is deliberately NOT fetched: its
    # repository carries no license statement at all (no LICENSE file, no
    # README terms, empty availability in every header — censused
    # 2026-10-11), so its markup layer has no grant; it waits for one.
    #
    # == Identity
    #
    # Document = one novel: urn:nabu:eltec-srp:<xml:id downcased>
    # (SRP18520 → srp18520 — ELTeC's own id, which encodes the reference
    # year). Passages = the eltec-tei family's blocks (head/p/l/trailer),
    # citation <div ordinals>.<block> ("1.5", "2.4.7", "0.1").
    #
    # == The admission rule (in-copyright works excluded by rule)
    #
    # The collection states "All texts included in this collection are in
    # the public domain" — true of US publication-era reckoning, but four
    # authors died less than 70 years ago, and the Serbian (and EU) term is
    # life + 70: Ранковић (d. 1956), Поповић (1957), Секулић (1958),
    # Ђуричић (1987). A work is admitted only when its author's death year
    # (the header's own "(birth-death)") is at or before
    # AUTHOR_DEATH_CUTOFF — 1955, the last year whose authors' works are
    # free on 1 January 2026; the constant is advanced deliberately each
    # January (a code change, so derivation stays a function of the
    # permanent folders). An author whose death year upstream does not
    # record ("????", 13 texts by obscure authors published 1875–1920) is
    # admitted on the collection's own public-domain statement — declared,
    # the orphan class. Excluded texts are discovery skips by rule.
    #
    # == Axes (the mining policy)
    #
    # Date: the firstEdition bibl's typed <date>s (an envelope over every
    # year they carry); without one, ELTeC's reference year from the id
    # (SRP18840 → 1884, raw marked as such) — MetadataDates :structured.
    # Place: the firstEdition pubPlace (the publication place, declared
    # coarse). The NAMED EDITION layer rides as metadata "print_source"
    # (the printed edition the text was digitized from — 41 texts name one,
    # several of them modern reprints: Матица српска 1987, Просвета 1990 …)
    # and "digital_source"; the respStmt chain as "responsibility"; ELTeC's
    # sampling keys as "eltec". Script: the root xml:lang (sr = Cyrillic,
    # sr-Latn = Latin) as metadata "script".
    #
    # == License
    #
    # README "Licence", verbatim: "All texts included in this collection
    # are in the public domain. The textual markup is provided with a
    # Creative Commons Attribution International 4.0 licence (CC BY,
    # https://creativecommons.org/licenses/by/4.0/)." → attribution. 81 of
    # 100 headers also carry <licence target=".../by/4.0/">; the other 19
    # leave publicationStmt empty and ride the collection grant.
    class EltecSrp < Nabu::Adapter
      REPO_URL = "https://github.com/COST-ELTeC/ELTeC-srp.git"
      SPARSE_PATHS = ["level1", "README.md"].freeze
      TEXT_DIR = "level1"
      LANGUAGE = "srp"
      URN_PREFIX = "urn:nabu:eltec-srp:"

      # const: the life+70 boundary as of 1 January 2026 — advance each January, not a corpus claim
      AUTHOR_DEATH_CUTOFF = 1955

      MANIFEST = Nabu::SourceManifest.new(
        id: "eltec-srp",
        name: "ELTeC-srp — the Serbian novel collection of the European Literary Text Collection",
        license: "Texts public domain; markup CC BY 4.0 — the repository README, verbatim: \"All " \
                 "texts included in this collection are in the public domain. The textual markup " \
                 "is provided with a Creative Commons Attribution International 4.0 licence (CC BY, " \
                 "https://creativecommons.org/licenses/by/4.0/).\" Cite: ELTeC-srp, ed. Cvetana " \
                 "Krstev (JeRTeH & University of Belgrade), COST Action CA16204, " \
                 "doi:10.5281/zenodo.3524056. Works whose author died after " \
                 "#{AUTHOR_DEATH_CUTOFF} are excluded by rule (life + 70).",
        license_class: "attribution",
        upstream_url: "https://github.com/COST-ELTeC/ELTeC-srp",
        parser_family: "eltec-tei"
      )

      def self.manifest = MANIFEST

      def fetch(workdir, progress: nil, force: false)
        git_fetch!(repo_url: repo_url, workdir: workdir, progress: progress, force: force,
                   sparse: SPARSE_PATHS)
      end

      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        candidates(workdir).each do |path, header|
          next unless admitted?(header)

          yield Nabu::DocumentRef.new(source_id: MANIFEST.id, id: urn_for(header),
                                      path: File.expand_path(path), metadata: {})
        end
      end

      def discovery_skips(workdir)
        excluded = candidates(workdir).reject { |_path, header| admitted?(header) }
        Nabu::Adapter::DiscoverySkips.new(
          skipped_by_rule: excluded.size,
          notes: excluded.map do |path, header|
            "#{File.basename(path)}: #{header.author} d. #{header.author_death} — in copyright " \
              "(life + 70; cutoff #{AUTHOR_DEATH_CUTOFF})"
          end
        )
      end

      def parse(document_ref)
        parsed = parser.parse(document_ref.path)
        header = parsed.header
        unless urn_for(header) == document_ref.id
          raise Nabu::ParseError, "#{document_ref.path}: xml:id #{header.xml_id} does not match #{document_ref.id}"
        end

        document = Nabu::Document.new(urn: document_ref.id, language: LANGUAGE,
                                      canonical_path: document_ref.path, title: header.title,
                                      metadata: metadata_for(header))
        parsed.blocks.each_with_index do |block, index|
          annotations = { "kind" => block.kind }
          annotations["page"] = block.page if block.page
          document << Nabu::Passage.new(urn: "#{document_ref.id}:#{block.citation}", language: LANGUAGE,
                                        text: block.text, sequence: index + 1, annotations: annotations)
        end
        raise Nabu::ParseError, "#{document_ref.id}: no text blocks" if document.empty?

        document
      rescue Nabu::ValidationError => e
        raise Nabu::ParseError, "#{document_ref.path}: #{e.message}"
      end

      private

      # Split out so the fetch test can point a singleton at a local repo.
      def repo_url = REPO_URL

      def parser = @parser ||= EltecTeiParser.new

      def candidates(workdir)
        Dir.glob(File.join(workdir, TEXT_DIR, "*.xml")).map { |path| [path, parser.header(path)] }
      end

      def admitted?(header)
        header.author_death.nil? || header.author_death <= AUTHOR_DEATH_CUTOFF
      end

      def urn_for(header) = "#{URN_PREFIX}#{header.xml_id.downcase}"

      def metadata_for(header)
        {
          "eltec_id" => header.xml_id,
          "title_en" => header.title_en,
          "author" => header.author,
          "author_birth" => header.author_birth,
          "author_death" => header.author_death,
          "author_refs" => presence(header.author_refs),
          "title_refs" => presence(header.title_refs),
          "words" => header.words,
          "script" => header.lang_tag.to_s.end_with?("Latn") ? "Latn" : "Cyrl",
          "date" => date_for(header),
          "place" => header.first_edition&.place,
          "first_edition" => presence(header.first_edition&.to_h),
          "print_source" => presence(header.print_source&.to_h),
          "digital_source" => presence(header.digital_source&.to_h),
          "responsibility" => presence(header.responsibility),
          "eltec" => presence(header.text_desc),
          "licence" => header.licence
        }.compact
      end

      # The firstEdition's typed years as an envelope; else ELTeC's
      # reference year from the id (SRP18840 → 1884).
      def date_for(header)
        years = header.first_edition&.years.to_a
        unless years.empty?
          return { "not_before" => years.min, "not_after" => years.max,
                   "raw" => header.first_edition.raw_date }
        end

        year = header.xml_id[/\ASRP(\d{4})/, 1]&.to_i or return nil
        { "not_before" => year, "not_after" => year, "raw" => "#{year} (ELTeC reference year, from the id)" }
      end

      def presence(value)
        value.nil? || (value.respond_to?(:empty?) && value.empty?) ? nil : value
      end
    end
  end
end

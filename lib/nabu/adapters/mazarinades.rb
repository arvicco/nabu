# frozen_string_literal: true

require "csv"

require_relative "antonomaz_tei_parser"
require_relative "source_read"

module Nabu
  module Adapters
    # Mazarinades — the Antonomaz corpus (github.com/Antonomaz/Corpus;
    # Projet ANTONOMAZ, Sorbonne Université — Karine Abiven, Gaël Lejeune).
    # The pamphlets of the Fronde (1648–1653), the libels, songs, letters,
    # official acts and burlesque verse printed in their thousands against
    # (and for) Cardinal Mazarin, encoded in TEI from public digitizations
    # (Gallica, the Bibliothèque Mazarine's Mazarinum, Google Books) and
    # classed by Célestin Moreau's Bibliographie des mazarinades (1850–51)
    # numbers, its supplements, and Socard's and Labadie's additions.
    #
    # == Upstream's delivery grains (census 2026-11-05, main @84f319b9,
    #    last push 2025-02-26; GitHub tree listing + every Mazarinades/ file
    #    read)
    #
    # 7,171 blobs:
    # - Mazarinades/**/*.xml — 3,080 TEI files: THE DOCUMENT GRAIN, one
    #   pamphlet per file. 2,838 in the Moreau hundreds (1-100 …
    #   4001-4100), Moreau_sup1/2/3 (37/55/19), Socard (26), Labadie (46),
    #   Bibliotheque_Mazarine (43 — pieces none of the three bibliographers
    #   recorded) and Antonomaz (3). The file suffix names the digitization:
    #   GBOOKS 1,951 · MAZ 620 · GALL 483 · MANUAL 21 · BOR 2 · BORD 1 ·
    #   BIS 1 · none 1. 13 files are malformed XML (all 13 MANUAL-suffixed
    #   — 12 hand transcriptions, one Kraken file: an unescaped "&",
    #   mismatched tags) — discovered and QUARANTINED at parse
    #   (ParseError), never skipped silently.
    # - Mazarinades/filecount.txt and Mazarinades/1-100/diff.txt — two
    #   working files beside the pamphlets: SKIPPED BY RULE.
    # - Doublons/** — 955 (953 TEI + README.md + a stray macOS
    #   .textClipping): further exemplars of Moreau numbers already encoded
    #   (another library's copy, another state or edition); upstream's
    #   README: "ils n'ont à priori pas été relus" (not reviewed). REJECTED,
    #   outside the sparse cone; specimens pinned, skipped by rule where
    #   present.
    # - Mazarinades_jsons/** — 3,065 JSON exports of the TEI (upstream's
    #   tei_to_json script): REJECTED (a derivative; outside the cone).
    # - output/** — 22 generated reports (corpus.csv, statistics, author
    #   tables): REJECTED, outside the cone — except output/reviewed_files.csv,
    #   the first-page review ledger, which rides the cone and is READ as
    #   per-document metadata (first_page_review), never as a document.
    # - script/** (40), .github/ and the top-level files (README.md — the
    #   licence evidence, riding the cone —, Antonomaz.xpr, apply_titles.py,
    #   titres_corriges_Moreau.json, Requete_sous_corpus.md, .gitignore):
    #   repository furniture, REJECTED.
    # Reconciliation: upstream advertises no total; its own
    # Mazarinades/filecount.txt names the 48 folders, and
    # output/Mazarinades_filecount.txt their per-folder counts (summing to
    # 3,065 — the JSON tree's figure, the TEI tree has grown 15 since). The
    # census IS the claim: 3,080 TEI = 3,067 well-formed + 13 malformed
    # (quarantined); in a live sparse checkout skipped-by-rule = 4 (the two
    # working files, README.md, the review ledger). The rejected trees never
    # materialize and are counted by rule only where a workdir carries them.
    #
    # == Text: OCR, declared per document
    #
    # The projectDesc states the text's origin, and it is read per file:
    # 3,057 say "L'édition présentée ici est issue d'un processus
    # d'OCRisation réalisé avec Kraken" (10 name kraken4.3.13.dev18) →
    # text_nature "machine-ocr" (the excluding label) with the statement in
    # text_origin; upstream hand-corrected the FIRST page only (pb
    # manual_correction="yes" — 3,046 files; a handful also a second or
    # third page; the review ledger tracks it), the body pages are raw
    # Kraken output (long s, ligatures and misreadings ride as recognized —
    # canonical means canonical). 23 say "transcription manuelle réalisée
    # par Karine Abiven": they carry NO OCR label (a hand transcription is
    # not OCR; the madurai precedent), the statement in text_origin.
    #
    # == License — the licence element governs
    #
    # README, verbatim: "Les textes sont publiés sous la licence CC BY 4.0"
    # (linked to creativecommons.org/licenses/by/4.0/). Every well-formed
    # file carries <licence target="https://creativecommons.org/licenses/by/4.0"/>
    # — inside <availability status="restricted" n="cc-by"> (3,034) or
    # n="NaN" (33). The ODDITY, recorded: TEI's availability@status
    # "restricted" contradicts an open licence; it is the project template's
    # default (identical on every file), and the licence element plus the
    # README's explicit statement govern → class attribution. Both ride
    # every document's metadata (licence, availability) verbatim.
    #
    # == Identity (FROZEN minting)
    #
    # urn:nabu:mazarinades:<file stem> — the stem is upstream's own
    # identifier, unique across the tree (urn:nabu:mazarinades:Moreau1483_GBOOKS,
    # …:Moreau1suppl218_GALL, …:Labadie332_GALL, …:BM49258_MAZ); the
    # root xml:id disagrees with it on 49 files, so the path names the
    # document. Passage = printed page (AntonomazTeiParser page keys):
    # …:Moreau1483_GBOOKS:1, …:Moreau2135_MAZ:v12, a pb-less transcription
    # …:pre.
    #
    # == Mined axes (the bibliographic entry, aggressively)
    #
    # DATE — the bibl's typed dates (Moreau 2,372 · Mazarine 621 · Labadie
    # 22 · Socard 20 · Carrier 15 · Antonomaz 12 · BM_Lyon 2 · BnF 1, by
    # first date): the envelope from the narrowest year span among them
    # (notBefore/notAfter, else @when; upstream order breaks ties), raw =
    # "<text> (<source>)"; every date rides "dates" whole (Carrier's
    # day-precise datings included). "Sans date" (68) dates nothing.
    # Envelopes: 3,029 of 3,067 dated, 1634–1663 (1649 ×1,413 · 1652 ×941 · 1651 · 1650 · 1648 …).
    # PLACE — the imprint pubPlace with its GeoNames ref: Paris 2,192 ·
    # Bordeaux · Orléans · Rouen · Pontoise · Saint-Germain-en-Laye …;
    # "Sans lieu" names none (715 unplaced). Upstream's template stamps Paris's id
    # (geonames:2988507) on five other towns (8 docs: Anvers ×4, Toulouse,
    # Leyde, Bourg, Saint-Germain-en-Laye): that ref rides only on a name that says
    # Paris ("Amsterdam (Paris)", a false imprint, keeps it); the name
    # always rides. Raw pubPlace in pub_place.
    # Beside them: catalog + catalog_number (from the stem), collection
    # (the folder), digitization (the suffix), title (the Moreau-normalized
    # main title; the print's own spelling in title_print), authors/author
    # (ISNI refs, roles alleged_author/speaker kept), printer (the
    # publisher persName), pages + format (in-4), moreau_entry and
    # mazarine_note (the abstracts verbatim), genre/form (textClass terms),
    # subjects, events (Moreau's episode settings: id, label, date),
    # holding (the copy's library and shelfmark), identifiers (the
    # Mazarine BM numbers), digitization_url, the descriptor flags,
    # revisions, licence, availability.
    #
    # == Language
    #
    # langUsage, read by its LABEL (the label is right where the ident is
    # not: Moreau1168 is ident "fra", "Document en latin"): français → fra
    # (3,041), latin → lat (26), italien → ita (4), néerlandais → nld,
    # allemand → deu, espagnol → spa, gascon → oci (Gascon is an Occitan
    # variety; the label rides language_label), picard → pcd and normand
    # → nrf (bare ISO 639-3 codes — NO registry node exists for either;
    # flagged for the lect-scope review, never minted here), "Patois
    # francilien" and "pseudo-patois (normand)" → fra (French peasant
    # patois and a Parisian literary imitation of Norman; the label rides).
    # "Passages en latin" is a partial claim: the document stays French and
    # the code joins "languages". fra resolves to fr:cls by the per-source
    # override (config/lect_overrides.yml).
    class Mazarinades < Nabu::Adapter
      REPO_URL = "https://github.com/Antonomaz/Corpus"
      URN_PREFIX = "urn:nabu:mazarinades:"
      TEXT_DIR = "Mazarinades"
      REVIEW_LEDGER = "output/reviewed_files.csv"

      # The sparse cone (GitFetch no-cone patterns, anchored).
      SPARSE_CONE = ["/Mazarinades/", "/README.md", "/#{REVIEW_LEDGER}"].freeze

      DUPLICATE_RULE = "a duplicate exemplar of a Moreau number already encoded (Doublons — upstream: " \
                       "\"ils n'ont à priori pas été relus\")"
      REJECTED_TREES = {
        "Doublons" => DUPLICATE_RULE,
        "Mazarinades_jsons" => "a JSON derivative of a TEI file (upstream's tei_to_json export)",
        "output" => "upstream's generated reports and statistics",
        "script" => "upstream's processing scripts",
        ".github" => "repository furniture"
      }.freeze
      WORKING_FILE_RULE = "a working file beside the pamphlets (a folder list / a diff), not a pamphlet"
      FURNITURE_RULE = "repository furniture (README, project file, scripts, title tables)"
      LEDGER_RULE = "the first-page review ledger — read as per-document metadata, not a document"

      COLLECTIONS = {
        "Moreau_sup1" => "Moreau supplement 1", "Moreau_sup2" => "Moreau supplement 2",
        "Moreau_sup3" => "Moreau supplement 3", "Socard" => "Socard", "Labadie" => "Labadie",
        "Bibliotheque_Mazarine" => "Bibliothèque Mazarine", "Antonomaz" => "Antonomaz"
      }.freeze
      MOREAU_HUNDRED = /\A\d+-\d+\z/
      STEM = /\A(?<catalog>[A-Za-z]+?)(?<number>\d[^_]*)?(?:_(?<suffix>[A-Z]+))?\z/

      # langUsage labels → language codes (class note). nil = a partial
      # claim ("Passages en …"), never the document's language.
      LANGUAGE_LABELS = {
        "français" => "fra", "latin" => "lat", "italien" => "ita", "néerlandais" => "nld",
        "allemand" => "deu", "espagnol" => "spa", "gascon" => "oci", "picard" => "pcd",
        "normand" => "nrf"
      }.freeze
      FRENCH_PATOIS = /\A(?:Document en )?(?:Patois francilien|pseudo-patois)/i

      PARIS_GEONAMES = "geonames:2988507"
      NO_PLACE = /\Asans lieu/i
      YEAR = /\A(\d{4})/

      OCR_NOTE = "Kraken OCR of a public digitization (Gallica, Mazarinum, Google Books); upstream " \
                 "hand-corrected the first page only — the body pages ride as recognized"

      MANIFEST = Nabu::SourceManifest.new(
        id: "mazarinades",
        name: "Mazarinades — the Antonomaz corpus of Fronde pamphlets (1648–1653)",
        license: "CC BY 4.0 — the repository README, verbatim: \"Les textes sont publiés sous la licence " \
                 "CC BY 4.0\" (https://creativecommons.org/licenses/by/4.0/); every file's TEI header " \
                 "carries <licence target=\"https://creativecommons.org/licenses/by/4.0\"/> (inside an " \
                 "availability whose status=\"restricted\" is the project template's default — the licence " \
                 "element governs). Credit: Projet ANTONOMAZ / Sorbonne Université.",
        license_class: "attribution",
        upstream_url: REPO_URL,
        parser_family: "antonomaz-tei",
        credit: "Projet ANTONOMAZ / Sorbonne Université (K. Abiven, G. Lejeune et al.), " \
                "github.com/Antonomaz/Corpus — CC BY 4.0"
      )

      def self.manifest = MANIFEST

      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        reviews = review_ledger(workdir)
        census(workdir).each do |entry|
          next unless entry[:accepted]

          review = reviews[File.basename(entry[:path])]
          yield Nabu::DocumentRef.new(
            source_id: MANIFEST.id, id: entry[:urn], path: entry[:path],
            metadata: entry[:metadata].merge(review ? { "first_page_review" => review } : {})
          )
        end
      end

      def discovery_skips(workdir)
        entries = census(workdir)
        notes = entries.filter_map { |entry| "#{entry[:rel]}: #{entry[:skip]}" if entry[:skip] }
        strays = entries.filter_map { |entry| "#{entry[:rel]}: #{entry[:stray]}" if entry[:stray] }
        Nabu::Adapter::DiscoverySkips.new(skipped_by_rule: notes.size, unrecognized: strays.size,
                                          notes: notes + strays)
      end

      def parse(document_ref)
        parsed = AntonomazTeiParser.new.parse(document_ref.path)
        header = parsed.header
        language = self.class.document_language(header.languages)
        document = Nabu::Document.new(
          urn: document_ref.id, language: language, canonical_path: document_ref.path,
          title: header.title || header.bibl_title,
          metadata: document_ref.metadata.merge(metadata_for(header, language))
        )
        parsed.pages.each_with_index do |page, index|
          document << Nabu::Passage.new(urn: "#{document_ref.id}:#{page.key}", language: language,
                                        text: page.text, sequence: index + 1, annotations: annotations_for(page))
        end
        raise Nabu::ParseError, "#{document_ref.path}: no page carries text" if document.empty?

        document
      rescue Nabu::ValidationError => e
        raise Nabu::ParseError, "#{document_ref.path}: #{e.message}"
      end

      def fetch(workdir, progress: nil, force: false)
        git_fetch!(repo_url: repo_url, workdir: workdir, progress: progress, force: force, sparse: SPARSE_CONE)
      end

      # Folder + file stem → catalog metadata (public: tests pin each rule).
      def self.catalog_metadata(folder, stem)
        match = STEM.match(stem)
        collection = MOREAU_HUNDRED.match?(folder) ? "Moreau" : COLLECTIONS.fetch(folder, folder)
        {
          "collection" => collection, "catalog" => match&.[](:catalog),
          "catalog_number" => match&.[](:number), "digitization" => match&.[](:suffix)
        }.compact
      end

      # The narrowest year envelope among the typed dates (class note).
      def self.date_envelope(dates)
        candidates = dates.filter_map do |date|
          low = year(date["not_before"]) || year(date["when"])
          high = year(date["not_after"]) || year(date["when"])
          next unless low && high

          [high - low, date, low, high]
        end
        _span, date, low, high = candidates.min_by.with_index { |(span, *), index| [span, index] }
        return nil unless date

        { "not_before" => low, "not_after" => high,
          "raw" => [date["text"] || date["when"], date["source"] && "(#{date['source']})"].compact.join(" ") }
      end

      def self.year(value)
        digits = value.to_s[YEAR, 1] or return nil
        Integer(digits, 10)
      end

      # pubPlace → the place hash (class note), nil when it names none.
      def self.place_claim(pub_place)
        name = pub_place&.[]("name")
        return nil if name.nil? || name.match?(NO_PLACE)

        ref = pub_place["ref"]
        ref = nil if ref == PARIS_GEONAMES && !name.include?("Paris")
        ref = nil unless ref.to_s.match?(/\Ageonames:[1-9]\d*\z/)
        { "ancient" => name, "geonames" => ref }.compact
      end

      # One langUsage entry → its code; nil for a partial ("Passages en")
      # claim (class note).
      def self.language_code(entry)
        label = entry["label"].to_s
        return nil if label.match?(/\APassages en /i)
        return "fra" if label.match?(FRENCH_PATOIS)

        named = label[/\ADocument en (.+)\z/i, 1]&.strip&.downcase
        return LANGUAGE_LABELS[named] if named && LANGUAGE_LABELS.key?(named)

        ident = entry["ident"].to_s
        ident.empty? || ident == "other" ? nil : ident
      end

      def self.document_language(languages)
        languages.lazy.filter_map { |entry| language_code(entry) }.first || "fra"
      end

      private

      # Test seam (the house pattern): fetch tests point this at a local rig.
      def repo_url
        REPO_URL
      end

      # One entry per file in the tree: accepted (urn/path/metadata),
      # skipped by rule (skip:), or a stray (stray:). Dotfiles (.git,
      # .attic, .gitignore) are not walked.
      def census(workdir)
        return [] unless Dir.exist?(workdir)

        Dir.glob("**/*", base: workdir).sort.filter_map do |rel|
          path = File.join(workdir, rel)
          next unless File.file?(path)

          classify(rel, File.expand_path(path))
        end
      end

      def classify(rel, path)
        tree, inner = rel.split("/", 2)
        return { rel: rel, skip: FURNITURE_RULE } if inner.nil?
        return { rel: rel, skip: LEDGER_RULE } if rel == REVIEW_LEDGER
        return { rel: rel, skip: REJECTED_TREES[tree] } if REJECTED_TREES.key?(tree)
        return { rel: rel, stray: "a tree no rule names (a new upstream folder?)" } unless tree == TEXT_DIR

        pamphlet(rel, inner, path)
      end

      def pamphlet(rel, inner, path)
        folder, name = inner.split("/", 2)
        return { rel: rel, skip: WORKING_FILE_RULE } if name.nil? || !name.end_with?(".xml")
        return { rel: rel, stray: "a nested path no rule names" } if name.include?("/")

        stem = File.basename(name, ".xml")
        { rel: rel, accepted: true, path: path, urn: "#{URN_PREFIX}#{stem}",
          metadata: self.class.catalog_metadata(folder, stem).merge("file" => rel) }
      end

      # output/reviewed_files.csv → { "Moreau1021_GBOOKS.xml" => {...} };
      # only reviewed rows or rows with a remark are claims.
      def review_ledger(workdir)
        path = File.join(workdir, REVIEW_LEDGER)
        return {} unless File.file?(path)

        CSV.parse(SourceRead.utf8_file(path, label: path), headers: true).each_with_object({}) do |row, out|
          reviewed = row["reviewed_status"].to_s.strip == "Y"
          remark = row["remark"].to_s.strip
          remark = nil if remark.empty? || remark == "NA"
          next unless reviewed || remark

          corrected = row["corrected_before"].to_s.strip
          out[row["file"].to_s.strip] = {
            "reviewed" => reviewed, "corrected_before" => corrected.empty? ? nil : corrected == "Y", "remark" => remark
          }.compact
        end
      rescue CSV::MalformedCSVError => e
        raise Nabu::FetchError, "#{path}: unreadable review ledger (#{e.message})"
      end

      def metadata_for(header, language)
        codes = header.languages.filter_map { |entry| self.class.language_code(entry) || partial_code(entry) }.uniq
        authors = header.authors
        {
          "xml_id" => header.xml_id, "title_print" => header.bibl_title, "title_source" => header.title_source,
          "authors" => presence(authors), "author" => authors.first&.[]("name"),
          "printer" => header.publisher&.[]("name"), "publisher" => header.publisher,
          "date" => self.class.date_envelope(header.dates), "dates" => presence(header.dates),
          "place" => self.class.place_claim(header.pub_place), "pub_place" => header.pub_place,
          "pages" => header.extent_pages, "format" => header.format,
          "moreau_entry" => header.abstracts["Moreau"], "mazarine_note" => header.abstracts["Mazarine"],
          "abstracts" => presence(header.abstracts.except("Moreau", "Mazarine")),
          "genre" => presence(header.genres), "form" => presence(header.forms),
          "subjects" => presence(header.subjects), "events" => presence(header.settings),
          "holding" => header.holding, "identifiers" => presence(header.identifiers),
          "digitization_url" => header.digitizations.first, "flags" => presence(header.flags),
          "language_label" => language_label(header.languages, language),
          "languages" => codes.size > 1 ? codes : nil,
          "licence" => header.licence, "availability" => header.availability,
          "file_dates" => presence(header.file_dates), "revisions" => presence(header.changes),
          "text_origin" => header.origin_statement
        }.merge(text_nature(header)).compact
      end

      def text_nature(header)
        header.text_origin == :ocr ? { "text_nature" => "machine-ocr", "ocr_note" => OCR_NOTE } : {}
      end

      # A "Passages en latin" claim joins the language list.
      def partial_code(entry)
        named = entry["label"].to_s[/\APassages en (.+)\z/i, 1]&.strip&.downcase
        LANGUAGE_LABELS[named]
      end

      # The label rides when it says more than the code (a dialect, a
      # patois, a code-less language) — never the plain "Document en français".
      def language_label(languages, language)
        label = languages.find { |entry| self.class.language_code(entry) == language }&.[]("label")
        label == "Document en français" ? nil : label
      end

      def annotations_for(page)
        {
          "page" => page.key, "n" => page.n, "vue" => page.vue, "facs" => page.facs,
          "manual_correction" => page.manual_correction || nil,
          "continued_lines" => presence(page.continued_lines), "furniture" => presence(page.furniture),
          "margin_notes" => presence(page.notes), "figures" => presence(page.figures),
          "gaps" => page.gaps.zero? ? nil : page.gaps, "corrections" => presence(page.corrections)
        }.compact
      end

      def presence(value)
        value.nil? || (value.respond_to?(:empty?) && value.empty?) ? nil : value
      end
    end
  end
end

# frozen_string_literal: true

require "csv"

require_relative "dharma_base"

module Nabu
  module Adapters
    # DHARMA text metadata (P118-4): github.com/erc-dharma/mdt-texts — the
    # ERC DHARMA project's per-inscription metadata tables, one CSV per
    # corpus (DaksinaKosala, Pallava, Somavamsin, Telugu; the project's
    # Google-Sheets exports), as a METADATA-ROW source: one zero-passage
    # document per row (the rsti/ebl metadata-only precedent — the asset
    # carries no text; the editions live in the DHARMA estate repos).
    #
    # == Purpose: a dating sidecar with an explicit join key
    #
    # Each row's "Identifier of the text" (INS<Corpus><5 digits>) is the
    # SAME id the DHARMA edition files carry as DHARMA_INS<Corpus>NNNNN.xml,
    # which DharmaBase mints as urn:nabu:<slug>:INS<Corpus>NNNNN. Every
    # document records it as "dharma_text_id" (= the edition urn's last
    # segment) and "dharma_edition_stem" (= the edition file stem), so a
    # later enrichment can walk mdt → edition and project the dates onto
    # the edition documents. That projection is deliberately NOT here
    # (one adapter per change).
    #
    # == Upstream shape (census 2026-10-11, commit e445bb5)
    #
    # 828 data rows (DaksinaKosala 100, Pallava 530, Somavamsin 100,
    # Telugu 98); rows 1-2 are field-group banners, row 3 the HEADER (63
    # columns: a leading "0" counter, "Fields", then the fields;
    # "Alternative designation" twice), row 4 "Description of the fields",
    # data from row 5. Cells escape commas as the literal token "COMMA";
    # multi-valued cells join with "$". 94 rows are PLACEHOLDERS (ids,
    # management and rights only — DaksinaKosala 42, Somavamsin 52): they
    # mint nothing and are censused skip-by-rule (a later fill mints them).
    #
    # Fill census (data rows): dates live almost entirely in Telugu (Date
    # CE 20, Date range CE 40, evidence 59 of 98) plus ONE Pallava row; all
    # are CE already — NO era-typed year occurs, so the era table is not
    # consumed here. No findspot column exists: "Location on the
    # artefact/conglomerate artefact/monument" (Telugu 95 rows) is
    # free location prose ("On a stone lying in a field at Addanki") —
    # recorded verbatim as "artefact_location", never minted as a place.
    #
    # == License
    #
    # Repo LICENCE.txt: CC BY 4.0. Every row declares "Distribution rights
    # of the metadata" = CC0 (828/828) — the row grant governs and is
    # recorded verbatim per document; a row declaring anything else
    # quarantines. Class `attribution` — the repo floor, conservative (CC0
    # rows sit inside it).
    class DharmaMdt < Nabu::Adapter
      SLUG = "dharma-mdt"
      REPO_URL = "https://github.com/erc-dharma/mdt-texts"
      CSV_DIR = "csv"
      FILE_PATTERN = /\ADHARMA_mdt_(?<corpus>[A-Za-z]+)_v\d+\.csv\z/

      HEADER_ROW = 2  # 0-based: row 3
      DATA_START = 4  # row 4 is the field-description row

      MANIFEST = Nabu::SourceManifest.new(
        id: SLUG,
        name: "DHARMA text metadata (mdt-texts) — dating and typology rows for the DHARMA inscription corpora",
        license: "CC0 — each row's \"Distribution rights of the metadata\" cell (828/828 rows, " \
                 "census 2026-10-11), recorded verbatim per document; the repository LICENCE.txt " \
                 "is CC BY 4.0, so the class is attribution (the repo floor)",
        license_class: "attribution",
        upstream_url: REPO_URL,
        parser_family: "dharma-mdt-csv",
        credit: "DHARMA — text metadata of the DHARMA inscription corpora (ERC no. 809994, " \
                "EFEO/CNRS; erc-dharma/mdt-texts on GitHub). Cite the corpus and its editors."
      )

      # The row-level metadata grant every row must carry.
      METADATA_LICENSE = "CC0"

      # Language names → stored codes, the witnessed vocabulary (census:
      # Sanskrit, Telugu, Tamil). An unseen name quarantines (the rsti rule).
      LANGUAGE_CODES = { "Sanskrit" => "san", "Telugu" => "tel", "Tamil" => "tam" }.freeze
      UNKNOWN_LANGUAGE = "und"

      # Management/rights/id columns — a row with nothing outside these is
      # a placeholder (class note).
      BOILERPLATE = ["0", "Fields", "Identifier of the resource", "DHARMA import", "Editor of the metadata",
                     "Date of the edition", "Contributor of the metadata", "Reviewer", "Date of review",
                     "Project", "Corpus", "Distribution rights of the metadata", "Identifier of the text",
                     "Project responsible for publication",
                     "Distribution rights of the text edition"].freeze

      # Single-valued columns carried verbatim (decoded) → metadata key.
      SCALARS = {
        "Origin of the metadata" => "origin_of_metadata",
        "Designation" => "designation",
        "Location on the artefact/conglomerate artefact/monument" => "artefact_location",
        "ID of the conglomerate artefact" => "conglomerate_artefact_id",
        "ID of the monument" => "monument_id",
        "Lettering technique" => "lettering_technique",
        "Lines (observed)" => "lines_observed",
        "Lines (estimated)" => "lines_estimated",
        "Lines per zone(s)" => "lines_per_zone",
        "Dimensions of text zone(s)" => "text_zone_dimensions",
        "Height of glyph" => "glyph_height",
        "Width of glyph" => "glyph_width",
        "Other instances" => "other_instances",
        "Type of filiation" => "filiation_type",
        "Reissue date" => "reissue_date",
        "Remarks" => "remarks",
        "Link to external repository of images" => "image_repository",
        "Editor of the metadata" => "metadata_editor",
        "Date of the edition" => "metadata_edited"
      }.freeze

      # "$"-joined multi-valued columns → metadata key (arrays).
      LISTS = {
        "Alternative identifier" => "alternative_ids",
        "Alternative designation" => "alternative_designations",
        "ID of the artefact(s)" => "artefact_ids",
        "Keyword(s)" => "keywords",
        "Identifier of the surrogate" => "surrogate_ids",
        "Identifier of the digital image" => "image_ids"
      }.freeze

      # A Date CE / Date range CE cell: "849" or "625-675" (CE years).
      YEAR_SPAN = /\A(\d{1,4})(?:\s*-\s*(\d{1,4}))?\z/

      def self.manifest = MANIFEST

      def initialize
        super
        @tables = {}
      end

      # One ref per substantive row across the four CSVs, sorted; the
      # first row wins a repeated id (censused, never seen upstream).
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        index(workdir)[:refs].each(&block)
      end

      def discovery_skips(workdir)
        found = index(workdir)
        Nabu::Adapter::DiscoverySkips.new(
          skipped_by_rule: found[:placeholders].size + found[:duplicates].size,
          unrecognized: found[:strays].size,
          notes: found[:placeholders].map { |id| "#{id}: placeholder row (ids and rights only)" } +
                 found[:duplicates].map { |id| "#{id}: repeated row, first wins" } +
                 found[:strays].map { |name| "#{name}: not a DHARMA_mdt_<Corpus> table" }
        )
      end

      def parse(document_ref)
        row = table(document_ref.path).fetch(document_ref.metadata.fetch("row"))
        id = document_ref.id.delete_prefix("urn:nabu:#{SLUG}:")
        verify_rights!(row, id)
        languages = list(row, "Language 1", "Language 2", "Language 3", "Language 4")
        Nabu::Document.new(
          urn: document_ref.id, language: document_language(languages, id),
          canonical_path: document_ref.path,
          title: first(row, "Designation") || id,
          metadata: row_metadata(row, id, document_ref, languages)
        )
      end

      # The memoized tables/index describe the PRE-fetch tree (the breaker
      # reads them); a fetch drops them so discover re-reads the new tree.
      def fetch(workdir, progress: nil, force: false)
        git_fetch!(repo_url: repo_url, workdir: workdir, progress: progress, force: force,
                   sparse: [CSV_DIR, "README.md", "LICENCE.txt"])
      ensure
        @tables = {}
        @index = {}
      end

      private

      # Seam for tests (the house local-git pattern).
      def repo_url = REPO_URL

      def table_paths(workdir)
        Dir.glob(File.join(workdir, CSV_DIR, "*.csv")).sort # rubocop:disable Lint/RedundantDirGlobSort -- explicit sort documents the urn-order guarantee
      end

      def index(workdir)
        @index ||= {}
        @index[File.expand_path(workdir)] ||= build_index(workdir)
      end

      def build_index(workdir)
        found = { refs: {}, placeholders: [], duplicates: [], strays: [] }
        table_paths(workdir).each do |path|
          name = File.basename(path)
          next found[:strays] << name unless FILE_PATTERN.match?(name)

          table(path).each_with_index { |row, position| index_row(found, row, position, path) }
        end
        found.merge(refs: found[:refs].values.sort_by(&:id))
      end

      def index_row(found, row, position, path)
        id = first(row, "Identifier of the text") or return
        return found[:placeholders] << id if placeholder?(row)
        return found[:duplicates] << id if found[:refs].key?(id)

        found[:refs][id] = Nabu::DocumentRef.new(
          source_id: SLUG, id: "urn:nabu:#{SLUG}:#{id}", path: File.expand_path(path),
          metadata: { "row" => position, "corpus" => first(row, "Corpus") }
        )
      end

      # The data rows of one CSV as [[header, value], …] pair lists (the
      # header repeats a name, so pairs, not a Hash), memoized per path.
      def table(path)
        @tables[File.expand_path(path)] ||= begin
          rows = CSV.read(path, encoding: "bom|utf-8")
          header = rows.fetch(HEADER_ROW).map { |cell| cell.to_s.strip }
          (rows[DATA_START..] || []).map { |cells| header.zip(cells.map { |cell| decode(cell) }) }
        end
      rescue CSV::MalformedCSVError => e
        raise Nabu::ParseError, "#{path}: malformed CSV: #{e.message}"
      end

      # Upstream's comma escape, then NFC; blank → nil.
      def decode(cell)
        value = cell.to_s.gsub("COMMA", ",").strip
        value.empty? ? nil : Nabu::Normalize.nfc(value)
      end

      def values(row, name) = row.filter_map { |header, value| value if header == name }

      def first(row, name) = values(row, name).first

      def list(row, *names)
        names.flat_map { |name| values(row, name) }.flat_map { |value| value.split("$") }
                                                   .map(&:strip).reject(&:empty?)
      end

      def placeholder?(row)
        row.none? { |header, value| value && !BOILERPLATE.include?(header) }
      end

      def verify_rights!(row, id)
        rights = first(row, "Distribution rights of the metadata")
        return if rights == METADATA_LICENSE

        raise Nabu::ParseError, "#{id}: metadata rights #{rights.inspect} != #{METADATA_LICENSE} — " \
                                "re-verify the grant before ingesting"
      end

      def document_language(languages, id)
        return UNKNOWN_LANGUAGE if languages.empty?

        LANGUAGE_CODES.fetch(languages.first) do
          raise Nabu::ParseError, "#{id}: unknown language #{languages.first.inspect} — the witnessed " \
                                  "vocabulary is #{LANGUAGE_CODES.keys.join(', ')}; extend " \
                                  "DharmaMdt::LANGUAGE_CODES deliberately"
        end
      end

      def row_metadata(row, id, document_ref, languages)
        metadata = {
          "dharma_text_id" => id,
          "dharma_edition_stem" => "#{DharmaBase::FILE_PREFIX}#{id}",
          "corpus" => document_ref.metadata["corpus"],
          "text_layer" => "none",
          "metadata_license" => first(row, "Distribution rights of the metadata"),
          "edition_license" => first(row, "Distribution rights of the text edition"),
          "languages" => languages,
          "text_types" => list(row, "Text type 1", "Text type 2", "Text type 3", "Text type 4"),
          "scripts" => scripts(row),
          "bibliography" => bibliography(row)
        }
        SCALARS.each { |header, key| metadata[key] = first(row, header) }
        LISTS.each { |header, key| metadata[key] = list(row, header) }
        metadata.merge!(dating(row))
        metadata.reject { |_key, value| value.nil? || (value.respond_to?(:empty?) && value.empty?) }
      end

      # One entry per declared language slot: its script classification
      # and maturity, verbatim.
      def scripts(row)
        (1..4).filter_map do |slot|
          entry = { "language" => first(row, "Language #{slot}"),
                    "classification" => first(row, "Script classification #{slot}"),
                    "maturity" => first(row, "Script maturity #{slot}") }.compact
          entry unless entry.empty?
        end
      end

      def bibliography(row)
        { "primary" => list(row, "Bibliographic references (primary)"),
          "secondary" => list(row, "Bibliographic references (secondary)") }
          .reject { |_kind, refs| refs.empty? }
      end

      # The :structured date envelope from Date CE (a point or, as upstream
      # sometimes writes it, a range) else Date range CE; certainty,
      # precision and evidence ride along. An unparseable cell rides raw
      # as date_raw — never a guessed bound.
      def dating(row)
        raw = first(row, "Date CE") || first(row, "Date range CE")
        return {} if raw.nil?

        match = YEAR_SPAN.match(raw) or return { "date_raw" => raw }
        low = Integer(match[1], 10)
        high = match[2] ? Integer(match[2], 10) : low
        { "date" => { "not_before" => low, "not_after" => high, "raw" => raw,
                      "certainty" => first(row, "Date certainty"),
                      "precision" => first(row, "Date precision"),
                      "evidence" => first(row, "Date evidence") }.compact }
      end
    end
  end
end

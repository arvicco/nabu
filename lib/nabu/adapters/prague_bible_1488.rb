# frozen_string_literal: true

require_relative "page_xml_parser"

module Nabu
  module Adapters
    # prague-bible-1488 — "HTR Winter School 2024 - Medieval Czech - Prague
    # Bible (1488)" (P116-1; Zenodo record 14524858, DOI
    # 10.5281/zenodo.14524858, v1.0, published 2024-12-19): a semi-
    # diplomatic ground-truth transcription of selected pages of the Prague
    # Bible (Bible pražská, printed 1488; Vienna, ÖNB Ink 13.C.5), Old Czech
    # in bastarda type, prepared by the Medieval Czech group of the Vienna
    # HTR Winter School 2024 and corrected by Anna Michalcová. Transcription
    # rules: Pero OCR's semi-diplomatic rules + Daňhelka's Směrnice — long
    # s, the ¬ line-break hyphen, superscript and abbreviation marks stay
    # in the text; Transkribus tags carry the expansions.
    #
    # == Shape (censused 2026-10-10 from the record's one zip)
    #
    # Bible_prazska_1488-20241219T111644Z-001.zip (36,365,040 bytes, md5
    # f4b09d8c45472f94ee79bff122bc7852) — ONE top dir Bible_prazska_1488/
    # holding 31 page images, page/ (31 PAGE 2013 XML files, every one
    # TranskribusMetadata status="GT"), txt/ (the same lines as plain text —
    # derived, not read), mets.xml + metadata.xml (Transkribus export
    # furniture). ZipFetch strips the top dir; the whole upstream tree lands
    # in canonical/ (no materialized paths). 2,940 TextLines across 80
    # regions (3 regions carry no lines; one whitespace-only line mints
    # nothing) → 31 documents / 2,939 passages; 596 abbreviation spans.
    #
    # Document = one page (urn :p<NNNN>, the Transkribus page number as
    # the file stem spells it — the page/ file stem's other half is the ÖNB
    # image id, kept as metadata). Passage = one TextLine (the page-xml
    # family): citation r<region>.l<line>, both 1-based from upstream's
    # reading order — a column of text is a region; running titles
    # ("Prwnie knihy", "Knihy") are lines like any other (upstream does
    # not type them; declared, not guessed). Abbreviation expansions,
    # unclear spans and superscripts ride as offset-addressed annotations.
    #
    # == Axes
    #
    # Each page is assigned its transcription SEGMENT from the record's own
    # description (book, biblical range, folio range, transcriber —
    # SEGMENTS below, verbatim); segments are contiguous page-number runs,
    # so the assignment is exact even though the record's folio ranges do
    # not map one-to-one onto image counts (folio claims stay segment-
    # level, never invented per page). Date: the edition's 1488 (the
    # record and the htr-united yml: notBefore/notAfter 1488) — every page
    # carries it (MetadataDates :structured). Place: Prague, the edition's
    # own name (Bible pražská) — the imprint place, declared coarse.
    #
    # == License (read live 2026-10-10 — two statements, recorded both)
    #
    # The Zenodo record's license field is cc-by-4.0, and the deposited
    # htr-united yml says "CC-BY 4.0"; the deposited CITATION.cff says
    # "CC-BY-SA-4.0". Both are attribution-class; the share-alike reading
    # is honored as the stricter one wherever the text is passed on.
    class PragueBible1488 < Nabu::Adapter
      ZIP_NAME = "Bible_prazska_1488-20241219T111644Z-001.zip"
      ZIP_URL = "https://zenodo.org/records/14524858/files/#{ZIP_NAME}".freeze

      LANGUAGE = "cs"
      URN_PREFIX = "urn:nabu:prague-bible-1488:"
      PAGE_DIR = "page"

      # The record description's segment list, verbatim (book · range ·
      # folios · transcriber), keyed by the Transkribus page-number run
      # each segment occupies in the zip.
      Segment = Data.define(:pages, :book, :passage_range, :folio_range, :transcriber)
      SEGMENTS = [
        Segment.new(pages: 23..26, book: "Genesis", passage_range: "Gn 2:15–8:17",
                    folio_range: "7v–9v", transcriber: "Martin Plechatý"),
        Segment.new(pages: 214..218, book: "Joshua", passage_range: "Jos 7:13–11:3",
                    folio_range: "103r–105r", transcriber: "Daniel Katscher"),
        Segment.new(pages: 501..503, book: "Judith", passage_range: "Jdt 4:14–7:28",
                    folio_range: "246r–247v", transcriber: "Marie Hedvíková"),
        Segment.new(pages: 566..569, book: "Psalms", passage_range: "Ps 31:10–39:6",
                    folio_range: "279r–281r", transcriber: "Jan Škvrňák"),
        Segment.new(pages: 840..843, book: "Ezechiel", passage_range: "Ez 22:22–25:2",
                    folio_range: "416r–417v", transcriber: "Martina Spěváčková"),
        Segment.new(pages: 1043..1047, book: "Gospel of Luke", passage_range: "L 11:51–16:4",
                    folio_range: "517v–519v", transcriber: "Jan Švarc"),
        Segment.new(pages: 1148..1150, book: "Hebrews", passage_range: "Hb 9:8–13:4",
                    folio_range: "570r–571v", transcriber: "Tereza Hejdová"),
        Segment.new(pages: 1205..1207, book: "Apocalypsis", passage_range: "Ap 10:1–16:16",
                    folio_range: "598v–599r", transcriber: "Václav Steiner")
      ].freeze

      EDITION_DATE = { "not_before" => 1488, "not_after" => 1488, "raw" => "1488" }.freeze
      EDITION_PLACE = "Prague"
      CORRECTOR = "Anna Michalcová"
      SHELFMARK = "Vienna, Österreichische Nationalbibliothek, Ink 13.C.5"

      MANIFEST = Nabu::SourceManifest.new(
        id: "prague-bible-1488",
        name: "Prague Bible 1488 — HTR Winter School 2024 Medieval Czech ground truth",
        license: "CC BY 4.0 — the Zenodo record's license field (cc-by-4.0) and the deposited " \
                 "htr-united yml (\"CC-BY 4.0\"); the deposited CITATION.cff states " \
                 "\"CC-BY-SA-4.0\" — both read 2026-10-10, the share-alike reading honored as " \
                 "the stricter. Cite: Michalcová, Plechatý, Katscher, Hedvíková, Škvrňák, " \
                 "Spěváčková, Švarc, Hejdová, Steiner, HTR Winter School 2024 - Medieval Czech - " \
                 "Prague Bible (1488), doi:10.5281/zenodo.14524858. Images: ÖNB (not ingested).",
        license_class: "attribution",
        upstream_url: "https://doi.org/10.5281/zenodo.14524858",
        parser_family: "page-xml"
      )

      def self.manifest = MANIFEST

      def self.remote_probe_strategy = :http_zip

      def self.http_probe_targets
        [Nabu::Adapter::HttpProbeTarget.new(
          label: ZIP_NAME, zip_url: ZIP_URL, metadata_url: nil,
          state_subdir: "", state_file: Nabu::ZipFetch::STATE_FILE
        )]
      end

      def fetch(workdir, progress: nil, force: false)
        result = Nabu::ZipFetch.sync!(
          url: ZIP_URL, dir: workdir, attic_dir: File.join(workdir, ATTIC_DIRNAME),
          progress: progress,
          guard: ->(doomed) { guard_mass_deletion!(workdir, doomed, force: force) }
        )
        notes = [result.not_modified ? "not modified (304)" : "#{ZIP_NAME} unpacked",
                 attic_notes(result.atticked)].compact.join("; ")
        Nabu::FetchReport.new(sha: result.sha, fetched_at: Time.now, notes: notes)
      rescue ZipFetch::Error, Nabu::Shell::Error => e
        raise Nabu::FetchError, "prague-bible-1488 fetch failed into #{workdir}: #{e.message}"
      end

      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        Dir.glob(File.join(workdir, PAGE_DIR, "*.xml")).each do |path|
          yield Nabu::DocumentRef.new(
            source_id: MANIFEST.id, id: "#{URN_PREFIX}p#{page_stem(path)}",
            path: File.expand_path(path), metadata: {}
          )
        end
      end

      def parse(document_ref)
        page = PageXmlParser.new.parse(document_ref.path)
        segment = SEGMENTS.find { |s| s.pages.cover?(page.page_nr) }
        document = Nabu::Document.new(
          urn: document_ref.id, language: LANGUAGE, canonical_path: document_ref.path,
          title: title_for(page, segment), metadata: metadata_for(page, segment, document_ref.path)
        )
        sequence = 0
        page.regions.each_with_index do |region, region_ordinal|
          region.lines.each_with_index do |line, line_ordinal|
            next if line.text.strip.empty?

            document << build_passage(document_ref.id, region, line,
                                      citation: "r#{region_ordinal + 1}.l#{line_ordinal + 1}",
                                      sequence: sequence += 1)
          end
        end
        raise Nabu::ParseError, "#{document_ref.id}: no transcribed lines" if document.empty?

        document
      rescue Nabu::ValidationError => e
        raise Nabu::ParseError, "#{document_ref.path}: #{e.message}"
      end

      private

      # "0023_DTL_547662-0024.xml" → "0023" (the Transkribus page number).
      def page_stem(path)
        File.basename(path, ".xml").split("_", 2).first
      end

      def title_for(page, segment)
        base = "Prague Bible 1488"
        segment ? "#{base} — #{segment.book}, page #{page.page_nr}" : "#{base}, page #{page.page_nr}"
      end

      def metadata_for(page, segment, path)
        meta = {
          "page_nr" => page.page_nr,
          "status" => page.status,
          "image" => page.image_filename,
          "onb_image" => File.basename(path, ".xml").split("_", 2).last,
          "transkribus_doc_id" => page.doc_id,
          "shelfmark" => SHELFMARK,
          "corrector" => CORRECTOR,
          "date" => EDITION_DATE,
          "place" => EDITION_PLACE
        }
        if segment
          meta.merge!("book" => segment.book, "passage_range" => segment.passage_range,
                      "folio_range" => segment.folio_range, "transcriber" => segment.transcriber)
        end
        meta.compact
      end

      def build_passage(urn, region, line, citation:, sequence:)
        annotations = { "line_id" => line.id, "region_id" => region.id }
        annotations["region_type"] = region.type if region.type
        abbrevs = line.spans.select { |span| span.tag == "abbrev" }
        annotations["abbreviations"] = abbrevs.map { |span| abbrev_annotation(span) } unless abbrevs.empty?
        %w[unclear superscript].each do |kind|
          spans = kind == "unclear" ? spans_tagged(line, "unclear") : superscripts(line)
          annotations[kind] = spans.map { |span| span_annotation(span) } unless spans.empty?
        end
        Nabu::Passage.new(urn: "#{urn}:#{citation}", language: LANGUAGE,
                          text: Normalize.nfc(line.text), sequence: sequence,
                          annotations: annotations)
      end

      def spans_tagged(line, tag) = line.spans.select { |span| span.tag == tag }

      def superscripts(line)
        line.spans.select { |span| span.tag == "textStyle" && span.attributes["superscript"] == "true" }
      end

      def span_annotation(span)
        { "offset" => span.offset, "length" => span.length, "form" => Normalize.nfc(span.form) }
      end

      def abbrev_annotation(span)
        entry = span_annotation(span).merge("expansion" => Normalize.nfc(span.attributes["expansion"].to_s))
        entry["continued"] = true if span.attributes["continued"] == "true"
        entry
      end
    end
  end
end

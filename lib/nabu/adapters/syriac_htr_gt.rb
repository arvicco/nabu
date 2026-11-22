# frozen_string_literal: true

require "digest"

require_relative "page_xml_parser"

module Nabu
  module Adapters
    # syriac-htr-gt — the Syriac ground truth of the Vienna HTR Winter
    # Schools (Österreichische Akademie der Wissenschaften, Institut für
    # Mittelalterforschung; project managers Ephrem Aboud Ishac and
    # Christine Roughan): two Syriac New Testament manuscripts transcribed
    # line by line by the participants, who "used Transkribus to manually
    # correct a preliminary automatic transcription" (Kraken/eScriptorium).
    # The library's first manuscript-transcription Syriac — the witnesses'
    # own lines, not an edition:
    #
    #   onb-cod-syr-1  Zenodo 14714089 (DOI 10.5281/zenodo.14714089, v1.0.0,
    #                  2025-01-21; HTR Winter School 2024): Vienna, ÖNB Cod.
    #                  Syr. 1 — 140 folios, Serto, the Gospels, written in
    #                  Vienna by Moses of Mardin (record: "Codex dated 1545
    #                  AD, scribed by Moses of Mardin in Vienna").
    #   smmj-36        Zenodo 18157525 (DOI 10.5281/zenodo.18157525,
    #                  2026-01-05; HTR Winter School 2025): Jerusalem, St
    #                  Mark's Monastery MS 36 (HMML SMMJ 00036) — 133
    #                  bifolio images, "primarily Estrangelo but with Serto
    #                  and Eastern features", "approximately 12th - 14th
    #                  century", Matthew through the Epistles (the last image
    #                  is Hebrews 10).
    #
    # ONE adapter for both: the records share the school, the transcription
    # guidelines (verbatim identical: Syriac letters, spaces, syome and the
    # distinguishing dots, punctuation as written, no vowels, Transkribus
    # `unclear`), the PAGE-XML format and the SegmOnto region vocabulary;
    # they differ only in manuscript-level facts (MANUSCRIPTS below).
    #
    # == Delivery grains (both records, read 2026-11-22)
    #
    # 14714089 serves page.zip (1,113,171 B: page/ — 140 PAGE 2019 XML files
    # + a macOS .DS_Store), images.zip (468,604,566 B), CITATION.cff and
    # htr-united.yml. 18157525 serves page.zip (2,457,701 B: 133 PAGE 2013
    # XML files at the root), alto.zip (2,618,558 B — the same ground truth
    # exported from eScriptorium as ALTO), images.zip (970,176,428 B),
    # CITATION.cff and htr-united.yml. ACCEPTED: each record's page.zip,
    # ZipFetch'd into canonical/syriac-htr-gt/<manuscript>/ (ZipFetch strips
    # 14714089's single page/ top directory; nothing is materialized beside
    # the unpacked trees). REJECTED by rule, never fetched: images.zip (the
    # heavy page scans), alto.zip (a second format of the same lines), and
    # CITATION.cff/htr-united.yml (record metadata — their facts are
    # transcribed into MANUSCRIPTS). Inside the trees, the .DS_Store is
    # skipped by rule (discovery_skips, the specimen pinned in the fixture
    # tree); any other non-page file is UNRECOGNIZED.
    #
    # == Reconciliation (census 2026-11-22, both zips through the family)
    #
    # onb-cod-syr-1: 140 pages / 498 regions / 2,875 TextLines, 5 of them
    # empty (margin and numbering lines with no text) → 2,870 passages;
    # htr-united.yml advertises "lines: 2869" — a one-line residue upstream
    # does not explain. smmj-36: 133 pages / 1,056 regions / 17,836 lines,
    # none empty → 17,836 passages, exactly htr-united.yml's "lines: 17836"
    # (and 311,392 characters, exactly its "characters: 311392").
    #
    # == Identity: document = page image, passage = TextLine
    #
    # urn:nabu:syriac-htr-gt:<manuscript>:p<NNNN> — the file stem's leading
    # sequence number (the image's place in the deposit; "0041" of
    # 0041_00000056.xml), the stem's other half (the ÖNB image number, the
    # HMML SMMJ_00036__076 image name) riding metadata "image_id". Passages
    # …:r<region>.l<line>, both 1-based from upstream's reading order (the
    # page-xml family). Every line is kept — main text, margins (catchwords,
    # lectionary and section marks) and folio numbers — its SegmOnto region
    # type riding "region_type" (MainZone, MainZone-gold, MarginTextZone,
    # NumberingZone; eScriptorium's line-only dummy blocks carry none).
    # Text: the line's TextEquiv verbatim, NFC at the boundary (57 lines
    # carry non-canonical mark order; the ÖNB
    # transcribers' ~900 no-break spaces, U+00A0, stay verbatim); the Transkribus tags (unclear with
    # its alternative, abbrev, sic with its correction, Variant, person,
    # add, Subtitle) ride per-tag annotation lists over the verbatim line,
    # offset-addressed, \uXXXX escapes in their values decoded.
    #
    # == Axes
    #
    # Dates: onb-cod-syr-1 carries 1554 — the manuscript's own colophon
    # (the last image, 0319: "ܫܢܬ ܐܠܦ ܘܚܡܫܡܐ ܘ ܚܡܫܝܢ ܘܐܪܒܥܐ ܡܫܝܚ̈ܝܬܐ:
    # ܒܐܝܪܚ ܬܡܘܙ ܬܡܢܝܐ ܘܥܣܪܝܢ ܒܗ." — the year 1554 of the Messiah, Tammuz
    # 28) — over the record's "dated 1545" (htr-united: notBefore/notAfter
    # 1545), which reads as a digit transposition; the record's claim rides
    # verbatim as "record_date". smmj-36: 1100–1399 (htr-united
    # notBefore/notAfter; the record's "approximately 12th - 14th
    # century"). Both the artifact's own date (MetadataDates :structured,
    # no class). Place: onb-cod-syr-1 was written in Vienna (the record's
    # "scribed by Moses of Mardin in Vienna"); smmj-36 names no place of
    # writing — Jerusalem is where it is kept, never claimed as its origin.
    #
    # == License (read first-hand 2026-11-22 — two statements, recorded both)
    #
    # Both Zenodo records' license field is cc-by-4.0, and both deposited
    # htr-united.yml files say "CC-BY 4.0"
    # (https://creativecommons.org/licenses/by/4.0/); both deposited
    # CITATION.cff files say "CC-BY-SA-4.0"; the record descriptions say
    # "all transcriptions are licensed under the Creative Commons 4
    # licence". All attribution-class; the share-alike reading is honored
    # as the stricter wherever the text is passed on (the prague-bible-1488
    # precedent, the same school's deposits). The images (ÖNB; St Mark's
    # Monastery) are not ingested.
    class SyriacHtrGt < Nabu::Adapter
      LANGUAGE = "syc"
      URN_PREFIX = "urn:nabu:syriac-htr-gt:"
      ZIP_NAME = "page.zip"

      # The file shape both zips use: <4-digit sequence>_<image id>.xml.
      PAGE_FILE = /\A(\d{4})_(.+)\.xml\z/
      FINDER_FILE = ".DS_Store"

      Manuscript = Data.define(:key, :record, :doi, :md5, :shelfmark, :title, :script_style,
                               :date, :place, :extra)

      MANUSCRIPTS = [
        Manuscript.new(
          key: "onb-cod-syr-1", record: "14714089", doi: "10.5281/zenodo.14714089",
          md5: "1e06e5814a3c08daf4e9158289231dc1",
          shelfmark: "Vienna, Österreichische Nationalbibliothek, Cod. Syr. 1",
          title: "Vienna, ÖNB Cod. Syr. 1 (Gospels, 1554)", script_style: "Serto",
          date: { "not_before" => 1554, "not_after" => 1554,
                  "raw" => "Tammuz 28, 1554 of the Messiah (the colophon, the last image); the record says 1545" },
          place: "Vienna",
          extra: { "scribe" => "Moses of Mardin", "record_date" => "1545",
                   "winter_school" => "HTR Winter School 2024, Vienna" }
        ),
        Manuscript.new(
          key: "smmj-36", record: "18157525", doi: "10.5281/zenodo.18157525",
          md5: "b88c33b0dd0117db0f88b24e5e26cb6e",
          shelfmark: "Jerusalem, St Mark's Syrian Orthodox Monastery, MS 36 (HMML SMMJ 00036)",
          title: "Jerusalem, St Mark's Monastery MS 36 (New Testament, 12th–14th c.)",
          script_style: "Estrangelo",
          date: { "not_before" => 1100, "not_after" => 1399, "raw" => "approximately 12th - 14th century" },
          place: nil,
          extra: { "script_note" => "primarily Estrangelo but with Serto and Eastern features",
                   "winter_school" => "HTR Winter School 2025, Vienna" }
        )
      ].freeze

      MANIFEST = Nabu::SourceManifest.new(
        id: "syriac-htr-gt",
        name: "Syriac HTR ground truth — ÖNB Cod. Syr. 1 and St Mark's Monastery MS 36 (HTR Winter School, Vienna)",
        license: "CC BY 4.0 — both Zenodo records' license field (cc-by-4.0) and the deposited " \
                 "htr-united.yml files (\"CC-BY 4.0\"); the deposited CITATION.cff files state " \
                 "\"CC-BY-SA-4.0\" — read 2026-11-22, the share-alike reading honored as the stricter. " \
                 "Cite: Aboud Ishac, Roughan et al., HTR Winter School 2024 - Syriac, ÖNB Cod. Syr. 1, " \
                 "doi:10.5281/zenodo.14714089; Ishac, Roughan et al., HTR Winter School 2025 - Syriac, " \
                 "MS Jerusalem, Saint Mark's Monastery 36, doi:10.5281/zenodo.18157525. Images (ÖNB; " \
                 "St Mark's Monastery) not ingested.",
        license_class: "attribution",
        upstream_url: "https://doi.org/10.5281/zenodo.14714089",
        parser_family: "page-xml"
      )

      def self.manifest = MANIFEST

      def self.zip_url(manuscript) = "https://zenodo.org/records/#{manuscript.record}/files/#{ZIP_NAME}"

      def self.remote_probe_strategy = :http_zip

      def self.http_probe_targets
        MANUSCRIPTS.map do |manuscript|
          Nabu::Adapter::HttpProbeTarget.new(
            label: "#{manuscript.key} #{ZIP_NAME}", zip_url: zip_url(manuscript), metadata_url: nil,
            state_subdir: manuscript.key, state_file: Nabu::ZipFetch::STATE_FILE
          )
        end
      end

      # +pins+ overrides the md5 pins (tests; a re-pin drill on a new
      # record version): { manuscript key => md5 }.
      def initialize(pins: MANUSCRIPTS.to_h { |m| [m.key, m.md5] })
        super()
        @pins = pins
      end

      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        MANUSCRIPTS.flat_map { |manuscript| page_refs(workdir, manuscript) }.sort_by(&:id).each(&block)
      end

      # The Finder file by rule; any other file in a manuscript tree that
      # is not a page, and any unknown directory beside the manuscript
      # trees (a third manuscript nobody registered), is unrecognized (fetch bookkeeping — the state file, the attic —
      # is not content).
      def discovery_skips(workdir)
        by_rule = []
        strays = []
        MANUSCRIPTS.each do |manuscript|
          tree_files(File.join(workdir, manuscript.key)).each do |name|
            next if PAGE_FILE.match?(name)

            (name == FINDER_FILE ? by_rule : strays) << "#{manuscript.key}/#{name}"
          end
        end
        strays.concat(unknown_top_entries(workdir))
        DiscoverySkips.new(
          skipped_by_rule: by_rule.size, unrecognized: strays.size,
          notes: by_rule.map { |rel| "#{rel}: macOS Finder metadata in the zip (not a page)" } +
                 strays.map { |rel| "#{rel}: not a PAGE file of a known manuscript" }
        )
      end

      def parse(document_ref)
        manuscript = MANUSCRIPTS.find { |m| m.key == document_ref.metadata.fetch("manuscript") }
        page = PageXmlParser.new.parse(document_ref.path)
        document = Nabu::Document.new(
          urn: document_ref.id, language: LANGUAGE, canonical_path: document_ref.path,
          title: "#{manuscript.title}, image #{document_ref.metadata.fetch('sequence')}",
          metadata: metadata_for(manuscript, page, document_ref.metadata)
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

      # Both page.zips prepared and md5-verified (the records' own published
      # checksums) BEFORE the guard and BEFORE either tree mutates.
      def fetch(workdir, progress: nil, force: false)
        fetches = MANUSCRIPTS.to_h { |manuscript| [manuscript.key, zip_fetch(workdir, manuscript, progress)] }
        begin
          fetches.each do |key, fetch|
            fetch.prepare!
            verify_pin!(key, fetch)
          end
          guard_mass_deletion!(workdir, fetches.values.flat_map(&:doomed_paths), force: force)
          fetches.each_value(&:complete!)
        ensure
          fetches.each_value(&:cleanup!)
        end
        Nabu::FetchReport.new(sha: Digest::SHA256.hexdigest(fetches.values.map(&:sha).join("\n")),
                              fetched_at: Time.now, notes: fetch_notes(fetches))
      rescue ZipFetch::Error, Nabu::Shell::Error => e
        raise Nabu::FetchError, "syriac-htr-gt fetch failed into #{workdir}: #{e.message}"
      end

      private

      def page_refs(workdir, manuscript)
        dir = File.join(workdir, manuscript.key)
        tree_files(dir).filter_map do |name|
          match = PAGE_FILE.match(name) or next

          Nabu::DocumentRef.new(
            source_id: MANIFEST.id, id: "#{URN_PREFIX}#{manuscript.key}:p#{match[1]}",
            path: File.expand_path(File.join(dir, name)),
            metadata: { "manuscript" => manuscript.key, "sequence" => match[1], "image_id" => match[2] }
          )
        end
      end

      def tree_files(dir)
        return [] unless File.directory?(dir)

        Dir.children(dir).sort.select do |name|
          File.file?(File.join(dir, name)) && name != Nabu::ZipFetch::STATE_FILE
        end
      end

      def unknown_top_entries(workdir)
        return [] unless File.directory?(workdir)

        known = MANUSCRIPTS.map(&:key) + [ATTIC_DIRNAME]
        Dir.children(workdir).sort.select do |name|
          File.directory?(File.join(workdir, name)) && !known.include?(name) && !name.start_with?(".")
        end
      end

      def metadata_for(manuscript, page, ref_metadata)
        {
          "manuscript" => manuscript.key,
          "shelfmark" => manuscript.shelfmark,
          "zenodo_record" => manuscript.record,
          "doi" => manuscript.doi,
          "script_style" => manuscript.script_style,
          "date" => manuscript.date,
          "place" => manuscript.place,
          "image" => page.image_filename,
          "image_id" => ref_metadata.fetch("image_id"),
          "transkribus_page_nr" => page.page_nr,
          "transkribus_status" => page.status,
          "transkribus_doc_id" => page.doc_id
        }.merge(manuscript.extra).compact
      end

      def build_passage(urn, region, line, citation:, sequence:)
        annotations = { "line_id" => line.id, "region_id" => region.id }
        annotations["region_type"] = region.type if region.type
        line.spans.group_by { |span| span.tag.downcase }.each do |tag, spans|
          annotations[tag] = spans.map { |span| span_annotation(span) }
        end
        Nabu::Passage.new(urn: "#{urn}:#{citation}", language: LANGUAGE,
                          text: Normalize.nfc(line.text), sequence: sequence, annotations: annotations)
      end

      def span_annotation(span)
        entry = { "offset" => span.offset, "length" => span.length, "form" => Normalize.nfc(span.form) }
        span.attributes.each { |key, value| entry[key] = Normalize.nfc(unescape(value)) }
        entry
      end

      # Transkribus writes spaces and other specials inside custom-attribute
      # values as \uXXXX escapes ("reason:… sic …").
      def unescape(value)
        value.gsub(/\\u(\h{4})/) { [Regexp.last_match(1).hex].pack("U") }
      end

      def zip_fetch(workdir, manuscript, progress)
        Nabu::ZipFetch.new(url: self.class.zip_url(manuscript), dir: File.join(workdir, manuscript.key),
                           attic_dir: File.join(workdir, ATTIC_DIRNAME, manuscript.key),
                           progress: progress, stream: true)
      end

      def verify_pin!(key, fetch)
        expected = @pins.fetch(key)
        return if fetch.not_modified? || fetch.md5 == expected

        manuscript = MANUSCRIPTS.find { |m| m.key == key }
        raise Nabu::FetchError,
              "syriac-htr-gt: #{key} #{ZIP_NAME} misses the record's published md5 (expected #{expected}, " \
              "got #{fetch.md5}) — Zenodo files are immutable, so this is corruption or a new record " \
              "version; read https://doi.org/#{manuscript.doi} and re-pin MANUSCRIPTS only after re-censusing"
      end

      def fetch_notes(fetches)
        parts = fetches.map do |key, fetch|
          "#{key}: #{fetch.not_modified? ? 'not modified (304)' : "md5 pin verified, sha256 #{fetch.sha}"}"
        end
        [parts.join("; "), attic_notes(fetches.values.flat_map(&:atticked))].compact.join("; ")
      end
    end
  end
end

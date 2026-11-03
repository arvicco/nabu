# frozen_string_literal: true

require "csv"
require "json"
require_relative "../eras"
require_relative "../zip_range_fetch"
require_relative "source_read"

module Nabu
  module Adapters
    # tianyige — the Tianyige Ming examination records (Joshua Snider; Zenodo
    # record 23817595, v1.0, 2026-10-30; concept 23817594; Hugging Face
    # jsnider3/tianyige-ming-exam-records): machine transcription of the 312
    # printed examination records (科舉錄) of the Tianyi Pavilion Museum
    # (天一閣博物院, Ningbo), from the museum's public-domain scans on
    # Wikimedia Commons — 236 provincial (鄉試錄, 7 of them military 武舉),
    # 37 metropolitan (會試錄) and 39 palace (進士登科錄) records, 1371–1684
    # (one Qing record: 康熙二十三年四川鄉試錄). Each record is the official
    # publication of one examination session: examiners, the questions of
    # the three sessions, the graduates' roster, and model answers (程文)
    # with the examiners' comments (批語).
    #
    # == License (verified first-hand 2026-11-02)
    #
    # Zenodo license field cc-zero; README.md verbatim "The transcriptions
    # and metadata are released under CC0 1.0 (public domain dedication).
    # The underlying scans are public domain." (Commons: PD-old-100-expired,
    # credited to the museum.) Class open.
    #
    # == Silver text — declared on every document
    #
    # The text is UNCORRECTED vision-language-model output (gemini-4-argon on
    # ~29,200 pages, Claude Opus 5.5 on ~11,200; 12,664 pages read by both,
    # median agreement 98.1%; ~2.3–2.4% CER against Wikisource volunteer
    # transcriptions, per upstream), and the models sometimes modernize
    # variant forms (扵 → 於). Every document carries text_nature
    # "uncorrected-ocr" + OCR_NOTE (the cgpg / ndl-kotenseki label); each
    # page carries its ocr_model and, when dual-read, the second model's
    # name and the agreement score — never the second reading itself.
    #
    # == Delivery grains (census of the v1.0 zip, 2026-11-02; 955 members)
    #
    # - pages/<tianyige_id>.jsonl — TAKEN: one record each (312 = the
    #   record's count), one JSON line per page image (40,461 = upstream's
    #   count). Document = record, passage = page, cited p<page> (the PDF
    #   page; each image is one opening, two half-leaves split by "===").
    #   1,750 pages flagged blank (upstream's own flag) skip by rule,
    #   counted per document (one blank page carries stray model chatter,
    #   0007578 p73 "エンド" — the flag governs). 38,711 pages /
    #   10,083,906 characters remain.
    # - volumes.tsv — TAKEN as the record table (dynasty, reign era + year,
    #   Western year, level, province, edition notes, Commons page).
    # - the page fields punctuated / translation_en / translation_model —
    #   DECLINED: machine punctuation and machine English translation
    #   (gpt-6-astra, gemini-4-argon), the Honkoku precedent; and alt_text
    #   (the second OCR reading) — they land on disk inside the page lines
    #   but never reach a passage.
    # - documents/ (the same text re-cut into 81,298 logical documents by a
    #   model-placed segmentation), text/ (plain-text renderings), tables/,
    #   questions.tsv, graduates.tsv (12,921 questions, 49,378 graduates —
    #   the persons layer, a later lane), volumes.json, index.html and
    #   assets/ (the viewer) — REJECTED: outside the Range cone, never
    #   fetched; the fixture pins one specimen of each.
    #
    # == Dates, places, kind
    #
    # Every record is typed by its reign era + year (洪武 4): converted
    # through config/eras.yml's dynasty-keyed nianhao rows (明洪武, 清康熙)
    # into a one-year envelope, class composition (the record is printed
    # for that session); upstream's own western_year agrees on all 312
    # (census) and a disagreement is flagged (date_conflict), never
    # silently preferred. Provincial records name their province (順天,
    # 應天, 浙江 …) → the document place, named; metropolitan and palace
    # records name none. The exam level rides as a facet; the kind is the
    # official register, whole-source (config/kind_map.yml).
    class Tianyige < Nabu::Adapter
      SLUG = "tianyige"
      LANGUAGE = "lzh"
      URN_PREFIX = "urn:nabu:tianyige:"
      RECORD_URL = "https://zenodo.org/records/23817595"
      ZIP_URL = "https://zenodo.org/api/records/23817595/files/tianyige-ming-exam-records-v1.0.zip/content"
      # sha256 of the v1.0 zip's central directory (zip md5
      # 9276b9512f06fe7ed1f4bffa0b3dc2e8 = the record's checksum,
      # 96,836,611 bytes, downloaded 2026-11-02).
      DIRECTORY_SHA256 = "de1bb49f45c9ee8c6311e9ea463bd7f3b74fb9067f4b25ab5175b6549e2041e4"
      KEEP = %r{\A(?:README\.md|CITATION\.cff|volumes\.tsv|pages/[^/]+\.jsonl)\z}
      VOLUMES = "volumes.tsv"
      PAGES_DIR = "pages"
      DYNASTY = { "Ming" => "明", "Qing" => "清" }.freeze
      DECLINED_FIELDS = %w[punctuated translation_en translation_model alt_text].freeze
      OCR_NOTE = "Uncorrected vision-language-model transcription (upstream: ~2.3–2.4% character error " \
                 "rate against volunteer transcriptions; variant forms sometimes modernized); check " \
                 "the linked scan before citing. Machine punctuation and translation declined."

      MANIFEST = Nabu::SourceManifest.new(
        id: SLUG,
        name: "Tianyige Ming examination records (天一閣藏明代科舉錄) — machine transcription",
        license: "CC0 1.0 — README.md: \"The transcriptions and metadata are released under CC0 1.0 (public " \
                 "domain dedication). The underlying scans are public domain.\" (Zenodo record 23817595, " \
                 "license field cc-zero, verified 2026-11-02)",
        license_class: "open",
        upstream_url: RECORD_URL,
        parser_family: "tianyige-jsonl",
        credit: "Tianyige Ming Examination Records, compiled by Joshua Snider, v1.0, Zenodo " \
                "10.5281/zenodo.23817595 — scans by the Tianyi Pavilion Museum (天一閣博物院)."
      )

      def self.manifest = MANIFEST

      def self.parallel_parse? = true

      def self.remote_probe_strategy = :http_zip

      def self.http_probe_targets
        [Nabu::Adapter::HttpProbeTarget.new(label: "zenodo 23817595", zip_url: ZIP_URL, metadata_url: nil,
                                            state_subdir: "", state_file: Nabu::ZipRangeFetch::STATE_FILE,
                                            liveness_only: true)]
      end

      def self.keep?(rel) = KEEP.match?(rel)

      # "provincial (鄉試)" → "provincial".
      def self.level_value(raw) = raw.to_s.sub(/\s*\(.*\)\z/, "")

      def initialize(range_fetch: ->(**kwargs) { Nabu::ZipRangeFetch.new(**kwargs) })
        super()
        @range_fetch = range_fetch
      end

      def discover(workdir)
        return enum_for(:discover, workdir) unless block_given?

        rows = volumes(workdir)
        page_files(workdir).each do |id, path|
          row = rows[id] or next
          yield Nabu::DocumentRef.new(source_id: SLUG, id: "#{URN_PREFIX}#{id}", path: path, metadata: row)
        end
      end

      def discovery_skips(workdir)
        rows = volumes(workdir)
        strays = page_files(workdir).map(&:first).reject { |id| rows.key?(id) }
        notes = strays.empty? ? [] : ["page files with no volumes.tsv row: #{strays.join(', ')}"]
        Nabu::Adapter::DiscoverySkips.new(skipped_by_rule: 0, unrecognized: strays.size, notes: notes)
      end

      def parse(document_ref)
        row = document_ref.metadata
        pages = SourceRead.utf8_file(document_ref.path, label: SLUG).each_line.map { |line| JSON.parse(line) }
        document = Nabu::Document.new(urn: document_ref.id, language: LANGUAGE, canonical_path: document_ref.path,
                                      title: row.fetch("title"),
                                      metadata: document_metadata(row, pages.count { |page| page["blank"] }))
        pages.reject { |page| page["blank"] }.each do |page|
          text = Normalize.nfc(page.fetch("text").to_s)
          next if text.strip.empty?

          document << Nabu::Passage.new(urn: "#{document_ref.id}:p#{page.fetch('page')}", language: LANGUAGE,
                                        text: text, sequence: page.fetch("page"), annotations: annotations(page))
        end
        raise Nabu::ParseError, "#{document_ref.path}: no transcribed pages" if document.empty?

        document
      rescue JSON::ParserError, KeyError, TypeError, Nabu::ValidationError => e
        raise Nabu::ParseError, "#{SLUG}: #{document_ref.path}: #{e.class}: #{e.message}"
      end

      def fetch(workdir, progress: nil, force: false)
        fetch = @range_fetch.call(url: ZIP_URL, dir: workdir, attic_dir: File.join(workdir, ATTIC_DIRNAME),
                                  select: ->(rel) { self.class.keep?(rel) }, progress: progress)
        fetch.prepare!
        result = fetch.result
        unless fetch.not_modified?
          verify_pin!(result.sha)
          guard_mass_deletion!(workdir, fetch.doomed_paths, force: force)
        end
        fetch.complete!
        Nabu::FetchReport.new(sha: result.sha, fetched_at: Time.now,
                              notes: [fetch_note(fetch, result), attic_notes(fetch.result.atticked)].compact.join("; "))
      rescue Nabu::ZipRangeFetch::Error => e
        raise Nabu::FetchError, "#{SLUG} fetch failed into #{workdir}: #{e.message}"
      end

      private

      def fetch_note(fetch, result)
        return "not modified (directory pin, every kept member on disk)" if fetch.not_modified?

        "zenodo v1.0 directory pin verified; #{result.kept} members kept by Range, #{result.skipped} never read"
      end

      def page_files(workdir)
        Dir.glob(File.join(workdir, PAGES_DIR, "*.jsonl"))
           .map { |path| [File.basename(path, ".jsonl"), File.expand_path(path)] }.sort
      end

      def volumes(workdir)
        path = File.join(workdir, VOLUMES)
        return {} unless File.file?(path)

        CSV.parse(SourceRead.utf8_file(path, label: SLUG), headers: true, col_sep: "\t", quote_char: "\u0000")
           .to_h { |row| [row.fetch("tianyige_id"), row.to_h.transform_values { |v| v && Normalize.nfc(v) }] }
      end

      def document_metadata(row, blanks)
        level = row["exam_level"]
        province = blank_nil(row["province"])
        {
          "tianyige_id" => row["tianyige_id"], "volume" => row["volume"], "dynasty" => row["dynasty"],
          "reign_era" => row["reign_era"], "reign_year" => integer(row["reign_year"]),
          "western_year" => integer(row["western_year"]), "exam_level" => level,
          "military" => row["military"] == "yes", "place" => province, "province_en" => blank_nil(row["province_en"]),
          "edition_notes" => blank_nil(row["edition_notes"]), "commons_page" => blank_nil(row["commons_page"]),
          "source_pdf_sha1" => blank_nil(row["sha1"]), "pages_advertised" => integer(row["pages"]),
          "blank_pages_skipped" => blanks,
          "facets" => { "exam_level" => { "value" => self.class.level_value(level), "raw" => level } },
          "text_nature" => "uncorrected-ocr", "ocr_note" => OCR_NOTE
        }.merge(date_fields(row)).compact
      end

      # The record's reign era + year → the nianhao row's one-year envelope.
      def date_fields(row)
        dynasty = DYNASTY[row["dynasty"]]
        era = dynasty && Nabu::Eras.default&.resolve("#{dynasty}#{row['reign_era']}")
        year = integer(row["reign_year"])
        return {} unless era && year

        bounds = Nabu::Eras.default.to_ce(era, year).to_date_bounds
        western = integer(row["western_year"])
        conflict = western && bounds["not_before"] != western ? western : nil
        { "date" => bounds.merge("raw" => "#{row['reign_era']}#{year} (#{row['dynasty']} #{row['reign_era_pinyin']})",
                                 "class" => "composition"),
          "date_conflict" => conflict }
      end

      def annotations(page)
        banxin = Array(page["banxin"]).map { |strip| Normalize.nfc(strip) }
        {
          "page" => page["page"], "scan_url" => page["scan_url"], "banxin" => (banxin unless banxin.empty?),
          "ocr_model" => page["ocr_model"], "alt_ocr_model" => page["alt_ocr_model"], "agreement" => page["agreement"],
          "has_examiner_comments" => (true if page["has_examiner_comments"]),
          "chatter_stripped" => (true if page["chatter_stripped"])
        }.compact
      end

      def integer(value) = value.to_s.match?(/\A\d+\z/) ? Integer(value, 10) : nil

      def blank_nil(value) = value.to_s.strip.empty? ? nil : value

      def verify_pin!(sha)
        return if sha == DIRECTORY_SHA256

        raise Nabu::FetchError,
              "#{SLUG}: the zip directory misses the v1.0 pin (expected #{DIRECTORY_SHA256}, got #{sha}) — " \
              "Zenodo files are immutable, so this is corruption or a new version; read #{RECORD_URL} and re-pin"
      end
    end
  end
end

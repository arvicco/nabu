# frozen_string_literal: true

require "csv"
require_relative "../zip_fetch"
require_relative "source_read"

module Nabu
  module Adapters
    # haga-jinmei — the Haga Jinmei Dictionary Dataset (National Institutes
    # for the Humanities, NIHU; Zenodo record 23804456, v0.1.0, 2026-10-29;
    # github.com/NIHU-jp/haga-jinmei-dataset): 芳賀矢一編『日本人名辞典』
    # (Tokyo: 大倉書店, 1914), the Meiji–Taishō biographical dictionary of
    # Japanese persons from antiquity to the late Meiji era, as one CSV row
    # per printed entry — 54,558 entries, the full entry text included.
    #
    # == License (verified first-hand 2026-11-02)
    #
    # Zenodo record license field `cc-zero`; the record description
    # verbatim "CC0 1.0で公開し、引用は再利用の条件とは別の学術上のお願いと
    # しています"; the in-deposit LICENSE verbatim "To the extent possible
    # under law, the National Institutes for the Humanities has waived all
    # copyright and related or neighboring rights that it holds in the
    # contents of this release repository, including the Haga Jinmei
    # dataset distributed in data/haga_jinmei_records.csv." Citation of
    # the Zenodo DOI is requested, explicitly not a condition (RIGHTS.md).
    # (The GitHub repository's license badge reads NOASSERTION; the
    # deposit's own LICENSE governs.) The 1914 print is itself public
    # domain (Haga Yaichi, 1867–1927). Class `open`.
    #
    # == Delivery grains (census of the v0.1.0 zip, 2026-11-02)
    #
    # - data/haga_jinmei_records.csv — TAKEN: one dictionary document,
    #   one entry per row (entry_no, source_page, name_yomi_katakana,
    #   full_name, entry_heading, description). 54,558 rows parse = the
    #   release manifest's record_count; 8,559 descriptions are a bare
    #   "⇒<reading>" see-reference = its redirect_like_count exactly
    #   (8,556 with a target → a `see` crossref; 3 bare "⇒" whose target
    #   the source dropped; one further entry carries ⇒ mid-text, kept as
    #   prose). 2 blank full_name, 3
    #   blank descriptions = the manifest's blank counts.
    # - entries naming several persons (inherited names: 式佐（岸沢） covers
    #   the sixth to eighth holders) stay ONE entry — upstream's own rule
    #   (MULTI_PERSON_ENTRIES.md): 54,558 entries are not 54,558 persons.
    # - the deposit's docs, data/README.md, data/release_manifest.json and
    #   schema/ — REJECTED (release documentation), skipped by rule.
    #
    # == Entry shape
    #
    # entry_id = entry_no (upstream's six-digit row number, unique);
    # headword = the printed heading without its 【】 (the dictionary's own
    # lookup form — 靄崖（高久）: the gō, the family name in brackets);
    # key_raw = the heading verbatim; body = the entry text verbatim (a
    # blank description falls back to the heading, flagged). Reading,
    # full name and page ride annotations — the full_name cell is kept
    # verbatim even where it is plainly a stray fragment (entry 002562).
    # Dates, places and offices are in the prose only; mining them into a
    # persons layer is a separate lane.
    #
    # == Fetch
    #
    # ZipFetch of the one deposit file (the single top directory strips
    # onto the workdir), the sha256 pinned BETWEEN download and any tree
    # mutation (the siddham choreography). Zenodo files are immutable: a
    # pin miss is corruption or a new version — an owner re-pin.
    class HagaJinmei < Nabu::Adapter
      SLUG = "haga-jinmei"
      LANGUAGE = "jpn"
      RECORD_URL = "https://zenodo.org/records/23804456"
      ZIP_URL = "https://zenodo.org/api/records/23804456/files/NIHU-jp/haga-jinmei-dataset-v0.1.0.zip/content"
      # sha256 of the 2,461,955-byte v0.1.0 zip, downloaded 2026-11-02
      # (md5 d3041e4c92a02d52d7573a6ca26dd22e = the record's checksum).
      ZIP_SHA256 = "410c05fa1d8e111edf6b1fbe724a991675fc3b969cc9b7034cd85a2916f1deec"

      CSV_PATH = File.join("data", "haga_jinmei_records.csv")
      COLUMNS = %w[entry_no source_page name_yomi_katakana full_name entry_heading description].freeze
      # The deposit's release documentation — the rejected grain.
      DOC_FILES = %w[
        README.md LICENSE RIGHTS.md DATA_DICTIONARY.md MULTI_PERSON_ENTRIES.md CITATION.cff CHANGELOG.md
        RELEASE_CHECKLIST.md data/README.md data/release_manifest.json schema/public_record.schema.json
      ].freeze
      # A see-reference: the whole description is ⇒ + a reading, which may
      # carry a title word after a space (⇒ゴトバ テンワウ); 3 bare "⇒" rows
      # are redirects whose target the source dropped (no crossref).
      REDIRECT = /\A⇒\s*(?<target>\S.*)?\z/
      TITLE = "芳賀矢一編『日本人名辞典』(1914) — Haga Jinmei Dictionary Dataset (NIHU)"

      MANIFEST = Nabu::SourceManifest.new(
        id: SLUG,
        name: "Haga Jinmei Dictionary Dataset (芳賀矢一『日本人名辞典』1914; NIHU)",
        license: "CC0 1.0 — the deposit LICENSE: \"the National Institutes for the Humanities has " \
                 "waived all copyright and related or neighboring rights that it holds in the contents " \
                 "of this release repository\" (Zenodo record 23804456, license field cc-zero, verified " \
                 "2026-11-02); citing the Zenodo DOI is requested, not required",
        license_class: "open",
        upstream_url: RECORD_URL,
        parser_family: "haga-csv",
        credit: "Haga Jinmei Dictionary Dataset, National Institutes for the Humanities (NIHU), " \
                "v0.1.0, Zenodo 10.5281/zenodo.23804456 — from 芳賀矢一編『日本人名辞典』(大倉書店, 1914)."
      )

      def self.manifest = MANIFEST

      # Entries, not passages (architecture §11).
      def self.content_kind = :dictionary

      def self.remote_probe_strategy = :http_zip

      def self.http_probe_targets
        [Nabu::Adapter::HttpProbeTarget.new(label: "zenodo 23804456", zip_url: ZIP_URL,
                                            metadata_url: nil, state_subdir: "")]
      end

      def initialize(pin: ZIP_SHA256)
        super()
        @pin = pin
      end

      def discover(workdir)
        return enum_for(:discover, workdir) unless block_given?

        path = File.join(workdir, CSV_PATH)
        return unless File.file?(path)

        yield Nabu::DocumentRef.new(source_id: SLUG, id: "#{SLUG}:#{CSV_PATH}", path: File.expand_path(path),
                                    metadata: { "dictionary" => SLUG })
      end

      def discovery_skips(workdir)
        present = DOC_FILES.select { |rel| File.file?(File.join(workdir, rel)) }
        return Nabu::Adapter::DiscoverySkips.new if present.empty?

        Nabu::Adapter::DiscoverySkips.new(
          skipped_by_rule: present.size,
          notes: ["release documentation, not entries (skipped by rule): #{present.join(', ')}"]
        )
      end

      def parse(document_ref)
        document = Nabu::DictionaryDocument.new(slug: SLUG, language: LANGUAGE, title: TITLE,
                                                canonical_path: document_ref.path)
        table = CSV.parse(SourceRead.utf8_file(document_ref.path, label: SLUG), headers: true)
        unless table.headers == COLUMNS
          raise Nabu::ParseError, "#{document_ref.path}: columns #{table.headers.inspect} ≠ the 0.1.0 schema"
        end

        table.each { |row| document << entry(row) }
        raise Nabu::ParseError, "#{document_ref.path}: no entries" if document.empty?

        document
      rescue CSV::MalformedCSVError, Nabu::ValidationError => e
        raise Nabu::ParseError, "#{SLUG}: #{document_ref.path}: #{e.message}"
      end

      def fetch(workdir, progress: nil, force: false)
        zip = Nabu::ZipFetch.new(url: ZIP_URL, dir: workdir, attic_dir: File.join(workdir, ATTIC_DIRNAME),
                                 progress: progress)
        begin
          zip.prepare!
          verify_pin!(zip)
          guard_mass_deletion!(workdir, zip.doomed_paths, force: force)
          zip.complete!
        ensure
          zip.cleanup!
        end
        Nabu::FetchReport.new(sha: zip.sha, fetched_at: Time.now,
                              notes: [zip.not_modified? ? "not modified (304)" : "zenodo v0.1.0 sha256 pin verified",
                                      attic_notes(zip.atticked)].compact.join("; "))
      rescue Nabu::ZipFetch::Error, Nabu::Shell::Error => e
        raise Nabu::FetchError, "#{SLUG} fetch failed into #{workdir}: #{e.message}"
      end

      private

      def entry(row)
        heading = text(row["entry_heading"])
        raise Nabu::ParseError, "#{SLUG}: entry #{row['entry_no'].inspect} has no heading" if heading.nil?

        description = text(row["description"])
        headword = heading.delete_prefix("【").delete_suffix("】")
        redirect = description&.match(REDIRECT)
        Nabu::DictionaryEntry.new(
          entry_id: row.fetch("entry_no"), key_raw: heading, language: LANGUAGE,
          headword: headword, headword_folded: Normalize.search_form(headword, language: LANGUAGE),
          body: description || heading,
          crossrefs: redirect&.[](:target) ? [see(redirect[:target])] : [],
          annotations: {
            "reading" => text(row["name_yomi_katakana"]), "full_name" => text(row["full_name"]),
            "page" => (Integer(row["source_page"], 10) if row["source_page"].to_s.match?(/\A\d+\z/)),
            "redirect" => (true if redirect), "description_blank" => (true if description.nil?)
          }.compact
        )
      end

      def see(target)
        Nabu::DictionaryCrossref.new(kind: "see", label: "⇒#{target}", target: target,
                                     target_folded: Normalize.search_form(target, language: LANGUAGE))
      end

      def text(value)
        stripped = Normalize.nfc(value.to_s).strip
        stripped.empty? ? nil : stripped
      end

      def verify_pin!(zip)
        return if zip.not_modified? || zip.sha == @pin

        raise Nabu::FetchError,
              "#{SLUG}: downloaded artifact misses the v0.1.0 sha256 pin (expected #{@pin}, got #{zip.sha}) — " \
              "Zenodo files are immutable, so this is corruption or a new version; read #{RECORD_URL} and " \
              "re-pin ZIP_SHA256"
      end
    end
  end
end

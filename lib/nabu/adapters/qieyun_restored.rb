# frozen_string_literal: true

require_relative "flat_csv_parser"

module Nabu
  module Adapters
    # The restored Qieyun shelf (P88-A2): nk2028/qieyun-restored — the
    # 切韻 itself (Lu Fayan, 601 CE), the PARENT rhyme dictionary the held
    # 廣韻 shelf (tshet-uinh, 1008) expanded, as restored by Fujita Takumi
    # 藤田拓海 (2017 thesis 陸法言『切韻』研究 / 2023 monograph) and
    # extracted upstream from the thesis PDF's appendix table. 11,158
    # character rows (censused 2026-08-29). Language ltc — the Qieyun IS
    # the foundation document of the Middle Chinese phonological system.
    #
    # == Identity: the thesis-table position
    #
    # 小韻 numbering RESTARTS per 韻目 (東 ends at 小韻 32, 冬 reopens at
    # 1 — censused), so the in-book small-rime number cannot key entries.
    # The (頁, 行) thesis-table position is unique across all 11,158 rows
    # (verified 2026-08-29) and cites straight into Fujita's printed
    # apparatus: entry_id "頁.行" ("1.1" = 東).
    #
    # == The file-set census (repo @ 2025-03-02, whole)
    #
    # 切韻 藤田拓海復元.csv 11,158 rows (INGESTED — the repo's headline
    # restoration, the 2023 monograph's) · 切韻 李永富復元.csv 11,163 rows
    # (Li Yongfu's restoration — 97.4% byte-identical rows; a censused
    # WITNESS lane, deliberately unmined: the 王三 posture, never a
    # near-duplicate shelf) · small-rime-diffs.csv 253 rows (where the two
    # restorations disagree on a small rime's existence) ·
    # to_tshet_uinh_data/small_rimes.csv 3,385 small rimes WITH the
    # 對應廣韻小韻號 column — the ready-made join key into the held
    # guangyun shelf, landing with the clone as a future consumer seam ·
    # fujita-data.csv (the raw table extraction) + *.pkl intermediates —
    # excluded by the sparse cone.
    #
    # == License (verified 2026-08-29)
    #
    # LICENSE at the repo root: MIT, © 2024 nk2028 (the extraction's
    # grant; the underlying 601 CE text is PD — credit Fujita's
    # restoration scholarship per the README's source section) →
    # attribution.
    #
    # == fetch / sync policy
    #
    # Sparse GitFetch scoped to the CSV cone + README/LICENSE (the ~20 MB
    # of PDF-extraction .pkl intermediates never materialize). Upstream is
    # a completed extraction (last push 2025-03-02) → sync_policy manual.
    class QieyunRestored < Nabu::Adapter
      REPO_URL = "https://github.com/nk2028/qieyun-restored"

      SPARSE_PATHS = ["**/*.csv", "README.md", "LICENSE"].freeze

      FILENAME = "切韻 藤田拓海復元.csv"
      DICTIONARY_SLUG = "qieyun"
      LANGUAGE = "ltc"
      TITLE = "切韻 — Qieyun (601), Fujita Takumi restoration (qieyun-restored)"

      REQUIRED_HEADERS = %w[頁 行 音韻地位描述 聲調 韻目 序数 小韻 音類 字頭 釋義].freeze

      MANIFEST = Nabu::SourceManifest.new(
        id: "qieyun-restored",
        name: "qieyun-restored — 切韻 Fujita restoration (nk2028)",
        license: "MIT (in-repo LICENSE, © 2024 nk2028, verified 2026-08-29 — the extraction's " \
                 "grant over a PD 601 CE text). Credit 藤田拓海 (Fujita Takumi), 陸法言『切韻』" \
                 "研究 (2017 thesis / 2023 monograph, 好文出版), whose restoration this is",
        license_class: "attribution",
        upstream_url: REPO_URL,
        parser_family: "flat-csv"
      )

      def self.manifest
        MANIFEST
      end

      # Entries, not passages (architecture §11) — SyncRunner/Rebuild route
      # through Store::DictionaryLoader.
      def self.content_kind = :dictionary

      # One DocumentRef for the one ingested CSV (the tshet-uinh shape);
      # the rest of the file set is census-only. The same walk works under
      # the attic.
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        Dir.glob(File.join(workdir, "**", FILENAME)).first(1).each do |path|
          yield Nabu::DocumentRef.new(
            source_id: manifest.id,
            id: "#{DICTIONARY_SLUG}:#{FILENAME}",
            path: File.expand_path(path),
            metadata: { "dictionary" => DICTIONARY_SLUG }
          )
        end
      end

      def parse(document_ref)
        document = Nabu::DictionaryDocument.new(
          slug: DICTIONARY_SLUG, language: LANGUAGE,
          title: TITLE, canonical_path: document_ref.path
        )
        parser.each_row(document_ref.path) { |row| document << build_entry(row, document_ref.path) }
        document
      rescue Nabu::ValidationError => e
        raise Nabu::ParseError, "qieyun-restored: #{document_ref.id}: #{e.message}"
      end

      # Clone or non-destructively pull the repo via the shared git path
      # (GitFetch: attic + pre-merge mass-deletion breaker), sparse cone.
      def fetch(workdir, progress: nil, force: false)
        git_fetch!(repo_url: repo_url, workdir: workdir, progress: progress, force: force,
                   sparse: SPARSE_PATHS)
      end

      private

      # Seam for tests (the house local-git pattern).
      def repo_url
        manifest.upstream_url
      end

      def parser
        FlatCsvParser.new(required_headers: REQUIRED_HEADERS)
      end

      def build_entry(row, path)
        entry_id = "#{row.fetch('頁')}.#{row.fetch('行')}"
        headword = row.fetch("字頭").to_s.strip
        Nabu::DictionaryEntry.new(
          entry_id: entry_id, key_raw: headword, language: LANGUAGE,
          headword: Normalize.nfc(headword),
          headword_folded: Normalize.search_form(headword, language: LANGUAGE),
          gloss: gloss(row),
          body: body_text(row),
          citations: []
        )
      rescue Nabu::ValidationError, Normalize::EncodingError => e
        raise Nabu::ParseError, "qieyun-restored: row #{entry_id.inspect} in #{path}: #{e.message}"
      end

      def gloss(row)
        text = row["釋義"].to_s.strip
        text.empty? ? nil : Normalize.nfc(text)
      end

      def body_text(row)
        lines = [
          labeled(row, "音韻地位描述", "音韻地位"), labeled(row, "聲調", "聲調"),
          labeled(row, "韻目", "韻目"), small_rime_line(row), labeled(row, "釋義", "釋義")
        ].compact
        Normalize.nfc(lines.join("\n"))
      end

      def labeled(row, column, label)
        value = row[column].to_s.strip
        value.empty? ? nil : "#{label}：#{value}"
      end

      # 小韻 restarts per 韻目, so its line carries the disambiguating
      # 音類 and the book-global 序数 alongside.
      def small_rime_line(row)
        "小韻：#{row.fetch('小韻')}（音類 #{row.fetch('音類')}，序数 #{row.fetch('序数')}）"
      end
    end
  end
end

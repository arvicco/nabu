# frozen_string_literal: true

require_relative "flat_csv_parser"

module Nabu
  module Adapters
    # The Zhongyuan Yinyun shelf (P88-R3 — the 02-sources row-99 un-park,
    # ruled by the same zho:oman stage as menggu-ziyun): nk2028/
    # zhongyuan-data — the 中原音韻 (Zhou Deqing 周德清, 1324), the
    # arch-source of Old Mandarin phonology, compiled for qu-verse
    # rhyming. 5,877 character rows (censused 2026-08-29), each carrying
    # the categorical position (聲母/韻母/聲調 — Zhongyuan tones 陰/陽/上/去,
    # the ru-tone already redistributed) and FOUR parallel scholarly
    # reconstructions: 楊耐思 (1981) · 寧繼福 (1985) · 薛鳳生 (1990,
    # phonemic) · unt (2021, phonemic + transcription). The repo's
    # verify.py cross-checks descriptions against the IPA — a maintained,
    # internally-consistent dataset.
    #
    # == The language ruling (the row-99 journal note, closed)
    #
    # This source sat journaled since P32-3 over "no honest ISO 639-3 tag
    # for Old Mandarin (cmn would misfile a 1324 rhyme book)". nabu-lects
    # v1.4.0 (№R-53 / PR #11) minted the zho:oman stage: entries tag
    # HONEST-COARSE `zho` and the stage row refines — the menggu-ziyun
    # pattern exactly. The owner's "let's do 1-3" (2026-08-29) is the
    # un-park ruling.
    #
    # == Identity + apparatus
    #
    # entry_id = "<小韻>.<ordinal>" (row order within the homophone
    # group's head character — no numeric group key exists upstream; the
    # (小韻, 字) pair is duplicate-free ×5,877 but the ordinal id is
    # robust regardless). All four reconstructions ride the body labeled
    # by their scholars verbatim; 校註 editorial notes (94 rows — 原作
    # "X"，誤 corrections, 四庫本 variants) ride verbatim; 釋義 is the
    # gloss when present (13 rows) — nil is honest.
    #
    # == License (verified IN-REPO 2026-08-29)
    #
    # LICENSE at the repo root is the full CC0 1.0 Universal legal code
    # (the tshet-uinh posture; the GitHub field agrees) → open. The
    # reconstructions are cited per the README (楊耐思 1981 · 寧繼福 1985
    # · 薛鳳生 1990 · unt 2021) — credit rides the manifest.
    #
    # == fetch / sync policy
    #
    # Plain GitFetch of the whole repo (4 files, ~350 KB) through the
    # attic + breaker contract. Last push 2025-05-22; the README says
    # "now including only Zhongyuan Yinyun itself" — the series may grow
    # → sync_policy manual.
    class Zhongyuan < Nabu::Adapter
      REPO_URL = "https://github.com/nk2028/zhongyuan-data"

      FILENAME = "中原音韻.tsv"
      DICTIONARY_SLUG = "zhongyuan"
      LANGUAGE = "zho"
      TITLE = "中原音韻 — Zhongyuan Yinyun (1324) with four scholarly reconstructions"

      REQUIRED_HEADERS = ["小韻", "字", "聲母", "韻母", "聲調", "楊耐思", "寧繼福",
                          "薛鳳生(音位)", "unt(音位)", "unt", "釋義", "校註"].freeze

      MANIFEST = Nabu::SourceManifest.new(
        id: "zhongyuan",
        name: "zhongyuan-data — 中原音韻 Old Mandarin rhyme book (nk2028)",
        license: "CC0 1.0 Universal (the in-repo LICENSE file carries the full legal code, " \
                 "verified 2026-08-29; the GitHub license field agrees). The four " \
                 "reconstruction lanes are cited per the README: 楊耐思 (1981), 寧繼福 (1985), " \
                 "薛鳳生 (1990), unt (2021)",
        license_class: "open",
        upstream_url: REPO_URL,
        parser_family: "flat-csv"
      )

      def self.manifest
        MANIFEST
      end

      # Entries, not passages (architecture §11) — SyncRunner/Rebuild route
      # through Store::DictionaryLoader.
      def self.content_kind = :dictionary

      # One DocumentRef for the one TSV (the tshet-uinh shape). The same
      # walk works under the attic; a pre-fetch workdir yields nothing.
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
        ordinals = Hash.new(0)
        parser.each_row(document_ref.path) do |row|
          document << build_entry(row, ordinals, document_ref.path)
        end
        document
      rescue Nabu::ValidationError => e
        raise Nabu::ParseError, "zhongyuan: #{document_ref.id}: #{e.message}"
      end

      # Clone or non-destructively pull the repo via the shared git path
      # (GitFetch: attic + pre-merge mass-deletion breaker).
      def fetch(workdir, progress: nil, force: false)
        git_fetch!(repo_url: repo_url, workdir: workdir, progress: progress, force: force)
      end

      private

      # Seam for tests (the house local-git pattern).
      def repo_url
        manifest.upstream_url
      end

      def parser
        FlatCsvParser.new(required_headers: REQUIRED_HEADERS, col_sep: "\t")
      end

      def build_entry(row, ordinals, path)
        rhyme = row.fetch("小韻").to_s.strip
        ordinals[rhyme] += 1
        entry_id = "#{rhyme}.#{ordinals[rhyme]}"
        headword = row.fetch("字").to_s.strip
        Nabu::DictionaryEntry.new(
          entry_id: entry_id, key_raw: headword, language: LANGUAGE,
          headword: Normalize.nfc(headword),
          headword_folded: Normalize.search_form(headword, language: LANGUAGE),
          gloss: gloss(row),
          body: body_text(row),
          citations: []
        )
      rescue Nabu::ValidationError, Normalize::EncodingError => e
        raise Nabu::ParseError, "zhongyuan: row #{entry_id.inspect} in #{path}: #{e.message}"
      end

      def gloss(row)
        text = row["釋義"].to_s.strip
        text.empty? ? nil : Normalize.nfc(text)
      end

      def body_text(row)
        lines = [
          labeled(row, "聲母", "聲母"), labeled(row, "韻母", "韻母"),
          labeled(row, "聲調", "聲調"),
          labeled(row, "楊耐思", "楊耐思"), labeled(row, "寧繼福", "寧繼福"),
          labeled(row, "薛鳳生(音位)", "薛鳳生（音位）"), unt_line(row),
          labeled(row, "校註", "校註"), labeled(row, "釋義", "釋義")
        ].compact
        Normalize.nfc(lines.join("\n"))
      end

      def labeled(row, column, label)
        value = row[column].to_s.strip
        value.empty? ? nil : "#{label}：#{value}"
      end

      def unt_line(row)
        phonemic = row["unt(音位)"].to_s.strip
        transcription = row["unt"].to_s.strip
        return nil if phonemic.empty?

        if transcription.empty?
          "unt（音位）：#{phonemic}"
        else
          "unt（音位）：#{phonemic}（轉寫 #{transcription}）"
        end
      end
    end
  end
end

# frozen_string_literal: true

require_relative "flat_csv_parser"

module Nabu
  module Adapters
    # The Menggu Ziyun shelf (P88-A2, unblocked by nabu-lects v1.4.0's
    # zho:oman ruling): nk2028/menggu-ziyun-data — the 蒙古字韻 (1308),
    # the 'Phags-pa-script rhyme book that is the primary phonological
    # record of Old Mandarin, in the digitization of 沈鍾偉《蒙古字韻》集校
    # (2015) with further revisions and reconstructions by unt (2023) and
    # variant forms from ccamc.org. 9,446 character rows across 853 small
    # rhymes (censused 2026-08-29).
    #
    # == The language ruling (№R-53 / nabu-lects PR #11)
    #
    # No ISO code exists for Old Mandarin — the question that parked the
    # sibling zhongyuan-data (02-sources row 99). The v1.4.0 registry
    # mints the zho:oman stage (band [1200, 1455]): this shelf tags its
    # entries HONEST-COARSE `zho` and the stage row refines — the same
    # honest-coarse + stage-refines pattern as en:early.
    #
    # == Identity + the entry apparatus
    #
    # entry_id = "<小韻號>.<ordinal>" (row order within the small rhyme —
    # the guangyun 小韻號.小韻字號 mold; upstream carries no explicit
    # in-rhyme number). Everything upstream states rides the body,
    # labeled and verbatim: the 'Phags-pa spelling (八思巴字), tone, rhyme
    # class, unt's reconstruction + transcription, the 對應切韻音系音韻地位
    # formula (the READY-MADE join into the held guangyun shelf's
    # position formulas), variant forms (備選異體), editorial verdicts
    # (需作調整 — a 此字當刪 row STILL MINTS, the guangyun 應刪字 stance)
    # and correction notes (注釋, IDS sequences and all). 釋義 is the
    # gloss when present (104 of 9,446 rows) — nil is honest.
    #
    # == The file-set census (repo @ 2025-02-15, whole)
    #
    # data.tsv 9,446 rows (INGESTED) · small_rhymes.tsv 853 rows (the
    # per-small-rhyme 'Phags-pa initial/final decomposition + 韻圖
    # provenance — censused, lands with the clone as a future seam,
    # the qieyun-restored small_rimes posture) · build_for_MCPDict.py
    # (packaging script, inert).
    #
    # == License (verified 2026-08-29)
    #
    # LICENSE at the repo root: MIT, © 2025 nk2028 → attribution; the
    # underlying 1308 rime book is PD. Credit the scholarship chain per
    # the README: 沈鍾偉 (2015), unt's revisions + reconstructions
    # (2023), ccamc.org variants.
    #
    # == fetch / sync policy
    #
    # Plain GitFetch of the whole repo (~84 KB packed) through the attic
    # + breaker contract. Last push 2025-02-15 → sync_policy manual.
    class MengguZiyun < Nabu::Adapter
      REPO_URL = "https://github.com/nk2028/menggu-ziyun-data"

      FILENAME = "data.tsv"
      DICTIONARY_SLUG = "menggu-ziyun"
      LANGUAGE = "zho"
      TITLE = "蒙古字韻 — Menggu Ziyun (1308), 沈鍾偉 collation with unt's reconstructions"

      REQUIRED_HEADERS = %w[小韻號 韻部 八思巴字 聲調 字頭 備選異體 釋義 需作調整 注釋
                            unt擬音 unt轉寫 對應切韻音系音韻地位].freeze

      MANIFEST = Nabu::SourceManifest.new(
        id: "menggu-ziyun",
        name: "menggu-ziyun-data — 蒙古字韻 'Phags-pa rhyme book (nk2028)",
        license: "MIT (in-repo LICENSE, © 2025 nk2028, verified 2026-08-29 — the digitization's " \
                 "grant over a PD 1308 rime book). Credit the chain per the README: 沈鍾偉" \
                 "《蒙古字韻》集校 (2015, 商務印書館), further revisions + reconstructions by " \
                 "unt (2023), variant forms from ccamc.org",
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

      # One DocumentRef for the one ingested TSV (the tshet-uinh shape);
      # small_rhymes.tsv is census-only. The same walk works under the
      # attic; a pre-fetch workdir yields nothing.
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
        raise Nabu::ParseError, "menggu-ziyun: #{document_ref.id}: #{e.message}"
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
        rhyme = row.fetch("小韻號").to_s.strip
        ordinals[rhyme] += 1
        entry_id = "#{rhyme}.#{ordinals[rhyme]}"
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
        raise Nabu::ParseError, "menggu-ziyun: row #{entry_id.inspect} in #{path}: #{e.message}"
      end

      def gloss(row)
        text = row["釋義"].to_s.strip
        text.empty? ? nil : Normalize.nfc(text)
      end

      def body_text(row)
        lines = [
          labeled(row, "八思巴字", "八思巴字"), labeled(row, "聲調", "聲調"),
          labeled(row, "韻部", "韻部"), reconstruction_line(row),
          labeled(row, "對應切韻音系音韻地位", "對應切韻音系音韻地位"),
          labeled(row, "備選異體", "備選異體"), labeled(row, "需作調整", "需作調整"),
          labeled(row, "注釋", "注釋"), labeled(row, "釋義", "釋義")
        ].compact
        Normalize.nfc(lines.join("\n"))
      end

      def labeled(row, column, label)
        value = row[column].to_s.strip
        value.empty? ? nil : "#{label}：#{value}"
      end

      def reconstruction_line(row)
        recon = row["unt擬音"].to_s.strip
        transcription = row["unt轉寫"].to_s.strip
        return nil if recon.empty?

        transcription.empty? ? "unt擬音：#{recon}" : "unt擬音：#{recon}（轉寫 #{transcription}）"
      end
    end
  end
end

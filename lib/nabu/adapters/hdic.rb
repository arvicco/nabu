# frozen_string_literal: true

require_relative "hdic_tsv_parser"

module Nabu
  module Adapters
    # The HDIC adapter (P32-4): the Integrated Database of Hanzi
    # Dictionaries in Early Japan (平安時代漢字字書総合データベース, Ikeda
    # Shoju's HDIC project, Hokkaido University) — the earliest Japanese
    # lexicography as five character-keyed dictionaries in ONE source (the
    # sl-lexica precedent). ACTIVE upstream github.com/shikeda/HDIC (last
    # push 2026-07-15 at packet time; the nk2028/HDIC mirror is a stale
    # 2022 fork and is never fetched).
    #
    # == The censused file set (2026-07-19, commit c8c36835)
    #
    #   yyp  YYP.tsv (2,087 rows)  — Yuanben Yupian 原本玉篇 fragments
    #        (Gu Yewang, 543; vols 8/9/18/19/22/24/27), updated 2026-05-23.
    #   syp  SYP.tsv (22,809)      — Songben Yupian 宋本玉篇 (Daguang Yihui
    #        Yupian, 1013).
    #   ktb  KTB.tsv (18,932)      — Tenrei Banshō Meigi 篆隸萬象名義
    #        (Kūkai, c. 827-835; Kōsanji copy). The project-claimed "TBM"
    #        VERIFIED present as full text.
    #   tsj  TSJ_definitions.tsv (19,980) — Shinsen Jikyō 新撰字鏡 (Shōju,
    #        c. 898-901; Tenji manuscript) VERIFIED present; the
    #        TSJ_wakun.tsv Japanese-readings database (3,828 rows, v1.1.8
    #        2026-07-15) rides as body lines joined by tsj_id.
    #   krm  KRM.tsv (32,607)      — Ruiju Myōgishō 類聚名義抄 (Kanchiin
    #        manuscript, 12th c.). NB upstream README: KRM updates have
    #        MOVED to github.com/shikeda/krm (revised spec) — this file is
    #        frozen here; the successor repo is a future-source candidate.
    #
    # Not ingested (censused, honest): GLS (Longkan Shoujing) and YQF
    # (Yupian quoted fragments) are marked "In preparation" upstream (no
    # published full text); ZRM lives only on the sample-dev branch;
    # TSJ_entries.tsv (24,381 headword-list rows incl. entries without
    # definitions) and the *_ndl edition-page concordances stay upstream —
    # the definitions databases are the dictionary shape.
    #
    # == Languages
    #
    # yyp/syp/ktb/tsj entries define Chinese characters in Literary Chinese
    # (fanqie spellings, classical citations) → lzh; krm's definition
    # column is dominantly Japanese kana readings/glosses → jpn. The
    # headword fold is script-neutral either way.
    #
    # == License — DISCREPANCY RECORDED (owner gate before any flip)
    #
    # README.md verbatim: "License / Creative Commons Attribution-ShareAlike
    # 4.0 International License (CC BY-SA 4.0) / Access Rights
    # (Availability) / Open access". EVERY published data file carries the
    # same in-file grant (e.g. KTB.tsv header: "License: / Creative Commons
    # Attribution-ShareAlike 4.0 International License (CC BY-SA 4.0)"),
    # maintained through the 2026 releases. The repo-level LICENSE file,
    # however, is the CC BY-NC-SA 4.0 LEGALCODE ("Attribution-NonCommercial-
    # ShareAlike 4.0 International") — git forensics: commit 72cfe74
    # (2022-02-02, "ライセンスの記述を変更") moved the project from CC
    # BY-NC 4.0 to BY-SA in the README and every file header but placed the
    # BY-NC-SA legalcode in LICENSE, an apparent template mismatch. Classed
    # "attribution" per the concordant per-file grants + README (the P32-4
    # scout verdict); the contradiction is journaled here, in the fixture
    # README and in docs/02-sources.md, and is on the owner queue — if the
    # owner rules the LICENSE file authoritative (the Kyoto/Ruthenian
    # precedent), the class tightens to "nc" before any enable.
    class Hdic < Nabu::Adapter
      MANIFEST = Nabu::SourceManifest.new(
        id: "hdic",
        name: "HDIC — Hanzi Dictionaries in Early Japan (Heian lexicography)",
        license: "CC BY-SA 4.0 (verbatim README + per-file headers: \"Creative Commons " \
                 "Attribution-ShareAlike 4.0 International License (CC BY-SA 4.0)\", \"Open access\"; " \
                 "NB repo LICENSE file carries the BY-NC-SA legalcode — discrepancy journaled, owner gate)",
        license_class: "attribution",
        upstream_url: "https://github.com/shikeda/HDIC",
        parser_family: "hdic-tsv"
      )

      WAKUN_FILE = "TSJ_wakun.tsv"

      # The five published databases, keyed by dictionary slug, in
      # chronological order of the works. Column names are per-database
      # (the hdic-tsv parser is generic over them).
      DICTIONARIES = {
        "yyp" => {
          file: "YYP.tsv", id: "YYID", entry: "Entry", def: "YY_def", language: "lzh",
          title: "Yuanben Yupian 原本玉篇 (Gu Yewang, 543 — fragments)"
        }.freeze,
        "ktb" => {
          file: "KTB.tsv", id: "TBID", entry: "Entry", def: "TB_def", language: "lzh",
          title: "Tenrei Banshō Meigi 篆隸萬象名義 (Kūkai, c. 827-835 — Kōsanji copy)"
        }.freeze,
        "tsj" => {
          file: "TSJ_definitions.tsv", id: "TSJ2ID", entry: "Entry_word", def: "SJ_def",
          language: "lzh", wakun: true,
          title: "Shinsen Jikyō 新撰字鏡 (Shōju, c. 898-901 — Tenji manuscript)"
        }.freeze,
        "syp" => {
          file: "SYP.tsv", id: "SYID", entry: "Entry", def: "SY_def", language: "lzh",
          title: "Songben Yupian 宋本玉篇 (Daguang Yihui Yupian, 1013)"
        }.freeze,
        "krm" => {
          file: "KRM.tsv", id: "KRID_n", entry: "Entry", def: "Def", language: "jpn",
          title: "Ruiju Myōgishō 類聚名義抄 (Kanchiin manuscript, 12th c.)"
        }.freeze
      }.freeze

      # The language-notes rider (P18-6 pattern): witness notes accreted
      # idempotently by the DictionaryLoader at every load.
      LANGUAGE_NOTES = [
        ["lzh", "witness:hdic",
         "HDIC (Ikeda Shoju, Hokkaido University; CC BY-SA 4.0): the Heian-period hanzi " \
         "dictionary line — Yuanben Yupian fragments (543), Kūkai's Tenrei Banshō Meigi " \
         "(c. 827-835), the Shinsen Jikyō (c. 898-901, with its wakun Japanese-readings " \
         "database) and the Songben Yupian (1013) — character-keyed entries whose Literary " \
         "Chinese definitions carry fanqie spellings and classical citations; the project's " \
         "own TBID/SYID/YYID columns cross-link the dictionaries and the headword characters " \
         "join Unihan/KANJIDIC2 by codepoint."].freeze,
        ["jpn", "witness:hdic",
         "HDIC's Ruiju Myōgishō (Kanchiin manuscript, 12th c.; 32,607 entries) is the " \
         "earliest-stratum Japanese reading evidence on this shelf: its definition column is " \
         "dominantly katakana wakun/on readings with tone-dot notation, beside the Shinsen " \
         "Jikyō wakun database (3,828 rows) riding on the tsj dictionary."].freeze
      ].freeze

      def self.manifest
        MANIFEST
      end

      # The routing declaration (architecture §11): entries, not passages —
      # SyncRunner/Rebuild load through Store::DictionaryLoader.
      def self.content_kind = :dictionary

      # [lang_code, kind, body] rows for the language-notes rider.
      def self.language_notes = LANGUAGE_NOTES

      # Clone or non-destructively pull the HDIC repo via the shared git
      # path (GitFetch: attic + pre-merge mass-deletion breaker).
      def fetch(workdir, progress: nil, force: false)
        git_fetch!(repo_url: repo_url, workdir: workdir, progress: progress, force: force)
      end

      # One DocumentRef per published database file, registry order. A
      # workdir without the files yields nothing (day-one pre-fetch state);
      # the same walk works under the attic (same relative shape).
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        DICTIONARIES.each do |slug, config|
          Dir.glob(File.join(workdir, "**", config.fetch(:file))).first(1).each do |path|
            yield Nabu::DocumentRef.new(
              source_id: manifest.id,
              id: "#{slug}:#{config.fetch(:file)}",
              path: File.expand_path(path),
              metadata: { "dictionary" => slug }
            )
          end
        end
      end

      def parse(document_ref)
        slug = document_ref.metadata.fetch("dictionary")
        config = DICTIONARIES.fetch(slug)
        document = Nabu::DictionaryDocument.new(
          slug: slug, language: config.fetch(:language),
          title: config.fetch(:title), canonical_path: document_ref.path
        )
        parser_entries(document_ref, config).each { |entry| document << entry }
        document
      rescue Nabu::ValidationError => e
        raise Nabu::ParseError, "hdic: #{document_ref.id}: #{e.message}"
      end

      private

      # Split out so fetch tests can point a singleton at a local git
      # tmpdir (the house pattern), keeping fetch off the network.
      def repo_url
        manifest.upstream_url
      end

      def parser_entries(document_ref, config)
        wakun = config[:wakun] ? File.join(File.dirname(document_ref.path), WAKUN_FILE) : nil
        HdicTsvParser.new.entries(
          document_ref.path,
          id_column: config.fetch(:id), entry_column: config.fetch(:entry),
          def_column: config.fetch(:def), language: config.fetch(:language), wakun: wakun
        )
      end
    end
  end
end

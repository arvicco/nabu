# frozen_string_literal: true

require "json"
require_relative "../normalize"

module Nabu
  module Adapters
    # The Shuowen Jiezi 說文解字 (Xu Shen 許慎, presented 100/121 CE) — the
    # founding dictionary of Chinese graphology, 540 radicals, every head
    # character explained by form — as the shuowen.org data repo serves it
    # (github.com/shuowenjiezi/shuowen, the site's own data, opened for
    # community correction in 2019). The anchor lexicon for OC-era
    # graphology beside the baxter-sagart and nk2028 shelves.
    #
    # == Upstream (census 2026-10-21, master @ 6553a350)
    #
    # data/<id>.json — ONE JSON RECORD PER HEAD CHARACTER, 9,833 files,
    # ids 1..9,833 contiguous (id == filename stem on every file), one
    # uniform key set (doc/FORMAT.md documents it field by field):
    #
    #   wordhead        the head character (single code point on all 9,833)
    #   explanation     Xu Shen's text (the 大徐本 Xu Xuan recension)
    #   volume          卷 01..14 ("" on 3 records — absent, never guessed)
    #   radical         the 說文部首 (540 distinct — the canonical count)
    #   pronunciation   the fanqie Xu Xuan added (from the 唐韻; "" on 14)
    #   pinyin/_full    modern readings (pinyin_full writes the IPA ɡ
    #                   U+0261 on 1,638 records — kept verbatim)
    #   components      the site's component analysis (empty on 73)
    #   variants        the 重文 forms: wordhead + explanation (1,253 on
    #                   1,068 records; 5 wordheads EMPTY — glyphs upstream
    #                   never encoded, explanation only)
    #   xuan_note       徐鉉 notes (406) · kai_note 徐鍇 notes (139)
    #   duan_notes      段玉裁《說文解字注》 pairs: the Shuowen clause as Duan
    #                   reads it + his note (9,355 records carry them)
    #   indexes         the site's search keys (variant spellings — 余→餘)
    #   seal_character  a code point into shuowen.org's SEAL FONT — a
    #                   font-slot key (帝 → "丈", 一 → "一"), not a character
    #                   claim; FORMAT.md: "此屬性無須修改". DROPPED, declared:
    #                   the small-seal glyph itself is an image the font
    #                   renders, and no Unicode small-seal block exists to
    #                   map it to (the deliberate coarseness of the seal
    #                   layer — the structural analysis rides components).
    #
    # Delivery grains: the per-character JSON (ACCEPTED, the document) and
    # the doc/ tree (FORMAT.md, CONTRIBUTING.md, img/ screenshots) — the
    # REJECTED documentation grain; doc/FORMAT.md rides the sparse cone as
    # the format's own provenance and is counted in discovery_skips.
    # Reconciliation (2026-10-21 census of the tarball at 6553a350): 9,833
    # data files = 9,833 head entries + 1,248 encoded 重文 entries
    # (1,253 variants − 5 unencoded), 0 records skipped; the doc grain = 1
    # file inside the cone. Upstream advertises no total of its own; the
    # radical count (540) and the contiguous id run are the cross-checks.
    #
    # == Entry shape (dictionary slug `shuowen`, language lzh)
    #
    # - head entry: entry_id = upstream id ("7"); headword = wordhead
    #   (NFC); gloss = Xu Shen's explanation; body = labeled lines (說文 /
    #   反切 / 拼音 / 部首 · 卷 / 構件 / 重文 / 徐鉉 / 徐鍇 / 段注〔clause〕note);
    #   annotations = radical, volume, fanqie, pinyin, components, indexes
    #   (present fields only — absent is absent, never a placeholder);
    #   crossrefs = each component (kind "component", resolved by headword)
    #   and each ENCODED 重文 (kind "chongwen", target_id its own entry).
    # - 重文 entry (encoded variants only): entry_id "<id>-v<n>" (n the
    #   1-based position in upstream's array — unencoded forms keep their
    #   slot, so ids never shift); headword = the variant glyph; gloss =
    #   its explanation ("古文一。"); a "chongwen-of" crossref back to the
    #   head by id. This is what makes `nabu define 弌` land on 古文一.
    #   An unencoded variant rides the head body as "重文 (glyph not
    #   encoded): …" and mints nothing.
    # - NFC at the boundary: 42 records carry CJK compatibility ideographs
    #   (e.g. 穊 U+2F95A in a Duan note), composed to the unified form —
    #   the house rule; Duan's "？" placeholders for unencodable glyphs ride
    #   verbatim.
    #
    # == License (verified verbatim 2026-10-21)
    #
    # LICENSE = the Apache License 2.0 text; README "## License":
    # "Copyright [2019] [Shuowen.org] / Licensed under the Apache License,
    # Version 2.0". The repo IS the data (no code), so the grant covers it
    # → attribution (the monlam-lexicon Apache precedent). The underlying
    # Han text and Duan's Qing commentary are public domain by age.
    #
    # == fetch / sync policy
    #
    # Sparse GitFetch of data/*.json + doc/FORMAT.md + README.md + LICENSE
    # (~39 MB tree; the screenshots stay out). A living correction repo
    # (last push 2025-09-05) → sync_policy manual.
    class Shuowen < Nabu::Adapter
      REPO_URL = "https://github.com/shuowenjiezi/shuowen"
      SPARSE_PATHS = ["data/*.json", "doc/FORMAT.md", "README.md", "LICENSE"].freeze

      DICTIONARY_SLUG = "shuowen"
      LANGUAGE = "lzh"
      TITLE = "說文解字 Shuowen Jiezi (許慎; 大徐本, with 段注) — shuowen.org data"
      RECORD = /\A(\d+)\.json\z/

      MANIFEST = Nabu::SourceManifest.new(
        id: "shuowen",
        name: "說文解字 Shuowen Jiezi — the shuowen.org data repo",
        license: "Apache License, Version 2.0 — README \"## License\" verbatim: \"Copyright [2019] " \
                 "[Shuowen.org] / Licensed under the Apache License, Version 2.0 (the \"License\")\"; " \
                 "LICENSE is the Apache 2.0 text (verified 2026-10-21). The repo is data only, so " \
                 "the grant covers the records; Xu Shen's text and Duan Yucai's commentary are PD by age",
        license_class: "attribution",
        upstream_url: REPO_URL,
        parser_family: "shuowen-json",
        credit: "Xu Shen 許慎, 說文解字 (Xu Xuan recension, with Duan Yucai's 說文解字注) — data " \
                "Shuowen.org (github.com/shuowenjiezi/shuowen), Apache-2.0"
      )

      def self.manifest = MANIFEST

      def self.content_kind = :dictionary

      # One ref per data/<id>.json, in numeric id order.
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        records(workdir).each do |id, path|
          yield Nabu::DocumentRef.new(source_id: manifest.id, id: "#{DICTIONARY_SLUG}:#{id}",
                                      path: File.expand_path(path), metadata: { "dictionary" => DICTIONARY_SLUG })
        end
      end

      # The rejected documentation grain (doc/), counted by rule; anything
      # else under data/ that is not a numbered record is unrecognized.
      def discovery_skips(workdir)
        docs = Dir.glob("doc/**/*", base: workdir).select { |rel| File.file?(File.join(workdir, rel)) }.sort
        strays = Dir.glob("data/*", base: workdir).reject { |rel| RECORD.match?(File.basename(rel)) }
        notes = []
        unless docs.empty?
          notes << "#{docs.size} documentation file(s) skipped — the doc/ grain, not dictionary data " \
                   "(#{docs.join(', ')})"
        end
        notes << "#{strays.size} unrecognized file(s) under data/ (#{strays.first(3).join(', ')})" unless strays.empty?
        DiscoverySkips.new(skipped_by_rule: docs.size, unrecognized: strays.size, notes: notes)
      end

      def parse(document_ref)
        record = JSON.parse(File.read(document_ref.path, encoding: "UTF-8"))
        document = Nabu::DictionaryDocument.new(slug: DICTIONARY_SLUG, language: LANGUAGE, title: TITLE,
                                                canonical_path: document_ref.path)
        head = head_entry(record)
        document << head
        variant_entries(record, head).each { |entry| document << entry }
        document
      rescue JSON::ParserError, KeyError, Nabu::ValidationError, Normalize::EncodingError => e
        raise Nabu::ParseError, "shuowen: #{document_ref.id}: #{e.message}"
      end

      def fetch(workdir, progress: nil, force: false)
        git_fetch!(repo_url: repo_url, workdir: workdir, progress: progress, force: force, sparse: SPARSE_PATHS)
      end

      private

      def repo_url = REPO_URL

      def records(workdir)
        Dir.glob(File.join(workdir, "data", "*.json")).filter_map do |path|
          match = RECORD.match(File.basename(path)) or next
          [Integer(match[1], 10), path]
        end.sort_by(&:first)
      end

      # -- the head entry ---------------------------------------------------------

      def head_entry(record)
        id = record.fetch("id").to_s
        wordhead = text(record.fetch("wordhead")) or raise Nabu::ParseError, "shuowen: #{id}: empty wordhead"
        Nabu::DictionaryEntry.new(
          entry_id: id, key_raw: record.fetch("wordhead"), language: LANGUAGE,
          headword: wordhead, headword_folded: fold(wordhead),
          gloss: text(record.fetch("explanation")),
          body: Normalize.nfc(head_body(record).join("\n")),
          crossrefs: component_refs(record) + variant_refs(record),
          annotations: head_annotations(record)
        )
      end

      def head_body(record)
        lines = ["說文: #{text(record.fetch('explanation'))}"]
        field(record, "pronunciation")&.then { |value| lines << "反切: #{value}" }
        field(record, "pinyin_full")&.then { |value| lines << "拼音: #{value}" }
        lines << placement(record)
        components(record).then { |parts| lines << "構件: #{parts.join(' ')}" unless parts.empty? }
        record.fetch("variants").each do |variant|
          glyph = text(variant["wordhead"])
          label = glyph ? "重文 #{glyph}" : "重文 (glyph not encoded)"
          lines << "#{label}: #{text(variant['explanation'])}"
        end
        field(record, "xuan_note")&.then { |value| lines << "徐鉉: #{value}" }
        field(record, "kai_note")&.then { |value| lines << "徐鍇: #{value}" }
        record.fetch("duan_notes").each do |pair|
          lines << "段注〔#{text(pair['explanation'])}〕#{text(pair['note'])}"
        end
        lines
      end

      def placement(record)
        radical = field(record, "radical")
        volume = field(record, "volume")
        "部首: #{[radical, volume && "卷#{volume}"].compact.join(' · ')}"
      end

      def head_annotations(record)
        {
          "radical" => field(record, "radical"), "volume" => field(record, "volume"),
          "fanqie" => field(record, "pronunciation"), "pinyin" => field(record, "pinyin_full"),
          "components" => components(record).then { |parts| parts.empty? ? nil : parts },
          "indexes" => index_keys(record)
        }.compact
      end

      def component_refs(record)
        components(record).map do |part|
          Nabu::DictionaryCrossref.new(kind: "component", label: "構件 #{part}", target: part,
                                       target_folded: fold(part))
        end
      end

      def variant_refs(record)
        id = record.fetch("id")
        encoded_variants(record).map do |position, glyph, _variant|
          Nabu::DictionaryCrossref.new(kind: "chongwen", label: "重文 #{glyph}", target: glyph,
                                       target_id: "#{id}-v#{position}")
        end
      end

      # -- the 重文 entries -------------------------------------------------------

      def variant_entries(record, head)
        id = record.fetch("id").to_s
        encoded_variants(record).map do |position, glyph, variant|
          Nabu::DictionaryEntry.new(
            entry_id: "#{id}-v#{position}", key_raw: variant.fetch("wordhead"), language: LANGUAGE,
            headword: glyph, headword_folded: fold(glyph),
            gloss: text(variant["explanation"]),
            body: Normalize.nfc(["說文: #{text(variant['explanation'])}",
                                 "重文 of #{head.headword} (說文 entry #{id})"].join("\n")),
            crossrefs: [Nabu::DictionaryCrossref.new(kind: "chongwen-of", label: "重文 of #{head.headword}",
                                                     target: head.headword, target_id: id)],
            annotations: { "chongwen_of" => id, "position" => position }
          )
        end
      end

      # [position (1-based, upstream array order), NFC glyph, raw variant]
      # for every variant whose glyph upstream encoded.
      def encoded_variants(record)
        record.fetch("variants").each_with_index.filter_map do |variant, index|
          glyph = text(variant["wordhead"]) or next
          [index + 1, glyph, variant]
        end
      end

      # -- helpers ----------------------------------------------------------------

      # The site's search keys, empty and duplicate keys dropped; nil when none.
      def index_keys(record)
        keys = record.fetch("indexes").filter_map { |key| text(key) }.uniq
        keys.empty? ? nil : keys
      end

      def components(record)
        record.fetch("components").filter_map { |part| text(part) }
      end

      def field(record, name) = text(record[name])

      def text(value)
        value = value.to_s.strip
        value.empty? ? nil : Normalize.nfc(value)
      end

      def fold(glyph) = Normalize.search_form(glyph, language: LANGUAGE)
    end
  end
end

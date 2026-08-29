# frozen_string_literal: true

require_relative "flat_csv_parser"

module Nabu
  module Adapters
    # The tshet-uinh Middle Chinese shelf (P32-3): nk2028/tshet-uinh-data —
    # the Qieyun-system phonological database behind the TshetUinh.js
    # ecosystem. The shelf is 韻書/廣韻.csv, the critical edition of the
    # 廣韻 (Kuangx Yonh, 1008): 25,336 rows = one CHARACTER at one
    # PHONOLOGICAL POSITION (小韻 homophone group × in-group ordinal), each
    # carrying the 音韻地位 position formula ("端一東平"), the 反切 spelling,
    # the 釋義 definition, and the repo's own 校本 correction apparatus.
    # Language ltc.
    #
    # == The 校本 apparatus, parsed HONESTLY (the packet rule)
    #
    # The upstream README documents an inline correction syntax (澤存堂本
    # base text corrected against 廣韻校本, 廣韻形聲考 etc.). Corrections
    # surface as ANNOTATIONS — never silent fixes, and the raw cell always
    # survives as key_raw:
    #
    # - 字頭 "X〈Y〉" (校訛字): headword = the corrected Y (upstream's own
    #   critical verdict), body carries 「校訛字：底本作「X」」 — both forms
    #   remain findable (X stays in key_raw and the body).
    # - 字頭 "［X］" (應補字, absent from 澤存堂本, restored per the 校本;
    #   小韻字號 gains an "a1"-style suffix): body carries 應補字.
    # - 字頭 "｛X｝" (應刪字, judged spurious): the entry STILL MINTS (never
    #   silently dropped) with an 應刪字 flag + the upstream 字頭說明 note.
    # - 反切/直音 cells ride VERBATIM, bracket annotations and all (脫字
    #   ［徒］候, 訛字 士〈七〉演, 〘〙/〖〗/｟｠ substitution marks — the
    #   documented syntax is quoted in the fixture README); nothing is
    #   applied or stripped.
    # - 釋義參照 上/下 ("同上"-style pointers) are preserved as body notes,
    #   never resolved into neighboring rows.
    # - 3 headwords are unencoded characters as IDS sequences (⿱𱡘正 …) —
    #   kept whole.
    #
    # == The 王三 second shelf (P88-R4, owner GO 2026-08-29)
    #
    # 韻書/王三.csv — 王仁昫《刊謬補缺切韻》 (~706), the fullest surviving
    # recension of the 601 Qieyun: with `qieyun-restored` (P88-A2) it
    # completes the ladder 切韻 601 → 王三 → 廣韻 1008. Same canonical dir,
    # so the SAME source mints a second dictionary (slug `wangsan`, ltc;
    # Store::DictionaryLoader keys dictionaries by slug, entries by
    # (dictionary, entry_id) — two slugs from one source is the design).
    # Upstream still marks the file 小韻內部待校 (in-rhyme ordering under
    # collation) — entries parse verbatim anyway (canonical means
    # canonical); a future upstream reorder only revises rows.
    #
    # The column set is NOT the 廣韻 shape (censused from bytes 2026-08-29,
    # 17,232 rows, no quoting): 小韻號,鈴木ID,鈴木小韻號,頁號,行號,字號,
    # 韻目原貌,首字,反切,地位,切韻拼音,小韻內字序,字頭,釋義. No 直音 /
    # 字頭說明 / 釋義參照; 地位 plays 音韻地位's role; 切韻拼音 is new.
    # entry_id = 小韻號.小韻內字序 — the ONLY unique pair (17,232 distinct;
    # 小韻號.字號 collides, 16,126). The 鈴木ID/鈴木小韻號 cross-reference
    # numbers (Suzuki Shingo's rhyme-book database) stay out of bodies —
    # id-apparatus, rebuildable from canonical; 頁號/行號/字號 ride as one
    # 底本位置 locus line. 字頭 shapes censused: 143 應補字 ［X］ (with a
    # ".1"-style ordinal suffix, the a1 analogue), ONE 校訛字 X〈Y〉, ZERO
    # 應刪字 ｛X｝ (the branch stays unwired here), 6 empty ［］ slots
    # (supplied but unrecovered — headword rides verbatim, never
    # interpreted), 3 【X】 rows (undocumented upstream — verbatim), IDS
    # sequences kept whole, and 5 headword-LESS rows (待校 slots, 釋義 "。"
    # etc.) — unmintable without a key, so they are SKIPPED, censused here
    # and pinned in the fixture (the OpenEtruscan explicit-skip stance):
    # expect 17,232 − 5 = 17,227 wangsan entries.
    #
    # == The file-set census (repo @ 2025-11-17, whole)
    #
    # 韻書/廣韻.csv 25,336 rows (INGESTED — the complete, corrected shelf) ·
    # 韻書/王三.csv 17,232 rows (INGESTED P88-R4 as the `wangsan` shelf —
    # see above; upstream 小韻內部待校) ·
    # 韻書/王一.csv 2 rows (stub, "not completed") · 韻圖/韻鏡（古逸叢書本）.csv
    # 3,871 rows + 韻圖/韻鏡（嘉吉本）.csv 622 rows (rhyme-TABLE grid
    # positions — no definitions, a different content kind) ·
    # 反切音韻地位/廣韻反切音韻地位表.csv 3,872 rows + 王三反切音韻地位表.csv
    # 3,656 rows (per-小韻 fanqie analyses — derivable apparatus). Only
    # 廣韻.csv and 王三.csv mint entries; the rest are censused in
    # docs/02-sources.md and test/fixtures/tshet-uinh/README.md. The sibling nk2028
    # zhongyuan-data repo (中原音韻, CC0) is JOURNALED, not registered: a
    # different physical format (TSV of four parallel scholarly
    # reconstructions, no 校本 apparatus) and no honest ISO 639-3 tag for
    # Old Mandarin (cmn would misfile a 1324 rhyme book) — an owner call.
    #
    # == License (verified IN-REPO, not just the GitHub field)
    #
    # LICENSE at the repo root is the full CC0 1.0 Universal legal code
    # ("Creative Commons Legal Code / CC0 1.0 Universal …", verified
    # 2026-07-19; the GitHub license field agrees) → license_class open.
    #
    # == fetch / sync policy
    #
    # Plain GitFetch of the whole repo (~10 MB; no sparse cone needed).
    # Upstream moves occasionally (last push 2025-11-17) → sync_policy:
    # manual, owner re-fires.
    class TshetUinh < Nabu::Adapter
      REPO_URL = "https://github.com/nk2028/tshet-uinh-data"

      FILENAME = "廣韻.csv"
      DICTIONARY_SLUG = "guangyun"
      LANGUAGE = "ltc"
      TITLE = "廣韻 — Kuangx Yonh critical edition (tshet-uinh-data)"

      REQUIRED_HEADERS = %w[小韻號 小韻字號 韻目原貌 音韻地位 反切 直音 字頭 字頭說明
                            釋義 釋義參照].freeze

      # The 王三 second shelf (P88-R4; class note above for the census).
      WANGSAN_FILENAME = "王三.csv"
      WANGSAN_SLUG = "wangsan"
      WANGSAN_TITLE = "王三 — 王仁昫《刊謬補缺切韻》 (tshet-uinh-data)"
      WANGSAN_REQUIRED_HEADERS = %w[小韻號 小韻內字序 頁號 行號 字號 韻目原貌 首字
                                    反切 地位 切韻拼音 字頭 釋義].freeze

      # filename → dictionary slug, in id-sorted order (guangyun first).
      SHELVES = { FILENAME => DICTIONARY_SLUG, WANGSAN_FILENAME => WANGSAN_SLUG }.freeze

      # The documented 字頭 annotation shapes (upstream README, quoted in
      # the fixture README).
      SUPPLEMENT = /\A［(.+)］\z/ # 應補字
      DELETION = /\A｛(.+)｝\z/ # 應刪字
      CORRECTION = /\A(.*)〈(.+)〉\z/ # 校訛字

      MANIFEST = Nabu::SourceManifest.new(
        id: "tshet-uinh",
        name: "tshet-uinh-data — 廣韻 critical edition (nk2028 Qieyun-system database)",
        license: "CC0 1.0 Universal (the in-repo LICENSE file carries the full legal code, " \
                 "verified 2026-07-19; the GitHub license field agrees)",
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

      # One DocumentRef per ingested CSV (廣韻 + 王三, P88-R4); the rest of
      # the repo's file set is census-only. The same walk works under the
      # attic.
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        SHELVES.each do |filename, slug|
          Dir.glob(File.join(workdir, "**", filename)).first(1).each do |path|
            yield Nabu::DocumentRef.new(
              source_id: manifest.id,
              id: "#{slug}:#{filename}",
              path: File.expand_path(path),
              metadata: { "dictionary" => slug }
            )
          end
        end
      end

      def parse(document_ref)
        if document_ref.metadata["dictionary"] == WANGSAN_SLUG
          parse_wangsan(document_ref)
        else
          parse_guangyun(document_ref)
        end
      rescue Nabu::ValidationError => e
        raise Nabu::ParseError, "tshet-uinh: #{document_ref.id}: #{e.message}"
      end

      # Clone or non-destructively pull the repo via the shared git path
      # (GitFetch: attic + pre-merge mass-deletion breaker).
      def fetch(workdir, progress: nil, force: false)
        git_fetch!(repo_url: repo_url, workdir: workdir, progress: progress, force: force)
      end

      private

      # Split out so fetch tests can point a singleton at a local git tmpdir
      # (the house pattern), keeping fetch off the network.
      def repo_url
        manifest.upstream_url
      end

      def parse_guangyun(document_ref)
        document = Nabu::DictionaryDocument.new(
          slug: DICTIONARY_SLUG, language: LANGUAGE,
          title: TITLE, canonical_path: document_ref.path
        )
        parser.each_row(document_ref.path) { |row| document << build_entry(row, document_ref.path) }
        document
      end

      def parse_wangsan(document_ref)
        document = Nabu::DictionaryDocument.new(
          slug: WANGSAN_SLUG, language: LANGUAGE,
          title: WANGSAN_TITLE, canonical_path: document_ref.path
        )
        wangsan_parser.each_row(document_ref.path) do |row|
          entry = build_wangsan_entry(row, document_ref.path)
          document << entry if entry
        end
        document
      end

      def parser
        FlatCsvParser.new(required_headers: REQUIRED_HEADERS)
      end

      def wangsan_parser
        FlatCsvParser.new(required_headers: WANGSAN_REQUIRED_HEADERS)
      end

      # -- entry building ------------------------------------------------------

      def build_entry(row, path)
        entry_id = "#{row.fetch('小韻號')}.#{row.fetch('小韻字號')}"
        raw = row.fetch("字頭").to_s.strip
        headword, correction_lines = headword_and_annotations(raw)
        Nabu::DictionaryEntry.new(
          entry_id: entry_id, key_raw: raw, language: LANGUAGE,
          headword: Normalize.nfc(headword),
          headword_folded: Normalize.search_form(headword, language: LANGUAGE),
          gloss: gloss(row),
          body: body_text(row, correction_lines),
          citations: []
        )
      rescue Nabu::ValidationError, Normalize::EncodingError => e
        raise Nabu::ParseError, "tshet-uinh: row #{entry_id.inspect} in #{path}: #{e.message}"
      end

      # [headword, annotation-lines] — the 校本 verdict names the entry, the
      # transmitted state stays visible (class note).
      def headword_and_annotations(raw)
        case raw
        when SUPPLEMENT then [Regexp.last_match(1), ["應補字：澤存堂本無此字，據校本補"]]
        when DELETION then [Regexp.last_match(1), ["應刪字：校本判此字當刪"]]
        when CORRECTION then correction(Regexp.last_match(1), Regexp.last_match(2))
        else [raw, []]
        end
      end

      def correction(transmitted, corrected)
        [corrected, ["校訛字：底本作「#{transmitted}」，校作「#{corrected}」"]]
      end

      def gloss(row)
        text = row["釋義"].to_s.strip
        text.empty? ? nil : Normalize.nfc(text)
      end

      def body_text(row, correction_lines)
        lines = [
          labeled(row, "音韻地位", "音韻地位"), labeled(row, "韻目原貌", "韻目"),
          labeled(row, "反切", "反切"), labeled(row, "直音", "直音"),
          *correction_lines, labeled(row, "字頭說明", "字頭說明"),
          labeled(row, "釋義", "釋義"), reference_line(row)
        ].compact
        Normalize.nfc(lines.join("\n"))
      end

      def labeled(row, column, label)
        value = row[column].to_s.strip
        value.empty? ? nil : "#{label}：#{value}"
      end

      # 釋義參照 上/下 — the 「同上」-style pointer, preserved, never resolved.
      def reference_line(row)
        case row["釋義參照"].to_s.strip
        when "上" then "釋義參照：上（釋義承上字）"
        when "下" then "釋義參照：下（釋義見下字）"
        end
      end

      # -- 王三 entry building (P88-R4; census in the class note) --------------

      # nil for the 5 censused headword-less 待校 slots — no key, no entry
      # (the explicit, censused skip; never a placeholder headword).
      def build_wangsan_entry(row, path)
        entry_id = "#{row.fetch('小韻號')}.#{row.fetch('小韻內字序')}"
        raw = row.fetch("字頭").to_s.strip
        return nil if raw.empty?

        headword, correction_lines = wangsan_headword_and_annotations(raw)
        Nabu::DictionaryEntry.new(
          entry_id: entry_id, key_raw: raw, language: LANGUAGE,
          headword: Normalize.nfc(headword),
          headword_folded: Normalize.search_form(headword, language: LANGUAGE),
          gloss: gloss(row),
          body: wangsan_body_text(row, correction_lines),
          citations: []
        )
      rescue Nabu::ValidationError, Normalize::EncodingError => e
        raise Nabu::ParseError, "tshet-uinh: row #{entry_id.inspect} in #{path}: #{e.message}"
      end

      # Only the shapes the census found: 應補字 ［X］ (base-neutral wording —
      # the 王三 base is the manuscript, not 澤存堂本) and the one 校訛字
      # X〈Y〉. 應刪字 never occurs here; empty ［］ slots and the 3
      # undocumented 【X】 rows fall through VERBATIM (never interpreted).
      def wangsan_headword_and_annotations(raw)
        case raw
        when SUPPLEMENT then [Regexp.last_match(1), ["應補字：底本無此字，據校補"]]
        when CORRECTION then correction(Regexp.last_match(1), Regexp.last_match(2))
        else [raw, []]
        end
      end

      def wangsan_body_text(row, correction_lines)
        lines = [
          labeled(row, "地位", "音韻地位"), labeled(row, "切韻拼音", "切韻拼音"),
          labeled(row, "韻目原貌", "韻目"), labeled(row, "首字", "小韻首字"),
          labeled(row, "反切", "反切"), *correction_lines,
          labeled(row, "釋義", "釋義"), wangsan_locus(row)
        ].compact
        Normalize.nfc(lines.join("\n"))
      end

      # 頁號/行號/字號 — the manuscript locus, one compact line (the 鈴木
      # cross-reference ids deliberately stay out; class note).
      def wangsan_locus(row)
        "底本位置：頁#{row.fetch('頁號')} 行#{row.fetch('行號')} 字#{row.fetch('字號')}"
      end
    end
  end
end

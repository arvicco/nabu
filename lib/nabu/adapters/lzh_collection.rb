# frozen_string_literal: true

require_relative "source_read"

module Nabu
  module Adapters
    # nk2028's Classical Chinese Collection (github.com/nk2028/lzh-collection):
    # plain-text Literary Chinese contributed to the nk2028 group's
    # collection (README: thanks to Billy Zhou). Scoped to the DISTINCT
    # REMAINDER — the eighteen Ming and Qing individual poetry collections
    # (別集) the library does not otherwise hold.
    #
    # == Upstream + the dedupe census (2026-10-29, upstream main, last push 2023-02-27)
    #
    # data/ serves 30 UTF-8 .txt files, one work each (LF, no BOM). Before
    # any code the collection was censused against the held catalog
    # (titles + twelve evenly spaced six-character content samples per
    # file, grepped over canonical kanripo / zh-wikisource / ccl /
    # classical-modern / cbeta):
    #
    #   ACCEPTED (20 files, 19 poets, 42,303 non-blank lines): the
    #     Ming–Qing 別集 — 劉大櫆 海峰詩集, 史可法 史忠正公集 (the poems), 吳汝綸,
    #     徐中行 天目先生集, 林古度 林茂之詩選 + its 補遺 (two files), 梁有譽
    #     蘭汀存藳, 沈德潛 歸愚詩鈔 (+ 詞), 王九思 渼陂集, 趙翼 甌北集, 申涵光
    #     聰山詩選, 譚元春 嶽歸堂合集, 邵晉涵 南江詩鈔, 陳子龍 陳忠裕公全集 (詩詞),
    #     顧廣圻 思適齋集 (詩詞), 夏完淳 夏節愍全集, 林則徐 雲左山房詩鈔, 盧世㴶
    #     尊水園集略, 鍾惺, 鄧廷楨 雙硯齋詩鈔. 0–1 of 12 samples held each (a
    #     stray hit is an anthology quotation; 沈德潛's 歸愚詞 alone is held,
    #     kanripo KR4j0037 — the 詩鈔 is not).
    #   SKIPPED by rule (10 files, held elsewhere, counted in
    #     discovery_skips): the nine Masters 白文 texts 公孫龍子 列子 墨子 新語
    #     法言 管子 老子 荀子 韓非子 (8–12 of 12 samples in kanripo, which holds
    #     every one; most are also in classical-modern) and 李夢陽詩集 (8/12 —
    #     kanripo KR4e0150 空同集). The HELD table names each witness.
    #   Any other data file is UNRECOGNIZED — loud, never ingested unread.
    #
    # Reconciliation: 20 accepted + 10 skipped by rule = the 30 files
    # upstream serves (it advertises no count of its own).
    #
    # == Shape
    #
    # One document per accepted file, urn:nabu:lzh-collection:<title> (the
    # file stem less upstream's 1_/2_ batch prefix); passage = one non-blank
    # line (a juan heading, a poem title, a poem or a preface paragraph —
    # upstream's own lines, interlinear variant notes "（一作上）" verbatim),
    # numbered in file order; lines after a juan heading (卷 + numeral, no
    # sentence punctuation) carry {"juan" => heading}. Metadata: the poet
    # (from the file name, or the table for the two titles that do not
    # name him) and the collection title. NFC at the boundary folds the
    # CJK compatibility ideographs upstream carries (22 lines in four
    # files) to their unified forms — the house invariant.
    #
    # == License
    #
    # In-repo LICENSE: the full CC0 1.0 Universal legal code ("Creative
    # Commons Legal Code / CC0 1.0 Universal"); the GitHub license field
    # reads CC0-1.0 (verified 2026-10-29) → class open. PROVENANCE: the
    # repo names no print edition for any text; the punctuation and the
    # inline variant notes come from an unnamed modern collated edition —
    # recorded, not guessed.
    #
    # == fetch / sync policy
    #
    # Plain GitFetch (~7 MB working tree); dormant since 2023-02 → manual.
    class LzhCollection < Nabu::Adapter
      REPO_URL = "https://github.com/nk2028/lzh-collection"
      DATA_DIR = "data"
      LANGUAGE = "lzh"
      URN_PREFIX = "urn:nabu:lzh-collection:"

      # Accepted files → the poet (the file stem names him except for the
      # 甌北集 and 雙硯齋詩鈔 rows).
      WORKS = {
        "1_劉大櫆詩集.txt" => "劉大櫆", "1_史可法詩集.txt" => "史可法", "1_吳汝綸詩集.txt" => "吳汝綸",
        "1_徐中行詩集.txt" => "徐中行", "1_林古度詩集.txt" => "林古度", "1_林古度詩集補遺.txt" => "林古度",
        "1_梁有誉詩集.txt" => "梁有譽", "1_沈德潛詩詞集.txt" => "沈德潛", "1_王九思詩集.txt" => "王九思",
        "1_甌北集.txt" => "趙翼", "1_申涵光詩集.txt" => "申涵光", "1_譚元春詩集.txt" => "譚元春",
        "1_邵晉涵詩集.txt" => "邵晉涵", "1_陳子龍詩詞集.txt" => "陳子龍", "1_顧廣圻詩詞集.txt" => "顧廣圻",
        "2_夏完淳詩集.txt" => "夏完淳", "2_林則徐詩集.txt" => "林則徐", "2_盧世㴶詩集.txt" => "盧世㴶",
        "鍾惺詩全集.txt" => "鍾惺", "雙硯齋詩鈔.txt" => "鄧廷楨"
      }.freeze

      # Skipped by rule: works the library already holds (class note).
      HELD = {
        "公孫龍子白文.txt" => "kanripo KR3j0007 公孫龍子", "列子白文.txt" => "kanripo KR5c0124 列子",
        "墨子白文.txt" => "kanripo KR3j0002 墨子", "新語白文.txt" => "kanripo KR3a0004 新語",
        "法言白文.txt" => "kanripo KR3a0009 揚子法言", "管子白文.txt" => "kanripo KR3c0001 管子",
        "老子白文.txt" => "kanripo KR5c0057 老子", "荀子白文.txt" => "kanripo KR3a0002 荀子",
        "韓非子白文.txt" => "kanripo KR3c0005 韓非子", "2_李夢陽詩集.txt" => "kanripo KR4e0150 空同集"
      }.freeze

      JUAN = /卷[一二三四五六七八九十百〇零]+/
      SENTENCE_PUNCTUATION = /[，。；：？！]/

      MANIFEST = Nabu::SourceManifest.new(
        id: "lzh-collection",
        name: "nk2028 Classical Chinese Collection — Ming–Qing poetry collections (別集)",
        license: "CC0 1.0 (in-repo LICENSE, the full \"CC0 1.0 Universal\" legal code; GitHub " \
                 "license field CC0-1.0; verified 2026-10-29). Provenance: no print edition is named " \
                 "for any text",
        license_class: "open",
        upstream_url: REPO_URL,
        parser_family: "plain-lines",
        credit: "nk2028 (github.com/nk2028/lzh-collection), texts contributed by Billy Zhou"
      )

      def self.manifest = MANIFEST

      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        data_files(workdir).each do |name|
          next unless WORKS.key?(name)

          yield Nabu::DocumentRef.new(source_id: manifest.id, id: "#{URN_PREFIX}#{title_for(name)}",
                                      path: File.expand_path(File.join(DATA_DIR, name), workdir),
                                      metadata: { "file" => name })
        end
      end

      def discovery_skips(workdir)
        files = data_files(workdir).reject { |name| WORKS.key?(name) }
        held, strays = files.partition { |name| HELD.key?(name) }
        notes = held.map { |name| "#{DATA_DIR}/#{name}: held elsewhere — #{HELD.fetch(name)}" } +
                strays.map { |name| "#{DATA_DIR}/#{name}: not a censused lzh-collection text" }
        DiscoverySkips.new(skipped_by_rule: held.size, unrecognized: strays.size, notes: notes)
      end

      def parse(document_ref)
        name = document_ref.metadata.fetch("file")
        title = title_for(name)
        document = Nabu::Document.new(
          urn: document_ref.id, language: LANGUAGE, title: title,
          metadata: { "author" => WORKS.fetch(name), "work" => title, "file" => "#{DATA_DIR}/#{name}" },
          canonical_path: document_ref.path
        )
        each_passage(document_ref) { |passage| document << passage }
        raise Nabu::ParseError, "lzh-collection: #{document_ref.id}: no text lines" if document.empty?

        document
      rescue Nabu::ValidationError, KeyError => e
        raise Nabu::ParseError, "lzh-collection: #{document_ref.id}: #{e.message}"
      end

      def fetch(workdir, progress: nil, force: false)
        git_fetch!(repo_url: repo_url, workdir: workdir, progress: progress, force: force)
      end

      private

      # Seam for tests (the house local-git pattern).
      def repo_url = REPO_URL

      def data_files(workdir)
        dir = File.join(workdir, DATA_DIR)
        return [] unless File.directory?(dir)

        names = Dir.children(dir).map { |name| name.unicode_normalize(:nfc) }
        names.select { |name| File.file?(File.join(dir, name)) }.sort
      end

      # The file stem less upstream's numeric batch prefix ("1_", "2_").
      def title_for(name) = File.basename(name, ".txt").sub(/\A\d+_/, "")

      def each_passage(document_ref)
        text = SourceRead.utf8_file(document_ref.path, label: "lzh-collection")
        juan = nil
        number = 0
        text.each_line do |raw|
          line = Nabu::Normalize.nfc(raw.strip)
          next if line.empty?

          juan = line if juan_heading?(line)
          number += 1
          yield Nabu::Passage.new(urn: "#{document_ref.id}:#{number}", language: LANGUAGE, text: line,
                                  annotations: juan ? { "juan" => juan } : {}, sequence: number)
        end
      end

      def juan_heading?(line)
        JUAN.match?(line) && !SENTENCE_PUNCTUATION.match?(line) && line.length <= 40
      end
    end
  end
end

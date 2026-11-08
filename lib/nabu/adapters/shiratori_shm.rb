# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"

require_relative "source_read"
require_relative "../redirect_follow"
require_relative "../wiki_fetch"
require_relative "../zip_fetch"
require_relative "../normalize"

module Nabu
  module Adapters
    # shiratori-shm — Shiratori Kurakichi's 音訳蒙文元朝秘史 (A Romanised
    # Representation of the Yüan-ch'ao-pi-shih in its Original Mongolian
    # Sound; Tōyō Bunko Publications Series C, vol. VIII; Tokyo: Tōyō
    # Bunko, 昭和18 = 1943 per the NDL record — the English title leaf
    # reads 1942), as the NDL digital collection's OCR full text of
    # pid 1184344 (the manchu-mongolic round-2 survey §2.4).
    #
    # == A second Middle Mongol edition, not a dedupe
    #
    # The library already holds the Secret History as Street's romanized
    # text (altaica-shm, v24 2013, his own line grain). Shiratori's is a
    # DISTINCT edition: Ye Dehui's 1908 print of the Ming hanzi
    # transcription reproduced leaf for leaf (its leaf numbers kept), with
    # Shiratori's romanized re-transcription of the Mongolian set beside
    # each hanzi word, the Ming interlinear glosses and the 總譯 Chinese
    # summary translation. Two editions of one work, each its own
    # editorial witness — the house keeps both (the eebo-tcp / noscemus
    # witness rule).
    #
    # == Route (the NDL Lab bulk route, held)
    #
    # The same per-book endpoint the ndl-kotenseki adapter crawls —
    # lab.ndl.go.jp/dl/api/book/fulltext-json/<pid>, the route NDL Lab
    # granted by email (2026-09-29; ~1 request/s, here ONE request).
    # ndl-kotenseki is census-driven (the 古典籍 open-dataset file, which
    # this 1943 図書 is not in) and claims jpn for its whole mass, so the
    # book rides its own single-PID slug rather than a declared extra PID
    # there: no ndl-kotenseki machinery changes and its 26k-book slice
    # never re-derives for one book. The book is fetched once and held
    # (the OCR is a published derivative; a re-OCR upstream is caught only
    # by deleting the held file — declared).
    #
    # == Documents and passages
    #
    # One document (urn:nabu:shiratori-shm:1184344), one passage per koma
    # (the scan frame — usually a two-page opening) with letters in its OCR
    # contents (:<page>, upstream's own koma number). Skipped by rule, with
    # the count in metadata "koma_skipped": the Kodak colour-calibration
    # target (koma 1) and letterless koma (a bare page number). The per-line
    # coordinate layer (coordjson: contenttext + bbox per OCR line) is NOT
    # taken — layout, not text; the koma's contents carry the same text.
    #
    # == Language per koma (the OCR's own script mix decides)
    #
    # kana-bearing front matter (序, 凡例) → jpn; the interlinear body
    # (hanzi transcription + Shiratori's Latin romanization) → xng;
    # Han-only koma BEFORE the body → lzh (Ye Dehui's preface and the
    # Qing colophons, classical Chinese) except the short title leaf (jpn,
    # the Japanese edition's own furniture); Han-only koma INSIDE the body
    # → zho (the Ming 總譯 summary translation — the layer zh-wikisource
    # holds as zho); Latin-only back matter (the English foreword,
    # explanations and title) → eng. The document claims xng.
    #
    # == License
    #
    # Public domain: Shiratori died 1942 — Wikimedia Commons' file page for
    # the same scan reads {{PD-scan|PD-old-auto-1996|deathyear=1942|
    # country=JP}}; PD in Japan since 1993, so no URAA restoration (US PD
    # too). The OCR is NDL's machine full text — text_nature machine-ocr,
    # uncorrected (〓 marks NDL's own unreadable-glyph dropouts), permalink
    # carried.
    class ShiratoriShm < Nabu::Adapter
      PID = "1184344"
      BOOK_URL = "https://lab.ndl.go.jp/dl/api/book/fulltext-json/%s"
      BOOKS_DIRNAME = "books"
      URN = "urn:nabu:shiratori-shm:#{PID}".freeze
      LANGUAGE = "xng"

      # A koma whose OCR names the colour/grey-scale target is the scan's
      # calibration frame, never text.
      CALIBRATION = /Kodak (?:Gray Scale|Color Control)/
      # The title leaf: a Han-only front-matter koma shorter than this
      # (in Han characters) is the edition's title furniture (koma 3: 31).
      TITLE_LEAF_MAX = 60
      # Script-class thresholds (letters per koma).
      KANA_MIN = 10
      LATIN_MIN = 20
      HAN_MIN = 20

      OCR_NOTE = "NDL's machine OCR full text (the 次世代デジタルライブラリー bulk API), never proofread: " \
                 "the hanzi transcription, Shiratori's romanization and the interlinear glosses of each " \
                 "opening run together in reading order as the OCR found them, with 〓 for glyphs it " \
                 "could not read. Cite the scan (permalink)."

      MANIFEST = Nabu::SourceManifest.new(
        id: "shiratori-shm",
        name: "Shiratori Kurakichi, 音訳蒙文元朝秘史 — the romanized Secret History of the Mongols " \
              "(Tōyō Bunko 1943; NDL OCR full text)",
        license: "Public domain: Shiratori Kurakichi died 1942 (Wikimedia Commons file page for the " \
                 "same scan: PD-scan, PD-old-auto-1996, deathyear=1942, country=JP). Text = the " \
                 "National Diet Library digital collection's machine OCR (dl.ndl.go.jp/pid/1184344), " \
                 "fetched through the NDL Lab bulk full-text API (route confirmed by NDL Lab by email, " \
                 "2026-09-29); credit the National Diet Library digital collections",
        license_class: "open",
        upstream_url: "https://dl.ndl.go.jp/pid/1184344",
        parser_family: "ndl-fulltext-json"
      )

      def self.manifest = MANIFEST

      def self.remote_probe_strategy = :http_zip

      # Liveness only: the book is held once fetched, so drift reads unknown.
      def self.http_probe_targets
        [Nabu::Adapter::HttpProbeTarget.new(
          label: "fulltext-json #{PID}", zip_url: format(BOOK_URL, PID), metadata_url: nil,
          state_subdir: "", liveness_only: true
        )]
      end

      # One koma's language from its OCR's script mix (see the header);
      # +body+ is whether the interlinear body has begun.
      def self.koma_language(text, body:)
        kana = text.scan(/[\p{Hiragana}\p{Katakana}]/).size
        han = text.scan(/\p{Han}/).size
        latin = text.scan(/[A-Za-z]/).size
        return "jpn" if kana >= KANA_MIN && kana > latin
        return "eng" if latin >= LATIN_MIN && han * 5 < latin
        return "xng" if latin >= LATIN_MIN && han >= HAN_MIN
        return "zho" if body

        han < TITLE_LEAF_MAX ? "jpn" : "lzh"
      end

      def initialize(http: Nabu::ZipFetch.default_http)
        super()
        @http = http
      end

      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        path = book_path(workdir)
        return unless File.file?(path)

        yield Nabu::DocumentRef.new(source_id: MANIFEST.id, id: URN, path: File.expand_path(path),
                                    metadata: { "pid" => PID })
      end

      def discovery_skips(workdir)
        strays = Dir.glob(File.join(workdir, "**", "*"))
                    .select { |path| File.file?(path) }
                    .reject { |path| path.include?("/#{ATTIC_DIRNAME}/") }
                    .reject { |path| File.basename(path).start_with?(".") }
                    .reject { |path| File.basename(path).downcase == "readme.md" }
                    .reject { |path| File.expand_path(path) == File.expand_path(book_path(workdir)) }
                    .map { |path| path.delete_prefix("#{workdir}/") }
                    .sort
        Nabu::Adapter::DiscoverySkips.new(unrecognized: strays.size,
                                          notes: strays.map { |rel| "non-corpus file: #{rel}" })
      end

      def parse(document_ref)
        book = read_book(document_ref.path)
        passages, skipped = koma_passages(book)
        document = Nabu::Document.new(
          urn: URN, language: LANGUAGE, canonical_path: document_ref.path,
          title: "音訳蒙文元朝秘史 (Shiratori Kurakichi, 1943)",
          metadata: metadata_for(book).merge("koma_skipped" => skipped)
        )
        passages.each { |passage| document << passage }
        raise Nabu::ParseError, "#{document_ref.path}: no koma with text" if document.passages.empty?

        document
      end

      # +force+ is part of the fetch interface; nothing is ever deleted.
      def fetch(workdir, progress: nil, force: false) # rubocop:disable Lint/UnusedMethodArgument
        path = book_path(workdir)
        unless File.file?(path)
          progress&.call("GET #{format(BOOK_URL, PID)}\n")
          body = download_book
          FileUtils.mkdir_p(File.dirname(path))
          File.binwrite("#{path}.part", body)
          File.rename("#{path}.part", path)
        end
        Nabu::FetchReport.new(sha: Digest::SHA256.file(path).hexdigest, fetched_at: Time.now,
                              notes: "pid #{PID} held (#{File.size(path)} bytes)")
      end

      private

      def book_path(workdir) = File.join(workdir, BOOKS_DIRNAME, "#{PID}.json")

      def download_book
        response, = Nabu::RedirectFollow.get(
          format(BOOK_URL, PID), http: @http, error: Nabu::FetchError,
                                 headers: { "User-Agent" => Nabu::WikiFetch::USER_AGENT }
        )
        body = response.body.to_s
        unless body.lstrip.start_with?("{") && JSON.parse(body)["list"].is_a?(Array)
          raise Nabu::FetchError, "#{MANIFEST.id}: pid #{PID} answered no koma list (#{body[0, 80].inspect})"
        end

        body
      rescue JSON::ParserError => e
        raise Nabu::FetchError, "#{MANIFEST.id}: pid #{PID} answered unparseable JSON: #{e.message}"
      end

      def read_book(path)
        book = JSON.parse(SourceRead.utf8_file(path, label: "shiratori-shm book"))
        raise ParseError, "#{path}: no koma list in the book payload" unless book["list"].is_a?(Array)

        book
      rescue JSON::ParserError, Errno::ENOENT => e
        raise ParseError, "#{path}: unreadable book payload: #{e.message}"
      end

      # [passages, skip tally {"calibration" => n, "letterless" => n}].
      def koma_passages(book)
        skipped = Hash.new(0)
        passages = []
        body = false
        book["list"].sort_by { |koma| koma["page"].to_i }.each do |koma|
          text = Normalize.nfc(koma["contents"].to_s.strip)
          next if text.empty?
          next skipped["calibration"] += 1 if text.match?(CALIBRATION)
          next skipped["letterless"] += 1 unless text.match?(/\p{L}/)

          language = self.class.koma_language(text, body: body)
          body ||= language == LANGUAGE
          passages << Nabu::Passage.new(
            urn: "#{URN}:#{koma['page']}", language: language, text: text,
            sequence: passages.size + 1, annotations: { "koma" => koma["page"].to_s }
          )
        end
        [passages, skipped.to_h]
      end

      def metadata_for(book)
        {
          "author" => "白鳥庫吉 (Shiratori Kurakichi, 1865–1942)",
          "title" => "音訳蒙文元朝秘史",
          "title_en" => "A Romanised Representation of the Yüan-ch'ao-pi-shih (A Secret History of the " \
                        "Mongols) in its Original Mongolian Sound",
          "series" => "東洋文庫叢刊 第8 (The Tōyō Bunko Publications, Series C, Volume VIII)",
          "publisher" => "東洋文庫 (Tōyō Bunko), Tokyo",
          "date" => { "not_before" => 1943, "not_after" => 1943, "class" => "edition",
                      "raw" => "昭和18 (1943), the NDL record; the English title leaf reads 1942" },
          "base_edition" => "葉德輝 (Ye Dehui), 元朝祕史, 1908 (光緒三十四年) — reproduced leaf for leaf",
          "work_note" => "the Secret History of the Mongols (Mongqol-un niuča tobča'an), 13th century; " \
                         "a second Middle Mongol edition beside altaica-shm (Street v24)",
          "facets" => { "author" => { "values" => ["白鳥庫吉"] } },
          "text_nature" => "machine-ocr", "ocr_note" => OCR_NOTE,
          "permalink" => "https://dl.ndl.go.jp/pid/#{PID}",
          "koma_count" => book["list"].size
        }
      end
    end
  end
end

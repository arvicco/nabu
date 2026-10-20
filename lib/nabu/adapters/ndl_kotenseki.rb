# frozen_string_literal: true

require "csv"
require "digest"
require "fileutils"
require "json"

require_relative "../url_download"
require_relative "../xlsx"
require_relative "../zip_fetch"
require_relative "../redirect_follow"
require_relative "../normalize"
require_relative "../eras"
require_relative "ndl_search_bib"

module Nabu
  module Adapters
    # ndl-kotenseki (P109-2, phase 1): the NDL 次世代デジタルライブ
    # ラリー classical-materials (古典籍) OCR full-text mass, over the
    # bulk route NDL Lab granted (by email, 2026-09-29): the Bulk
    # Download API for Full-Text Data (JSON) — per-book
    # lab.ndl.go.jp/dl/api/book/fulltext-json/<pid> — with the PID list
    # from the documented open-dataset bibliography steps. The
    # COMMITTED etiquette (stated by NDL, promised back): ~1 request
    # per second — DELAY guards it; never lower it.
    #
    # == The resumable crawl (the cantigas/TitusFetch mold)
    #
    # The census: the NDL open bibliographic dataset's 古典籍 internet-
    # public file (CENSUS_URL, a dated immutable snapshot; public
    # domain), filtered to 権利区分「保護期間満了」— 97,731 PIDs at the
    # 2026-02 snapshot — and derived into census.tsv (pid + the bib
    # columns parse joins back). The crawl: up to SLICE books per sync,
    # resume at the file grain (books/<pid>.json on disk is done); a
    # PID the API refuses ("This PID is not allowed" — the spec's own
    # caveat that not every census PID has downloadable text) or
    # answers empty is ledgered in .ndl-crawl.json and never retried.
    # A book that HANGS (Net::ReadTimeout — two PIDs once wedged the
    # crawl at 26,860: every resumed slice re-hit them and died) is
    # retried in-slice TIMEOUT_ATTEMPTS times with backoff, then
    # ledgered under its own reason ("timeout-stuck" — distinct from a
    # 403 denial, so a later phase can deliberately revisit the class)
    # and the slice advances; the sync notes name the stuck PIDs.
    # The full mass is a multi-phase paced crawl by design (the
    # remainder stays queued); each sync's report shows the crawl position.
    #
    # == Documents
    #
    # One document per book (urn:nabu:ndl-kotenseki:<pid>), one passage
    # per koma with non-empty OCR contents (:<page>). Every document
    # carries text_nature "machine-ocr" (the OCR-nature labelling
    # promised in the ask) and the dl.ndl.go.jp permalink (the per-item
    # NDL provenance, likewise promised). Language jpn — DELIBERATELY
    # COARSE (declared): the mass mixes Japanese and kanbun; no
    # per-item language field exists in the bibliography.
    #
    # == Axes (owner ruling 2026-09-26)
    #
    # 出版日（W3CDTF） mints the date envelope (every 4-digit year in
    # the ||-separated value; the bare sentinel "1000" — 5,388 rows,
    # censused 2026-09-29, the dataset's unknown-date placeholder —
    # mints nothing, declared); the prose 出版日 rides verbatim as raw.
    # 件名 (subjects, ||-separated) and コレクション facet.
    #
    # == The NDL Search bib join (bib/<pid>.xml)
    #
    # The census bibliography carries no classification, no authority
    # forms and — on ~59% of held books — no typed year. NDL Search
    # (国立国会図書館サーチ) holds the richer records for the same
    # items; the fetch crawls them AFTER the book slice into per-PID
    # sidecars, through the SRU interface (recordSchema dcndl) in
    # batches of BIB_BATCH PIDs per request (one CQL OR — a per-PID
    # OpenSearch call measured ~5.8 s each, 2026-10-19, so batching is
    # the difference between ~65 h and ~1.5 h of crawl). Paced by the
    # same DELAY, sliced (BIB_SLICE batches per sync), oldest PID first,
    # incremental (a PID with a sidecar never re-fetches) and resumable
    # through its own ledger (.ndl-bib.json): "missing" (the answer
    # links no record to the PID), "denied" (a 403/404 batch), and
    # "timeout-stuck" (the book crawl's timeout mold, per batch).
    #
    # Terms, read first-hand 2026-10-19:
    # - https://ndlsearch.ndl.go.jp/help/api/provider — メタデータ利用条件:
    #   国立国会図書館蔵書 (iss-ndl-opac, R100000002) "CC BY" (非営利 and
    #   営利 alike); 国立国会図書館デジタルコレクション（オープンデータ）
    #   (ndl-dl-open, R100000039) "CC BY" — every R100000039 PID sampled
    #   answers inside ndl-dl-open.
    # - https://ndlsearch.ndl.go.jp/help/api 17-4 (2): 「本APIを利用する
    #   サイトやアプリケーションには、NDLサーチのAPIを用いていることを
    #   明記してください。」 — the manifest license names it.
    # - 17-4 (1): 「APIをご利用いただく際は、多重アクセスが生じないよう
    #   ご対応をお願いいたします。」 — one request at a time, paced.
    # - https://www.ndl.go.jp/jp/help/data — 書誌データ: 「営利・非営利の
    #   目的や件数等にかかわらず、申請は必要ありません。」
    #
    # The join at parse: "ndc"/"ndlc" (codes verbatim, the ndc/ndlc
    # facets; NDC folds onto the kind axis in config/kind_map.yml),
    # "creators" (authority forms; life-years split conservatively, the
    # authority URI and reading kept) whose names join the author facet,
    # "publication_places" (publishers' locations verbatim — metadata
    # only, no place fold yet), and — ONLY where the census mints no
    # typed year — the record's W3CDTF issued years as the date
    # envelope, its raw labeled as the NDL Search record's claim (the
    # honkoku ndl_catalog precedent; the print's own date, so the
    # artifact class).
    class NdlKotenseki < Nabu::Adapter
      CENSUS_URL = "https://dl.ndl.go.jp/static/files/dataset/dataset_202602_k_internet.xlsx"
      CENSUS_XLSX = "dataset_202602_k_internet.xlsx"
      CENSUS_TSV = "census.tsv"
      BOOKS_DIRNAME = "books"
      LEDGER_FILE = ".ndl-crawl.json"
      BOOK_URL = "https://lab.ndl.go.jp/dl/api/book/fulltext-json/%s"
      RIGHTS_OK = "保護期間満了"
      URN_PREFIX = "urn:nabu:ndl-kotenseki:"
      LANGUAGE = "jpn"

      # The committed etiquette: ~1 req/s (NDL's own guidance, promised
      # back in the grant thread). Never lower.
      DELAY = 1.0
      # Books per sync — one slice of the multi-phase crawl (~7 min of
      # paced requests + the census download on the first run).
      SLICE = 400

      # Timeout-wedge fix (2026-10-11): attempts on ONE book whose GET times out, before it is
      # ledgered "timeout-stuck" and the slice moves on; the backoff
      # (seconds) doubles between attempts (5 s, then 10 s). The
      # transport's own read timeout (Net::HTTP's 60 s default) is kept:
      # both wedging PIDs answered in under 2 s when re-probed
      # 2026-10-11 — the hang was transient upstream, not a slow book.
      TIMEOUT_ATTEMPTS = 3
      TIMEOUT_BACKOFF = 5.0
      STUCK = "timeout-stuck"
      LEDGER_CLASSES = ["denied", "empty", STUCK].freeze
      # A transport failure that is a timeout (Faraday::TimeoutError /
      # Net::ReadTimeout / Net::OpenTimeout, wrapped by RedirectFollow).
      TIMEOUT_PATTERN = /transport error for .*(timeout|timed out|execution expired)/i

      # The dataset's unknown-date placeholder (censused 2026-09-29:
      # 5,388 rows carry the bare "1000") — mints no envelope.
      DATE_SENTINEL = "1000"

      # The bib join (see the header): sidecar dir, its ledger, PIDs per
      # SRU request, and requests per sync — 120 batches ≈ 6,000 PIDs ≈
      # 16 min at the measured ~7 s per batch answer + DELAY.
      BIB_DIRNAME = "bib"
      BIB_LEDGER_FILE = ".ndl-bib.json"
      BIB_BATCH = 50
      BIB_SLICE = 120
      BIB_LEDGER_CLASSES = ["missing", "denied", STUCK].freeze
      # Pages followed for one batch before the answer is distrusted.
      BIB_MAX_PAGES = 10

      MANIFEST = Nabu::SourceManifest.new(
        id: "ndl-kotenseki",
        name: "NDL 次世代デジタルライブラリー — 古典籍 OCR full text (bulk API)",
        license: "Copyright-expired classical materials (権利区分「保護期間満了」only); the " \
                 "bibliographic dataset is public domain (NDL open dataset page). Bulk API " \
                 "route confirmed by NDL Lab (by email, 2026-09-29); credit the National Diet " \
                 "Library digital collections, per-item permalink carried. Joined bibliographic " \
                 "records via the NDL Search (国立国会図書館サーチ) API — NDL metadata, CC BY 4.0",
        license_class: "open",
        upstream_url: "https://lab.ndl.go.jp/service/tsugidigi/",
        parser_family: "ndl-fulltext-json"
      )

      def self.manifest = MANIFEST

      def self.remote_probe_strategy = :http_zip

      def self.http_probe_targets
        [Nabu::Adapter::HttpProbeTarget.new(
          label: "census xlsx", zip_url: CENSUS_URL, metadata_url: nil,
          state_subdir: "", liveness_only: true
        )]
      end

      # census.tsv is derived beside the upstream xlsx at fetch, and the bib
      # sidecars are written per PID from the NDL Search answers (the
      # declared-materializations rule, 2026-09-03).
      def self.materialized_paths = [CENSUS_TSV, BIB_DIRNAME]

      def initialize(delay: DELAY, slice: SLICE, http: Nabu::ZipFetch.default_http,
                     timeout_backoff: TIMEOUT_BACKOFF, bib_batch: BIB_BATCH, bib_slice: BIB_SLICE)
        super()
        @delay = delay
        @slice = slice
        @timeout_backoff = timeout_backoff
        @bib_batch = bib_batch
        @bib_slice = bib_slice
        @http = http
        @requests = 0
      end

      # -- fetch -------------------------------------------------------------

      # +force+ is part of the fetch interface; nothing here ever
      # deletes, so there is no breaker to override.
      def fetch(workdir, progress: nil, force: false) # rubocop:disable Lint/UnusedMethodArgument
        FileUtils.mkdir_p(workdir)
        ensure_census!(workdir, progress)
        pids = census_pids(workdir)
        ledger = read_ledger(workdir)
        crawled, denied, stuck = crawl_slice!(workdir, pids, ledger, progress)
        held = held_pids(workdir)
        stuck_list = stuck.empty? ? "" : " (#{stuck.join(', ')})"
        notes = "crawl at #{held.size}/#{pids.size} book(s) " \
                "(+#{crawled} this sync, #{denied} newly refused, " \
                "#{stuck.size} stuck on timeout#{stuck_list}, " \
                "#{LEDGER_CLASSES.sum { |key| ledger[key].size }} ledgered)"
        bib = crawl_bib_slice!(workdir, progress: progress)
        notes += "; bib records at #{bib_held(workdir).size}/#{held.size} held book(s) " \
                 "(+#{bib[:fetched]} this sync, #{bib[:missing]} missing, #{bib[:denied]} refused, " \
                 "#{bib[:stuck]} stuck; #{bib[:batches]} batch(es))"
        progress&.call("#{notes}\n")
        Nabu::FetchReport.new(sha: crawl_sha(workdir, held, ledger), fetched_at: Time.now, notes: notes)
      end

      # -- discover ----------------------------------------------------------

      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        Dir.glob(File.join(workdir, BOOKS_DIRNAME, "*.json")).each do |path|
          pid = File.basename(path, ".json")
          yield Nabu::DocumentRef.new(
            source_id: MANIFEST.id, id: "#{URN_PREFIX}#{pid}",
            path: File.expand_path(path), metadata: { "pid" => pid }
          )
        end
      end

      def discovery_skips(workdir)
        strays = stray_files(workdir)
        Nabu::Adapter::DiscoverySkips.new(
          unrecognized: strays.size,
          notes: strays.map { |rel| "non-corpus file: #{rel}" }
        )
      end

      # -- parse -------------------------------------------------------------

      def parse(document_ref)
        pid = document_ref.metadata.fetch("pid")
        book = read_book(document_ref.path)
        workdir = File.dirname(document_ref.path, 2)
        bib = census_row(workdir, pid)
        record = bib_record(workdir, pid)
        document = Nabu::Document.new(
          urn: document_ref.id, language: LANGUAGE,
          canonical_path: document_ref.path,
          title: title_for(bib), metadata: metadata_for(pid, bib, book, record)
        )
        append_koma(document, document_ref, book)
        document
      end

      # census.tsv column → the dataset's own column header. シリーズタイトル
      # (series title — 11,119 of the 97,731 rows) and 容量・大きさ
      # (physical extent — 29,138) joined 2026-10-18; a held census.tsv
      # whose header predates a column re-derives from the held xlsx at
      # the next fetch (#ensure_census!). Still unread, declared: 版表示
      # (edition statement), 識別子（ISBN） (empty for these prints) and
      # the 公開範囲/権利区分注記 access columns (the 権利区分 filter is
      # applied at derivation).
      CENSUS_COLUMNS = {
        "title" => "タイトル", "volume" => "巻次又は部編番号", "author" => "著者",
        "publisher" => "出版者", "pub_date" => "出版日", "w3cdtf" => "出版日（W3CDTF）",
        "subject" => "件名", "collection" => "コレクション",
        "series" => "シリーズタイトル", "extent" => "容量・大きさ"
      }.freeze

      # The census.tsv header the current CENSUS_COLUMNS derive.
      CENSUS_HEADER = ["pid", *CENSUS_COLUMNS.keys].join("\t").freeze

      # A trailing role token on one 著者 part ("藤原基経 編", "春常 画",
      # "顕真 [著]" — the bracket is the cataloguer's supplied-role mark,
      # kept verbatim): a closed vocabulary of single role words. Tails
      # carrying "et al." or decree furniture (等奉敕撰, [ほか編], [等編])
      # and the rarer composites DELIBERATELY do not split — the name
      # stays whole rather than guessed apart.
      AUTHOR_ROLE = /\A\[?(?:編|画|畫|著|作|撰|校|輯|述|補|注|註|訳|譯|記|筆|録|書|集|纂|閲|訂|解|評|稿|誌|
                          編輯|編纂|著述|輯録|纂輯|口授|戯作|増補|作・画)\]?\z/x

      # One ||-separated 著者 part → {"name" => …, "role" => …}; a part
      # without a recognized trailing role token is the whole name.
      # Comma-joined co-authors ("小島好謙, 鈴木世孝 [編]") stay one name
      # string — the conservative split touches only the trailing token.
      def self.author_part(part)
        value = Normalize.nfc(part.to_s.strip)
        tokens = value.split(/[[:space:]]+/)
        return { "name" => value } unless tokens.size > 1 && tokens.last.match?(AUTHOR_ROLE)

        { "name" => value.sub(/[[:space:]]+#{Regexp.escape(tokens.last)}\z/, ""), "role" => tokens.last }
      end

      # The derived census.tsv as {pid => {column => value}} ({} when the
      # file is absent). Public: the honkoku catalog join reads the same
      # rows (Nabu::HonkokuNdlCatalog).
      def self.census_table(path)
        return {} unless File.file?(path)

        header = nil
        File.foreach(path).each_with_object({}) do |line, rows|
          values = line.chomp.split("\t", -1)
          (header = values) && next if header.nil?

          rows[values[0]] = header.zip(values).to_h
        end
      end

      # Every 4-digit year in the ||-separated W3CDTF value joins the
      # envelope; the bare unknown-date sentinel mints nothing; the
      # prose 出版日 is the raw.
      def self.date_envelope(bib)
        value = bib["w3cdtf"].to_s.strip
        return nil if value.empty? || value == DATE_SENTINEL

        years = value.scan(/\b(\d{4})\b/).flatten.map { |year| Integer(year, 10) }
        return nil if years.empty?

        raw = bib["pub_date"].to_s.strip
        { "not_before" => years.min, "not_after" => years.max,
          "raw" => raw.empty? ? value : Normalize.nfc(raw) }
      end

      # The bib record's envelope (NdlSearchBib.read fields): its W3CDTF
      # issued years, the raw labeled as the record's claim so no reader
      # takes it for the census. nil without a year.
      def self.bib_date_envelope(pid, record)
        years = Array(record["issued"])
        return nil if years.empty?

        { "not_before" => years.min, "not_after" => years.max,
          "raw" => "NDL Search record (pid #{pid}): #{record['date_prose'] || years.join(', ')}" }
      end

      # The census prose 出版日's nengō years (寛政4刊, 弘化4-嘉永6, 宝暦8序,安永9刊)
      # through the shared era table (config/eras.yml, owner-ruled
      # 2026-10-20) — the LAST rung, below both typed sources: census
      # 2026-10-20, 4,622 of the 56,484 census rows without a W3CDTF year
      # carry an era-year shape (天保 458 · 文政 428 · 文化 329 …). All era
      # years stated span the envelope (a preface and a print date
      # together); Chinese print-era homonyms (Ming 正徳 imprints sit in
      # this collection), the one-year eras, era spans without a year
      # number (慶長元和年間) and pre-Taika dates read nothing — declared.
      def self.era_date_envelope(bib, eras: Nabu::Eras.default)
        prose = Normalize.nfc(bib["pub_date"].to_s.strip)
        return nil if prose.empty? || eras.nil?

        eras.nengo_date(prose, basis: "census 出版日 nengō (config/eras.yml)")
      end

      private

      # -- fetch internals ---------------------------------------------------

      def ensure_census!(workdir, progress)
        xlsx = File.join(workdir, CENSUS_XLSX)
        tsv = File.join(workdir, CENSUS_TSV)
        unless File.file?(xlsx)
          progress&.call("Downloading the census bibliography (#{CENSUS_XLSX})…\n")
          downloaded = Nabu::UrlDownload.new.fetch(CENSUS_URL, dir: workdir)
          FileUtils.mv(downloaded, xlsx) unless downloaded == xlsx
        end
        derive_census!(xlsx, tsv) unless File.file?(tsv) && census_current?(tsv)
      end

      # A census.tsv derived before a CENSUS_COLUMNS addition lacks the
      # new columns — re-derived offline from the held xlsx (the xlsx is
      # the dated snapshot; the TSV is the declared materialization).
      def census_current?(tsv)
        File.open(tsv, &:gets).to_s.chomp == CENSUS_HEADER
      end

      def derive_census!(xlsx, tsv)
        rows = Nabu::Xlsx.rows(xlsx)
        header = rows.first
        indexes = CENSUS_COLUMNS.transform_values { |name| header.index(name) }
        rights = header.index("権利区分")
        File.open("#{tsv}.tmp", "w") do |file|
          file.puts(["pid", *CENSUS_COLUMNS.keys].join("\t"))
          rows[1..].each do |row|
            next unless row[rights].to_s.strip == RIGHTS_OK

            pid = row[0].to_s[%r{pid/(\d+)\z}, 1] or next
            file.puts([pid, *indexes.each_value.map { |i| row[i].to_s.tr("\t\n", "  ") }].join("\t"))
          end
        end
        File.rename("#{tsv}.tmp", tsv)
      end

      # OLDEST PID FIRST (ascending numeric): the dataset lists newest
      # first, and the newest additions' OCR text is not served yet —
      # the first live slice burned all 400 requests on a refusal
      # desert at the head (every 144xxxxx PID 403'd, ledgered). The
      # old PD scans are what the OCR corpus was built on; a future
      # re-census may deliberately clear the denied ledger when
      # upstream catches up (a phase decision, never automatic).
      def census_pids(workdir)
        File.foreach(File.join(workdir, CENSUS_TSV)).drop(1)
            .filter_map { |line| line[/\A\d+/] }
            .sort_by { |pid| Integer(pid, 10) }
      end

      # Returns [crawled, denied, stuck_pids].
      def crawl_slice!(workdir, pids, ledger, progress)
        skip = LEDGER_CLASSES.flat_map { |key| ledger.fetch(key, []) }.to_set
        crawled = 0
        denied = 0
        stuck = []
        pids.each do |pid|
          break if crawled + denied + stuck.size >= @slice
          next if skip.include?(pid) || File.file?(book_path(workdir, pid))

          case fetch_with_retries!(workdir, pid, progress)
          when :ok
            crawled += 1
          when :denied
            ledger["denied"] << pid
            denied += 1
          when :empty
            ledger["empty"] << pid
            denied += 1
          when :timeout
            (ledger[STUCK] ||= []) << pid
            stuck << pid
          end
          progress&.call("crawl: +#{crawled} book(s), #{denied} refused…\n") if ((crawled + denied) % 50).zero?
        end
        write_ledger!(workdir, ledger)
        [crawled, denied, stuck]
      end

      # The timeout-wedge fix: a timeout is retried in-slice with doubling backoff; only
      # TIMEOUT_ATTEMPTS consecutive timeouts give up (:timeout — the
      # caller ledgers the book "timeout-stuck").
      def fetch_with_retries!(workdir, pid, progress)
        TIMEOUT_ATTEMPTS.times do |attempt|
          outcome = fetch_book!(workdir, pid)
          return outcome unless outcome == :timeout
          break if attempt == TIMEOUT_ATTEMPTS - 1

          progress&.call("crawl: #{pid} timed out (attempt #{attempt + 1}/#{TIMEOUT_ATTEMPTS}), retrying…\n")
          backoff = @timeout_backoff * (2**attempt)
          sleep(backoff) if backoff.positive?
        end
        progress&.call("crawl: #{pid} timed out #{TIMEOUT_ATTEMPTS}× — ledgered #{STUCK}, moving on\n")
        :timeout
      end

      def fetch_book!(workdir, pid)
        sleep(@delay) if @delay.positive? && @requests.positive?
        @requests += 1
        response, = Nabu::RedirectFollow.get(
          format(BOOK_URL, pid), http: @http, error: Nabu::FetchError,
                                 headers: { "User-Agent" => Nabu::WikiFetch::USER_AGENT }
        )
        body = response.body.to_s
        return :denied unless body.lstrip.start_with?("{")

        payload = JSON.parse(body)
        return :empty if Array(payload["list"]).empty?

        target = book_path(workdir, pid)
        FileUtils.mkdir_p(File.dirname(target))
        File.binwrite("#{target}.tmp", body)
        File.rename("#{target}.tmp", target)
        :ok
      rescue JSON::ParserError
        :denied
      rescue Nabu::FetchError => e
        # A refused PID answers HTTP 403 "This PID is not allowed"
        # (censused at the first crawl — the spec's own caveat);
        # 404 is the same class. Ledgered, never retried. Anything
        # else (5xx, network) stays fatal — the crawl is resumable —
        # except a TIMEOUT, which the caller retries then ledgers (the timeout-wedge fix).
        return :timeout if e.message.match?(TIMEOUT_PATTERN)
        raise unless e.message.match?(/HTTP 40[34]\b/)

        :denied
      end

      def book_path(workdir, pid)
        File.join(workdir, BOOKS_DIRNAME, "#{pid}.json")
      end

      # -- the bib crawl -----------------------------------------------------

      # Up to @bib_slice SRU batches over the held PIDs that have neither a
      # sidecar nor a ledger entry, oldest PID first. Returns the tallies.
      def crawl_bib_slice!(workdir, progress:)
        ledger = read_bib_ledger(workdir)
        skip = BIB_LEDGER_CLASSES.flat_map { |key| ledger[key] }.to_set
        todo = held_pids(workdir).sort_by { |pid| Integer(pid, 10) }
                                 .reject { |pid| skip.include?(pid) || File.file?(bib_path(workdir, pid)) }
        counts = { fetched: 0, missing: 0, denied: 0, stuck: 0, batches: 0 }
        todo.each_slice(@bib_batch).first(@bib_slice).each do |batch|
          tally_bib_batch!(workdir, batch, ledger, counts, progress)
          counts[:batches] += 1
          next unless (counts[:batches] % 10).zero?

          progress&.call("bib: +#{counts[:fetched]} record(s), #{counts[:missing]} missing " \
                         "(#{counts[:batches]} batch(es))…\n")
        end
        counts
      ensure
        # A fatal answer mid-slice still keeps what the slice learned.
        write_bib_ledger!(workdir, ledger) if ledger
      end

      def tally_bib_batch!(workdir, batch, ledger, counts, progress)
        case (records = fetch_bib_with_retries!(batch, progress))
        when :denied
          ledger["denied"].concat(batch)
          counts[:denied] += batch.size
        when :timeout
          ledger[STUCK].concat(batch)
          counts[:stuck] += batch.size
        else
          batch.each do |pid|
            mine = NdlSearchBib.records_for(pid, records)
            if mine.empty?
              ledger["missing"] << pid
              counts[:missing] += 1
            else
              write_bib!(workdir, pid, mine)
              counts[:fetched] += 1
            end
          end
        end
      end

      # The book crawl's timeout mold, per batch: TIMEOUT_ATTEMPTS tries
      # with doubling backoff, then :timeout (the caller ledgers it stuck).
      def fetch_bib_with_retries!(batch, progress)
        TIMEOUT_ATTEMPTS.times do |attempt|
          outcome = fetch_bib_batch(batch)
          return outcome unless outcome == :timeout
          break if attempt == TIMEOUT_ATTEMPTS - 1

          progress&.call("bib: batch at #{batch.first} timed out (attempt #{attempt + 1}/#{TIMEOUT_ATTEMPTS})…\n")
          backoff = @timeout_backoff * (2**attempt)
          sleep(backoff) if backoff.positive?
        end
        :timeout
      end

      # Every record the batch's answer holds (paged through
      # nextRecordPosition), :denied on 403/404, :timeout on a timeout;
      # anything else stays fatal — the crawl is resumable.
      def fetch_bib_batch(batch)
        records = []
        start = 1
        BIB_MAX_PAGES.times do
          page = NdlSearchBib.page(bib_get(NdlSearchBib.query_url(batch, start: start)))
          records.concat(page.records)
          return records unless page.next_position && page.next_position > start && records.size < page.total

          start = page.next_position
        end
        raise Nabu::FetchError, "NDL Search SRU: batch at #{batch.first} still paging after #{BIB_MAX_PAGES} pages"
      rescue Nabu::FetchError => e
        return :timeout if e.message.match?(TIMEOUT_PATTERN)
        raise unless e.message.match?(/HTTP 40[34]\b/)

        :denied
      end

      def bib_get(url)
        sleep(@delay) if @delay.positive? && @requests.positive?
        @requests += 1
        response, = Nabu::RedirectFollow.get(url, http: @http, error: Nabu::FetchError,
                                                  headers: { "User-Agent" => Nabu::WikiFetch::USER_AGENT })
        response.body.to_s
      end

      def write_bib!(workdir, pid, records)
        target = bib_path(workdir, pid)
        FileUtils.mkdir_p(File.dirname(target))
        File.write("#{target}.tmp", NdlSearchBib.sidecar(pid, records))
        File.rename("#{target}.tmp", target)
      end

      def bib_path(workdir, pid)
        File.join(workdir, BIB_DIRNAME, "#{pid}.xml")
      end

      def bib_held(workdir)
        Dir.glob(File.join(workdir, BIB_DIRNAME, "*.xml")).map { |path| File.basename(path, ".xml") }.sort
      end

      def read_bib_ledger(workdir)
        blank = BIB_LEDGER_CLASSES.to_h { |key| [key, []] }
        path = File.join(workdir, BIB_LEDGER_FILE)
        return blank unless File.file?(path)

        blank.merge(JSON.parse(File.read(path)))
      rescue JSON::ParserError
        blank
      end

      def write_bib_ledger!(workdir, ledger)
        File.write(File.join(workdir, BIB_LEDGER_FILE),
                   JSON.pretty_generate(BIB_LEDGER_CLASSES.to_h { |key| [key, ledger.fetch(key, []).uniq.sort] }))
      end

      def held_pids(workdir)
        Dir.glob(File.join(workdir, BOOKS_DIRNAME, "*.json")).map { |path| File.basename(path, ".json") }.sort
      end

      # A ledger from before the timeout-wedge fix has no "timeout-stuck" class — every class
      # defaults to empty.
      def read_ledger(workdir)
        blank = LEDGER_CLASSES.to_h { |key| [key, []] }
        path = File.join(workdir, LEDGER_FILE)
        return blank unless File.file?(path)

        blank.merge(JSON.parse(File.read(path)))
      rescue JSON::ParserError
        blank
      end

      def write_ledger!(workdir, ledger)
        File.write(File.join(workdir, LEDGER_FILE),
                   JSON.pretty_generate(LEDGER_CLASSES.to_h { |key| [key, ledger.fetch(key, []).uniq.sort] }))
      end

      def crawl_sha(workdir, held, ledger)
        census = if File.file?(File.join(workdir,
                                         CENSUS_TSV))
                   Digest::SHA256.file(File.join(workdir, CENSUS_TSV)).hexdigest
                 else
                   ""
                 end
        # The stuck class joins the identity only when non-empty, so a
        # pre-fix crawl state keeps its sha (no re-parse churn).
        stuck = ledger.fetch(STUCK, []).sort
        parts = [census, held, ledger["denied"].sort, ledger["empty"].sort]
        parts << stuck unless stuck.empty?
        # The bib state joins likewise only once there is some (a crawl
        # from before the bib join keeps its identity).
        bib = bib_held(workdir)
        bib_ledger = read_bib_ledger(workdir)
        parts << ["bib", bib, BIB_LEDGER_CLASSES.map { |key| bib_ledger[key].sort }] unless
          bib.empty? && BIB_LEDGER_CLASSES.all? { |key| bib_ledger[key].empty? }
        Digest::SHA256.hexdigest(JSON.generate(parts))
      end

      # -- discovery/parse internals -----------------------------------------

      def stray_files(workdir)
        Dir.glob(File.join(workdir, "**", "*"))
           .select { |path| File.file?(path) }
           .reject { |path| path.include?("/#{ATTIC_DIRNAME}/") }
           .reject { |path| File.basename(path).start_with?(".") }
           .grep_v(%r{/#{BOOKS_DIRNAME}/\d+\.json\z})
           .grep_v(%r{/#{BIB_DIRNAME}/\d+\.xml\z})
           .reject { |path| [CENSUS_XLSX, CENSUS_TSV].include?(File.basename(path)) }
           .reject { |path| File.basename(path).downcase == "readme.md" }
           .map { |path| path.delete_prefix("#{workdir}/") }
           .sort
      end

      def read_book(path)
        book = JSON.parse(File.read(path))
        raise ParseError, "#{path}: no koma list in the book payload" unless book["list"].is_a?(Array)

        book
      rescue JSON::ParserError, Errno::ENOENT => e
        raise ParseError, "#{path}: unreadable book payload: #{e.message}"
      end

      # census.tsv row for +pid+, memoized whole (97k rows load once per
      # process — discover + parse must not re-read per document).
      def census_row(workdir, pid)
        @census ||= {}
        @census[workdir] ||= self.class.census_table(File.join(workdir, CENSUS_TSV))
        @census[workdir][pid] || {}
      end

      def title_for(bib)
        parts = [bib["title"], bib["volume"]].map { |value| value.to_s.strip }.reject(&:empty?)
        parts.empty? ? nil : Normalize.nfc(parts.join(" "))
      end

      # The bib sidecar's fields for +pid+ ({} when the crawl has not
      # reached it, or the answer linked no record).
      def bib_record(workdir, pid)
        path = bib_path(workdir, pid)
        File.file?(path) ? NdlSearchBib.read(path) : {}
      end

      def metadata_for(pid, bib, book, record)
        metadata = {
          "text_nature" => "machine-ocr",
          "permalink" => "https://dl.ndl.go.jp/pid/#{pid}",
          "koma_count" => Array(book["list"]).size
        }
        %w[author publisher pub_date collection series extent].each do |key|
          value = bib[key].to_s.strip
          metadata[key] = Normalize.nfc(value) unless value.empty?
        end
        parts = bib["author"].to_s.split("||").reject { |part| part.strip.empty? }
        metadata["authors"] = parts.map { |part| self.class.author_part(part) } unless parts.empty?
        %w[ndc ndlc creators publication_places].each { |key| metadata[key] = record[key] if record[key] }
        metadata["ndl_bib"] = { "records" => record["records"] } if record["records"]
        date = self.class.date_envelope(bib) || self.class.bib_date_envelope(pid, record) ||
               self.class.era_date_envelope(bib)
        metadata["date"] = date if date
        facets = facets_for(bib, record)
        metadata["facets"] = facets unless facets.empty?
        metadata
      end

      # Both 件名 and コレクション are ||-multi (the dataset's own
      # separator — the first slice fused a two-collection value);
      # シリーズタイトル is the series facet (no || value censused, split
      # all the same), and the 著者 parts' names facet as author (the
      # role split off — see .author_part), joined by the bib record's
      # authority-form creator names (life-years never in the value).
      # The record's NDC and NDLC codes facet verbatim.
      def facets_for(bib, record)
        facets = {}
        %w[subject collection series].each do |key|
          values = bib[key].to_s.split("||").map { |value| Normalize.nfc(value.strip) }.reject(&:empty?)
          facets[key] = { "values" => values } unless values.empty?
        end
        names = bib["author"].to_s.split("||").reject { |part| part.strip.empty? }
                                              .map { |part| self.class.author_part(part)["name"] }
        names = (names + Array(record["creators"]).map { |creator| creator["name"] }).uniq
        facets["author"] = { "values" => names } unless names.empty?
        %w[ndc ndlc].each { |key| facets[key] = { "values" => record[key] } if record[key] }
        facets
      end

      def append_koma(document, document_ref, book)
        sequence = 0
        book["list"].each do |koma|
          text = Normalize.nfc(koma["contents"].to_s.strip)
          next if text.empty?

          sequence += 1
          document << Nabu::Passage.new(
            urn: "#{document_ref.id}:#{koma['page']}", language: LANGUAGE,
            text: text, sequence: sequence,
            annotations: { "koma" => koma["page"].to_s }
          )
        end
      end
    end
  end
end

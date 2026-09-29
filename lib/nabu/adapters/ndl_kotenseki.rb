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

module Nabu
  module Adapters
    # ndl-kotenseki (P109-2, Q108 phase-1): the NDL 次世代デジタルライブ
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
    # The full mass is a multi-phase paced crawl by design (Q108 keeps
    # the remainder); each sync's report shows the crawl position.
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
    # == Axes (№R-70)
    #
    # 出版日（W3CDTF） mints the date envelope (every 4-digit year in
    # the ||-separated value; the bare sentinel "1000" — 5,388 rows,
    # censused 2026-09-29, the dataset's unknown-date placeholder —
    # mints nothing, declared); the prose 出版日 rides verbatim as raw.
    # 件名 (subjects, ||-separated) and コレクション facet.
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

      # The dataset's unknown-date placeholder (censused 2026-09-29:
      # 5,388 rows carry the bare "1000") — mints no envelope.
      DATE_SENTINEL = "1000"

      MANIFEST = Nabu::SourceManifest.new(
        id: "ndl-kotenseki",
        name: "NDL 次世代デジタルライブラリー — 古典籍 OCR full text (bulk API)",
        license: "Copyright-expired classical materials (権利区分「保護期間満了」only); the " \
                 "bibliographic dataset is public domain (NDL open dataset page). Bulk API " \
                 "route confirmed by NDL Lab (by email, 2026-09-29); credit the National Diet " \
                 "Library digital collections, per-item permalink carried",
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

      # census.tsv is derived beside the upstream xlsx at fetch (Q59-a).
      def self.materialized_paths = [CENSUS_TSV]

      def initialize(delay: DELAY, slice: SLICE, http: Nabu::ZipFetch.default_http)
        super()
        @delay = delay
        @slice = slice
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
        crawled, denied = crawl_slice!(workdir, pids, ledger, progress)
        held = held_pids(workdir)
        notes = "crawl at #{held.size}/#{pids.size} book(s) " \
                "(+#{crawled} this sync, #{denied} newly refused, " \
                "#{ledger['denied'].size + ledger['empty'].size} ledgered)"
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
        bib = census_row(File.dirname(document_ref.path, 2), pid)
        document = Nabu::Document.new(
          urn: document_ref.id, language: LANGUAGE,
          canonical_path: document_ref.path,
          title: title_for(bib), metadata: metadata_for(pid, bib, book)
        )
        append_koma(document, document_ref, book)
        document
      end

      # census.tsv column → the dataset's own column header.
      CENSUS_COLUMNS = {
        "title" => "タイトル", "volume" => "巻次又は部編番号", "author" => "著者",
        "publisher" => "出版者", "pub_date" => "出版日", "w3cdtf" => "出版日（W3CDTF）",
        "subject" => "件名", "collection" => "コレクション"
      }.freeze

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
        derive_census!(xlsx, tsv) unless File.file?(tsv)
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

      def crawl_slice!(workdir, pids, ledger, progress)
        skip = ledger["denied"].to_set | ledger["empty"].to_set
        crawled = 0
        denied = 0
        pids.each do |pid|
          break if crawled + denied >= @slice
          next if skip.include?(pid) || File.file?(book_path(workdir, pid))

          case fetch_book!(workdir, pid)
          when :ok
            crawled += 1
          when :denied
            ledger["denied"] << pid
            denied += 1
          when :empty
            ledger["empty"] << pid
            denied += 1
          end
          progress&.call("crawl: +#{crawled} book(s), #{denied} refused…\n") if ((crawled + denied) % 50).zero?
        end
        write_ledger!(workdir, ledger)
        [crawled, denied]
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
        # else (5xx, network) stays fatal — the crawl is resumable.
        raise unless e.message.match?(/HTTP 40[34]\b/)

        :denied
      end

      def book_path(workdir, pid)
        File.join(workdir, BOOKS_DIRNAME, "#{pid}.json")
      end

      def held_pids(workdir)
        Dir.glob(File.join(workdir, BOOKS_DIRNAME, "*.json")).map { |path| File.basename(path, ".json") }.sort
      end

      def read_ledger(workdir)
        path = File.join(workdir, LEDGER_FILE)
        return { "denied" => [], "empty" => [] } unless File.file?(path)

        JSON.parse(File.read(path))
      rescue JSON::ParserError
        { "denied" => [], "empty" => [] }
      end

      def write_ledger!(workdir, ledger)
        File.write(File.join(workdir, LEDGER_FILE),
                   JSON.pretty_generate({ "denied" => ledger["denied"].uniq.sort,
                                          "empty" => ledger["empty"].uniq.sort }))
      end

      def crawl_sha(workdir, held, ledger)
        census = if File.file?(File.join(workdir,
                                         CENSUS_TSV))
                   Digest::SHA256.file(File.join(workdir, CENSUS_TSV)).hexdigest
                 else
                   ""
                 end
        Digest::SHA256.hexdigest(JSON.generate([census, held, ledger["denied"].sort, ledger["empty"].sort]))
      end

      # -- discovery/parse internals -----------------------------------------

      def stray_files(workdir)
        Dir.glob(File.join(workdir, "**", "*"))
           .select { |path| File.file?(path) }
           .reject { |path| path.include?("/#{ATTIC_DIRNAME}/") }
           .reject { |path| File.basename(path).start_with?(".") }
           .grep_v(%r{/#{BOOKS_DIRNAME}/\d+\.json\z})
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
        @census[workdir] ||= begin
          path = File.join(workdir, CENSUS_TSV)
          if File.file?(path)
            header = nil
            File.foreach(path).each_with_object({}) do |line, rows|
              values = line.chomp.split("\t", -1)
              (header = values) && next if header.nil?

              rows[values[0]] = header.zip(values).to_h
            end
          else
            {}
          end
        end
        @census[workdir][pid] || {}
      end

      def title_for(bib)
        parts = [bib["title"], bib["volume"]].map { |value| value.to_s.strip }.reject(&:empty?)
        parts.empty? ? nil : Normalize.nfc(parts.join(" "))
      end

      def metadata_for(pid, bib, book)
        metadata = {
          "text_nature" => "machine-ocr",
          "permalink" => "https://dl.ndl.go.jp/pid/#{pid}",
          "koma_count" => Array(book["list"]).size
        }
        %w[author publisher pub_date collection].each do |key|
          value = bib[key].to_s.strip
          metadata[key] = Normalize.nfc(value) unless value.empty?
        end
        date = date_envelope(bib)
        metadata["date"] = date if date
        facets = facets_for(bib)
        metadata["facets"] = facets unless facets.empty?
        metadata
      end

      # Every 4-digit year in the ||-separated W3CDTF value joins the
      # envelope; the bare unknown-date sentinel mints nothing; the
      # prose 出版日 is the raw.
      def date_envelope(bib)
        value = bib["w3cdtf"].to_s.strip
        return nil if value.empty? || value == DATE_SENTINEL

        years = value.scan(/\b(\d{4})\b/).flatten.map { |year| Integer(year, 10) }
        return nil if years.empty?

        raw = bib["pub_date"].to_s.strip
        { "not_before" => years.min, "not_after" => years.max,
          "raw" => raw.empty? ? value : Normalize.nfc(raw) }
      end

      # Both 件名 and コレクション are ||-multi (the dataset's own
      # separator — the first slice fused a two-collection value).
      def facets_for(bib)
        facets = {}
        %w[subject collection].each do |key|
          values = bib[key].to_s.split("||").map { |value| Normalize.nfc(value.strip) }.reject(&:empty?)
          facets[key] = { "values" => values } unless values.empty?
        end
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

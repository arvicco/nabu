# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"

require_relative "../zip_fetch"
require_relative "../redirect_follow"
require_relative "../normalize"

module Nabu
  module Adapters
    # damos: DĀMOS — the Database of Mycenaean at Oslo (Federico Aurora,
    # University of Oslo; damos.hf.uio.no), the complete Linear B
    # corpus: the Knossos, Pylos, Thebes, Mycenae, Tiryns, Khania …
    # tablets, sealings and labels plus the inscribed stirrup jars.
    # Footer, verbatim (re-read 2026-10-18): "Content: CC BY-NC-SA 4.0"
    # (software GPL-3.0) → license_class nc.
    #
    # == The resumable crawl (the ndl-kotenseki mold)
    #
    # The census: ONE POST to /ajaxgetfilter (empty body) answers the
    # site's whole filter state as JSON (~967 KB) — "collections" (29,
    # each with its item count) and "tables", one row per tablet
    # DESIGNATION: 7,687 rows over 5,932 unique item ids at the
    # 2026-10-18 census (the 1,755 extra rows are the joined fragments'
    # own numbers pointing at their host item, "!KN 31 = 5797 >+ KN 1
    # Fp(1)"). The unique ids must equal the summed collection counts —
    # the truncation defense; zero ids aborts. The listing is kept
    # under map/ verbatim.
    #
    # The crawl: GET /ajaxitem/<id>/ per id, ascending, up to SLICE per
    # sync, resume at the file grain (items/<id>.json on disk is done).
    # Ledgered in .damos-crawl.json and never retried: 403/404 or a
    # non-JSON answer ("denied"), a record with no transliteration
    # ("empty"), an item that times out TIMEOUT_ATTEMPTS times
    # ("timeout-stuck"), and an item that answers 5xx as often
    # ("server-error" — upstream answers a missing id with HTTP 500,
    # probed 2026-10-18, so a lone persistent 500 is a bad id, not an
    # outage). OUTAGE_RUN consecutive failures ARE an outage: the sync
    # aborts without ledgering the run and the next one resumes there.
    #
    # == Documents
    #
    # One document per item (urn:nabu:damos:<id>, the heading "KN B 822
    # (-)" as title), one passage per content LINE — upstream's own line
    # labels (".1a", ".2", ".A") are the passage ids. A side marker on a
    # line of its own ("v." verso, "lat. inf." lower edge, the sealing
    # faces α/β/γ) prefixes the following labels (v.1 — the verso
    # restarts its numbering); an unlabeled line (margin text, "inf.
    # mut.", "reliqua pars sine regulis", a one-line vase inscription)
    # is kept as its own passage u1, u2 … — nothing is dropped. The
    # transliteration rides VERBATIM (Leiden-flavored Mycenaean
    # conventions, logograms, vac., the layout spacing that places a
    # line on the tablet), NFC-composed at the boundary (gmy is not on
    # the NFC-exempt list: d + U+0323 → ḍ).
    #
    # == Axes (aggressive mining)
    #
    # The site (the collection; a "Vases - Thebes" collection places at
    # Thebes — the grouping word is not a toponym) + find-area +
    # find-spot mint the "place" hash; the jar's clay "Provenance"
    # (West Crete α) is NOT the findspot and rides as metadata. The
    # chronology (Aegean ceramic phases, "LM IIIA2 or LM IIIB", "LH
    # IIIB2/LH IIIC") rides as the "period" label through MetadataDates
    # :period_label, banded by the ruled Aegean rows of
    # config/period_bands.yml (all 27 held labels covered). The find-
    # context dating rides as "context_chronology". Series(+subseries),
    # set, hand, collection and object type facet; museum location,
    # inventory, find year, Trismegistos id, bibliography, editorial
    # notes and the permalink ride as metadata. Upstream's "-" is its
    # no-value sentinel and mints nothing.
    class Damos < Nabu::Adapter
      BASE_URL = "https://damos.hf.uio.no"
      LISTING_URL = "#{BASE_URL}/ajaxgetfilter".freeze
      ITEM_URL = "#{BASE_URL}/ajaxitem/%s/".freeze
      MAP_DIRNAME = "map"
      LISTING_FILE = "ajaxgetfilter.json"
      ITEMS_DIRNAME = "items"
      LEDGER_FILE = ".damos-crawl.json"
      URN_PREFIX = "urn:nabu:damos:"
      LANGUAGE = "gmy"

      # const: crawl politeness pause, not a corpus claim (~1 req/s).
      DELAY = 1.0
      # Items per sync: ~25 min of paced requests — 5,932 ids crawl in
      # four slices.
      SLICE = 1_500

      # Attempts on ONE item that times out or answers 5xx before it is
      # ledgered; the backoff (seconds) doubles between attempts.
      TIMEOUT_ATTEMPTS = 3
      TIMEOUT_BACKOFF = 5.0
      # Consecutive failed ids that mean upstream is down, not the ids.
      OUTAGE_RUN = 3
      STUCK = "timeout-stuck"
      SERVER_ERROR = "server-error"
      LEDGER_CLASSES = ["denied", "empty", STUCK, SERVER_ERROR].freeze
      FAILURE_CLASS = { timeout: STUCK, server_error: SERVER_ERROR }.freeze
      TIMEOUT_PATTERN = /transport error for .*(timeout|timed out|execution expired)/i

      # Upstream's no-value sentinel in every metadata field.
      NONE = "-"
      VASES = /\AVases - /

      # A line that is only a side marker (the censused shapes: verso,
      # with or without its orientation arrow; the edges; sealing faces).
      SIDE_MARKER = /\A(?:v\.|r\.|lat\.\s*(?:inf|sup|dex|sin)\.|[α-ω])\s*[↓↑]?\z/
      LINE_LABEL = /\A\.([0-9A-Za-z]+)(?:\s+(.*))?\z/

      MANIFEST = Nabu::SourceManifest.new(
        id: "damos",
        name: "DĀMOS — Database of Mycenaean at Oslo (the Linear B corpus)",
        license: "Site footer, verbatim: \"Content: CC BY-NC-SA 4.0\" (software GPL-3.0); " \
                 "credit DĀMOS, University of Oslo, per-item permalink carried",
        license_class: "nc",
        upstream_url: BASE_URL,
        parser_family: "damos-json"
      )

      def self.manifest = MANIFEST

      def self.remote_probe_strategy = :http_zip

      # The listing is POST-only; the site root answers liveness.
      def self.http_probe_targets
        [Nabu::Adapter::HttpProbeTarget.new(
          label: "damos site", zip_url: "#{BASE_URL}/", metadata_url: nil,
          state_subdir: "", liveness_only: true
        )]
      end

      def initialize(delay: DELAY, slice: SLICE, http: Nabu::ZipFetch.default_http,
                     timeout_backoff: TIMEOUT_BACKOFF)
        super()
        @delay = delay
        @slice = slice
        @timeout_backoff = timeout_backoff
        @http = http
        @requests = 0
      end

      # -- fetch -------------------------------------------------------------

      # +force+ is part of the fetch interface; nothing here ever
      # deletes, so there is no breaker to override.
      def fetch(workdir, progress: nil, force: false) # rubocop:disable Lint/UnusedMethodArgument
        FileUtils.mkdir_p(workdir)
        body = post_listing!(progress)
        ids = listing_ids(body)
        write_listing!(workdir, body)
        ledger = read_ledger(workdir)
        crawled, refused, stuck = crawl_slice!(workdir, ids, ledger, progress)
        held = held_ids(workdir)
        stuck_list = stuck.empty? ? "" : " (#{stuck.join(', ')})"
        notes = "crawl at #{held.size}/#{ids.size} item(s) " \
                "(+#{crawled} this sync, #{refused} newly refused, " \
                "#{stuck.size} stuck on timeout/server error#{stuck_list}, " \
                "#{LEDGER_CLASSES.sum { |key| ledger[key].size }} ledgered)"
        progress&.call("#{notes}\n")
        Nabu::FetchReport.new(sha: crawl_sha(workdir, held, ledger), fetched_at: Time.now, notes: notes)
      end

      # -- discover ----------------------------------------------------------

      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        Dir.glob(File.join(workdir, ITEMS_DIRNAME, "*.json")).each do |path|
          id = File.basename(path, ".json")
          yield Nabu::DocumentRef.new(
            source_id: MANIFEST.id, id: "#{URN_PREFIX}#{id}",
            path: File.expand_path(path), metadata: { "id" => id }
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
        payload = read_item(document_ref.path)
        item = payload["item"]
        document = Nabu::Document.new(
          urn: document_ref.id, language: LANGUAGE,
          canonical_path: document_ref.path,
          title: clean(item["heading"]),
          metadata: metadata_for(item, payload["meta"] || {}, payload["bibliography"])
        )
        content_lines(item["content"].to_s).each_with_index do |line, index|
          annotations = { "line" => line[:unlabeled] ? nil : ".#{line[:label]}",
                          "side" => line[:side], "unlabeled" => line[:unlabeled] ? "true" : nil }.compact
          document << Nabu::Passage.new(
            urn: "#{document_ref.id}:#{line[:id]}", language: LANGUAGE,
            text: line[:text], sequence: index + 1, annotations: annotations
          )
        end
        document
      end

      private

      # -- fetch internals ---------------------------------------------------

      def post_listing!(progress)
        progress&.call("DĀMOS listing (POST ajaxgetfilter)…\n")
        response = @http.post(LISTING_URL, "", { "User-Agent" => Nabu::WikiFetch::USER_AGENT })
        raise FetchError, "damos listing POST returned HTTP #{response.status}" unless response.status == 200

        response.body.to_s.dup.force_encoding(Encoding::UTF_8)
      rescue Faraday::Error => e
        raise FetchError, "damos listing POST failed: #{e.message}"
      end

      # Only a listing that passed the truncation defense replaces map/.
      def write_listing!(workdir, body)
        target = File.join(workdir, MAP_DIRNAME, LISTING_FILE)
        FileUtils.mkdir_p(File.dirname(target))
        File.binwrite("#{target}.tmp", body)
        File.rename("#{target}.tmp", target)
      end

      # Unique item ids, ascending — alias rows (a joined fragment's own
      # designation) share their host's id and collapse.
      def listing_ids(body)
        listing = JSON.parse(body)
        ids = Array(listing["tables"]).map { |row| row["id"] }.compact.uniq.sort
        raise FetchError, "damos listing carries no item ids — upstream shape changed" if ids.empty?

        expected = Array(listing["collections"]).sum { |coll| Integer(coll["count"]) }
        unless ids.size == expected
          raise FetchError, "damos listing is TRUNCATED: the collections count #{expected} item(s) " \
                            "but the tables carry #{ids.size} unique id(s) — retry, and check " \
                            "#{LISTING_URL} by hand"
        end
        ids.map(&:to_s)
      rescue JSON::ParserError => e
        raise FetchError, "damos listing is not JSON: #{e.message}"
      end

      # Returns [crawled, refused, stuck_ids]. Failed ids (timeout/5xx
      # after retries) wait in +pending+ until a later id answers — a run
      # of OUTAGE_RUN of them aborts the slice unledgered.
      def crawl_slice!(workdir, ids, ledger, progress)
        skip = LEDGER_CLASSES.flat_map { |key| ledger.fetch(key, []) }.to_set
        crawled = 0
        refused = 0
        stuck = []
        pending = []
        ids.each do |id|
          break if crawled + refused + stuck.size + pending.size >= @slice
          next if skip.include?(id) || File.file?(item_path(workdir, id))

          outcome = fetch_with_retries!(workdir, id, progress)
          if FAILURE_CLASS.key?(outcome)
            pending << [id, FAILURE_CLASS.fetch(outcome)]
            abort_outage!(workdir, ledger, pending) if pending.size >= OUTAGE_RUN
            next
          end

          stuck.concat(flush_pending!(ledger, pending))
          case outcome
          when :ok then crawled += 1
          when :denied, :empty
            ledger[outcome.to_s] << id
            refused += 1
          end
          progress&.call("crawl: +#{crawled} item(s), #{refused} refused…\n") if ((crawled + refused) % 100).zero?
        end
        stuck.concat(flush_pending!(ledger, pending))
        write_ledger!(workdir, ledger)
        [crawled, refused, stuck]
      end

      def flush_pending!(ledger, pending)
        flushed = pending.map do |id, klass|
          (ledger[klass] ||= []) << id
          id
        end
        pending.clear
        flushed
      end

      def abort_outage!(workdir, ledger, pending)
        write_ledger!(workdir, ledger)
        raise FetchError, "damos crawl aborted — upstream outage: #{pending.size} consecutive item(s) " \
                          "failed (#{pending.map(&:first).join(', ')}); nothing ledgered for the run, " \
                          "the next sync resumes here"
      end

      # A timeout or 5xx is retried in-slice with doubling backoff; only
      # TIMEOUT_ATTEMPTS consecutive failures give up.
      def fetch_with_retries!(workdir, id, progress)
        outcome = nil
        TIMEOUT_ATTEMPTS.times do |attempt|
          outcome = fetch_item!(workdir, id)
          return outcome unless FAILURE_CLASS.key?(outcome)
          break if attempt == TIMEOUT_ATTEMPTS - 1

          progress&.call("crawl: #{id} #{outcome} (attempt #{attempt + 1}/#{TIMEOUT_ATTEMPTS}), retrying…\n")
          backoff = @timeout_backoff * (2**attempt)
          sleep(backoff) if backoff.positive?
        end
        progress&.call("crawl: #{id} #{outcome} #{TIMEOUT_ATTEMPTS}× — held back\n")
        outcome
      end

      def fetch_item!(workdir, id)
        sleep(@delay) if @delay.positive? && @requests.positive?
        @requests += 1
        response, = Nabu::RedirectFollow.get(
          format(ITEM_URL, id), http: @http, error: Nabu::FetchError,
                                headers: { "User-Agent" => Nabu::WikiFetch::USER_AGENT }
        )
        body = response.body.to_s
        return :denied unless body.lstrip.start_with?("{")

        item = JSON.parse(body)["item"]
        return :denied unless item.is_a?(Hash)
        return :empty if item["content"].to_s.strip.empty?

        target = item_path(workdir, id)
        FileUtils.mkdir_p(File.dirname(target))
        File.binwrite("#{target}.tmp", body)
        File.rename("#{target}.tmp", target)
        :ok
      rescue JSON::ParserError
        :denied
      rescue Nabu::FetchError => e
        return :timeout if e.message.match?(TIMEOUT_PATTERN)
        return :server_error if e.message.match?(/HTTP 5\d\d\b/)
        raise unless e.message.match?(/HTTP 40[34]\b/)

        :denied
      end

      def item_path(workdir, id)
        File.join(workdir, ITEMS_DIRNAME, "#{id}.json")
      end

      def held_ids(workdir)
        Dir.glob(File.join(workdir, ITEMS_DIRNAME, "*.json")).map { |path| File.basename(path, ".json") }.sort
      end

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
        listing = File.join(workdir, MAP_DIRNAME, LISTING_FILE)
        census = File.file?(listing) ? Digest::SHA256.file(listing).hexdigest : ""
        classes = LEDGER_CLASSES.map { |key| ledger.fetch(key, []).sort }
        Digest::SHA256.hexdigest(JSON.generate([census, held, *classes]))
      end

      # -- discovery/parse internals -----------------------------------------

      def stray_files(workdir)
        Dir.glob(File.join(workdir, "**", "*"))
           .select { |path| File.file?(path) }
           .reject { |path| path.include?("/#{ATTIC_DIRNAME}/") }
           .reject { |path| File.basename(path).start_with?(".") }
           .grep_v(%r{/#{ITEMS_DIRNAME}/\d+\.json\z})
           .grep_v(%r{/#{MAP_DIRNAME}/#{Regexp.escape(LISTING_FILE)}\z})
           .reject { |path| File.basename(path).downcase == "readme.md" }
           .map { |path| path.delete_prefix("#{workdir}/") }
           .sort
      end

      def read_item(path)
        payload = JSON.parse(File.read(path))
        raise ParseError, "#{path}: no item record in the payload" unless payload["item"].is_a?(Hash)

        payload
      rescue JSON::ParserError, Errno::ENOENT => e
        raise ParseError, "#{path}: unreadable item payload: #{e.message}"
      end

      # The content's lines → [{id:, label:, side:, text:, unlabeled:}].
      # Blank lines and label-only lines mint nothing; a repeated id gets
      # a "~n" suffix (never silently merged).
      def content_lines(content)
        side = nil
        unlabeled = 0
        seen = Hash.new(0)
        content.each_line.filter_map do |raw|
          stripped = raw.strip
          next if stripped.empty?

          if stripped.match?(SIDE_MARKER)
            side = stripped
            next
          end

          if (match = LINE_LABEL.match(stripped))
            label = match[1]
            text = match[2].to_s.strip
            next if text.empty?

            flag = false
          else
            unlabeled += 1
            label = "u#{unlabeled}"
            text = stripped
            flag = true
          end
          id = side ? "#{side_slug(side)}.#{label}" : label
          seen[id] += 1
          id = "#{id}~#{seen[id]}" if seen[id] > 1
          { id: id, label: label, side: side, text: Normalize.nfc(text), unlabeled: flag }
        end
      end

      def side_slug(marker)
        marker.delete(".↓↑").strip.gsub(/\s+/, "-")
      end

      # A metadata LABEL (never passage text): upstream sprinkles U+00A0
      # into some labels ("LH IIIA2-LH IIIB" on Thebes contexts, 2
      # chronology and 23 find-area filter values, censused 2026-10-18 —
      # the listing even counts "LM IIIB1" twice), so whitespace folds to
      # one space and the same label stays one label.
      def clean(value)
        text = value.to_s.gsub(/[[:space:]]+/, " ").strip
        text.empty? || text == NONE ? nil : Normalize.nfc(text)
      end

      def metadata_for(item, meta, bibliography)
        site = clean(meta["Site"])
        metadata = {
          "site" => site,
          "place" => place_for(site, meta),
          "period" => clean(meta["Chronology"] || item["chronology1"]),
          "context_chronology" => clean(meta["Context"]),
          "provenance" => clean(meta["Provenance"]),
          "object" => clean(item["object"]),
          "material" => clean(item["material"]),
          "find_area_name" => clean(item["find_area_name"]),
          "find_year" => clean(meta["Find Year"]),
          "location" => clean(meta["Location"]),
          "inventory" => clean(meta["Inv. no."]),
          "joins" => clean(meta["Joins"]),
          "tm" => clean(meta["Trismegistos"]),
          "permalink" => clean(item["permalink1"]),
          "notes" => clean(item["notes"])
        }
        metadata["lost"] = true if item["lost"].to_i.negative? || meta["Preserved"] == "No"
        bib = Array(bibliography).filter_map { |entry| clean(entry) }
        metadata["bibliography"] = bib unless bib.empty?
        metadata["facets"] = facets_for(item, meta, site)
        metadata.compact
      end

      def place_for(site, meta)
        return nil if site.nil?

        { "ancient" => site.sub(VASES, ""), "find_area" => clean(meta["Find-area"]),
          "find_spot" => clean(meta["Find-spot"]) }.compact
      end

      # Series + subseries is the Linear B series prefix ("Tn", "Ak");
      # a "-" subseries leaves the bare series letter.
      def facets_for(item, meta, site)
        series = clean(meta["Series"])
        subseries = clean(meta["Subseries"])
        values = {
          "series" => series && "#{series}#{subseries}",
          "set" => clean(meta["Set"]),
          "hand" => clean(meta["Hand"]),
          "collection" => site,
          "object" => clean(item["object"])
        }
        values.compact.transform_values { |value| { "values" => [value] } }
      end
    end
  end
end

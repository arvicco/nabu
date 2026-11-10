# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"

require_relative "../zip_fetch"
require_relative "../redirect_follow"
require_relative "../normalize"
require_relative "../paced_crawl"

module Nabu
  module Adapters
    # damos: DĀMOS — the Database of Mycenaean at Oslo (Federico Aurora,
    # University of Oslo; damos.hf.uio.no), the complete Linear B
    # corpus: the Knossos, Pylos, Thebes, Mycenae, Tiryns, Khania …
    # tablets, sealings and labels plus the inscribed stirrup jars.
    # Footer, verbatim (re-read 2026-10-18): "Content: CC BY-NC-SA 4.0"
    # (software GPL-3.0) → license_class nc.
    #
    # == The resumable crawl (the paced-crawl rail)
    #
    # The census: ONE POST to /ajaxgetfilter (empty body) answers the
    # site's whole filter state as JSON (~967 KB) — "collections" (29,
    # each with its item count) and "tables", one row per tablet
    # DESIGNATION: 7,687 rows over 5,932 unique item ids at the
    # 2026-10-18 census (the 1,755 extra rows are the joined fragments'
    # own numbers pointing at their host item, "!KN 31 = 5797 >+ KN 1
    # Fp(1)"). The unique ids must equal the summed collection counts —
    # the truncation defense; zero ids aborts. The listing is kept
    # under map/ verbatim, and only a listing that passed the defense
    # replaces it — the held listing IS the crawl's universe.
    #
    # The crawl rides the paced-crawl rail (Nabu::PacedCrawl,
    # architecture §19; ITEM_CRAWL is the lane): GET /ajaxitem/<id>/ per
    # id, ascending, up to SLICE per sync, held = items/<id>.json on
    # disk. The engine owns selection, the one slice budget, pacing, the
    # timeout policy, the ledger and the slice report the fetch notes
    # carry. Ledgered in .damos-crawl.json (flat class arrays — the
    # pre-engine shape reads and writes back unchanged, the engine's
    # last_slice beside it) and never retried: 403/404 or a non-JSON
    # answer ("denied"), a record with no transliteration ("empty"), an
    # item that times out TIMEOUT_ATTEMPTS times ("timeout-stuck"), and
    # an item that answers 5xx as often ("server-error", a subclass of
    # the timeout class, retried with the same backoff — upstream
    # answers a missing id with HTTP 500, probed 2026-10-18, so a lone
    # persistent 500 is a bad id, not an outage). Any other failure
    # stays fatal (the crawl is resumable).
    #
    # THE OUTAGE BREAKER is the engine's (outage_statuses [:timeout],
    # outage_run OUTAGE_RUN): a timeout or 5xx answer is STAGED off the
    # ledger and commits only when a later id answers otherwise;
    # OUTAGE_RUN consecutive staged answers abort the slice with the run
    # dropped unledgered (the next sync re-asks it), and the sync then
    # raises FetchError, as the hand-rolled breaker did. ENGINE LAW,
    # accepted: a staged run shorter than OUTAGE_RUN still open when the
    # slice ends stays UNLEDGERED too and is re-asked next slice (the
    # hand-rolled crawl committed it at slice end). The consequence:
    # genuine failures at the very END of the cone are re-asked every
    # run, the crawl never reports cone-exhausted, and a chained run
    # (rake crawl:chain) stops loudly on the declared zero-yield budget
    # instead — a human read of those ids, never a silent commit.
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
      # The item lane's declared schedule (read by the phase slate). The
      # cone completed 2026-10-18 (four slices); a phase's slices now
      # answer cone-exhausted until the listing grows. Undeclared before
      # the rail, so the citizens' default: per phase, three slices, and a
      # chained run stops after three consecutive zero-yield slices.
      ITEM_CRAWL = Nabu::PacedCrawl::Spec.new(
        name: "items", ledger_file: LEDGER_FILE,
        classes: { denied: "denied", empty: "empty", timeout: STUCK },
        subclasses: { timeout: [SERVER_ERROR] },
        delay: DELAY, slice: SLICE, timeout_attempts: TIMEOUT_ATTEMPTS, timeout_backoff: TIMEOUT_BACKOFF,
        outage_statuses: [:timeout], outage_run: OUTAGE_RUN,
        schedule: Nabu::PacedCrawl::Schedule.new(cadence: :per_phase, slices_per_phase: 3, stop_after_zero_slices: 3)
      )
      # The ledger classes, in the on-disk order the crawl identity hashes.
      LEDGER_CLASSES = ITEM_CRAWL.class_names.freeze
      # The answers an item GET takes as terminal, accepted so their bodies
      # ride as evidence: 403/404 (denied) and any 5xx (server-error).
      # Every other non-200 stays fatal.
      DENIED_STATUSES = [403, 404].freeze
      SERVER_ERRORS = (500..599).to_a.freeze
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
        @listing_ids = {}
      end

      # -- fetch -------------------------------------------------------------

      # +force+ is part of the fetch interface; nothing here ever
      # deletes, so there is no breaker to override.
      def fetch(workdir, progress: nil, force: false) # rubocop:disable Lint/UnusedMethodArgument
        FileUtils.mkdir_p(workdir)
        body = post_listing!(progress)
        listing_ids(body) # the truncation defense, before the listing replaces map/
        write_listing!(workdir, body)
        crawl = item_crawl(workdir, progress: progress)
        report = crawl.slice!
        lines = report.lines
        lines.each { |line| progress&.call("#{line}\n") }
        abort_outage!(report) if report.outage_aborted?
        Nabu::FetchReport.new(sha: crawl_sha(workdir, held_ids(workdir), crawl.ledger), fetched_at: Time.now,
                              notes: lines.join("; "))
      end

      # The chain runner's seam (rake crawl:chain): the one paced lane.
      def paced_crawls(workdir, progress: nil)
        { ITEM_CRAWL.name => item_crawl(workdir, progress: progress) }
      end

      # The item lane's engine over +workdir+ (ITEM_CRAWL retuned by this
      # instance's knobs): the held listing's ids ascending, held =
      # items/<id>.json on disk, one paced GET per id. Public so an offline
      # surface can #diagnose the crawl without crawling.
      def item_crawl(workdir, progress: nil)
        Nabu::PacedCrawl::Engine.new(
          spec: ITEM_CRAWL.with(delay: @delay, slice: @slice, timeout_backoff: @timeout_backoff),
          dir: workdir, progress: progress,
          universe: -> { held_listing_ids(workdir) },
          held: ->(id) { File.file?(item_path(workdir, id)) },
          fetch_one: ->(id) { fetch_item!(workdir, id) }
        )
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
        target = listing_path(workdir)
        FileUtils.mkdir_p(File.dirname(target))
        File.binwrite("#{target}.tmp", body)
        File.rename("#{target}.tmp", target)
        @listing_ids.delete(workdir)
      end

      def listing_path(workdir) = File.join(workdir, MAP_DIRNAME, LISTING_FILE)

      # The crawl's universe: the held listing's ids (none before the first
      # listing lands), parsed once per listing write — the engine asks for
      # the universe on every scan.
      def held_listing_ids(workdir)
        @listing_ids[workdir] ||= begin
          path = listing_path(workdir)
          File.file?(path) ? listing_ids(File.read(path, encoding: Encoding::UTF_8)) : []
        end
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

      # The sync aborts on a tripped breaker, as the hand-rolled crawl did
      # (the ledger is already written; the run stays selectable).
      def abort_outage!(report)
        ids = report.outage[:ids]
        raise FetchError, "damos crawl aborted — upstream outage: #{ids.size} consecutive item(s) " \
                          "failed (#{ids.join(', ')}); nothing ledgered for the run, " \
                          "the next sync resumes here"
      end

      # One GET → a PacedCrawl::Outcome (the engine paces, retries, stages
      # and ledgers): :ok (the item held), :denied (403/404, or a 200 that
      # is no item record), :empty (no transliteration), :timeout (a
      # transport timeout, or the server-error subclass for a 5xx — both
      # outage-staged). Any other failure raises. An already-held item (the
      # engine's held-id re-probe) is never overwritten: the probe answers
      # liveness, canonical stays.
      def fetch_item!(workdir, id)
        response, = Nabu::RedirectFollow.get(
          format(ITEM_URL, id), http: @http, error: Nabu::FetchError,
                                accept: [200, *DENIED_STATUSES, *SERVER_ERRORS],
                                headers: { "User-Agent" => Nabu::WikiFetch::USER_AGENT }
        )
        return item_outcome(:denied, response) if DENIED_STATUSES.include?(response.status)
        return item_outcome(:timeout, response, ledger_class: SERVER_ERROR) if SERVER_ERRORS.include?(response.status)

        body = response.body.to_s
        verdict = item_verdict(body)
        store_item!(item_path(workdir, id), body) if verdict == :ok
        item_outcome(verdict, response)
      rescue Nabu::FetchError => e
        raise unless e.message.match?(TIMEOUT_PATTERN)

        Nabu::PacedCrawl::Outcome.new(status: :timeout, evidence: { body_head: Nabu::PacedCrawl.body_head(e.message) })
      end

      def item_verdict(body)
        return :denied unless body.lstrip.start_with?("{")

        item = JSON.parse(body)["item"]
        return :denied unless item.is_a?(Hash)

        item["content"].to_s.strip.empty? ? :empty : :ok
      rescue JSON::ParserError
        :denied
      end

      def item_outcome(status, response, ledger_class: nil)
        Nabu::PacedCrawl::Outcome.from_body(status, http_status: response.status, body: response.body,
                                                    ledger_class: ledger_class)
      end

      def store_item!(target, body)
        return if File.file?(target)

        FileUtils.mkdir_p(File.dirname(target))
        File.binwrite("#{target}.tmp", body)
        File.rename("#{target}.tmp", target)
      end

      def item_path(workdir, id)
        File.join(workdir, ITEMS_DIRNAME, "#{id}.json")
      end

      def held_ids(workdir)
        Dir.glob(File.join(workdir, ITEMS_DIRNAME, "*.json")).map { |path| File.basename(path, ".json") }.sort
      end

      # The crawl identity: the listing bytes, the held items, the ledgered
      # classes (last_slice is derived, never identity) — the same inputs
      # as before the rail, so an unchanged tree keeps its sha.
      def crawl_sha(workdir, held, ledger)
        listing = listing_path(workdir)
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

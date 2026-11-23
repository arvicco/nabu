# frozen_string_literal: true

require "date"
require "digest"
require "fileutils"
require "json"
require "nokogiri"

require_relative "../fetch/zip_fetch"
require_relative "../redirect_follow"
require_relative "../fetch/wiki_fetch"
require_relative "../normalize"
require_relative "../paced_crawl"
require_relative "ntvmr_tei_parser"
require_relative "source_read"

module Nabu
  module Adapters
    # ntvmr: the New Testament Virtual Manuscript Room of the Institut für
    # Neutestamentliche Textforschung (INTF), Münster — the Gregory-Aland
    # catalogue of Greek New Testament manuscripts (the Kurzgefasste Liste:
    # papyri P1…, majuscules 01…, minuscules 1…, lectionaries L1…) and the
    # PUBLISHED transcriptions behind the Editio Critica Maior: each witness
    # transcribed page by page, verse by verse, with its scribes' corrections,
    # damaged letters, editorial restorations and contracted sacred names.
    #
    # == License (verified first-hand on every fixture transcript, 2026-11-23)
    #
    # Every transcript/get TEI header's availability carries, verbatim:
    # "(C) 2026 Institut für Neutestamentliche Textforschung." and "This work
    # is licensed under a Creative Commons Attribution 4.0 Unported License"
    # linking https://creativecommons.org/licenses/by/4.0/ → attribution.
    # The site's license agreement (ntvmr.uni-muenster.de/license-agreement)
    # says contributions "will be made available freely under the terms of
    # the Creative Commons, CC-BY license", while the IMAGES are licensed by
    # their holding institutions with no use outside the NTVMR — images are
    # out of scope, never fetched. A held transcript whose header lacks the
    # CC BY statement is not admitted (ParseError → quarantine).
    #
    # == Etiquette (read first-hand 2026-11-23) — the crawl is SUSPENDED
    #
    # ntvmr.uni-muenster.de/robots.txt, for User-agent *: "Disallow:
    # /community/vmr/api/" and "Crawl-delay: 10", under the comment "The
    # web-service API is not for search-engine crawling: several endpoints
    # execute expensive database queries. Bulk data consumers: please contact
    # the INTF, or use the documented exports rather than walking the API."
    # Both the Liste and transcript/get live under that disallowed path, and
    # no documented export of the transcriptions was found on the public
    # surface (home, help, ecm, license-agreement pages; the API's own
    # directory listing names no export). The API states no rate limit. So
    # the lane is declared SUSPENDED until the INTF grants bulk access (or
    # names an export), and #fetch REFUSES while it is: walking the API
    # against an explicit Disallow is not a pace question. DELAY is declared
    # for the day it is lifted: 30 s, three times the robots Crawl-delay,
    # because transcript/get assembles a whole manuscript per request (the
    # "expensive database queries" the robots comment names) — never lower
    # without an upstream statement allowing it.
    #
    # == Upstream's delivery grains (enumerated 2026-11-23)
    #
    # - the LISTE (metadata/liste/get/, no parameters): ONE XML document,
    #   <manuscripts count="7772"> with one empty <manuscript> per catalogued
    #   document (docID, gaNum, lang, orig — the century —, origEarly/
    #   origLate — 0 on all 7,772 —, primaryName, groupID/userID/v11n — empty
    #   on all). Held whole as liste.xml: the census. It carries no place.
    # - the MANUSCRIPT (transcript/get/?docID=<id>&pageID=ALL&format=teiraw):
    #   the whole published transcription as TEI — TAKEN as the document.
    #   An uncatalogued or untranscribed docID answers HTTP 200 with a bare
    #   error element instead (<error code="1" message="No Transcription
    #   Available for GA: L500 page: ALL"/> — ledgered no-transcript; <error
    #   code="300" message="docID: 34000 not found"/> — ledgered not-found).
    # - the PAGE (pageID=<n>) and the VERSE range (indexContent=Matt.1.1)
    #   answers are cuts of the same TEI — never fetched (the whole-
    #   manuscript answer subsumes them). The page is the passage fallback.
    # - the page IMAGES — restricted, out of scope.
    # - the Liste's NON-GA records — REJECTED by rule: the VMR catalogues far
    #   more than the Greek NT manuscripts (versional witnesses — Coptic,
    #   Syriac, Latin, Armenian, Arabic …; Septuagint and Qumran items;
    #   printed editions — Complutensis, Erasmus 1516 …; project working
    #   copies duplicating a GA number; test records). The GA manuscripts
    #   are exactly the five-digit docIDs 1xxxx (papyri), 2xxxx (majuscules),
    #   3xxxx (minuscules) and 4xxxx (lectionaries); every other docID is
    #   censused and skipped by rule, never crawled. A transcript file whose
    #   body is an error answer, found on disk, is skipped by rule too.
    #
    # == Reconciliation (the whole Liste, fetched 2026-11-23, 1,074,627 B)
    #
    # Upstream advertises count="7772" and lists exactly 7,772 records:
    # 6,200 GA manuscripts in scope (142 papyri + 332 majuscules + 3,067
    # minuscules + 2,659 lectionaries; every GA number unique, unique still
    # downcased with whitespace removed — the urn slug) + 1,572 non-GA
    # records skipped by rule (9 five-digit 5xxxx shelfmark-named records,
    # 339 five-digit 8xxxx/9xxxx, 735 six-digit, 479 seven-digit and 10
    # eight-digit docIDs). The census defense: the count attribute must
    # equal the records listed, else the fetch aborts (a truncated answer).
    # Of the 6,200, how many carry a PUBLISHED transcript is unknown until
    # the crawl asks (every no-transcript answer ledgers): expected at the
    # cone's end, held + no-transcript + not-found (+ any denied) = 6,200.
    #
    # == The resumable crawl (the paced-crawl rail, architecture §19)
    #
    # TRANSCRIPT_CRAWL is the lane: universe = the in-scope docIDs in Liste
    # order (docID ascending — papyri, majuscules, minuscules,
    # lectionaries), held = transcripts/<docID>.xml on disk, one GET per
    # docID, SLICE per sync. Ledgered in .ntvmr-crawl.json and never
    # retried blindly: no-transcript (error code 1) and its subclass
    # textless (a TEI whose body carries no letter); denied (403/404/410, an
    # unknown error code) with subclasses not-found (error code 300) and
    # malformed (a 200 that is neither TEI nor an error answer);
    # timeout-stuck with subclass server-error (5xx), under the outage
    # breaker. An HTTP 429 is the clean stop (Outcome.halt). INTF publishes
    # transcriptions over time: re-asking the no-transcript class is a
    # deliberate ledger clear at a phase decision, never automatic. The Liste
    # is a snapshot: held once with its dated manifest (.ntvmr-census.json:
    # url, fetched_on, the advertised count, bytes, sha256) and reused —
    # delete liste.xml to re-census.
    #
    # == Documents and passages
    #
    # Document = manuscript, urn urn:nabu:ntvmr:<GA slug> (the Liste's
    # gaNum downcased, whitespace removed: p52, 01, 0189, 304, l500, l102a);
    # passage = verse (…:p52:john.18.31 — sblgnt's book stems), or the page
    # (…:<ga>:p<page n>) for text in an ab carrying no verse key. Text and
    # annotation policy: NtvmrTeiParser's header (the cntr precedent: the
    # first hand's reading, restorations read through, nomina sacra as
    # written; corrections, the extant reading, Leiden counts and per-word
    # tokens ride annotations). Language grc on every document.
    #
    # == The nt alignment hub — DECLARED, not wired
    #
    # Every verse passage's tokens carry the hub's citation_part ("JOHN
    # 18.31"), the cntr shape the default proiel-citation extractor reads.
    # Joining the hub is then the cntr registry step — one single-document
    # witness entry per manuscript in config/alignments.yml — but which of
    # the 6,200 carry a published transcript is known only after the crawl;
    # the entries are minted from the held set once the crawl has run.
    #
    # == Axes (aggressive mining)
    #
    # - date — the Liste's orig century field (III, IV/V, XI-XII, "E III - A
    #   IV", a year "1292", "1291/92", "ca. 1043-55") → the envelope of every
    #   century or year it names (date_for); a "?" rides date_uncertain. The
    #   A/M/E (Anfang/Mitte/Ende) qualifiers and the per-part datings
    #   ("r: XII; ap: XIII") widen to the whole centuries — declared coarse.
    #   No class: the manuscript's own date (the artifact).
    # - place — none: the Liste carries no place, and the TEI msIdentifier
    #   (country, settlement, repository, idno) is the PRESENT holding
    #   library, which rides metadata only (the rundata/menota origin-axis
    #   stance). Unplaced, declared.
    # - category — papyrus / majuscule / minuscule / lectionary from the
    #   docID class (metadata + facet); the hands of the listWit ride
    #   metadata hands.
    class Ntvmr < Nabu::Adapter
      SLUG = "ntvmr"
      HOST = "https://ntvmr.uni-muenster.de"
      API = "#{HOST}/community/vmr/api".freeze
      LISTE_URL = "#{API}/metadata/liste/get/".freeze
      TRANSCRIPT_URL = "#{API}/transcript/get/?docID=%s&pageID=ALL&format=teiraw".freeze
      WORKSPACE_URL = "#{HOST}/manuscript-workspace?docID=%s".freeze
      URN_PREFIX = "urn:nabu:ntvmr:"
      LANGUAGE = "grc"

      LISTE_FILE = "liste.xml"
      CENSUS_STATE = ".ntvmr-census.json"
      TRANSCRIPTS_DIRNAME = "transcripts"
      LEDGER_FILE = ".ntvmr-crawl.json"

      # const: crawl politeness pause, not a corpus claim — three times the
      # robots Crawl-delay (10 s); see the header. Never lower.
      DELAY = 30.0
      # Manuscripts per sync: 60 × 30 s = 30 min of paced requests, the
      # loop's pass ceiling; the 6,200-docID cone is ~52 h of pace.
      SLICE = 60
      TIMEOUT_ATTEMPTS = 3
      TIMEOUT_BACKOFF = 30.0
      OUTAGE_RUN = 3
      NO_TRANSCRIPT = "no-transcript"
      TEXTLESS = "textless"
      NOT_FOUND = "not-found"
      MALFORMED = "malformed"
      STUCK = "timeout-stuck"
      SERVER_ERROR = "server-error"
      SUSPENSION = "robots.txt disallows /community/vmr/api/ and asks bulk consumers to contact the INTF — " \
                   "await INTF permission or a documented export"
      # The transcript lane's declared schedule (read by the phase slate):
      # per phase, three slices (~90 min of paced requests), a chained run
      # stops after three zero-yield slices (a no-transcript desert is
      # likely in the minuscule and lectionary ranges). Basis: the wellcome
      # cap, not a measured or ratified cadence. SUSPENDED by declaration
      # (the robots.txt Disallow — see the header): the rail skips the lane
      # and #fetch refuses until the INTF's word lifts it.
      TRANSCRIPT_CRAWL = Nabu::PacedCrawl::Spec.new(
        name: "transcripts", ledger_file: LEDGER_FILE,
        classes: { denied: "denied", empty: NO_TRANSCRIPT, timeout: STUCK },
        subclasses: { denied: [NOT_FOUND, MALFORMED], empty: [TEXTLESS], timeout: [SERVER_ERROR] },
        delay: DELAY, slice: SLICE, timeout_attempts: TIMEOUT_ATTEMPTS, timeout_backoff: TIMEOUT_BACKOFF,
        outage_statuses: [:timeout], outage_run: OUTAGE_RUN,
        schedule: Nabu::PacedCrawl::Schedule.new(cadence: :per_phase, slices_per_phase: 3, stop_after_zero_slices: 3,
                                                 suspended: SUSPENSION)
      )
      LEDGER_CLASSES = TRANSCRIPT_CRAWL.class_names.freeze
      DENIED_STATUSES = [403, 404, 410].freeze
      SERVER_ERRORS = (500..599).to_a.freeze
      TIMEOUT_PATTERN = /transport error for .*(timeout|timed out|execution expired)/i

      # The GA manuscripts: five-digit docIDs 1xxxx–4xxxx (see the header).
      GA_DOC_ID = /\A[1-4]\d{4}\z/
      CATEGORIES = { "1" => "papyrus", "2" => "majuscule", "3" => "minuscule", "4" => "lectionary" }.freeze
      DOC_ID = /\A\d+\z/
      ERROR_ANSWER = /\A\s*(?:<\?xml[^>]*\?>\s*)?<error\b/
      ERROR_ANSWER_MAX_BYTES = 1024

      CREDIT = "Institut für Neutestamentliche Textforschung (INTF), Münster — the New Testament Virtual " \
               "Manuscript Room (ntvmr.uni-muenster.de)"

      MANIFEST = Nabu::SourceManifest.new(
        id: SLUG,
        name: "NTVMR — the INTF New Testament Virtual Manuscript Room: published Greek NT manuscript transcriptions",
        license: "Creative Commons Attribution 4.0 (every transcript TEI header: \"This work is licensed under " \
                 "a Creative Commons Attribution 4.0 Unported License\", https://creativecommons.org/licenses/" \
                 "by/4.0/; \"(C) Institut für Neutestamentliche Textforschung\"). Credit the INTF, Münster. " \
                 "Transcriptions only — the manuscript images are licensed by their holding institutions and " \
                 "are not used",
        license_class: "attribution",
        upstream_url: HOST,
        parser_family: "ntvmr-tei",
        credit: CREDIT
      )

      # One Liste record.
      Record = Data.define(:doc_id, :ga, :orig, :category) do
        def in_scope? = !category.nil?
      end

      def self.manifest = MANIFEST

      def self.remote_probe_strategy = :http_zip

      # Liveness on the site's home page — an allowed path (the API is
      # robots-disallowed; a probe never walks it).
      def self.http_probe_targets
        [Nabu::Adapter::HttpProbeTarget.new(
          label: "ntvmr home", zip_url: "#{HOST}/", metadata_url: nil, state_subdir: "", liveness_only: true
        )]
      end

      # The Liste XML → [Record], upstream's order. Raises FetchError on an
      # answer that is not the Liste.
      def self.liste_records(xml)
        root = Nokogiri::XML(xml).root
        raise FetchError, "ntvmr Liste: no <manuscripts> root — the shape changed" unless root&.name == "manuscripts"

        root.xpath("./manuscript").map do |node|
          doc_id = node["docID"].to_s
          ga = node["gaNum"].to_s.strip
          category = doc_id.match?(GA_DOC_ID) && !ga.empty? ? CATEGORIES.fetch(doc_id[0]) : nil
          Record.new(doc_id: doc_id, ga: ga, orig: node["orig"].to_s.strip, category: category)
        end
      end

      # The Liste's own advertised record count (the count attribute).
      def self.liste_count(xml)
        value = Nokogiri::XML(xml).root&.[]("count")
        value&.match?(/\A\d+\z/) ? Integer(value, 10) : nil
      end

      # The urn slug of a GA number: downcased, whitespace removed.
      def self.ga_slug(number) = number.downcase.gsub(/[[:space:]]+/, "")

      ROMAN = { "I" => 1, "V" => 5, "X" => 10 }.freeze
      ROMAN_NUMERAL = /(?<![A-Za-z])[IVX]+(?![A-Za-z])/

      # The Liste's orig field → {"not_before", "not_after", "raw"} or nil
      # (blank, "?", "[reserved]" — no reading). Years (3–4 digits, an
      # abbreviated second year "1291/92" / "1034-41" expanded) take
      # precedence over centuries; otherwise every Roman century named (I–
      # XIX, upcased — the "XIIi" typo reads XIII) widens the envelope:
      # century N = (N-1)*100+1 .. N*100.
      def self.date_for(orig)
        raw = orig.to_s.strip
        bounds = year_bounds(raw)
        bounds = century_bounds(raw) if bounds.empty?
        return nil if bounds.empty?

        { "not_before" => bounds.min, "not_after" => bounds.max, "raw" => raw }
      end

      def self.year_bounds(raw)
        pairs = raw.scan(%r{(?<!\d)(\d{3,4})(?:\s*[/-]\s*(\d{1,4}))?(?!\d)})
        years = pairs.flat_map do |first, second|
          start = Integer(first, 10)
          finish = second ? expand_year(first, second) : start
          [start, [finish, start].max]
        end
        years.grep(1..1900)
      end

      def self.century_bounds(raw)
        centuries = raw.upcase.scan(ROMAN_NUMERAL).filter_map { |token| century(token) }
        centuries.flat_map { |number| [((number - 1) * 100) + 1, number * 100] }
      end

      def self.expand_year(first, second)
        return Integer(second, 10) if second.length >= first.length

        Integer(first[0, first.length - second.length] + second, 10)
      end

      def self.century(token)
        values = token.chars.map { |char| ROMAN.fetch(char) }
        total = values.each_with_index.sum do |value, index|
          following = values[index + 1]
          following && following > value ? -value : value
        end
        total.between?(1, 19) && roman(total) == token ? total : nil
      end

      def self.roman(number)
        [[10, "X"], [9, "IX"], [5, "V"], [4, "IV"], [1, "I"]].each_with_object(+"") do |(value, mark), out|
          while number >= value
            out << mark
            number -= value
          end
        end
      end

      # A 200 body → [status, ledger subclass or nil]: TEI with letters is
      # :ok; error code 1 :empty (the class's own no-transcript); a TEI
      # without letters :empty/textless; error code 300 :denied/not-found;
      # another error code :denied; anything else :denied/malformed.
      def self.transcript_verdict(body)
        if body.match?(ERROR_ANSWER)
          code = Nokogiri::XML(body).root&.[]("code")
          return [:empty, nil] if code == "1"
          return [:denied, NOT_FOUND] if code == "300"

          return [:denied, nil]
        end
        result = NtvmrTeiParser.parse(body, label: "ntvmr transcript")
        result.verses.empty? ? [:empty, TEXTLESS] : [:ok, nil]
      rescue ParseError
        [:denied, MALFORMED]
      end

      def initialize(delay: DELAY, slice: SLICE, http: Nabu::ZipFetch.default_http,
                     timeout_backoff: TIMEOUT_BACKOFF, sleeper: ->(seconds) { sleep(seconds) },
                     clock: -> { Time.now }, honor_suspension: true)
        super()
        @delay = delay
        @slice = slice
        @timeout_backoff = timeout_backoff
        @http = http
        @sleeper = sleeper
        @clock = clock
        @honor_suspension = honor_suspension
        @census = {}
      end

      # -- fetch -------------------------------------------------------------

      # Refuses while the lane is declared suspended (see the header).
      # +force+ is part of the fetch interface; nothing here ever deletes.
      def fetch(workdir, progress: nil, force: false) # rubocop:disable Lint/UnusedMethodArgument
        if @honor_suspension && TRANSCRIPT_CRAWL.schedule.suspended?
          raise FetchError, "ntvmr: the transcript crawl is SUSPENDED (#{SUSPENSION}); nothing fetched"
        end

        FileUtils.mkdir_p(workdir)
        census_note = ensure_census!(workdir, progress)
        crawl = transcript_crawl(workdir, progress: progress)
        report = crawl.slice!
        lines = report.lines
        lines.each { |line| progress&.call("#{line}\n") }
        abort_outage!(report) if report.outage_aborted?
        Nabu::FetchReport.new(sha: crawl_sha(workdir, held_ids(workdir), crawl.ledger), fetched_at: @clock.call,
                              notes: ([census_note] + lines).join("; "))
      end

      # The chain runner's seam (rake crawl:chain): the one paced lane.
      def paced_crawls(workdir, progress: nil)
        { TRANSCRIPT_CRAWL.name => transcript_crawl(workdir, progress: progress) }
      end

      # The transcript lane's engine over +workdir+: the in-scope docIDs in
      # Liste order, held = transcripts/<docID>.xml, one paced GET each.
      def transcript_crawl(workdir, progress: nil)
        Nabu::PacedCrawl::Engine.new(
          spec: TRANSCRIPT_CRAWL.with(delay: @delay, slice: @slice, timeout_backoff: @timeout_backoff),
          dir: workdir, progress: progress, sleeper: @sleeper,
          universe: -> { census(workdir).fetch(:in_scope).map(&:doc_id) },
          held: ->(id) { File.file?(transcript_path(workdir, id)) },
          fetch_one: ->(id) { fetch_transcript!(workdir, id) }
        )
      end

      # The held census, offline: {count:, records:, in_scope:, rejected:,
      # by_id:} ({} shapes when liste.xml is absent).
      def census(workdir)
        @census[workdir] ||= begin
          path = File.join(workdir, LISTE_FILE)
          xml = File.file?(path) ? SourceRead.utf8_file(path, label: "ntvmr Liste") : nil
          records = xml ? self.class.liste_records(xml) : []
          { count: xml && self.class.liste_count(xml), records: records,
            in_scope: records.select(&:in_scope?), rejected: records.reject(&:in_scope?),
            by_id: records.to_h { |record| [record.doc_id, record] } }
        end
      end

      # -- discover ----------------------------------------------------------

      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        scan(workdir).fetch(:refs).each(&block)
      end

      def discovery_skips(workdir)
        result = scan(workdir)
        Nabu::Adapter::DiscoverySkips.new(skipped_by_rule: result.fetch(:skipped).size,
                                          unrecognized: result.fetch(:unrecognized).size,
                                          notes: result.fetch(:skipped) + result.fetch(:unrecognized))
      end

      # -- parse -------------------------------------------------------------

      def parse(document_ref)
        result = NtvmrTeiParser.parse(read_transcript(document_ref.path), label: document_ref.path)
        header = result.header
        unless header.license_url
          raise ParseError, "#{document_ref.path}: no Creative Commons Attribution statement in the TEI header " \
                            "— not admitted"
        end

        doc_id = document_ref.metadata.fetch("doc_id")
        record = census(File.dirname(document_ref.path, 2))[:by_id][doc_id]
        document = Nabu::Document.new(
          urn: document_ref.id, language: LANGUAGE, canonical_path: document_ref.path,
          title: title_for(document_ref.metadata.fetch("ga"), header),
          metadata: metadata_for(doc_id, document_ref.metadata.fetch("ga"), record, result)
        )
        result.verses.each do |verse|
          document << Nabu::Passage.new(urn: "#{document_ref.id}:#{verse.urn_tail}", language: LANGUAGE,
                                        text: verse.text, sequence: document.size + 1,
                                        annotations: verse.annotations)
        end
        raise ParseError, "#{document_ref.path}: the transcription carries no lettered verse or page" if document.empty?

        document
      end

      private

      # -- census ------------------------------------------------------------

      # Reads (or fetches once) the Liste; returns its note.
      def ensure_census!(workdir, progress)
        path = File.join(workdir, LISTE_FILE)
        fetched = false
        unless File.file?(path)
          progress&.call("ntvmr census: #{LISTE_URL}\n")
          response, = Nabu::RedirectFollow.get(LISTE_URL, http: @http, error: Nabu::FetchError,
                                                          headers: { "User-Agent" => Nabu::WikiFetch::USER_AGENT })
          body = response.body.to_s.dup.force_encoding(Encoding::UTF_8)
          defend_liste!(body)
          write_atomic!(path, body)
          write_census_state!(workdir, body)
          @census.delete(workdir)
          fetched = true
          @sleeper.call(@delay) if @delay.positive?
        end
        held = census(workdir)
        "census #{held[:records].size} Liste record(s) (upstream count #{held[:count]}) = " \
          "#{held[:in_scope].size} GA manuscripts + #{held[:rejected].size} non-GA records (skipped by rule)" \
          "#{fetched ? ' — Liste fetched' : ' — held Liste reused'}"
      end

      # The truncation defense: the advertised count must equal the records.
      def defend_liste!(body)
        records = self.class.liste_records(body)
        count = self.class.liste_count(body)
        raise FetchError, "ntvmr Liste states no record count — upstream shape changed" if count.nil?
        return if count == records.size && records.any?(&:in_scope?)

        raise FetchError, "ntvmr Liste is TRUNCATED: upstream states count=#{count}, the answer lists " \
                          "#{records.size} record(s) — retry"
      end

      def write_census_state!(workdir, body)
        state = { "url" => LISTE_URL, "fetched_on" => @clock.call.utc.to_date.iso8601,
                  "count" => self.class.liste_count(body), "bytes" => body.bytesize,
                  "sha256" => Digest::SHA256.hexdigest(body) }
        write_atomic!(File.join(workdir, CENSUS_STATE), "#{JSON.pretty_generate(state)}\n")
      end

      # -- the crawl ---------------------------------------------------------

      def abort_outage!(report)
        ids = report.outage[:ids]
        raise FetchError, "ntvmr crawl aborted — upstream outage: #{ids.size} consecutive docID(s) failed " \
                          "(#{ids.join(', ')}); nothing ledgered for the run, the next sync resumes here"
      end

      # One GET → a PacedCrawl::Outcome (see the header's ledger classes).
      # A held transcript (the engine's re-probe) is never overwritten.
      def fetch_transcript!(workdir, id)
        response, = Nabu::RedirectFollow.get(
          format(TRANSCRIPT_URL, id), http: @http, error: Nabu::FetchError,
                                      accept: [200, 429, *DENIED_STATUSES, *SERVER_ERRORS],
                                      headers: { "User-Agent" => Nabu::WikiFetch::USER_AGENT }
        )
        return halt(response) if response.status == 429
        return outcome(:denied, response) if DENIED_STATUSES.include?(response.status)
        return outcome(:timeout, response, ledger_class: SERVER_ERROR) if SERVER_ERRORS.include?(response.status)

        body = response.body.to_s.dup.force_encoding(Encoding::UTF_8)
        status, ledger_class = self.class.transcript_verdict(body)
        store!(transcript_path(workdir, id), body) if status == :ok
        outcome(status, response, ledger_class: ledger_class)
      rescue Nabu::FetchError => e
        raise unless e.message.match?(TIMEOUT_PATTERN)

        Nabu::PacedCrawl::Outcome.new(status: :timeout, evidence: { body_head: Nabu::PacedCrawl.body_head(e.message) })
      end

      def halt(response)
        Nabu::PacedCrawl::Outcome.halt(reason: "HTTP 429 (rate-limited) — the next sync resumes",
                                       evidence: { http_status: 429,
                                                   body_head: Nabu::PacedCrawl.body_head(response.body) })
      end

      def outcome(status, response, ledger_class: nil)
        Nabu::PacedCrawl::Outcome.from_body(status, http_status: response.status, body: response.body,
                                                    ledger_class: ledger_class)
      end

      def store!(target, body)
        return if File.file?(target)

        write_atomic!(target, body)
      end

      def write_atomic!(target, body)
        FileUtils.mkdir_p(File.dirname(target))
        File.binwrite("#{target}.tmp", body)
        File.rename("#{target}.tmp", target)
      end

      def transcript_path(workdir, id) = File.join(workdir, TRANSCRIPTS_DIRNAME, "#{id}.xml")

      def held_ids(workdir)
        Dir.glob(File.join(workdir, TRANSCRIPTS_DIRNAME, "*.xml")).map { |path| File.basename(path, ".xml") }.sort
      end

      # The crawl identity: the Liste bytes, the held transcripts, the
      # ledgered classes (last_slice is derived, never identity).
      def crawl_sha(workdir, held, ledger)
        liste = File.join(workdir, LISTE_FILE)
        census = File.file?(liste) ? Digest::SHA256.file(liste).hexdigest : ""
        classes = LEDGER_CLASSES.map { |key| ledger.fetch(key, []).sort }
        Digest::SHA256.hexdigest(JSON.generate([census, held, *classes]))
      end

      # -- discovery ---------------------------------------------------------

      def scan(workdir)
        refs = []
        skipped = []
        unrecognized = []
        held = census(workdir)
        Dir.glob(File.join(workdir, TRANSCRIPTS_DIRNAME, "*")).each do |path|
          next unless File.file?(path)

          name = File.basename(path)
          id = name.delete_suffix(".xml")
          record = held[:by_id][id]
          rel = "#{TRANSCRIPTS_DIRNAME}/#{name}"
          if !name.end_with?(".xml") || !id.match?(DOC_ID)
            unrecognized << "#{rel}: not a <docID>.xml transcript"
          elsif record.nil?
            unrecognized << "#{rel}: docID #{id} is not in the held Liste"
          elsif !record.in_scope?
            skipped << "#{rel}: docID #{id} (#{record.ga}) is a non-GA Liste record — skipped by rule"
          elsif error_answer?(path)
            skipped << "#{rel}: an upstream error answer (no published transcription), not a TEI — skipped by rule"
          else
            refs << ref_for(path, record)
          end
        end
        { refs: disambiguate(refs), skipped: skipped, unrecognized: unrecognized + stray_files(workdir) }
      end

      def ref_for(path, record)
        Nabu::DocumentRef.new(source_id: SLUG, id: "#{URN_PREFIX}#{self.class.ga_slug(record.ga)}",
                              path: File.expand_path(path),
                              metadata: { "doc_id" => record.doc_id, "ga" => record.ga })
      end

      # Two docIDs whose GA slugs collide (none at the 2026-11-23 census)
      # both take a -d<docID> suffix rather than one shadowing the other.
      def disambiguate(refs)
        colliding = refs.group_by(&:id).select { |_, group| group.size > 1 }.keys
        refs.map do |ref|
          next ref unless colliding.include?(ref.id)

          ref.with(id: "#{ref.id}-d#{ref.metadata.fetch('doc_id')}")
        end
      end

      # An error answer is a one-element document of a few dozen bytes; a
      # transcript is kilobytes — only a small file is read to tell.
      def error_answer?(path)
        File.size(path) < ERROR_ANSWER_MAX_BYTES &&
          SourceRead.utf8_file(path, label: "ntvmr transcript").match?(ERROR_ANSWER)
      rescue ParseError
        false
      end

      # Files outside transcripts/ and the Liste (dotfiles — the ledger and
      # the census manifest — and the attic excepted; the fixture sentinel's
      # README/manifest too).
      def stray_files(workdir)
        Dir.glob(File.join(workdir, "**", "*"))
           .select { |path| File.file?(path) }
           .reject { |path| path.include?("/#{ATTIC_DIRNAME}/") || File.basename(path).start_with?(".") }
           .reject { |path| path.start_with?(File.join(workdir, TRANSCRIPTS_DIRNAME, "")) }
           .map { |path| path.delete_prefix("#{workdir}/") }
           .reject { |rel| [LISTE_FILE, "README.md", "manifest.yml"].include?(rel) }
           .map { |rel| "#{rel}: non-corpus file" }
      end

      # -- parse internals ---------------------------------------------------

      def read_transcript(path)
        SourceRead.utf8_file(path, label: "ntvmr transcript")
      rescue Errno::ENOENT => e
        raise ParseError, "#{path}: unreadable transcript: #{e.message}"
      end

      def title_for(ga_number, header)
        holding = [header.settlement, header.repository, header.idno].compact.join(", ")
        Normalize.nfc(holding.empty? ? "GA #{ga_number}" : "GA #{ga_number} (#{holding})")
      end

      def metadata_for(doc_id, ga_number, record, result)
        header = result.header
        date = record && self.class.date_for(record.orig)
        {
          "ga" => ga_number, "doc_id" => doc_id, "category" => record&.category,
          "liste_century" => record && !record.orig.empty? ? Normalize.nfc(record.orig) : nil,
          "date" => date, "date_uncertain" => date && record.orig.include?("?") ? true : nil,
          "country" => header.country, "settlement" => header.settlement, "repository" => header.repository,
          "idno" => header.idno, "hands" => header.hands.empty? ? nil : header.hands,
          "books" => books(result), "verses" => result.verses.count(&:key),
          "page_passages" => result.page_passages.zero? ? nil : result.page_passages,
          "verses_letterless" => result.letterless.zero? ? nil : result.letterless,
          "copyright" => header.copyright, "license_statement" => header.license_statement,
          "license_url" => header.license_url, "permalink" => format(WORKSPACE_URL, doc_id),
          "facets" => record&.category ? { "category" => { "values" => [record.category] } } : nil
        }.compact
      end

      def books(result)
        list = result.verses.filter_map { |verse| verse.key && NtvmrTeiParser::BOOKS.fetch(verse.key.first)[1] }.uniq
        list.empty? ? nil : list
      end
    end
  end
end

# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "nokogiri"

require_relative "../fetch/zip_fetch"
require_relative "../redirect_follow"
require_relative "../fetch/wiki_fetch"
require_relative "../normalize"
require_relative "../paced_crawl"
require_relative "source_read"

module Nabu
  module Adapters
    # niupepa: Niupepa — Māori Newspapers, the New Zealand Digital
    # Library's collection (University of Waikato) of the newspapers
    # published primarily for a Māori audience between 1842 and 1932: 34
    # periodical runs from Te Karere O Nui Tireni (1842, printed by order
    # of the Governor in Auckland) through the government Maori Messenger
    # / Te Karere Maori and the Waka Maori papers, the independent and
    # Kīngitanga press (Te Hokioi, Te Wananga, Huia Tangata Kotahi, Te
    # Puke Ki Hikurangi), the church papers (Te Haeata, Te Hoa Maori, Te
    # Kopara) to Te Toa Takitini (1921–1932) — the largest body of
    # Māori-language text online. The collection's own description: 70% of
    # it is written solely in Māori, 27% bilingual, about 3% in English. It
    # is built on the Alexander Turnbull Library's microfiche "Niupepa
    # 1842-1933".
    #
    # == License (the restricted research class)
    #
    # No public license is stated on the collection's surface. Use is
    # granted on these terms: a personal single-user research library,
    # held locally only, nothing redistributed, the harvest polite and
    # spread over several days → research_private (local fixtures only,
    # never a public surface). The Niupepa collection and the New Zealand
    # Digital Library, University of Waikato, are credited on every
    # passage (MANIFEST credit). The newspapers themselves are out of
    # copyright by age.
    #
    # == The host (established first-hand 2026-11-21)
    #
    # niupepa.natlib.govt.nz does not resolve, and every www.nzdl.org URL
    # (robots.txt included) answers a JavaScript bot challenge — neither is
    # a route. The collection is served by the University of Waikato's
    # Greenstone 3 Showcase at www.greenstone.org/greenstone3/library/
    # collection/niupepa, which answers plain GETs. Its robots.txt is
    # "User-agent: * / Disallow:" followed by "Crawl-delay: 10" (the
    # msnbot line above it is commented out, so the delay binds every
    # agent): the crawl paces at DELAY = 10 s.
    #
    # == Upstream's delivery grains (enumerated 2026-11-21)
    #
    # - the collection → the SERIES classifier browse/CL1: 34 periodical
    #   runs, each labelled with its document count ("Te Karere O Nui
    #   Tireni 1842-1846 (49 issues )") — summed, 1,840. Each series lists
    #   its documents at browse/CL1/<n>?excerptid=divCL1.<n> (the page the
    #   classifier's own toggle requests). Both are kept under map/
    #   verbatim: they are the crawl's census.
    # - the ISSUE (Greenstone oid <series>_<volume>_<number>: 01_1_1,
    #   06a_1_1, 41__1, 19_2_ — the series code may carry a letter, the
    #   volume or number may be empty) — TAKEN as the document. One GET of
    #   document/<oid>?ed=1&o=xml answers the whole issue as Greenstone's
    #   page XML: the root documentNode carries the issue metadata (Title
    #   "Volume 1, Number 1", Date "18420101" / "185710" / "1859", Series,
    #   DocType Niupepa, the abstract and commentary oids), every leaf
    #   documentNode is one PAGE with its metadata (Title = the page
    #   number, hastxt, the facsimile image names) and its text as the
    #   escaped HTML of a <pre> block.
    # - the PAGE — the passage (urn …:<oid>:p<n>, n = the section number).
    #   A page without text (hastxt 0, empty <pre>) mints no passage and is
    #   counted in metadata pages_without_text.
    # - the series COMMENTARY (<series>commentary, docType simple —
    #   Dallimore's modern English bibliographic commentaries, 22 of them
    #   among the 1,840 listed documents) — REJECTED: modern scholarly
    #   prose, not the newspapers. Never fetched; censused off the listing;
    #   a specimen found on disk is skipped by rule.
    # - the issue ABSTRACT (<oid>abstract, linked from the listing and the
    #   issue's "abstract" metadata — modern English summaries, not counted
    #   in the series totals) — REJECTED likewise: never fetched, a
    #   specimen on disk is skipped by rule.
    # - the facsimile page images (GIF + screen JPEG under index/assoc/) —
    #   never fetched (text only).
    #
    # == Reconciliation (census 2026-11-21, the 34 listings read whole)
    #
    # Upstream counts 1,840 documents over 34 series; the listings carry
    # exactly 1,840: 1,818 issues + 22 series commentaries (12 series —
    # Takitimu, Te Hoa Maori, Aotearoa 1892, Te Paki o Matariki, Huia
    # Tangata Kotahi, Panui Whakawa Whenua Maori, He Kupu Whakamarama, Te
    # Tiupiri, Pipiwharauroa, The Maori Record, Te Waka Maori o Niu Tirani
    # 1871-1877, Te Toa Takitini — list none). The universe is the 1,818
    # issues; the 22 commentaries are the rejected grain. Some issues serve
    # no text at all (every page hastxt 0 — 2 of 7 sampled at fixture
    # time); they ledger "no-text" and are never re-asked. Expected at the
    # end of the cone: held + no-text (+ any denied) = 1,818.
    #
    # == The resumable crawl (the paced-crawl rail, architecture §19)
    #
    # The census is read once: browse/CL1 plus every series listing, each
    # written to map/ only after its truncation defense passes (a listing
    # must carry exactly the count its series label states; a missing
    # count, zero series or zero issues aborts). A held complete census is
    # REUSED on later syncs — the collection is a closed historical set —
    # and a partial one is completed (only the missing listings are asked).
    # Delete map/ to re-census. Census GETs pace at DELAY too.
    #
    # ISSUE_CRAWL is the lane: one paced GET per issue in census order
    # (series order, then upstream's listing order), SLICE per sync, held =
    # issues/<oid>.xml on disk. Ledgered in .niupepa-crawl.json and never
    # retried: 403/404 or an answer that is not this issue's page XML
    # ("denied"), an issue with no page text ("no-text"), an issue that
    # times out TIMEOUT_ATTEMPTS times ("timeout-stuck") or answers 5xx as
    # often ("server-error", a subclass of the timeout class). The outage
    # breaker (the damos shape) aborts a slice after OUTAGE_RUN
    # consecutive timeouts/5xx with the run unledgered.
    #
    # == Text and language
    #
    # The page text is the collection's searchable text layer (machine OCR,
    # uncorrected: "boa" for hoa, "0" for O) as served — text_nature
    # machine-ocr. Lines keep upstream's layout; trailing whitespace per
    # line and blank edges are trimmed, nothing else. Period orthography is
    # canonical, never corrected: the early prints write w for wh
    # ("wakaaro", "Kawana") and carry no macrons, and spacing and
    # hyphenation follow the columns. Language mri on every document (the
    # codemap carries mri → mi): deliberately coarse — the bilingual issues
    # (Māori with English columns: the Maori Messenger, the Anglo Maori
    # Warder, the Maori Record) carry no per-page or per-issue language
    # mark, so no English claim is made.
    #
    # == Axes (aggressive mining)
    #
    # - date — the issue's own Date (YYYYMMDD, YYYYMM or YYYY) → a one-year
    #   envelope (MetadataDates :structured), the ISO day/month riding raw;
    #   no class (the print IS the publication, the delpher-newspapers
    #   precedent).
    # - series — the periodical run as upstream names it ("Te Wananga
    #   1874-1878": title + run years); the paper's name and run ride
    #   series_title / series_run, the series facets the paper.
    # - issue label, volume, number, page count, the abstract/commentary
    #   cross-reference oids, the permalink.
    # - places — the issue records name no place of publication (the
    #   commentaries do, in prose — the rejected grain): unplaced, DECLARED.
    # - kind — the whole source is the periodical press (kind_map
    #   source_kind periodical/newspaper).
    class Niupepa < Nabu::Adapter
      SLUG = "niupepa"
      COLLECTION_URL = "https://www.greenstone.org/greenstone3/library/collection/niupepa"
      SERIES_URL = "#{COLLECTION_URL}/browse/CL1".freeze
      LISTING_URL = "#{COLLECTION_URL}/browse/CL1/%<n>s?excerptid=divCL1.%<n>s".freeze
      ISSUE_URL = "#{COLLECTION_URL}/document/%s?ed=1&o=xml".freeze
      PERMALINK = "#{COLLECTION_URL}/document/%s".freeze
      URN_PREFIX = "urn:nabu:niupepa:"
      LANGUAGE = "mri"

      MAP_DIRNAME = "map"
      SERIES_FILE = "CL1.html"
      LISTING_FILE = "CL1.%s.html"
      ISSUES_DIRNAME = "issues"
      LEDGER_FILE = ".niupepa-crawl.json"

      # const: crawl politeness pause, not a corpus claim — robots.txt's
      # "Crawl-delay: 10" binds every agent.
      DELAY = 10.0
      # Issues per sync: ~150 × (10 s pause + ~1 s answer) ≈ 28 min, under
      # the live-pass limit; the 1,818-issue cone crawls in ~13 slices.
      SLICE = 150
      TIMEOUT_ATTEMPTS = 3
      TIMEOUT_BACKOFF = 5.0
      OUTAGE_RUN = 3
      STUCK = "timeout-stuck"
      SERVER_ERROR = "server-error"
      NO_TEXT = "no-text"
      # The issue lane's declared schedule (read by the phase slate): per
      # phase, three slices (~1.4 h of paced requests), a chained run stops
      # after three zero-yield slices. Basis: the grant's own framing —
      # a polite harvest spread over several days — the 13-slice cone
      # spans about five phases at this cap.
      ISSUE_CRAWL = Nabu::PacedCrawl::Spec.new(
        name: "issues", ledger_file: LEDGER_FILE,
        classes: { denied: "denied", empty: NO_TEXT, timeout: STUCK },
        subclasses: { timeout: [SERVER_ERROR] },
        delay: DELAY, slice: SLICE, timeout_attempts: TIMEOUT_ATTEMPTS, timeout_backoff: TIMEOUT_BACKOFF,
        outage_statuses: [:timeout], outage_run: OUTAGE_RUN,
        schedule: Nabu::PacedCrawl::Schedule.new(cadence: :per_phase, slices_per_phase: 3, stop_after_zero_slices: 3)
      )
      LEDGER_CLASSES = ISSUE_CRAWL.class_names.freeze
      DENIED_STATUSES = [403, 404].freeze
      SERVER_ERRORS = (500..599).to_a.freeze
      TIMEOUT_PATTERN = /transport error for .*(timeout|timed out|execution expired)/i

      # Greenstone oids: an issue is <series>_<volume>_<number> (letters
      # allowed in the series code, volume/number possibly empty, a double
      # issue hyphenated: Te Kopara's 40__24-25); the rejected grains end
      # in "commentary" / "abstract".
      ISSUE_ID = /\A(?!.*(?:abstract|commentary)\z)\d+[a-z]?_[0-9a-z]*_[0-9a-z-]*\z/
      COMMENTARY_ID = /commentary\z/
      ABSTRACT_ID = /abstract\z/
      SERIES_COUNT = /\((\d+) issues? \)/
      SERIES_RUN = /\s+(\d{4}(?:-\d{4})?)\z/
      ISSUE_DATE = /\A(\d{4})(\d{2})?(\d{2})?\z/
      ISSUE_DOC_TYPE = "Niupepa"

      CREDIT = "Niupepa: Māori Newspapers — the New Zealand Digital Library, University of Waikato " \
               "(#{COLLECTION_URL})".freeze

      MANIFEST = Nabu::SourceManifest.new(
        id: SLUG,
        name: "Niupepa — Māori Newspapers 1842–1932 (New Zealand Digital Library, University of Waikato)",
        license: "Research use on granted terms (no public license stated): a personal single-user " \
                 "research library, held locally only, nothing redistributed; harvested politely over " \
                 "several days. Credit the Niupepa collection and the New Zealand Digital Library, " \
                 "University of Waikato. The newspapers (1842–1932) are out of copyright by age",
        license_class: "research_private",
        upstream_url: COLLECTION_URL,
        parser_family: "greenstone-niupepa",
        credit: CREDIT
      )

      # One series of the census: its classifier index, upstream's label
      # (the name with its run), and the document count the label states.
      Series = Data.define(:index, :label, :count)
      # One listed document of a series listing.
      Listed = Data.define(:oid, :label)

      def self.manifest = MANIFEST

      def self.remote_probe_strategy = :http_zip

      def self.http_probe_targets
        [Nabu::Adapter::HttpProbeTarget.new(
          label: "niupepa collection", zip_url: COLLECTION_URL, metadata_url: nil,
          state_subdir: "", liveness_only: true
        )]
      end

      # The series classifier page → [Series], upstream's order. Raises
      # FetchError on a page with no series (the shape changed).
      def self.series_list(html)
        doc = Nokogiri::HTML(html)
        series = doc.css("table[id^='titleCL1.']").filter_map do |table|
          index = table["id"][/\AtitleCL1\.(\d+)\z/, 1] or next
          label = table.css("td").last.text.gsub(/[[:space:]]+/, " ").strip
          count = label[SERIES_COUNT, 1]
          raise FetchError, "niupepa series CL1.#{index} states no document count: #{label.inspect}" unless count

          Series.new(index: index, label: Normalize.nfc(label.sub(SERIES_COUNT, "").strip), count: Integer(count, 10))
        end
        raise FetchError, "niupepa series classifier lists no series — upstream shape changed" if series.empty?

        series
      end

      # One series listing → [Listed], upstream's order.
      def self.listing(html)
        Nokogiri::HTML(html).css("table[id^='div']").filter_map do |table|
          oid = table["id"].delete_prefix("div")
          next if oid.start_with?("CL")

          Listed.new(oid: oid, label: table.css("td").last.text.gsub(/[[:space:]]+/, " ").strip)
        end
      end

      def initialize(delay: DELAY, slice: SLICE, http: Nabu::ZipFetch.default_http,
                     timeout_backoff: TIMEOUT_BACKOFF, sleeper: ->(seconds) { sleep(seconds) })
        super()
        @delay = delay
        @slice = slice
        @timeout_backoff = timeout_backoff
        @http = http
        @sleeper = sleeper
        @universe = {}
      end

      # -- fetch -------------------------------------------------------------

      # +force+ is part of the fetch interface; nothing here ever deletes.
      def fetch(workdir, progress: nil, force: false) # rubocop:disable Lint/UnusedMethodArgument
        FileUtils.mkdir_p(workdir)
        census_note = ensure_census!(workdir, progress)
        crawl = issue_crawl(workdir, progress: progress)
        report = crawl.slice!
        lines = report.lines
        lines.each { |line| progress&.call("#{line}\n") }
        abort_outage!(report) if report.outage_aborted?
        Nabu::FetchReport.new(sha: crawl_sha(workdir, held_ids(workdir), crawl.ledger), fetched_at: Time.now,
                              notes: ([census_note] + lines).join("; "))
      end

      # The chain runner's seam (rake crawl:chain): the one paced lane.
      def paced_crawls(workdir, progress: nil)
        { ISSUE_CRAWL.name => issue_crawl(workdir, progress: progress) }
      end

      # The issue lane's engine over +workdir+: the held census's issues in
      # order, held = issues/<oid>.xml, one paced GET per issue.
      def issue_crawl(workdir, progress: nil)
        Nabu::PacedCrawl::Engine.new(
          spec: ISSUE_CRAWL.with(delay: @delay, slice: @slice, timeout_backoff: @timeout_backoff),
          dir: workdir, progress: progress, sleeper: @sleeper,
          universe: -> { universe(workdir) },
          held: ->(id) { File.file?(issue_path(workdir, id)) },
          fetch_one: ->(id) { fetch_issue!(workdir, id) }
        )
      end

      # The held census, read offline: {series:, issues:, commentaries:}
      # or nil when map/ holds no complete census.
      def census(workdir)
        top = map_path(workdir, SERIES_FILE)
        return nil unless File.file?(top)

        series = self.class.series_list(SourceRead.utf8_file(top, label: "niupepa census"))
        listed = series.map do |entry|
          path = map_path(workdir, format(LISTING_FILE, entry.index))
          return nil unless File.file?(path)

          self.class.listing(SourceRead.utf8_file(path, label: "niupepa census"))
        end.flatten
        { series: series, issues: listed.map(&:oid).grep(ISSUE_ID),
          commentaries: listed.map(&:oid).grep(COMMENTARY_ID) }
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
        xml = read_issue(document_ref.path)
        root = issue_root!(xml, document_ref)
        meta = node_metadata(root)
        pages = root.xpath(".//documentNode[@nodeType='leaf']")
        texts = pages.map { |page| [page, page_text(page)] }
        oid = document_ref.metadata.fetch("oid")
        document = Nabu::Document.new(
          urn: document_ref.id, language: LANGUAGE, canonical_path: document_ref.path,
          title: title_for(meta), metadata: metadata_for(oid, meta, pages.size, texts.count { |_, t| t.empty? })
        )
        texts.each do |page, text|
          next if text.empty?

          page_meta = node_metadata(page)
          document << Nabu::Passage.new(
            urn: "#{document_ref.id}:p#{section_number(page, oid)}", language: LANGUAGE, text: text,
            sequence: document.size + 1, annotations: { "page" => page_meta["Title"] }.compact
          )
        end
        raise ParseError, "#{document_ref.path}: no page of issue #{oid} carries text" if document.empty?

        document
      end

      private

      # -- census ------------------------------------------------------------

      # Reads (or completes) the census under map/; returns its note.
      def ensure_census!(workdir, progress)
        asked = 0
        top = map_path(workdir, SERIES_FILE)
        unless File.file?(top)
          body = census_get!(SERIES_URL, progress, asked)
          asked += 1
          self.class.series_list(body) # the defense, before the page lands
          write_atomic!(top, body)
        end
        series = self.class.series_list(SourceRead.utf8_file(top, label: "niupepa census"))
        series.each do |entry|
          path = map_path(workdir, format(LISTING_FILE, entry.index))
          next if File.file?(path)

          body = census_get!(format(LISTING_URL, n: entry.index), progress, asked)
          asked += 1
          defend_listing!(entry, body)
          write_atomic!(path, body)
        end
        @universe.delete(workdir)
        @sleeper.call(@delay) if asked.positive? && @delay.positive?
        held = census(workdir)
        "census #{held[:series].size} series / #{held[:series].sum(&:count)} listed documents = " \
          "#{held[:issues].size} issues + #{held[:commentaries].size} commentaries (rejected grain)" \
          "#{asked.positive? ? " — #{asked} census GET(s)" : ' — held census reused'}"
      end

      def census_get!(url, progress, asked)
        @sleeper.call(@delay) if asked.positive? && @delay.positive?
        progress&.call("niupepa census: #{url}\n")
        response, = Nabu::RedirectFollow.get(url, http: @http, error: Nabu::FetchError,
                                                  headers: { "User-Agent" => Nabu::WikiFetch::USER_AGENT })
        response.body.to_s.dup.force_encoding(Encoding::UTF_8)
      end

      # A listing must carry exactly the count its series label states, and
      # every listed oid must be an issue or a commentary.
      def defend_listing!(entry, body)
        listed = self.class.listing(body)
        unless listed.size == entry.count
          raise FetchError, "niupepa listing CL1.#{entry.index} (#{entry.label}) is TRUNCATED: the label " \
                            "states #{entry.count} document(s), the listing carries #{listed.size} — retry"
        end
        strange = listed.map(&:oid).reject { |oid| oid.match?(ISSUE_ID) || oid.match?(COMMENTARY_ID) }
        return if strange.empty?

        raise FetchError, "niupepa listing CL1.#{entry.index} carries unrecognized oid(s) #{strange.join(', ')}"
      end

      def universe(workdir)
        @universe[workdir] ||= census(workdir)&.fetch(:issues) || []
      end

      # -- the crawl ---------------------------------------------------------

      def abort_outage!(report)
        ids = report.outage[:ids]
        raise FetchError, "niupepa crawl aborted — upstream outage: #{ids.size} consecutive issue(s) " \
                          "failed (#{ids.join(', ')}); nothing ledgered for the run, the next sync resumes here"
      end

      # One GET → a PacedCrawl::Outcome: :ok (the issue held), :denied
      # (403/404, or a 200 that is not this issue's page XML), :empty (no
      # page carries text), :timeout (transport timeout, or the
      # server-error subclass for a 5xx). A held issue (the engine's
      # re-probe) is never overwritten.
      def fetch_issue!(workdir, id)
        response, = Nabu::RedirectFollow.get(
          format(ISSUE_URL, id), http: @http, error: Nabu::FetchError,
                                 accept: [200, *DENIED_STATUSES, *SERVER_ERRORS],
                                 headers: { "User-Agent" => Nabu::WikiFetch::USER_AGENT }
        )
        return outcome(:denied, response) if DENIED_STATUSES.include?(response.status)
        return outcome(:timeout, response, ledger_class: SERVER_ERROR) if SERVER_ERRORS.include?(response.status)

        body = response.body.to_s
        verdict = issue_verdict(body, id)
        store!(issue_path(workdir, id), body) if verdict == :ok
        outcome(verdict, response)
      rescue Nabu::FetchError => e
        raise unless e.message.match?(TIMEOUT_PATTERN)

        Nabu::PacedCrawl::Outcome.new(status: :timeout, evidence: { body_head: Nabu::PacedCrawl.body_head(e.message) })
      end

      def issue_verdict(body, id)
        xml = Nokogiri::XML(body)
        root = xml.at_xpath("//document/documentNode[@nodeType='root']")
        return :denied unless root && root["nodeID"] == id && node_metadata(root)["DocType"] == ISSUE_DOC_TYPE

        root.xpath(".//documentNode[@nodeType='leaf']").any? { |page| !page_text(page).empty? } ? :ok : :empty
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

      def map_path(workdir, name) = File.join(workdir, MAP_DIRNAME, name)

      def issue_path(workdir, id) = File.join(workdir, ISSUES_DIRNAME, "#{id}.xml")

      def held_ids(workdir)
        Dir.glob(File.join(workdir, ISSUES_DIRNAME, "*.xml")).map { |path| File.basename(path, ".xml") }.sort
      end

      # The crawl identity: the census bytes, the held issues, the ledgered
      # classes (last_slice is derived, never identity).
      def crawl_sha(workdir, held, ledger)
        census = Dir.glob(File.join(workdir, MAP_DIRNAME, "*.html")).map do |path|
          [File.basename(path), Digest::SHA256.file(path).hexdigest]
        end
        classes = LEDGER_CLASSES.map { |key| ledger.fetch(key, []).sort }
        Digest::SHA256.hexdigest(JSON.generate([census, held, *classes]))
      end

      # -- discovery ---------------------------------------------------------

      def scan(workdir)
        refs = []
        skipped = []
        unrecognized = []
        Dir.glob(File.join(workdir, ISSUES_DIRNAME, "*")).each do |path|
          next unless File.file?(path)

          name = File.basename(path)
          oid = name.delete_suffix(".xml")
          if !name.end_with?(".xml")
            unrecognized << "#{ISSUES_DIRNAME}/#{name}: not an issue XML"
          elsif oid.match?(COMMENTARY_ID)
            skipped << "#{ISSUES_DIRNAME}/#{name}: a series commentary (modern English bibliographic prose) " \
                       "— rejected grain, skipped by rule"
          elsif oid.match?(ABSTRACT_ID)
            skipped << "#{ISSUES_DIRNAME}/#{name}: an issue abstract (modern English summary) — rejected " \
                       "grain, skipped by rule"
          elsif oid.match?(ISSUE_ID)
            refs << Nabu::DocumentRef.new(source_id: SLUG, id: "#{URN_PREFIX}#{oid}",
                                          path: File.expand_path(path), metadata: { "oid" => oid })
          else
            unrecognized << "#{ISSUES_DIRNAME}/#{name}: not a Greenstone issue oid"
          end
        end
        { refs: refs, skipped: skipped, unrecognized: unrecognized + stray_files(workdir) }
      end

      # Files outside issues/ and the census (dotfiles — the ledger — and
      # the attic excepted).
      def stray_files(workdir)
        Dir.glob(File.join(workdir, "**", "*"))
           .select { |path| File.file?(path) }
           .reject { |path| path.include?("/#{ATTIC_DIRNAME}/") || File.basename(path).start_with?(".") }
           .reject { |path| path.start_with?(File.join(workdir, ISSUES_DIRNAME, "")) }
           .grep_v(%r{/#{MAP_DIRNAME}/CL1(?:\.\d+)?\.html\z})
           .reject { |path| File.basename(path).casecmp?("readme.md") }
           .map { |path| "#{path.delete_prefix("#{workdir}/")}: non-corpus file" }
      end

      # -- parse internals ---------------------------------------------------

      def read_issue(path)
        Nokogiri::XML(SourceRead.utf8_file(path, label: "niupepa issue"), &:strict)
      rescue Nokogiri::XML::SyntaxError, Errno::ENOENT => e
        raise ParseError, "#{path}: unreadable issue XML: #{e.message}"
      end

      def issue_root!(xml, ref)
        root = xml.at_xpath("//document/documentNode[@nodeType='root']")
        oid = ref.metadata.fetch("oid")
        return root if root && root["nodeID"] == oid

        raise ParseError, "#{ref.path}: no root documentNode for issue #{oid}"
      end

      def node_metadata(node)
        node.xpath("./metadataList/metadata").each_with_object({}) do |entry, out|
          out[entry["name"]] ||= entry.text.strip
        end
      end

      # The page's <pre> text (escaped HTML inside nodeContent): lines keep
      # their layout, trailing whitespace and blank edges trimmed.
      def page_text(page)
        html = page.at_xpath("./nodeContent")&.text.to_s
        lines = Nokogiri::HTML.fragment(html).text.split("\n").map(&:rstrip)
        lines.shift while lines.first&.strip&.empty?
        lines.pop while lines.last&.strip&.empty?
        Normalize.nfc(lines.join("\n"))
      end

      def section_number(page, oid)
        page["nodeID"].to_s.delete_prefix("#{oid}.")
      end

      def series_parts(series)
        run = series.to_s[SERIES_RUN, 1]
        [run ? series.sub(SERIES_RUN, "") : series, run]
      end

      def date_for(raw)
        match = ISSUE_DATE.match(raw.to_s)
        return nil unless match

        year = Integer(match[1], 10)
        iso = [match[1], match[2], match[3]].compact.join("-")
        { "not_before" => year, "not_after" => year, "raw" => iso }
      end

      def title_for(meta)
        name, = series_parts(text(meta["Series"]))
        date = date_for(meta["Date"])
        [[name, text(meta["Title"])].compact.join(" — "), date && "(#{date['raw']})"].compact.join(" ")
      end

      def metadata_for(oid, meta, page_count, textless)
        series = text(meta["Series"])
        name, run = series_parts(series)
        issue = text(meta["Title"])
        {
          "oid" => oid, "series" => series, "series_title" => name, "series_run" => run,
          "issue" => issue, "volume" => issue&.[](/Volume (\w+)/, 1), "number" => issue&.[](/Number (\w+)/, 1),
          "date" => date_for(meta["Date"]), "date_raw" => text(meta["Date"]),
          "pages" => page_count, "pages_without_text" => textless.zero? ? nil : textless,
          "abstract_oid" => text(meta["abstract"]), "commentary_oid" => text(meta["commentary"]),
          "permalink" => format(PERMALINK, oid), "text_nature" => "machine-ocr",
          "facets" => name ? { "series" => { "values" => [name] } } : nil
        }.compact
      end

      def text(value)
        stripped = value.to_s.strip
        stripped.empty? ? nil : Normalize.nfc(stripped)
      end
    end
  end
end

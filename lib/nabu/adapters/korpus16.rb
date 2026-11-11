# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "nokogiri"

require_relative "../paced_crawl"
require_relative "../redirect_follow"
require_relative "../zip_fetch"
require_relative "../normalize"
require_relative "source_read"
require_relative "korpus16_page_parser"

module Nabu
  module Adapters
    # korpus16 (02-sources row 386): Korpus 16 — Korpus besedil slovenskih
    # protestantskih piscev 16. stoletja, the corpus of the 16th-century
    # Slovene Protestant writers (Inštitut za slovenski jezik Frana Ramovša
    # ZRC SAZU, ed. Kozma Ahačič with Andreja Legan Ravnikar and Alenka
    # Jelovšek; version 1.0, Ljubljana 2019, the Fran collection;
    # fran.si/korpus16). The whole Slovene book production of the
    # Reformation, 1550–1595: Trubar, Dalmatin, Krelj, Juričič, Tulščak,
    # Trošt, Felicijan Trubar, Znojilšek — catechisms, primers, the New
    # Testament and Dalmatin's 1584 Bible, psalters, hymnals, postils,
    # prayer books, the church order and the agenda.
    #
    # == A KEYED TRANSCRIPTION, NOT OCR (declared)
    #
    # The Info page, verbatim in substance: hand transcription by
    # CyberData India by double keying (two keyers type the same text, a
    # third reconciles the differences), then a review against the prints
    # (students + researchers on the hard spots), then conversion to TEI.
    # "Evidentnih napak v zapisu nismo popravljali" — evident misprints are
    # NOT corrected, misnumbered pages are kept as text, "#" marks an
    # illegible or typographically special spot, doubled w is keyed "vv",
    # most ligatures are resolved (æ > ae) but the tilde for m/n is kept.
    # Every document carries text_nature "double-keyed transcription";
    # nothing is corrected here either (canonical means canonical). The
    # portal's own caveat: errors remain possible; corrections are being
    # gathered ("Prepise še izpopolnjujemo").
    #
    # == License (read first-hand 2026-11-05, fran.si/korpus16/o-portalu?page=Colofon)
    #
    # Verbatim: "To delo je dostopno pod licenco Creative Commons Priznanje
    # avtorstva-Deljenje pod enakimi pogoji 4.0" (link:
    # creativecommons.org/licenses/by-sa/4.0/) → license_class
    # attribution (CC BY-SA 4.0). Cite: "Korpus 16: Korpus besedil
    # slovenskih protestantskih piscev 16. stoletja. Različica 1.0,
    # www.fran.si/korpus16". The colophon also records that the
    # transcription of the biblical books of Dalmatin's 1584 Bible (without
    # the accompanying texts) was contributed by Svetopisemska družba
    # Slovenije (the Bible Society of Slovenia) — carried as
    # transcription_credit on that document; the work-level license covers
    # the publication as a whole.
    #
    # == Why a crawl (CLARIN.SI re-checked 2026-11-05)
    #
    # The colophon promises "Baza korpusa bo v kratkem dostopna v
    # repozitoriju CLARIN.SI" — its link points at hdl 11356/1166, the
    # Thesaurus of Modern Slovene, an unrelated record. A full OAI-PMH
    # harvest of the CLARIN.SI repository (1,362 records, 2026-11-05)
    # holds no Korpus 16 deposit — only its satellites (besedje16
    # 11356/1127, the Trubar Matthew concordance 11356/1124, the Franček
    # historical module 11356/1472). So the portal's reading pages are the
    # only public delivery; robots.txt disallows only /iskanje/ (search).
    #
    # == Delivery grains (census 2026-11-05) and the reconciliation
    #
    # - the corpus index (/korpus16): 45 books, each tiled twice (the
    #   all-authors tab and its author tab — Trubar / Dalmatin / Ostali);
    #   deduplicated by the book id. Kept at map/korpus16.html.
    # - the book (/korpus16/Knjiga/<id>/<slug>): there is no separate TOC
    #   grain — the book is its pages; page 1 carries the book header
    #   (siglum, author/editor, title, "Place, Year") and the pager whose
    #   max is the page count. Document = book.
    # - the page (?stran=<n>): the ACCEPTED passage grain — one reading
    #   page = one print page (or the portal's blank-page placeholder).
    # - the portal pages (o-portalu?page=Info / Colofon / Bibliography):
    #   front matter — Info states the advertised size, Colofon the
    #   license, Bibliography the 45-row catalogue. REJECTED as text,
    #   kept at map/about-<page>.html as license/count provenance and
    #   skipped by rule in discovery_skips. (News carries one line; not
    #   fetched.)
    # - search (/iskanje/): robots-disallowed, never touched.
    #
    # Reconciliation: Info says "obsega prepise 45 knjižnih del na 12.945
    # straneh"; the index lists 45 book ids (4–58, gaps upstream's), and
    # the 45 page-1 pagers sum to exactly 12,945 (censused 2026-11-05) —
    # accepted + skipped-by-rule = upstream's count with no residue. Every
    # fetch re-reads Info and the index and states both numbers in its
    # notes. Passages ≤ 12,945: a page with no body text (the portal's
    # blank-page placeholders, e.g. TM 1555's p. 7) mints nothing and is
    # listed in the document's blank_pages.
    #
    # Out of the corpus by upstream's own scope (Info): Bohorič's 1580
    # Otrozhia tabla leaflet, his mostly Latin 1584 grammar, foreign-
    # language works with single Slovene words, Megiser's dictionaries
    # (1592, 1603); and longer German/Latin passages inside the books are
    # not yet transcribed. Short German/Latin/Italian title blocks and
    # epigraphs ARE keyed (TM 1555's Italian epigraph, TPs 1579's German
    # title) — the HTML carries no language tag, so every passage reads
    # sl: deliberately coarse, declared.
    #
    # == The paced, resumable crawl (the paced-crawl rail, architecture §19)
    #
    # Per sync: the index (rewritten only when changed; zero books
    # aborts) and the three portal pages, then the PAGE_CRAWL lane on
    # Nabu::PacedCrawl. Its universe is one id per reading page, in book
    # id order: the bare book id is the book's page 1 — the sizing
    # request — and once page 1 is held its pager adds "<book>:<n>" for
    # pages 2..max. The universe therefore GROWS as page 1s land; the
    # engine fixes a slice's selection at its start, so #fetch re-slices
    # with the budget left while a slice sized new pages (SLICE requests
    # per sync in all). held = books/<id>/<nnnnn>.html on disk (a killed
    # run loses at most the page in flight); the engine owns selection,
    # pacing (DELAY between requests), the timeout policy and the ledger.
    # Terminal answers are ledgered in .korpus16-crawl.json and never
    # retried: 403/404/410 "refused" (a refused page 1 refuses the whole
    # book — it never sizes), a 200 that is no reading page "not-reading",
    # a page timing out timeout_attempts times "timeout-stuck". A 429 is
    # the clean stop (Outcome.halt): the slice ends, the page stays
    # selectable, the next sync resumes there. A 5xx retries RETRIES
    # times with backoff, then aborts the sync. The ledger keeps the shape
    # the hand-rolled crawl wrote — refused books and refused pages per
    # book — through LedgerCodec, the new classes beside it. Pages land as
    # the raw bytes upstream served (~16 KB each, ~210 MB for the corpus).
    # Sizing: 12,945 pages ≈ 3.6 h at 1 req/s plus latency; SLICE covers
    # the whole corpus in one detached run.
    #
    # == Documents and passages
    #
    # One document per book, discovered only once its crawl is COMPLETE
    # (every page on disk or ledgered) — a partial book never mints a
    # partial document (discovery_skips names it). urn =
    # urn:nabu:korpus16:<book id>; one passage per page with text, cited
    # by the page index (…:58:200). Text = the page's body blocks, one per
    # line (Korpus16PageParser); forme work rides annotations (folio — the
    # print's own page label "I,56a" — running_head, catchword,
    # signature), and the marginal notes ride annotations "notes" in page
    # order, OUT of the running text (declared: their anchors sit
    # mid-sentence).
    #
    # == Axes (aggressive mining)
    #
    # date — the header's print year (+ the siglum's "1581-82" span) →
    # {not_before, not_after, raw, class edition} (:structured). place —
    # the imprint place as the portal gives it (modern names: Tübingen,
    # Schwäbisch Hall, Regensburg, Ljubljana, Wittenberg), named. author
    # — the header name; "(ur.)" (urednik) → author_role editor, " in "
    # joins two editors. siglum — upstream's abbreviation (TC 1550, DB
    # 1584): the very sigla besedje16 (sl-lexica) cites per word, so a
    # word→page crosswalk is a mechanical join later. kind — folded per
    # siglum in config/kind_map.yml. lect — sl, staged sl:emod by the
    # source-level override in config/lect_overrides.yml (the corpus IS
    # Early Modern Slovene print; the 1550 books sit on the old/emod band
    # edge, where date inference would leave them bare).
    #
    # == Overlaps (ingested WITH provenance — keyed text beats OCR)
    #
    # mdz-protestant holds MDZ's uncorrected OCR of four of these prints
    # (TAr 1562 Articuli, DJ 1575 Jesus Sirah, DC 1584 Ta celi catehismus,
    # DM 1584 Karszanske lepe molitve; its Bohorič grammar and the
    # Croatian Spovid are outside this corpus). sl-wikisource holds the
    # Wikivir transcriptions of 1584 Dalmatin/Trubar pages; goo300k/imp
    # hold Dalmatin's 1584 Biblia (ZRC_00001-1584). Different layers of
    # the same prints: never deduped at parse — the keyed transcription
    # here is the stronger witness; dedupe is a catalog-side concern.
    class Korpus16 < Nabu::Adapter
      BASE_URL = "https://fran.si"
      INDEX_URL = "#{BASE_URL}/korpus16".freeze
      PORTAL_URL = "#{BASE_URL}/korpus16/o-portalu?page=%s".freeze
      BOOK_URL = "#{BASE_URL}/korpus16/Knjiga/%<id>s/%<slug>s".freeze
      PAGE_URL = "#{BOOK_URL}?stran=%<page>d".freeze
      PORTAL_PAGES = %w[Info Colofon Bibliography].freeze
      MAP_DIRNAME = "map"
      INDEX_FILE = "korpus16.html"
      BOOKS_DIRNAME = "books"
      LEDGER_FILE = ".korpus16-crawl.json"
      URN_PREFIX = "urn:nabu:korpus16:"
      LANGUAGE = "sl"
      TEXT_NATURE = "double-keyed transcription"

      # const: crawl politeness pause, not a corpus claim (~1 req/s). Never lower.
      DELAY = 1.0
      # Page requests per sync — the whole corpus (12,945 pages) in one detached run.
      SLICE = 15_000
      # Attempts for a 5xx (the timeout policy is the engine's).
      RETRIES = 3
      BACKOFF = 5.0
      STOP_NOTES = { slice: "slice limit reached — resume next sync",
                     rate_limited: "rate limited — resume next sync" }.freeze
      # The answers that refuse a page (ledgered "refused").
      REFUSED_STATUSES = [403, 404, 410].freeze
      RATE_LIMITED = 429
      TIMEOUT_PATTERN = /transport error for .*(timeout|timed out|execution expired)/i

      REFUSED = "refused"
      NOT_READING = "not-reading"
      STUCK = "timeout-stuck"

      # The page lane's ledger on disk. The "refused" class keeps the
      # hand-rolled crawl's shape: a book-level id (a refused page 1)
      # in "books", "<book>:<n>" as n under "pages"[book]; an id of
      # neither form lands in "books" verbatim (the codec is total and
      # lossless). The other classes are flat id arrays; any other
      # section passes through.
      module LedgerCodec
        LEGACY = %w[books pages].freeze
        PAGE_ID = /\A(.+):([1-9]\d*)\z/

        def self.load(raw)
          refused = Array(raw["books"]).to_set(&:to_s)
          pages = raw["pages"].is_a?(Hash) ? raw["pages"] : {}
          pages.each { |book, list| Array(list).each { |page| refused << "#{book}:#{page}" } }
          Nabu::PacedCrawl::FLAT_CODEC.load(raw.except(*LEGACY)).merge(REFUSED => refused)
        end

        def self.dump(classes, raw)
          books = []
          pages = Hash.new { |hash, book| hash[book] = [] }
          classes.fetch(REFUSED, []).each do |id|
            match = PAGE_ID.match(id)
            match ? pages[match[1]] << Integer(match[2], 10) : books << id
          end
          legacy = { "books" => books.uniq.sort_by { |id| order(id) },
                     "pages" => pages.sort_by { |book, _| order(book) }.to_h { |book, list| [book, list.uniq.sort] } }
          legacy.merge(Nabu::PacedCrawl::FLAT_CODEC.dump(classes.except(REFUSED), raw.except(*LEGACY)))
        end

        # Numeric ids in numeric order, anything else after them.
        def self.order(id) = id.match?(/\A\d+\z/) ? [0, Integer(id, 10), ""] : [1, 0, id]
      end

      # The page lane (see the header): the declared schedule is the
      # rail's default — the corpus is one detached run, so a phase
      # spends at most a few slices.
      PAGE_CRAWL = Nabu::PacedCrawl::Spec.new(
        name: "pages", ledger_file: LEDGER_FILE,
        classes: { denied: REFUSED, empty: NOT_READING, timeout: STUCK },
        delay: DELAY, slice: SLICE, timeout_backoff: BACKOFF, codec: LedgerCodec,
        schedule: Nabu::PacedCrawl::Schedule.new(cadence: :per_phase, slices_per_phase: 3, stop_after_zero_slices: 3)
      )

      # The union of every ledger class: book-level refusals and
      # ledgered pages per book (what discovery and the notes read).
      Ledger = Data.define(:books, :pages)

      BOOK_HREF = %r{\A/korpus16/Knjiga/(\d+)/([^?/#]+)}
      ADVERTISED = /prepise\s+(\d+)\s+knjižnih\s+del\s+na\s+([\d.]+)\s+straneh/

      # The colophon's one per-book provenance statement.
      CREDITS = {
        "DB 1584" => "Colophon: the transcription of the biblical books of Dalmatin's 1584 Bible (without " \
                     "the accompanying texts) was contributed by Svetopisemska družba Slovenije " \
                     "(the Bible Society of Slovenia)"
      }.freeze

      Book = Data.define(:id, :slug, :label)

      MANIFEST = Nabu::SourceManifest.new(
        id: "korpus16",
        name: "Korpus 16 — the 16th-century Slovene Protestant writers (ZRC SAZU, fran.si)",
        license: "Colophon, verbatim: \"To delo je dostopno pod licenco Creative Commons Priznanje " \
                 "avtorstva-Deljenje pod enakimi pogoji 4.0\" (CC BY-SA 4.0). Cite \"Korpus 16: Korpus " \
                 "besedil slovenskih protestantskih piscev 16. stoletja. Različica 1.0, www.fran.si/korpus16\" " \
                 "(Inštitut za slovenski jezik Frana Ramovša ZRC SAZU; Založba ZRC, 2019)",
        license_class: "attribution",
        upstream_url: "https://fran.si/korpus16",
        parser_family: "korpus16-html"
      )

      def self.manifest = MANIFEST

      def self.remote_probe_strategy = :http_zip

      def self.http_probe_targets
        [Nabu::Adapter::HttpProbeTarget.new(
          label: "Korpus 16 index", zip_url: INDEX_URL, metadata_url: nil,
          state_subdir: "", liveness_only: true
        )]
      end

      # The header's "(ur.)" (urednik, editor) and " in " (and) →
      # [names "; "-joined, role or nil].
      def self.people(statement)
        names = statement.to_s.strip
        role = nil
        if names.match?(/\s*\(ur\.\)\z/)
          role = "editor"
          names = names.sub(/\s*\(ur\.\)\z/, "")
        end
        [names.split(" in ").map(&:strip).join("; "), role]
      end

      # +books+ narrows the crawl to the named book ids (the fixture
      # recipe and the tests' seam); nil crawls the whole index.
      def initialize(delay: DELAY, slice: SLICE, http: Nabu::ZipFetch.default_http, books: nil, backoff: BACKOFF)
        super()
        @delay = delay
        @slice = slice
        @http = http
        @books = books&.map(&:to_s)
        @backoff = backoff
        @last_request_at = nil
        @page_counts = {}
        @index_books = {}
      end

      # -- fetch -------------------------------------------------------------

      # +force+ is part of the fetch interface; nothing here ever deletes.
      def fetch(workdir, progress: nil, force: false) # rubocop:disable Lint/UnusedMethodArgument
        FileUtils.mkdir_p(workdir)
        books = refresh_index!(workdir, progress)
        PORTAL_PAGES.each { |name| refresh_portal!(workdir, name) }
        reports = crawl_slices!(workdir, progress)
        ledger = ledger_view(workdir)
        notes = crawl_notes(workdir, books, crawl_set(books), ledger, reports)
        progress&.call("#{notes}\n")
        notes = [notes, *reports.last.lines].join("; ")
        Nabu::FetchReport.new(sha: crawl_sha(workdir, ledger), fetched_at: Time.now, notes: notes)
      end

      # The chain runner's seam (rake crawl:chain): the one paced lane.
      def paced_crawls(workdir, progress: nil)
        { PAGE_CRAWL.name => page_crawl(workdir, progress: progress) }
      end

      # The page lane's engine over +workdir+ (PAGE_CRAWL retuned by this
      # instance's knobs; +slice+ overrides the budget). Public so an
      # offline surface can #diagnose the crawl without crawling.
      def page_crawl(workdir, progress: nil, slice: @slice)
        Nabu::PacedCrawl::Engine.new(
          spec: PAGE_CRAWL.with(delay: @delay, slice: slice, timeout_backoff: @backoff),
          dir: workdir, progress: progress,
          universe: -> { page_universe(workdir) },
          held: ->(id) { File.file?(page_path(workdir, *split_id(id))) },
          fetch_one: ->(id) { fetch_page!(workdir, id) }
        )
      end

      # -- discover ----------------------------------------------------------

      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        ledger = ledger_view(workdir)
        index_books(workdir).each do |book|
          next unless complete?(workdir, book, ledger)

          block.call(Nabu::DocumentRef.new(
                       source_id: MANIFEST.id, id: "#{URN_PREFIX}#{book.id}",
                       path: File.expand_path(page_path(workdir, book.id, 1)),
                       metadata: { "book" => book.id, "slug" => book.slug }
                     ))
        end
      end

      def discovery_skips(workdir)
        ledger = ledger_view(workdir)
        listed = index_books(workdir)
        held = book_dirs(workdir)
        by_rule = listed.select { |book| held.include?(book.id) }
                        .filter_map { |book| incomplete_note(workdir, book, ledger) }
        by_rule += PORTAL_PAGES.filter_map do |name|
          rel = File.join(MAP_DIRNAME, "about-#{name}.html")
          "portal page #{rel}: front matter, not corpus text" if File.file?(File.join(workdir, rel))
        end
        strays = held - listed.map(&:id)
        Nabu::Adapter::DiscoverySkips.new(
          skipped_by_rule: by_rule.size, unrecognized: strays.size,
          notes: by_rule + strays.map { |id| "book directory not in the index: #{BOOKS_DIRNAME}/#{id}" }
        )
      end

      # -- parse -------------------------------------------------------------

      def parse(document_ref)
        workdir = File.dirname(document_ref.path, 3)
        id = document_ref.metadata.fetch("book")
        first_html = read_page(document_ref.path)
        first = parser.parse(first_html)
        metadata = book_metadata(first_html, book_id: id, slug: document_ref.metadata.fetch("slug"))
        pages, accounting = read_pages(workdir, id, first, ledger_view(workdir))
        document = Nabu::Document.new(urn: document_ref.id, language: LANGUAGE, title: first.header.title,
                                      canonical_path: document_ref.path, metadata: metadata.merge(accounting))
        pages.each do |number, page|
          document << Nabu::Passage.new(urn: "#{document.urn}:#{number}", language: LANGUAGE, text: page.text,
                                        sequence: document.size, annotations: annotations_for(page))
        end
        raise ParseError, "#{document_ref.path}: no page carries body text" if document.empty?

        document
      rescue Nabu::ValidationError => e
        raise ParseError, "#{document_ref.path}: #{e.message}"
      end

      # The book-level metadata from any of its reading pages' header.
      def book_metadata(html, book_id:, slug:)
        header = parser.parse(html).header
        raise ParseError, "korpus16 book #{book_id}: the page carries no book header" if header.nil?

        author, role = self.class.people(header.author)
        {
          "book_id" => book_id, "slug" => slug, "siglum" => header.siglum,
          "author" => author, "author_role" => role, "statement_of_responsibility" => header.author,
          "imprint" => header.imprint, "place" => imprint_place(header.imprint),
          "date" => date_envelope(header.imprint, header.siglum),
          "permalink" => format(BOOK_URL, id: book_id, slug: slug),
          "text_nature" => TEXT_NATURE, "transcription_credit" => CREDITS[header.siglum]
        }.compact
      end

      private

      # -- fetch internals ---------------------------------------------------

      def refresh_index!(workdir, progress)
        progress&.call("Korpus 16 index…\n")
        body = utf8_body(get_with_retries!(INDEX_URL, accept: [200]))
        books = parse_index(body)
        raise FetchError, "korpus16: the index lists no books — upstream shape changed" if books.empty?

        write_if_changed!(File.join(workdir, MAP_DIRNAME, INDEX_FILE), body)
        books
      end

      def refresh_portal!(workdir, name)
        body = utf8_body(get_with_retries!(format(PORTAL_URL, name), accept: [200]))
        write_if_changed!(File.join(workdir, MAP_DIRNAME, "about-#{name}.html"), body)
      end

      def crawl_set(books)
        @books ? books.select { |book| @books.include?(book.id) } : books
      end

      # The page lane's slices for one sync, under ONE budget of @slice
      # requests: a slice that sized books (its page 1s landed) leaves
      # their pages selectable only for the next slice, so the sync
      # re-slices with the budget left. Stops on a clean stop, a spent
      # budget, or nothing left to select.
      def crawl_slices!(workdir, progress)
        budget = @slice
        reports = []
        loop do
          report = page_crawl(workdir, progress: progress, slice: budget).slice!
          reports << report
          report.lines.each { |line| progress&.call("#{line}\n") }
          budget -= report.attempted
          break if report.halted? || budget <= 0 || report.attempted.zero? || report.remaining[:after].zero?
        end
        reports
      end

      # "<book>" is the book's page 1; "<book>:<n>" its page n.
      def split_id(id)
        book, sep, page = id.to_s.rpartition(":")
        sep.empty? ? [id.to_s, 1] : [book, Integer(page, 10)]
      end

      # Every reading page, book by book in id order: page 1 (the bare
      # book id) until it is held, then the pages its pager names.
      def page_universe(workdir)
        crawl_set(index_books(workdir)).flat_map do |book|
          next [book.id] unless File.file?(page_path(workdir, book.id, 1))

          [book.id, *(2..page_count(workdir, book.id)).map { |page| "#{book.id}:#{page}" }]
        end
      end

      # One page GET → a PacedCrawl::Outcome. An already-held page (the
      # engine's held-id re-probe) is never overwritten: the probe answers
      # liveness, canonical stays.
      def fetch_page!(workdir, id)
        book_id, page = split_id(id)
        book = index_books(workdir).find { |listed| listed.id == book_id } or
          raise FetchError, "korpus16: #{id} names a book the index does not list"
        response = get_with_retries!(format(PAGE_URL, id: book.id, slug: book.slug, page: page),
                                     accept: [200, *REFUSED_STATUSES, RATE_LIMITED], timeouts: false)
        return rate_limited(response) if response.status == RATE_LIMITED
        return page_outcome(:denied, response) if REFUSED_STATUSES.include?(response.status)

        body = utf8_body(response)
        return page_outcome(:empty, response) unless parser.reading_page?(body)

        path = page_path(workdir, book.id, page)
        write_atomic!(path, body) unless File.file?(path)
        page_outcome(:ok, response)
      rescue Nabu::FetchError => e
        raise unless e.message.match?(TIMEOUT_PATTERN)

        Nabu::PacedCrawl::Outcome.new(status: :timeout, evidence: { body_head: Nabu::PacedCrawl.body_head(e.message) })
      end

      def rate_limited(response)
        Nabu::PacedCrawl::Outcome.halt(reason: "HTTP 429 (rate limited)",
                                       evidence: { http_status: response.status,
                                                   retry_after: response.headers["retry-after"] }.compact)
      end

      def page_outcome(status, response)
        Nabu::PacedCrawl::Outcome.from_body(status, http_status: response.status, body: utf8_body(response))
      end

      # A 5xx (or any non-accepted answer) is retried RETRIES times with
      # backoff; +timeouts+ false hands a transport timeout straight up
      # (the page lane's timeout policy is the engine's).
      def get_with_retries!(url, accept:, timeouts: true)
        attempt = 0
        begin
          attempt += 1
          get!(url, accept: accept)
        rescue Nabu::FetchError => e
          raise if attempt >= RETRIES || (!timeouts && e.message.match?(TIMEOUT_PATTERN))

          pause = @backoff * (2**(attempt - 1))
          sleep(pause) if pause.positive?
          retry
        end
      end

      # Request STARTS are spaced DELAY apart (latency counts toward the
      # pause): ~1 req/s, never faster.
      def get!(url, accept:)
        if @delay.positive? && @last_request_at
          pause = @delay - (Process.clock_gettime(Process::CLOCK_MONOTONIC) - @last_request_at)
          sleep(pause) if pause.positive?
        end
        @last_request_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        response, = Nabu::RedirectFollow.get(
          url, http: @http, error: Nabu::FetchError, accept: accept,
               headers: { "User-Agent" => Nabu::WikiFetch::USER_AGENT }
        )
        response
      end

      def utf8_body(response) = response.body.to_s.dup.force_encoding(Encoding::UTF_8)

      def write_if_changed!(path, body)
        return if File.file?(path) && Digest::SHA256.file(path).hexdigest == Digest::SHA256.hexdigest(body)

        write_atomic!(path, body)
      end

      def write_atomic!(path, body)
        FileUtils.mkdir_p(File.dirname(path))
        File.binwrite("#{path}.tmp", body)
        File.rename("#{path}.tmp", path)
      end

      def crawl_notes(workdir, books, crawl, ledger, reports)
        sized = crawl.select { |book| File.file?(page_path(workdir, book.id, 1)) }
        total = sized.sum { |book| page_count(workdir, book.id) }
        held = sized.sum { |book| held_pages(workdir, book.id).size }
        ledgered = ledger.pages.values_at(*crawl.map(&:id)).compact.sum(&:size)
        complete = crawl.count { |book| complete?(workdir, book, ledger) }
        unsized = crawl.size - sized.size
        written = reports.sum(&:ok)
        parts = ["crawl at #{held}/#{total} page(s)#{" (+#{unsized} book(s) not yet sized)" if unsized.positive?}; " \
                 "#{complete}/#{crawl.size} book(s) complete (+#{written} page(s) this sync)"]
        parts << STOP_NOTES[stop_reason(reports.last)]
        parts << "#{ledgered} page(s) ledgered" if ledgered.positive?
        parts << "#{ledger.books.size} book(s) refused" unless ledger.books.empty?
        parts << "#{advertised(workdir)}; the index lists #{books.size} book(s)"
        parts.compact.join("; ")
      end

      def advertised(workdir)
        path = File.join(workdir, MAP_DIRNAME, "about-Info.html")
        return "upstream's advertised size unread" unless File.file?(path)

        match = Nokogiri::HTML(SourceRead.utf8_file(path, label: "korpus16 Info")).text.match(ADVERTISED)
        return "upstream's advertised size unread" if match.nil?

        pages = Integer(match[2].delete("."), 10).to_s.reverse.scan(/\d{1,3}/).join(",").reverse
        "upstream advertises #{match[1]} books / #{pages} pages"
      end

      def crawl_sha(workdir, ledger)
        index = File.join(workdir, MAP_DIRNAME, INDEX_FILE)
        files = Dir.glob(File.join(workdir, BOOKS_DIRNAME, "*", "*.html"))
                   .map { |path| path.delete_prefix("#{workdir}/") }.sort
        Digest::SHA256.hexdigest(JSON.generate([File.file?(index) ? Digest::SHA256.file(index).hexdigest : "",
                                                files, ledger_identity(ledger)]))
      end

      # The ledger as the crawl identity hashes it: the hand-rolled
      # crawl's {"books", "pages"} shape (so an unchanged ledger keeps its
      # sha across the move onto the rail), over every class.
      def ledger_identity(ledger)
        { "books" => ledger.books.sort_by { |id| LedgerCodec.order(id) },
          "pages" => ledger.pages.sort_by { |id, _| LedgerCodec.order(id) }.to_h }
      end

      def stop_reason(report)
        return :rate_limited if report.halted?

        :slice if report.remaining[:after].positive?
      end

      # Every ledger class, read through the lane's codec (an unreadable
      # ledger reads blank, as the engine reads it).
      def ledger_view(workdir)
        path = File.join(workdir, LEDGER_FILE)
        raw = File.file?(path) ? JSON.parse(SourceRead.utf8_file(path, label: "korpus16 crawl ledger")) : {}
        raw = {} unless raw.is_a?(Hash)
        classes = LedgerCodec.load(raw.except(Nabu::PacedCrawl::LAST_SLICE))
        ids = PAGE_CRAWL.class_names.reduce(Set.new) { |all, klass| all | classes.fetch(klass, Set.new) }
        books = Set.new
        pages = Hash.new { |hash, id| hash[id] = [] }
        ids.each do |id|
          match = LedgerCodec::PAGE_ID.match(id)
          match ? pages[match[1]] << Integer(match[2], 10) : books << id
        end
        Ledger.new(books: books, pages: pages.to_h { |id, list| [id, list.uniq.sort] })
      rescue JSON::ParserError
        Ledger.new(books: Set.new, pages: {})
      end

      # -- index -------------------------------------------------------------

      def index_books(workdir)
        path = File.join(workdir, MAP_DIRNAME, INDEX_FILE)
        return [] unless File.file?(path)

        stamp = [File.mtime(path), File.size(path)]
        cached = @index_books[workdir]
        return cached.last if cached&.first == stamp

        books = parse_index(SourceRead.utf8_file(path, label: "korpus16 index"))
        @index_books[workdir] = [stamp, books]
        books
      end

      # Every tile links its book; the four tabs repeat them — first
      # sighting wins, upstream id order.
      def parse_index(html)
        books = {}
        Nokogiri::HTML(html).css("a[href]").each do |link|
          match = BOOK_HREF.match(link["href"].to_s)
          next if match.nil? || books.key?(match[1])

          books[match[1]] = Book.new(id: match[1], slug: match[2], label: Normalize.nfc(link["title"].to_s))
        end
        books.values.sort_by { |book| Integer(book.id, 10) }
      end

      # -- shared internals --------------------------------------------------

      def parser
        @parser ||= Korpus16PageParser.new
      end

      def page_path(workdir, id, page) = File.join(workdir, BOOKS_DIRNAME, id, format("%05d.html", page))

      def read_page(path) = SourceRead.utf8_file(path, label: "korpus16 page")

      def book_dirs(workdir)
        root = File.join(workdir, BOOKS_DIRNAME)
        return [] unless Dir.exist?(root)

        dirs = Dir.children(root).select { |child| File.directory?(File.join(root, child)) }
        dirs.sort_by { |id| id.match?(/\A\d+\z/) ? [0, Integer(id, 10), ""] : [1, 0, id] }
      end

      def held_pages(workdir, id)
        Dir.glob(File.join(workdir, BOOKS_DIRNAME, id, "*.html")).filter_map do |path|
          name = File.basename(path, ".html")
          Integer(name, 10) if name.match?(/\A\d+\z/)
        end
      end

      # The book's page count from its page 1 pager (a pager-less page 1
      # is a one-page book).
      def page_count(workdir, id)
        @page_counts[id] ||= parser.parse(read_page(page_path(workdir, id, 1))).page_count || 1
      end

      def missing_pages(workdir, book, ledger)
        return [] if ledger.books.include?(book.id)
        return [1] unless File.file?(page_path(workdir, book.id, 1))

        done = held_pages(workdir, book.id) + ledger.pages.fetch(book.id, [])
        (1..page_count(workdir, book.id)).to_a - done
      end

      def complete?(workdir, book, ledger)
        return false if ledger.books.include?(book.id) || !File.file?(page_path(workdir, book.id, 1))

        missing_pages(workdir, book, ledger).empty?
      end

      def incomplete_note(workdir, book, ledger)
        return "book #{book.id}: page 1 refused upstream (ledgered)" if ledger.books.include?(book.id)

        first = page_path(workdir, book.id, 1)
        return "crawl incomplete: book #{book.id} (page count unknown)" unless File.file?(first)

        missing = missing_pages(workdir, book, ledger).size
        return nil if missing.zero?

        siglum = parser.parse(read_page(first)).header&.siglum
        "crawl incomplete: book #{book.id}#{" #{siglum}" if siglum} (#{missing} page(s) to go)"
      end

      # -- parse internals ---------------------------------------------------

      # [[page number, parsed page] for every held page with body text,
      #  the page accounting for the document metadata].
      def read_pages(workdir, id, first, ledger)
        count = first.page_count || 1
        blank = []
        pages = (1..count).filter_map do |number|
          path = page_path(workdir, id, number)
          next unless File.file?(path)

          page = number == 1 ? first : parser.parse(read_page(path))
          blank << number if page.text.empty?
          [number, page] unless page.text.empty?
        end
        accounting = { "page_count" => count, "blank_pages" => blank,
                       "ledgered_pages" => ledger.pages.fetch(id, []) }
        [pages, accounting.reject { |_, value| value.respond_to?(:empty?) && value.empty? }]
      end

      def annotations_for(page)
        {
          "folio" => page.folio, "running_head" => page.running_head,
          "catchword" => page.catchword, "signature" => page.signature,
          "notes" => page.notes.empty? ? nil : page.notes
        }.merge(page.other_forme_work).compact
      end

      def imprint_place(imprint)
        place, sep, = imprint.to_s.rpartition(",")
        place = place.strip
        sep.empty? || place.empty? ? nil : place
      end

      def date_envelope(imprint, siglum)
        years = imprint.to_s.scan(/\b(1\d{3})\b/).flatten.map { |year| Integer(year, 10) }
        siglum_years = siglum_years(siglum)
        all = (years + siglum_years).uniq
        return nil if all.empty?

        raw = (siglum_years - years).empty? ? imprint : "#{imprint} (siglum #{siglum})"
        { "not_before" => all.min, "not_after" => all.max, "raw" => raw, "class" => "edition" }
      end

      # "TT 1581-82" → [1581, 1582]; "TC 1550" → [1550].
      def siglum_years(siglum)
        match = siglum.to_s.match(/\b(1\d{3})(?:-(\d{2}))?\b/)
        return [] if match.nil?

        first = Integer(match[1], 10)
        match[2] ? [first, ((first / 100) * 100) + Integer(match[2], 10)] : [first]
      end
    end
  end
end

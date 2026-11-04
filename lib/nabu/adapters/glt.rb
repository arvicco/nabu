# frozen_string_literal: true

require "uri"

require_relative "../glt_fetch"
require_relative "glt_html_parser"
require_relative "source_read"

module Nabu
  module Adapters
    # GLT — Greek Orthodox Liturgical Texts (glt.goarch.org): the Greek
    # Orthodox Archdiocese of America's site of the Byzantine-rite service
    # books in Greek, compiled and maintained by Fr. Leo Schefe. The
    # liturgical cycle the books transmit, one page per service: the twelve
    # Menaia (the fixed feasts, day by day), the Octoechos (the eight-tone
    # weekly cycle, with the eleven Eothina and the Theotokia), the Triodion
    # (the pre-Lenten and Lenten cycle through Holy Week) and the
    # Pentecostarion (Pascha to All Saints), the Horologion (Vespers,
    # Compline, the Midnight Office, the Hours, Orthros, the Divine
    # Liturgies of Chrysostom, Basil, the Presanctified and James, the
    # Akathist, the Paraklesis) and the Euchologion (the blessing of water,
    # baptism, marriage, unction, the Trisagion and the funeral), plus a
    # Synekdemos shelf (Katabasiai, Megalynaria, the Orthros enkolpion).
    #
    # == License
    #
    # Permission by email from the site maintainer (Fr. Leo Schefe),
    # 2026-11-02: the texts are in the public domain and "you are welcome
    # to use them"; reports of errors in the texts are invited. → open.
    #
    # == The census (2026-11-04) and the crawl (Nabu::GltFetch)
    #
    # The site is static HTML behind Cloudflare: no bulk archive, no sitemap
    # (/sitemap.xml 404s), no directory listings (/texts/Sep/ 403s). Its two
    # index pages ARE the catalog: index.html (654 in-site texts/ links) and
    # extra.htm ("ΑΛΛΕΣ ΑΚΟΛΟΥΘΙΕΣ", the additional services — 75), together
    # 727 unique texts/ targets = 725 .html service pages + 1 .rtf + 1 .pdf.
    # The .html pages by shelf: Menaia 458 (Sep 41 · Oct 40 · Nov 36 · Dec
    # 58 · Jan 44 · Feb 40 · Mar 33 · Apr 30 · May 35 · Jun 32 · Jul 34 · Aug
    # 35), Och 81, Tri 70, Pen 60, Oro 47, Euch 6, Synek 3 (the .pdf sits
    # under Mar, the .rtf under Euch). Text pages are leaves (they link only
    # recordings, icons and the Archdiocese), so the crawl is index → pages:
    # GET the two index pages, then each listed .html once, paced 1 req/s
    # with a nabu User-Agent — ≈ 727 requests, ≈ 13 minutes plus transfer
    # (pages run 35–110 KB). Re-syncs are conditional GETs (If-Modified-
    # Since against each page's pinned Last-Modified), so an unchanged page
    # costs a 304. The site's robots.txt disallows /texts/ to all agents
    # (beside a Cloudflare-managed content-signal block); the crawl rests on
    # the maintainer's direct permission (License, above).
    #
    # The index's own labels are kept verbatim, grouping quirks included:
    # index.html lists the Typika (Oro/Typikon.html) after the Orthros
    # links, so its group reads ΟΡΘΡΟΣ.
    #
    # Grains (README in test/fixtures/glt/ enumerates them with specimens):
    # ACCEPTED — the texts/<shelf>/<page>.html service page = the document.
    # REJECTED, never fetched by the crawl and skipped by rule if present:
    # the catalog pages themselves (index.html, extra.htm — fetched and
    # kept as provenance; DISCOVERY skips them); the weekly-compiled daily
    # services (daily/, Lite/, Athos/, AthosJ/ — "Καθημερινὲς ἀκολουθίες",
    # regenerated every week from the same books: derivative and volatile,
    # specimen daily/Mon.html); the misc/ shelf (the lectionary scripture
    # books Evangelion/Apostolos/Psalter — biblical text, a widening
    # candidate — and the Automela-and-Heirmoi anthology with its English
    # apparatus, specimen misc/Prosomia.html); every non-HTML rendering
    # (the .epub twins, the Evangelion/Theotokarion/St Patrick PDFs, the
    # Greek+English funeral .rtf); the mp3 recordings (music/); the
    # external links (the Ecumenical Patriarchate's typikon, the GOARCH
    # kanonion).
    #
    # The site is Greek-only (no English translation halves exist beyond
    # the rejected .rtf and the Prosomia apparatus), so the adapter takes
    # the whole of what it fetches.
    #
    # == Document, passage, and the mined layers
    #
    # Document = one service page, urn:nabu:glt:<shelf>.<page> (lowercased,
    # spaces → "-": texts/Sep/Sep05.html → urn:nabu:glt:sep.sep05,
    # texts/Oro/Esperinos Sunday.html → urn:nabu:glt:oro.esperinos-sunday).
    # Passage = one LINE of the page (GltHtmlParser): a hymn, a petition, a
    # prayer, a verse, or a rubric — "<doc>:<n>", n from 1 in page order.
    # Rubrics are passages with role "rubric" (GltHtmlParser's ink rule);
    # each passage also carries, where the page states it:
    #   role       rubric | text | mixed (+ "rubrics": the inline spans)
    #   tone       the tone (1–8: α' β' γ' δ', πλ. α' 5, πλ. β' 6, βαρύς 7,
    #              πλ. δ' 8) of the LAST tone rubric above the passage on
    #              the page — cleared by a section heading (the coarseness
    #              is declared: a litany after the stichera inherits their
    #              tone until the next heading)
    #   section    the last all-capitals rubric heading above it
    #              (ΕΝ Τῼ ΕΣΠΕΡΙΝῼ, ΕΙΣ ΤΟΝ ΟΡΘΡΟΝ, ΑΦΟΡΚΙΣΜΟΣ Α')
    #   ink/bold   blue / green / bold where the whole line carries it
    #   recordings the model-melody mp3 paths a melody incipit links
    # Per document: book (the shelf), the index's own labels (list, group,
    # label — the titles are built from them), the page <title>, the URL;
    # Menaion pages add the commemoration (month from the shelf, day from
    # the page name, where the name carries one); the tone-cycle pages
    # (Och/ToneN*, Och/TheotokiaN, Tri/ToneN, Oro/SunN) their tone.
    #
    # Language grc: the books' hymnography and euchology are Byzantine
    # liturgical Greek (the lect posture: pending grc:byz, approximation).
    # Text is NFC at this boundary — the site's polytonic is keyed with the
    # Greek Extended OXIA vowels (U+1F71 …) and ANO TELEIA (U+0387), which
    # NFC folds canonically to the tonos vowels and U+00B7.
    class Glt < Nabu::Adapter
      SLUG = "glt"
      LANGUAGE = "grc"
      URN_PREFIX = "urn:nabu:glt:"
      BASE_URL = "https://glt.goarch.org/"
      TEXTS_DIR = "texts"

      Book = Data.define(:key, :title, :month)
      MONTHS = %w[Sep Oct Nov Dec Jan Feb Mar Apr May Jun Jul Aug].freeze
      MONTH_NUMBERS = MONTHS.each_with_index.to_h { |name, index| [name, ((index + 8) % 12) + 1] }.freeze
      # The site's shelf directories under texts/ (the index's own filing).
      BOOKS = {
        **MONTHS.to_h { |name| [name, Book.new(key: "Menaion", title: "Μηναῖον", month: MONTH_NUMBERS.fetch(name))] },
        "Och" => Book.new(key: "Octoechos", title: "Ὀκτώηχος", month: nil),
        "Tri" => Book.new(key: "Triodion", title: "Τριῴδιον", month: nil),
        "Pen" => Book.new(key: "Pentecostarion", title: "Πεντηκοστάριον", month: nil),
        "Oro" => Book.new(key: "Horologion", title: "Ὡρολόγιον", month: nil),
        "Euch" => Book.new(key: "Euchologion", title: "Εὐχολόγιον", month: nil),
        "Synek" => Book.new(key: "Synekdemos", title: "Συνέκδημος", month: nil)
      }.freeze

      CATALOG_PAGES = Nabu::GltFetch::CATALOG_PAGES
      # The file shapes the site serves (census 2026-11-04) — what discovery accounts for.
      SITE_EXTENSIONS = %w[.html .htm .epub .pdf .rtf .mp3].freeze
      # The rejected grains a canonical tree may carry (see the class comment).
      REJECTED_DIRS = {
        "daily" => "the weekly-compiled daily services (derivative of the books, regenerated weekly)",
        "Lite" => "the weekly-compiled daily services, LITE (derivative, regenerated weekly)",
        "Athos" => "the weekly-compiled monastic daily services (derivative, regenerated weekly)",
        "AthosJ" => "the weekly-compiled monastic daily services, old calendar (derivative, regenerated weekly)",
        "misc" => "the misc/ shelf: lectionary scripture books + the Automela/Heirmoi anthology"
      }.freeze

      # The tone-cycle page names that state their tone.
      TONE_PAGE = %r{\A(?:Och/Tone(?<tone>[1-8])(?<weekday>Sun|Mon|Tue|Wed|Thu|Fri|Sat)|
                       Och/Theotokia(?<tone>[1-8])|Tri/Tone(?<tone>[1-8])|Oro/Sun(?<tone>[1-8]))\z}x
      # A Menaion page name that carries its day: Sep05, 14b, 13a1, Oct01b.
      MENAION_DAY = /\A(?:[A-Z][a-z]{2})?(?<day>[0-3]\d)[a-z]?\d?\z/

      # A tone rubric: Ἦχος δ', Ἦχος πλ. δ', Ἦχος βαρύς (also monotonic Ήχος).
      TONE = /(?<!\p{L})(?:ἦ|ή|η)χος\s+(?<plagal>πλ\.?\s*)?(?<mode>βαρ[υύ]ς|[αβγδ])(?!\p{L})/i
      MODES = { "α" => 1, "β" => 2, "γ" => 3, "δ" => 4 }.freeze

      CREDIT = "Greek Orthodox Liturgical Texts (glt.goarch.org), Greek Orthodox Archdiocese of " \
               "America; compiled and maintained by Fr. Leo Schefe"

      MANIFEST = Nabu::SourceManifest.new(
        id: SLUG,
        name: "GLT — Greek Orthodox Liturgical Texts (glt.goarch.org): the Byzantine service books in Greek",
        license: "Public domain, by the maintainer's own statement: permission by email from the site " \
                 "maintainer (Fr. Leo Schefe), 2026-11-02 — the texts are in the public domain and " \
                 "\"you are welcome to use them\"; reports of errors in the texts are invited. Credit " \
                 "the site (glt.goarch.org, Greek Orthodox Archdiocese of America)",
        license_class: "open",
        upstream_url: BASE_URL,
        parser_family: "glt-html",
        credit: CREDIT
      )

      def self.manifest = MANIFEST

      def self.remote_probe_strategy = :http_zip

      def self.http_probe_targets
        [Nabu::Adapter::HttpProbeTarget.new(
          label: "glt.goarch.org index.html", zip_url: "#{BASE_URL}index.html", metadata_url: nil,
          state_subdir: "", state_file: Nabu::GltFetch::STATE_FILE, liveness_only: true
        )]
      end

      # The document urn of a site-relative page path.
      def self.urn_for(rel)
        shelf, page = rel.delete_prefix("#{TEXTS_DIR}/").split("/", 2)
        "#{URN_PREFIX}#{shelf.downcase}.#{page.delete_suffix('.html').downcase.gsub(/\s+/, '-')}"
      end

      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        index = index_entries(workdir)
        accepted_pages(workdir).each do |rel|
          metadata = { "page" => rel }
          if (entry = index[rel])
            metadata["index"] = { "list" => entry.list, "group" => entry.group, "label" => entry.label }.compact
          end
          yield Nabu::DocumentRef.new(source_id: SLUG, id: self.class.urn_for(rel),
                                      path: File.expand_path(File.join(workdir, rel)), metadata: metadata)
        end
      end

      def discovery_skips(workdir)
        by_rule = 0
        unrecognized = 0
        notes = []
        rejected = Hash.new(0)
        accepted = accepted_pages(workdir).to_set
        files(workdir).each do |rel|
          next if accepted.include?(rel)

          reason = rejection(rel)
          if reason
            by_rule += 1
            rejected[reason] += 1
          else
            unrecognized += 1
            notes << "unrecognized file: #{rel}"
          end
        end
        notes = rejected.map { |reason, count| "#{count} skipped by rule — #{reason}" } + notes
        Nabu::Adapter::DiscoverySkips.new(skipped_by_rule: by_rule, unrecognized: unrecognized, notes: notes)
      end

      def parse(document_ref)
        rel = document_ref.metadata.fetch("page") { raise Nabu::ParseError, "#{SLUG}: ref without a page" }
        text = SourceRead.utf8_file(document_ref.path, label: SLUG)
        page = GltHtmlParser.page(text)
        raise Nabu::ParseError, "#{SLUG}: #{rel}: no text lines" if page.lines.empty?

        document = Nabu::Document.new(
          urn: document_ref.id, language: LANGUAGE, canonical_path: document_ref.path,
          title: title_for(rel, document_ref.metadata["index"], page),
          metadata: document_metadata(rel, document_ref, page)
        )
        state = { tone: nil, section: nil }
        page.lines.each_with_index do |line, sequence|
          document << Nabu::Passage.new(
            urn: "#{document_ref.id}:#{sequence + 1}", language: LANGUAGE,
            text: nfc(line.text), sequence: sequence, annotations: line_annotations(line, state)
          )
        end
        document
      end

      def fetch(workdir, progress: nil, force: false)
        result = Nabu::GltFetch.sync!(
          dir: workdir, attic_dir: File.join(workdir, ATTIC_DIRNAME), progress: progress, delay: fetch_delay,
          guard: ->(doomed) { guard_mass_deletion!(workdir, doomed, force: force) }
        )
        notes = [attic_notes(result.atticked),
                 "#{result.listed} listed pages: #{result.fetched} fetched, #{result.unchanged} unchanged",
                 ("#{result.missing.size} listed page(s) 404 upstream: #{result.missing.first(5).join(', ')}" unless
                   result.missing.empty?)].compact
        FetchReport.new(sha: result.sha, fetched_at: Time.now, notes: notes.join("; "))
      rescue Nabu::GltFetch::Error => e
        raise Nabu::FetchError, "#{SLUG} fetch failed into #{workdir}: #{e.message}"
      end

      # Seam for tests (the politeness pause between GETs).
      def fetch_delay = Nabu::GltFetch::DELAY

      private

      def nfc(text) = SourceRead.nfc(text, language: LANGUAGE)

      # Every site-shaped file (the extensions the site serves) under the
      # workdir outside the dot-dirs (attic, state pins).
      def files(workdir)
        Dir.glob("**/*", base: workdir)
           .select { |rel| SITE_EXTENSIONS.include?(File.extname(rel).downcase) && File.file?(File.join(workdir, rel)) }
           .reject { |rel| rel.split("/").any? { |part| part.start_with?(".") } }.sort
      end

      def page_candidate?(rel)
        shelf, page = rel.split("/", 3).values_at(1, 2)
        rel.start_with?("#{TEXTS_DIR}/") && page && !page.include?("/") && page.end_with?(".html") &&
          BOOKS.key?(shelf)
      end

      # The accepted pages, minus any whose urn collides with an earlier one
      # (case-folded names: none upstream at census, refused rather than merged).
      def accepted_pages(workdir)
        seen = {}
        files(workdir).select { |rel| page_candidate?(rel) }.reject do |rel|
          urn = self.class.urn_for(rel)
          collided = seen.key?(urn)
          seen[urn] = rel
          collided
        end
      end

      def rejection(rel)
        return "the catalog pages (index.html, extra.htm — provenance, not texts)" if CATALOG_PAGES.include?(rel)

        top = rel.split("/").first
        return REJECTED_DIRS.fetch(top) if REJECTED_DIRS.key?(top)
        if rel.start_with?("#{TEXTS_DIR}/") && !rel.end_with?(".html")
          return "non-HTML renderings under texts/ (.rtf/.pdf — the HTML pages are the texts)"
        end

        nil
      end

      def index_entries(workdir)
        CATALOG_PAGES.each_with_object({}) do |name, map|
          path = File.join(workdir, name)
          next unless File.file?(path)

          GltHtmlParser.index_entries(SourceRead.utf8_file(path, label: SLUG), list: name).each do |entry|
            map[entry.rel] ||= entry
          end
        rescue Nabu::ParseError
          next
        end
      end

      def book_for(rel) = BOOKS.fetch(rel.split("/")[1])

      def title_for(rel, index, page)
        book = book_for(rel)
        parts = if index && (index["group"] || index["label"])
                  [index["group"], index["label"]]
                else
                  [page.title || File.basename(rel, ".html")]
                end
        nfc([book.title, *parts.compact].uniq.join(" — "))
      end

      def document_metadata(rel, document_ref, page)
        book = book_for(rel)
        metadata = { "book" => book.key, "page" => rel, "url" => BASE_URL + URI::DEFAULT_PARSER.escape(rel) }
        metadata["page_title"] = nfc(page.title) if page.title
        index = document_ref.metadata["index"]
        metadata["index"] = index.transform_values { |value| nfc(value) } if index
        day = File.basename(rel, ".html")[MENAION_DAY, :day] if book.month
        metadata["commemoration"] = { "month" => book.month, "day" => Integer(day, 10) } if day
        if (match = rel.delete_prefix("#{TEXTS_DIR}/").delete_suffix(".html").match(TONE_PAGE))
          metadata["tone"] = Integer(match[:tone], 10)
          metadata["weekday"] = match[:weekday] if match[:weekday]
        end
        metadata
      end

      # The mined layers of one line (see the class comment); +state+ carries
      # the tone and section in force down the page.
      def line_annotations(line, state)
        role = line.role
        rubric_text = if role == "text"
                        nil
                      else
                        nfc(role == "rubric" ? line.text : line.rubric_spans.join(" "))
                      end
        if role == "rubric" && heading?(rubric_text)
          state[:section] = rubric_text
          state[:tone] = nil
        end
        tone = rubric_text && tone_of(rubric_text)
        state[:tone] = tone if tone
        annotations = { "role" => role }
        annotations["rubrics"] = line.rubric_spans.map { |span| nfc(span) } if role == "mixed"
        annotations["ink"] = line.uniform_ink if line.uniform_ink
        annotations["bold"] = true if role == "text" && line.all_bold?
        annotations["recordings"] = line.recordings unless line.recordings.empty?
        annotations["tone"] = state[:tone] if state[:tone]
        annotations["section"] = state[:section] if state[:section]
        annotations
      end

      # An all-capitals rubric (at least four letters, none lowercase).
      def heading?(text) = text.scan(/\p{L}/).size >= 4 && !text.match?(/\p{Ll}/)

      def tone_of(text)
        match = text.match(TONE) or return nil
        mode = match[:mode].downcase
        return 7 if mode.start_with?("βαρ")

        base = MODES.fetch(mode)
        match[:plagal] ? base + 4 : base
      end
    end
  end
end

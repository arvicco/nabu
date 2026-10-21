# frozen_string_literal: true

require "cgi"
require "digest"
require "fileutils"
require "json"
require "nokogiri"
require "zlib"

require_relative "../zip_fetch"
require_relative "../redirect_follow"
require_relative "../normalize"
require_relative "source_read"
require_relative "vakk_page_parser"

module Nabu
  module Adapters
    # vakk: VAKK — Vana kirjakeele korpus, the Corpus of Old Written
    # Estonian (University of Tartu; Külli Prillop, Külli Habicht, Epp
    # Ehasalu, Valve-Liivi Kingisepp, Jaak Peebo; vakk.ut.ee, DOI
    # 10.15155/1-00-0000-0000-0000-00075L). Every surviving Estonian text
    # of the 15th–16th centuries (manuscripts and prints, name lists
    # excepted), most 17th-century prints and the manuscript sermons
    # (Georg Müller's 1600–06), a selection of 18th–19th-century prints
    # (the 1739 Bible, Stahl's Hand- und Hausbuch and Leyen Spiegel,
    # the 1715 New Testament, Lithander's cookbook …), German-language
    # metatexts about Estonian (grammars, prefaces), the Moravian
    # Brethren manuscripts, and — hosted, not part of VAKK proper — the
    # 19th-century parish-court protocols (vallakohtute protokollid). The
    # texts are in their original spelling; the older ones are
    # morphologically annotated with Külli Prillop's Vakker (modern-
    # Estonian lemmas, part of speech, form, gloss, token language).
    #
    # == Upstream and grains (census 2026-10-21; the www.murre.ut.ee/vakk
    # address of older citations no longer completes a TLS handshake —
    # the corpus lives at vakk.ut.ee)
    #
    #   index (tekstid.php)         the text list: year, author, title, the
    #                               dialect basis (eP North / eL South
    #                               Estonian, ee unspecified, "" no
    #                               Estonian), class (V religious, I secular,
    #                               S dictionary, M metatext, H Moravian
    #                               Brethren, K court protocol), medium (K
    #                               manuscript, T print), token counts
    #                               "all / Estonian / annotated" — kept
    #                               verbatim under map/
    #   text (kood)                 THE DOCUMENT (3,052 listed)
    #   info page (lk=info)         the text's own record: source edition
    #                               and commentary; for the protocols
    #                               Teema / Vald / Kuupäev / Protokolli
    #                               number / Kohtumehed fields
    #   page (lk=<n>)               the reading view's page — a passage
    #                               grouping (the page id cites)
    #   sentence (div.lause)        THE PASSAGE
    #   token (span.sone)           annotations "tokens"
    # Not taken: the page facsimile JPEGs (/pildid/, shown beside some
    # manuscript pages — images, never requested), the search interface
    # (otsi.php — a view over the same tokens) and the linked VAKS
    # dictionary (sisu.ut.ee/vaks — a separate resource).
    #
    # Census 2026-10-21: 3,052 texts / 3,374,325 tokens (2,895,520
    # Estonian, 1,675,332 annotated): 196 corpus texts (V 80 · I 67 · M
    # 22 · H 26 · S 1; 2,977,185 tokens — 107 of them dated ≤ 1739,
    # 1,809,693 tokens) + 2,856 court protocols (1866–1890s, 397,140
    # tokens). Accepted documents = the texts whose crawl is complete;
    # an incomplete one skips by rule (discovery_skips names it).
    #
    # == The paced, resumable crawl (the mdz-protestant mold)
    #
    # Per sync: the index (rewritten only when it changed; zero rows
    # aborts), then up to SLICE requests, DELAY apart, walking the texts
    # in index order — the 196 corpus texts first, the court protocols
    # after: a text's info page, its first reading page (the selector
    # names every page value), then each remaining page. Resume is at
    # the file grain (texts/<kood>/<file>.html.gz on disk is done). Pages
    # land GZIP-compressed — the bytes upstream served, verbatim, inside
    # gzip (the reading view's markup is ~650 B per token; gzip takes the
    # whole crawl from ~2.4 GB to ~70 MB). A 404, or an answer that is not
    # a reading view, ledgers the text (or page) in .vakk-crawl.json and
    # is never retried; a timeout or 5xx retries with backoff and then
    # aborts the sync — the next one resumes there. Sizing (2026-10-21,
    # eight texts' selectors read): ~411 tokens a page over the corpus
    # texts → ~7,300 pages, plus ~2,860 protocol pages and 3,052 info
    # pages — ~13,000 requests, ~4–5 h at 1 req/s: about eleven syncs at
    # SLICE 1,200 (~25 min each).
    #
    # == Documents
    #
    # urn:nabu:vakk:<kood> (upstream's text id, percent-decoded: 1535-Koell,
    # 1866-Kahkva-0001); one passage per sentence, cited
    # <page value>.<sentence n> (…:1535-Koell:3.2; front matter -4.1). The
    # passage string is the tokens space-joined with compound halves
    # closed up and closing punctuation attached (VakkPageParser); the
    # tokens ride verbatim as annotations "tokens" (form / lemma / gloss /
    # pos / morph / lang / comment / style), the page label as "page".
    #
    # == Axes (aggressive mining)
    #
    # date — the index year ("1535", "1485-1495") → {not_before,
    # not_after, raw} (:structured); the protocol's own Kuupäev rides as
    # metadata. place — the protocol's Vald (the parish commune whose
    # court sat: "Kahkva"), a named claim; the corpus texts carry no
    # structured place (imprint towns stay inside the commentary prose —
    # declared coarse). author — the index author verbatim (a court for
    # the protocols). Facets: class (V/I/S/M/H/K with upstream's own
    # label — folded in config/kind_map.yml), dialect (North / South
    # Estonian), medium (manuscript / print). lect — et; a passage whose
    # language-tagged tokens are mostly German or Latin reads de / lat
    # (the metatexts and bilingual prints), the rest et — the Old Written
    # Estonian stage by date band (postures.yml). Lemmas: the modern-
    # Estonian headwords of the Estonian tokens, silver (semi-automatic,
    # upstream's own account: the 18th–19th-century tagging is unchecked).
    #
    # == License
    #
    # The META-SHARE record behind the DOI (metashare.ut.ee, read
    # 2026-10-21), verbatim: "Availability: Available - Restricted Use",
    # "Licence CC - BY - NC Restrictions: Academic - Non Commercial Use",
    # "Distribution Access/Medium: Accessible Through Interface" →
    # license_class nc. Citation per the site's guide: "VAKK (= Vana
    # kirjakeele korpus. Tartu Ülikool. https://vakk.ut.ee/)".
    class Vakk < Nabu::Adapter
      BASE_URL = "https://vakk.ut.ee"
      INDEX_URL = "#{BASE_URL}/tekstid.php".freeze
      FIRST_URL = "#{BASE_URL}/tekstid.php?kood=%s".freeze
      PAGE_URL = "#{BASE_URL}/tekstid.php?lk=%s&kood=%s".freeze
      INFO_URL = "#{BASE_URL}/tekstid.php?lk=info&kood=%s".freeze
      MAP_DIRNAME = "map"
      INDEX_FILE = "tekstid.html"
      TEXTS_DIRNAME = "texts"
      INFO_FILE = "info.html.gz"
      FIRST_FILE = "first.html.gz"
      LEDGER_FILE = ".vakk-crawl.json"
      URN_PREFIX = "urn:nabu:vakk:"
      LANGUAGE = "et"

      # const: crawl politeness pause, not a corpus claim (~1 req/s).
      DELAY = 1.0
      # Requests per sync (~25 min of paced requests).
      SLICE = 1_200
      RETRIES = 3
      BACKOFF = 5.0

      COURT = "K"
      CLASS_LABELS = { "V" => "V - vaimulik", "I" => "I - ilmalik", "S" => "S - sõnastik",
                       "K" => "K - kohtuprotokoll", "M" => "M - metatekst",
                       "H" => "H - vennastekogudus" }.freeze
      DIALECTS = { "eP" => "North Estonian", "eL" => "South Estonian", "ee" => "Estonian" }.freeze
      MEDIA = { "K" => "manuscript", "T" => "print" }.freeze
      # Token languages that move a passage off et when they hold the
      # majority of its language-tagged words.
      FOREIGN = { "saksa" => "de", "ladina" => "lat" }.freeze
      ESTONIAN = "eesti"
      NON_WORDS = %w[kirjavahemärk number viide].freeze
      YEAR = /\A(\d{3,4})(?:\s*-\s*(\d{3,4}))?\z/

      IndexRow = Data.define(:kood, :href, :year, :author, :title, :dialect, :klass, :medium, :counts)

      MANIFEST = Nabu::SourceManifest.new(
        id: "vakk",
        name: "VAKK — Vana kirjakeele korpus, the Corpus of Old Written Estonian (University of Tartu)",
        license: "META-SHARE record (DOI 10.15155/1-00-0000-0000-0000-00075L), verbatim: \"Licence CC - BY " \
                 "- NC Restrictions: Academic - Non Commercial Use\", \"Available - Restricted Use\". Cite " \
                 "\"VAKK (= Vana kirjakeele korpus. Tartu Ülikool. https://vakk.ut.ee/)\"",
        license_class: "nc",
        upstream_url: "https://vakk.ut.ee/",
        parser_family: "vakk-html"
      )

      def self.manifest = MANIFEST

      def self.remote_probe_strategy = :http_zip

      def self.http_probe_targets
        [Nabu::Adapter::HttpProbeTarget.new(
          label: "VAKK text list", zip_url: INDEX_URL, metadata_url: nil,
          state_subdir: "", liveness_only: true
        )]
      end

      # +koods+ narrows the crawl to the named texts (the fixture recipe
      # and the tests' seam); nil crawls the whole index.
      def initialize(delay: DELAY, slice: SLICE, http: Nabu::ZipFetch.default_http, koods: nil,
                     backoff: BACKOFF)
        super()
        @delay = delay
        @slice = slice
        @http = http
        @koods = koods
        @backoff = backoff
        @requests = 0
      end

      # -- fetch -------------------------------------------------------------

      # +force+ is part of the fetch interface; nothing here ever deletes.
      def fetch(workdir, progress: nil, force: false) # rubocop:disable Lint/UnusedMethodArgument
        FileUtils.mkdir_p(workdir)
        rows = refresh_index!(workdir, progress)
        ledger = read_ledger(workdir)
        fetched, done = crawl_slice!(workdir, crawl_order(rows), ledger, progress)
        write_ledger!(workdir, ledger)
        complete = crawl_order(rows).count { |row| complete?(workdir, row.href, ledger) }
        notes = "crawl at #{complete}/#{crawl_order(rows).size} text(s) complete " \
                "(+#{fetched} request(s) this sync#{'; slice limit reached — resume next sync' unless done})"
        progress&.call("#{notes}\n")
        Nabu::FetchReport.new(sha: crawl_sha(workdir, ledger), fetched_at: Time.now, notes: notes)
      end

      # -- discover ----------------------------------------------------------

      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        ledger = read_ledger(workdir)
        rows_by_href = index_rows(workdir).to_h { |row| [row.href, row] }
        text_dirs(workdir).each do |href|
          row = rows_by_href[href]
          next if row.nil? || !complete?(workdir, href, ledger)

          block.call(Nabu::DocumentRef.new(
                       source_id: MANIFEST.id, id: "#{URN_PREFIX}#{row.kood}",
                       path: File.expand_path(File.join(text_dir(workdir, href), FIRST_FILE)),
                       metadata: { "href" => href }
                     ))
        end
      end

      def discovery_skips(workdir)
        ledger = read_ledger(workdir)
        listed = index_rows(workdir).map(&:href)
        incomplete = text_dirs(workdir).select { |href| listed.include?(href) && !complete?(workdir, href, ledger) }
        strays = text_dirs(workdir) - listed
        Nabu::Adapter::DiscoverySkips.new(
          skipped_by_rule: incomplete.size, unrecognized: strays.size,
          notes: incomplete.map { |href| "crawl incomplete: #{href}" } +
                 strays.map { |href| "text directory not in the index: #{href}" }
        )
      end

      # -- parse -------------------------------------------------------------

      def parse(document_ref)
        dir = File.dirname(document_ref.path)
        workdir = File.dirname(dir, 2)
        href = document_ref.metadata.fetch("href")
        row = index_rows(workdir).find { |candidate| candidate.href == href }
        raise ParseError, "#{document_ref.path}: #{href} is not in the index" if row.nil?

        info_path = File.join(dir, INFO_FILE)
        info = File.file?(info_path) ? info_fields(read_gz(info_path)) : {}
        document = Nabu::Document.new(
          urn: document_ref.id, language: LANGUAGE, title: row.title || row.kood,
          canonical_path: document_ref.path, metadata: metadata_for(row, info)
        )
        append_pages(document, dir)
        raise ParseError, "#{document_ref.path}: no sentence on any page" if document.empty?

        document
      rescue Nabu::ValidationError => e
        raise ParseError, "#{document_ref.path}: #{e.message}"
      end

      private

      # -- fetch internals ---------------------------------------------------

      def refresh_index!(workdir, progress)
        progress&.call("VAKK text list…\n")
        body = get!(INDEX_URL).body.to_s.dup.force_encoding(Encoding::UTF_8)
        rows = parse_index(body)
        raise FetchError, "vakk: the text list carries no rows — upstream shape changed" if rows.empty?

        path = File.join(workdir, MAP_DIRNAME, INDEX_FILE)
        unless File.file?(path) && File.binread(path) == body.b
          FileUtils.mkdir_p(File.dirname(path))
          File.binwrite("#{path}.tmp", body)
          File.rename("#{path}.tmp", path)
        end
        rows
      end

      # The corpus texts first, then the court protocols, each in index
      # order; narrowed to +koods+ when given.
      def crawl_order(rows)
        rows = rows.select { |row| @koods.include?(row.kood) } if @koods
        rows.reject { |row| row.klass == COURT } + rows.select { |row| row.klass == COURT }
      end

      # Returns [requests made, whether the walk finished].
      def crawl_slice!(workdir, rows, ledger, progress)
        made = 0
        rows.each do |row|
          # The first page's selector names the remaining pages, so the
          # wanted list is re-read after each file lands.
          until ledger["texts"].include?(row.href) || (wanted = missing_files(workdir, row.href, ledger)).empty?
            return [made, false] if made >= @slice

            name, url = wanted.first
            made += 1
            outcome = fetch_file!(workdir, row.href, name, url)
            record_refusal!(ledger, row.href, name) unless outcome == :ok
            progress&.call("crawl: +#{made} request(s)…\n") if (made % 100).zero?
          end
        end
        [made, true]
      end

      # [file name, url] pairs still to fetch for a text, in crawl order:
      # info, the first page, then every other page the selector lists.
      def missing_files(workdir, href, ledger)
        dir = text_dir(workdir, href)
        wanted = [[INFO_FILE, format(INFO_URL, href)], [FIRST_FILE, format(FIRST_URL, href)]]
        first = File.join(dir, FIRST_FILE)
        if File.file?(first)
          page = parser.parse(read_gz(first))
          (page.page_values - [page.selected]).each do |value|
            wanted << [page_file(value), format(PAGE_URL, CGI.escape(value), href)]
          end
        end
        refused = Array(ledger["pages"][href])
        wanted.reject { |name, _| refused.include?(name) || File.file?(File.join(dir, name)) }
      end

      def record_refusal!(ledger, href, name)
        if name == FIRST_FILE
          ledger["texts"] << href
        else
          (ledger["pages"][href] ||= []) << name
        end
      end

      def fetch_file!(workdir, href, name, url)
        response = get_with_retries!(url)
        return :refused if response.status == 404

        body = response.body.to_s.dup.force_encoding(Encoding::UTF_8)
        return :refused if name != INFO_FILE && !parser.reading_view?(body)

        write_gz!(File.join(text_dir(workdir, href), name), body)
        :ok
      end

      def get_with_retries!(url)
        attempt = 0
        begin
          attempt += 1
          get!(url, accept: [200, 404])
        rescue Nabu::FetchError
          raise if attempt >= RETRIES

          pause = @backoff * (2**(attempt - 1))
          sleep(pause) if pause.positive?
          retry
        end
      end

      def get!(url, accept: [200])
        sleep(@delay) if @delay.positive? && @requests.positive?
        @requests += 1
        response, = Nabu::RedirectFollow.get(
          url, http: @http, error: Nabu::FetchError, accept: accept,
               headers: { "User-Agent" => Nabu::WikiFetch::USER_AGENT }
        )
        response
      end

      def write_gz!(path, body)
        FileUtils.mkdir_p(File.dirname(path))
        Zlib::GzipWriter.open("#{path}.tmp") do |gz|
          gz.mtime = 0 # byte-stable archives: the same page gzips to the same file
          gz.write(body)
        end
        File.rename("#{path}.tmp", path)
      end

      def read_ledger(workdir)
        path = File.join(workdir, LEDGER_FILE)
        blank = { "texts" => [], "pages" => {} }
        return blank unless File.file?(path)

        blank.merge(JSON.parse(File.read(path)).slice("texts", "pages"))
      rescue JSON::ParserError
        blank
      end

      def write_ledger!(workdir, ledger)
        pages = ledger["pages"].transform_values { |names| names.uniq.sort }.sort.to_h
        File.write(File.join(workdir, LEDGER_FILE),
                   JSON.pretty_generate({ "texts" => ledger["texts"].uniq.sort, "pages" => pages }))
      end

      def crawl_sha(workdir, ledger)
        index = File.join(workdir, MAP_DIRNAME, INDEX_FILE)
        files = Dir.glob(File.join(workdir, TEXTS_DIRNAME, "*", "*.html.gz"))
                   .map { |path| path.delete_prefix("#{workdir}/") }.sort
        Digest::SHA256.hexdigest(JSON.generate([File.file?(index) ? Digest::SHA256.file(index).hexdigest : "",
                                                files, ledger]))
      end

      # -- index -------------------------------------------------------------

      def index_rows(workdir)
        path = File.join(workdir, MAP_DIRNAME, INDEX_FILE)
        File.file?(path) ? parse_index(SourceRead.utf8_file(path, label: "vakk text list")) : []
      end

      def parse_index(html)
        Nokogiri::HTML(html).css("table#tekstid tbody tr").filter_map do |tr|
          cells = tr.css("> td")
          link = cells[2]&.at_css("a[href]")
          next if cells.size < 7 || link.nil?

          href = link["href"].to_s[/[?&]kood=([^&]+)/, 1]
          next if href.nil?

          IndexRow.new(kood: Normalize.nfc(CGI.unescape(href)), href: href, year: cell(cells[0]),
                       author: cell(cells[1]), title: cell(link), dialect: cell(cells[3]),
                       klass: cell(cells[4]), medium: cell(cells[5]), counts: cell(cells[6]))
        end
      end

      def cell(node)
        text = node.text.gsub(/[[:space:]]+/, " ").strip
        text.empty? ? nil : Normalize.nfc(text)
      end

      # -- discovery/parse internals -----------------------------------------

      def parser
        @parser ||= VakkPageParser.new
      end

      def text_dir(workdir, href) = File.join(workdir, TEXTS_DIRNAME, href)

      def text_dirs(workdir)
        root = File.join(workdir, TEXTS_DIRNAME)
        return [] unless Dir.exist?(root)

        Dir.children(root).select { |child| File.directory?(File.join(root, child)) }.sort
      end

      def page_file(value) = "p#{value}.html.gz"

      def complete?(workdir, href, ledger)
        dir = text_dir(workdir, href)
        return false if ledger["texts"].include?(href) || !File.file?(File.join(dir, FIRST_FILE))

        missing_files(workdir, href, ledger).empty?
      end

      def read_gz(path)
        SourceRead.utf8(Zlib.gunzip(File.binread(path)), label: "vakk page #{path}")
      rescue Zlib::Error, Errno::ENOENT => e
        raise ParseError, "#{path}: unreadable page archive: #{e.message}"
      end

      # The first page, then the selector's other pages in selector order.
      def append_pages(document, dir)
        first = parser.parse(read_gz(File.join(dir, FIRST_FILE)))
        pages = first.page_values.empty? ? [[first.selected || "1", first]] : []
        first.page_values.each do |value|
          if value == first.selected
            pages << [value, first]
          else
            path = File.join(dir, page_file(value))
            pages << [value, parser.parse(read_gz(path))] if File.file?(path)
          end
        end
        pages.each { |value, page| append_sentences(document, value, page) }
      end

      def append_sentences(document, value, page)
        page.sentences.each_with_index do |sentence, index|
          document << Nabu::Passage.new(
            urn: "#{document.urn}:#{value}.#{index + 1}", language: passage_language(sentence),
            text: sentence.text, sequence: document.size,
            annotations: { "page" => page.label, "tokens" => sentence.tokens.map { |t| token_hash(t) } }.compact
          )
        end
      end

      # The majority language of the sentence's language-tagged words.
      def passage_language(sentence)
        tags = sentence.tokens.map(&:lang).compact.reject { |lang| NON_WORDS.include?(lang) }
        return LANGUAGE if tags.empty?

        top, count = tags.tally.max_by { |_, n| n }
        FOREIGN.key?(top) && count * 2 > tags.size ? FOREIGN.fetch(top) : LANGUAGE
      end

      # Lemmas are modern-Estonian headwords: only the Estonian tokens
      # carry the "lemma" key the lemma index reads; a foreign token's
      # headword rides as "headword".
      def token_hash(token)
        hash = { "form" => token.form, "gloss" => token.gloss, "pos" => token.pos, "morph" => token.morph,
                 "lang" => token.lang, "comment" => token.comment, "style" => token.style }
        hash[token.lang == ESTONIAN ? "lemma" : "headword"] = token.lemma
        hash.compact
      end

      # The info page's "Key: value" paragraphs (the protocols' record)
      # and the corpus texts' "Teksti allikas" source edition.
      def info_fields(html)
        info = Nokogiri::HTML(html).at_css("div.info")
        return {} if info.nil?

        info.css("> p").each_with_object({}) do |para, fields|
          text = para.text.gsub(/[[:space:]]+/, " ").strip
          key, value = text.split(/:\s*/, 2)
          next if value.nil? || key.length > 40 || value.empty?

          fields[key] ||= Normalize.nfc(value)
        end
      end

      def metadata_for(row, info)
        metadata = {
          "kood" => row.kood, "author" => row.author, "year" => row.year,
          "date" => date_for(row.year),
          "class" => row.klass && CLASS_LABELS.fetch(row.klass, row.klass),
          "dialect" => row.dialect && DIALECTS[row.dialect],
          "medium" => row.medium && MEDIA[row.medium],
          "token_counts" => row.counts,
          "source_edition" => info["Teksti allikas"],
          "place" => info["Vald"],
          "court_date" => info["Kuupäev"], "protocol_number" => info["Protokolli number"],
          "topic" => info["Teema"], "judges" => info["Kohtumehed"],
          "permalink" => format(FIRST_URL, row.href)
        }
        metadata.compact
      end

      def date_for(year)
        match = YEAR.match(year.to_s)
        return nil if match.nil?

        from = Integer(match[1], 10)
        to = match[2] ? Integer(match[2], 10) : from
        { "not_before" => [from, to].min, "not_after" => [from, to].max, "raw" => "VAKK text list: #{year}" }
      end
    end
  end
end

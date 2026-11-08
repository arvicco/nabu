# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "uri"

require_relative "manchu_wikisource_parser"
require_relative "source_read"
require_relative "../redirect_follow"
require_relative "../wiki_fetch"
require_relative "../zip_fetch"
require_relative "../normalize"

module Nabu
  module Adapters
    # mnc-wikisource — the Manchu texts on Multilingual Wikisource
    # (wikisource.org), in Unicode Manchu script or Möllendorff
    # romanization (the manchu-mongolic round-2 survey §2.2, which
    # corrected round 1's "image-only universe" for the Manchu Veritable
    # Records).
    #
    # == Fetch (the held api.php category crawl, zh-wikisource's envelope)
    #
    # Three categories — Category:ᠮᠠᠨᠵᡠ ᡤᡳᠰᡠᠨ (the Manchu-language
    # category), Category:Manchu (the 2008-era romanized pages) and the
    # 清文啓蒙 sub-category ᠴᡳᠩ ᠸᡝᠨ ᡴᡳ ᠮᡝᠩ ᠪᡳᡨ᠌ᡥᡝ: generator=categorymembers
    # + prop=info (every namespace, lastrevid) → batched revisions for the
    # new or edited pages → one envelope per page, pages/<pageid>.json
    # (+ "categories"). NOT Nabu::WikiFetch's per-title files: its
    # percent-escaped UTF-8 filename runs ~9 bytes per Manchu letter and
    # overflows the 255-byte filename limit on a 30-letter title. Pinned
    # by the pageid → revid map; non-destructive (a page that leaves the
    # categories keeps its envelope). Throttled (WikiFetch::DELAY, ~1
    # request/s) and UA-identified; the census itself was cut short by an
    # HTTP 429 in the survey and re-run paced (1.5 s) on 2026-11-08.
    #
    # == The provenance census (2026-11-08; WORKS + REJECTED below)
    #
    # 34 main-namespace member pages (redirects are not category members).
    # ADMITTED — 21 pages, 13 premodern works, each with what the page
    # states of its base (the 底本 strings verbatim where given):
    # 滿洲實錄 juan 1–4 of 8 ("依照中華書局影印本"), 清文啓蒙 preface + juan
    # 1–2 of 4 ("早稻田大學圖書館藏宏文閣刻本"), 盛京賦, the Treaty of
    # Nerchinsk, Nurhaci's Seven Grievances, the Samjeondo stele, three
    # of the Kangxi Emperor's 避暑山莊 poems, the Manchu Sunzi (Mair & Toh
    # 2008's transcription), the Yijing's first two hexagrams, Lunyu ch. 1,
    # 清語老乞大 juan 1, the native-script 三字經 and the Acts of the Manchu
    # New Testament. SKIPPED BY RULE (each class counted in discovery_skips):
    # - landing (6): work main pages and contents lists (MYK, 清文啓蒙,
    #   避暑山莊, 周易, 三國 index, the Analects intro) — navigation, no text
    #   of their own;
    # - modern (4): compositions of today, not texts of the period — the
    #   main page's "Short Stories" (Usiha be toloro jui "The boy that
    #   counts stars", Dunggo siyanxeng jai niohe, Mentuhun gung alin be
    #   guribuhengge — PRC schoolbook pieces put into Manchu) and the Dao De
    #   Jing, whose Manchu follows the 1973 Mawangdui text (恒道);
    # - unattested (2): the romanized 三字經 pair (Sanzijing ≡
    #   Manchu/sanzijing, byte-identical): no base, and its Manchu diverges
    #   from the Qing translation the native-script page carries;
    # - out-of-lect (1): 三國演義 ch. 1 in Sibe orthography (lang=sjo on the
    #   page), provenance unstated — not Manchu;
    # - other-namespace: Index:/Page:/Template:/Category:/Wikisource: members;
    # - redirect: a member page that is a #REDIRECT.
    # A main-namespace page in neither table is UNRECOGNIZED (loud) — a new
    # upstream page waits for its census row. The Mongolian-script works on
    # mul.wikisource are not in these categories (a separate census).
    #
    # == Documents and passages
    #
    # One document per admitted page (urn:nabu:mnc-wikisource:<pageid>), the
    # work riding metadata; one passage per text line the
    # manchu-wikisource parser yields (paragraph, verse line, list item or
    # table cell; a >1,500-character paragraph splits at the Manchu full
    # stop). Language per passage: Manchu (script or romanized) → mnc;
    # Han-dominant lines → the work's own Chinese layer (清文啓蒙's Qing
    # vernacular glosses zho; the Lunyu's classical text lzh). The script of
    # each passage rides annotation "script" (Mong / Latn / Hani, "+"-joined
    # when mixed).
    #
    # == License
    #
    # The texts are public domain (Qing-era works, the 1835 New Testament);
    # the transcription layer is the site's: "Text is available under the
    # Creative Commons Attribution-ShareAlike License; additional terms may
    # apply." (wikisource.org footer, verbatim) → attribution, credit the
    # Wikisource contributors.
    class MncWikisource < Nabu::Adapter
      API_URL = "https://wikisource.org/w/api.php"
      CATEGORIES = ["ᠮᠠᠨᠵᡠ ᡤᡳᠰᡠᠨ", "Manchu", "ᠴᡳᠩ ᠸᡝᠨ ᡴᡳ ᠮᡝᠩ ᠪᡳᡨ᠌ᡥᡝ"].freeze
      URN_PREFIX = "urn:nabu:mnc-wikisource:"
      LANGUAGE = "mnc"
      REDIRECT = /\A\s*#\s*redirect\b/i

      # One censused work. +pages+ the admitted pageids in reading order;
      # +date+ the structured MetadataDates shape (class composition: the
      # text's own date, the basis in raw); +han+ the language Han-dominant
      # lines claim; +start+ a pattern the text begins at (editorial lines
      # before it drop); +base+ what the page states of its base edition.
      Work = Data.define(:key, :pages, :title, :author, :date, :genre, :han, :start, :base, :note) do
        def initialize(key:, pages:, title:, author:, date:, genre:, han: "lzh", start: nil,
                       base: "unstated", note: nil)
          super
        end
      end

      def self.dated(first, last = first, raw:)
        { "not_before" => first, "not_after" => last, "class" => "composition", "raw" => raw }
      end

      QING = dated(1644, 1911, raw: "Qing-era Manchu translation (1644–1911); the page states no date")

      WORKS = [
        Work.new(key: "manju-i-yargiyan-kooli", pages: [152_837, 260_168, 260_170, 260_173],
                 title: "ᠮᠠᠨᠵᡠ ᡳ ᠶᠠᡵᡤᡳᠶᠠᠨ ᡴᠣᠣᠯᡳ (滿洲實錄, the Manchu Veritable Records), juan 1–4",
                 author: "the Qing court historiographers", genre: "veritable records",
                 date: dated(1635, 1781, raw: "compiled 1635 (Tiancong 9); the illustrated recension " \
                                              "copied 1779–1781; narrates 1583–1626 (the page: " \
                                              "'Written in 1583--1626')"),
                 base: "According to the copy version published by Zhonghua Book Company (依照中華書局影印本)",
                 note: "juan 1–4 of 8 hosted (census 2026-11-08); the Manchu text ('Here the Manchu text " \
                       "is recorded'), juan 1 also carrying the Chinese column in the page's own short " \
                       "column lines (lzh); the full Chinese side is on zh.wikisource"),
        Work.new(key: "cing-wen-ki-meng-bithe", pages: [152_893, 152_894, 151_804],
                 title: "ᠴᡳᠩ ᠸᡝᠨ ᡴᡳ ᠮᡝᠩ ᠪᡳᡨ᠌ᡥᡝ (滿漢字清文啓蒙), preface and juan 1–2",
                 author: "舞格 壽平 (Wuge Shouping); 程明遠 佩和 (ed.)", genre: "grammar", han: "zho",
                 date: dated(1730, raw: "1730 (雍正庚戌, the preface's own date line)"),
                 base: "早稻田大學圖書館藏宏文閣刻本",
                 note: "preface + juan 1–2 of 4; the Chinese is the Qing vernacular and classical gloss " \
                       "layer (the page: 清代白話文與文言文)"),
        Work.new(key: "mukden-i-fujurun-bithe", pages: [77_616],
                 title: "ᠮᡠᡴᡩᡝᠨ ᡳ ᡶᡠᠵᡠᡵᡠᠨ ᠪᡳᡨ᠌ᡥᡝ (御製盛京賦, the Ode to Mukden)",
                 author: "the Qianlong Emperor", genre: "fu",
                 date: dated(1743, raw: "1743 (Qianlong 8)"),
                 note: "the ode in Manchu script followed by its romanization"),
        Work.new(key: "nibcu-i-boji-bithe", pages: [168_826],
                 title: "ᠨᡳᠪᠴᡠ ᠊ᡳ ᠪᠣᠵᡳ ᠪᡳᡨ᠌ᡥᡝ (尼布楚條約, the Treaty of Nerchinsk)",
                 author: "Songgotu; Fyodor Golovin (negotiators)", genre: "treaty",
                 date: dated(1689, raw: "1689 (elhe taifin i orin jakūci aniya — Kangxi 28 — the text's " \
                                        "own date line)"),
                 note: "the Manchu text in script and romanization"),
        Work.new(key: "nadan-amba-koro", pages: [198_758],
                 title: "ᠨᠠᡩᠠᠨ ᠠᠮᠪᠠ ᡴᠣᡵᠣ (七大恨, the Seven Grievances)",
                 author: "Nurhaci", genre: "proclamation",
                 date: dated(1618, raw: "1618 (Tianming 3)")),
        Work.new(key: "daicing-gurun-i-gung-erdemui-bei", pages: [153_191],
                 title: "Daicing gurun-i enduringge han-i gung erdemui bei (大清皇帝功德碑, the Samjeondo stele)",
                 author: "the Qing court (erected by Joseon)", genre: "stele",
                 date: dated(1639, raw: "1639 (wesihun erdemunggei duici aniya — Chongde 4 — the text's " \
                                        "own date line)"),
                 note: "romanized; [--] marks the page's own lacunae"),
        Work.new(key: "alin-i-tokso-de-halhun-be-jailaha-si", pages: [83_720, 84_446, 78_295],
                 title: "ᡥᠠᠨ ᡳ ᠠᡵᠠᡥᠠ ᠠᠯᡳᠨ ᡳ ᡨᠣᡴᠰᠣ ᡩᡝ ᡥᠠᠯᡥᡡᠨ ᠪᡝ ᠵᠠᡳᠯᠠᡥᠠ ᡧᡳ (御製避暑山莊詩), three poems",
                 author: "the Kangxi Emperor", genre: "poetry",
                 date: dated(1711, 1712, raw: "1711–1712 (Kangxi 50–51)")),
        Work.new(key: "sun-dz-i-coohai-doro", pages: [153_207],
                 title: "Sun dz-i coohai doro bithe (孫子兵法, the Manchu Sunzi)",
                 author: "Sunzi; Qing Manchu translation", genre: "military treatise", date: QING,
                 start: /\(263\)/,
                 base: "Victor H. Mair and H. T. Toh, \"Soldierly Methods\", Sino-Platonic Papers 178 " \
                       "(2008), Appendix IV — romanized; their page numbers in parentheses",
                 note: "the page's two bibliographic lines before the text are editorial and drop"),
        Work.new(key: "jijungge-nomun", pages: [84_536, 84_537],
                 title: "ᠵᡳᠵᡠᠩᡤᡝ ᠨᠣᠮᡠᠨ (易經), hexagrams 1–2", author: "the Qing Manchu translation",
                 genre: "classic", date: QING),
        Work.new(key: "leolen-gisuren", pages: [64_127],
                 title: "Leolen gisuren (論語), chapter 1", author: "the Qing Manchu translation",
                 genre: "classic", date: QING,
                 note: "romanized Manchu (the old wiki keyboard: v = ū, x = š) beside the Chinese, line " \
                       "by line"),
        Work.new(key: "cingyu-lao-kida", pages: [64_132],
                 title: "清語老乞大 (Cingyu Lao kida), juan 1", author: "the Joseon Sayŏgwŏn interpreters",
                 genre: "primer",
                 date: dated(1703, 1765, raw: "the Joseon interpreters' Manchu conversation primer: first " \
                                              "Manchu version 1703, the revised print 1765"),
                 note: "romanized (the old wiki keyboard); the page's modern Chinese translation section " \
                       "drops"),
        Work.new(key: "ilan-hergen-i-ging", pages: [77_619],
                 title: "ᠰᠠᠨ ᡯᡳ ᡤᡳᠩ ᠨᡳ ᠪᡳᡨ᠌ᡥᡝ (三字經)", author: "the Qing Manchu translation",
                 genre: "primer", date: QING),
        Work.new(key: "ice-hese-acts", pages: [154_512],
                 title: "Ice hese — Geren apostol-i yabuha babe ejehe bithe (the Acts of the Apostles)",
                 author: "S. V. Lipovtsov (tr.)", genre: "scripture",
                 date: dated(1835, raw: "the Manchu New Testament (Lipovtsov's translation), St " \
                                        "Petersburg 1835 — the print the page's title follows"),
                 note: "romanized (the old wiki keyboard)")
      ].freeze

      WORK_BY_PAGE = WORKS.flat_map { |work| work.pages.map { |page| [page, work] } }.to_h.freeze

      # The census's skipped main-namespace pages, pageid → class.
      REJECTED = {
        152_815 => :landing, 152_891 => :landing, 78_294 => :landing, 84_535 => :landing,
        159_227 => :landing, 64_126 => :landing,
        64_129 => :modern, 64_130 => :modern, 64_131 => :modern, 64_133 => :modern,
        64_134 => :unattested, 64_128 => :unattested,
        159_228 => :out_of_lect
      }.freeze

      RULE_NOTES = {
        landing: "landing/contents page(s) — navigation, no text of their own",
        modern: "modern composition(s) — not texts of the period",
        unattested: "unattested romanized page(s) — no base, diverging from the Qing translation",
        out_of_lect: "Sibe-orthography page(s) (lang=sjo) — not Manchu",
        other_namespace: "non-main-namespace member(s) (Index/Page/Template/Category/Wikisource)",
        redirect: "redirect member(s)"
      }.freeze

      MANIFEST = Nabu::SourceManifest.new(
        id: "mnc-wikisource",
        name: "Multilingual Wikisource — Manchu texts (滿洲實錄, 清文啓蒙, 盛京賦, the Treaty of Nerchinsk …)",
        license: "Texts public domain (Qing-era works; the 1835 Manchu New Testament); the " \
                 "transcription layer: \"Text is available under the Creative Commons " \
                 "Attribution-ShareAlike License; additional terms may apply.\" (wikisource.org " \
                 "footer, verbatim, read 2026-11-08) → attribution, credit the Wikisource contributors",
        license_class: "attribution",
        upstream_url: "https://wikisource.org/wiki/Wikisource:Main_Page/Manchu",
        parser_family: "manchu-wikisource",
        credit: "Multilingual Wikisource (wikisource.org) contributors, CC BY-SA"
      )

      def self.manifest = MANIFEST

      def self.remote_probe_strategy = :http_zip

      def self.http_probe_targets
        [Nabu::Adapter::HttpProbeTarget.new(
          label: "api.php", zip_url: "#{API_URL}?action=query&meta=siteinfo&format=json",
          metadata_url: nil, state_subdir: ".", state_file: Nabu::WikiFetch::STATE_FILE
        )]
      end

      def initialize(delay: Nabu::WikiFetch::DELAY, http: Nabu::ZipFetch.default_http)
        super()
        @delay = delay
        @http = http
      end

      # +force+ is part of the fetch interface; nothing here ever deletes
      # (a page that leaves the categories keeps its envelope), so there is
      # no breaker to override.
      def fetch(workdir, progress: nil, force: false) # rubocop:disable Lint/UnusedMethodArgument
        @requests = 0
        @census = nil
        members = category_members
        stale = members.reject { |pageid, info| held_revid(workdir, pageid) == info["revid"] }
        progress&.call("#{members.size} member page(s), #{stale.size} new or edited\n")
        title_batches(stale.values.map { |info| info["title"] }).each do |batch|
          pages_payload(batch).each { |page| write_envelope!(workdir, page, members.fetch(page["pageid"])) }
        end
        pin = members.keys.sort.to_h { |pageid| [pageid.to_s, members[pageid]["revid"]] }
        sha = Digest::SHA256.hexdigest(JSON.generate(pin))
        write_state!(workdir, sha)
        Nabu::FetchReport.new(sha: sha, fetched_at: Time.now,
                              notes: "pages: #{stale.size} fetched, #{members.size - stale.size} cached " \
                                     "(#{members.size} members across #{CATEGORIES.size} categories)")
      end

      # api.php content batches: the 50-title cap AND an encoded-byte cap —
      # a Manchu-script title percent-encodes to ~9 bytes per letter (the
      # zh-wikisource HTTP 414 lesson).
      BATCH_BYTE_CAP = 5_000

      def title_batches(titles)
        titles.each_with_object([[]]) do |title, batches|
          size = URI.encode_www_form_component(title).bytesize + 3
          current = batches.last
          bytes = current.sum { |t| URI.encode_www_form_component(t).bytesize + 3 }
          batches << [] if !current.empty? &&
                           (current.size >= Nabu::WikiFetch::CONTENT_BATCH || bytes + size > BATCH_BYTE_CAP)
          batches.last << title
        end.reject(&:empty?)
      end

      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        census(workdir).each do |path, envelope, klass|
          next unless klass == :text

          yield Nabu::DocumentRef.new(source_id: MANIFEST.id, id: "#{URN_PREFIX}#{envelope.fetch('pageid')}",
                                      path: path, metadata: { "pageid" => envelope.fetch("pageid") })
        end
      end

      def discovery_skips(workdir)
        classes = census(workdir).map(&:last).tally
        unknown = census(workdir).select { |_, _, klass| klass == :uncensused }
        Nabu::Adapter::DiscoverySkips.new(
          skipped_by_rule: RULE_NOTES.keys.sum { |klass| classes.fetch(klass, 0) },
          unrecognized: unknown.size,
          notes: RULE_NOTES.filter_map { |klass, note| "#{classes[klass]} #{note}" if classes[klass] } +
                 unknown.map { |_, envelope, _| "uncensused page: #{envelope['title']} (#{envelope['pageid']})" }
        )
      end

      def parse(document_ref)
        envelope = read_envelope(document_ref.path)
        work = WORK_BY_PAGE[envelope["pageid"]] or
          raise ParseError, "#{document_ref.id}: page #{envelope['pageid']} is not an admitted census page"

        result = parser.parse(envelope.fetch("wikitext"))
        lines = text_lines(result.lines, work)
        raise ParseError, "#{document_ref.id}: no text lines extracted" if lines.empty?

        document = Nabu::Document.new(
          urn: document_ref.id, language: LANGUAGE, title: Normalize.nfc(envelope.fetch("title")),
          canonical_path: document_ref.path, metadata: metadata_for(envelope, work, result.header)
        )
        lines.each_with_index do |line, index|
          text = Normalize.nfc(line.text)
          annotations = { "script" => self.class.scripts(text) }
          annotations["section"] = Normalize.nfc(line.section) if line.section
          document << Nabu::Passage.new(urn: "#{document_ref.id}:#{index + 1}", language: language_of(text, work),
                                        text: text, sequence: index + 1, annotations: annotations)
        end
        document
      end

      # The scripts a text line carries, in a fixed order, "+"-joined.
      def self.scripts(text)
        found = []
        found << "Mong" if text.match?(/[᠀-᢯]/)
        found << "Latn" if text.match?(/[A-Za-zÀ-ž]/)
        found << "Hani" if text.match?(/\p{Han}/)
        found.join("+")
      end

      private

      def parser
        @parser ||= ManchuWikisourceParser.new
      end

      # -- fetch internals ---------------------------------------------------

      # pageid → {"title", "revid" (upstream's lastrevid), "categories"} over
      # every crawled category (a page in two categories merges).
      def category_members
        members = {}
        CATEGORIES.each do |category|
          continue = {}
          loop do
            payload = get_json("action" => "query", "format" => "json", "generator" => "categorymembers",
                               "gcmtitle" => "Category:#{category}", "gcmlimit" => "500", "prop" => "info",
                               **continue)
            (payload.dig("query", "pages") || {}).each_value do |page|
              entry = members[page.fetch("pageid")] ||= { "title" => page.fetch("title"), "categories" => [] }
              entry["revid"] = page["lastrevid"]
              entry["categories"] |= [category]
            end
            continue = payload["continue"]&.except("continue") or break
          end
        end
        members
      end

      def pages_payload(batch)
        payload = get_json("action" => "query", "format" => "json", "prop" => "revisions",
                           "rvprop" => "content|ids|timestamp", "rvslots" => "main", "titles" => batch.join("|"))
        (payload.dig("query", "pages") || {}).values.reject { |page| page.key?("missing") }
      end

      def write_envelope!(workdir, page, member)
        revision = page.dig("revisions", 0) or return
        envelope = {
          "title" => page.fetch("title"), "pageid" => page.fetch("pageid"), "ns" => page["ns"] || 0,
          "revid" => revision["revid"], "timestamp" => revision["timestamp"],
          "categories" => member["categories"].sort, "wikitext" => revision.dig("slots", "main", "*").to_s
        }
        dir = File.join(workdir, Nabu::WikiFetch::PAGES_DIRNAME)
        FileUtils.mkdir_p(dir)
        target = File.join(dir, "#{envelope['pageid']}.json")
        File.binwrite("#{target}.tmp", "#{JSON.pretty_generate(envelope)}\n")
        File.rename("#{target}.tmp", target)
      end

      def held_revid(workdir, pageid)
        path = File.join(workdir, Nabu::WikiFetch::PAGES_DIRNAME, "#{pageid}.json")
        File.file?(path) ? JSON.parse(SourceRead.utf8_file(path, label: "mnc-wikisource envelope"))["revid"] : nil
      rescue JSON::ParserError, Nabu::ParseError
        nil # a corrupt envelope is refetched, never trusted
      end

      def write_state!(workdir, sha)
        FileUtils.mkdir_p(workdir)
        state = { "last_modified" => nil, "sha256" => sha, "url" => API_URL }
        File.write(File.join(workdir, Nabu::WikiFetch::STATE_FILE), JSON.pretty_generate(state))
      end

      def get_json(params)
        sleep(@delay) if @delay.positive? && @requests.to_i.positive?
        @requests = @requests.to_i + 1
        url = "#{API_URL}?#{URI.encode_www_form(params)}"
        response, = Nabu::RedirectFollow.get(url, http: @http, error: Nabu::FetchError,
                                                  headers: { "User-Agent" => Nabu::WikiFetch::USER_AGENT })
        payload = JSON.parse(response.body.to_s)
        raise Nabu::FetchError, "api.php error: #{payload['error']}" if payload.key?("error")

        payload
      rescue JSON::ParserError => e
        raise Nabu::FetchError, "api.php returned unparseable JSON: #{e.message}"
      end

      # -- discovery internals -----------------------------------------------

      # [path, envelope, class] per held member page, in pageid order.
      def census(workdir)
        @census ||= {}
        @census[workdir] ||= Dir.glob(File.join(workdir, Nabu::WikiFetch::PAGES_DIRNAME, "*.json"))
                                .sort_by { |path| File.basename(path, ".json").to_i }
                                .map do |path|
          envelope = read_envelope(path)
          [File.expand_path(path), envelope, page_class(envelope)]
        end
      end

      def page_class(envelope)
        return :other_namespace unless envelope["ns"].to_i.zero?
        return :redirect if envelope["wikitext"].match?(REDIRECT)
        return :text if WORK_BY_PAGE.key?(envelope["pageid"])

        REJECTED.fetch(envelope["pageid"], :uncensused)
      end

      def read_envelope(path)
        envelope = JSON.parse(SourceRead.utf8_file(path, label: "mnc-wikisource envelope"))
        raise ParseError, "#{path}: page envelope has no wikitext" unless envelope["wikitext"].is_a?(String)

        envelope
      rescue JSON::ParserError, Errno::ENOENT => e
        raise ParseError, "#{path}: unreadable page envelope: #{e.message}"
      end

      def text_lines(lines, work)
        return lines unless work.start

        first = lines.index { |line| line.text.match?(work.start) }
        first ? lines.drop(first) : lines
      end

      # Han-dominant lines claim the work's Chinese layer; everything else
      # (Manchu script, romanized Manchu) is mnc.
      def language_of(text, work)
        han = text.scan(/\p{Han}/).size
        other = text.scan(/[᠀-᢯A-Za-z]/).size
        han > other ? work.han : LANGUAGE
      end

      def metadata_for(envelope, work, header)
        {
          "work" => work.key, "work_title" => work.title, "author" => work.author,
          "date" => work.date, "genre" => work.genre, "facets" => { "genre" => { "value" => work.genre } },
          "base_edition" => work.base, "note" => work.note,
          "page_part" => work.pages.index(envelope["pageid"]) + 1, "work_pages" => work.pages.size,
          "wiki_author" => header["author"], "wiki_section" => header["section"], "wiki_notes" => header["notes"],
          "pageid" => envelope["pageid"], "revid" => envelope["revid"],
          "url" => "https://wikisource.org/wiki/#{envelope['title'].tr(' ', '_')}"
        }.compact.transform_values { |value| value.is_a?(String) ? Normalize.nfc(value) : value }
      end
    end
  end
end

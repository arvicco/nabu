# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "uri"

require_relative "orkhon_wikisource_parser"
require_relative "source_read"
require_relative "../redirect_follow"
require_relative "../fetch/wiki_fetch"
require_relative "../fetch/zip_fetch"
require_relative "../normalize"

module Nabu
  module Adapters
    # tr-wikisource — the Orkhon inscriptions on Turkish Wikisource
    # (tr.wikisource.org): the three Old Turkic royal monuments of the
    # Second Türk Khaganate — Kül Tigin, Bilge Kağan and Tonyukuk — each
    # line in the runiform original, a transliteration, a transcription
    # and a modern Turkish translation.
    #
    # == Fetch (the mnc-wikisource envelope crawl)
    #
    # Kategori:Orhun Abideleri (generator=categorymembers + prop=info,
    # every namespace, lastrevid) plus the landing title "Orhun Yazıtları"
    # (prop=info by title — a disambiguation page, not a category member)
    # → batched revisions for the new or edited pages → one envelope per
    # page, pages/<pageid>.json (+ "categories"). Pinned by the pageid →
    # revid map; non-destructive (a page that leaves the category keeps its
    # envelope). Throttled (WikiFetch::DELAY, ~1 request/s) and
    # UA-identified.
    #
    # == The census (2026-11-27, every grain upstream serves here)
    #
    # Kategori:Orhun Abideleri has exactly 3 members, all main namespace,
    # all ADMITTED: Orhun Yazıtları (Kül Tigin) (pageid 5093, 99,515 bytes),
    # (Bilge Kağan) (5095, 108,320) and (Tonyukuk) (5096, 53,720). The
    # landing page Orhun Yazıtları (5338) is a disambiguation list of three
    # links (Kategori:Anlam ayrımı) — SKIPPED BY RULE as landing. The three
    # "Orhun Abideleri (…)" titles it links (17741/17742/17744) and the
    # "Orhun Abideleri" title are #YÖNLENDİRME redirects to the three pages,
    # never category members, never fetched (the redirect rule stands for
    # any that turns up). The category's parent, Kategori:Yazıtlar, also
    # holds the wiki's other inscriptions (Elegeş, Kızıl Taş, Talas, Bagha
    # Tur Cheghsi, the Ortakent cuneiform, an Ottoman kitabe) — Latin
    # transcriptions without runiform, outside this crawl. A main-namespace
    # page in neither table is UNRECOGNIZED (loud): a new upstream page
    # waits for its census row.
    #
    # Reconciliation: upstream's own captions declare the line count of
    # every face ("Kül Tigin taşı, 1. yüz (güney) 13 dizi"); every face's
    # rows match its caption — Kül Tigin 13+40+13+1+1+1+1 = 70, Bilge Kağan
    # 41+1+15+15+9+1 = 82, Tonyukuk (two stones, four faces each)
    # 7+10+7+11 + 9+6+8+4 = 62: 3 documents / 214 passages, no residue.
    #
    # == Documents and passages
    #
    # One document per inscription (urn:nabu:tr-wikisource:<work key>);
    # one passage per inscribed line, the passage urn carrying upstream's
    # own citation (…:kul-tigin:G1, …:tonyukuk:1-B1 — face letter + line;
    # Tonyukuk stone-face-line), upstream's stable row id ("kt-1-g-13-01")
    # riding annotation "row_id", the face ("Güney Yüzü") and, for
    # Tonyukuk, the stone ("Birinci Taş") as "face"/"stone".
    #
    # The PRIMARY TEXT is the runiform original (Göktürk Türkçesi (aslı) —
    # Old Turkic script, U+10C00 block), language otk, script Orkh. The
    # other three columns ride the passage's annotations under the
    # family's layer keys: "transliteration" (Harf çevirisi — the
    # letter-by-letter rendering, upstream's case-coded letters verbatim:
    # capitals the back-vowel letters), "transcription" (Çeviri yazı — the
    # vocalized reading) and "translation" (Türkiye Türkçesi çevirisi, the
    # modern Turkish rendering; its language rides "translation_language"
    # tur). The translation is a TranslationKeys layer, the transcription an
    # AnnotationKeys layer (both searchable); the transliteration is held
    # unindexed (a case-coded letter string no reader types).
    #
    # Fallback: a row whose runiform cell carries no Old Turkic letter
    # keeps that cell verbatim as its text — upstream's lacuna marker,
    # "[...]:" — and says so (annotation "text_layer" => "lacuna", script
    # none). Census: 2 rows, Bilge Kağan B8 and B9, lost on the stone in
    # every column; every other row carries runiform. The page's own
    # "[...]" lacunae inside lines stay verbatim.
    #
    # == Axes
    #
    # Dates (MetadataDates :structured): Kül Tigin 732 and Bilge Kağan 735
    # from the texts' own date lines — KT KD1 (the monument finished in the
    # biçin, monkey, year, 7th month 27th day; Kül Tigin died in the koyun,
    # sheep, year) and BK G10 (Bilge Kağan died in the it, dog, year 10th
    # month 26th; his yoğ in the lağzın, pig, year 5th month 27th) — the
    # stones' own dates, no class; the page gives only the animal-cycle
    # years, the CE years are the standard conversion (raw says so).
    # Tonyukuk carries no date line: c. 716–726 is ATTRIBUTED (after
    # Qapağan Kağan's death, in Bilge Kağan's reign) — class composition,
    # raw saying it is attributed. Places: the pages state none; the
    # census names the monuments' findspots (still in situ) — Khöshöö
    # Tsaidam in the Orkhon valley for Kül Tigin and Bilge Kağan, Bain
    # Tsokto in the Tuul valley for Tonyukuk — as named places (no
    # gazetteer ref minted). Kind: the census's genre label, folded in
    # config/kind_map.yml.
    #
    # == License and provenance
    #
    # The texts are 8th-century inscriptions, public domain; the wiki layer
    # (transliteration, transcription, translation, row division) is the
    # site's: "Metin Creative Commons Atıf-BenzerPaylaşım Lisansı
    # altındadır ve ek koşullar uygulanabilir." (tr.wikisource.org footer,
    # verbatim, read 2026-11-27 — the CC BY-SA notice) → attribution, credit the Wikisource
    # contributors. PROVENANCE CAVEAT: the pages name no source edition.
    # Kül Tigin's "Dış bağlantılar" lists two web transcriptions
    # (turkbitig.com's Kültigin Anıtı, orhunyazitlari.appspot.com's
    # Kültiğin Anıtı Metini) and a bibliography — Tekin, Orhon Yazıtları
    # (1995; Simurg 2nd ed. 1998), Ata, Orhun Türkçesi (2011), and six
    # articles; Bilge Kağan and Tonyukuk link only a turkbitig.com archive
    # copy. The bibliography rides document metadata verbatim
    # ("bibliography").
    class TrWikisource < Nabu::Adapter
      API_URL = "https://tr.wikisource.org/w/api.php"
      CATEGORY = "Kategori:Orhun Abideleri"
      LANDING_TITLES = ["Orhun Yazıtları"].freeze
      URN_PREFIX = "urn:nabu:tr-wikisource:"
      LANGUAGE = "otk"
      TRANSLATION_LANGUAGE = "tur"
      # An Old Turkic (runiform) letter — Unicode's Old Turkic block.
      RUNIFORM = /[\u{10C00}-\u{10C4F}]/
      # MediaWiki redirect in any interface language (tr: #YÖNLENDİRME).
      REDIRECT = /\A\s*#\s*(?:redirect|yönlendirme|YÖNLENDİRME)/i

      # One censused inscription. +date+ the structured MetadataDates shape;
      # +place+ the monument's findspot; +genre+ the kind_map.yml label.
      Work = Data.define(:key, :pageid, :title, :author, :date, :place, :genre, :note)

      def self.dated(first, last = first, raw:, klass: nil)
        { "not_before" => first, "not_after" => last, "class" => klass, "raw" => raw }.compact
      end

      ORKHON = "Khöshöö Tsaidam, Orkhon valley (Mongolia)"

      WORKS = [
        Work.new(key: "kul-tigin", pageid: 5093,
                 title: "Kül Tigin yazıtı (the Kül Tigin inscription)",
                 author: "Yollığ Tigin (the text's own signature, GD1 and GB1), in the voice of Bilge Kağan",
                 date: dated(732, raw: "732 — the text's own date line (KD1): the monument finished in the " \
                                       "biçin (monkey) year, 7th month, 27th day; Kül Tigin died in the koyun " \
                                       "(sheep) year (731). The page gives the animal-cycle years only; the CE " \
                                       "year is the standard conversion"),
                 place: ORKHON, genre: "royal memorial inscription",
                 note: "seven faces: south 13, east 40, north 13 lines, the north-east, south-east, " \
                       "south-west and west edges one line each"),
        Work.new(key: "bilge-kagan", pageid: 5095,
                 title: "Bilge Kağan yazıtı (the Bilge Kağan inscription)",
                 author: "Yollığ Tigin (the text's own signature, GB1), in the voice of Bilge Kağan",
                 date: dated(735, raw: "735 — the text's own date line (G10): Bilge Kağan died in the it (dog) year, " \
                                       "10th month, 26th day (734); his yoğ (funeral feast) held in the lağzın " \
                                       "(pig) year, 5th month, 27th day (735). The page gives the animal-cycle " \
                                       "years only; the CE years are the standard conversion"),
                 place: ORKHON, genre: "royal memorial inscription",
                 note: "six faces: east 41, south-east 1, south 15, north 15, west 9, south-west 1 lines; " \
                       "west B8–B9 lost in every column"),
        Work.new(key: "tonyukuk", pageid: 5096,
                 title: "Tonyukuk yazıtı (the Tonyukuk inscription)",
                 author: "Bilge Tonyukuk (the text's own first person)",
                 date: dated(716, 726, klass: "composition",
                                       raw: "c. 716–726 — ATTRIBUTED: the text carries no date line; after " \
                                            "Qapağan Kağan's death (716), in Bilge Kağan's reign, before " \
                                            "Tonyukuk's death — the standard dating, the page states none"),
                 place: "Bain Tsokto, Tuul valley (Mongolia)", genre: "monumental inscription",
                 note: "two stones, four faces each: 7, 10, 7, 11 and 9, 6, 8, 4 lines")
      ].freeze

      WORK_BY_PAGE = WORKS.to_h { |work| [work.pageid, work] }.freeze

      # The census's skipped main-namespace pages, pageid → class.
      REJECTED = { 5338 => :landing }.freeze

      RULE_NOTES = {
        landing: "landing/disambiguation page(s) — navigation, no text of their own",
        other_namespace: "non-main-namespace member(s) (Kategori/Dosya/Şablon/Vikikaynak)",
        redirect: "redirect page(s)"
      }.freeze

      MANIFEST = Nabu::SourceManifest.new(
        id: "tr-wikisource",
        name: "Turkish Wikisource — the Orkhon inscriptions (Kül Tigin, Bilge Kağan, Tonyukuk)",
        license: "Texts public domain (8th-century inscriptions); the wiki layer: \"Metin Creative " \
                 "Commons Atıf-BenzerPaylaşım Lisansı altındadır ve ek koşullar uygulanabilir.\" " \
                 "(tr.wikisource.org footer, verbatim, read 2026-11-27 — CC BY-SA) → attribution, " \
                 "credit the Wikisource contributors",
        license_class: "attribution",
        upstream_url: "https://tr.wikisource.org/wiki/Kategori:Orhun_Abideleri",
        parser_family: "orkhon-wikisource",
        credit: "Turkish Wikisource (tr.wikisource.org) contributors, CC BY-SA"
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
      # (a page that leaves the category keeps its envelope), so there is
      # no breaker to override.
      def fetch(workdir, progress: nil, force: false) # rubocop:disable Lint/UnusedMethodArgument
        @requests = 0
        @census = nil
        members = crawl_members
        stale = members.reject { |pageid, info| held_revid(workdir, pageid) == info["revid"] }
        progress&.call("#{members.size} page(s), #{stale.size} new or edited\n")
        stale.values.map { |info| info["title"] }.each_slice(Nabu::WikiFetch::CONTENT_BATCH) do |batch|
          pages_payload(batch).each { |page| write_envelope!(workdir, page, members.fetch(page["pageid"])) }
        end
        pin = members.keys.sort.to_h { |pageid| [pageid.to_s, members[pageid]["revid"]] }
        sha = Digest::SHA256.hexdigest(JSON.generate(pin))
        write_state!(workdir, sha)
        Nabu::FetchReport.new(sha: sha, fetched_at: Time.now,
                              notes: "pages: #{stale.size} fetched, #{members.size - stale.size} cached " \
                                     "(#{members.size} pages: #{CATEGORY} + #{LANDING_TITLES.size} landing)")
      end

      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        census(workdir).each do |path, envelope, klass|
          next unless klass == :text

          work = WORK_BY_PAGE.fetch(envelope.fetch("pageid"))
          yield Nabu::DocumentRef.new(source_id: MANIFEST.id, id: "#{URN_PREFIX}#{work.key}",
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
        raise ParseError, "#{document_ref.id}: no inscription rows extracted" if result.rows.empty?

        document = Nabu::Document.new(
          urn: document_ref.id, language: LANGUAGE, title: Normalize.nfc(work.title),
          canonical_path: document_ref.path, metadata: metadata_for(envelope, work, result)
        )
        result.rows.each_with_index do |row, index|
          document << passage(document_ref.id, row, index + 1)
        end
        document
      end

      private

      def parser
        @parser ||= OrkhonWikisourceParser.new
      end

      def passage(doc_urn, row, sequence)
        runiform = row.runiform.match?(RUNIFORM)
        annotations = {
          "row_id" => row.row_id, "face" => row.face, "stone" => row.stone,
          "script" => runiform ? "Orkh" : "none",
          "text_layer" => runiform ? nil : "lacuna",
          "transliteration" => row.transliteration, "transcription" => row.transcription,
          "translation" => row.translation, "translation_language" => TRANSLATION_LANGUAGE
        }.compact.transform_values { |value| Normalize.nfc(value) }
        Nabu::Passage.new(urn: "#{doc_urn}:#{row.cite}", language: LANGUAGE, text: Normalize.nfc(row.runiform),
                          sequence: sequence, annotations: annotations)
      end

      # -- fetch internals ---------------------------------------------------

      # pageid → {"title", "revid" (upstream's lastrevid), "categories"}: the
      # category's members, then the landing titles (merged by pageid).
      def crawl_members
        members = {}
        continue = {}
        loop do
          payload = get_json("action" => "query", "format" => "json", "generator" => "categorymembers",
                             "gcmtitle" => CATEGORY, "gcmlimit" => "500", "prop" => "info", **continue)
          record_members!(members, payload, category: CATEGORY)
          continue = payload["continue"]&.except("continue") or break
        end
        payload = get_json("action" => "query", "format" => "json", "prop" => "info",
                           "titles" => LANDING_TITLES.join("|"))
        record_members!(members, payload, category: nil)
        members
      end

      def record_members!(members, payload, category:)
        (payload.dig("query", "pages") || {}).each_value do |page|
          next if page.key?("missing")

          entry = members[page.fetch("pageid")] ||= { "title" => page.fetch("title"), "categories" => [] }
          entry["revid"] = page["lastrevid"]
          entry["categories"] |= [category] if category
        end
      end

      def pages_payload(batch)
        payload = get_json("action" => "query", "format" => "json", "prop" => "revisions|categories",
                           "rvprop" => "content|ids|timestamp", "rvslots" => "main", "cllimit" => "500",
                           "titles" => batch.join("|"))
        (payload.dig("query", "pages") || {}).values.reject { |page| page.key?("missing") }
      end

      def write_envelope!(workdir, page, member)
        revision = page.dig("revisions", 0) or return
        categories = (page["categories"] || []).map { |category| category["title"] } | member["categories"]
        envelope = {
          "title" => page.fetch("title"), "pageid" => page.fetch("pageid"), "ns" => page["ns"] || 0,
          "revid" => revision["revid"], "timestamp" => revision["timestamp"],
          "categories" => categories.sort, "wikitext" => revision.dig("slots", "main", "*").to_s
        }
        dir = File.join(workdir, Nabu::WikiFetch::PAGES_DIRNAME)
        FileUtils.mkdir_p(dir)
        target = File.join(dir, "#{envelope['pageid']}.json")
        File.binwrite("#{target}.tmp", "#{JSON.pretty_generate(envelope)}\n")
        File.rename("#{target}.tmp", target)
      end

      def held_revid(workdir, pageid)
        path = File.join(workdir, Nabu::WikiFetch::PAGES_DIRNAME, "#{pageid}.json")
        File.file?(path) ? JSON.parse(SourceRead.utf8_file(path, label: "tr-wikisource envelope"))["revid"] : nil
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

      # [path, envelope, class] per held page, in pageid order.
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
        envelope = JSON.parse(SourceRead.utf8_file(path, label: "tr-wikisource envelope"))
        raise ParseError, "#{path}: page envelope has no wikitext" unless envelope["wikitext"].is_a?(String)

        envelope
      rescue JSON::ParserError, Errno::ENOENT => e
        raise ParseError, "#{path}: unreadable page envelope: #{e.message}"
      end

      def metadata_for(envelope, work, result)
        {
          "work" => work.key, "work_title" => work.title, "author" => work.author,
          "date" => work.date, "place" => work.place, "genre" => work.genre,
          "facets" => { "genre" => { "value" => work.genre } }, "note" => work.note,
          "faces" => result.faces.map do |face|
            { "stone" => face.stone, "face" => face.face, "caption" => face.caption,
              "declared_lines" => face.declared_lines, "lines" => face.lines }.compact
          end,
          "bibliography" => result.bibliography,
          "base_edition" => "unstated — the page names no source edition (see bibliography)",
          "wiki_title" => envelope["title"], "wikipedia" => result.header["vikipedi"],
          "pageid" => envelope["pageid"], "revid" => envelope["revid"],
          "url" => "https://tr.wikisource.org/wiki/#{envelope['title'].tr(' ', '_')}"
        }.compact.then { |meta| nfc_strings(meta) }
      end

      def nfc_strings(value)
        case value
        in String then Normalize.nfc(value)
        in Array then value.map { |item| nfc_strings(item) }
        in Hash then value.transform_values { |item| nfc_strings(item) }
        else value
        end
      end
    end
  end
end

# frozen_string_literal: true

require_relative "../bu_ajami_fetch"
require_relative "../pdf_text"
require_relative "bu_ajami_item_parser"

module Nabu
  module Adapters
    # bu-ajami — Boston University's NEH Ajami collection (P124-1;
    # sites.bu.edu/nehajami, PI Fallou Ngom; NEH-funded): 80 manuscripts,
    # 20 each in Hausa, Mandinka, Fula (Fuuta Jalon Pular) and Wolof, each
    # an item page with metadata, manuscript images, an English and a
    # French translation, and a TYPED TRANSCRIPTION PDF — the text this
    # source serves. The library's first holdings in all four languages.
    #
    # == What the text is (declared on every document)
    #
    # The manuscripts are written in Ajami (Arabic script adapted to the
    # African language: upstream's Script field — "Hausa Ajami", "Wolof
    # Ajami", …); the transcriptions are the editors' ROMANIZATION of them
    # (Latin script, the languages' standard orthographies, Arabic phrases
    # in ALA-LC-style transliteration). The passage text is that Latin
    # transcription; metadata "text_script" says so and
    # "manuscript_script" keeps upstream's script field verbatim.
    #
    # == Documents and passages
    #
    # One document per item whose transcription PDF is held —
    # urn:nabu:bu-ajami:<lang>:<slug> (upstream's own URL path words) —
    # and one passage per non-blank PDF page, :p<n> (the house PDF grain,
    # Nabu::PdfText: the page is the only unit a PDF keeps stable). The
    # Word-generated PDFs (census 2026-10-13: 80 of 80 carry a text layer,
    # 705 pages, ~860k characters) carry the editors' citation block
    # ("Citation: Fallou Ngom (PI), … 2022. “Title.” <url>.") as a running
    # header at the head of every page (above the page number, or below it
    # on six items): it is cut from every page and the first copy moves to
    # metadata "pdf_citation" (all 80 items). Everything else stays verbatim, the
    # Word page-number line included (it cannot be told from numeral
    # content — one item is a numerology manual with number tables), and
    # the transcription's own manuscript-page markers ("[Page 3]",
    # "[Document 1: Page 1]", "[Page 3, Column 2]") stay in the text and
    # ride annotations "ms_pages". Whitespace: lines stripped, runs folded,
    # blank lines dropped (Word double-spaces every line).
    #
    # == Language (the honest grain)
    #
    # Per item from upstream's own section: hausa → ha, mandinka → mnk,
    # wolof → wo, fula → fuf (upstream: "Fuuta Jalon Fula" — Pular, the
    # 639-3 individual language, not the ff macrolanguage). Two items say
    # "… and Arabic" / "with interlinear glosses in Arabic": the Arabic is
    # transliterated inside the African-language text and rides the same
    # claim; upstream's Language field rides "upstream_language" verbatim.
    #
    # == Mined metadata (the aggressive-mining policy)
    #
    # Every table field rides metadata under a stable key (unknown labels
    # kept under "other_fields"); Provenance is also the PLACE claim (the
    # manuscript's provenance: Touba, Kano, Sedhiou, Labé, …); Genre feeds
    # the genre facet (Poetry/Prose/…), Subject the subject facet (one row
    # per comma-separated topical heading — #facets_for). DATES — the item table has no date
    # field, so dating comes from two honest lanes:
    #   * a TYPED year in the source reference — Northwestern's catalog
    #     form “Title” (1968/9) — an artifact/catalog date (typed_date);
    #   * the curated DATES table: dates the item page STATES in prose
    #     (each with its verbatim basis) — witness dates ("completed on
    #     July 28, 1990", a printed source's imprint year) as plain dates,
    #     and authorship eras ("written by Serigne Moussa Ka (1889-1963)")
    #     as the composition class (the attributed-era class, ruled
    #     2026-09-26). Subjects' lifespans and inferred termini are NOT
    #     claimed. The table wins over the typed year.
    #
    # == License
    #
    # CC BY-NC 4.0, stated verbatim on every item page (the "Access
    # condition and copyright" field, carried per document as "rights"):
    # credit the original author and source; beyond those terms, contact
    # Professor Fallou Ngom. Each item's required citation rides
    # "citation".
    class BuAjami < Nabu::Adapter
      ITEM_BASE = "https://sites.bu.edu/nehajami/the-four-languages"
      LANGUAGES = { "fula" => "fuf", "hausa" => "ha", "mandinka" => "mnk", "wolof" => "wo" }.freeze
      TEXT_SCRIPT = "Latin — the editors' romanized transcription of the Ajami (Arabic-script) manuscript"

      FIELD_KEYS = {
        "Title" => "title", "Author or Owner" => "author_or_owner", "Subject" => "subject",
        "Content" => "summary", "Genre" => "genre", "Language" => "upstream_language",
        "Script" => "manuscript_script", "Manuscript condition" => "manuscript_condition",
        "Type" => "manuscript_type", "Publisher" => "publisher", "Provenance" => "provenance",
        "Source Reference" => "source_reference", "Access condition and copyright" => "rights",
        "Contributors" => "contributors", "Required citation information" => "citation",
        "Required citation" => "citation"
      }.freeze

      CITATION_HEAD = /\A\s*Citation\s*:/
      PAGE_NUMBER_LINE = /\A\s*\d{1,3}\s*\z/
      # The longest citation block censused is 3 lines; a block that has
      # not closed by this many lines is not the citation header.
      CITATION_MAX_LINES = 6
      MS_MARKER = /\[((?:Document \d+:\s*)?Pages? [^\]\n]{1,24})\]/
      TYPED_YEAR = %r{[”"]\s*\((\d{4})(?:\s*/\s*(\d{1,4}))?\)}

      def self.dated(first, last, basis, composition: false)
        date = { "not_before" => first, "not_after" => last,
                 "raw" => first == last ? first.to_s : "#{first}–#{last}", "basis" => basis }
        composition ? date.merge("class" => "composition") : date
      end

      # Dates the item pages STATE (census 2026-10-13, all 80 pages read);
      # the basis quotes upstream — a Content sentence (elisions marked …)
      # or, for a printed source, its Source Reference imprint.
      DATES = {
        "hausa/falke-1041-1-tabbat-haqiqan-2" =>
          dated(1754, 1817, "This poem was written by Shehu Usman Ɗan Fodio (1754-1817).", composition: true),
        "hausa/falke-1569-wakar-nasara" =>
          dated(1903, 1903, "He wrote this poem in 1903", composition: true),
        "hausa/falke-2729-wakar-sarkin-kano" =>
          dated(1953, 1953, "The poem deals with the Emir’s trip to England in 1953 … the poet composed the " \
                            "song while the Emir was on a trip to London.", composition: true),
        "hausa/hunwick-95-1-godaben-gaskiya" =>
          dated(1793, 1864, "a panegyric poem composed by Nana Asma’u (1793-1864)", composition: true),
        "hausa/hunwick-95-2-tabbat-haqiqan-1" =>
          dated(1793, 1864, "This poem is composed by Nana Asma’u (1793-1864)", composition: true),
        "hausa/hunwick-95-3-nana-asmaau-waazi" =>
          dated(1855, 1857, "The final verse suggests that it was completed between 1855 and 1857 CE.",
                composition: true),
        "hausa/infiraji-1-majidu" =>
          dated(1894, 1990, "nine poems composed by Alhaji Aliyu Namangi (1894-1990)", composition: true),
        "hausa/infiraji-2-gargadi" =>
          dated(1894, 1990, "Alhaji Aliyu Namangi (1894-1990)", composition: true),
        "mandinka/arfang-bajinka-i-tuloo-loo" =>
          dated(1857, 1971, "a copy of a Mandinka Ajami poem written by … Sitookoto Daabo (1857-1971)",
                composition: true),
        "mandinka/kitaaboo-foloota" =>
          dated(1857, 1971, "a copy of the Mandinka religious poem by Sitookoto Daabo (1857-1971)",
                composition: true),
        "mandinka/ni-yaa-je" =>
          dated(1857, 1971, "a copy of a poem by Sitookoto Daabo (1857-1971)", composition: true),
        "mandinka/yaa-rabbi" =>
          dated(1857, 1971, "a copy of a poem by Sitookoto Daabo (1857-1971)", composition: true),
        "mandinka/heerebaa-daraame-la-lasiloo-2" =>
          dated(1977, 1977, "Foode Alaaji Daraame, the current owner, copied it in 1977."),
        "fula/mantugol-nelaado-1" =>
          dated(1755, 1852, "an excerpt from Oogirde Malal (The Vein of Eternal Happiness) written by Cerno " \
                            "Samba Mombeya (1755-1852)", composition: true),
        "fula/deftere-tumbondiral" =>
          dated(2000, 2006, "Two letters, one from October 23, 2005 and another from December 17, 2000 … " \
                            "A letter written on October 4, 2006"),
        "fula/jokkere-endan-3" =>
          dated(2006, 2009, "The documents were written between 2006 and 2009 in Dakar, Senegal."),
        "fula/kuude-lette-3" =>
          dated(1990, 1990, "This manuscript was completed on July 28, 1990."),
        "wolof/bakk-wi" =>
          dated(1889, 1963, "The poem was written by … Serigne Moussa Ka also known as Muusaa Ka (1889-1963).",
                composition: true),
        "wolof/marsiya-serin-masamba-mbakke" =>
          dated(1889, 1963, "The poem was written by … Serigne Moussa Ka also known as Sëriñ Muusaa Ka " \
                            "(1889-1963).", composition: true),
        "wolof/wolofalu-jumaa-ji" =>
          dated(1932, 1963, "It consists of 1647 verses, written between 1932 and 1963.", composition: true),
        "wolof/xarbaaxi-yonnen-bi" =>
          dated(1869, 1951, "a poem written by Serigne Mor Kayre (also known as Sëriñ Moor Kayre, 1869-1951)",
                composition: true),
        "wolof/xareb-badar-bu-njekk-ba" =>
          dated(1869, 1951, "a poem written by Serigne Moor Kayre (1869-1951)", composition: true),
        "wolof/speech-1-tabaski-1972" =>
          dated(1972, 1972, "a speech made by Sëriñ Abdul Ahad Mbakke on the day of Tabaski 1972"),
        "wolof/speech-2-korite-1971-1972" =>
          dated(1971, 1972, "a speech made by Sëriñ Abdul Ahad Mbakke on the day of Korite 1971 or 1972"),
        "wolof/ndigel-1" =>
          dated(1980, 1989, "a report of the activities of a Murid organization based in Europe, written in " \
                            "the 1980s"),
        "wolof/soxna-asta-waalo-mbakke" =>
          dated(2015, 2015, "source: Jaar-Jaari Magi Murid yi: Xaaj bu Njëkk (Touba: Université du Magal, 2015)"),
        "wolof/soxna-aysatu-mbakke-kajoor" =>
          dated(2015, 2015, "source: Jaar-Jaari Magi Murid yi: Xaaj bu Njëkk (Touba: Université du Magal, 2015)"),
        "wolof/soxna-faati-ja-mbakke" =>
          dated(2015, 2015, "source: Jaar-Jaari Magi Murid yi: Xaaj bu Njëkk (Touba: Université du Magal, 2015)"),
        "wolof/soxna-maam-jaaratul-laahi-buso" =>
          dated(2015, 2015, "source: Jaar-Jaari Magi Murid yi: Xaaj bu Njëkk (Touba: Université du Magal, 2015)"),
        "wolof/yoonu-murid" =>
          dated(2021, 2021, "source: Yoonu Murid (Dakar: Dāʾiratu Kanzu l-Muhtadīn / Sinkkimpression, 2021)")
      }.freeze

      MANIFEST = Nabu::SourceManifest.new(
        id: "bu-ajami",
        name: "African Ajami Library — NEH Ajami collection (Boston University): Hausa, Mandinka, " \
              "Fula and Wolof manuscripts in romanized transcription",
        license: "Creative Commons Attribution-Non-Commercial 4.0 (CC BY-NC 4.0), stated verbatim on " \
                 "every item page: \"distributed under the terms of the Creative Commons Attribution-" \
                 "Non-Commercial 4.0 License, which permits non-commercial use, distribution, and " \
                 "reproduction in any medium, provided the original author and source are credited. For " \
                 "use, distribution or reproduction beyond these terms, contact Professor Fallou Ngom " \
                 "(fngom@bu.edu).\" Credit: Fallou Ngom (PI) and the project's editors and contributors " \
                 "(per item), Boston University; each item's required citation rides its metadata",
        license_class: "nc",
        upstream_url: "https://sites.bu.edu/nehajami/",
        parser_family: "bu-ajami-html"
      )

      def self.manifest = MANIFEST

      def self.remote_probe_strategy = :http_zip

      # Liveness only: the walk's state is the listing's modified stamps,
      # not a Last-Modified pin — drift honestly reads unknown.
      def self.http_probe_targets
        [Nabu::Adapter::HttpProbeTarget.new(
          label: "wp-json pages listing", zip_url: Nabu::BuAjamiFetch.list_url(1), metadata_url: nil,
          state_subdir: "", liveness_only: true
        )]
      end

      # A typed year in Northwestern's catalog form — “Title” (1968/9) —
      # as a date hash; nil for "(nd)" or anything else (a digitization
      # project's year is never read).
      def self.typed_date(reference)
        match = TYPED_YEAR.match(reference.to_s) or return nil
        first = Integer(match[1], 10)
        last = match[2] ? Integer(match[1][0, 4 - match[2].size] + match[2], 10) : first
        return nil if last < first

        { "not_before" => first, "not_after" => last, "raw" => match[0].sub(/\A[”"]\s*/, ""),
          "basis" => "the source reference's typed year" }
      end

      # +pdf_text+ is the text-layer seam (path → Array of page strings,
      # Nabu::PdfText.pages' contract), injectable so the suite never
      # depends on mutool being installed.
      def initialize(pdf_text: PdfText.method(:pages), delay: Nabu::BuAjamiFetch::DELAY)
        super()
        @pdf_text = pdf_text
        @delay = delay
      end

      def fetch(workdir, progress: nil, force: false) # rubocop:disable Lint/UnusedMethodArgument
        result = Nabu::BuAjamiFetch.sync!(dir: workdir, delay: @delay, progress: progress)
        notes = "#{result.held}/#{result.listed} listed item(s) held (+#{result.pages_fetched} page(s), " \
                "+#{result.pdfs_fetched} transcription PDF(s) this sync)"
        notes += "; unreachable, retried next sync: #{result.failed.join(', ')}" unless result.failed.empty?
        progress&.call("#{notes}\n")
        Nabu::FetchReport.new(sha: result.sha, fetched_at: Time.now, notes: notes)
      rescue Nabu::BuAjamiFetch::Error => e
        raise Nabu::FetchError, "bu-ajami fetch failed into #{workdir}: #{e.message}"
      end

      # One ref per held item page whose transcription PDF is held too.
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        Dir.glob(File.join(workdir, Nabu::BuAjamiFetch::ITEMS_DIR, "*", "*.html")).each do |page|
          lang = File.basename(File.dirname(page))
          next unless LANGUAGES.key?(lang)

          pdf = held_pdf(workdir, page) or next
          slug = File.basename(page, ".html")
          yield Nabu::DocumentRef.new(source_id: MANIFEST.id, id: "urn:nabu:#{MANIFEST.id}:#{lang}:#{slug}",
                                      path: File.expand_path(pdf),
                                      metadata: { "lang" => lang, "slug" => slug,
                                                  "item_page" => File.expand_path(page) })
        end
      end

      def parse(document_ref)
        lang = document_ref.metadata.fetch("lang")
        slug = document_ref.metadata.fetch("slug")
        item = BuAjamiItemParser.parse_file(document_ref.metadata.fetch("item_page"))
        language = LANGUAGES.fetch(lang)
        raw_pages = read_pages(document_ref.path)
        citation, pages = split_pages(raw_pages)
        document = Nabu::Document.new(
          urn: document_ref.id, language: language, canonical_path: document_ref.path,
          title: item.fields.fetch("Title"), metadata: metadata_for(lang, slug, item, citation, raw_pages.size)
        )
        pages.each do |number, text|
          annotations = { "pdf_page" => number }
          markers = text.scan(MS_MARKER).flatten.map { |m| m.gsub(/\s+/, " ").strip }
          annotations["ms_pages"] = markers unless markers.empty?
          document << Nabu::Passage.new(urn: "#{document_ref.id}:p#{number}", language: language, text: text,
                                        sequence: number, annotations: annotations)
        end
        raise Nabu::ParseError, "#{document_ref.path}: no text on any PDF page" if document.passages.empty?

        document
      end

      private

      def held_pdf(workdir, page)
        href = BuAjamiItemParser.parse_file(page).transcription_href
        path = Nabu::BuAjamiFetch.local_pdf_path(workdir, href)
        File.file?(path) ? path : nil
      rescue Nabu::ParseError, Nabu::BuAjamiFetch::Error
        nil
      end

      def read_pages(path)
        @pdf_text.call(path)
      rescue PdfText::Error, Errno::ENOENT => e
        raise Nabu::ParseError, "#{path}: #{e.message}"
      end

      # [first citation block (or nil), [[page number, clean text], …]]
      # — blank pages dropped, numbering kept physical.
      def split_pages(raw_pages)
        citation = nil
        pages = raw_pages.each_with_index.filter_map do |raw, index|
          head, body = cut_citation(raw.to_s)
          citation ||= head
          text = clean(body)
          [index + 1, text] unless text.empty?
        end
        [citation, pages]
      end

      # The citation block: a "Citation:" line at the page head — preceded
      # by nothing but blank lines or the lone Word page-number line (the
      # header sits above the number on most pages, below it on six items)
      # — up to the next whitespace-only line, within CITATION_MAX_LINES.
      def cut_citation(raw)
        lines = raw.split("\n", -1)
        start = lines.index { |line| !line.strip.empty? && !PAGE_NUMBER_LINE.match?(line) }
        return [nil, raw] if start.nil? || !CITATION_HEAD.match?(lines[start])

        length = lines.drop(start).first(CITATION_MAX_LINES).index { |line| line.strip.empty? }
        return [nil, raw] if length.nil?

        head = Normalize.nfc(lines[start, length].join(" ").gsub(/\s+/, " ").strip)
        [head, (lines.first(start) + lines.drop(start + length)).join("\n")]
      end

      def clean(text)
        lines = text.split("\n").map { |line| line.gsub(/[[:blank:]]+/, " ").strip }
        Normalize.nfc(lines.reject(&:empty?).join("\n"))
      end

      def metadata_for(lang, slug, item, citation, page_count)
        meta = {}
        other = {}
        item.fields.each do |label, value|
          key = FIELD_KEYS[label]
          key ? (meta[key] ||= value) : (other[label] = value)
        end
        meta["other_fields"] = other unless other.empty?
        meta["place"] = meta["provenance"]
        facets = facets_for(meta)
        meta["facets"] = facets unless facets.empty?
        meta["date"] = DATES["#{lang}/#{slug}"] || self.class.typed_date(meta["source_reference"])
        meta.merge(
          "collection" => "NEH Ajami (Boston University African Ajami Library)",
          "item_url" => "#{ITEM_BASE}/#{lang}/#{lang}-manuscripts/#{slug}/",
          "transcription_url" => Nabu::BuAjamiFetch.request_url(item.transcription_href),
          "translation_urls" => item.translation_hrefs.transform_values { |h| Nabu::BuAjamiFetch.request_url(h) },
          "manuscript_image_urls" => item.manuscript_hrefs.map { |h| Nabu::BuAjamiFetch.request_url(h) },
          "source_links" => item.source_links,
          "pdf_citation" => citation, "pdf_pages" => page_count,
          "text_script" => TEXT_SCRIPT
        ).reject { |_k, v| v.nil? || (v.respond_to?(:empty?) && v.empty?) }
      end

      # The genre facet (the form label the kind fold reads) and the
      # subject facet: upstream's Subject field is a comma-separated list
      # of topical headings ("History, Biography, Mandinka Society, …" —
      # census 2026-10-21: 80 of 80 items, 426 headings, 285 distinct; no
      # heading carries an inner comma), one facet row per heading. The
      # headings are topical, not genre claims: no kind fold reads them.
      def facets_for(meta)
        facets = {}
        facets["genre"] = { "value" => meta["genre"] } if meta["genre"]
        subjects = meta["subject"].to_s.split(",").map(&:strip).reject(&:empty?)
        facets["subject"] = { "values" => subjects } unless subjects.empty?
        facets
      end
    end
  end
end

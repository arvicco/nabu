# frozen_string_literal: true

require "json"
require_relative "source_read"

module Nabu
  module Adapters
    # ottoman-ocr — OttomanOCR-search (Enes Yılandiloğlu, University of
    # Helsinki; github.com/koras0ff/OttomanOCR-search): machine OCR of 59
    # printed Ottoman Turkish books and serials, 1729–1923 printings, in
    # Arabic script — Evliyâ Çelebi's Seyâhatnâme (8 volumes), the
    # chronicles of Peçevî, Selânikî, Solakzâde, Hoca Sadeddin, Lütfi Paşa
    # and Kâtib Çelebi, the Kanunname-i Âl-i Osman, the dîvâns of Fuzûlî and
    # Nedîm, the fetvâ collections of Yenişehirli Abdullah and Çatalcalı Ali
    # Efendi, Şemseddin Sâmî's Kâmûs-ı Türkî and Kâmûsü'l-aʿlâm, Muallim
    # Nâcî's lexicon, two Turkish New Testaments (1819, 1857), the Düstur,
    # Tanzimat-era plays, novels, poetry, military and law textbooks and
    # four serials. The pages are region- and line-segmented by two custom
    # YOLO26s models and read by the Ottoman-Print-OCR-Qwen4B vision-
    # language model; the page images (public domain) sit on Hugging Face.
    #
    # == License (README + LICENSE, read 2026-11-28 at the pin)
    #
    # README verbatim: "Creative Commons Attribution-NonCommercial 4.0
    # International (CC BY-NC 4.0). https://creativecommons.org/licenses/
    # by-nc/4.0/ The original images are in the public domain. The license
    # applies to the layout and OCR data." LICENSE is the CC BY-NC 4.0 legal
    # code. NonCommercial → class `nc`.
    #
    # == The OCR honesty flag (rides every document)
    #
    # metadata "text_nature" = "uncorrected-ocr" + OCR_NOTE + a measured
    # "ocr_latin_line_share" (text lines carrying any Latin letter — the
    # VLM's code-switch hallucination signature, "قضanak", "منزelnی", beside
    # genuine Latin print: library plates, the Kâmûsü'l-aʿlâm's French name
    # forms). Census of the whole pin through this adapter (2026-11-28):
    # 95.7 % of the 10.9 M non-space characters are Arabic-script, 0.20 %
    # Latin; 3,188 of the 270,810 passage text lines (1.18 %) carry a Latin
    # letter — 910 of the 10,374 lines of the Kâmûsü'l-aʿlâm (8.77 %, mostly
    # printed French name forms), 2,278 of the other 260,436 (0.87 %); no
    # U+FFFD, no control or bidi characters; 24 entries repeat a token four
    # times running, all of them table-of-contents dot leaders (no
    # generation loops). Never proofread: read it as a finding aid, cite
    # the page image.
    #
    # == Delivery grains (the census of the pin, every file read)
    #
    # - TAKEN: data/<work>.js — one per manifest work (59), the JSON object
    #   {id, title, nw, nc, pages} behind `window.__W["<work>"]=`. Document =
    #   work (a multi-volume work is one document per upstream volume file:
    #   Evliyâ ×8, Peçevî ×2), urn:nabu:ottoman-ocr:<work>; upstream's own
    #   file stem is the stable key. data/manifest.js (`window.__MANIFEST=`)
    #   is the catalogue the metadata is mined from, not a document.
    # - Passage = PAGE (`{n, im, w, h, R, L}`): urn …:<work>:<n>, n
    #   upstream's page label — the 1-based image ordinal, or "3–4" for a
    #   two-page spread photographed as one image (cited "3-4", the en dash
    #   folded to an ASCII hyphen in the URN only). Text = the page's L
    #   entries' text joined by "\n" in upstream order, every region class
    #   (text column, heading, running header, footnote, marginalia,
    #   catchword, table) except page_number, whose text rides the
    #   annotation "printed_page" — page furniture, the printed folio.
    #   Upstream is NOT line-grained throughout: 8,599 of the 187,917
    #   non-empty L entries carry a whole region's text with embedded
    #   newlines, so the page is the one grain every work shares (and the
    #   grain the upstream viewer cites).
    # - Dropped: the line polygons and region boxes (L[1], R — layout
    #   geometry, no text), the region index L[3], the image size. The
    #   image file rides per passage ("image"; the URL prefix rides the
    #   document's "image_base").
    # - Untranscribed pages mint nothing: 16,837 of the 24,375 pages carry
    #   no text (680,866 of the 868,783 L entries are segmented lines with
    #   an empty string — upstream OCR'd only part of most volumes: Evliyâ
    #   vol. 1 130 of 698 pages), and 59 more carry only a page number.
    #   Counted per document ("pages", "text_pages").
    # - REJECTED by rule, per page: the colour-calibration charts (`"cal":
    #   true`, page label "-"; 9 pages, all textless) — counted per
    #   document ("calibration_pages"), never a passage.
    # - REJECTED by rule, per file (discovery_skips): transcriptions_
    #   ziyapasa.json at the root — an earlier line-JSON transcription of 73
    #   pages of the Eşʿâr-ı Ziyâ, which data/esariziyapasa.js re-delivers
    #   (only 931 of its 3,615 distinct lines recur verbatim: a superseded
    #   OCR pass; the viewer never loads it).
    # - REJECTED at the fetch (outside the sparse cone): index.html (the
    #   viewer), yolo26s_region_printed_24_06_2026.pt (the region model),
    #   .nojekyll.
    #
    # Reconciliation: 59 manifest works = 59 data/*.js beside manifest.js
    # (none unlisted, none missing); their pages sum to 24,375 = the
    # manifest's own page counts, work by work = 7,470 passages + 16,837
    # textless + 59 page-number-only + 9 calibration pages; words
    # 2,501,215 = the manifest's `words` total (whitespace tokens of every
    # text entry), 2,485,641 of them in passage text (the rest are the
    # printed page numbers).
    #
    # == Page order
    #
    # 18 works — the University of Toronto scans (…uoft: Evliyâ, Peçevî,
    # Selânikî, Hoca Sadeddin, Lütfi Paşa …) and four more — were imaged
    # back to front: their printed page numbers DESCEND through upstream's
    # image order. Upstream's order is kept (it is upstream's citation);
    # the document declares "page_order" = "descending", measured at parse
    # time from the printed page numbers, and every passage carries its
    # printed page.
    #
    # == Axes
    #
    # Dates: a work is dated by its COMPOSITION where author and era are
    # textbook-certain (COMPOSITION — 21 documents, each with its reason,
    # class composition); otherwise by its print year (upstream's typed
    # year_min/year_max; a Hijri-only label converted to its CE envelope)
    # as class edition. The print years ride "print_year"/"print_year_ah"
    # either way. One work (Kavâʿid-i esâsiye-i harbiye) carries neither.
    # Places: upstream types no place; the press ("publisher": Matbaa-i
    # Âmire, İkdâm Matbaası …) is the printing's imprint, never the text's
    # place — declared, no claim. Kind: the per-work fold in
    # config/kind_map.yml over metadata "work" (upstream's genre is "book/
    # printed material" or "periodicals"; its subjects ride "subjects").
    #
    # == Fetch
    #
    # Sparse GitFetch (attic + mass-deletion breaker) of the data/ files,
    # the root JSON grain and the licence files, PINNED: the repository is
    # under active revision (metadata normalized and the LICENSE fixed
    # 2026-10-31), so a moved HEAD is an event to review (licence + text +
    # metadata), never a cadence — the fetch aborts loudly on drift. A git
    # checkout's identity is its HEAD; nothing is materialized beside it.
    class OttomanOcr < Nabu::Adapter
      SLUG = "ottoman-ocr"
      LANGUAGE = "ota"
      REPO_URL = "https://github.com/koras0ff/OttomanOCR-search"

      # main HEAD at the 2026-11-28 census ("Fix LICENSE text; add volume
      # numbers to Peçevî and New Testament titles", 2026-10-31).
      PINNED_SHA = "bac65b67166cd55033263c0d5f4b204b3d6d81e1"

      SPARSE_PATHS = ["data/*.js", "README.md", "LICENSE", "transcriptions_ziyapasa.json"].freeze

      DATA_DIR = "data"
      MANIFEST_FILE = File.join(DATA_DIR, "manifest.js")
      MANIFEST_PREFIX = "window.__MANIFEST="

      # The rejected root grains (class note), workdir-relative => why.
      REJECTED_FILES = {
        "transcriptions_ziyapasa.json" =>
          "an earlier line-JSON OCR pass over 73 pages of the Eşʿâr-ı Ziyâ, superseded by data/esariziyapasa.js"
      }.freeze

      LICENSE = "CC BY-NC 4.0 — README verbatim: \"Creative Commons Attribution-NonCommercial 4.0 International " \
                "(CC BY-NC 4.0). https://creativecommons.org/licenses/by-nc/4.0/ The original images are in the " \
                "public domain. The license applies to the layout and OCR data.\" (read 2026-11-28 at commit " \
                "bac65b6); LICENSE carries the CC BY-NC 4.0 legal code"

      CREDIT = "OttomanOCR-search, Enes Yılandiloğlu (University of Helsinki), github.com/koras0ff/OttomanOCR-search " \
               "— OCR by the Ottoman-Print-OCR-Qwen4B model, layout by YOLO26s region and line models; page images " \
               "from archive.org, the Library of Congress, HathiTrust and the Digital Bible Society scans."

      OCR_NOTE = "Uncorrected machine OCR (the Ottoman-Print-OCR-Qwen4B vision-language model over YOLO-segmented " \
                 "page images), never proofread: the Arabic-script text reads approximately; stray Latin letters " \
                 "inside Ottoman words are model hallucinations. Cite the page image (image_base + image)."

      # The composition-era table (class note): work => the structured date.
      # Only works whose author and era are textbook-certain; every raw
      # opens "ATTRIBUTED: " and gives the reason.
      def self.composed(first, last, reason)
        { "not_before" => first, "not_after" => last, "class" => "composition", "raw" => "ATTRIBUTED: #{reason}" }
      end

      EVLIYA = composed(1640, 1685, "Evliyâ Çelebi (1611–after 1683): the journeys of 1640–1676, written up in " \
                                    "Cairo in his last years, the text breaking off after 1683")
      PECEVI = composed(1641, 1650, "Peçevî İbrahim (1574–c. 1650) wrote his history in retirement after 1641")

      COMPOSITION = {
        "Behcetu_l-Fetava" => composed(1718, 1743, "the fatwas of Yenişehirli Abdullah Efendi, şeyhülislam " \
                                                   "1718–1730 (d. 1743)"),
        "Feta_va_-y_Ali_Efendi" => composed(1674, 1692, "the fatwas of Çatalcalı Ali Efendi, şeyhülislam " \
                                                        "1674–1686 and 1692 (d. 1692)"),
        "Kanunnamei_Ali_Osman" => composed(1477, 1481, "the kanunname of Mehmed II, compiled in his last years — " \
                                                       "the edition's own preface names Sultan Mehmed Hân-ı Sânî " \
                                                       "(upstream's author field names Mehmed I)"),
        "divan__nedim" => composed(1700, 1730, "Nedîm (1681?–1730), the Tulip-era poet: the dîvân of his career"),
        "evliyaelebisey01evliuoft" => EVLIYA, "evliyaelebisey02evliuoft" => EVLIYA,
        "evliyaelebisey03evliuoft" => EVLIYA, "evliyaelebisey04evliuoft" => EVLIYA,
        "evliyaelebisey05evliuoft" => EVLIYA, "evliyaelebisey06evliuoft" => EVLIYA,
        "evliyaelebisey07evliuoft" => EVLIYA, "evliyaelebisey08evliuoft" => EVLIYA,
        "katip_celebi_tuhfe" => composed(1656, 1657, "Kâtib Çelebi (1609–1657) completed the Tuhfetü'l-kibâr " \
                                                     "in 1067 AH (1656–57)"),
        "klliytidvniful00fuzuuoft" => composed(1510, 1556, "Fuzûlî (c. 1480–1556): the Turkish dîvân of his " \
                                                           "Baghdad career"),
        "solakzade_tarihi" => composed(1650, 1658, "Solakzâde Mehmed Hemdemî (d. 1658) closed his history " \
                                                   "c. 1657"),
        "sururi_mecmuas" => composed(1770, 1814, "Osman Sürûrî (1752–1814), master of the chronogram: the " \
                                                 "tarih verses of his career"),
        "taceltevarih01sadeuoft" => composed(1574, 1599, "Hoca Sadeddin (1536–1599) wrote the Tâcü't-tevârîh " \
                                                         "for Murad III (r. 1574–1595)"),
        "tarih_selaniki" => composed(1563, 1600, "Selânikî Mustafa (d. c. 1600) wrote his history year by year, " \
                                                 "971–1008 AH (1563–1600)"),
        "tarihipeevi01peuoft" => PECEVI, "tarihipeevi02peuoft" => PECEVI,
        "tevarihiliosma00lutfuoft" => composed(1541, 1564, "Lütfi Paşa (c. 1488–1564) wrote the Tevârîh-i " \
                                                           "Âl-i Osman after his dismissal as grand vizier in 1541")
      }.freeze

      # Arabic-Indic and Extended (Persian) digits → ASCII, for reading
      # the printed page numbers' direction.
      DIGITS = (("٠".."٩").zip("0".."9") + ("۰".."۹").zip("0".."9")).to_h.freeze

      def self.manifest
        Nabu::SourceManifest.new(
          id: SLUG,
          name: "OttomanOCR-search — machine OCR of printed Ottoman Turkish books (1729–1923 printings)",
          license: LICENSE, license_class: "nc", upstream_url: REPO_URL,
          parser_family: "ottoman-ocr-js", credit: CREDIT
        )
      end

      def self.parallel_parse? = true

      # The print date (class edition) from the manifest meta: the typed
      # year_min/year_max, else a single Hijri year label converted to its
      # CE envelope; nil when upstream gives neither (a Hijri span such as
      # "1294-1298" is never guessed into CE).
      def self.print_date(meta)
        first = meta["year_min"]
        last = meta["year_max"]
        if first.is_a?(Integer) && last.is_a?(Integer)
          label = meta["year_g_label"].to_s.strip
          return { "not_before" => first, "not_after" => last, "class" => "edition",
                   "raw" => "printed #{label.empty? ? first : label}" }
        end
        hijri = meta["year_h_label"].to_s.strip
        return nil unless hijri.match?(/\A\d{3,4}\z/)

        first, last = hijri_envelope(hijri.to_i)
        { "not_before" => first, "not_after" => last, "class" => "edition",
          "raw" => "printed #{hijri} AH (upstream's Hijri year; #{first == last ? first : "#{first}–#{last}"} CE)" }
      end

      # The CE years a whole Hijri year touches: 1 Muḥarram AH 1 = 19 July
      # 622 (proleptic Gregorian, year fraction 0.548), the mean tabular
      # year 354.36707 days = 0.970224 Gregorian years. Exact to within a
      # few days of a Muḥarram that falls at a CE new year.
      def self.hijri_envelope(year)
        start = 622.548 + ((year - 1) * 0.970224)
        [start.floor, (start + 0.970224).floor]
      end

      # +repo_url+/+pinned_sha+ exist for the tests (local upstream repos);
      # no-arg construction stays the registry contract.
      def initialize(repo_url: REPO_URL, pinned_sha: PINNED_SHA)
        super()
        @repo_url = repo_url
        @pinned_sha = pinned_sha
      end

      def fetch(workdir, progress: nil, force: false)
        report = git_fetch!(repo_url: @repo_url, workdir: workdir, progress: progress, force: force,
                            sparse: SPARSE_PATHS)
        return report if report.sha == @pinned_sha

        raise Nabu::FetchError,
              "#{SLUG}: upstream #{@repo_url} is at #{report.sha[0, 12]}, but the source is pinned to " \
              "#{@pinned_sha[0, 12]} — review the new commits (license + text + metadata) and re-pin (owner " \
              "decision; the repository is under active revision, so drift is an event, not a cadence)"
      end

      # One ref per manifest work whose data file is on disk, in manifest
      # order.
      def discover(workdir)
        return enum_for(:discover, workdir) unless block_given?

        works(workdir).each_key do |id|
          path = work_path(workdir, id)
          next unless File.file?(path)

          yield Nabu::DocumentRef.new(source_id: SLUG, id: "urn:nabu:#{SLUG}:#{id}", path: path,
                                      metadata: { "work" => id })
        end
      end

      def discovery_skips(workdir)
        listed = works(workdir).keys
        files = Dir.glob("*.js", base: File.join(workdir, DATA_DIR)).map { |name| name.delete_suffix(".js") }
        files.delete("manifest")
        missing = listed - files
        stray = files - listed
        rejected = REJECTED_FILES.select { |rel, _why| File.file?(File.join(workdir, rel)) }
        notes = rejected.map { |rel, why| "#{rel}: skipped by rule — #{why}" }
        notes << "manifest works with no data file: #{missing.join(', ')}" if missing.any?
        notes << "data files the manifest does not list: #{stray.map { |id| "#{id}.js" }.join(', ')}" if stray.any?
        Nabu::Adapter::DiscoverySkips.new(skipped_by_rule: rejected.size, unrecognized: missing.size + stray.size,
                                          notes: notes)
      end

      def parse(document_ref)
        id = document_ref.metadata.fetch("work")
        workdir = File.dirname(document_ref.path, 2)
        work = works(workdir).fetch(id) { raise Nabu::ParseError, "#{document_ref.id}: not in the manifest" }
        data = read_work(document_ref.path, id)
        pages = data["pages"]
        raise Nabu::ParseError, "#{document_ref.path}: no pages array" unless pages.is_a?(Array)

        passages = page_passages(document_ref.id, pages)
        raise Nabu::ParseError, "#{document_ref.id}: no transcribed page" if passages.empty?

        title = presence(work["title"]) || id
        document = Nabu::Document.new(urn: document_ref.id, language: LANGUAGE, canonical_path: document_ref.path,
                                      title: Nabu::Normalize.nfc(title),
                                      metadata: metadata_for(id, work, pages, passages, workdir))
        passages.each { |passage| document << passage }
        document
      rescue Nabu::ValidationError => e
        raise Nabu::ParseError, "#{SLUG} #{document_ref.id}: #{e.message}"
      end

      private

      def work_path(workdir, id) = File.expand_path(File.join(workdir, DATA_DIR, "#{id}.js"))

      # {work id => manifest work} plus the catalogue's image base,
      # memoized per workdir (one read per adapter instance).
      def catalogue(workdir)
        @catalogue ||= {}
        @catalogue[workdir] ||= read_catalogue(File.join(workdir, MANIFEST_FILE))
      end

      def read_catalogue(path)
        return { works: {}, image_base: "" } unless File.file?(path)

        json = unwrap(SourceRead.utf8_file(path, label: SLUG), MANIFEST_PREFIX, path)
        works = json["works"]
        unless works.is_a?(Array) && works.all? { |work| work.is_a?(Hash) && presence(work["id"]) }
          raise Nabu::ParseError, "#{path}: no works array of id-keyed objects"
        end

        { works: works.to_h { |work| [work["id"], work] }, image_base: json["imageBase"].to_s }
      end

      def works(workdir) = catalogue(workdir)[:works]

      def read_work(path, id)
        unwrap(SourceRead.utf8_file(path, label: SLUG), %(window.__W=window.__W||{};window.__W["#{id}"]=), path)
      end

      # The JSON object behind upstream's `<prefix>{…};` script wrapper.
      def unwrap(text, prefix, path)
        raise Nabu::ParseError, "#{path}: does not open with #{prefix.inspect}" unless text.start_with?(prefix)

        body = text.delete_prefix(prefix).rstrip.delete_suffix(";")
        json = JSON.parse(body)
        raise Nabu::ParseError, "#{path}: not a JSON object" unless json.is_a?(Hash)

        json
      rescue JSON::ParserError => e
        raise Nabu::ParseError, "#{path}: malformed JSON (#{e.message[0, 120]})"
      end

      # One passage per transcribed page (class note): calibration charts
      # and textless pages mint nothing; the page-number entries ride the
      # annotation.
      def page_passages(urn, pages)
        pages.each_with_object([]) do |page, passages|
          next if page["cal"]

          entries = Array(page["L"]).reject { |entry| entry[2].to_s.strip.empty? }
          printed, body = entries.partition { |entry| entry[0] == "page_number" }
          next if body.empty?

          label = page["n"].to_s
          raise Nabu::ParseError, "#{urn}: a page without its label" if label.strip.empty?

          annotations = { "page" => Nabu::Normalize.nfc(label), "image" => page["im"],
                          "printed_page" => presence(printed.map { |entry| entry[2].strip }.join(" ")) }
          passages << Nabu::Passage.new(urn: "#{urn}:#{Nabu::Normalize.nfc(label).tr('–', '-')}", language: LANGUAGE,
                                        text: Nabu::Normalize.nfc(body.map { |entry| entry[2] }.join("\n")),
                                        sequence: passages.size,
                                        annotations: annotations.compact.transform_values { |v| nfc_deep(v) })
        end
      end

      def metadata_for(id, work, pages, passages, workdir)
        meta = work["meta"] || {}
        authors = Array(meta["authors"])
        lines = passages.flat_map { |passage| passage.text.split("\n") }
        {
          "work" => id, "full_title" => presence(meta["full_title"]),
          "authors" => authors.filter_map { |author| presence(author["name"]) },
          "viaf" => authors.filter_map { |author| presence(author["viaf"]) },
          "translators" => Array(meta["translators"]).filter_map { |name| presence(name) },
          "publisher" => presence(meta["publisher"]), "upstream_genre" => presence(meta["genre"]),
          "subjects" => Array(meta["subjects"]).filter_map { |subject| presence(subject) },
          "print_year" => presence(meta["year_g_label"]), "print_year_ah" => presence(meta["year_h_label"]),
          "date" => COMPOSITION[id] || self.class.print_date(meta),
          "source_url" => presence(meta["source"]), "upstream_notes" => presence(meta["notes"]),
          "image_base" => presence(catalogue(workdir)[:image_base])&.then { |base| "#{base}#{id}/" },
          "pages" => pages.size, "text_pages" => passages.size,
          "calibration_pages" => pages.count { |page| page["cal"] },
          "page_order" => page_order(pages),
          "text_nature" => "uncorrected-ocr", "ocr_note" => OCR_NOTE,
          "ocr_latin_line_share" => (lines.count { |line| line.match?(/\p{Latin}/) }.to_f / lines.size).round(4)
        }.reject { |_key, value| value.nil? || (value.respond_to?(:empty?) && value.empty?) }
         .transform_values { |value| nfc_deep(value) }
      end

      # "descending" when the printed page numbers run downward through
      # upstream's image order (a back-to-front scan: falls outnumber rises
      # more than two to one); nil otherwise.
      def page_order(pages)
        numbers = pages.filter_map do |page|
          printed = Array(page["L"]).find { |entry| entry[0] == "page_number" && !entry[2].to_s.strip.empty? }
          printed && printed[2].gsub(/[٠-٩۰-۹]/, DIGITS)[/\d+/]&.to_i
        end
        steps = numbers.each_cons(2).map { |a, b| b <=> a }
        falls = steps.count(-1)
        falls > 2 * steps.count(1) ? "descending" : nil
      end

      def presence(value)
        text = value.to_s.strip
        text.empty? ? nil : text
      end

      def nfc_deep(value)
        case value
        when String then Nabu::Normalize.nfc(value)
        when Array then value.map { |item| nfc_deep(item) }
        else value
        end
      end
    end
  end
end

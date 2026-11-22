# frozen_string_literal: true

require "json"

require_relative "../fetch/dicta_library_fetch"
require_relative "../zip_reader"
require_relative "source_read"

module Nabu
  module Adapters
    # dicta-library: "the Dicta library" (הספרייה של דיקטה) — rabbinic
    # printed books read by Dicta's AI OCR (which also renders Rashi script
    # in square letters), published through github.com/Dicta-Israel-Center-
    # for-Text-Analysis/Dicta-Library-Download: a books.json manifest naming,
    # per book, three zips on files.dicta.org.il. The library's first
    # responsa shelf, beside its Talmud, Tanakh, Rambam and Shulchan Arukh
    # commentaries, halakha, derashot, Chassidut and Kabbalah.
    #
    # == Upstream's delivery grains (manifest census 2026-11-16)
    #
    # books.json: 1,205 entries (fileName, author/authorEnglish, category/
    # subcategory in Hebrew and English, displayName(English), printLocation
    # (English), printYear — 1,204 integers 1726–1982 plus one "1925-1931"
    # string — source, ocrFeDir, and three URLs). Per book:
    #   textFileURL        <fileName>__text_files.zip — one plain-text member
    #                      per scanned page, <fileName>-NNN.txt (536.4 MB over
    #                      1,204 HEAD-censused zips)
    #   nikudMetegFileURL  <fileName>__nikud_meteg_files.zip — the same pages
    #                      run through Dicta's automatic vocalizer, one line
    #                      per page (750.5 MB)
    #   OCRDataURL         <fileName>__ocr_data_html_files.zip — per-page HTML
    #                      spans carrying OCR layout/confidence classes
    #                      (685.0 MB)
    #
    # The document is the BOOK; the passage is one PAGE of the plain-text
    # zip, cited by its scan number (urn …:<slug>:<NNN as integer>; an empty
    # page mints no passage and is counted in metadata empty_pages). The
    # plain text is the OCR reading of the print, which is unpointed; the
    # vocalized zip is Dicta's machine vocalization layered on it — an
    # enrichment-class reading, not the book, so it is NOT fetched … EXCEPT
    # for the three books whose text zip upstream ships EMPTY (22-byte
    # archives: amudeiohr, chidusheiharadad, maharamlublin). There the
    # vocalized zip is the book's one text witness and becomes the document
    # (metadata text_layer says so) — unless it is empty too
    # (chidusheiharadad), which is skipped by rule. The OCR HTML zip is
    # markup over the same reading — never fetched.
    #
    # Rejected grains, skipped BY RULE and counted (discovery_skips; each
    # pinned in the fixture): a book with no text in either zip; a vocalized
    # zip beside a held plain-text zip; any OCR HTML zip. Reconciliation
    # (expected at first sync): 1,205 manifest entries = 1,204 documents
    # (1,202 plain + 2 vocalized fallbacks) + 1 skipped by rule.
    #
    # == Upstream's own warning (declared)
    #
    # README, verbatim (Hebrew): "כיוון שמדובר בתהליכים אוטומטיים ייתכנו
    # שיבושים בטקסט וכן בניקוד" — since these are automatic processes, the
    # text and the vocalization may contain errors. text_nature
    # "machine-ocr"; nothing is corrected (canonical means canonical). The
    # plain text also carries a line-start quirk: a line's closing
    # punctuation often opens the NEXT line (". שלמא …", ": אחדש"ה …") —
    # upstream's bytes, kept.
    #
    # == LICENSE
    #
    # The README's last line is the bare link
    # "https://creativecommons.org/licenses/by-sa/4.0/" (read 2026-11-13 and
    # 2026-11-16) → CC BY-SA 4.0, attribution; credit Dicta. The texts are
    # 18th–20th-century prints.
    #
    # == Axes (aggressive mining — every manifest field lands)
    #
    # - date — printYear as {not_before, not_after, raw, class edition}: the
    #   PRINT year (a reprint can postdate its author by centuries — the
    #   1881 Warsaw Maharam Lublin), never a composition claim (the blbooks
    #   precedent).
    # - place — printLocationEnglish (the imprint town); the Hebrew rides
    #   place_he.
    # - genre — "categoryEnglish -- subcategoryEnglish" (kind_map.yml folds
    #   it by prefix; the Hebrew pair rides genre_he — upstream's two
    #   languages disagree on a few rows, both kept verbatim).
    # - era facet — the subcategory's own Rishonim / Acharonim / Geonim
    #   label (English, else the Hebrew ראשונים/אחרונים/גאונים): upstream's
    #   classification of the AUTHOR's era, which the lect rule reads.
    # - author — authorEnglish (author_he beside it) and the author facet.
    #
    # == Language
    #
    # Bare `heb` on every book: post-classical rabbinic Hebrew with Aramaic
    # quotation and idiom throughout (the responsa and novellae style) — the
    # mix is declared, not split. The Rishonim era facet stages onto heb:med
    # (config/lect_facet_rules.yml); the Acharonim mass stays bare (the
    # registry carries no early-modern rabbinic stage). `heb` is not
    # NFC-exempt: the boundary composes (the vocalized fallbacks are not NFC
    # upstream).
    #
    # == fetch
    #
    # GitFetch of the manifest repo (books.json + README; attic + breaker),
    # then Nabu::DictaLibraryFetch crawls the book zips into books/ (the
    # declared materialization: sidecar + zip per book, resumable, additive).
    class DictaLibrary < Nabu::Adapter
      REPO_URL = "https://github.com/Dicta-Israel-Center-for-Text-Analysis/Dicta-Library-Download"
      URN_PREFIX = "urn:nabu:dicta-library:"
      LANGUAGE = "heb"
      BOOKS_DIR = "books"
      MANIFEST_FILE = "books.json"

      TEXT_SUFFIX = DictaLibraryFetch::TEXT_SUFFIX
      NIKUD_SUFFIX = DictaLibraryFetch::NIKUD_SUFFIX
      OCR_SUFFIX = "__ocr_data_html_files.zip"

      # A page member: <fileName>-NNN.txt (plain) / -NNN__nikud_meteg.txt.
      PAGE_MEMBER = /-(\d+)(?:__nikud_meteg)?\.txt\z/n

      # The subcategory's era label (English, then the Hebrew).
      ERAS = [["rishonim", /Rishonim/, /ראשונים/], ["acharonim", /Acharonim/, /אחרונים/],
              ["geonim", /Geonim/, /גאונים/]].freeze

      OCR_NOTE = "Dicta's automatic OCR of the printed book (Rashi script rendered in square " \
                 "letters); upstream warns that automatic processing may leave errors in the text " \
                 "and the vocalization."

      FALLBACK_LAYER = "vocalized (the plain-text zip is empty upstream)"

      MANIFEST = Nabu::SourceManifest.new(
        id: "dicta-library",
        name: "Dicta — the Dicta library: AI-OCR'd rabbinic printed books (responsa, commentaries, " \
              "halakha, derashot, Chassidut)",
        license: "CC BY-SA 4.0 (Dicta-Library-Download README, closing line verbatim: " \
                 "\"https://creativecommons.org/licenses/by-sa/4.0/\"); 18th–20th-century prints read " \
                 "by Dicta's automatic OCR — machine text, not an edition",
        license_class: "attribution",
        upstream_url: REPO_URL,
        parser_family: "dicta-library-zip",
        credit: "Dicta: The Israel Center for Text Analysis — the Dicta library (library.dicta.org.il)"
      )

      Scan = Data.define(:refs, :skipped, :unrecognized)

      def self.manifest = MANIFEST

      # Each parse opens its own zip — no state crosses refs.
      def self.parallel_parse? = true

      def self.materialized_paths = [BOOKS_DIR]

      # The urn slug of an upstream fileName: lowercase, every run of
      # non-alphanumerics one hyphen ("(h)b(z)lt_hsrvn-(h)lk_b=1573" →
      # "h-b-z-lt-hsrvn-h-lk-b-1573"). Lossy by design, so discovery refuses
      # a collision loudly.
      def self.slug(file_name)
        file_name.downcase.gsub(/[^a-z0-9]+/, "-").gsub(/\A-|-\z/, "")
      end

      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        scan(workdir).refs.each(&block)
      end

      def discovery_skips(workdir)
        result = scan(workdir)
        Nabu::Adapter::DiscoverySkips.new(skipped_by_rule: result.skipped.size,
                                          unrecognized: result.unrecognized.size,
                                          notes: result.skipped + result.unrecognized)
      end

      def parse(document_ref)
        entry = read_sidecar(document_ref.metadata.fetch("sidecar"))
        pages = read_pages(document_ref.path)
        raise DocumentSkipped.new("#{document_ref.path}: no page member", reason: "empty book zip") if pages.empty?

        document = Nabu::Document.new(
          urn: document_ref.id, language: LANGUAGE, title: title(entry),
          canonical_path: document_ref.path,
          metadata: book_metadata(entry, document_ref.metadata.fetch("layer"), pages)
        )
        pages.each do |page, text|
          next if text.nil?

          document << Nabu::Passage.new(urn: "#{document.urn}:#{page}", language: LANGUAGE, text: text,
                                        sequence: document.size, annotations: { "page" => page })
        end
        raise ParseError, "#{document_ref.path}: every page is empty" if document.empty?

        document
      end

      def fetch(workdir, progress: nil, force: false)
        report = git_fetch!(repo_url: repo_url, workdir: workdir, progress: progress, force: force)
        result = DictaLibraryFetch.sync!(manifest_path: File.join(workdir, MANIFEST_FILE),
                                         dir: File.join(workdir, BOOKS_DIR), delay: crawl_delay,
                                         progress: progress)
        Nabu::FetchReport.new(sha: report.sha, fetched_at: Time.now, notes: fetch_notes(report, result))
      rescue DictaLibraryFetch::Error => e
        raise FetchError, "dicta-library fetch failed: #{e.message}"
      end

      private

      # Seams for tests (the house local-git pattern; a zero crawl pause).
      def repo_url = REPO_URL

      def crawl_delay = DictaLibraryFetch::DELAY

      def fetch_notes(report, result)
        notes = ["#{result.books} books in the manifest; #{result.fetched} downloaded, #{result.cached} " \
                 "already held"]
        notes << "#{result.fallbacks.size} empty text zip(s) → vocalized fallback" unless result.fallbacks.empty?
        notes << "#{result.missing.size} missing upstream (404): #{result.missing.first(3).join(', ')}" unless
          result.missing.empty?
        notes << report.notes if report.notes
        notes.join("; ")
      end

      # One walk of books/: every sidecar is a listed book; every zip is
      # either a book's witness or a counted rejected grain.
      def scan(workdir)
        refs = {}
        skipped = []
        unrecognized = []
        dir = File.join(workdir, BOOKS_DIR)
        return Scan.new(refs: [], skipped: skipped, unrecognized: unrecognized) unless Dir.exist?(dir)

        files = Dir.children(dir).reject { |name| name.start_with?(".") }.to_set
        witnesses = Set.new
        files.select { |name| name.end_with?(".json") }.sort.each do |sidecar|
          name = sidecar.delete_suffix(".json")
          book_ref(dir, name, files, refs, skipped, unrecognized, witnesses)
        end
        files.reject { |name| name.end_with?(".json") || witnesses.include?(name) }.sort.each do |name|
          note_stray(name, files, skipped, unrecognized)
        end
        Scan.new(refs: refs.values.sort_by(&:id), skipped: skipped, unrecognized: unrecognized)
      end

      # -- one walk's accumulators
      def book_ref(dir, name, files, refs, skipped, unrecognized, witnesses)
        text = "#{name}#{TEXT_SUFFIX}"
        nikud = "#{name}#{NIKUD_SUFFIX}"
        unless files.include?(text)
          unrecognized << "#{BOOKS_DIR}/#{name}: listed in the manifest but its text zip was never downloaded"
          return
        end
        witnesses << text
        layer, witness = witness(dir, text, nikud, files)
        witnesses << nikud if files.include?(nikud) && witness != text
        if witness.nil?
          skipped << "#{BOOKS_DIR}/#{name}: both the text and the vocalized zip are empty upstream"
          return
        end

        id = "#{URN_PREFIX}#{self.class.slug(name)}"
        if refs.key?(id)
          unrecognized << "#{BOOKS_DIR}/#{name}: its urn slug collides with #{refs[id].metadata['file_name']}"
          return
        end
        refs[id] = Nabu::DocumentRef.new(
          source_id: manifest.id, id: id, path: File.expand_path(File.join(dir, witness)),
          metadata: { "sidecar" => File.expand_path(File.join(dir, "#{name}.json")), "layer" => layer,
                      "file_name" => name }
        )
      end

      # [layer, member file] — the text zip unless it is empty, then the
      # vocalized zip unless that is empty or absent too.
      def witness(dir, text, nikud, files)
        return ["plain", text] unless empty_zip?(File.join(dir, text))
        return [FALLBACK_LAYER, nikud] if files.include?(nikud) && !empty_zip?(File.join(dir, nikud))

        [nil, nil]
      end

      def note_stray(name, files, skipped, unrecognized)
        stem = name.sub(/(?:#{Regexp.escape(TEXT_SUFFIX)}|#{Regexp.escape(NIKUD_SUFFIX)}|#{OCR_SUFFIX})\z/o, "")
        if name.end_with?(OCR_SUFFIX)
          skipped << "#{BOOKS_DIR}/#{name}: the OCR layout HTML — markup over the held reading, not text"
        elsif name.end_with?(NIKUD_SUFFIX) && files.include?("#{stem}#{TEXT_SUFFIX}")
          skipped << "#{BOOKS_DIR}/#{name}: the machine-vocalized layer of a book whose plain text is held"
        elsif !name.end_with?(".tmp")
          unrecognized << "#{BOOKS_DIR}/#{name}: no manifest sidecar names this file"
        end
      end

      def empty_zip?(path)
        DictaLibraryFetch.empty_zip?(path)
      end

      def read_sidecar(path)
        parsed = JSON.parse(SourceRead.utf8_file(path, label: "dicta-library sidecar"))
        raise ParseError, "#{path}: the sidecar is not a manifest entry" unless parsed.is_a?(Hash)

        parsed
      rescue JSON::ParserError => e
        raise ParseError, "#{path}: unreadable sidecar: #{e.message}"
      end

      # [[page number, NFC text or nil when empty]] in page order.
      def read_pages(path)
        zip = SourceRead.zip_file(path)
        pages = zip.entries.map do |entry|
          number = entry.name.b[PAGE_MEMBER, 1]
          raise ParseError, "#{path}: unexpected member #{entry.name.inspect}" unless number

          text = SourceRead.utf8_member(zip, entry, label: path).strip
          [Integer(number, 10), text.empty? ? nil : SourceRead.nfc(text, language: LANGUAGE)]
        end
        pages.sort_by(&:first)
      rescue Nabu::ZipReader::Error => e
        raise ParseError, "#{path}: unreadable zip: #{e.message}"
      end

      def title(entry)
        text(entry["displayNameEnglish"]) || text(entry["displayName"]) || entry.fetch("fileName")
      end

      def book_metadata(entry, layer, pages)
        author = text(entry["authorEnglish"])
        {
          "he_title" => text(entry["displayName"]),
          "author" => author, "author_he" => text(entry["author"]),
          "date" => date_envelope(entry["printYear"]),
          "place" => text(entry["printLocationEnglish"]), "place_he" => text(entry["printLocation"]),
          "genre" => joined(entry["categoryEnglish"], entry["subcategoryEnglish"]),
          "genre_he" => joined(entry["category"], entry["subcategory"]),
          "text_nature" => "machine-ocr", "ocr_note" => OCR_NOTE, "text_layer" => layer,
          "page_count" => pages.size, "empty_pages" => pages.count { |_page, body| body.nil? },
          "dicta_file_name" => entry["fileName"], "dicta_collection" => text(entry["source"]),
          "facets" => facets(entry, author)
        }.compact
      end

      def facets(entry, author)
        facets = {}
        if (era = era(entry))
          facets["era"] = { "value" => era, "raw" => text(entry["subcategoryEnglish"]) || text(entry["subcategory"]) }
        end
        facets["author"] = { "values" => [author] } if author
        facets.empty? ? nil : facets
      end

      def era(entry)
        english = entry["subcategoryEnglish"].to_s
        hebrew = entry["subcategory"].to_s
        ERAS.find { |_slug, en, he| english.match?(en) || (english.empty? && hebrew.match?(he)) }&.first
      end

      # printYear 1908 or "1925-1931" → an edition envelope.
      def date_envelope(value)
        years = value.to_s.scan(/\b(1\d{3})\b/).flatten.map { |year| Integer(year, 10) }
        return nil if years.empty?

        { "not_before" => years.min, "not_after" => years.max, "raw" => value.to_s, "class" => "edition" }
      end

      def joined(head, sub)
        [text(head), text(sub)].compact.join(" -- ").then { |value| value.empty? ? nil : value }
      end

      def text(value)
        return nil unless value.is_a?(String)

        stripped = value.strip
        stripped.empty? ? nil : Normalize.nfc(stripped)
      end
    end
  end
end

# frozen_string_literal: true

require_relative "usfm_parser"

module Nabu
  module Adapters
    # ebible-pacific — eBible.org's public-domain Pacific Bibles (P154,
    # the Pacific openers): the library's first Oceanic and Micronesian
    # running text, and its first Hawaiian.
    #
    # - haw1868 — Ka Baibala Hemolele, "The Holy Bible in the Hawaiian
    #   language of the United States, 1868 revision": the ABCFM
    #   missionaries' 1839 Bible as revised in 1868, whole (66 books /
    #   31,102 verses), in the period's own spelling — no ʻokina or
    #   kahakō, the 20th-century Pukui–Elbert marks are absent ("I KINOHI
    #   ka Logou"); the few ASCII apostrophes (ka'u, ko'u) are the text's.
    # - cha — "Y CUATRO EBANGELIO SIJA YAN Y CHECHO Y APOSTOLES YAN Y SALMO
    #   SIJA", the American Bible Society's Chamorro Gospels, Acts and
    #   Psalms (6 books / 7,245 verses), eBible's sword module cha1908.
    # - pon — "Kadede Kap Pjam Akan", the Pohnpeian New Testament and
    #   Psalms, "old translation, using old alphabet" (28 books / 10,415
    #   verses; the j-for-s spelling "Iejuj", "majan"), eBible's sword
    #   module pon1922.
    #
    # == Upstream's delivery grains (census 2026-11-02)
    #
    # One zip per translation, https://ebible.org/Scriptures/<id>_usfm.zip,
    # unpacking FLAT: NN-<BOOK><id>.usfm — one book per file → THE
    # DOCUMENT GRAIN (urn:nabu:ebible-pacific:<id>-<book>, the eng-web
    # book-urn shape with the translation prefixed); passages
    # <chapter>.<verse>. Rejected inside the zip, counted in
    # discovery_skips: copr.htm (the rights page), the *.css stylesheet,
    # keys.asc and signature.txt.asc (eBible's signing material). eBible
    # also serves each text as USFX/OSIS/HTML/PDF/ePub/Sword — the same
    # text in other formats, not fetched. Reconciliation: 66 + 6 + 28 =
    # 100 books / 48,762 verses = eBible's own catalog counts
    # (translations.csv OT+NT verses: 23,145+7,957 · 2,461+4,784 ·
    # 2,460+7,955), plus 4 rule-skipped files per zip and the fetcher's
    # own .zip-fetch.json state pin per tree — no residue.
    #
    # == Refused (the survey's other Pacific eBible rows)
    #
    # kos ("BIBLE MUTAL", eBible: "public domain because the copyright has
    # expired", "Translation by: Elizabeth Baldwin") — the zip's own front
    # matter states a NEW translation (work begun 15 September 1992 from
    # the NRSV and the Good News Bible, published by the Bible Society of
    # Micronesia) with footnotes, cross-references, book introductions and
    # a glossary: not the 1928 Baldwin print (the srp1868 modernization
    # precedent). pon-pdn (respelled), pon2006 (©), ton (the modern Revised
    # West Version), mri (©) — refused per the survey.
    #
    # == Text, language, axes
    #
    # The usfm family reads verses only: \s headings, \mt titles and
    # \q/\p/\b layout are not verse text; the pon text's \it…\it* italics
    # (supplied words, 9,064 spans) and the cha text's \it/\bd spans drop
    # their markers and keep their words. NFC at the boundary (no
    # exemption). Languages: ISO 639-3 haw / cha / pon — the 2026-11-02
    # registry mint's haw and pon anchors by identity, cha → ch through
    # the codemap. Kind: scripture (kind_map source_kind). Date: each
    # translation's edition year as eBible records it — 1868 from the
    # title ("1868 revision"), 1908 and 1922 from its sword-module names
    # (cha1908eb, pon1922eb) — an edition-class date (MetadataDates
    # :structured), attributed, declared coarse: the zips name no
    # imprint, so no place claim.
    #
    # == License
    #
    # Each translation's copyright.htm (verbatim 2026-11-02): haw1868 —
    # "Public Domain", "Translation by: na na misionari i pai"; cha —
    # "Public Domain", "Translation by: American Bible Society"; pon —
    # "Public Domain". → open.
    #
    # == fetch
    #
    # Three ZipFetch trees (haw1868/, cha/, pon/ — the damaskini
    # two-phase choreography: all staged, one mass-deletion breaker over
    # the whole set, then all swap in). eBible regenerates its zips
    # (Last-Modified 30 Oct 2026 at census); the conditional GET keeps an
    # unchanged one untouched. sync_policy manual.
    class EbiblePacific < Nabu::Adapter
      URN_PREFIX = "urn:nabu:ebible-pacific:"
      ZIP_URL = "https://ebible.org/Scriptures/%s_usfm.zip"

      NT_BOOKS = %w[MAT MRK LUK JHN ACT ROM 1CO 2CO GAL EPH PHP COL 1TH 2TH 1TI 2TI TIT PHM HEB
                    JAS 1PE 2PE 1JN 2JN 3JN JUD REV].freeze

      # translation id => what the asset and eBible's catalog state.
      TRANSLATIONS = {
        "haw1868" => { "language" => "haw", "translator" => "na na misionari i pai",
                       "edition" => "Baibala Hemolele, 1868 revision",
                       "date" => { "not_before" => 1868, "not_after" => 1868, "class" => "edition",
                                   "raw" => "1868 — eBible's title: \"The Holy Bible in the Hawaiian " \
                                            "language of the United States, 1868 revision\"" } },
        "cha" => { "language" => "cha", "translator" => "American Bible Society",
                   "edition" => "Y Cuatro Ebangelio Sija yan y Checho y Apostoles yan y Salmo Sija",
                   "date" => { "not_before" => 1908, "not_after" => 1908, "class" => "edition",
                               "raw" => "1908 — eBible's sword module cha1908eb" } },
        "pon" => { "language" => "pon", "orthography" => "old alphabet",
                   "edition" => "Kadede Kap Pjam Akan (old translation, using old alphabet)",
                   "date" => { "not_before" => 1922, "not_after" => 1922, "class" => "edition",
                               "raw" => "1922 — eBible's sword module pon1922eb" } }
      }.freeze

      BOOK_FILE = /\A\d{2,3}-([1-4A-Z]{3})(#{TRANSLATIONS.keys.join('|')})\.usfm\z/
      NON_BOOK_FILES = /\A(?:copr\.htm|[\w-]+\.css|keys\.asc|signature\.txt\.asc)\z/

      MANIFEST = Nabu::SourceManifest.new(
        id: "ebible-pacific",
        name: "eBible.org Pacific Bibles — Hawaiian 1868, Chamorro (ABS 1908), Pohnpeian (old alphabet)",
        license: "Public Domain (each translation's eBible.org copyright.htm, verbatim 2026-11-02: " \
                 "haw1868 \"Public Domain\" — \"Translation by: na na misionari i pai\"; cha \"Public " \
                 "Domain\" — \"Translation by: American Bible Society\"; pon \"Public Domain\")",
        license_class: "open",
        upstream_url: "https://ebible.org/",
        parser_family: "usfm",
        credit: "eBible.org — the public-domain Hawaiian, Chamorro and Pohnpeian Bibles"
      )

      def self.manifest = MANIFEST

      def self.zip_url(id) = format(ZIP_URL, id)

      # The probe HEADs each zip: reachability + Last-Modified drift vs
      # each tree's .zip-fetch.json pin.
      def self.remote_probe_strategy = :http_zip

      def self.http_probe_targets
        TRANSLATIONS.keys.map do |id|
          Nabu::Adapter::HttpProbeTarget.new(label: "#{id}_usfm.zip", zip_url: zip_url(id), metadata_url: nil,
                                             state_subdir: id, state_file: Nabu::ZipFetch::STATE_FILE)
        end
      end

      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        TRANSLATIONS.each_key do |id|
          book_files(workdir, id).each do |path|
            book = File.basename(path)[BOOK_FILE, 1]
            yield Nabu::DocumentRef.new(source_id: MANIFEST.id, id: "#{URN_PREFIX}#{id}-#{book.downcase}",
                                        path: File.expand_path(path),
                                        metadata: { "translation" => id, "book" => book })
          end
        end
      end

      def discovery_skips(workdir)
        notes = []
        unrecognized = []
        TRANSLATIONS.each_key do |id|
          entries(workdir, id).each do |name|
            next if BOOK_FILE.match?(name)

            if name == Nabu::ZipFetch::STATE_FILE
              notes << "#{id}/#{name}: the fetcher's own state pin — not upstream content"
            elsif NON_BOOK_FILES.match?(name)
              notes << "#{id}/#{name}: the zip's rights page / stylesheet / signing material — not scripture"
            else
              unrecognized << "#{id}/#{name}: unrecognized file in the translation zip"
            end
          end
        end
        Nabu::Adapter::DiscoverySkips.new(skipped_by_rule: notes.size, unrecognized: unrecognized.size,
                                          notes: notes + unrecognized)
      end

      def parse(document_ref)
        id = document_ref.metadata.fetch("translation")
        info = TRANSLATIONS.fetch(id)
        book = UsfmParser.new.parse(document_ref.path)
        expected = document_ref.metadata.fetch("book")
        unless book.id == expected
          raise Nabu::ParseError, "#{document_ref.path}: \\id #{book.id} does not match the file's #{expected}"
        end

        language = info.fetch("language")
        document = Nabu::Document.new(urn: document_ref.id, language: language, canonical_path: document_ref.path,
                                      title: book.heading || book.id, metadata: metadata_for(id, info, book))
        book.verses.each_with_index do |verse, index|
          document << Nabu::Passage.new(urn: "#{document_ref.id}:#{verse.chapter}.#{verse.verse}",
                                        language: language, text: verse.text, sequence: index + 1)
        end
        raise Nabu::ParseError, "#{document_ref.id}: no verses" if document.empty?

        document
      rescue Nabu::ValidationError => e
        raise Nabu::ParseError, "#{document_ref.path}: #{e.message}"
      end

      def fetch(workdir, progress: nil, force: false)
        fetches = zip_fetches(workdir, progress)
        begin
          fetches.each_value(&:prepare!)
          guard_mass_deletion!(workdir, fetches.values.flat_map(&:doomed_paths), force: force)
          fetches.each_value(&:complete!)
        ensure
          fetches.each_value(&:cleanup!)
        end
        report(fetches)
      rescue ZipFetch::Error, Nabu::Shell::Error => e
        raise Nabu::FetchError, "ebible-pacific fetch failed into #{workdir}: #{e.message}"
      end

      private

      def entries(workdir, id)
        dir = File.join(workdir, id)
        return [] unless File.directory?(dir)

        Dir.children(dir).select { |name| File.file?(File.join(dir, name)) }.sort
      end

      # Book files in eBible's own numeric order (the NN- prefix).
      def book_files(workdir, id)
        entries(workdir, id).grep(BOOK_FILE).sort_by(&:to_i).map { |name| File.join(workdir, id, name) }
      end

      def metadata_for(id, info, book)
        { "translation" => id, "book" => book.id, "testament" => NT_BOOKS.include?(book.id) ? "nt" : "ot",
          "edition" => info["edition"], "translator" => info["translator"], "orthography" => info["orthography"],
          "date" => info["date"], "script" => "Latn", "toc" => book.toc }
          .reject { |_k, v| v.nil? || (v.respond_to?(:empty?) && v.empty?) }
      end

      def zip_fetches(workdir, progress)
        TRANSLATIONS.keys.to_h do |id|
          [id, Nabu::ZipFetch.new(url: self.class.zip_url(id), dir: File.join(workdir, id),
                                  attic_dir: File.join(workdir, ATTIC_DIRNAME, id), progress: progress)]
        end
      end

      def report(fetches)
        shas = fetches.transform_values(&:sha)
        notes = shas.map { |id, sha| "#{id}=#{sha[0, 12]}" }.join(" ")
        atticked = fetches.values.sum { |fetch| fetch.atticked.size }
        notes = "#{notes} · atticked #{atticked} upstream-deleted file(s)" if atticked.positive?
        Nabu::FetchReport.new(sha: shas.fetch("haw1868"), fetched_at: Time.now, notes: notes,
                              repos: shas.to_h { |id, sha| [self.class.zip_url(id), sha] })
      end
    end
  end
end

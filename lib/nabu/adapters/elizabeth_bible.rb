# frozen_string_literal: true

require "json"

module Nabu
  module Adapters
    # elizabeth-bible — the Elizabeth Bible (Елизаветинская Библия) in
    # Church Slavonic, the Synodal standard's own text, from getBible's
    # public-domain edition `csielizabeth` (P152).
    #
    # == The asset, and what it is
    #
    # https://api.getbible.net/v2/csielizabeth.json — ONE whole-translation
    # JSON file (23.7 MB, pretty-printed, ASCII-escaped): a distribution
    # envelope (translation "1757 Church Slavonic Elizabeth Bible", lang
    # "cu", distribution_license "Public Domain", distribution_source
    # "rusbible.ru", distribution_sourcetype "OSIS", distribution_
    # versification "Synodal", version 1.5.2 — the CrossWire SWORD module
    # cslelizabeth's history) around books[] → chapters[] → verses[]
    # {chapter, verse, name, text}. Census 2026-11-02: 76 books / 36,000
    # verses, every verse non-empty and NFC, numbering gapless.
    #
    # It is a RENDERING, declared, never a claim on the 1757 print's
    # orthography: distribution_about says "This electronic edition comes
    # from rusbible.ru and features modernized spelling", and the file
    # bears it out — civil-script Cyrillic with no ѣ, і, ѵ, ѳ, ѡ, ѧ, no
    # titla and no accents anywhere ("В начале сотвори Бог небо и
    # землю."). The words, forms and syntax are the Elizabethan text's; the
    # spelling is modern. Metadata "rendering" names that on every
    # document (the bg-wikisource Paisiy shape), "base_edition" carries
    # distribution_about verbatim, "script" Cyrl, "orthography" modernized.
    #
    # Delivery grains (test/fixtures/elizabeth-bible/README.md): getBible
    # serves the translation, the book (/v2/csielizabeth/<nr>.json), the
    # chapter (/<nr>/<chapter>.json) and the verse inside each. The
    # translation file is the fetch unit; the BOOK is the document; the
    # VERSE is the passage. The per-book and per-chapter endpoint shapes are
    # rejected (the same text without the distribution fields): any such
    # file in the workdir is counted skipped by rule, never parsed.
    #
    # Reconciliation: getBible's own book list for csielizabeth is the
    # file's books[] — 76 entries, all minted (66 protocanonical + 10
    # deuterocanonical: Prayer of Manasses, 1 Esdras, Tobit, Judith, Wisdom,
    # Sirach, Epistle of Jeremiah, Baruch, 1–2 Maccabees). The Synodal
    # canon's 3 Esdras and 3 Maccabees are absent UPSTREAM (not served),
    # not skipped here.
    #
    # == Identity (FROZEN minting)
    #
    # Document = one book: urn:nabu:elizabeth-bible:<OSIS id downcased>
    # (the source is OSIS; the oshb book-urn shape — gen, prman, 1esd,
    # jonah, 2john), keyed by getBible's stable book number `nr` through
    # BOOKS. Passages <doc-urn>:<chapter>.<verse> — the house verse shape
    # the alignment hub's cts-verse extractor reads. Titles are getBible's
    # English book names (the file carries no Slavonic titles); declared,
    # not translated. A book number outside BOOKS is never minted — it is
    # censused unrecognized by discovery_skips (a new upstream book needs a
    # deliberate code).
    #
    # Text: whitespace collapsed (1,339 verses carry trailing or doubled
    # spaces — the usfx family's rule), NFC; nothing else touched. 1 Kings
    # 2.35 keeps the Greek-tradition insertions with their inline numerals
    # (1 … 10) and Judith 15.9 its "|" separators, verbatim.
    #
    # == Axes
    #
    # Lect: chu → chu:ncs, a whole-source override in
    # config/lect_overrides.yml (tier certain) — the registry's New Church
    # Slavonic node names this Bible as the text that fixed the standard;
    # the spelling is the rendering's and rides metadata, not the lect.
    # Kind: scripture (kind_map source_kind). Date: the edition year the
    # translation title states (1757) as date_class EDITION
    # (MetadataDates :structured) — the year of the print the electronic
    # text renders, never a composition or artifact date of the respelled
    # text (which upstream does not date; distribution_version_date
    # 2011-08-17 is the SWORD module's). Place: none — the asset names no
    # imprint. Versification: Synodal, per the file; verified Greek-scheme
    # at the MT split points (Jonah 2.1 the fish verse, Joel 3 and Malachi 4
    # chapters, Deuteronomy 13.1, Hosea 2.1, Zechariah 2.1, Greek psalm
    # numbering) — the alignment registry's entries carry the census.
    #
    # == License
    #
    # The file's own distribution_license: "Public Domain" (verbatim); the
    # Elizabeth Bible itself is an 18th-century print → open.
    #
    # == fetch
    #
    # Nabu::FileFetch (the aspr single-file rail): conditional GET on the
    # stored Last-Modified, sha256 pin, attic + mass-deletion guard. The
    # remote probe HEADs the same URL. Upstream is a stable module release
    # → sync_policy manual.
    class ElizabethBible < Nabu::Adapter
      FILENAME = "csielizabeth.json"
      URN_PREFIX = "urn:nabu:elizabeth-bible:"
      LANGUAGE = "chu"
      RENDERING = "modernized civil-script spelling"

      # getBible book number → OSIS book id (the file's 76 books). getBible
      # numbers the deuterocanon from 67 up; 40–66 are the NT.
      BOOKS = {
        1 => "Gen", 2 => "Exod", 3 => "Lev", 4 => "Num", 5 => "Deut", 6 => "Josh", 7 => "Judg",
        8 => "Ruth", 9 => "1Sam", 10 => "2Sam", 11 => "1Kgs", 12 => "2Kgs", 13 => "1Chr", 14 => "2Chr",
        15 => "Ezra", 16 => "Neh", 17 => "Esth", 18 => "Job", 19 => "Ps", 20 => "Prov", 21 => "Eccl",
        22 => "Song", 23 => "Isa", 24 => "Jer", 25 => "Lam", 26 => "Ezek", 27 => "Dan", 28 => "Hos",
        29 => "Joel", 30 => "Amos", 31 => "Obad", 32 => "Jonah", 33 => "Mic", 34 => "Nah", 35 => "Hab",
        36 => "Zeph", 37 => "Hag", 38 => "Zech", 39 => "Mal",
        40 => "Matt", 41 => "Mark", 42 => "Luke", 43 => "John", 44 => "Acts", 45 => "Rom", 46 => "1Cor",
        47 => "2Cor", 48 => "Gal", 49 => "Eph", 50 => "Phil", 51 => "Col", 52 => "1Thess",
        53 => "2Thess", 54 => "1Tim", 55 => "2Tim", 56 => "Titus", 57 => "Phlm", 58 => "Heb",
        59 => "Jas", 60 => "1Pet", 61 => "2Pet", 62 => "1John", 63 => "2John", 64 => "3John",
        65 => "Jude", 66 => "Rev",
        67 => "1Esd", 69 => "Tob", 70 => "Jdt", 73 => "Wis", 74 => "Sir", 75 => "Bar", 79 => "PrMan",
        80 => "1Macc", 81 => "2Macc", 84 => "EpJer"
      }.freeze
      NT = (40..66)

      MANIFEST = Nabu::SourceManifest.new(
        id: "elizabeth-bible",
        name: "The Elizabeth Bible (1757) in Church Slavonic — modernized-spelling rendering, via getBible",
        license: "Public Domain — the file's own distribution_license: \"Public Domain\" (getBible " \
                 "csielizabeth, the rusbible.ru electronic edition distributed as CrossWire SWORD " \
                 "cslelizabeth 1.5.2); the 1757 print is public domain by age",
        license_class: "open",
        upstream_url: "https://api.getbible.net/v2/csielizabeth.json",
        parser_family: "getbible-json",
        credit: "getBible (api.getbible.net), electronic edition from rusbible.ru"
      )

      def self.manifest = MANIFEST

      # The probe HEADs the translation file: reachability + Last-Modified
      # drift vs the .file-fetch.json pin. The license rides inside the
      # file, re-read at every real fetch.
      def self.remote_probe_strategy = :http_zip

      def self.http_probe_targets
        [Nabu::Adapter::HttpProbeTarget.new(
          label: FILENAME, zip_url: MANIFEST.upstream_url, metadata_url: nil,
          state_subdir: "", state_file: Nabu::FileFetch::STATE_FILE
        )]
      end

      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        path = translation_path(workdir)
        return unless path

        translation(path).fetch("books").each do |book|
          code = BOOKS[book["nr"]] or next
          yield Nabu::DocumentRef.new(
            source_id: MANIFEST.id, id: "#{URN_PREFIX}#{code.downcase}", path: File.expand_path(path),
            metadata: { "book" => code, "book_nr" => book["nr"], "title" => book["name"], "language" => LANGUAGE }
          )
        end
      end

      def discovery_skips(workdir)
        grains = Dir.glob(File.join(workdir, "**", "*.json")).reject { |p| File.basename(p) == FILENAME }
        path = translation_path(workdir)
        unknown = path ? translation(path).fetch("books").reject { |book| BOOKS.key?(book["nr"]) } : []
        Nabu::Adapter::DiscoverySkips.new(
          skipped_by_rule: grains.size,
          unrecognized: unknown.size,
          notes: unknown.map { |book| "getBible book nr #{book['nr']} (#{book['name']}) has no OSIS code" }
        )
      end

      def parse(document_ref)
        data = translation(document_ref.path)
        nr = document_ref.metadata.fetch("book_nr")
        book = data.fetch("books").find { |entry| entry["nr"] == nr } or
          raise Nabu::ParseError, "#{document_ref.path}: book nr #{nr} not found"

        document = Nabu::Document.new(urn: document_ref.id, language: LANGUAGE, canonical_path: document_ref.path,
                                      title: book["name"], metadata: metadata_for(data, document_ref))
        book.fetch("chapters").each do |chapter|
          chapter.fetch("verses").each do |verse|
            document << Nabu::Passage.new(urn: "#{document_ref.id}:#{chapter.fetch('chapter')}.#{verse.fetch('verse')}",
                                          language: LANGUAGE, text: Normalize.nfc(verse.fetch("text").split.join(" ")),
                                          sequence: document.size + 1)
          end
        end
        raise Nabu::ParseError, "#{document_ref.id}: no verses" if document.empty?

        document
      rescue Nabu::ValidationError, KeyError => e
        raise Nabu::ParseError, "#{document_ref.path}: #{document_ref.id}: #{e.message}"
      end

      # Download the one translation file via FileFetch (conditional GET,
      # sha pin, attic + guard contract). No network in tests: WebMock.
      def fetch(workdir, progress: nil, force: false)
        result = Nabu::FileFetch.sync!(
          url: manifest.upstream_url, dir: workdir, filename: FILENAME,
          attic_dir: File.join(workdir, ATTIC_DIRNAME), progress: progress,
          guard: ->(doomed) { guard_mass_deletion!(workdir, doomed, force: force) }
        )
        FetchReport.new(sha: result.sha, fetched_at: Time.now, notes: attic_notes(result.atticked))
      rescue FileFetch::Error => e
        raise Nabu::FetchError, "elizabeth-bible fetch failed into #{workdir}: #{e.message}"
      end

      private

      def translation_path(workdir)
        Dir.glob(File.join(workdir, "**", FILENAME)).min
      end

      # The parsed file, held once per instance (76 books parse from one
      # 23.7 MB file; re-reading it per book would cost a full JSON parse
      # each). Keyed by path + mtime + size so a re-fetch is never served
      # stale.
      def translation(path)
        stat = File.stat(path)
        key = [File.expand_path(path), stat.mtime, stat.size]
        return @translation if @translation_key == key

        @translation_key = key
        @translation = JSON.parse(SourceRead.utf8_file(path, label: MANIFEST.id))
      rescue JSON::ParserError => e
        @translation_key = nil
        raise Nabu::ParseError, "#{path}: malformed getBible JSON: #{e.message}"
      end

      def metadata_for(data, document_ref)
        {
          "book" => document_ref.metadata.fetch("book"),
          "book_nr" => document_ref.metadata.fetch("book_nr"),
          "testament" => NT.cover?(document_ref.metadata.fetch("book_nr")) ? "nt" : "ot",
          "rendering" => RENDERING,
          "script" => "Cyrl",
          "orthography" => "modernized",
          "versification" => data["distribution_versification"],
          "base_edition" => data["distribution_about"] && Normalize.nfc(data["distribution_about"]),
          "date" => edition_date(data["translation"])
        }.compact
      end

      # The edition year the translation title states ("1757 Church
      # Slavonic Elizabeth Bible") — date_class edition. No year, no date.
      def edition_date(title)
        year = title.to_s[/\b1[5-9]\d\d\b/] or return nil

        { "not_before" => year.to_i, "not_after" => year.to_i, "class" => "edition",
          "raw" => "#{year} — the edition the electronic text renders (upstream title " \
                   "\"#{Normalize.nfc(title)}\"); the modernized-spelling rendering itself is undated" }
      end
    end
  end
end

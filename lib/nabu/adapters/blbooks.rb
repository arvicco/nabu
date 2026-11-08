# frozen_string_literal: true

require "digest"
require "json"
require "zlib"

require_relative "../zip_fetch"
require_relative "../normalize"
require_relative "source_read"
require_relative "blbooks_title_genre"

module Nabu
  module Adapters
    # blbooks: the British Library's Digitised Books c.1510–c.1900 — the
    # Microsoft-digitised BL printed books (49,455 books / 65,227 volumes /
    # 25M+ pages), published by BL Labs as OCR text + catalogue metadata
    # ("Digitised Books. c. 1510 - c. 1900. JSONL (OCR derived text +
    # metadata)", DOI 10.23636/r7w6-zy15). THIS era of the source holds the
    # PRE-1800 CONE only (CONE below); the 19th-century mass is one CONE
    # line per decade away, an adoption-time call.
    #
    # == The route (probed 2026-11-08)
    #
    # The BL's own Hugging Face repo (TheBritishLibrary/blbooks, ungated,
    # main b085f99d) serves the set ONLY as parquet — and an incomplete
    # conversion at that: 50 of 61 shards on main, the other 11 in an
    # unmerged PR (refs/pr/3); the datasets-server rows API refuses the
    # repo ("Dataset scripts are no longer supported, but found
    # blbooks.py"). The repo's loading script names the ORIGINAL
    # per-period JSONL tarballs on the BL repository; their old
    # /downloads/<uuid> URLs answer 404 since the repository moved to
    # DSpace-CRIS, but the same tarballs are bitstreams of the dataset's
    # product record (bl.iro.bl.uk/entities/product/af56d5ab-…, DSpace
    # REST /server/api/core/items/<uuid>/bundles → ORIGINAL, 13
    # bitstreams). A GET of /bitstreams/<uuid>/download 302s to a signed
    # S3 URL on the 4science CDN and serves the tar.gz; a HEAD answers the
    # SPA's HTML shell (the "HTML stub" earlier probes met — a HEAD
    # artifact, not a refusal). No parquet reader, no new gem.
    #
    # Each tarball holds one top directory (<period>/) of per-BOOK
    # gzipped JSONL files, <year>_<record_id>.jsonl.gz, one JSON line per
    # PAGE: record_id, date, raw_date, title, place, empty_pg, text, pg,
    # mean_wc_ocr, std_wc_ocr, Name, All names, Publisher, Country of
    # publication 1, All Countries of publication, Physical description,
    # Language_1..4, multi_language — the book's catalogue fields repeated
    # on every page. Upstream quirk, pinned in the fixture: a missing
    # place is the bare JSON literal NaN (parsed allow_nan, read as
    # absent).
    #
    # == License (verbatim, read 2026-11-08)
    #
    # - BL repository product record af56d5ab-… (the JSONL deposit):
    #   dc.rights.license "https://creativecommons.org/publicdomain/zero/1.0/".
    # - HF card YAML: "license: - cc0-1.0".
    # - HF card prose: "The books are licensed under the [CC Public Domain
    #   Mark 1.0](https://creativecommons.org/publicdomain/mark/1.0/)
    #   license."
    # - BL dataset record 888b314f… (the 2014 text deposit, DOI
    #   10.21250/db14): "Licence CC Public Domain Mark 1.0".
    # The texts are PD (pre-1900 prints); the metadata is CC0. Class open.
    #
    # == The cone and its census (the pinned tarballs, 2026-11-08)
    #
    #   1510_1699.tar.gz  42,320,165 B   682 books   61,074 pages (51,982 with text)
    #   1700_1799.tar.gz  95,137,895 B 1,816 books  198,686 pages (178,224 with text)
    #
    # = 2,498 books / 259,760 page rows / 230,206 pages with text, ~301M
    # characters of OCR; 137.5 MB on the wire and on disk (the per-book
    # files stay gzipped). Every file carries exactly one record_id, and
    # its file-name year equals its date field. The cone is ~5% of the
    # books and 1.3% of the bytes (the 13 bitstreams total 10.5 GB).
    #
    # Upstream's delivery grains: the 13 period tarballs (1510_1699,
    # 1700_1799, ten 1800s decades, and unk — 79 books with no date,
    # 20.4 MB) → per-book JSONL → per-page rows. The adapter takes the
    # BOOK as the document and the PAGE as the passage (the ndl-kotenseki
    # precedent). Rejected grains, each pinned in the fixture tree and
    # skipped BY RULE (discovery_skips), never silently:
    # - a book file under any period directory outside CONE (an 1800s
    #   decade; unk — undated, so no pre-1800 claim can be made, though
    #   some of the 79 are early prints by their titles: a dating lane is
    #   a follow-up, not this cone);
    # - the one cone book whose every page is empty_pg (EMPTY_BOOKS:
    #   001370315, Capell's MS. catalogues of Garrick's plays — 414
    #   manuscript leaves the OCR never read);
    # - empty_pg pages mint no passage (counted per document,
    #   metadata empty_pages).
    # Reconciliation: upstream advertises 682 + 1,816 book files in the
    # two cone tarballs; 2,497 documents + 1 skipped by rule = 2,498.
    #
    # == OCR, not an edition (declared)
    #
    # Raw Microsoft-era OCR of early modern type — long s read as f,
    # ligatures, catchwords, running heads, blackletter and Fraktur read
    # as noise. text_nature "machine-ocr"; nothing is corrected (canonical
    # means canonical). Each page's own OCR word-confidence pair rides the
    # passage annotations (ocr_mean_wc / ocr_std_wc) so a reader can weigh
    # a page before trusting it.
    #
    # == Axes (aggressive mining)
    #
    # - date — the catalogue year (date; raw_date's range where it carries
    #   one: "1780-1790" → 1780–1790, a serial's "1781-" stays 1781) →
    #   {not_before, not_after, raw, class edition}: the PRINT year.
    # - place — the imprint place as catalogued ("London", "Oxonii",
    #   "Seuilla"), the first of a " ; " list (the list rides as
    #   imprint_places); country of publication beside it.
    # - language — Language_1 onto the registry's codes (LANGUAGES), all
    #   four slots into "languages". LANGUAGE_ERRATA corrects 24 records
    #   (census 2026-11-08): 8 continental imprints catalogued "English"
    #   against their own title pages and OCR (the 1510 Paris Plutarch,
    #   Latin; Seville 1584, Spanish; Rome 1556 and Florence 1774,
    #   Italian; Berlin 1765 and Königsberg 1798, German; Delft 1784,
    #   Dutch; the 1528 Bologna Latin verse) and the 16 records with no
    #   language at all whose titles and OCR are English (English
    #   function-word share 0.13–0.25, the Latin-English Horace imitation
    #   lowest). The catalogue's own value rides as bl_language.
    # - kind — the title's form noun (BlbooksTitleGenre; no upstream genre
    #   field), folded in config/kind_map.yml.
    # - author — Name (the catalogue heading); every "All names" entry
    #   rides as names [{name, kind}], the persons as the author facet.
    class Blbooks < Nabu::Adapter
      SLUG = "blbooks"
      URN_PREFIX = "urn:nabu:blbooks:"
      BITSTREAM_URL = "https://bl.iro.bl.uk/bitstreams/%s/download"
      RECORD_URL = "https://bl.iro.bl.uk/entities/product/af56d5ab-a384-4880-ba78-eca1ffd6a54d"

      Period = Data.define(:bitstream, :bytes, :sha256)

      # The cone: period tarball → its bitstream, size and hard sha256 pin
      # (the deposit is a 2021 snapshot; a drift is corruption or a silent
      # re-release, never a routine update).
      CONE = {
        "1510_1699" => Period.new(bitstream: "c3fcee4c-1b01-4846-b0f9-7387ce0117a3", bytes: 42_320_165,
                                  sha256: "6795dd54f6b489f9fcd9146bdd6d5d9abdcb34e1492e7a283b720936292ac599"),
        "1700_1799" => Period.new(bitstream: "e64fdf0c-9d5f-4474-82a0-81a33f0e5420", bytes: 95_137_895,
                                  sha256: "da6ca8597b7e65c0be51b239f5aa06462419970332c2c82308b8f2e1fe66b58e")
      }.freeze

      # Upstream's period directories outside the cone (skipped by rule
      # when present): the ten 1800s decades and the undated unk.
      PERIOD_DIR = /\A(?:\d{4}_\d{4}|unk)\z/
      BOOK_FILE = /\A(?:\d{4}|UNKOWN)_(\d+)\.jsonl\.gz\z/

      # Cone books with no OCR on any page (census 2026-11-08).
      EMPTY_BOOKS = {
        "001370315" => "Capell's MS. catalogues of Garrick's plays (1778): 414 manuscript leaves, no OCR"
      }.freeze

      # The catalogue's language names → registry codes (lat is the
      # registry's Latin anchor; the rest are the 639-1 anchors). Exactly
      # the names the cone carries (census 2026-11-08: English, French,
      # Latin, Italian, German in Language_1..4; Spanish and Dutch reached
      # only through the errata). A widening censuses its own names — an
      # unlisted one reads "und", never a guess.
      LANGUAGES = {
        "English" => "en", "French" => "fr", "Latin" => "lat", "Italian" => "it",
        "German" => "de", "Spanish" => "es", "Dutch" => "nl"
      }.freeze
      UNKNOWN_LANGUAGE = "und"

      # Record-level corrections of Language_1 (class note; census
      # 2026-11-08 over the whole cone). The catalogue's value rides as
      # bl_language; the reason as language_erratum.
      FOREIGN = "the catalogue says English; the title page and OCR are not"
      UNSTATED = "no catalogue language; the title and OCR are English"
      LANGUAGE_ERRATA = {
        "002938347" => ["lat", "#{FOREIGN} (Plutarch's Apophthegmata, Paris 1510: Latin)"],
        "000840022" => ["lat", "#{FOREIGN} (Ro. vrbis excidium, Bologna 1528: Latin verse)"],
        "001080196" => ["it", "#{FOREIGN} (Capitoli della Tregua, Rome 1556: Italian)"],
        "002263347" => ["es", "#{FOREIGN} (Verdadero Entretenimiento del Christiano, Seville 1584: Spanish)"],
        "001230725" => ["de", "#{FOREIGN} (Fielding komischer Roman, Berlin 1765: German)"],
        "002414782" => ["it", "#{FOREIGN} (Elfrida. Poema drammatico, Florence 1774: Italian)"],
        "001346555" => ["nl", "#{FOREIGN} (Rym Journaal, Delft 1784: Dutch)"],
        "000553383" => ["de", "#{FOREIGN} (Butlers Hudibras, frey übersetzt, Königsberg 1798: German)"],
        "002177162" => ["en", UNSTATED], "001733788" => ["en", UNSTATED],
        "002941593" => ["en", UNSTATED], "001895346" => ["en", UNSTATED],
        "001440932" => ["en", UNSTATED], "001440933" => ["en", UNSTATED],
        "001370335" => ["en", UNSTATED], "001370222" => ["en", UNSTATED],
        "003626484" => ["en", UNSTATED], "000133732" => ["en", UNSTATED],
        "002144677" => ["en", UNSTATED], "001664273" => ["en", UNSTATED],
        "003508322" => ["en", UNSTATED], "001643125" => ["en", UNSTATED],
        "001945835" => ["en", UNSTATED], "003496675" => ["en", UNSTATED]
      }.freeze

      OCR_NOTE = "Uncorrected Microsoft-era OCR of the British Library's scans (BL Labs, 2021 JSONL " \
                 "release): long s, ligatures, running heads and catchwords ride as recognized; " \
                 "each page's OCR word confidence rides its annotations."

      MANIFEST = Nabu::SourceManifest.new(
        id: SLUG,
        name: "British Library Digitised Books c.1510–c.1900 — OCR text (pre-1800 cone)",
        license: "CC0 1.0 (BL repository record: dc.rights.license " \
                 "https://creativecommons.org/publicdomain/zero/1.0/; HF card license: cc0-1.0) / " \
                 "CC Public Domain Mark 1.0 (HF card prose: \"The books are licensed under the CC " \
                 "Public Domain Mark 1.0 license\") — pre-1900 prints, the texts public domain; " \
                 "the text is uncorrected OCR, not an edition",
        license_class: "open",
        upstream_url: RECORD_URL,
        parser_family: "blbooks-jsonl",
        credit: "British Library Labs, Digitised Books c.1510–c.1900 (JSONL), DOI 10.23636/r7w6-zy15"
      )

      def self.manifest = MANIFEST

      # Each parse opens its own book file — no state crosses refs.
      def self.parallel_parse? = true

      # The extracted period trees (a plain tree: the identity walker
      # hashes every byte anyway; declared for the rule's sake).
      def self.materialized_paths = CONE.keys

      # GET-only bitstreams (a HEAD answers the repository SPA's HTML
      # shell, no Last-Modified): liveness only, drift rides the pin.
      def self.remote_probe_strategy = :http_zip

      def self.http_probe_targets
        CONE.map do |name, period|
          Nabu::Adapter::HttpProbeTarget.new(
            label: "#{name}.tar.gz", zip_url: format(BITSTREAM_URL, period.bitstream),
            metadata_url: nil, state_subdir: name, liveness_only: true
          )
        end
      end

      # +cone+/+http+ are seams for tests (a stub tarball's own pin).
      def initialize(cone: CONE, http: Nabu::ZipFetch.default_http)
        super()
        @cone = cone
        @http = http
      end

      # -- fetch -------------------------------------------------------------

      # Every cone tarball is downloaded (streamed) and unpacked into
      # staging FIRST, each checked against its sha pin, and the
      # mass-deletion breaker runs over all of them before ANY period's
      # tree changes (the multi-project ZipFetch choreography). A 304
      # touches nothing.
      def fetch(workdir, progress: nil, force: false)
        fetches = @cone.to_h { |name, period| [name, period_fetch(workdir, name, period, progress)] }
        begin
          fetches.each do |name, fetch|
            fetch.prepare!
            verify_pin!(name, fetch)
          end
          guard_mass_deletion!(workdir, fetches.values.flat_map(&:doomed_paths), force: force)
          fetches.each_value(&:complete!)
        ensure
          fetches.each_value(&:cleanup!)
        end
        Nabu::FetchReport.new(sha: Digest::SHA256.hexdigest(fetches.values.map(&:sha).join("\n")),
                              fetched_at: Time.now, notes: fetch_notes(fetches))
      rescue Nabu::ZipFetch::Error, Nabu::Shell::Error => e
        raise Nabu::FetchError, "blbooks fetch failed into #{workdir}: #{e.message}"
      end

      # -- discover ----------------------------------------------------------

      # One ref per cone book file, in period then file order (the file
      # name leads with the year). A pre-fetch workdir yields nothing.
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        @cone.each_key do |period|
          book_files(workdir, period).each do |path, record_id|
            next if EMPTY_BOOKS.key?(record_id)

            block.call(Nabu::DocumentRef.new(
                         source_id: SLUG, id: "#{URN_PREFIX}#{record_id}", path: File.expand_path(path),
                         metadata: { "period" => period, "record_id" => record_id }
                       ))
          end
        end
      end

      # The rule skips (class note) and anything in a cone directory that
      # is not a book file (unrecognized — a defect, never a norm).
      def discovery_skips(workdir)
        notes = []
        skipped = 0
        unrecognized = 0
        period_dirs(workdir).each do |period|
          if @cone.key?(period)
            empty = book_files(workdir, period).count { |_, id| EMPTY_BOOKS.key?(id) }
            skipped += empty
            notes << "#{period}: #{empty} book(s) with no OCR on any page" if empty.positive?
            strays = stray_files(workdir, period)
            unrecognized += strays.size
            notes.concat(strays.map { |name| "#{period}/#{name}: not a book file" })
          else
            count = book_files(workdir, period).size
            skipped += count
            notes << "#{period}: #{count} book(s) outside the pre-1800 cone" if count.positive?
          end
        end
        Nabu::Adapter::DiscoverySkips.new(skipped_by_rule: skipped, unrecognized: unrecognized, notes: notes)
      end

      # -- parse -------------------------------------------------------------

      def parse(document_ref)
        rows = read_rows(document_ref.path)
        head = rows.first or raise ParseError, "#{document_ref.path}: no page rows"
        record_id = document_ref.metadata.fetch("record_id")
        unless rows.all? { |row| row["record_id"] == record_id }
          raise ParseError, "#{document_ref.path}: a row's record_id is not #{record_id}"
        end

        language, language_meta = language_for(head)
        document = Nabu::Document.new(
          urn: document_ref.id, language: language, title: text(head["title"]),
          canonical_path: document_ref.path,
          metadata: book_metadata(head, rows, document_ref).merge(language_meta)
        )
        append_pages(document, document_ref.id, rows, language)
        raise ParseError, "#{document_ref.path}: no page carries OCR text" if document.empty?

        document
      rescue Nabu::ValidationError => e
        raise ParseError, "#{document_ref.path}: #{e.message}"
      end

      private

      # -- fetch internals ---------------------------------------------------

      def period_fetch(workdir, name, period, progress)
        Nabu::ZipFetch.new(url: format(BITSTREAM_URL, period.bitstream), dir: File.join(workdir, name),
                           attic_dir: File.join(workdir, ATTIC_DIRNAME, name), http: @http,
                           progress: progress, stream: true, archive: :tar_gz)
      end

      def verify_pin!(name, fetch)
        expected = @cone.fetch(name).sha256
        return if fetch.not_modified? || fetch.sha == expected

        raise Nabu::FetchError,
              "blbooks: #{name}.tar.gz misses its sha256 pin (expected #{expected}, got #{fetch.sha}) — " \
              "the 2021 deposit is a frozen snapshot, so this is corruption or an unannounced " \
              "re-release; read #{RECORD_URL} and re-pin CONE only after re-censusing"
      end

      def fetch_notes(fetches)
        parts = fetches.map do |name, fetch|
          "#{name}: #{fetch.not_modified? ? 'not modified (304)' : 'sha pin verified'}"
        end
        [parts.join("; "), attic_notes(fetches.values.flat_map(&:atticked))].compact.join("; ")
      end

      # -- discovery internals -----------------------------------------------

      def period_dirs(workdir)
        return [] unless Dir.exist?(workdir)

        Dir.children(workdir).sort.select do |name|
          name.match?(PERIOD_DIR) && File.directory?(File.join(workdir, name))
        end
      end

      # [[path, record_id]] for the period's book files, sorted.
      def book_files(workdir, period)
        dir = File.join(workdir, period)
        return [] unless Dir.exist?(dir)

        Dir.children(dir).sort.filter_map do |name|
          match = BOOK_FILE.match(name) or next
          [File.join(dir, name), match[1]]
        end
      end

      def stray_files(workdir, period)
        dir = File.join(workdir, period)
        Dir.children(dir).sort.reject { |name| name.match?(BOOK_FILE) || name.start_with?(".") }
      end

      # -- parse internals ---------------------------------------------------

      # The gunzipped book through the belt's UTF-8 check (the vakk gz
      # mold — the belt has no gzip reader; a book is ≤ 2.6 MB gzipped).
      def read_rows(path)
        body = SourceRead.utf8(Zlib.gunzip(File.binread(path)), label: "blbooks book #{path}")
        body.each_line.reject { |line| line.strip.empty? }.map { |line| JSON.parse(line, allow_nan: true) }
      rescue JSON::ParserError, Zlib::Error, Errno::ENOENT => e
        raise ParseError, "#{path}: unreadable book file: #{e.message}"
      end

      def append_pages(document, urn, rows, language)
        rows.each do |row|
          next if row["empty_pg"]

          body = text(row["text"])
          next if body.nil?

          document << Nabu::Passage.new(
            urn: "#{urn}:#{row['pg']}", language: language, text: body, sequence: document.size,
            annotations: { "page" => row["pg"], "ocr_mean_wc" => number(row["mean_wc_ocr"]),
                           "ocr_std_wc" => number(row["std_wc_ocr"]) }.compact
          )
        end
      end

      def book_metadata(head, rows, document_ref)
        places = list(head["place"])
        countries = list(head["All Countries of publication"])
        names = name_list(head["All names"])
        persons = names.select { |entry| entry["kind"] == "person" }.map { |entry| entry["name"] }
        {
          "text_nature" => "machine-ocr", "ocr_note" => OCR_NOTE,
          "bl_record_id" => document_ref.metadata["record_id"],
          "bl_period" => document_ref.metadata["period"],
          "date" => date_envelope(head),
          "place" => places.first, "imprint_places" => (places if places.size > 1),
          "country" => text(head["Country of publication 1"]),
          "countries" => (countries if countries.size > 1),
          "publisher" => text(head["Publisher"]), "extent" => text(head["Physical description"]),
          "author" => text(head["Name"]), "names" => (names unless names.empty?),
          "page_count" => rows.size, "empty_pages" => rows.count { |row| row["empty_pg"] },
          "facets" => facets(head["title"], persons)
        }.compact
      end

      def facets(title, persons)
        facets = {}
        head = BlbooksTitleGenre.head(title)
        facets["genre"] = { "value" => head, "raw" => text(title) } if head
        facets["author"] = { "values" => persons.uniq } unless persons.empty?
        facets.empty? ? nil : facets
      end

      # [code, metadata] — the errata table first, then Language_1.
      def language_for(head)
        stated = text(head["Language_1"])
        all = (1..4).filter_map { |i| text(head["Language_#{i}"]) }
                    .map { |name| LANGUAGES.fetch(name, UNKNOWN_LANGUAGE) }
        meta = { "bl_language" => stated, "multi_language" => head["multi_language"] == true || nil }
        if (erratum = LANGUAGE_ERRATA[head["record_id"]])
          code, reason = erratum
          meta["language_erratum"] = reason
          all = [code] + all.drop(1)
        else
          code = stated ? LANGUAGES.fetch(stated, UNKNOWN_LANGUAGE) : UNKNOWN_LANGUAGE
        end
        meta["languages"] = all.uniq if all.uniq.size > 1
        [code, meta.compact]
      end

      # The catalogue year, widened by a raw_date range; class edition.
      def date_envelope(head)
        year = head["date"]
        return nil unless year.is_a?(Integer)

        raw = text(head["raw_date"]) || year.to_s
        years = raw.scan(/\b(1\d{3})\b/).flatten.map { |y| Integer(y, 10) }
        years = [year] if years.empty?
        { "not_before" => years.min, "not_after" => years.max, "raw" => raw, "class" => "edition" }
      end

      # "Regius, Raphael [person] ; England [organisation]" →
      # [{"name" => "Regius, Raphael", "kind" => "person"}, …].
      def name_list(value)
        list(value).map do |part|
          name, kind = part.match(/\A(.*?)\s*\[(\w+)\]\z/)&.captures || [part, nil]
          { "name" => name, "kind" => kind }.compact
        end
      end

      def list(value)
        (text(value) || "").split(";").map(&:strip).reject(&:empty?)
      end

      # A catalogue string, NFC and stripped; nil for null, NaN or blank.
      def text(value)
        return nil unless value.is_a?(String)

        stripped = value.strip
        stripped.empty? ? nil : Normalize.nfc(stripped)
      end

      def number(value)
        value.is_a?(Numeric) && !(value.is_a?(Float) && value.nan?) ? value : nil
      end
    end
  end
end

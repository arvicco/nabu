# frozen_string_literal: true

require "digest"

require_relative "opengnt_csv_parser"
require_relative "source_read"

module Nabu
  module Adapters
    # The Open Greek New Testament (eliranwong/OpenGNT, Eliran Wong): OGNT
    # version 3, a free NA28-equivalent Greek New Testament compiled from
    # the Berean Greek Bible database (itself on Nestle 1904), weighed
    # against BHP, with Nestle-1904 versification following SBLGNT's minor
    # variations. Upstream states "only … a total of 61 words different
    # from the text of NA28" apart from orthography. Word-tagged: every
    # word carries its lexeme, Robinson morphology (RMAC), extended Strong's
    # number and Louw-Nida key. A third Greek NT witness beside sblgnt and
    # PROIEL's greek-nt — distinct editions, never a dedupe.
    #
    # == Delivery grains (enumerated at fixture time, 2026-11-18)
    #
    # The repo (dormant since 2022-04-21, no releases) serves many grains:
    # the base-text zip (THE document source), OpenGNT_keyedFeatures.csv.zip
    # (Levinsohn/OpenText mapping features), interlinear and clause
    # translation zips (Berean, NET2, CUV, CSB, Spanish), per-language RMAC
    # dictionaries, lexicons, glossaries, Bible-app modules, mapping
    # templates and old versions. Only the base text is fetched; every
    # other grain is out of scope by rule and never lands in canonical/.
    # Inside the fetched zip the only other member is the macOS AppleDouble
    # resource fork __MACOSX/._OpenGNT_version3_3.csv — skipped by rule in
    # discovery_skips (pinned real in the fixture tree). Anything else in
    # the tree is UNRECOGNIZED (a defect, never silently dropped).
    #
    # == Identity (FROZEN minting) — the sblgnt conventions
    #
    # One document per NT book (CSV book numbers 40–66), urn
    # urn:nabu:opengnt:<sblgnt stem> (matt, mark, 1cor, titus, phlm, 3john,
    # rev…) so the Greek NT witnesses align book-for-book with
    # urn:nabu:sblgnt:<stem>; passages <doc-urn>:<chapter>.<verse>. Titles
    # are English book names (the CSV carries no titles). An unknown book
    # number is a loud ParseError at discover, never a guess.
    #
    # == Text: the accented OGNTa column
    #
    # Column 7 packs 〔OGNTk｜OGNTu｜OGNTa｜lexeme｜rmac｜sn〕 (README /
    # fileDescription.md: OGNTk = Koine-font encoding, lunate sigma and
    # nomina sacra overlines; OGNTu = unaccented; OGNTa = "Greek word of
    # OGNT in accented form"). The passage text is OGNTa — the accented
    # canonical text — with the punctuation of column 11 (PMpWord/PMfWord,
    # TANTT-derived) attached, words single-space joined. ¶ (paragraph end)
    # and ¬ (indented-line opener) are layout marks: they ride the token's
    # "pmp"/"pmf" verbatim and are kept out of the running text. [[ ]]
    # (Mark 16:9–20's brackets and the shorter ending appended inside 16:20,
    # John 7:53–8:11) stay in the text — canonical means canonical.
    #
    # == Word-level layers (annotations["tokens"], the house token contract)
    #
    # Kept, one hash per word: "id" (OGNTsort), "form" (OGNTa), "lemma"
    # (lexeme — the lemma index's default key), "rmac" (Robinson code,
    # verbatim), "strong" (extended Strong's, G976 style), "ln" (Louw-Nida,
    # "LN-33.38" verbatim, multi-keys joined by upstream's fullwidth comma),
    # "pmp"/"pmf" (punctuation marks), and the NA28-comparison columns:
    # "note" (＊ differs from NA28, ＝ orthographic variant of the NA28
    # word, ＋BYZ/＋BHP words added from those editions) with the NA28-side
    # reading "mvar"/"mlexeme"/"mrmac"/"msn". The OT-quotation flag is NOT
    # kept: it is the Levinsohn layer (see License).
    #
    # Declared coarse (not license-bound; deferred, never silent): OGNTk and
    # OGNTu (renderings of the same word), the BDAG/EDNT/Mounce catchwords
    # and Goodrick-Kohlenberger numbers (lookup keys into lexica the
    # library does not hold), the SBL/modern-Greek transliterations
    # (mechanical), and the sort/mapping keys into other OpenGNT files. RMAC
    # is stored verbatim but not yet decoded by Query::MorphFacets (a new
    # tagset row is its own change), so `--morph` facets do not match
    # opengnt tokens yet; `search --lemma` does.
    #
    # == License (verified first-hand at fixture time from the README)
    #
    # The core database is CC BY-SA 4.0 → license_class "attribution",
    # share-alike noted. Verbatim (README "License:"): "The main text of
    # Open Greek New Testament Project, OGNT in short, is released under the
    # following license: … Open Greek New Testament Project by Eliran Wong
    # is licensed under a Creative Commons Attribution-ShareAlike 4.0
    # International License."
    #
    # EXCLUDED AT PARSE (the adapter never emits them; a test pins it):
    # - column 10 〔TBESG｜IT｜LT｜ST｜Español〕 and the variant's MTBESG:
    #   TBESG glosses (Tyndale's TBESG file is itself titled "CC BY-NC-ND"
    #   in fileDescription.md's link), the Interlinear/Literal/Study
    #   translations "adapted from Berean Interlinear Bible" (README credit:
    #   "Copyright ©2016, 2018 by Bible Hub … Used by Permission. All Rights
    #   Reserved Worldwide."), and the Spanish literal translation;
    # - columns 3–4, LevinsohnClauseID and OTquotation: the SIL discourse
    #   layer (Levinsohn GNT Discourse Features, "©2016 SIL International",
    #   distributed under SIL's own end-user licence — no sale on its own,
    #   licensing above 25% of a sold work, mandatory attribution), terms
    #   outside the CC BY-SA grant.
    #
    # == Reconciliation plan (the first real sync)
    #
    # Census of the pinned CSV at fixture time: 138,013 word rows (+1 header
    # = 138,014 lines), 27 books (40–66), 7,941 distinct verses. The first
    # sync must land exactly 27 documents / 7,941 passages / 138,013 tokens,
    # with 1 file skipped by rule (the AppleDouble) and 0 unrecognized.
    # sblgnt holds 7,939 verses: the two-verse residue is the versification
    # difference to reconcile verse-for-verse at wiring.
    #
    # == fetch
    #
    # Nabu::ZipFetch over the raw blob URL AT THE PINNED COMMIT (immutable),
    # with the zip's sha256 checked between download and any tree mutation
    # (the clics choreography). The zip unpacks to the CSV + __MACOSX/ at
    # the workdir root. The workdir is a plain (non-git) tree, so its
    # identity is the bytes of every file — no materialized_paths
    # declaration applies (that rule is for untracked artifacts beside a
    # git checkout); nothing else is materialized.
    class Opengnt < Nabu::Adapter
      COMMIT_SHA = "0029589cccd50bd48b1941aa041a956de6c29ac4"

      ARTIFACT_URL = "https://raw.githubusercontent.com/eliranwong/OpenGNT/#{COMMIT_SHA}/OpenGNT_BASE_TEXT.zip".freeze

      # sha256 of the zip at COMMIT_SHA (8,351,123 B), downloaded 2026-11-18.
      RELEASE_SHA256 = "7d8377bad8d8c836272ca67a646024a303e524434345c61ee288b82d13f8e712"

      CSV_FILE = "OpenGNT_version3_3.csv"
      APPLEDOUBLE = %r{\A__MACOSX/\._}

      # The data shapes upstream ships (the base CSV, its TSV/zip siblings,
      # text dumps) — what the discovery census accounts for.
      CONTENT_PATTERN = /\.(?:csv|tsv|txt|zip|json)\z/i

      LANGUAGE = "grc"
      URN_PREFIX = "urn:nabu:opengnt:"

      # CSV book number → [sblgnt file stem (downcased), English title].
      BOOKS = {
        40 => %w[matt Matthew], 41 => %w[mark Mark], 42 => %w[luke Luke], 43 => %w[john John],
        44 => %w[acts Acts], 45 => %w[rom Romans], 46 => ["1cor", "1 Corinthians"],
        47 => ["2cor", "2 Corinthians"], 48 => %w[gal Galatians], 49 => %w[eph Ephesians],
        50 => %w[phil Philippians], 51 => %w[col Colossians], 52 => ["1thess", "1 Thessalonians"],
        53 => ["2thess", "2 Thessalonians"], 54 => ["1tim", "1 Timothy"], 55 => ["2tim", "2 Timothy"],
        56 => %w[titus Titus], 57 => %w[phlm Philemon], 58 => %w[heb Hebrews], 59 => %w[jas James],
        60 => ["1pet", "1 Peter"], 61 => ["2pet", "2 Peter"], 62 => ["1john", "1 John"],
        63 => ["2john", "2 John"], 64 => ["3john", "3 John"], 65 => %w[jude Jude],
        66 => %w[rev Revelation]
      }.freeze

      MANIFEST = Nabu::SourceManifest.new(
        id: "opengnt",
        name: "Open Greek New Testament (OpenGNT, OGNT v3)",
        license: "CC BY-SA 4.0 (README verbatim: \"Open Greek New Testament Project by Eliran Wong is " \
                 "licensed under a Creative Commons Attribution-ShareAlike 4.0 International License.\"); " \
                 "share-alike; credit Eliran Wong, Open Greek New Testament Project, " \
                 "https://github.com/eliranwong/OpenGNT. The bundled glosses/translations and the " \
                 "SIL Levinsohn discourse columns are excluded at parse",
        license_class: "attribution",
        upstream_url: "https://github.com/eliranwong/OpenGNT",
        parser_family: "opengnt-csv"
      )

      def self.manifest
        MANIFEST
      end

      def self.remote_probe_strategy = :http_zip

      def self.http_probe_targets
        [Nabu::Adapter::HttpProbeTarget.new(
          label: "OpenGNT_BASE_TEXT.zip", zip_url: ARTIFACT_URL, metadata_url: nil,
          state_subdir: "", state_file: Nabu::ZipFetch::STATE_FILE
        )]
      end

      # +pin+ overrides the zip sha (tests; a future re-pin drill).
      def initialize(pin: RELEASE_SHA256)
        super()
        @pin = pin
      end

      # One DocumentRef per book block of the CSV, sorted by urn. The CSV is
      # in OGNTsort order, so each book is one contiguous line range; the
      # range rides the ref metadata so parse decodes only its book. Without
      # a block, an Enumerator (the adapter contract's lazy shape).
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        path = File.join(workdir, CSV_FILE)
        return unless File.file?(path)

        book_ranges(path).map { |book, (first, count)| book_ref(path, book, first, count) }
                         .sort_by(&:id).each(&block)
      end

      # Every content-shaped tree file (CONTENT_PATTERN) other than the CSV:
      # the AppleDouble by rule, anything else unrecognized. Fetch
      # bookkeeping (state file, attic) is not content.
      def discovery_skips(workdir)
        others = tree_files(workdir).grep(CONTENT_PATTERN) - [CSV_FILE]
        appledouble, unknown = others.partition { |rel| APPLEDOUBLE.match?(rel) }
        notes = appledouble.map { |rel| "macOS AppleDouble resource fork in the zip (not text): #{rel}" } +
                unknown.map { |rel| "unexpected file beside the base-text CSV: #{rel}" }
        Nabu::Adapter::DiscoverySkips.new(skipped_by_rule: appledouble.size, unrecognized: unknown.size,
                                          notes: notes)
      end

      def parse(document_ref)
        meta = document_ref.metadata
        label = "opengnt #{document_ref.id}"
        words = parser.words(book_lines(document_ref.path, meta.fetch("first_line"), meta.fetch("lines"), label),
                             label: label)
        book = meta.fetch("book_number")
        stray = words.find { |w| w.book != book }
        raise Nabu::ParseError, "#{label}: line range holds book #{stray.book}" if stray

        document = Nabu::Document.new(urn: document_ref.id, language: LANGUAGE,
                                      canonical_path: document_ref.path, title: meta.fetch("title"),
                                      metadata: { "book_number" => book })
        words.chunk_while { |a, b| a.chapter == b.chapter && a.verse == b.verse }.each do |verse_words|
          document << passage(document_ref.id, verse_words, document.size)
        end
        document
      rescue Nabu::ValidationError, Nabu::Normalize::EncodingError => e
        raise Nabu::ParseError, "#{label}: #{e.message}"
      end

      # ZipFetch with the phases driven by hand so the sha pin is checked
      # BETWEEN download and any tree mutation.
      def fetch(workdir, progress: nil, force: false)
        fetch = Nabu::ZipFetch.new(url: ARTIFACT_URL, dir: workdir,
                                   attic_dir: File.join(workdir, ATTIC_DIRNAME), progress: progress)
        begin
          fetch.prepare!
          verify_pin!(fetch)
          guard_mass_deletion!(workdir, fetch.doomed_paths, force: force)
          fetch.complete!
        ensure
          fetch.cleanup!
        end
        Nabu::FetchReport.new(sha: fetch.sha, fetched_at: Time.now, notes: fetch_notes(fetch))
      rescue ZipFetch::Error, Nabu::Shell::Error => e
        raise Nabu::FetchError, "opengnt fetch failed into #{workdir}: #{e.message}"
      end

      private

      def parser
        @parser ||= OpengntCsvParser.new
      end

      def passage(doc_urn, words, sequence)
        first = words.first
        Nabu::Passage.new(
          urn: "#{doc_urn}:#{first.chapter}.#{first.verse}", language: LANGUAGE,
          text: Normalize.nfc(parser.verse_text(words)), sequence: sequence,
          annotations: { "tokens" => words.map(&:token) }
        )
      end

      def book_ref(path, book, first_line, lines)
        stem, title = BOOKS.fetch(book) do
          raise Nabu::ParseError, "opengnt #{path}: book number #{book} is not an NT book (40–66)"
        end
        Nabu::DocumentRef.new(
          source_id: manifest.id, id: "#{URN_PREFIX}#{stem}", path: File.expand_path(path),
          metadata: { "title" => title, "book_number" => book, "first_line" => first_line, "lines" => lines }
        )
      end

      # {book => [first line number, line count]} over the data lines (1 =
      # the header, checked first). A book that reappears after another is
      # a ParseError (the line-range plan relies on OGNTsort grouping).
      def book_ranges(path)
        ranges = {}
        current = nil
        SourceRead.utf8_lines(path, label: "opengnt").each_with_index do |line, index|
          next parser.check_header!(line, label: path) if index.zero?

          book = parser.book_number(line, label: path)
          if book != current
            raise Nabu::ParseError, "opengnt #{path}: book #{book} is not contiguous" if ranges.key?(book)

            ranges[book] = [index + 1, 0]
            current = book
          end
          ranges[book][1] += 1
        end
        ranges
      end

      # The +count+ data lines from line number +first+ (1-based), joined —
      # streamed, stopping once the book's range is read.
      def book_lines(path, first, count, label)
        lines = []
        number = 0
        SourceRead.utf8_lines(path, label: label) do |line|
          break if lines.size == count

          number += 1
          lines << line if number >= first
        end
        raise Nabu::ParseError, "#{label}: lines #{first}+#{count} reach past the end of #{path}" if lines.size < count

        lines.join
      end

      def tree_files(workdir)
        return [] unless File.directory?(workdir)

        Dir.glob("**/*", File::FNM_DOTMATCH, base: workdir)
           .select { |rel| File.file?(File.join(workdir, rel)) }
           .reject { |rel| rel == Nabu::ZipFetch::STATE_FILE || rel.split("/").first == ATTIC_DIRNAME }
           .sort
      end

      def verify_pin!(fetch)
        return if fetch.not_modified? || fetch.sha == @pin

        raise Nabu::FetchError,
              "opengnt: downloaded zip misses the sha256 pin (expected #{@pin}, got #{fetch.sha}) — " \
              "the URL names commit #{COMMIT_SHA}, whose blob never changes, so this is corruption; " \
              "verify #{ARTIFACT_URL} and re-pin RELEASE_SHA256 only after reading upstream"
      end

      def fetch_notes(fetch)
        base = fetch.not_modified? ? "not modified (304)" : "commit #{COMMIT_SHA[0, 7]} zip sha pin verified"
        [base, attic_notes(fetch.atticked)].compact.join("; ")
      end
    end
  end
end

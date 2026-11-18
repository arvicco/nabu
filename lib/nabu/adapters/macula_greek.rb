# frozen_string_literal: true

module Nabu
  module Adapters
    # MACULA Greek (Clear-Bible/macula-greek, Biblica): the word-level TSV
    # of the SBL Greek New Testament — one row per word, keyed word-by-word
    # (xml:id n<book><chapter><verse><word>) to the SBLGNT text, carrying
    # Clear's syntax roles, morphology, Strong's numbers, semantic frames
    # and participant referents, the Berean interlinear gloss, and the
    # Cherith English and Mandarin glosses.
    #
    # == A deliberate overlap: an annotation edition of a held text
    #
    # The SBLGNT text itself is held as `sblgnt` (Faithlife/SBLGNT). This
    # source is the SAME text as an ANNOTATION EDITION, landed as its own
    # source on purpose: the word-level layers are the value, and they key
    # to MACULA's own word segmentation, not to anything in sblgnt's verse
    # lines. Distinct documents, never a dedupe. URNs mirror sblgnt's book
    # stems (urn:nabu:macula-greek:mark ↔ urn:nabu:sblgnt:mark, passage
    # <doc>:<chapter>.<verse>) so the two editions line up verse for verse.
    #
    # == Grain and text
    #
    # One document per NT book (27), one passage per verse (7,939 at the
    # pin — the same verse set sblgnt mints), one token per word row
    # (137,741 at the pin). The verse text is reassembled from the word
    # rows: each word's `text`, then its `after` column (a space, or a
    # punctuation mark — , . · ; ’ — which upstream then follows with a
    # space). Measured against the held sblgnt text at the pin: 7,778 of
    # 7,939 verses are identical once SBLGNT's text-critical sigla
    # (⸀⸁⸂⸃⸄⸅) are set aside and the elision mark's codepoint is folded
    # (MACULA mixes ’ U+2019 with SBLGNT's ʼ U+02BC; kept verbatim). The 161
    # residual verses are upstream's own: 136 differ in punctuation only
    # (the word rows carry no dashes, parentheses, square or double
    # brackets — ⟦ ⟧ around Mark 16:9–20 — and drop a few commas); 25
    # differ in a word form, all accent or capitalization variants
    # (παραβολήν vs SBLGNT παραβολὴν, Δαυὶδ vs Δαυίδ, ἰδὼν vs Ἰδὼν).
    # Canonical means canonical — none is "repaired".
    #
    # == Annotation layers: kept vs declared coarse
    #
    # Each passage's "tokens" carries one hash per word, upstream column
    # names verbatim, empty cells dropped: id (xml:id), form (text), trailer
    # (after, when not a plain space), lemma, normalized, strong, morph
    # (the Robinson-style code, V-IAI-3S), class, type, role, person,
    # number, gender, case, tense, voice, mood, degree, english, mandarin,
    # gloss, frame, subjref, referent. The lemma feeds the lemma index
    # (gold — curated, not automatic); `english` (Cherith) is the
    # registered token-gloss layer (Query::TokenGlosses).
    #
    # Declared coarse, deliberately:
    # - `mandarin` (Cherith Chinese) and `gloss` (Berean interlinear,
    #   contextual — "of [the] genealogy") ride every token but are not
    #   gloss-lane indexed: the token-gloss registry holds one key per
    #   source, and the lexical English gloss is the one a word lookup wants.
    # - person/number/gender/case/tense/voice/mood/degree ride verbatim
    #   (spelled-out English values) but no MorphFacets decoder row reads
    #   them yet, so `--morph` facets do not match this source.
    # - frame / subjref / referent are stored as upstream's xml:id pointers
    #   (resolvable through each token's `id`); no frame or coreference
    #   index is built over them.
    # - the syntax TREES (the lowfat/nodes XML) are not ingested; the TSV's
    #   `role` (clause-level role: s, v, o, p, vc, adv, io…) is the only
    #   syntax carried.
    #
    # EXCLUDED at parse, by rule: `domain` and `ln` — the UBS MARBLE Louw-
    # Nida semantic domains. Upstream's LICENSE.md: "Word sense data from
    # the United Bible Societies MARBLE project. (`@ln`, `@domain`) Used
    # with permission." That permission runs to MACULA, not through CC BY
    # to us, and a column-level caveat cannot ride the source-wide license
    # string honestly everywhere it surfaces — so v1 never lands them
    # (MARBLE_COLUMNS, pinned by test). The canonical copy keeps the file
    # verbatim; only the parse drops the columns.
    #
    # == Delivery grains (upstream serves; this adapter takes the TSV)
    #
    # SBLGNT/tsv (taken: the document grain is the BOOK, cut from the one
    # whole-NT TSV), SBLGNT/lowfat, SBLGNT/nodes and SBLGNT/tei (per-book
    # XML — out of scope by rule; fetch never downloads them, and any that
    # appears under the workdir counts skipped-by-rule in discovery_skips),
    # and the Nestle1904 tree (a different edition — out of scope).
    #
    # Reconciliation plan (first sync): 27 documents = upstream's 27 book
    # codes; Σ tokens = the file's data rows (137,741 at the pin); 7,939
    # passages = sblgnt's verse count.
    #
    # == License
    #
    # CC BY 4.0 (LICENSE.md, "© 2022-2024 by Biblica, Inc"), attribution
    # string verbatim in the manifest; the MARBLE columns' "Used with
    # permission" caveat rides it verbatim too (excluded, see above).
    # Constituents: SBLGNT (CC BY 4.0), Berean Interlinear glosses (public
    # domain since 2023-04-30), Cherith glosses (CC BY 4.0, Andi Wu).
    #
    # == fetch / pin
    #
    # One FileFetch of the TSV from the commit-pinned raw URL into
    # canonical/macula-greek/SBLGNT/tsv/ (upstream's own path), sha256-
    # verified BEFORE the tree mutates (the baxter-sagart choreography).
    # COMMIT is main HEAD at adoption; the TSV blob there (542e91a2) was
    # last regenerated at 076282a3 (2026-04-22), so later tree fixes on
    # main (the OC/O2 distinction, 2026-07-07) are not yet in the TSV.
    # Re-pinning is an owner decision → sync_policy manual.
    class MaculaGreek < Nabu::Adapter
      REPO_URL = "https://github.com/Clear-Bible/macula-greek"
      COMMIT = "8423afe47b9e8f24b7772e808af45c7159a6fe7e" # main @ 2026-07-07
      RELATIVE_DIR = File.join("SBLGNT", "tsv")
      FILENAME = "macula-greek-SBLGNT.tsv"
      TSV_URL = "https://raw.githubusercontent.com/Clear-Bible/macula-greek/" \
                "#{COMMIT}/SBLGNT/tsv/#{FILENAME}".freeze
      TSV_SHA256 = "7f71504fdee8659bdd9f85342e4103d645864c2851b8205915bb298f0c004cc5"

      HEADERS = %w[xml:id ref role class type english mandarin gloss text after lemma normalized
                   strong morph person number gender case tense voice mood degree domain ln
                   frame subjref referent].freeze

      # The UBS MARBLE columns — "Used with permission" only; never parsed.
      MARBLE_COLUMNS = %w[domain ln].freeze

      # Upstream column → token key. text/after map to the house form/
      # trailer keys; everything else keeps upstream's name. ref is the
      # passage's own citation, not repeated per token.
      TOKEN_KEYS = {
        "xml:id" => "id", "text" => "form", "lemma" => "lemma", "normalized" => "normalized",
        "strong" => "strong", "morph" => "morph", "class" => "class", "type" => "type",
        "role" => "role", "person" => "person", "number" => "number", "gender" => "gender",
        "case" => "case", "tense" => "tense", "voice" => "voice", "mood" => "mood",
        "degree" => "degree", "english" => "english", "mandarin" => "mandarin", "gloss" => "gloss",
        "frame" => "frame", "subjref" => "subjref", "referent" => "referent"
      }.freeze

      # USFM book code → sblgnt's file stem (downcased into the urn) and an
      # English title. Order is canonical NT order.
      BOOKS = {
        "MAT" => %w[matt Matthew], "MRK" => %w[mark Mark], "LUK" => %w[luke Luke],
        "JHN" => %w[john John], "ACT" => %w[acts Acts], "ROM" => %w[rom Romans],
        "1CO" => ["1cor", "1 Corinthians"], "2CO" => ["2cor", "2 Corinthians"],
        "GAL" => %w[gal Galatians], "EPH" => %w[eph Ephesians], "PHP" => %w[phil Philippians],
        "COL" => %w[col Colossians], "1TH" => ["1thess", "1 Thessalonians"],
        "2TH" => ["2thess", "2 Thessalonians"], "1TI" => ["1tim", "1 Timothy"],
        "2TI" => ["2tim", "2 Timothy"], "TIT" => %w[titus Titus], "PHM" => %w[phlm Philemon],
        "HEB" => %w[heb Hebrews], "JAS" => %w[jas James], "1PE" => ["1pet", "1 Peter"],
        "2PE" => ["2pet", "2 Peter"], "1JN" => ["1john", "1 John"], "2JN" => ["2john", "2 John"],
        "3JN" => ["3john", "3 John"], "JUD" => %w[jude Jude], "REV" => %w[rev Revelation]
      }.freeze

      REF = /\A(?<book>[0-9A-Z]{3}) (?<chapter>\d+):(?<verse>\d+)!(?<word>\d+)\z/

      MANIFEST = Nabu::SourceManifest.new(
        id: "macula-greek",
        name: "MACULA Greek Linguistic Datasets — SBLGNT word-level TSV (Clear Bible / Biblica)",
        license: "CC BY 4.0 — \"MACULA Greek Linguistic Datasets, available at " \
                 "https://github.com/Clear-Bible/macula-greek/\" (© 2022-2024 Biblica, Inc). " \
                 "Column-level caveat, verbatim from LICENSE.md: \"Word sense data from the United " \
                 "Bible Societies MARBLE project. (`@ln`, `@domain`) Used with permission.\" — those " \
                 "two columns are not ingested.",
        license_class: "attribution",
        upstream_url: REPO_URL,
        parser_family: "macula-tsv"
      )

      def self.manifest
        MANIFEST
      end

      # One HEAD against the pinned raw URL (reachability; the commit-pinned
      # body never drifts — drift means the PIN changed locally).
      def self.remote_probe_strategy = :http_zip

      def self.http_probe_targets
        [Nabu::Adapter::HttpProbeTarget.new(
          label: FILENAME, zip_url: TSV_URL, metadata_url: nil,
          state_subdir: RELATIVE_DIR, state_file: Nabu::FileFetch::STATE_FILE
        )]
      end

      # Each parse streams the one TSV for its own book — pure per ref.
      def self.parallel_parse? = true

      # +tsv_sha256+ exists for the WebMock'd fetch tests — real syncs keep
      # the frozen pin.
      def initialize(tsv_sha256: TSV_SHA256)
        super()
        @tsv_sha256 = tsv_sha256
      end

      # One DocumentRef per known book code present in the TSV, sorted by
      # urn. A workdir without the file yields nothing; the same walk works
      # under the attic.
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        path = tsv_path(workdir) or return
        census(path).fetch(:books).filter_map do |code|
          stem, = BOOKS[code]
          next unless stem

          Nabu::DocumentRef.new(
            source_id: manifest.id, id: "urn:nabu:macula-greek:#{stem}",
            path: path, metadata: { "book" => code, "language" => "grc" }
          )
        end.sort_by(&:id).each(&block)
      end

      # Skipped by rule: upstream's XML grains (lowfat / nodes / TEI) found
      # under the workdir. Unrecognized: a book code outside the NT table.
      def discovery_skips(workdir)
        xml = Dir.glob(File.join(workdir, "**", "*.xml"))
        notes = xml.map do |file|
          "#{relative(file, workdir)}: MACULA XML grain (lowfat/nodes/TEI) — out of scope by rule; " \
            "the word-level TSV is the ingested grain"
        end
        path = tsv_path(workdir)
        unknown = path ? census(path).fetch(:books).reject { |code| BOOKS.key?(code) } : []
        notes += unknown.map { |code| "#{FILENAME}: unknown book code #{code.inspect} — no NT book mapped" }
        Nabu::Adapter::DiscoverySkips.new(skipped_by_rule: xml.size, unrecognized: unknown.size, notes: notes)
      end

      def parse(document_ref)
        code = document_ref.metadata.fetch("book")
        stem, title = BOOKS.fetch(code)
        document = Nabu::Document.new(
          urn: document_ref.id, language: "grc", title: "#{title} (MACULA Greek)",
          canonical_path: document_ref.path, metadata: { "book" => code }
        )
        verses(document_ref.path, code).each do |(chapter, verse), words|
          append_verse(document, code, chapter, verse, words)
        end
        raise Nabu::ParseError, "#{document_ref.path}: no word rows for #{code} (#{stem})" if document.empty?

        document
      rescue Nabu::ValidationError, Normalize::EncodingError => e
        raise Nabu::ParseError, "macula-greek: #{document_ref.id}: #{e.message}"
      end

      # FileFetch phases run separately so the sha pin verifies BEFORE the
      # tree mutates.
      def fetch(workdir, progress: nil, force: false)
        fetch = FileFetch.new(
          url: TSV_URL, dir: File.join(workdir, RELATIVE_DIR), filename: FILENAME,
          attic_dir: File.join(workdir, ATTIC_DIRNAME, RELATIVE_DIR), progress: progress
        )
        fetch.prepare!
        verify_pin!(fetch)
        guard_mass_deletion!(workdir, fetch.doomed_paths, force: force)
        fetch.complete!
        FetchReport.new(sha: fetch.sha, fetched_at: Time.now, notes: attic_notes(fetch.atticked))
      rescue FileFetch::Error => e
        raise Nabu::FetchError, "macula-greek fetch failed into #{workdir}: #{e.message}"
      end

      private

      def tsv_path(workdir)
        path = File.join(workdir, RELATIVE_DIR, FILENAME)
        File.file?(path) ? File.expand_path(path) : nil
      end

      def relative(file, workdir)
        File.expand_path(file).delete_prefix("#{File.expand_path(workdir)}#{File::SEPARATOR}")
      end

      # The book codes in first-appearance order (one cheap pass, cached per
      # instance and path — discover and discovery_skips share it).
      def census(path)
        @census ||= {}
        @census[path] ||= begin
          books = []
          each_line(path, check_header: false) do |line|
            code = line[/\A[^\t]*\t([^ \t]+) /, 1]
            books << code if code && books.last != code && !books.include?(code)
          end
          { books: books }
        end
      end

      # The data lines after the header. +check_header+ refuses a drifted
      # header (parse — the document quarantines); discovery's cheap book
      # census reads only the ref column and leaves the verdict to parse.
      def each_line(path, check_header: true)
        SourceRead.utf8_lines(path, label: "macula-greek").each_with_index do |line, index|
          if index.zero?
            header_check!(line.chomp, path) if check_header
          else
            yield line
          end
        end
      end

      def header_check!(header, path)
        columns = header.split("\t", -1)
        return if columns == HEADERS

        missing = HEADERS - columns
        raise Nabu::ParseError,
              "#{path}: header drifted from the pinned 27 columns " \
              "(missing #{missing.join(', ')}; got #{columns.size} columns) — review upstream and re-pin"
      end

      # [[chapter, verse], [row hashes]] in file order for +code+.
      def verses(path, code)
        prefix = "\t#{code} "
        grouped = {}
        each_line(path) do |line|
          next unless line.include?(prefix)

          row = HEADERS.zip(line.chomp.split("\t", -1)).to_h
          match = REF.match(row["ref"].to_s) or
            raise(Nabu::ParseError, "#{path}: unreadable ref #{row['ref'].inspect} (#{row['xml:id']})")
          next unless match[:book] == code

          (grouped[[match[:chapter].to_i, match[:verse].to_i]] ||= []) << row
        end
        grouped
      end

      def append_verse(document, code, chapter, verse, rows)
        document << Nabu::Passage.new(
          urn: "#{document.urn}:#{chapter}.#{verse}",
          language: "grc",
          text: Normalize.nfc(verse_text(rows)),
          sequence: document.size,
          annotations: { "citation" => "#{code} #{chapter}:#{verse}", "tokens" => rows.map { |row| token(row) } }
        )
      end

      # Each word, then its `after`: a whitespace separator stands as is; a
      # punctuation mark is followed by a space (upstream's convention — the
      # column holds the mark alone); an empty cell joins with nothing.
      def verse_text(rows)
        rows.map do |row|
          after = row["after"].to_s
          trailer = after.empty? || after.strip.empty? ? after : "#{after} "
          "#{row['text']}#{trailer}"
        end.join.strip
      end

      def token(row)
        token = TOKEN_KEYS.each_with_object({}) do |(column, key), hash|
          value = row[column].to_s.strip
          hash[key] = Normalize.nfc(value) unless value.empty?
        end
        after = row["after"].to_s
        token["trailer"] = Normalize.nfc(after) unless after.strip.empty?
        token
      end

      def verify_pin!(fetch)
        return if fetch.sha == @tsv_sha256

        raise Nabu::FetchError,
              "macula-greek: #{FILENAME} drifted — fetched sha256 #{fetch.sha} != pinned " \
              "#{@tsv_sha256} (commit #{COMMIT[0, 12]}); review upstream and re-pin (owner decision)"
      end
    end
  end
end

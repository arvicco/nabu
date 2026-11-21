# frozen_string_literal: true

require "uri"
require_relative "stepbible_tagnt_parser"
require_relative "../file_fetch"

module Nabu
  module Adapters
    # The TAGNT adapter: the Translators Amalgamated Greek New Testament
    # from STEPBible-Data (github.com/STEPBible/STEPBible-Data, directory
    # "Translators Amalgamated OT+NT"; Tyndale House Cambridge, curated by
    # STEPBible.org) — every word of the NA27/NA28, Tyndale House GNT, SBL,
    # Tregelles, Byzantine, Westcott-Hort and TR editions in one
    # word-per-row amalgam, each word carrying the editions that read it,
    # its word-type class (NKO / N(K)O / K / k / …), the meaning and
    # spelling variants with their editions, Strong's number, morphology
    # and dictionary form. The library's cross-edition NT apparatus, beside
    # sblgnt's single-edition text (distinct witness, never a dedupe).
    #
    # == Delivery grains (enumerated at fixture time)
    #
    # The upstream directory serves: TAGNT in two files (Mat-Jhn, Act-Rev —
    # split only for GitHub's file-size limit) — ACCEPTED, one document per
    # book; TAHOT (the Hebrew OT amalgam, four files) and the "OLD format
    # TOTHT" subdirectory (four older Hebrew files) — REJECTED by rule (OT
    # Hebrew, out of this source's scope; discovery_skips counts any that
    # appear in the tree). #fetch only ever downloads the two TAGNT files.
    #
    # == Identity (FROZEN once used)
    #
    # Document urn = urn:nabu:stepbible-tagnt:<sblgnt's book stem> (matt,
    # mark, … 1cor … phlm … 3john, jude, rev) so the two Greek NT witnesses
    # share book tails; passage urn <doc-urn>:<C>.<V> in upstream's NRSV
    # versification (StepbibleTagntParser). Titles are the English book
    # names (upstream gives none).
    #
    # == Reconciliation (pinned commit 5de0a47f, censused 2026-11-18)
    #
    # Upstream's header claims 142,036 words (133,608 + 3,084 + 4,164 + 896
    # + 284 across its five word-type classes); the pinned files carry
    # 142,095 word rows in 7,958 NRSV verses over 27 books. The 59-row
    # residue is upstream's own: its summary counts exclude spelling- and
    # word-order-only differences ("recorded below but … not counted in
    # these totals"). Expected first sync: 27 documents, 7,958 passages.
    #
    # == License
    #
    # CC BY 4.0 → license_class "attribution": repo README ("STEPBible
    # Data Repository CC BY 4.0"; credit "STEP Bible" linked to
    # www.STEPBible.org) and every file header ("Data created by
    # www.STEPBible.org based on work at Tyndale House Cambridge (CC BY
    # 4.0)"). The header also asks: "Please do not post copies of this data
    # file elsewhere, so that this remains the single up-to-date source" —
    # a courtesy request about reposting the FILES, honored: the library
    # serves passages, never the files.
    #
    # == fetch
    #
    # Two FileFetches of the PINNED commit's raw URLs, each into its own
    # subdirectory (FileFetch treats every sibling in its dir as doomed),
    # both sha256-verified BEFORE either tree mutates (the larth-etp
    # choreography at two-artifact size). Upstream pushes most weeks →
    # sync_policy manual; re-pinning is a deliberate edit here.
    class StepbibleTagnt < Nabu::Adapter
      REPO_URL = "https://github.com/STEPBible/STEPBible-Data"
      COMMIT = "5de0a47f35f0fc13dfe1430d104e5db8a4285f9c" # master @ 2026-11-02 ("Licence summary clarified")
      UPSTREAM_DIR = "Translators Amalgamated OT+NT"

      Part = Data.define(:dir, :filename, :sha256) do
        def url
          path = [UPSTREAM_DIR, filename].map { |seg| URI.encode_www_form_component(seg).gsub("+", "%20") }
          "https://raw.githubusercontent.com/STEPBible/STEPBible-Data/#{COMMIT}/#{path.join('/')}"
        end
      end

      PARTS = [
        Part.new(dir: "Mat-Jhn",
                 filename: "TAGNT Mat-Jhn - Translators Amalgamated Greek NT - STEPBible.org CC-BY.txt",
                 sha256: "d4c0c820fdf9f2b450c9f96ce6103d6875028affd2e44094d753f1329ca1fd85"),
        Part.new(dir: "Act-Rev",
                 filename: "TAGNT Act-Rev - Translators Amalgamated Greek NT - STEPBible.org CC-BY.txt",
                 sha256: "122040eeeaeba50d6abbf67b39cacaff687211bda69b080e5d53927c830d9968")
      ].freeze

      ACCEPTED_PREFIX = "TAGNT "
      # The OT Hebrew grains of the same upstream directory (TAHOT, and
      # the OLD-format TOTHT) — out of scope by rule.
      REJECTED_PREFIXES = ["TAHOT ", "TOTHT "].freeze

      # Upstream book code => [sblgnt's urn tail, English title], canonical order.
      BOOKS = {
        "Mat" => %w[matt Matthew], "Mrk" => %w[mark Mark], "Luk" => %w[luke Luke],
        "Jhn" => %w[john John], "Act" => %w[acts Acts], "Rom" => %w[rom Romans],
        "1Co" => ["1cor", "1 Corinthians"], "2Co" => ["2cor", "2 Corinthians"],
        "Gal" => %w[gal Galatians], "Eph" => %w[eph Ephesians], "Php" => %w[phil Philippians],
        "Col" => %w[col Colossians], "1Th" => ["1thess", "1 Thessalonians"],
        "2Th" => ["2thess", "2 Thessalonians"], "1Ti" => ["1tim", "1 Timothy"],
        "2Ti" => ["2tim", "2 Timothy"], "Tit" => %w[titus Titus], "Phm" => %w[phlm Philemon],
        "Heb" => %w[heb Hebrews], "Jas" => %w[jas James], "1Pe" => ["1pet", "1 Peter"],
        "2Pe" => ["2pet", "2 Peter"], "1Jn" => ["1john", "1 John"], "2Jn" => ["2john", "2 John"],
        "3Jn" => ["3john", "3 John"], "Jud" => %w[jude Jude], "Rev" => %w[rev Revelation]
      }.freeze
      BOOK_ORDER = BOOKS.keys.each_with_index.to_h.freeze

      MANIFEST = Nabu::SourceManifest.new(
        id: "stepbible-tagnt",
        name: "TAGNT — Translators Amalgamated Greek New Testament (STEPBible / Tyndale House)",
        license: "CC BY 4.0 (STEPBible-Data README + every file header; credit: STEP Bible, " \
                 "www.STEPBible.org, based on work at Tyndale House Cambridge)",
        license_class: "attribution",
        upstream_url: REPO_URL,
        parser_family: "tagnt-tsv"
      )

      def self.manifest
        MANIFEST
      end

      # #parse is pure per ref: it re-reads the one file it names and keeps
      # no state across parses — safe for rebuild's forked workers.
      def self.parallel_parse? = true

      # One HEAD per pinned raw URL (reachability; a commit-pinned body
      # never drifts — drift means the PIN changed locally).
      def self.remote_probe_strategy = :http_zip

      def self.http_probe_targets
        PARTS.map do |part|
          Nabu::Adapter::HttpProbeTarget.new(
            label: part.filename, zip_url: part.url, metadata_url: nil,
            state_subdir: part.dir, state_file: Nabu::FileFetch::STATE_FILE
          )
        end
      end

      # +pins+ (filename => sha256) exists for the WebMock'd fetch tests —
      # real syncs keep the frozen pins.
      def initialize(pins: PARTS.to_h { |p| [p.filename, p.sha256] })
        super()
        @pins = pins
      end

      # One DocumentRef per book in each TAGNT file, in canonical order. A
      # workdir without the files yields nothing; the same walk works under
      # the attic.
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        refs = tagnt_files(workdir).flat_map do |path|
          parser.books(path).filter_map do |book|
            tail, title = BOOKS[book]
            next unless tail # counted unrecognized by discovery_skips

            Nabu::DocumentRef.new(
              source_id: manifest.id,
              id: "urn:nabu:stepbible-tagnt:#{tail}",
              path: File.expand_path(path),
              metadata: { "book" => book, "title" => title, "language" => "grc" }
            )
          end
        end
        refs.sort_by { |ref| BOOK_ORDER.fetch(ref.metadata["book"]) }.each(&block)
      end

      # The OT Hebrew files are skipped by rule; any other .txt in the tree,
      # or a book code outside the 27, is unrecognized.
      def discovery_skips(workdir)
        skipped = 0
        unrecognized = 0
        notes = []
        text_files(workdir).each do |path|
          name = File.basename(path)
          if name.start_with?(ACCEPTED_PREFIX)
            unknown = parser.books(path) - BOOKS.keys
            unrecognized += unknown.size
            notes.concat(unknown.map { |book| "#{name}: unknown book code #{book.inspect}" })
          elsif REJECTED_PREFIXES.any? { |prefix| name.start_with?(prefix) }
            skipped += 1
            notes << "#{name}: skipped by rule — OT Hebrew grain (TAHOT/TOTHT), outside the Greek NT scope"
          else
            unrecognized += 1
            notes << "#{name}: unrecognized .txt in the TAGNT tree"
          end
        end
        Nabu::Adapter::DiscoverySkips.new(skipped_by_rule: skipped, unrecognized: unrecognized, notes: notes)
      end

      def parse(document_ref)
        parser.parse(document_ref.path,
                     book: document_ref.metadata.fetch("book"),
                     urn: document_ref.id,
                     title: document_ref.metadata["title"],
                     language: "grc")
      end

      # Both files prepare (download + pin check) before either is written.
      def fetch(workdir, progress: nil, force: false)
        fetches = PARTS.map do |part|
          FileFetch.new(url: part.url, dir: File.join(workdir, part.dir), filename: part.filename,
                        attic_dir: File.join(workdir, ATTIC_DIRNAME, part.dir), progress: progress)
        end
        fetches.each(&:prepare!)
        PARTS.zip(fetches).each { |part, fetch| verify_pin!(part, fetch) }
        guard_mass_deletion!(workdir, fetches.flat_map(&:doomed_paths), force: force)
        fetches.each(&:complete!)
        FetchReport.new(sha: COMMIT, fetched_at: Time.now, notes: attic_notes(fetches.flat_map(&:atticked)))
      rescue FileFetch::Error => e
        raise Nabu::FetchError, "stepbible-tagnt fetch failed into #{workdir}: #{e.message}"
      end

      private

      def parser
        @parser ||= StepbibleTagntParser.new
      end

      def text_files(workdir)
        Dir.glob(File.join(workdir, "**", "*.txt")) # sorted by default (Ruby >= 3.0)
      end

      def tagnt_files(workdir)
        text_files(workdir).select { |path| File.basename(path).start_with?(ACCEPTED_PREFIX) }
      end

      # A 304 re-serves the stored pin (FileFetch's state file), so the same
      # equality holds for both answers.
      def verify_pin!(part, fetch)
        expected = @pins.fetch(part.filename)
        return if fetch.sha == expected

        raise Nabu::FetchError,
              "stepbible-tagnt: #{part.filename} drifted — fetched sha256 #{fetch.sha} != pinned " \
              "#{expected} (commit #{COMMIT[0, 12]}); review upstream and re-pin"
      end
    end
  end
end

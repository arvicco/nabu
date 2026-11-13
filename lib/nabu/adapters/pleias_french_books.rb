# frozen_string_literal: true

require "fileutils"
require "json"
require "zlib"

require_relative "../zip_fetch"
require_relative "../paced_crawl"
require_relative "../pleias_shard_fetch"
require_relative "../normalize"
require_relative "../version"
require_relative "source_read"
require_relative "pleias_title_genre"

module Nabu
  module Adapters
    # pleias-french-books: French public-domain monographs digitized by
    # Gallica (Bibliothèque nationale de France), re-hosted as OCR text on
    # Hugging Face by PleIAs — PleIAs/French-PD-Books ("French-Public
    # Domain-Book", compiled by Pierre-Carl Langlais on the corpus Benoît
    # de Courson and Benjamin Azoulay curated for Gallicagram, with
    # OpenLLMFrance). The French-print opening of the library (route ruled
    # 2026-11-12: the BnF Datalab ask pending, this re-host the ratified
    # fallback, admitted WITH CREDIT to Gallica/BnF and PleIAs). THIS era
    # holds the PRE-1700 CONE only (CONE below).
    #
    # == The census (HF API + parquet footers, 2026-11-13)
    #
    # Revision 21abfb3f646a0f1846175c63709913a51abc9bcb (main; last
    # modified 2024-03-19). 147 files: README.md, .gitattributes and 145
    # parquet shards gallica_mono_1 … gallica_mono_145.parquet, 336–474 MB
    # each, 60,528,820,259 bytes in all (LFS; the tree API gives each
    # shard's sha256 — the fetch's per-shard pin). Every shard is
    # fastparquet 2023.10.1 output: ONE row group of ~2,000 books "selected
    # at random" (the card), nine flat OPTIONAL columns, PLAIN, SNAPPY,
    # v1 data pages — file_id, ocr, title, date, author (BYTE_ARRAY),
    # page_count, word_count, character_count (INT64), complete_text
    # (BYTE_ARRAY: the whole book's OCR; the metadata columns sit in the
    # first ~230 KB, the text column is the rest, in pages of up to
    # ~526 MB uncompressed). 289,577 rows over the 145 footers (the card:
    # "289,000 books (16,407,292,362 words)"); 289,577 distinct file_ids.
    #
    # Columns as upstream fills them: file_id is the Gallica ark name
    # (bpt6k…; ark:/12148/<file_id>); ocr is Gallica's OCR quality
    # percentage as a string ("96"); date is the catalogue's imprint year
    # (262,979 "YYYY", 26,369 "YYYY-YYYY", the rest open or truncated
    # ranges: "1863-????", "1843-18..", "1607-16", "1847-."); author is the
    # BnF heading ("Louis XIII (1601-1643 ; roi de France)") or the string
    # "None" (Python's None stringified — 1,295 cone books); title carries
    # XML-escaped entities (&amp;) as do the texts. page_count counts
    # Gallica's VIEWS (covers, blanks and plates included), not text pages.
    # No language, place, publisher or genre column exists.
    #
    # == License (verbatim, the dataset card at the pinned revision)
    #
    # The card's YAML carries NO license field (the datasets-server info
    # answers "license": ""). The card prose, verbatim: "The entire
    # collection is in the public domain everywhere. This means that the
    # patrimonial rights of each individual or collective rightholders
    # have expired. The French National Library claims additional rights
    # in its terms of use and restricts commercial use: "La réutilisation
    # commerciale de ces contenus est payante et fait l'objet d'une
    # licence. …" … Since 2019, the EU Copyright Directive states that …
    # any material resulting from an act of reproduction of that work is
    # not subject to copyright or related rights … (art. 14)". The texts
    # are pre-1700 prints, public domain; the BnF's commercial-reuse claim
    # over reproductions is the modern pretension the house rule declines
    # to be fussy about (owner 2026-11-03), and the re-hoster states the
    # whole set PD. Class open, credit Gallica/BnF and PleIAs.
    #
    # == The cone (the first era) and its census
    #
    # The shards are a RANDOM split, so every date cone touches every
    # shard: a cone is fetched by streaming EVERY shard (the whole 60.5 GB
    # crosses the wire once), keeping only the cone's texts on disk. The
    # catalogue columns of every row are kept (shards/<n>.jsonl), so the
    # cone is re-derivable at discovery and the rejected rows are COUNTED.
    #
    # CONE: the imprint date's envelope closes at or before 1699. Over the
    # 289,577 rows: 6,477 books in the cone (6,204 single years, 273
    # closed ranges; 166 printed before 1600, 5 straddling 1600) —
    # 1,823,065,683 characters / 300,483,806 words of OCR; 25–64 per
    # shard. Rejected by rule (discovery_skips): 282,992 printed after
    # 1699; 92 whose range opens before 1700 and closes after it (serials,
    # multi-volume sets: "1633-1742", "1667-1793"); 16 reversed ranges
    # ("1890-1889"). 6,477 + 282,992 + 92 + 16 = 289,577. Why 1699: the
    # cone holds the whole Middle French print era and the grand siècle
    # (the registry's frm [1400, 1600] and fr:cls [1600, 1789] up to
    # Louis XIV's last decade) at a phase-sized document count, where
    # ≤1749 doubles it (13,250) and ≤1799 is 35,110 books / 11.1 G
    # characters. Widening is one CONE line — but the texts are re-streamed
    # (every shard's stamp names the cone it was cut for, so a new cone
    # re-queues the whole rail by itself).
    #
    # Upstream's delivery grains: the shard (parquet file) → the row (one
    # book: catalogue + whole OCR text). The adapter takes the BOOK as the
    # document. The rejected grains, each pinned in the fixture tree and
    # counted, never silently dropped: an out-of-cone row (catalogue line
    # only, skipped by rule with its reason); the other repo files
    # (README.md, the dataset card, is kept as the dataset-card.md sidecar;
    # .gitattributes is ignored).
    #
    # == The passage grain: upstream's page breaks
    #
    # The OCR export joins pages with a blank line — the exact separator
    # "\n \n" (a line holding one space). Read against the fixtures and
    # the 100-book sample: each segment ends at a catchword or signature
    # and the next opens with the following page's number ("…Son \n \n
    # ri \n5 Son Altesse"), so the segment IS the printed page. Segment
    # count ≠ page_count (Gallica's views include blanks and plates), so
    # the passage is cited by its SEGMENT ordinal (…:4 = the 4th segment;
    # blank segments mint nothing and keep their ordinal). A segment over
    # MAX_PASSAGE_CHARS (none in the census sample) splits at line
    # boundaries into …:4.1, …:4.2. Within a page the OCR's lines keep
    # their breaks; trailing spaces and edge blank lines are trimmed.
    #
    # == OCR, not an edition (declared)
    #
    # Gallica's uncorrected OCR of early-modern type (long s read as f,
    # u/v and i/j as printed, tildes, ligatures, running heads, catchwords,
    # Gallica's "[texte_manquant]" gap marker kept verbatim). text_nature
    # "machine-ocr"; nothing is corrected (canonical means canonical).
    # One DECODING step: upstream's export left the five XML entities
    # escaped (&amp; &lt; &gt; &quot; &apos;) in titles and texts; they
    # are decoded to their characters at parse — the bytes' meaning, not
    # a correction. Gallica's per-book OCR quality rides as ocr_quality.
    #
    # == Axes (aggressive mining)
    #
    # - date — the imprint year envelope (DateEnvelope), class edition:
    #   the PRINT year. The lect inference law keeps edition-class dates
    #   out of the date-band hull, so the books stay bare fra (posture).
    # - place — none: no column carries the imprint place; it lives only in
    #   the OCR'd title page ("A PARIS. Par ANTOINE ESTIENE"). Declared
    #   unplaced; the BnF catalogue record behind each ark carries it (a
    #   metadata-expansion lane, not this adapter).
    # - kind — the title's form noun (PleiasTitleGenre; no genre column),
    #   folded in config/kind_map.yml.
    # - author — the BnF heading verbatim (the "None" string read as
    #   absent) → the author facet.
    # - language — fra for every book: the card's own claim ("language:
    #   fr", "French monographies"); no language column exists. Latin or
    #   bilingual prints Gallica catalogued among them stay fra until a
    #   per-book language lane exists (declared, not checked).
    class PleiasFrenchBooks < Nabu::Adapter
      SLUG = "pleias-french-books"
      URN_PREFIX = "urn:nabu:pleias-french-books:"
      REPO = "PleIAs/French-PD-Books"
      REVISION = "21abfb3f646a0f1846175c63709913a51abc9bcb"
      API_URL = "https://huggingface.co/api/datasets/#{REPO}".freeze
      TREE_URL = "#{API_URL}/tree/#{REVISION}".freeze
      RESOLVE_URL = "https://huggingface.co/datasets/#{REPO}/resolve/#{REVISION}/%s".freeze
      GALLICA_URL = "https://gallica.bnf.fr/ark:/12148/%s"
      LANGUAGE = "fra"

      # The era's cone: its id is stamped on every shard cut for it.
      Cone = Data.define(:id, :ceiling)
      CONE = Cone.new(id: "imprint-envelope<=1699", ceiling: 1699)

      SHARD_FILE = "gallica_mono_%s.parquet"
      TREE_FILE = Nabu::PleiasShardFetch::TREE_FILE
      CARD_TARGET = Nabu::PleiasShardFetch::CARD_TARGET
      SHARDS_DIR = Nabu::PleiasShardFetch::SHARDS_DIR
      BOOKS_DIR = Nabu::PleiasShardFetch::BOOKS_DIR
      STAGING_DIR = Nabu::PleiasShardFetch::STAGING_DIR
      LEDGER_FILE = ".pleias-crawl.json"
      PAGE_BREAK = "\n \n"
      # const: a passage-size guard, not a corpus claim (the census
      # sample's longest page segment is ~2.4k characters)
      MAX_PASSAGE_CHARS = 20_000
      ENTITIES = { "&amp;" => "&", "&lt;" => "<", "&gt;" => ">", "&quot;" => "\"", "&apos;" => "'" }.freeze
      ENTITY = Regexp.union(ENTITIES.keys)

      # const: crawl politeness pause between shard GETs, not a corpus claim
      DELAY = 1.0
      # Shards per sync. A shard is ~417 MB on the wire plus ~20 s of
      # pure-Ruby snappy (YJIT; ~55 s without) for its ~800 MB of text:
      # ~30–60 s a shard on a fast line, so a slice of 25 is ~15–25 min
      # (an ESTIMATE until the first live slice measures it). The 145
      # shards take six slices.
      SLICE = 25
      TIMEOUT_ATTEMPTS = 3
      TIMEOUT_BACKOFF = 5.0
      STUCK = "timeout-stuck"

      # The shard lane (architecture §19): the universe is the pinned
      # revision's shard numbers, held = the shard's stamp names this
      # revision and this cone. Six slices finish the cone, so the
      # declared schedule spends all six in one phase. Basis: cone
      # arithmetic (145 shards / 25 a slice = 6) — a cap, never a quota.
      SHARD_CRAWL = Nabu::PacedCrawl::Spec.new(
        name: "shards", ledger_file: LEDGER_FILE,
        classes: { denied: "denied", empty: "empty", timeout: STUCK },
        delay: DELAY, slice: SLICE, timeout_attempts: TIMEOUT_ATTEMPTS, timeout_backoff: TIMEOUT_BACKOFF,
        schedule: Nabu::PacedCrawl::Schedule.new(cadence: :per_phase, slices_per_phase: 6, stop_after_zero_slices: 3)
      )

      OCR_NOTE = "Uncorrected Gallica OCR of the BnF's scans, re-hosted by PleIAs (French-PD-Books): long s, " \
                 "u/v, ligatures, running heads and catchwords ride as recognized; Gallica's [texte_manquant] " \
                 "gap marker kept; the book's Gallica OCR quality rides as ocr_quality."

      MANIFEST = Nabu::SourceManifest.new(
        id: SLUG,
        name: "French Public Domain Books — Gallica OCR via PleIAs (pre-1700 cone)",
        license: "Public domain (dataset card, verbatim: \"The entire collection is in the public domain " \
                 "everywhere\"; the card YAML carries no license field). The BnF's terms claim a fee for " \
                 "commercial reuse of Gallica reproductions; the card cites EU Directive 2019/790 art. 14 " \
                 "against such claims. Pre-1700 prints; the text is uncorrected OCR, not an edition",
        license_class: "open",
        upstream_url: "https://huggingface.co/datasets/#{REPO}",
        parser_family: "pleias-parquet",
        credit: "Gallica / Bibliothèque nationale de France (digitization and OCR); PleIAs, French-PD-Books " \
                "(huggingface.co/datasets/PleIAs/French-PD-Books, compiled by Pierre-Carl Langlais)"
      )

      def self.manifest = MANIFEST

      # Each parse opens its own book file — no state crosses refs.
      def self.parallel_parse? = true

      # Everything under the workdir is fetch-made: the pinned file
      # listing, the card, the per-shard catalogues + stamps, the cone's
      # book files.
      def self.materialized_paths = [TREE_FILE, CARD_TARGET, SHARDS_DIR, BOOKS_DIR]

      def self.remote_probe_strategy = :http_zip

      def self.http_probe_targets
        [Nabu::Adapter::HttpProbeTarget.new(
          label: "French-PD-Books dataset API", zip_url: API_URL, metadata_url: nil,
          state_subdir: "", liveness_only: true
        )]
      end

      def initialize(delay: DELAY, slice: SLICE, http: Nabu::ZipFetch.default_http,
                     timeout_backoff: TIMEOUT_BACKOFF, cone: CONE, jit: true)
        super()
        @jit = jit
        @delay = delay
        @slice = slice
        @http = http
        @timeout_backoff = timeout_backoff
        @cone = cone
        @shards = {}
      end

      # -- fetch -------------------------------------------------------------

      # One slice of the shard rail: the pinned listing and the card
      # first, then up to SLICE shards streamed, pinned, cut to the cone
      # (each staged shard is deleted the moment it is cut; the staging
      # dir goes with the slice). +force+ is part of the fetch interface;
      # nothing here ever deletes a held book (a cone change re-cuts
      # shards in place).
      def fetch(workdir, progress: nil, force: false) # rubocop:disable Lint/UnusedMethodArgument
        FileUtils.mkdir_p(workdir)
        enable_yjit!
        fetcher = shards(workdir)
        drift = fetcher.revision_drift
        fetcher.refresh_listing!
        lines = shard_crawl(workdir, progress: progress).slice!.lines
        lines.each { |line| progress&.call("#{line}\n") }
        Nabu::FetchReport.new(sha: fetcher.crawl_sha, fetched_at: Time.now, notes: [drift, *lines].compact.join("; "))
      ensure
        shards(workdir).clear_staging!
      end

      # The chain runner's seam (rake crawl:chain): the one paced lane.
      def paced_crawls(workdir, progress: nil)
        { SHARD_CRAWL.name => shard_crawl(workdir, progress: progress) }
      end

      # The shard lane's engine over +workdir+ (SHARD_CRAWL retuned by
      # this instance's knobs). Public so an offline surface can #diagnose
      # the crawl without crawling.
      def shard_crawl(workdir, progress: nil)
        Nabu::PacedCrawl::Engine.new(
          spec: SHARD_CRAWL.with(delay: @delay, slice: @slice, timeout_backoff: @timeout_backoff),
          dir: workdir, progress: progress,
          universe: -> { shards(workdir).tree.keys },
          held: ->(id) { shards(workdir).held?(id) },
          fetch_one: ->(id) { shards(workdir).fetch_shard!(id) }
        )
      end

      # -- discover ----------------------------------------------------------

      # One ref per cone row of every held shard, in shard then row order,
      # whose book file is on disk. A pre-fetch workdir yields nothing.
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        each_catalogue_row(workdir) do |shard, line|
          next unless cone_verdict(line) == :cone

          path = shards(workdir).book_path(line.fetch("file_id"))
          next unless File.file?(path)

          block.call(Nabu::DocumentRef.new(
                       source_id: SLUG, id: "#{URN_PREFIX}#{line.fetch('file_id')}", path: File.expand_path(path),
                       metadata: { "shard" => shard, "index" => line.fetch("index") }
                     ))
        end
      end

      SKIP_NOTES = {
        after: "printed after %<ceiling>d (outside the cone)",
        straddles: "date range opens before %<next>d and closes after it (serials, multi-volume sets)",
        open: "date range opens before %<next>d but leaves its end open",
        reversed: "reversed date range (upstream dating defect)",
        undated: "no readable imprint year"
      }.freeze

      # Every held catalogue row outside the cone is skipped BY RULE with
      # its reason; a cone row whose book file is missing, and a book file
      # no held catalogue names as a cone row, are unrecognized.
      def discovery_skips(workdir)
        tally = Hash.new(0)
        missing = []
        named = Set.new
        each_catalogue_row(workdir) do |shard, line|
          verdict = cone_verdict(line)
          if verdict == :cone
            named << line.fetch("file_id")
            missing << "#{SHARDS_DIR}/#{shard}: cone row #{line['file_id']} has no book file" unless
              File.file?(shards(workdir).book_path(line.fetch("file_id")))
          else
            tally[verdict] += 1
          end
        end
        strays = stray_books(workdir, named)
        notes = tally.map { |reason, count| "#{count} row(s): #{format(SKIP_NOTES.fetch(reason), cone_format)}" }
        notes.concat(missing).concat(strays.map { |name| "#{BOOKS_DIR}/#{name}: no held catalogue names it" })
        Nabu::Adapter::DiscoverySkips.new(skipped_by_rule: tally.values.sum,
                                          unrecognized: missing.size + strays.size, notes: notes)
      end

      # -- parse -------------------------------------------------------------

      def parse(document_ref)
        book = read_book(document_ref.path)
        row = book.fetch("row")
        file_id = document_ref.id.delete_prefix(URN_PREFIX)
        raise ParseError, "#{document_ref.path}: the row is #{row['file_id']}, not #{file_id}" unless
          row["file_id"] == file_id

        title = text(row["title"])
        document = Nabu::Document.new(
          urn: document_ref.id, language: LANGUAGE, title: title, canonical_path: document_ref.path,
          metadata: book_metadata(row, book, title)
        )
        append_pages(document, row["complete_text"].to_s)
        raise ParseError, "#{document_ref.path}: no page carries OCR text" if document.empty?

        document
      rescue Nabu::ValidationError, KeyError => e
        raise ParseError, "#{document_ref.path}: #{e.message}"
      end

      # The imprint date as an envelope: [not_before, not_after] (either
      # nil when upstream leaves it open), or nil when unreadable.
      #   "1626" → [1626, 1626]; "1633-1742" → [1633, 1742];
      #   "1607-16" → [1607, 1616] (the abbreviated close, same century);
      #   "1843-18.." → [1843, 1899]; "1863-????" / "1847-." → [1863, nil].
      def self.date_envelope(raw)
        value = raw.to_s.strip
        case value
        when /\A(\d{4})\z/ then [Integer(::Regexp.last_match(1), 10)] * 2
        when /\A(\d{4})-(\d{4})\z/ then [Integer(::Regexp.last_match(1), 10), Integer(::Regexp.last_match(2), 10)]
        when /\A(\d{4})-(\d{2})\z/ then abbreviated_close(Integer(::Regexp.last_match(1), 10),
                                                          Integer(::Regexp.last_match(2), 10))
        when /\A(\d{4})-(\d{1,3})\.+\z/
          [Integer(::Regexp.last_match(1), 10), Integer(::Regexp.last_match(2).ljust(4, "9"), 10)]
        when /\A(\d{4})-/ then [Integer(::Regexp.last_match(1), 10), nil]
        end
      end

      def self.abbreviated_close(year, tail)
        tail >= year % 100 ? [year, (year / 100 * 100) + tail] : [year, nil]
      end
      private_class_method :abbreviated_close

      private

      def cone_format = { ceiling: @cone.ceiling, next: @cone.ceiling + 1 }

      # :cone, or the rule that rejects the row.
      def cone_verdict(line)
        not_before, not_after = self.class.date_envelope(line["date"])
        return :undated if not_before.nil?
        return (not_before > @cone.ceiling ? :after : :open) if not_after.nil?
        return :reversed if not_after < not_before
        return :cone if not_after <= @cone.ceiling

        not_before > @cone.ceiling ? :after : :straddles
      end

      # -- fetch internals ---------------------------------------------------

      # A process-wide JIT for the pure-Ruby snappy loop (3× here; a no-op
      # where YJIT is absent or already on; the +jit+ knob false keeps a
      # test process's JIT state untouched).
      def enable_yjit!
        return unless @jit

        RubyVM::YJIT.enable if defined?(RubyVM::YJIT.enable) && !RubyVM::YJIT.enabled?
      end

      # The workdir's shard fetcher (Nabu::PleiasShardFetch): keeps the
      # rows this instance's cone accepts.
      def shards(workdir)
        @shards[workdir] ||= Nabu::PleiasShardFetch.new(
          workdir: workdir, repo: REPO, revision: REVISION, cone_id: @cone.id, http: @http, label: SLUG,
          keep: ->(line) { cone_verdict(line) == :cone }
        )
      end

      # -- discovery internals -----------------------------------------------

      # Yield [shard id, catalogue line] for every held shard, in shard
      # then row order.
      def each_catalogue_row(workdir)
        fetcher = shards(workdir)
        fetcher.tree.each_key do |id|
          next unless fetcher.held?(id)

          SourceRead.utf8_lines(fetcher.catalogue_path(id), label: "#{SLUG} catalogue") do |raw|
            yield id, JSON.parse(raw) unless raw.strip.empty?
          end
        end
      end

      def stray_books(workdir, named)
        dir = File.join(workdir, BOOKS_DIR)
        return [] unless Dir.exist?(dir)

        Dir.children(dir).sort.reject do |name|
          name.start_with?(".") || named.include?(name.delete_suffix(".json.gz"))
        end
      end

      # -- parse internals ---------------------------------------------------

      def read_book(path)
        JSON.parse(SourceRead.utf8_gzip(path, label: "#{SLUG} book"))
      rescue JSON::ParserError, Zlib::Error, Errno::ENOENT => e
        raise ParseError, "#{path}: unreadable book file: #{e.message}"
      end

      def append_pages(document, body)
        decode(body).split(PAGE_BREAK, -1).each_with_index do |segment, i|
          page = clean_page(segment)
          next if page.empty?

          chunks = page.length > MAX_PASSAGE_CHARS ? split_page(page) : [page]
          chunks.each_with_index do |chunk, part|
            cite = chunks.size == 1 ? (i + 1).to_s : "#{i + 1}.#{part + 1}"
            document << Nabu::Passage.new(
              urn: "#{document.urn}:#{cite}", language: LANGUAGE, text: Normalize.nfc(chunk),
              sequence: document.size, annotations: { "segment" => i + 1, "part" => (if chunks.size > 1
                                                                                       part + 1
                                                                                     end) }.compact
            )
          end
        end
      end

      # Lines keep their breaks; trailing spaces and edge blank lines go.
      def clean_page(segment)
        segment.split("\n").map(&:rstrip).drop_while(&:empty?).reverse.drop_while(&:empty?).reverse.join("\n")
      end

      def split_page(page)
        chunks = [+""]
        page.each_line do |line|
          chunks << +"" if !chunks.last.empty? && chunks.last.length + line.length > MAX_PASSAGE_CHARS
          chunks.last << line
        end
        chunks.map(&:strip).reject(&:empty?)
      end

      def book_metadata(row, book, title)
        file_id = row.fetch("file_id")
        author = text(row["author"])
        author = nil if author == "None"
        {
          "text_nature" => "machine-ocr", "ocr_note" => OCR_NOTE,
          "gallica_ark" => "ark:/12148/#{file_id}", "source_url" => format(GALLICA_URL, file_id),
          "hf_shard" => format(SHARD_FILE, book["shard"]), "hf_row" => book["index"],
          "date" => date_metadata(row["date"]),
          "author" => author,
          "ocr_quality" => integer(row["ocr"]),
          "gallica_views" => row["page_count"], "word_count" => row["word_count"],
          "character_count" => row["character_count"],
          "facets" => facets(title, author)
        }.compact
      end

      def date_metadata(raw)
        not_before, not_after = self.class.date_envelope(raw)
        return nil if not_before.nil?

        { "not_before" => not_before, "not_after" => not_after, "raw" => raw.to_s.strip, "class" => "edition" }.compact
      end

      def facets(title, author)
        facets = {}
        head = PleiasTitleGenre.head(title)
        facets["genre"] = { "value" => head, "raw" => title } if head
        facets["author"] = { "values" => [author] } if author
        facets.empty? ? nil : facets
      end

      def decode(value) = value.gsub(ENTITY, ENTITIES)

      # A catalogue string, entity-decoded, NFC and stripped; nil if blank.
      def text(value)
        return nil unless value.is_a?(String)

        stripped = decode(value).strip
        stripped.empty? ? nil : Normalize.nfc(stripped)
      end

      def integer(value)
        value.to_s.match?(/\A\d+\z/) ? Integer(value, 10) : nil
      end
    end
  end
end

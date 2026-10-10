# frozen_string_literal: true

require "nokogiri"
require_relative "titus_khotanese_parser"
require_relative "titus_pahlavi_parser"

module Nabu
  module Adapters
    # TITUS Khotanese — the Corpus of Khotanese Saka Texts on TITUS (J. W.
    # Goethe-Universität Frankfurt, Prof. Jost Gippert): the Khotanese of the
    # Khotan oasis and Dunhuang as edited by H.W. Bailey (Buddhist Khotanese
    # Texts; Khotanese Texts I–V) and R.E. Emmerick (the Book of Zambasta) —
    # data entry R.E. Emmerick, corrections (with some text improvements) H.
    # Kumamoto, TITUS version J. Gippert (1998–2000; the collection header,
    # khots001.htm). Seven books, 1,648 texts, ONE PAGE PER TEXT (the index
    # frames' own option lists and page-number offsets, censused 2026-10-10:
    # KBT 36, KT1 9, KT2 82, KT3 121, KT4 112, KT5 1,264, Zamb. 24).
    #
    # == The grant (by email, 2026-10-06) and the credit duty
    #
    # Fetched under the owner's PERSONAL grant (Gippert): the Middle Iranian
    # families on TITUS "to whatever extent TITUS hosts them as retrievable
    # text" — ONE retrieval per corpus, local personal research use only, no
    # redistribution, TITUS and the editors credited wherever displayed. The
    # titus-pahlavi mechanisms verbatim: `grant_required: true` guards the
    # fetch right; license_class `nc` + the manifest +credit+ line carry the
    # display duty (and each document's own "data_entry"/"edition_basis"
    # metadata, where its page carries the header).
    #
    # == Shape (see Nabu::Adapters::TitusKhotaneseParser)
    #
    # canonical/titus-khotanese/khotsNNN.htm (pages 1–999) and khotNNNN.htm
    # (1000–1648) — the index frame's own JavaScript naming rule. One page is
    # one document (`urn:nabu:titus-khotanese:khots001`); one passage per
    # Line (`…:khots001:KBT.1.134r.1` — book.text.folio-side.line; the
    # folio side is absent where the text has no Paragraph level:
    # `…:khots200:KT3.53a.1`). The book rides every passage from its own
    # anchor, so continuation pages (which carry no book header) still know
    # their book.
    #
    # == Places — declared coarse
    #
    # A manuscript reference (`voc` lane, KBT's "Khadaliq 1.13") whose
    # leading word is a SITE in FINDSPOTS mines the findspot; other
    # references ride metadata raw (`manuscripts`), never guessed.
    class TitusKhotanese < Nabu::Adapter
      SLUG = "titus-khotanese"
      LANGUAGE = "kho" # Khotanese (Saka)
      PARSER_FAMILY = "titus_khotanese"

      BASE_URL = "https://titus.uni-frankfurt.de/texte/etcs/iran/miran/khot/khotsak/"
      ENTRY_URL = "#{BASE_URL}khots.htm".freeze

      PAGE_GLOB = "khot*.htm"
      PAGE_RE = /\Akhot(?:s\d{3}|\d{4})\.htm\z/

      # One TITUS book: +name+ and +basis+ verbatim from its first page's
      # header ("based upon the edition by …"). Census 2026-10-10 (each
      # book's first page: khots001/037/046/128/249/361, khot1625).
      Book = Data.define(:name, :basis)

      BOOKS = {
        "KBT" => Book.new(name: "Buddhist Khotanese Texts", basis: "H.W. Bailey, London 1951"),
        "KT1" => Book.new(name: "Khotanese Texts I", basis: "H.W. Bailey, London 1965"),
        "KT2" => Book.new(name: "Khotanese Texts II", basis: "H.W. Bailey, London 1965"),
        "KT3" => Book.new(name: "Khotanese Texts III", basis: "H.W. Bailey, London 1965"),
        "KT4" => Book.new(name: "Khotanese Texts IV", basis: "H.W. Bailey, London 1965"),
        "KT5" => Book.new(name: "Khotanese Texts V", basis: "H.W. Bailey, London 1965"),
        "Zamb." => Book.new(name: "Book of Zambasta", basis: "R.E. Emmerick, London 1966")
      }.freeze

      # Manuscript-reference site words → findspot. Census-complete for the
      # sampled pages (Khadaliq, khots001); deliberately coarse — any other
      # reference mints nothing.
      FINDSPOTS = { "Khadaliq" => "Khadaliq" }.freeze

      # The anchor components below the collection, by level.
      LEVEL_KEYS = { 2 => "book", 3 => "text", 4 => "paragraph", 5 => "line" }.freeze
      COLLECTION = "Khot."

      LICENSE = "personal grant, Gippert (by email, 2026-10-06): one retrieval, local personal " \
                "research use only, no redistribution; TITUS and the editors clearly indicated " \
                "wherever displayed"

      CREDIT = "TITUS (J. Gippert, Frankfurt) — Corpus of Khotanese Saka Texts: data entry " \
               "R.E. Emmerick, corrections H. Kumamoto, TITUS version J. Gippert; on the basis of " \
               "the editions of H.W. Bailey (Buddhist Khotanese Texts; Khotanese Texts I–V) and " \
               "R.E. Emmerick (The Book of Zambasta)."

      def self.manifest
        Nabu::SourceManifest.new(
          id: SLUG,
          name: "TITUS Corpus of Khotanese Saka Texts",
          license: LICENSE,
          license_class: "nc",
          upstream_url: ENTRY_URL,
          parser_family: PARSER_FAMILY,
          credit: CREDIT
        )
      end

      # The frameset entry stands for the corpus — HEAD it for liveness; the
      # TitusFetch state file (url + sha) feeds the drift lane.
      def self.remote_probe_strategy = :http_zip

      def self.http_probe_targets
        [Nabu::Adapter::HttpProbeTarget.new(
          label: "khots.htm entry", zip_url: ENTRY_URL, metadata_url: nil,
          state_subdir: "", state_file: Nabu::TitusFetch::STATE_FILE
        )]
      end

      # The findspot a manuscript reference's leading site word names, or nil.
      def self.findspot_for(reference)
        FINDSPOTS[reference.to_s.split.first]
      end

      # +delay+ is TitusFetch's polite pause between requests (tests pass 0).
      def initialize(delay: Nabu::TitusFetch::DELAY)
        super()
        @delay = delay
      end

      def discover(workdir)
        Dir.glob(File.join(workdir, PAGE_GLOB)).filter_map do |path|
          name = File.basename(path)
          next unless name.match?(PAGE_RE)

          stem = name.delete_suffix(".htm")
          Nabu::DocumentRef.new(source_id: SLUG, id: document_urn(stem), path: path,
                                metadata: { "page" => stem })
        end
      end

      # Parse one page into a Document of Line passages. A page with no
      # text-bearing line is a structural failure (ParseError).
      def parse(document_ref)
        html = TitusPahlaviParser.read_page(document_ref.path)
        lines = TitusKhotaneseParser.parse(html)
        raise Nabu::ParseError, "#{SLUG}: no text lines in #{document_ref.path}" if lines.empty?

        stem = document_ref.metadata.fetch("page")
        metadata = document_metadata(html, lines)
        document = Nabu::Document.new(
          urn: document_ref.id, language: LANGUAGE, canonical_path: document_ref.path,
          title: title_for(stem, metadata), metadata: metadata
        )
        seen = Hash.new(0)
        lines.each_with_index do |line, sequence|
          citation = citation_for(line)
          occurrence = (seen[citation] += 1)
          document << Nabu::Passage.new(
            urn: passage_urn(document_ref.id, citation, occurrence), language: LANGUAGE,
            text: line.text, sequence: sequence, annotations: line_annotations(line, occurrence)
          )
        end
        document
      end

      # One polite TitusFetch walk over the "Next part" chain (owner-run;
      # never in tests — WebMock blocks the network). Pages already on disk
      # are never re-fetched (the grant's ONE retrieval). Nothing beyond the
      # upstream pages and the fetch's own state file is materialized.
      def fetch(workdir, progress: nil, force: false)
        result = Nabu::TitusFetch.sync!(
          entry_url: ENTRY_URL, dir: workdir, attic_dir: File.join(workdir, ATTIC_DIRNAME),
          page_re: PAGE_RE, delay: @delay, progress: progress,
          guard: ->(doomed) { guard_mass_deletion!(workdir, doomed, force: force) }
        )
        FetchReport.new(sha: result.sha, fetched_at: Time.now, notes: attic_notes(result.atticked))
      rescue Nabu::TitusFetch::Error => e
        raise Nabu::FetchError, "#{SLUG} fetch failed into #{workdir}: #{e.message}"
      end

      private

      def document_urn(stem)
        "urn:nabu:#{SLUG}:#{stem}"
      end

      # The components below the collection, empties (absent levels) dropped:
      # "KBT.1.134r.1", "Zamb.1.31" (a component's own trailing period —
      # "Zamb." — drops so the dots stay separators).
      def citation_for(line)
        below_collection(line.components).reject(&:empty?).map { |c| c.delete_suffix(".") }.join(".")
      end

      def below_collection(components)
        components.first == COLLECTION ? components.drop(1) : components
      end

      # A citation the page re-anchors (KBT 1's two "139v 4" lines, census
      # 2026-10-10) keys as `<citation>#<occurrence>` in document order — real
      # text, never merged, never dropped.
      def passage_urn(document_urn, citation, occurrence)
        tail = occurrence > 1 ? "#{citation}##{occurrence}" : citation
        "#{document_urn}:#{tail}"
      end

      def line_annotations(line, occurrence)
        annotations = { "unit" => line.label }
        line.components.each_with_index do |value, index|
          key = LEVEL_KEYS[index + 1]
          annotations[key] = value if key && !value.empty?
        end
        annotations["occurrence"] = occurrence if occurrence > 1
        annotations
      end

      # Book (from the anchors — every page), the book table's name and
      # edition basis, the text id(s), and the header matter mined verbatim:
      # the data-entry statement, the Sanskrit title, the manuscript
      # references (+ the findspot their site word names).
      def document_metadata(html, lines)
        books = lines.filter_map { |line| line.components[1] }.uniq
        texts = lines.filter_map { |line| line.components[2] }.uniq
        metadata = { "book" => books.join(", "), "text" => texts.join(", ") }
        book = BOOKS[books.first]
        metadata.merge!("book_name" => book.name, "edition_basis" => book.basis) if book && books.size == 1
        doc = Nokogiri::HTML(html)
        header_text(doc, "textdescr")&.then { |text| metadata["data_entry"] = text }
        header_text(doc, "iosk")&.then { |text| metadata["sanskrit_title"] = text }
        references = header_runs(doc, "voc")
        unless references.empty?
          metadata["manuscripts"] = references
          findspot = references.filter_map { |ref| self.class.findspot_for(ref) }.first
          metadata["findspot"] = findspot if findspot
        end
        metadata
      end

      # The text of every span whose id starts with +prefix+ and is that
      # prefix (+ a size), cleaned, in page order.
      def header_runs(doc, prefix)
        pattern = /\A#{Regexp.escape(prefix)}\d*\z/
        spans = doc.css("span[id]").select { |span| pattern.match?(span["id"]) }
        spans.map { |span| TitusPahlaviParser.clean(span.text) }.reject(&:empty?)
      end

      # Split runs of one kind join with an ellipsis (the pahlavi rule).
      def header_text(doc, prefix)
        runs = header_runs(doc, prefix)
        runs.empty? ? nil : runs.join(" … ")
      end

      def title_for(stem, metadata)
        label = [metadata["book_name"] || metadata["book"], metadata["text"]].reject { |v| v.nil? || v.empty? }
        "Khotanese — #{label.join(' ')} (#{stem})"
      end
    end
  end
end

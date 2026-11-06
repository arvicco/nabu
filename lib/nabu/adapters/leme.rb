# frozen_string_literal: true

require "json"
require_relative "leme_fetch"
require_relative "leme_xml_parser"
require_relative "source_read"

module Nabu
  module Adapters
    # LEME — Lexicons of Early Modern English (ed. Ian Lancashire,
    # University of Toronto; University of Toronto Press / University of
    # Toronto Libraries, 2018–): the encoded texts of the monolingual,
    # bilingual and polyglot dictionaries, hard-word glossaries, spelling
    # lists, herbals, glossed texts and lexically valuable treatises that
    # survive in print or manuscript from about 1475 to 1755 — published
    # as LEME-XML through TSpace, the University of Toronto's repository
    # (collection 1807/99021). One lexical work = one dictionary shelf
    # ("leme-<handle suffix>", 312 of them), its word-entries the entries.
    #
    # == Upstream / grains (verified 2026-11-05)
    #
    # The DSpace 7 REST API (Nabu::Adapters::LemeFetch) advertises 314 archived items
    # in the collection (collection archivedItemsCount and the discovery
    # listing's totalElements agree), each with:
    #
    # - ONE ORIGINAL-bundle bitstream named *.xml — the LEME-XML of the
    #   work, ACCEPTED (314 of 314);
    # - on 20 items, 26 further UNNAMED ORIGINAL bitstreams (earlier or
    #   duplicate uploads, sizes within bytes of the named file; every one
    #   answers HTTP 500 at /content) — REJECTED by rule, never fetched,
    #   counted from the held item JSON;
    # - the CC-LICENSE (license_rdf) and LICENSE (license.txt) bundles —
    #   DSpace deposit furniture, not data.
    #
    # Of the 314 XMLs, TWO carry no headworded word-entry (no <form>) —
    # 1807/102105, Cotton's Society of Antiquaries discourse "Of the
    # Antiquity of Motts and Words" (running prose, no <wordentry>), and
    # 1807/111075, Manlove's lead-mine terms (1653: one <wordentry> wrapping
    # a verse word list) — REJECTED by rule at discovery.
    #
    # Reconciliation (census 2026-11-05, every XML through this adapter):
    # 312 discovered + 2 rule skips = the 314 advertised items. Of the 312,
    # 311 parse to 943,211 entries (218 form-less word-entries inside them
    # are skipped, the parser's census) and ONE quarantines on an upstream
    # well-formedness defect: 1807/131265 (Martinez's Key of the Holy
    # Tongue, 1593) line 925, `<subform lang="he"><אַצׅיל/subform>` — a
    # broken end tag no rule can honestly repair (2,286 word-entries).
    # Entry languages: en 512,005 · ita 167,042 · lat 141,293 · fra 60,388 ·
    # spa 28,406 · ang 7,998 · cym 7,322 · und 6,368 · hbo 6,065 · enm
    # 3,281 · ara 1,243 · sco 960 · grc 833 · por 5 · nld 2. Shelves: en
    # 233 · lat 28 · und 16 · ita 6 · fra 6 · enm 5 · hbo/grc/ang 3 each ·
    # ara/cym/spa/sco 2 each. 100,047 entries are glossless — spelling lists
    # and Minsheu's polyglot index print a head with no explanation.
    #
    # == Dating, lect, places
    #
    # Each item's Dublin Core dc.date.created is the work's typed year (the
    # base edition's — LEME transcribes "normally its earliest edition"):
    # 314 of 314 four-digit (1477–1755 but for one 1884), the exception made by rule
    # from upstream's own data (DATE_ERRATA). It rides every entry as
    # "lexicon_year" with the author as "lexicon_author" — the dictionary
    # store keeps no per-shelf metadata, so the entry grain carries it.
    # Headword language is per entry (LemeXmlParser::LANGUAGES); the shelf
    # takes its entries' majority. Place: the imprint town sits only inside
    # the citation prose (dc.identifier.citation), declared unmined.
    #
    # == License
    #
    # LEME's Terms of Use (leme.library.utoronto.ca/help/termsofuse, read
    # 2026-11-05), verbatim: "The following materials in LEME are licensed
    # under a Creative Commons Attribution 4.0 International license: All
    # files provided on the LEME website (http://leme.library.utoronto.ca),
    # and the XML encoded texts of lexical works, made available through
    # the TSpace institutional repository." Each item's dc.rights reads
    # "Attribution 4.0 International" (309 of 314) and dc.rights.uri
    # http://creativecommons.org/licenses/by/4.0/ (311 of 314); three items
    # carry neither and ride the site-wide grant. Parse re-verifies a
    # present dc.rights.uri and quarantines drift. → license_class
    # "attribution".
    class Leme < Nabu::Adapter
      MANIFEST = Nabu::SourceManifest.new(
        id: "leme",
        name: "LEME — Lexicons of Early Modern English (University of Toronto), the LEME-XML texts on TSpace",
        license: "CC BY 4.0 (LEME Terms of Use, verbatim: \"The following materials in LEME are licensed under " \
                 "a Creative Commons Attribution 4.0 International license: All files provided on the LEME " \
                 "website (http://leme.library.utoronto.ca), and the XML encoded texts of lexical works, made " \
                 "available through the TSpace institutional repository.\"; each TSpace item's dc.rights " \
                 "\"Attribution 4.0 International\"). Credit: Lexicons of Early Modern English, ed. Ian " \
                 "Lancashire (Toronto: University of Toronto Press, 2018), https://leme.library.utoronto.ca",
        license_class: "attribution",
        upstream_url: "https://hdl.handle.net/1807/99021",
        parser_family: "leme-xml"
      )

      SLUG_PREFIX = "leme-"
      LICENSE_URI = %r{\Ahttps?://creativecommons\.org/licenses/by/4\.0/?\z}
      TITLE_MAX = 120
      # The one item whose dc.date.created is not the work's date: the
      # manuscript Nominale is lost, LEME transcribes it from Wright and
      # Wülcker's 1884 edition, and dc.date.created gives that edition's
      # year. LEME's own head note in the XML dates the work "(ca.
      # 1475-1500)", and the bitstream name says "Nominale1475-1500".
      DATE_ERRATA = {
        "1807/139760" => "1475–1500"
      }.freeze
      MARKERS = [/<wordentry[\s>]/, /<form[\s>]/].freeze
      private_constant :LICENSE_URI, :TITLE_MAX, :MARKERS

      def self.manifest = MANIFEST

      # Entries, not passages — SyncRunner/Rebuild load through
      # Store::DictionaryLoader (architecture §11).
      def self.content_kind = :dictionary

      def self.remote_probe_strategy = :http_zip

      # Liveness only: the walk's state is the listing's lastModified stamps
      # and the bitstream MD5s, not a Last-Modified pin.
      def self.http_probe_targets
        [Nabu::Adapter::HttpProbeTarget.new(
          label: "TSpace discovery listing", zip_url: Nabu::Adapters::LemeFetch.list_url(0), metadata_url: nil,
          state_subdir: "", liveness_only: true
        )]
      end

      # The canonical tree is the walk's own plain directory (no git), so
      # the identity walker hashes all of it; nothing is materialized
      # beside an upstream tree.
      def self.materialized_paths = []

      # The work's date as the "lexicon_year" string ("1549", "1475–1500"),
      # nil when the item carries no usable year.
      def self.lexicon_year(item)
        erratum = DATE_ERRATA[item["handle"]]
        return erratum if erratum

        year = dc(item, "dc.date.created").first.to_s.strip
        year.match?(/\A\d{4}\z/) ? year : nil
      end

      def self.dc(item, key) = Array(item.dig("metadata", key)).map { |m| m["value"].to_s }

      def initialize(delay: Nabu::Adapters::LemeFetch::DELAY)
        super()
        @delay = delay
      end

      def fetch(workdir, progress: nil, force: false) # rubocop:disable Lint/UnusedMethodArgument
        result = Nabu::Adapters::LemeFetch.sync!(dir: workdir, delay: @delay, progress: progress)
        notes = "#{result.held}/#{result.listed} listed item(s) held of #{result.advertised} advertised " \
                "(+#{result.items_fetched} item record(s), +#{result.xml_fetched} XML file(s) this sync)"
        notes += "; unreachable, retried next sync: #{result.failed.join(', ')}" unless result.failed.empty?
        progress&.call("#{notes}\n")
        Nabu::FetchReport.new(sha: result.sha, fetched_at: Time.now, notes: notes)
      rescue Nabu::Adapters::LemeFetch::Error => e
        raise Nabu::FetchError, "leme fetch failed into #{workdir}: #{e.message}"
      end

      # One ref per held item whose XML is held and carries word-entries.
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        held_items(workdir).each do |key, item_path, xml_path|
          next unless xml_path && entries?(xml_path)

          yield Nabu::DocumentRef.new(
            source_id: MANIFEST.id, id: "leme:#{key}", path: File.expand_path(xml_path),
            metadata: { "dictionary" => "#{SLUG_PREFIX}#{key}", "item" => File.expand_path(item_path) }
          )
        end
      end

      def discovery_skips(workdir)
        skipped = 0
        unrecognized = 0
        notes = []
        held_items(workdir).each do |key, item_path, xml_path|
          handle = "1807/#{key}"
          if xml_path.nil?
            unrecognized += 1
            notes << "#{handle}: item record held without its XML (a failed fetch — retried next sync)"
            next
          end
          unless entries?(xml_path)
            skipped += 1
            notes << "#{handle}: skipped by rule — the XML carries no headworded <wordentry> (no <form>: " \
                     "prose or verse, not a lexicon)"
          end
          unnamed = unnamed_bitstreams(item_path)
          next if unnamed.zero?

          skipped += unnamed
          notes << "#{handle}: #{unnamed} unnamed ORIGINAL bitstream(s) skipped by rule — earlier or duplicate " \
                   "uploads beside the named XML, never fetched"
        end
        Nabu::Adapter::DiscoverySkips.new(skipped_by_rule: skipped, unrecognized: unrecognized, notes: notes)
      end

      def parse(document_ref)
        item = read_item(document_ref.metadata.fetch("item"))
        verify_license!(item, document_ref)
        context = { "lexicon_year" => self.class.lexicon_year(item), "lexicon_author" => author(item) }.compact
        result = LemeXmlParser.new.parse(document_ref.path, context: context)
        raise Nabu::ParseError, "leme: #{document_ref.id}: no word-entry parsed" if result.entries.empty?

        document = Nabu::DictionaryDocument.new(
          slug: document_ref.metadata.fetch("dictionary"), language: result.language, title: title(item),
          canonical_path: document_ref.path
        )
        result.entries.each { |entry| document << entry }
        document
      rescue Nabu::ValidationError => e
        raise Nabu::ParseError, "leme: #{document_ref.id}: #{e.message}"
      end

      private

      # [key, item json path, xml path or nil] per held item record, sorted.
      def held_items(workdir)
        Dir.glob(File.join(workdir, Nabu::Adapters::LemeFetch::ITEMS_DIR, "*.json")).map do |item_path|
          key = File.basename(item_path, ".json")
          xml = Nabu::Adapters::LemeFetch.xml_path(workdir, key)
          [key, item_path, File.file?(xml) ? xml : nil]
        end
      end

      # Does the file carry headworded LEME word-entries — a <wordentry>
      # AND a <form> (its headword element)? A text scan through the belt —
      # discovery never parses. Bad bytes answer yes: the file then reaches
      # parse, which quarantines it with the belt's own error.
      def entries?(xml_path)
        text = SourceRead.utf8_file(xml_path, label: "leme-xml")
        MARKERS.all? { |marker| text.match?(marker) }
      rescue Nabu::ParseError
        true
      end

      def unnamed_bitstreams(item_path)
        Nabu::Adapters::LemeFetch.original_bitstreams(read_item(item_path)).count { |b| b["name"].to_s.strip.empty? }
      rescue Nabu::ParseError
        0
      end

      def read_item(path)
        data = JSON.parse(SourceRead.utf8_file(path, label: "leme item"))
        raise Nabu::ParseError, "leme: #{path}: item record is not a JSON object" unless data.is_a?(Hash)

        data
      rescue JSON::ParserError => e
        raise Nabu::ParseError, "leme: #{path}: item record is not JSON (#{e.message})"
      end

      def verify_license!(item, document_ref)
        uris = self.class.dc(item, "dc.rights.uri")
        return if uris.empty? || uris.all? { |uri| uri.strip.match?(LICENSE_URI) }

        raise Nabu::ParseError, "leme: #{document_ref.id}: dc.rights.uri drifted from CC BY 4.0: #{uris.inspect}"
      end

      def author(item)
        names = self.class.dc(item, "dc.contributor.author").map(&:strip).reject(&:empty?)
        names.empty? ? nil : Nabu::Normalize.nfc(names.join("; "))
      end

      # The catalogue number (STC / Wing / ESTC / a manuscript shelfmark);
      # 19 items repeat the publisher's name in dc.identifier instead —
      # not an identifier, dropped.
      def identifier(item)
        publisher = self.class.dc(item, "dc.publisher").map(&:strip)
        self.class.dc(item, "dc.identifier").map(&:strip).find { |id| !id.empty? && !publisher.include?(id) }
      end

      # "Baldwin, William, The Canticles or Balades of Solomon (1549; STC 2768)".
      def title(item)
        short = (self.class.dc(item, "dc.title.alternative") + self.class.dc(item, "dc.title"))
                .map { |t| t.gsub(/\s+/, " ").strip }.find { |t| !t.empty? } || item["handle"].to_s
        short = "#{short[0, TITLE_MAX].sub(/\s+\S*\z/, '')}…" if short.length > TITLE_MAX
        tail = [self.class.lexicon_year(item), identifier(item)].compact.reject(&:empty?)
        head = [author(item), short].compact.join(", ")
        Nabu::Normalize.nfc(tail.empty? ? head : "#{head} (#{tail.join('; ')})")
      end
    end
  end
end

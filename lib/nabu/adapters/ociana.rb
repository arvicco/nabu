# frozen_string_literal: true

require "nokogiri"
require_relative "../file_fetch"

module Nabu
  module Adapters
    # OCIANA — the Online Corpus of the Inscriptions of Ancient North
    # Arabia (Khalili Research Centre, University of Oxford): 37,955
    # inscription records in the Safaitic (31,760), Hismaic (3,644),
    # Dadanitic (1,706), Taymanitic (482) and minor ANA scripts, as ONE
    # immutable ORA archive deposit (doi 10.5287/bodleian:OBVk0AY52,
    # copyright 2017). Mostly desert graffiti — "By N son of N …" —
    # transliterated in the scholarly ANA convention, with English
    # translations on 36,811 records and WGS84 coordinates on 21,837.
    #
    # == License / acquisition
    #
    # No open licence: the deposit falls under the archive's own Terms of
    # Use (https://ora.ox.ac.uk/terms_of_use, captured 2026-10-18), whose
    # operative clause reads, verbatim: "Unless otherwise indicated in the
    # relevant permissions notice on the item record, users may download
    # and/or print one copy of any item in ORA to facilitate their private
    # study or research for non-commercial purposes." and "users may not
    # use material obtained from ORA for any profit-making activities or
    # any commercial gain." No redistribution grant was sought → the
    # corpus-gysseling / corpus-oudnederlands NON-GRANT posture,
    # research_private (strictest reading): held locally for the owner's
    # research only. The standing class gates do the rest — excluded from
    # MCP serving, the site figures and every nabu-data publication by
    # license_class alone (nothing here special-cases the slug). NO
    # deposit bytes in the public repo: fixtures live under gitignored
    # local/fixtures/ociana/. Acquired 2026-10-18 (sha256 pinned below).
    #
    # == The file (a byte-level cut — the deposit is not one XML document)
    #
    # An <?xml?> prologue, an <xs:schema> preamble, then 37,955 SIBLING
    # <inscription> roots, each with the same flat children. The record
    # boundary is cut on the RAW BYTES (the skjaervo-khotanese mold):
    # the flat <inscription>…</inscription> spans are regex-exact
    # (37,955, censused), which skips the preamble and the multiple roots
    # for free. Each fragment then parses ALONE, STRICT. Damage boundary:
    # 8 records carry XML-illegal C0 control characters (U+0002/0004/000B
    # — stray bytes in a translation, a commentary, and one
    # transliteration padded with U+000B runs); for exactly those the
    # parse falls back to libxml2 recover, which drops the illegal
    # characters and keeps every other byte of that one record (verified
    # field by field on all 8). Text is otherwise kept verbatim — entities
    # decode per XML, and line ends (the &#xD; CR entities upstream uses
    # for line breaks, 1,317 transliterations) normalize to "\n" (the
    # line-end normalization XML applies to literal CRLF; nothing else is
    # "cleaned").
    #
    # == Identity / passages
    #
    # One document per record, urn:nabu:ociana:<id> where <id> is the
    # STABLE page id the record's url ends in (…/OCIANA_0002825.html).
    # 13 ids carry upstream suffixes (OCIANA_0038668B, …BPWS, one
    # "OCIANA_0035040JSLih 200" with a space — whitespace runs become "-"
    # in the urn; the verbatim id rides metadata "ociana_id"). A record
    # whose url carries no OCIANA_ id is quarantined (ParseError), never
    # minted from its position. One passage per record: the
    # transliteration. 1,161 records carry NO transliteration (973
    # Safaitic, 150 "Rock Drawing Only", the rest scattered) — skipped
    # by rule and censused in discovery_skips; there is no text to serve.
    #
    # == Language / script
    #
    # Document language xna (ISO 639-3 Ancient North Arabian) — the
    # bare-code claim — save the 36 text-bearing non-ANA records, which
    # keep their own codes (SCRIPT_LANGUAGES); the per-record script rides metadata "script"
    # (facet + the stage flip once the registry carries the ANA stage
    # nodes). The upstream language field (empty on 37,940 records,
    # "Dadanitic" on 7) rides "language_field" when present.
    #
    # == Mining (the aggressive-mining rule)
    #
    # translation → "translation_en"; site/region/country/
    # provenanceNotes/coordinates → the "place" hash ({"ancient" => site,
    # "geo" => "lat, lon"} when BOTH coordinates are decimal — 28 records
    # carry degree-minute or prefixed strings, kept raw in
    # "coordinates_raw", never guessed into a point). findDate (17,681
    # records: "1989", "1920s and 1930s", "1904–1905") is the DISCOVERY /
    # survey date, never the inscription's date — it rides "find_date"
    # and is deliberately NOT a dating claim (the dating posture is
    # undatable). siglum / alternativeSigla, the apparatus (appCrit), the
    # commentary, fieldCollector, survey and the references list ride
    # document metadata verbatim.
    #
    # == fetch / sync policy
    #
    # One FileFetch GET of the deposit file into <workdir>/ociana.xml,
    # two-phase with a FROZEN sha256 pin (the open-etruscan shape): drift
    # aborts BEFORE the tree mutates — a re-pin is an owner decision.
    # sync_policy: frozen.
    class Ociana < Nabu::Adapter
      RECORD_URL = "https://ora.ox.ac.uk/objects/uuid:08a60ae8-e61d-486e-9ef1-836ca71d904c"
      FILE_URL = "#{RECORD_URL}/files/mc562d7869379fa3570db57cd9ed0c28c".freeze
      DOI = "10.5287/bodleian:OBVk0AY52"

      # sha256 of the full deposit, computed at acquisition 2026-10-18.
      CORPUS_SHA256 = "5a90c113356fac5943f34036464680f4a8651a69cb34102fed6bc54af0a3077c"

      FILENAME = "ociana.xml"
      URN_PREFIX = "urn:nabu:ociana:"
      LANGUAGE = "xna"
      # The non-ANA inscriptions the corpus also records (full-deposit
      # census, text-bearing): Greek in Greek capitals (22), Latin (1),
      # Minaic (8, ISO Minaean), Nabataean Aramaic (4 — arc, the Aramaic
      # anchor; no ISO code is Nabataean-specific) and one generic "South
      # Arabian" (xsa, the nearest ISO code — declared coarse). Each keeps
      # its own language; every ANA script stays xna.
      SCRIPT_LANGUAGES = { "Greek" => "grc", "Latin" => "lat", "Minaic" => "inm",
                           "South Arabian" => "xsa", "Nabataean" => "arc" }.freeze

      FRAGMENT = %r{<inscription>.*?</inscription>}m
      URL_ID = %r{/(OCIANA_\d[^/]*?)\.html\s*\z}
      RAW_URL = %r{<url>(.*?)</url>}m
      RAW_TRANSLITERATION = %r{<transliteration>(.*?)</transliteration>}m
      # The XML-1.0-illegal C0 controls (the damage-boundary trigger).
      ILLEGAL_CONTROLS = /[\x00-\x08\x0B\x0C\x0E-\x1F]/
      DECIMAL = /\A-?\d+(?:\.\d+)?\z/

      CITATION = "OCIANA — Online Corpus of the Inscriptions of Ancient North Arabia, " \
                 "Khalili Research Centre, University of Oxford (Oxford University Research " \
                 "Archive, 2017), doi #{DOI}".freeze

      MANIFEST = Nabu::SourceManifest.new(
        id: "ociana",
        name: "OCIANA — Online Corpus of the Inscriptions of Ancient North Arabia",
        license: "ORA Terms of Use (https://ora.ox.ac.uk/terms_of_use; deposit doi #{DOI}, " \
                 "copyright 2017; acquired 2026-10-18): \"users may download and/or print one " \
                 "copy of any item in ORA to facilitate their private study or research for " \
                 "non-commercial purposes\"; no profit-making use. No redistribution grant → " \
                 "strictest reading: local research ingest only, never redistributed. " \
                 "Cite: #{CITATION}",
        license_class: "research_private",
        upstream_url: RECORD_URL,
        parser_family: "ociana-xml",
        credit: CITATION
      )

      def self.manifest = MANIFEST

      def self.remote_probe_strategy = :http_zip

      def self.http_probe_targets
        [Nabu::Adapter::HttpProbeTarget.new(
          label: FILENAME, zip_url: FILE_URL, metadata_url: nil,
          state_subdir: "", state_file: FileFetch::STATE_FILE
        )]
      end

      # +corpus_sha256+ exists for the WebMock'd fetch tests — real syncs
      # keep the frozen pin.
      def initialize(corpus_sha256: CORPUS_SHA256)
        super()
        @pin = corpus_sha256
      end

      # One ref per record carrying a transliteration, in deposit order. A
      # workdir without the deposit yields nothing (the pre-fetch state).
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        path = corpus_path(workdir) or return
        refs_for(path).each(&block)
      end

      # The empty-transliteration census (1,161 on the full deposit).
      def discovery_skips(workdir)
        path = corpus_path(workdir)
        return DiscoverySkips.new if path.nil?

        empty = fragments(path).count { |fragment| !transliterated?(fragment) }
        notes = empty.positive? ? ["#{empty} records without a transliteration skipped — no text to serve"] : []
        DiscoverySkips.new(skipped_by_rule: empty, notes: notes)
      end

      def parse(document_ref)
        index = document_ref.metadata.fetch("index")
        fragment = fragments(document_ref.path)[index] or
          raise Nabu::ParseError, "#{document_ref.id}: fragment #{index} vanished (stale ref?)"
        record = parse_fragment(fragment, document_ref.id)
        build_document(document_ref, record)
      rescue Nabu::ValidationError => e
        raise Nabu::ParseError, "#{document_ref.path}: #{document_ref.id}: #{e.message}"
      end

      # One GET, two-phase: prepare holds the body, the frozen pin
      # verifies it, the breaker sees the doomed set, then complete.
      def fetch(workdir, progress: nil, force: false)
        fetch = FileFetch.new(url: FILE_URL, dir: workdir, filename: FILENAME,
                              attic_dir: File.join(workdir, ATTIC_DIRNAME), progress: progress)
        fetch.prepare!
        verify_pin!(fetch)
        guard_mass_deletion!(workdir, fetch.doomed_paths, force: force)
        fetch.complete!
        notes = ["#{FILENAME} #{fetch.sha[0, 12]}", attic_notes(fetch.atticked)].compact.join("; ")
        Nabu::FetchReport.new(sha: fetch.sha, fetched_at: Time.now, notes: notes)
      rescue FileFetch::Error => e
        raise Nabu::FetchError, "ociana fetch failed into #{workdir}: #{e.message}"
      end

      private

      def corpus_path(workdir)
        path = File.join(workdir, FILENAME)
        File.file?(path) ? File.expand_path(path) : nil
      end

      def verify_pin!(fetch)
        return if fetch.sha == @pin

        raise Nabu::FetchError,
              "ociana: deposit drifted — fetched sha256 #{fetch.sha} != pinned #{@pin}; the ORA " \
              "deposit #{DOI} is frozen — review upstream and re-pin (owner decision)"
      end

      # Raw-byte record spans, cached per [path, mtime] (the skjaervo
      # cache — parse is called once per ref, the file holds every ref).
      def fragments(path)
        key = [path, File.mtime(path)]
        return @fragments_cache if defined?(@fragments_key) && @fragments_key == key

        @fragments_key = key
        @fragments_cache = File.read(path, encoding: "UTF-8").scan(FRAGMENT)
      end

      # Cheap discover-time test: does the raw transliteration carry any
      # text once whitespace (U+000B included), CR entities and illegal
      # controls are set aside? Parse re-checks on the decoded text.
      def transliterated?(fragment)
        raw = fragment[RAW_TRANSLITERATION, 1].to_s
        !raw.gsub(/&#(?:x[dDaA9]|1[03]|9);/, "").gsub(ILLEGAL_CONTROLS, "").strip.empty?
      end

      def refs_for(path)
        seen = Hash.new(0)
        fragments(path).each_with_index.filter_map do |fragment, index|
          next unless transliterated?(fragment)

          slug = urn_slug(fragment[RAW_URL, 1]) || "x#{index + 1}"
          seen[slug] += 1
          urn = seen[slug] == 1 ? "#{URN_PREFIX}#{slug}" : "#{URN_PREFIX}#{slug}b#{seen[slug]}"
          Nabu::DocumentRef.new(source_id: MANIFEST.id, id: urn, path: path,
                                metadata: { "index" => index })
        end
      end

      def url_id(url)
        url.to_s[URL_ID, 1]
      end

      def urn_slug(url)
        url_id(url)&.gsub(/\s+/, "-")
      end

      # Strict per fragment; the recover fallback ONLY for the censused
      # illegal-control-character damage (class note).
      def parse_fragment(fragment, urn)
        Nokogiri::XML(fragment, &:strict).root
      rescue Nokogiri::XML::SyntaxError => e
        raise Nabu::ParseError, "#{urn}: malformed record (#{e.message.lines.first&.strip})" unless
          fragment.match?(ILLEGAL_CONTROLS)

        Nokogiri::XML(fragment, &:recover).root or raise Nabu::ParseError, "#{urn}: unparseable record"
      end

      def build_document(document_ref, record)
        id = url_id(field(record, "url")) or
          raise Nabu::ParseError, "#{document_ref.id}: record url carries no OCIANA_ page id " \
                                  "(#{field(record, 'url').inspect})"
        text = field(record, "transliteration") or
          raise Nabu::ParseError, "#{document_ref.id}: empty transliteration"

        language = SCRIPT_LANGUAGES.fetch(field(record, "script"), LANGUAGE)
        document = Nabu::Document.new(
          urn: document_ref.id, language: language, canonical_path: document_ref.path,
          title: field(record, "siglum"), metadata: metadata_for(record, id)
        )
        document << Nabu::Passage.new(urn: "#{document_ref.id}:1", language: language,
                                      text: text, sequence: 0)
        document
      end

      # One child's decoded text: line ends to "\n", ends stripped, NFC;
      # nil when empty.
      def field(record, name)
        text = record.at_xpath(name)&.text.to_s.gsub(/\r\n?/, "\n").strip
        text.empty? ? nil : Normalize.nfc(text)
      end

      METADATA_FIELDS = {
        "siglum" => "siglum", "alternative_sigla" => "alternativeSigla", "script" => "script",
        "language_field" => "language", "translation_en" => "translation",
        "apparatus" => "appCrit", "commentary" => "commentary",
        "field_collector" => "fieldCollector", "survey" => "survey", "find_date" => "findDate"
      }.freeze
      private_constant :METADATA_FIELDS

      def metadata_for(record, id)
        meta = { "ociana_id" => id, "permanent_url" => field(record, "url"), "citation" => CITATION }
        METADATA_FIELDS.each do |key, tag|
          value = field(record, tag)
          meta[key] = value if value
        end
        references = record.xpath("reference").filter_map do |node|
          text = node.text.gsub(/\r\n?/, "\n").strip
          text.empty? ? nil : Normalize.nfc(text)
        end
        meta["references"] = references unless references.empty?
        place = place_for(record)
        meta["place"] = place unless place.empty?
        meta
      end

      # The place hash (the ogham/EDR shape): "ancient" = the site, the
      # region/country ladder, provenanceNotes as "notes", and the WGS84
      # "geo" pair ONLY when both coordinates are decimals; anything else
      # rides "coordinates_raw" verbatim.
      def place_for(record)
        place = {}
        { "ancient" => "site", "region" => "region", "country" => "country",
          "notes" => "provenanceNotes" }.each do |key, tag|
          value = field(record, tag)
          place[key] = value if value
        end
        lat = field(record, "latitude")
        lon = field(record, "longitude")
        if lat && lon && lat.match?(DECIMAL) && lon.match?(DECIMAL)
          place["geo"] = "#{lat}, #{lon}"
        elsif lat || lon
          place["coordinates_raw"] = [lat, lon].join(", ")
        end
        place
      end
    end
  end
end

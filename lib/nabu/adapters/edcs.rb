# frozen_string_literal: true

require "json"

require_relative "../json_array_splitter"
require_relative "../fetch/file_fetch"

module Nabu
  module Adapters
    # The EDCS adapter: the Epigraphik-Datenbank Clauss-Slaby (db.edcs.eu;
    # Manfred Clauss, Anne Kolb, Wolfgang A. Slaby, Barbara Woitas et al.)
    # — the largest index of Latin inscriptions, every province of the
    # empire and Italy — as the SDAM project (Social Dynamics and complexity
    # in the Ancient Mediterranean, Aarhus University; Petra Heřmánková)
    # scraped and cleaned it. THIS IS A THIRD-PARTY CLEANED SCRAPE of
    # db.edcs.eu, frozen 2022-09-12, never EDCS's own export: credit goes to
    # both EDCS (the texts and their metadata) and SDAM (the scrape and the
    # cleaned layers). EDCS indexes the same stones EDH and EDR edit, so
    # heavy overlap with the held edh/edr is expected and DELIBERATELY not
    # deduplicated — separate databases, provenance-distinct witnesses (the
    # edh/edr standing doctrine); the EDH partner ids ride metadata for the
    # join.
    #
    # == The deposit (census of the whole file, 2026-11-28)
    #
    # ONE Zenodo artifact: record 7072337 ("EDCS", version 2.0, published
    # 2022-09-12), EDCS_text_cleaned_2022-09-12.json, 465,523,658 B, md5
    # 7ee22c65f442d54ba3537955603cc0ba (Zenodo's own checksum, matched on
    # the census download). ONE line: a single JSON array of 537,262
    # records (pandas records orient; an empty upstream value is "{}"). The
    # grains upstream serves: the record (an inscription) is the only one —
    # no volume, page or index grain exists in the file. Accounting:
    #
    #   537,262 records = 513,781 documents
    #     + 6,997 without an inscription key
    #     + 12,549 whose inscription carries no letter (12,382 are EDCS's
    #       "?" — text not given; the rest bare lacuna brackets "[3]",
    #       "[[6]]", "//")
    #     + 3,935 repeated copies: 3,955 EDCS-IDs occur twice, every pair
    #       identical as parsed; the later copy of a text-bearing pair is
    #       skipped by rule (one document per id; 20 pairs are text-less
    #       and skip as such).
    #
    # Measured dry parse of the whole file (2026-11-28): 513,781 documents
    # / 513,781 passages, 0 parse errors, all three skip classes as above.
    #
    # == Identity
    #
    # urn = urn:nabu:edcs:<digits of the EDCS-ID> — "EDCS-24700151" →
    # …:24700151, the digits verbatim (leading zeros kept; 3 ids carry 7
    # digits, the rest 8). Every record's id matches EDCS-\d+; an id that
    # does not is unrecognized (loud), never guessed.
    #
    # == Text layers
    #
    # The raw "inscription" — EDCS's own edition text with its Leiden-ish
    # markup: (expansions), [restorations], [[erasures]], {superfluous},
    # <corrections>, "/" line and "//" part breaks, digits for lacuna
    # length — IS the passage text (canonical means canonical). SDAM's two
    # final cleanings ride verbatim as annotations: clean_text_conservative
    # (abbreviations unexpanded, restorations dropped) and
    # clean_text_interpretive_word (abbreviations expanded, restorations
    # kept). text_normalized is minted from the interpretive layer (else
    # the raw text) — the open-etruscan documented derivation: "D(ecimi)"
    # searches as "decimi", "Piis/simo" as "piissimo". The intermediate
    # inscription_*_cleaning fields are not carried: the interpretive one
    # equals clean_text_interpretive_word wherever it exists (34 records
    # lack it, never the clean_text field), the conservative one is the
    # pre-correction draft of clean_text_conservative (1,166 differ).
    # One passage per inscription: "//" separates faces, fragments and
    # the halves of bilinguals with no consistent reading, and SDAM's
    # cleanings run over the whole record — splitting would misalign them.
    #
    # == Language by script (the EDH/EDR per-passage rule, whole-record)
    #
    # Greek letters outnumbering Latin ones → grc (18,477 documents), else
    # lat (495,304; ~1,066 records mixing both scripts stay lat — the
    # Latin is the larger half).
    # The dump's own "language" field (8,327 records: GR, PU, IB, OS, ET,
    # HE, PA…) flags a part EDCS does NOT transcribe — 6,927 of those
    # records carry no text at all, and the rest transcribe only the Latin
    # half — so it rides verbatim as metadata + the other_language facet,
    # never as the document's language.
    #
    # == Axes (the aggressive-mining law)
    #
    # dates — SDAM's date_not_before/date_not_after envelope (the min/max
    #   over EDCS's dating parts; signed years, negative = BCE, no year 0
    #   in the file) as the :structured "date" hash, raw_dating verbatim as
    #   raw (196,743 documents dated). dating_from/dating_to (the
    #   first part only) are subsumed by raw. 12 reversed pairs ride
    #   verbatim; the builder's REORDER swaps them.
    # places — the findspot name ("place", modern / ancient names joined
    #   " / " by EDCS) as "ancient" (504,102 documents), the latitude/
    #   longitude pair as "geo" (500,229). EDCS's "?" names nothing; its
    #   pair still places (504,391 placed in all).
    # kind — inscr_type (16 EDCS genus labels, string or list; 391,232
    #   documents) → the genre facet, folded in config/kind_map.yml.
    # facets — status_notation → social, material, province, inscr_process
    #   → execution (stamped, erased), language → other_language.
    # Also carried: publication (the CIL/AE concordance — its first item
    # titles the document), partner_link verbatim + the EDH ids in it,
    # photo (EDCS's image page; never fetched), comment, extra_text. The
    # "status" string is the concatenation of the facet fields and is not
    # carried twice.
    #
    # == License
    #
    # The Zenodo record's license field is cc-by-4.0 → attribution. EDCS
    # itself publishes no bulk licence; the deposit's grant is the one this
    # snapshot is ingested under, credited to EDCS and SDAM together.
    #
    # == fetch / sync policy
    #
    # FileFetch in stream mode (465 MB never buffers in memory), the pins
    # checked BETWEEN download and any tree mutation: sha256 (computed on
    # the census download) and Zenodo's published md5. Zenodo files are
    # immutable and SDAM's scrape is frozen — a mismatch is corruption or
    # a new deposit, an owner re-pin. Parse streams too: discover walks the
    # array once with Nabu::JsonArraySplitter and each ref carries its
    # record's byte offset/length, so parse reads and JSON-parses exactly
    # one record (the okhc offset pattern).
    class Edcs < Nabu::Adapter
      RECORD_URL = "https://zenodo.org/records/7072337"
      FILENAME = "EDCS_text_cleaned_2022-09-12.json"
      FILE_URL = "#{RECORD_URL}/files/#{FILENAME}?download=1".freeze

      # The frozen pins of the v2.0 deposit file (census download
      # 2026-11-28; the md5 is Zenodo's own checksum field).
      SIZE = 465_523_658
      MD5 = "7ee22c65f442d54ba3537955603cc0ba"
      SHA256 = "5ecdb22311eb48c4d522212896cc828905f959c766ae57c89f49e069b5899d2a"

      URN_PREFIX = "urn:nabu:edcs:"
      ID_PATTERN = /\AEDCS-(\d+)\z/
      EDH_ID = /\AHD\d{6}\z/
      SIGNED_YEAR = /\A-?\d+\z/
      COORDINATE = /\A-?\d+(?:\.\d+)?\z/
      # EDCS's own "place unknown".
      UNKNOWN_PLACE = "?"

      # The annotation layers, verbatim upstream keys (class note).
      LAYERS = %w[clean_text_conservative clean_text_interpretive_word].freeze

      # The skip-by-rule classes, in the order the census notes name them.
      SKIP_NOTES = {
        no_inscription: ["record without an inscription", "records without an inscription"],
        no_letter: ["inscription without a letter (EDCS \"?\": text not given)",
                    "inscriptions without a letter (EDCS \"?\": text not given)"],
        duplicate: ["repeated copy of an earlier record", "repeated copies of earlier records"]
      }.freeze

      MANIFEST = Nabu::SourceManifest.new(
        id: "edcs",
        name: "EDCS — Epigraphik-Datenbank Clauss-Slaby (SDAM cleaned dump, Zenodo 7072337)",
        license: "CC BY 4.0 (Zenodo record 7072337 license field cc-by-4.0, version 2.0, 2022-09-12) — " \
                 "a cleaned scrape of db.edcs.eu by the SDAM project (Aarhus University; Petra " \
                 "Heřmánková); texts and metadata © the Epigraphik-Datenbank Clauss-Slaby (Manfred " \
                 "Clauss, Anne Kolb, Wolfgang A. Slaby, Barbara Woitas et al.), credited with SDAM",
        license_class: "attribution",
        upstream_url: RECORD_URL,
        parser_family: "edcs-json"
      )

      def self.manifest
        MANIFEST
      end

      # HEAD the deposit file against the .file-fetch.json pin. No
      # probe-shaped license endpoint (the Zenodo API record body carries
      # volatile stats — the diorisis false-alarm lesson).
      def self.remote_probe_strategy = :http_zip

      def self.http_probe_targets
        [Nabu::Adapter::HttpProbeTarget.new(
          label: FILENAME, zip_url: FILE_URL, metadata_url: nil,
          state_subdir: "", state_file: FileFetch::STATE_FILE
        )]
      end

      def self.urn_for(edcs_id)
        digits = ID_PATTERN.match(edcs_id.to_s)&.[](1)
        digits && "#{URN_PREFIX}#{digits}"
      end

      # The documented text_normalized derivation (class note).
      def self.search_source(text, annotations)
        annotations["clean_text_interpretive_word"] || text
      end

      # Greek letters outnumbering Latin ones → grc, else lat (class note).
      def self.language_for(text)
        text.scan(/\p{Greek}/).size > text.scan(/\p{Latin}/).size ? "grc" : "lat"
      end

      # The sha keywords exist for the WebMock'd fetch tests; real syncs
      # keep the frozen pins.
      def initialize(sha256: SHA256, md5: MD5)
        super()
        @sha256 = sha256
        @md5 = md5
      end

      # One ref per text-bearing record with an unseen id, in file order;
      # the ref carries the record's byte offset/length. A workdir without
      # the dump yields nothing (the day-one pre-fetch state).
      def discover(workdir)
        return enum_for(:discover, workdir) unless block_given?

        walk(workdir) do |verdict, record, offset, length|
          next unless verdict == :document

          yield Nabu::DocumentRef.new(
            source_id: manifest.id, id: self.class.urn_for(record.fetch("EDCS-ID")),
            path: dump_path(workdir), metadata: { "offset" => offset, "length" => length }
          )
        end
      end

      # The discovery census: the three skip-by-rule classes counted with
      # their notes; an id outside EDCS-\d+ is unrecognized.
      def discovery_skips(workdir)
        counts = Hash.new(0)
        unrecognized = []
        walk(workdir) do |verdict, record, _offset, _length|
          case verdict
          when :document then next
          when :unrecognized then unrecognized << "#{record['EDCS-ID'].inspect}: not an EDCS-<digits> id"
          else counts[verdict] += 1
          end
        end
        notes = SKIP_NOTES.filter_map do |verdict, (one, many)|
          count = counts[verdict]
          "#{count} #{count == 1 ? one : many}" if count.positive?
        end
        Nabu::Adapter::DiscoverySkips.new(skipped_by_rule: counts.values.sum, unrecognized: unrecognized.size,
                                          notes: notes + unrecognized)
      end

      def parse(document_ref)
        record = read_record(document_ref)
        urn = self.class.urn_for(record["EDCS-ID"])
        unless urn == document_ref.id
          raise ParseError, "#{document_ref.path}: record at #{document_ref.metadata['offset']} is #{urn}, " \
                            "expected #{document_ref.id}"
        end

        build_document(record, document_ref)
      rescue JSON::ParserError, ValidationError => e
        raise ParseError, "#{document_ref.path}: #{document_ref.id}: #{e.message}"
      end

      # Download (streamed) + verify both pins + land, phases hand-driven
      # so the pins are checked before any tree mutation; a 304 replays the
      # stored pin and touches nothing.
      def fetch(workdir, progress: nil, force: false)
        fetch = FileFetch.new(url: FILE_URL, dir: workdir, filename: FILENAME,
                              attic_dir: File.join(workdir, ATTIC_DIRNAME), progress: progress, stream: true)
        begin
          fetch.prepare!
          verify_pins!(fetch)
          guard_mass_deletion!(workdir, fetch.doomed_paths, force: force)
          fetch.complete!
        ensure
          fetch.cleanup!
        end
        Nabu::FetchReport.new(sha: fetch.sha, fetched_at: Time.now, notes: fetch_notes(fetch))
      rescue FileFetch::Error, JsonArraySplitter::Error => e
        raise Nabu::FetchError, "edcs fetch failed into #{workdir}: #{e.message}"
      end

      private

      def dump_path(workdir) = File.expand_path(File.join(workdir, FILENAME))

      # Every record of the dump with its verdict — :document, a skip class,
      # or :unrecognized — and its byte location.
      def walk(workdir)
        path = dump_path(workdir)
        return unless File.file?(path)

        seen = Set.new
        SourceRead.binary_file(path) do |io|
          JsonArraySplitter.new(path).each do |offset, length|
            record = JSON.parse(SourceRead.utf8_at(io, offset: offset, length: length, label: path))
            yield verdict(record, seen), record, offset, length
          end
        end
      end

      def verdict(record, seen)
        id = record["EDCS-ID"]
        return :unrecognized unless ID_PATTERN.match?(id.to_s)

        text = record["inscription"]
        return :no_inscription unless text.is_a?(String)
        return :no_letter unless text.match?(/\p{L}/)
        return :duplicate unless seen.add?(id)

        :document
      end

      def read_record(document_ref)
        SourceRead.binary_file(document_ref.path) do |io|
          JSON.parse(SourceRead.utf8_at(io, offset: document_ref.metadata.fetch("offset"),
                                            length: document_ref.metadata.fetch("length"),
                                            label: document_ref.path))
        end
      end

      # -- document building ---------------------------------------------------

      def build_document(record, document_ref)
        text = Normalize.nfc(record.fetch("inscription"))
        language = self.class.language_for(text)
        annotations = layer_annotations(record)
        document = Nabu::Document.new(
          urn: document_ref.id, language: language, title: title(record),
          canonical_path: document_ref.path, metadata: record_metadata(record)
        )
        document << Nabu::Passage.new(
          urn: "#{document_ref.id}:1", language: language, text: text,
          text_normalized: Normalize.search_form(self.class.search_source(text, annotations), language: language),
          annotations: annotations, sequence: 0
        )
        document
      end

      def layer_annotations(record)
        LAYERS.each_with_object({}) do |key, annotations|
          value = string(record[key])
          annotations[key] = Normalize.nfc(value) if value
        end
      end

      # The first concordance item ("CIL 01, 02650 (p 1097)"), else the id.
      def title(record)
        string(record["publication"].to_s.split(" = ").first) || record.fetch("EDCS-ID")
      end

      def record_metadata(record)
        metadata = { "edcs_id" => record.fetch("EDCS-ID") }
        %w[publication partner_link photo comment language extra_text].each do |key|
          value = string(record[key])
          metadata[key] = Normalize.nfc(value) if value
        end
        edh = edh_ids(record["partner_link"])
        metadata["edh_ids"] = edh unless edh.empty?
        date = date(record)
        metadata["date"] = date if date
        place = place(record)
        metadata["place"] = place if place
        facets = facets(record)
        metadata["facets"] = facets unless facets.empty?
        metadata
      end

      def edh_ids(link)
        string(link).to_s.sub(/\A.*param=/, "").split(";").map(&:strip).grep(EDH_ID).uniq
      end

      # SDAM's envelope, raw_dating verbatim (class note); a bound that is
      # absent or not a signed integer mints nothing, year 0 neither.
      def date(record)
        not_before = year(record["date_not_before"])
        not_after = year(record["date_not_after"])
        return nil if not_before.nil? && not_after.nil?

        date = { "not_before" => not_before, "not_after" => not_after }.compact
        raw = string(record["raw_dating"])
        date["raw"] = raw if raw
        date
      end

      def year(value)
        text = string(value)
        return nil unless text&.match?(SIGNED_YEAR)

        year = Integer(text, 10)
        year.zero? ? nil : year
      end

      def place(record)
        place = {}
        name = string(record["place"])
        place["ancient"] = Normalize.nfc(name) if name && name != UNKNOWN_PLACE
        lat = string(record["latitude"])
        lon = string(record["longitude"])
        place["geo"] = "#{lat}, #{lon}" if lat&.match?(COORDINATE) && lon&.match?(COORDINATE)
        place.empty? ? nil : place
      end

      def facets(record)
        facets = {}
        { "genre" => "inscr_type", "social" => "status_notation", "execution" => "inscr_process" }.each do |facet, key|
          values = strings(record[key])
          facets[facet] = { "values" => values } unless values.empty?
        end
        { "material" => "material", "province" => "province" }.each do |facet, key|
          value = string(record[key])
          facets[facet] = { "value" => Normalize.nfc(value) } if value
        end
        languages = string(record["language"]).to_s.split(/\s*,\s*/).reject(&:empty?).uniq
        facets["other_language"] = { "values" => languages } unless languages.empty?
        facets
      end

      # A string value, stripped; "{}" (pandas' empty) and blanks are nil.
      def string(value)
        return nil unless value.is_a?(String)

        text = value.strip
        text.empty? ? nil : text
      end

      def strings(value)
        items = value.is_a?(Hash) ? [] : Array(value)
        items.filter_map { |item| string(item) }.map { |item| Normalize.nfc(item) }.uniq
      end

      # -- fetch ---------------------------------------------------------------

      def verify_pins!(fetch)
        return if fetch.not_modified? || (fetch.sha == @sha256 && fetch.md5 == @md5)

        raise Nabu::FetchError,
              "edcs: the downloaded deposit misses its pins (sha256 #{fetch.sha} vs #{@sha256}, md5 " \
              "#{fetch.md5} vs #{@md5}; #{SIZE} bytes expected) — Zenodo files are immutable and the " \
              "SDAM scrape is frozen at 2022-09-12, so this is corruption or a new deposit; read " \
              "#{RECORD_URL} and re-pin (owner decision)"
      end

      def fetch_notes(fetch)
        base = fetch.not_modified? ? "not modified (304)" : "zenodo record 7072337 sha256 + md5 pins verified"
        [base, attic_notes(fetch.atticked)].compact.join("; ")
      end
    end
  end
end

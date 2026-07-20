# frozen_string_literal: true

require "json"

require_relative "ebl_atf_parser"
require_relative "cdli"
require_relative "../file_fetch"

module Nabu
  module Adapters
    # The eBL Fragmentarium adapter (P31-3): the Electronic Babylonian
    # Library's transliterated museum fragments — the Kuyunjik/Babylon
    # tablet mass behind the ebl.lmu.de Fragmentarium — through the atf
    # family's eBL-ATF dialect (EblAtfParser).
    #
    # == Upstream: the citable Zenodo snapshot, honestly 2023-10-18
    #
    # Bootstrap = Zenodo record 10018951 (DOI 10.5281/zenodo.10018951,
    # published 2023-10-18): ONE fragments.json (73,854,507 B, Zenodo md5
    # 71538e2d86c8ba6d47f499892bb3e5d3 verified byte-for-byte at fixture
    # time, sha256-pinned below) — a single-line JSON array of 23,289
    # fragment objects, every one carrying a non-empty eBL-ATF "atf" field
    # (the record packages TRANSLITERATED fragments only; the live
    # Fragmentarium had 37,296 at scout time). The record's companion zip is
    # the MIT-licensed retrieval code, not data — never fetched. The
    # sanctioned refresh channel is the ebl.lmu.de/api/fragments/
    # retrieve-all endpoint (4-8 min per batch): OWNER-FIRED only,
    # documented in docs/02-sources.md, deliberately never wired.
    #
    # == License: two upstream claims, recorded verbatim, held at nc
    #
    # The JOHD data paper (10.5334/johd.148, 2024) License section:
    #   "eBL fragments Python code: MIT License
    #    Data (fragments.json): Attribution-NonCommercial-ShareAlike 4.0
    #    International (CC BY-NC-SA 4.0)."
    # The Zenodo record's own license field: cc-by-4.0.
    # The claims conflict; the class stays nc (the conservative reading)
    # until owner email №24 resolves it — photographs need per-institution
    # consent and are entirely out of scope (never fetched).
    #
    # == Identity and grain
    #
    # Document = the museum-number fragment: urn:nabu:ebl:k.11360 (urn_for
    # is the ONE minting rule — NFC, downcased, whitespace → "." for the
    # one "U.7321 ?" id; "," and "?" ride verbatim). Passage = the line
    # within face/column, the family grain. The one byte-identical
    # duplicate _id at the snapshot (K.5808) skips by rule, first wins.
    # 66 fragments whose atf carries only state/structure lines parse to
    # zero-passage documents ("text_layer" => "none", the metadata-only
    # precedent); upstream's three workflow test fragments
    # (Test.Fragment &c.) are catalogued as the data honestly is.
    #
    # == Catalog metadata → metadata, facets, edges
    #
    # script.period (closed 14-value vocabulary, "None" = upstream's
    # no-value sentinel) / genres (hierarchical category paths, first path
    # facets as "A/B/C") / collection / museum → facets. The structured
    # king-year "date" field (39 fragments) and "datesInText" ride
    # verbatim — too thin for a timeline extractor (census verdict; period
    # names carry no year envelopes, so no CdliDates sibling is minted).
    # externalNumbers ride verbatim; edges minted per the P25-1
    # edge-worthiness rule: cdliNumber (18,610 = 79.9% of fragments) →
    # urn:nabu:cdli:p… through Cdli.urn_for (dangling-but-stable into the
    # P31-2 space), editedInOraccProject + cdliNumber → urn:nabu:oracc:
    # <project>:<P> (the ORACC id IS the CDLI number), bdtnsNumber →
    # "bdtns:<n>" (the CDLI concordance space); unschemed numbers
    # (bmIdNumber &c.) stay metadata. NOT carried: "record" (edit-workflow
    # history), "signs" (the sign-reading layer is NOT reliably
    # line-aligned — 2,169 of 23,222 misalign against the text lines, so
    # per-line attachment would lie; it stays in canonical for a future
    # enrichment), "joins" (empty on every snapshot fragment).
    #
    # == Language and lemma honesty
    #
    # No language field exists; eBL-ATF's own default is Akkadian, and the
    # first text line's %-shift decides sux docs (EblAtfParser class note).
    # #lem exists on ONE fragment (71 lines, BM.47447) — carried verbatim
    # as line annotations, nothing reaches the lemma index; sources.yml
    # pins lemma_tier: silver defensively (the cdli discipline).
    class Ebl < Nabu::Adapter
      SNAPSHOT_URL = "https://zenodo.org/records/10018951/files/fragments.json"
      FILENAME = "fragments.json"

      # sha256 of the 73,854,507-byte fragments.json, computed from the
      # 2026-07-19 census download whose md5 matched the Zenodo record's
      # published checksum (71538e2d86c8ba6d47f499892bb3e5d3) exactly.
      SNAPSHOT_SHA256 = "4e970d8713315ca9559fb9dfd79956d5b19b1debb9941c22f8bed0339745d753"

      URN_PREFIX = "urn:nabu:ebl:"

      # Both upstream license claims, verbatim (class note).
      LICENSE_JOHD = "Data (fragments.json): Attribution-NonCommercial-ShareAlike 4.0 " \
                     "International (CC BY-NC-SA 4.0)."
      MANIFEST = Nabu::SourceManifest.new(
        id: "ebl",
        name: "eBL Fragmentarium — Electronic Babylonian Library transliterated fragments " \
              "(Zenodo 10018951 snapshot, 2023-10-18)",
        license: "CONFLICTING upstream claims, both verbatim: the JOHD data paper " \
                 "(10.5334/johd.148) License section says \"#{LICENSE_JOHD}\" while the " \
                 "Zenodo record 10018951 license field says cc-by-4.0 — held at nc until " \
                 "email №24 resolves it; photographs out of scope entirely",
        license_class: "nc",
        upstream_url: "https://doi.org/10.5281/zenodo.10018951",
        parser_family: "atf"
      )

      # %-shift codes → stored codes (the ebl-atf.md shift table; consulted
      # only for a first text line's LEADING shift — EblAtfParser class
      # note). Every Akkadian variety folds to akk; %sux and %es (Emesal, a
      # Sumerian register with no ISO code of its own) to sux; the Greek-
      # script varieties keep their language. Unmapped (%su typo, 1
      # fragment) falls to the akk default, verbatim kept.
      SHIFT_LANGUAGES = {
        "sux" => "sux", "SUX" => "sux", "es" => "sux", "suxgrc" => "sux",
        "n" => "akk", "ma" => "akk", "mb" => "akk", "na" => "akk", "nb" => "akk",
        "lb" => "akk", "sb" => "akk", "a" => "akk", "akk" => "akk", "eakk" => "akk",
        "oakk" => "akk", "ur3akk" => "akk", "oa" => "akk", "ob" => "akk",
        "akkgrc" => "akk"
      }.freeze

      # Catalog string fields carried into document metadata verbatim
      # (non-empty, NFC).
      STRING_FIELDS = %w[description publication collection museum accession].freeze

      # Upstream's explicit no-value sentinel in script fields.
      NONE_SENTINEL = "None"

      def self.manifest
        MANIFEST
      end

      # urn:nabu:ebl:k.11360 from the museum-number _id — the ONE minting
      # rule (NFC, downcase, whitespace runs → ".").
      def self.urn_for(id)
        "#{URN_PREFIX}#{Normalize.nfc(id.to_s.strip).downcase.gsub(/\s+/, '.')}"
      end

      # cdliNumber / editedInOraccProject / bdtnsNumber concordances
      # (class note).
      def self.reference_edges? = true

      def self.reference_producer(catalog:, journal:)
        LibraryReferences.new(catalog: catalog, journal: journal, producer: "ebl")
      end

      # HEAD the Zenodo artifact: reachability + Last-Modified drift against
      # the .file-fetch.json pin. metadata_url nil — the Zenodo API body
      # carries volatile stats that would false-alarm (the tlhdig/diorisis
      # lesson); the license field re-reads at any real refetch.
      def self.remote_probe_strategy = :http_zip

      def self.http_probe_targets
        [Nabu::Adapter::HttpProbeTarget.new(
          label: FILENAME, zip_url: SNAPSHOT_URL, metadata_url: nil,
          state_subdir: "", state_file: Nabu::FileFetch::STATE_FILE
        )]
      end

      # +pin+ overrides the snapshot sha (tests; a deliberate owner re-pin).
      def initialize(pin: SNAPSHOT_SHA256)
        super()
        @pin = pin
        @index_cache = {}
      end

      # One ref per fragment, sorted by urn; the K.5808 byte-identical twin
      # skips by rule (first wins). A pre-fetch workdir yields nothing.
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        index(workdir)[:refs].each(&block)
      end

      def discovery_skips(workdir)
        DiscoverySkips.new(skipped_by_rule: index(workdir)[:duplicates])
      end

      def parse(document_ref)
        fragment = fragment_for(document_ref)
        parser.parse(
          fragment.fetch("atf").to_s, urn: document_ref.id, path: document_ref.path,
                                      title_fallback: Normalize.nfc(fragment.fetch("_id")),
                                      metadata: fragment_metadata(fragment)
        )
      rescue ValidationError => e
        raise ParseError, "#{document_ref.path}: #{document_ref.id}: #{e.message}"
      end

      # FileFetch with the phases driven by hand so the sha pin is checked
      # BETWEEN download and any tree mutation (the tlhdig choreography); a
      # 304 replays the stored pin and touches nothing.
      def fetch(workdir, progress: nil, force: false)
        fetch = Nabu::FileFetch.new(url: SNAPSHOT_URL, dir: workdir, filename: FILENAME,
                                    attic_dir: File.join(workdir, ATTIC_DIRNAME), progress: progress)
        fetch.prepare!
        verify_pin!(fetch)
        guard_mass_deletion!(workdir, fetch.doomed_paths, force: force)
        fetch.complete!
        Nabu::FetchReport.new(sha: fetch.sha, fetched_at: Time.now, notes: fetch_notes(fetch))
      rescue FileFetch::Error => e
        raise Nabu::FetchError, "ebl fetch failed into #{workdir}: #{e.message}"
      end

      private

      def verify_pin!(fetch)
        return if fetch.not_modified? || fetch.sha == @pin

        raise Nabu::FetchError,
              "ebl: downloaded fragments.json misses the sha256 pin (expected #{@pin}, " \
              "got #{fetch.sha}) — the Zenodo versioned deposit is immutable, so this is " \
              "corruption or tampering; verify #{SNAPSHOT_URL} against the record before re-pinning"
      end

      def fetch_notes(fetch)
        base = fetch.not_modified? ? "not modified (304)" : "Zenodo 10018951 sha pin verified"
        [base, attic_notes(fetch.atticked)].compact.join("; ")
      end

      # -- discovery index ------------------------------------------------------

      def snapshot_path(workdir) = File.expand_path(File.join(workdir, FILENAME))

      def index(workdir)
        path = snapshot_path(workdir)
        return { refs: [], duplicates: 0 } unless File.file?(path)

        @index_cache[path] ||= build_index(path)
      end

      def build_index(path)
        refs = {}
        duplicates = 0
        fragments(path).each_with_index do |fragment, position|
          urn = self.class.urn_for(fragment.fetch("_id"))
          if refs.key?(urn)
            duplicates += 1 # first block wins, the house rule
          else
            refs[urn] = Nabu::DocumentRef.new(source_id: manifest.id, id: urn, path: path,
                                              metadata: { "index" => position })
          end
        end
        { refs: refs.values.sort_by!(&:id), duplicates: duplicates }
      end

      # The parsed snapshot array, cached per path (73.9 MB is read once per
      # sync, never per parse).
      def fragments(path)
        @fragments ||= {}
        @fragments[path] ||= JSON.parse(File.read(path))
      rescue JSON::ParserError => e
        raise ParseError, "#{path}: fragments.json is not valid JSON: #{e.message}"
      end

      def fragment_for(document_ref)
        fragments(document_ref.path).fetch(document_ref.metadata.fetch("index"))
      end

      def parser
        EblAtfParser.new(language_map: SHIFT_LANGUAGES, default_language: "akk")
      end

      # -- catalog metadata -----------------------------------------------------

      def fragment_metadata(fragment)
        metadata = {}
        string_fields(fragment, metadata)
        script_fields(fragment, metadata)
        structured_fields(fragment, metadata)
        facets = build_facets(fragment)
        metadata["facets"] = facets unless facets.empty?
        related = related_edges(fragment)
        metadata["related"] = related unless related.empty?
        metadata
      end

      def string_fields(fragment, metadata)
        STRING_FIELDS.each do |field|
          value = fragment[field].to_s.strip
          metadata[field] = Normalize.nfc(value) unless value.empty?
        end
        notes = fragment.dig("notes", "text").to_s.strip
        metadata["notes"] = Normalize.nfc(notes) unless notes.empty?
        introduction = fragment.dig("introduction", "text").to_s.strip
        metadata["introduction"] = Normalize.nfc(introduction) unless introduction.empty?
      end

      def script_fields(fragment, metadata)
        script = fragment["script"] || {}
        period = script["period"].to_s.strip
        metadata["period"] = period unless period.empty? || period == NONE_SENTINEL
        modifier = script["periodModifier"].to_s.strip
        metadata["period_modifier"] = modifier unless modifier.empty? || modifier == NONE_SENTINEL
        metadata["script_uncertain"] = true if script["uncertain"] == true
      end

      def structured_fields(fragment, metadata)
        metadata["genres"] = fragment["genres"] unless Array(fragment["genres"]).empty?
        metadata["projects"] = fragment["projects"] unless Array(fragment["projects"]).empty?
        oracc = fragment["editedInOraccProject"].to_s.strip
        metadata["edited_in_oracc"] = oracc unless oracc.empty?
        metadata["date"] = fragment["date"] if fragment["date"]
        metadata["dates_in_text"] = fragment["datesInText"] unless Array(fragment["datesInText"]).empty?
        numbers = external_numbers(fragment)
        metadata["external_numbers"] = numbers unless numbers.empty?
        dimensions = dimensions_of(fragment)
        metadata["dimensions"] = dimensions unless dimensions.empty?
      end

      def external_numbers(fragment)
        (fragment["externalNumbers"] || {}).reject { |_scheme, value| value.to_s.strip.empty? }
      end

      def dimensions_of(fragment)
        %w[width length thickness].each_with_object({}) do |side, dimensions|
          value = fragment.dig(side, "value")
          dimensions[side] = value if value
        end
      end

      def build_facets(fragment)
        facets = {}
        { "period" => period_facet(fragment), "genre" => genre_facet(fragment),
          "collection" => fragment["collection"], "museum" => fragment["museum"] }.each do |facet, value|
          value = value.to_s.strip
          facets[facet] = { "value" => Normalize.nfc(value) } unless value.empty?
        end
        facets
      end

      def period_facet(fragment)
        period = fragment.dig("script", "period").to_s.strip
        period == NONE_SENTINEL ? nil : period
      end

      # The first genre's category path, the corpus's own hierarchy
      # ("ARCHIVAL/Administrative/Receipts"); all genres ride metadata.
      def genre_facet(fragment)
        first = Array(fragment["genres"]).first
        first && Array(first["category"]).join("/")
      end

      # The P25-1 edge-worthiness rule (class note): schemed concordances
      # mint edges, bare strings stay metadata.
      def related_edges(fragment)
        numbers = external_numbers(fragment)
        related = []
        if (cdli = numbers["cdliNumber"])
          related << Cdli.urn_for(cdli)
          oracc = fragment["editedInOraccProject"].to_s.strip
          related << "urn:nabu:oracc:#{oracc}:#{cdli}" unless oracc.empty?
        end
        related << "bdtns:#{numbers['bdtnsNumber']}" if numbers["bdtnsNumber"]
        related.uniq
      end
    end
  end
end

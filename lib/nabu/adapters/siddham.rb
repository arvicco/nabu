# frozen_string_literal: true

require_relative "siddham_epidoc_parser"
require_relative "../eras"
require_relative "../zip_fetch"

module Nabu
  module Adapters
    # Siddham (P118-4): the Siddham Epigraphic Archive texts — Dániel
    # Balogh's EpiDoc editions of early historic Indian epigraphy (the
    # Gupta, Vākāṭaka, Aulikara, Parivrājaka/Uccakalpa, Maitraka-age
    # corpus), archived on Zenodo before ingestion into the siddham.network
    # database. The 2019-02-21 version is "the complete collection of
    # siddham editions prepared offline": 427 editions, all san-Latn.
    #
    # == Upstream (censused 2026-10-11)
    #
    # Zenodo record 2574901, file "Siddham Texts Archive 20190221.zip"
    # (1,210,929 B; md5 741d7331… = the record's published checksum): a
    # FLAT zip of 427 IN<5 digits>_TEI.xml editions + tei-epidoc.rng (the
    # schema) + a stray desktop.ini — both censused skip-by-rule. The
    # record says it outright: the TEI headers are "blank (except for
    # title and ID number) and added for validation purposes only;
    # metadata prepared offline are archived separately in the form of
    # spreadsheets" (not in this record). So: NO in-file licence, NO
    # origDate/origPlace, and NO translation divs (the census found only
    # div[@type=edition]) — the edition text is the whole asset.
    #
    # == License (record-level)
    #
    # The Zenodo RECORD declares cc-by-sa-4.0 (API-read 2026-10-11); with
    # blank headers the record's grant is the basis — recorded verbatim at
    # source level and per document. → class `attribution`.
    #
    # == Identity and grain
    #
    # urn:nabu:siddham:<IN-number> (the file stem sans "_TEI", case kept —
    # the archive's own id, equal to every file's <idno type="filename">);
    # passage = the physical line, :<lb n> verbatim (siddham-epidoc).
    #
    # == Dating (aggressive mining, honest scope)
    #
    # With blank headers the only date matter in the asset is the English
    # TITLE (census of 427): 9 carry an ERA-TYPED year ("GE 98" — the
    # Gupta era) → converted through the shared era table (config/eras.yml,
    # Nabu::Eras: GE Y → CE [Y+319, Y+320]); 4 carry a century
    # attribution ("of the 5th Century" → 401–500); ~88 carry an UNTYPED
    # "year N" (regnal, or an era the title does not name — the
    # Parivrājaka charters' years are Gupta-era by scholarly consensus,
    # but the title does not say so) → recorded raw as "title_year",
    # NEVER converted. The edition TEXT's own dating formulae
    # (saṃvatsare 90 8, gupta-nṛpa-rājya-bhuktau) are a future extractor
    # story, deliberately out of scope here.
    #
    # == Fetch
    #
    # ZipFetch, phases hand-driven so the hard sha256 pin verifies BETWEEN
    # download and any tree mutation (the rem choreography); the flat zip
    # unpacks onto the workdir root as upstream's own tree (a plain tree
    # hashes whole — no materialized_paths needed, Q59-a acts only inside
    # git repos). Zenodo files are immutable: a pin miss is corruption or
    # a re-release — an owner re-pin decision.
    class Siddham < Nabu::Adapter
      RECORD_URL = "https://zenodo.org/records/2574901"
      ZIP_URL = "https://zenodo.org/api/records/2574901/files/" \
                "Siddham%20Texts%20Archive%2020190221.zip/content"

      # sha256 of the 1,210,929-byte 2019-02-21 deposit, pinned from the
      # 2026-10-11 download (md5 cross-checked against the record).
      ZIP_SHA256 = "f9ebbf9938f6357daac3e12c0467db7ff1fe13d2b85e3130024318474694ac73"

      LICENSE = "CC BY-SA 4.0 — the Zenodo record's license field (record 2574901, " \
                "\"cc-by-sa-4.0\", API-read 2026-10-11); the TEI headers are deliberately " \
                "blank (title + idno only, no <availability>), so the record-level grant " \
                "is the basis. Cite: Dániel Balogh, Siddham Epigraphic Archive - Texts in " \
                "EpiDoc, version 20190221, Zenodo, doi:10.5281/zenodo.2574901."

      MANIFEST = Nabu::SourceManifest.new(
        id: "siddham",
        name: "Siddham Epigraphic Archive — texts in EpiDoc (Gupta-age Sanskrit epigraphy)",
        license: LICENSE,
        license_class: "attribution",
        upstream_url: RECORD_URL,
        parser_family: "siddham-epidoc",
        credit: "Dániel Balogh et al., Siddham — The Asian Inscription Database " \
                "(siddham.network); EpiDoc archive on Zenodo, doi:10.5281/zenodo.2574901"
      )

      FILE_PATTERN = /\AIN\d{5}_TEI\.xml\z/
      FILE_SUFFIX = "_TEI.xml"

      # The censused non-edition members of the zip (skip-by-rule).
      KNOWN_NON_EDITIONS = %w[tei-epidoc.rng desktop.ini].freeze

      # A title's century attribution ("of the 5th Century").
      CENTURY = /\b(\d{1,2})(?:st|nd|rd|th) Century\b/
      # An untyped title year ("year 156", "Year 50 (100?)").
      UNTYPED_YEAR = /\b[Yy]ear (\d+)(?: \(\d+\?\))?/
      # A candidate era-typed year: a capitalized token + a number, kept
      # only when the era table resolves the token ("GE 98").
      ERA_YEAR = /\b(\p{Lu}[\p{L}.]*) (\d+)\b/

      def self.manifest = MANIFEST

      def self.remote_probe_strategy = :http_zip

      def self.http_probe_targets
        [Nabu::Adapter::HttpProbeTarget.new(
          label: "Siddham Texts Archive 20190221.zip", zip_url: ZIP_URL, metadata_url: nil,
          state_subdir: "", state_file: Nabu::ZipFetch::STATE_FILE
        )]
      end

      # The title's date matter (class note): {"date" => …} for an
      # era-typed year or a century, {"title_year" => …} for an untyped
      # year; {} when the title carries none.
      def self.title_dating(title, eras: Nabu::Eras.default)
        era_date(title, eras) || century_date(title) || untyped_year(title) || {}
      end

      def self.era_date(title, eras)
        title.scan(ERA_YEAR) do |token, number|
          key = eras&.resolve(token) or next
          conversion = eras.to_ce(key, Integer(number, 10))
          return { "date" => conversion.to_date_bounds.merge(
            "raw" => "#{token} #{number}", "era" => key, "era_year" => conversion.year, "basis" => "title"
          ) }
        end
        nil
      end

      def self.century_date(title)
        match = CENTURY.match(title) or return nil
        century = Integer(match[1], 10)
        { "date" => { "not_before" => ((century - 1) * 100) + 1, "not_after" => century * 100,
                      "raw" => match[0], "basis" => "title" } }
      end

      def self.untyped_year(title)
        match = UNTYPED_YEAR.match(title) or return nil
        { "title_year" => { "raw" => match[0], "year" => Integer(match[1], 10) } }
      end

      # +pin+ overrides the release sha (tests; a future owner re-pin).
      def initialize(pin: ZIP_SHA256)
        super()
        @pin = pin
      end

      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        edition_names(workdir).each do |name|
          path = File.join(workdir, name)
          yield Nabu::DocumentRef.new(
            source_id: MANIFEST.id,
            id: "urn:nabu:siddham:#{name.delete_suffix(FILE_SUFFIX)}",
            path: File.expand_path(path),
            metadata: { "stem" => name.delete_suffix(FILE_SUFFIX) }
          )
        end
      end

      # The zip's schema and stray desktop.ini are known non-editions;
      # anything else unexpected is counted loud. Fetch state and the attic
      # are infrastructure, never census.
      def discovery_skips(workdir)
        return Nabu::Adapter::DiscoverySkips.new unless Dir.exist?(workdir)

        others = Dir.children(workdir).sort.reject { |name| name.start_with?(".") || FILE_PATTERN.match?(name) }
        known, unknown = others.partition { |name| KNOWN_NON_EDITIONS.include?(name) }
        Nabu::Adapter::DiscoverySkips.new(
          skipped_by_rule: known.size, unrecognized: unknown.size,
          notes: known.map { |name| "#{name}: archive schema/stray, not an edition" } +
                 unknown.map { |name| "#{name}: unrecognized member" }
        )
      end

      def parse(document_ref)
        result = SiddhamEpidocParser.parse(document_ref.path)
        document = Nabu::Document.new(
          urn: document_ref.id, language: result.language, canonical_path: document_ref.path,
          title: result.title || document_ref.metadata["stem"],
          metadata: document_metadata(result, document_ref)
        )
        result.passages.each_with_index do |unit, index|
          document << Nabu::Passage.new(urn: "#{document_ref.id}:#{unit.key}", language: result.language,
                                        text: unit.text, sequence: index, annotations: unit.annotations)
        end
        document
      rescue Nabu::ValidationError => e
        raise ParseError, "#{document_ref.path}: #{e.message}"
      end

      # Download + verify the hard sha pin + unpack, phases hand-driven so
      # the pin check runs BETWEEN download and any tree mutation; a 304
      # replays the stored pin and touches nothing.
      def fetch(workdir, progress: nil, force: false)
        zip = Nabu::ZipFetch.new(url: ZIP_URL, dir: workdir,
                                 attic_dir: File.join(workdir, ATTIC_DIRNAME), progress: progress)
        begin
          zip.prepare!
          verify_pin!(zip)
          guard_mass_deletion!(workdir, zip.doomed_paths, force: force)
          zip.complete!
        ensure
          zip.cleanup!
        end
        Nabu::FetchReport.new(sha: zip.sha, fetched_at: Time.now, notes: fetch_notes(zip))
      rescue ZipFetch::Error, Nabu::Shell::Error => e
        raise Nabu::FetchError, "siddham fetch failed into #{workdir}: #{e.message}"
      end

      private

      def edition_names(workdir)
        return [] unless Dir.exist?(workdir)

        Dir.children(workdir).grep(FILE_PATTERN).sort
      end

      def document_metadata(result, document_ref)
        {
          "siddham_id" => result.idno || document_ref.metadata["stem"],
          "license" => LICENSE,
          "textparts" => (result.textparts unless result.textparts.empty?)
        }.compact.merge(result.title ? self.class.title_dating(result.title) : {})
      end

      def verify_pin!(zip)
        return if zip.not_modified? || zip.sha == @pin

        raise Nabu::FetchError,
              "siddham: downloaded artifact misses the release sha256 pin (expected #{@pin}, got " \
              "#{zip.sha}) — Zenodo files are immutable, so this is corruption or an unannounced " \
              "re-release; verify #{ZIP_URL} and re-pin ZIP_SHA256 only after reading the record"
      end

      def fetch_notes(zip)
        [zip.not_modified? ? "not modified (304)" : "zenodo 20190221 sha pin verified",
         attic_notes(zip.atticked)].compact.join("; ")
      end
    end
  end
end

# frozen_string_literal: true

require_relative "bosworth_csv_parser"

module Nabu
  module Adapters
    # The Bosworth-Toller adapter (P12-3): An Anglo-Saxon Dictionary
    # (Bosworth & Toller + Supplement, bosworthtoller.com) from the official
    # LINDAT/CLARIAH-CZ data dump — the THIRD dictionary-shelf occupant
    # (architecture §11) and the first CSV dictionary (parser family
    # bosworth-csv; the lexica are TEI). Same content_kind :dictionary
    # routing, same DictionaryDocument/Entry model, dictionary slug
    # bosworth-toller, language ang, no betacode; citations start empty (B-T
    # cites OE works by short title without urns — the ISWOC/ASPR crosswalk
    # is future work, the resolution layer needs nothing new).
    #
    # == Upstream (verified page-level, docs/backlog.md P12-3 Phase A)
    #
    # LINDAT hdl 11234/1-3532 ("Bosworth-Toller's Anglo-Saxon Dictionary
    # online", data dump v0.1, 2021; Ondřej Tichý, Charles University — the
    # site's own maintainer). The ingested artifact is
    # bosworth_entries_export.csv (88,387,561 bytes, id;headword;body, UTF-8,
    # multi-line XML bodies); the deposit's SQL backup is out of scope. The
    # stable auth-free download is the DSpace bitstream /content URL below —
    # the old xmlui handle URLs serve the DSpace 7 Angular shell, not files.
    #
    # == License
    #
    # CC BY 4.0, verbatim from the record's metadata: dc.rights = "Creative
    # Commons - Attribution 4.0 International (CC BY 4.0)", dc.rights.uri =
    # http://creativecommons.org/licenses/by/4.0/ → license_class
    # "attribution", MCP-surface-safe. bosworthtoller.com itself shows no
    # readable license; the LINDAT deposit is the authoritative grant.
    #
    # == fetch / sync policy
    #
    # Single-file HTTP via Nabu::FileFetch (the ASPR path: conditional GET on
    # Last-Modified, sha256 pin, attic + mass-deletion guard). Upstream is a
    # frozen deposit (Last-Modified 2021-04-26, v0.1) → sync_policy: manual,
    # enabled: false until the owner-fired first real sync. The remote-health
    # probe HEADs the bitstream (:http_zip strategy); there is no
    # probe-shaped license endpoint (LINDAT's item JSON is DSpace metadata,
    # not a {"license": …} document), so the license row honestly reads
    # unchecked — license drift is caught by re-reading the record at any
    # real refetch.
    class BosworthToller < Nabu::Adapter
      MANIFEST = Nabu::SourceManifest.new(
        id: "bosworth-toller",
        name: "Bosworth-Toller — An Anglo-Saxon Dictionary (LINDAT dump)",
        license: "CC BY 4.0 (verbatim dc.rights of LINDAT hdl 11234/1-3532: \"Creative Commons - " \
                 "Attribution 4.0 International (CC BY 4.0)\"; data from bosworthtoller.com)",
        license_class: "attribution",
        upstream_url: "https://lindat.mff.cuni.cz/repository/server/api/core/bitstreams/" \
                      "3010b742-b2c4-4152-870a-716ce1652e7c/content",
        parser_family: "bosworth-csv"
      )

      FILENAME = "bosworth_entries_export.csv"
      DICTIONARY_SLUG = "bosworth-toller"
      LANGUAGE = "ang"
      TITLE = "An Anglo-Saxon Dictionary (Bosworth & Toller)"

      def self.manifest
        MANIFEST
      end

      # The routing declaration (architecture §11): entries, not passages —
      # SyncRunner/Rebuild load through Store::DictionaryLoader.
      def self.content_kind = :dictionary

      # The probe HEADs the bitstream itself: reachability + Last-Modified
      # drift vs the .file-fetch.json pin. metadata_url nil — see class note.
      def self.remote_probe_strategy = :http_zip

      def self.http_probe_targets
        [Nabu::Adapter::HttpProbeTarget.new(
          label: FILENAME, zip_url: MANIFEST.upstream_url, metadata_url: nil,
          state_subdir: "", state_file: Nabu::FileFetch::STATE_FILE
        )]
      end

      # One DocumentRef for the one CSV. A workdir without the file yields
      # nothing (the day-one pre-fetch state); the same walk works under the
      # attic (same relative shape), so retention costs nothing here.
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        Dir.glob(File.join(workdir, "**", FILENAME)).first(1).each do |path|
          yield Nabu::DocumentRef.new(
            source_id: manifest.id,
            id: "#{DICTIONARY_SLUG}:#{FILENAME}",
            path: File.expand_path(path),
            metadata: { "dictionary" => DICTIONARY_SLUG }
          )
        end
      end

      def parse(document_ref)
        document = Nabu::DictionaryDocument.new(
          slug: DICTIONARY_SLUG, language: LANGUAGE,
          title: TITLE, canonical_path: document_ref.path
        )
        BosworthCsvParser.new.entries(document_ref.path).each { |entry| document << entry }
        document
      rescue Nabu::ValidationError => e
        raise Nabu::ParseError, "bosworth-toller: #{document_ref.id}: #{e.message}"
      end

      # Download the single upstream CSV via FileFetch (conditional GET, sha
      # pin, attic + guard contract). No network in tests: WebMock stubs.
      def fetch(workdir, progress: nil, force: false)
        result = Nabu::FileFetch.sync!(
          url: manifest.upstream_url, dir: workdir, filename: FILENAME,
          attic_dir: File.join(workdir, ATTIC_DIRNAME), progress: progress,
          guard: ->(doomed) { guard_mass_deletion!(workdir, doomed, force: force) }
        )
        FetchReport.new(sha: result.sha, fetched_at: Time.now, notes: attic_notes(result.atticked))
      rescue FileFetch::Error => e
        raise Nabu::FetchError, "bosworth-toller fetch failed into #{workdir}: #{e.message}"
      end
    end
  end
end

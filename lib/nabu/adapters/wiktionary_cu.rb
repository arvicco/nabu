# frozen_string_literal: true

require_relative "wiktionary_jsonl_parser"

module Nabu
  module Adapters
    # The Wiktionary-OCS adapter (P13-10): English Wiktionary's Old Church
    # Slavonic entries via the kaikki.org wiktextract extraction — the
    # FOURTH dictionary-shelf occupant (architecture §11) and the first
    # JSONL dictionary (parser family wiktionary-jsonl; the lexica are TEI,
    # Bosworth-Toller CSV). Same content_kind :dictionary routing, same
    # DictionaryDocument/Entry model, dictionary slug wiktionary-cu,
    # language chu, no betacode; citations start empty (Wiktionary's
    # quotations are unanchored). Etymology text is KEPT in entry bodies —
    # it carries the Proto-Slavic/PIE reconstruction chains the future
    # reconstruction shelf will join on (improvements register, P13-10 (b)).
    #
    # == Upstream (verified page-level + ranged reads, docs/backlog.md P13-10 Phase A)
    #
    # https://kaikki.org/dictionary/Old%20Church%20Slavonic/ — "4548
    # distinct words", built from the enwiktionary dump dated 2026-07-06
    # (wiktextract, Tatu Ylönen). The ingested artifact is the postprocessed
    # per-language JSONL below (46,091,411 bytes at fixture time, 4,615
    # lines, one JSON object per line).
    #
    # DEPRECATION CAVEAT: the per-language JSONL is labelled "DEPRECATED,
    # will be removed in the near future" (wiktextract issue #1178). It is
    # the artifact the site itself builds on and serves today; if it 404s
    # (clean FetchError, sync aborts), the durable fallback is filtering the
    # full enwiktionary extract (~2.6 GB compressed) by lang_code == "cu" —
    # recorded in docs/02-sources.md.
    #
    # == License
    #
    # Verbatim, https://kaikki.org/dictionary/ "Copyright and license":
    # "This data is made available under the same licenses as Wiktionary -
    # both CC-BY-SA and GFDL." Dual license, the SA arm governs →
    # license_class "attribution", MCP-surface-safe. Wiktextract asks for an
    # academic citation (Ylönen, LREC 2022) — carried in 02-sources.
    #
    # == fetch / sync policy
    #
    # Single-file HTTP via Nabu::FileFetch (the Bosworth-Toller path:
    # conditional GET on Last-Modified, sha256 pin, attic + mass-deletion
    # guard). kaikki re-extracts regularly, but re-syncs are an owner call
    # (each one re-mints revisions across the shelf) → sync_policy: manual,
    # enabled: false until the owner-fired first real sync. The
    # remote-health probe HEADs the JSONL (:http_zip strategy); kaikki has
    # no probe-shaped license endpoint, so the license row honestly reads
    # unchecked — drift is caught by re-reading the dictionary index page at
    # any real refetch.
    class WiktionaryCu < Nabu::Adapter
      MANIFEST = Nabu::SourceManifest.new(
        id: "wiktionary-cu",
        name: "Wiktionary OCS — kaikki.org machine-readable extract",
        license: "CC-BY-SA + GFDL (verbatim kaikki.org/dictionary/: \"This data is made available " \
                 "under the same licenses as Wiktionary - both CC-BY-SA and GFDL.\")",
        license_class: "attribution",
        upstream_url: "https://kaikki.org/dictionary/Old%20Church%20Slavonic/" \
                      "kaikki.org-dictionary-OldChurchSlavonic.jsonl",
        parser_family: "wiktionary-jsonl"
      )

      FILENAME = "kaikki.org-dictionary-OldChurchSlavonic.jsonl"
      DICTIONARY_SLUG = "wiktionary-cu"
      LANGUAGE = "chu"
      TITLE = "Wiktionary — Old Church Slavonic (kaikki.org extract)"

      def self.manifest
        MANIFEST
      end

      # The routing declaration (architecture §11): entries, not passages —
      # SyncRunner/Rebuild load through Store::DictionaryLoader.
      def self.content_kind = :dictionary

      # The probe HEADs the JSONL itself: reachability + Last-Modified drift
      # vs the .file-fetch.json pin — and, given the deprecation flag, the
      # early warning that upstream pulled the file. metadata_url nil — see
      # the class note.
      def self.remote_probe_strategy = :http_zip

      def self.http_probe_targets
        [Nabu::Adapter::HttpProbeTarget.new(
          label: FILENAME, zip_url: MANIFEST.upstream_url, metadata_url: nil,
          state_subdir: "", state_file: Nabu::FileFetch::STATE_FILE
        )]
      end

      # One DocumentRef for the one JSONL. A workdir without the file yields
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
        WiktionaryJsonlParser.new(language: LANGUAGE)
                             .entries(document_ref.path).each { |entry| document << entry }
        document
      rescue Nabu::ValidationError => e
        raise Nabu::ParseError, "wiktionary-cu: #{document_ref.id}: #{e.message}"
      end

      # Download the single upstream JSONL via FileFetch (conditional GET,
      # sha pin, attic + guard contract). No network in tests: WebMock stubs.
      def fetch(workdir, progress: nil, force: false)
        result = Nabu::FileFetch.sync!(
          url: manifest.upstream_url, dir: workdir, filename: FILENAME,
          attic_dir: File.join(workdir, ATTIC_DIRNAME), progress: progress,
          guard: ->(doomed) { guard_mass_deletion!(workdir, doomed, force: force) }
        )
        FetchReport.new(sha: result.sha, fetched_at: Time.now, notes: attic_notes(result.atticked))
      rescue FileFetch::Error => e
        raise Nabu::FetchError, "wiktionary-cu fetch failed into #{workdir}: #{e.message}"
      end
    end
  end
end

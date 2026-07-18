# frozen_string_literal: true

require "csv"

require_relative "ccl_tei_parser"
require_relative "../file_fetch"

module Nabu
  module Adapters
    # The CCL adapter (P28-3, .docs/surveys/egyptian-survey.md §9): the
    # Comprehensive Coptic Lexicon v1.2 (BBAW Akademienvorhaben "Strukturen
    # und Transformationen des Wortschatzes der ägyptischen Sprache" + FU
    # Berlin DDGLC; Refubium fub188/27813, DOI 10.17169/refubium-27566) —
    # the Coptic dictionary shelf, 11,284 entries whose xml:ids ARE the
    # Coptic Dictionary Online C-ids. content_kind :dictionary, slug ccl,
    # language cop, urns urn:nabu:dict:ccl:<C-id>.
    #
    # == Two canonical artifacts, one source (the crosswalk packaging verdict)
    #
    # Beside the TEI, #fetch pulls ORAEC's coptic_etymologies crosswalk
    # (CC0; 2,177 rows C-id ↔ TLA hieroglyphic lemma id ↔ TLA demotic word
    # id — the CSV has no header; the survey's "2,176" was one short) into
    # crosswalk/. It rides as CONFIG of this adapter, not as its own
    # source: its only content is edges, every one of its C-ids exists in
    # CCL v1.2 (censused 2026-07-18 — an entry-riding design loses
    # nothing), and a source needs a catalog grain the crosswalk does not
    # have. At parse time each matched entry carries its ancestor ids as
    # DictionaryCitations (content-sha'd — a crosswalk change honestly
    # revises the entry), and Nabu::CclEtymologies re-derives them into
    # kind=etymology links-journal edges after every sync (the
    # reference_producer seam; a pure function of the catalog, the
    # CorphDilReferences pattern). A missing crosswalk file parses to
    # citation-less entries (the day-one state); the entries revise when
    # it lands.
    #
    # == License (both layers verbatim; in-file grant governs, the house
    # doctrine)
    #
    # - TEI teiHeader <availability>: "Licence for this TEI document:
    #   Creative Commons, Attribution-ShareAlike 4.0 International (CC
    #   BY-SA 4.0)"; the Refubium record shows "Creative Commons:
    #   Namensnennung, Weitergabe unter gleichen Bedingungen" with
    #   DC.rights = https://creativecommons.org/licenses/by-sa/4.0/.
    # - Crosswalk repo LICENSE: CC0 1.0 Universal; its README verbatim:
    #   "The mapping was created by the ORAEC project and is licensed
    #   under CC 0." CC0 imposes nothing → license_class stays
    #   "attribution" (BY-SA).
    #
    # == fetch / sync policy
    #
    # Two Nabu::FileFetch units (the wiktionary-recon two-phase
    # choreography: all prepare, one combined breaker, all complete) —
    # the Refubium bitstream is a frozen 2020 deposit, the crosswalk repo
    # last moved 2024-08 → sync_policy: manual, enabled: false until the
    # owner-fired first sync. The remote probe HEADs both artifacts
    # (:http_zip); neither host serves a probe-shaped license endpoint, so
    # those rows honestly read unchecked (drift is caught by re-reading
    # record/README at any refetch).
    class Ccl < Nabu::Adapter
      LEXICON_URL = "https://refubium.fu-berlin.de/bitstream/handle/fub188/27813/" \
                    "Comprehensive_Coptic_Lexicon-v1.2-2020.xml?sequence=1&isAllowed=y"
      CROSSWALK_URL = "https://raw.githubusercontent.com/oraec/coptic_etymologies/main/" \
                      "digitizing_coptic_etymologies_coptic_list_entries.csv"

      LEXICON_DIRNAME = "lexicon"
      LEXICON_FILENAME = "Comprehensive_Coptic_Lexicon-v1.2-2020.xml"
      CROSSWALK_DIRNAME = "crosswalk"
      CROSSWALK_FILENAME = "digitizing_coptic_etymologies_coptic_list_entries.csv"

      DICTIONARY_SLUG = "ccl"
      LANGUAGE = "cop"
      TITLE = "Comprehensive Coptic Lexicon (CCL v1.2)"

      MANIFEST = Nabu::SourceManifest.new(
        id: "ccl",
        name: "Comprehensive Coptic Lexicon v1.2 (BBAW/DDGLC) + ORAEC egy↔cop crosswalk",
        license: "CC BY-SA 4.0 (verbatim in-file <licence>: \"Licence for this TEI document: Creative " \
                 "Commons, Attribution-ShareAlike 4.0 International (CC BY-SA 4.0)\"; Refubium record " \
                 "fub188/27813 concurs). Crosswalk: CC0 1.0 (ORAEC coptic_etymologies README verbatim: " \
                 "\"The mapping was created by the ORAEC project and is licensed under CC 0.\")",
        license_class: "attribution",
        upstream_url: LEXICON_URL,
        parser_family: "ccl-tei"
      )

      def self.manifest
        MANIFEST
      end

      # Entries, not passages (architecture §11) — SyncRunner/Rebuild load
      # through Store::DictionaryLoader.
      def self.content_kind = :dictionary

      # The crosswalk edges (class note): refreshed after every load via
      # the shared reference_producer seam (P25-0).
      def self.reference_edges? = true

      def self.reference_producer(catalog:, journal:)
        CclEtymologies.new(catalog: catalog, journal: journal)
      end

      # Both artifacts HEADed for reachability + Last-Modified drift
      # against their subdirs' FileFetch pins; no license metadata_url
      # (class note).
      def self.remote_probe_strategy = :http_zip

      def self.http_probe_targets
        [
          Nabu::Adapter::HttpProbeTarget.new(
            label: LEXICON_FILENAME, zip_url: LEXICON_URL, metadata_url: nil,
            state_subdir: LEXICON_DIRNAME, state_file: Nabu::FileFetch::STATE_FILE
          ),
          Nabu::Adapter::HttpProbeTarget.new(
            label: CROSSWALK_FILENAME, zip_url: CROSSWALK_URL, metadata_url: nil,
            state_subdir: CROSSWALK_DIRNAME, state_file: Nabu::FileFetch::STATE_FILE
          )
        ]
      end

      # One DocumentRef for the one TEI (the crosswalk is adapter config,
      # not a document — it surfaces through the entries it annotates). A
      # workdir without the file yields nothing (the day-one pre-fetch
      # state); the same walk works under the attic (same relative shape).
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        Dir.glob(File.join(workdir, "**", LEXICON_FILENAME)).first(1).each do |path|
          yield Nabu::DocumentRef.new(
            source_id: manifest.id,
            id: "#{DICTIONARY_SLUG}:#{LEXICON_FILENAME}",
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
        etymologies = crosswalk_for(document_ref.path)
        CclTeiParser.new.entries(document_ref.path, etymologies: etymologies)
                    .each { |entry| document << entry }
        document
      rescue Nabu::ValidationError => e
        raise Nabu::ParseError, "ccl: #{document_ref.id}: #{e.message}"
      end

      # Both artifacts two-phase (the wiktionary-recon choreography): all
      # prepare with the live tree untouched, the breaker sees the combined
      # doomed set, then all complete. Report: the lexicon sha (the
      # single-pin convention), both shas in notes.
      def fetch(workdir, progress: nil, force: false)
        fetches = file_fetches(workdir, progress)
        fetches.each_value(&:prepare!)
        guard_mass_deletion!(workdir, fetches.values.flat_map(&:doomed_paths), force: force)
        fetches.each_value(&:complete!)
        Nabu::FetchReport.new(sha: fetches.fetch(:lexicon).sha, fetched_at: Time.now,
                              notes: fetch_notes(fetches))
      rescue FileFetch::Error => e
        raise Nabu::FetchError, "ccl fetch failed into #{workdir}: #{e.message}"
      end

      private

      # The crosswalk beside the lexicon: <workdir>/crosswalk/… relative to
      # <workdir>/lexicon/<xml> — the same relative shape under the attic.
      # Absent file → empty map (class note). Rows are id,hieroglyphic,
      # demotic with NO header (censused); malformed lines would surface as
      # CSV errors and quarantine the one dictionary file, honestly.
      def crosswalk_for(lexicon_path)
        path = File.join(File.dirname(lexicon_path, 2), CROSSWALK_DIRNAME, CROSSWALK_FILENAME)
        return {} unless File.file?(path)

        CSV.read(path).to_h { |row| [row[0], [row[1], row[2]]] }
      rescue CSV::MalformedCSVError => e
        raise Nabu::ParseError, "ccl: malformed crosswalk #{path}: #{e.message}"
      end

      def file_fetches(workdir, progress)
        {
          lexicon: file_fetch(workdir, LEXICON_URL, LEXICON_DIRNAME, LEXICON_FILENAME, progress),
          crosswalk: file_fetch(workdir, CROSSWALK_URL, CROSSWALK_DIRNAME, CROSSWALK_FILENAME, progress)
        }
      end

      def file_fetch(workdir, url, subdir, filename, progress)
        Nabu::FileFetch.new(
          url: url, dir: File.join(workdir, subdir), filename: filename,
          attic_dir: File.join(workdir, ATTIC_DIRNAME, subdir), progress: progress
        )
      end

      def fetch_notes(fetches)
        shas = fetches.map { |name, fetch| "#{name} #{fetch.sha[0, 8]}" }
        [shas.join(" · "), attic_notes(fetches.values.flat_map(&:atticked))].compact.join("; ")
      end
    end
  end
end

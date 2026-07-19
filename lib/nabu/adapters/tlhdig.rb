# frozen_string_literal: true

require "fileutils"

require_relative "aoxml_parser"

module Nabu
  module Adapters
    # TLHdig — Thesaurus Linguarum Hethaeorum digitalis (P31-1): the
    # Hittite corpus. Beta Version 0.3 as ONE frozen Zenodo deposit
    # (record 20328284, published 2026-05-21; TLHbasisONLINE25_1_ZENODO_
    # Beta_03.zip, 74,449,198 bytes, Zenodo md5 f9acbc8db3111cc7dd88d82f
    # 7819a912 verified byte-for-byte at fixture time, sha256-pinned
    # below) — 23,937 per-manuscript AOxml files in 826 "CTH n_XML_
    # <project>" folders (663 distinct CTH numbers; the site claims >98%
    # of published Hittite fragments). A thin composition of the
    # AoxmlParser family; the adapter owns identity (the CTH folder
    # layout), the fetch pin, and the quarantine-honesty stance.
    #
    # == Identity: the folder layout IS the catalog
    #
    #   urn:nabu:tlhdig:<cth>:<project>:<manuscript>
    #   626 : hfr : kbo.52.195+   ← "CTH 626_XML_HFR/KBo 52.195+.xml"
    #
    # CTH numbers repeat across TWO sub-project folders (163 numbers)
    # and the same publication siglum recurs under different CTH numbers
    # (132 basenames — provenance-distinct filings, never deduped), so
    # all three segments carry identity. The one upstream twin — CTH
    # 999_XML_TLH holds byte-identical KUB 46.39+.xml in two project
    # bins — is skipped by rule after the first (path-sorted) copy,
    # censused in discovery_skips; a NON-identical collision would be
    # real damage and raises instead. CTH 670's "CTH 670-NNNN-NNNN"
    # range subfolders are pagination, not identity.
    #
    # == The silver stance (the lemma-tier verdict, censused)
    #
    # The mrp candidate analyses are upstream's own hypothesis layer
    # (annot editor="auto" in the headers; unresolved multi-candidate
    # words throughout). A disambiguated subset EXISTS — 72.6% of the
    # 757,728 analyzed words carry a digit selection or a single
    # candidate (measured over the whole Beta 0.3 corpus) — and only it
    # mints "lemma" keys; sources.yml registers lemma_tier: silver, so
    # every count renders LABELED, never as gold attestation (the
    # diorisis/goo300k discipline). All candidates ride annotations
    # verbatim either way.
    #
    # == Quarantine honesty (Beta reality)
    #
    # 224 files are not well-formed XML and 226 more carry no
    # transliteration lines (the deposit's own description: "XML errors
    # and inconsistencies" are work in progress) — both quarantine as
    # ParseError at sync, loud and censused, never patched or skipped
    # silently. Fixture exemplars pin both shapes.
    #
    # == fetch / license
    #
    # ZipFetch with a hard sha256 pin (the diorisis choreography:
    # prepare → verify pin → breaker → complete; the versioned DOI is
    # immutable, so a mismatch is corruption, never an update). The zip
    # carries a __MACOSX sibling next to the corpus directory — kept in
    # canonical (the artifact stays whole); discover simply never scans
    # it. License: the Zenodo record's license field is cc-by-4.0 →
    # attribution, with the prescribed citation verbatim in the
    # manifest. Registry enabled: false, sync_policy manual.
    class Tlhdig < Nabu::Adapter
      ZIP_URL = "https://zenodo.org/records/20328284/files/TLHbasisONLINE25_1_ZENODO_Beta_03.zip"

      # sha256 of the 74,449,198-byte zip, computed from the 2026-07-19
      # census download whose md5 (f9acbc8db3111cc7dd88d82f7819a912)
      # matched the Zenodo record's published checksum exactly.
      ZIP_SHA256 = "c845a23223bb9461eeb215f5ede0e223c8871473873c6123eadaeb72114fcd36"

      # The corpus directory inside the zip (its __MACOSX sibling and
      # .DS_Store stragglers stay in canonical, unscanned).
      CORPUS_DIR_PATTERN = /\ATLHbasis/

      CTH_FOLDER = /\ACTH (?<cth>[^_]+)_XML_(?<project>.+)\z/

      URN_PREFIX = "urn:nabu:tlhdig:"

      MANIFEST = Nabu::SourceManifest.new(
        id: "tlhdig",
        name: "TLHdig — Thesaurus Linguarum Hethaeorum digitalis (Beta 0.3, Zenodo 20328284)",
        license: "CC BY 4.0 (Zenodo record 20328284 license field cc-by-4.0, both Beta versions; " \
                 "cite verbatim: \"Thesaurus Linguarum Hethaeorum digitalis, hethiter.net/: " \
                 "TLHdig – Beta Version 0.3 (2025-11-01)\")",
        license_class: "attribution",
        upstream_url: "https://doi.org/10.5281/zenodo.20328284",
        parser_family: "aoxml"
      )

      def self.manifest
        MANIFEST
      end

      # HEAD the Zenodo artifact: reachability + Last-Modified drift
      # against the .zip-fetch.json pin. metadata_url nil — the Zenodo
      # API body carries volatile stats that would false-alarm a hash
      # comparison (the diorisis figshare lesson); the license field
      # re-reads at any real refetch.
      def self.remote_probe_strategy = :http_zip

      def self.http_probe_targets
        [Nabu::Adapter::HttpProbeTarget.new(
          label: "TLHdig-Beta03.zip", zip_url: ZIP_URL, metadata_url: nil,
          state_subdir: "", state_file: Nabu::ZipFetch::STATE_FILE
        )]
      end

      # +pin+ overrides the zip sha (tests; a deliberate owner re-pin drill).
      def initialize(pin: ZIP_SHA256)
        super()
        @pin = pin
      end

      # One DocumentRef per manuscript XML under the CTH folders, sorted
      # by urn. Identity is pure path derivation — no XML is read here
      # (23,937 files; header peeks would cost a full-corpus scan). A
      # pre-fetch workdir yields nothing.
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        document_refs(workdir).each(&block)
      end

      # The discovery census (P11-7): the byte-identical twin skips by
      # rule (1 upstream — class note); a CTH folder that misses the
      # "CTH n_XML_project" pattern would be unrecognized (0 upstream).
      def discovery_skips(workdir)
        skipped = 0
        notes = []
        grouped_refs(workdir) do |kind, detail|
          case kind
          when :duplicate then skipped += 1
          when :unrecognized then notes << detail
          end
        end
        DiscoverySkips.new(skipped_by_rule: skipped, unrecognized: notes.size, notes: notes)
      end

      def parse(document_ref)
        AoxmlParser.new.parse(
          document_ref.path,
          urn: document_ref.id,
          cth: document_ref.metadata["cth"],
          project: document_ref.metadata["project"]
        )
      rescue Nabu::ValidationError => e
        raise ParseError, "#{document_ref.path}: #{e.message}"
      end

      # ZipFetch with the phases driven by hand so the sha pin is checked
      # BETWEEN download and any tree mutation (the diorisis/IE-CoR
      # choreography); a 304 replays the stored pin and touches nothing.
      def fetch(workdir, progress: nil, force: false)
        fetch = Nabu::ZipFetch.new(url: ZIP_URL, dir: workdir,
                                   attic_dir: File.join(workdir, ATTIC_DIRNAME), progress: progress)
        begin
          fetch.prepare!
          verify_pin!(fetch)
          guard_mass_deletion!(workdir, fetch.doomed_paths, force: force)
          fetch.complete!
        ensure
          fetch.cleanup!
        end
        Nabu::FetchReport.new(sha: fetch.sha, fetched_at: Time.now, notes: fetch_notes(fetch))
      rescue ZipFetch::Error, Nabu::Shell::Error => e
        raise Nabu::FetchError, "tlhdig fetch failed into #{workdir}: #{e.message}"
      end

      private

      def verify_pin!(fetch)
        return if fetch.not_modified? || fetch.sha == @pin

        raise Nabu::FetchError,
              "tlhdig: downloaded artifact misses the sha256 pin (expected #{@pin}, " \
              "got #{fetch.sha}) — the Zenodo versioned deposit is immutable, so this is " \
              "corruption or tampering; verify #{ZIP_URL} against the record before re-pinning"
      end

      def fetch_notes(fetch)
        base = fetch.not_modified? ? "not modified (304)" : "Zenodo Beta 0.3 sha pin verified"
        [base, attic_notes(fetch.atticked)].compact.join("; ")
      end

      def document_refs(workdir)
        refs = []
        grouped_refs(workdir) do |kind, detail|
          refs << detail if kind == :ref
        end
        refs.sort_by(&:id)
      end

      # The one path walk both discover and the census share. Yields
      # [:ref, DocumentRef] for each canonical file, [:duplicate, path]
      # for a byte-identical urn twin (first path-sorted copy wins),
      # [:unrecognized, note] for a CTH folder outside the pattern —
      # and raises on a NON-identical urn collision (damage, class note).
      def grouped_refs(workdir, &block)
        root = corpus_root(workdir) or return
        seen = {}
        Dir.glob(File.join(root, "CTH *")).each do |folder|
          match = CTH_FOLDER.match(File.basename(folder))
          unless match
            yield :unrecognized, "#{File.basename(folder)}: not a 'CTH n_XML_project' folder"
            next
          end
          folder_refs(folder, match, seen, &block)
        end
      end

      def folder_refs(folder, match, seen)
        Dir.glob(File.join(folder, "**", "*.xml")).each do |path|
          id = urn_for(match[:cth], match[:project], path)
          if (first = seen[id])
            require_identical_twin!(first, path, id)
            yield :duplicate, path
            next
          end
          seen[id] = path
          yield :ref, document_ref(id, path, match)
        end
      end

      def document_ref(id, path, match)
        Nabu::DocumentRef.new(
          source_id: manifest.id, id: id, path: File.expand_path(path),
          metadata: { "cth" => match[:cth], "project" => match[:project] }
        )
      end

      def urn_for(cth, project, path)
        manuscript = File.basename(path, ".xml").unicode_normalize(:nfc)
                         .downcase.gsub(/\s+/, ".")
        "#{URN_PREFIX}#{cth}:#{project.downcase}:#{manuscript}"
      end

      def require_identical_twin!(first, path, id)
        return if FileUtils.identical?(first, path)

        raise ParseError,
              "#{path}: urn collision with #{first} (#{id}) and the files differ — " \
              "upstream damage, not the censused byte-identical CTH 999 twin"
      end

      # The fixture dir carries CTH folders at its root; a real sync
      # unpacks the corpus directory beside __MACOSX, so the root is the
      # single TLHbasis* entry. No CTH folders anywhere = pre-fetch.
      def corpus_root(workdir)
        return workdir unless Dir.glob(File.join(workdir, "CTH *")).empty?

        Dir.children(workdir)
           .grep(CORPUS_DIR_PATTERN)
           .map { |name| File.join(workdir, name) }
           .find { |path| File.directory?(path) }
      rescue Errno::ENOENT
        nil
      end
    end
  end
end

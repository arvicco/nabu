# frozen_string_literal: true

require_relative "hsms_parser"

module Nabu
  module Adapters
    # The OSTA adapter (P77-1): the Old Spanish Textual Archive
    # (github.com/hispanicseminary/OSTA — Hispanic Seminary of Medieval
    # Studies; Gago Jover & Pueyo Mena), 663 semi-paleographic
    # transcriptions of medieval Spanish manuscripts and incunabula over
    # the NEW hsms family (HsmsParser — the curly-brace HSMS markup).
    # The headline of the P77 medieval content phase: the foundational
    # machine-readable record of Old Spanish, unblocked by the №45-1
    # grant. The verticalized/ lemma lane (78 .vrt.html files) is packet
    # 77-2; the tables/ works metadata (languages, dating) is №R-30.
    #
    # == Identity (FROZEN minting)
    #
    # One document per transcriptions/TEXT.<SIGLUM>.txt: urn =
    # urn:nabu:osta:<siglum downcased> — the FILENAME siglum mints (the
    # syriac-corpus precedent: the in-file "[SIG]" header siglum rides
    # metadata verbatim and is never trusted for identity). Passage =
    # the HSMS numbered section, citation = the ordinal zero-stripped
    # (:1), with the honest `head` for pre-section text and the house
    # :b2 belt for collisions — see HsmsParser. Minting is frozen once
    # used (standing rule).
    #
    # == Language
    #
    # `osp` (Old Spanish) for every document — the v1 default under the
    # pending №R-30 ruling: the archive's Asturian/Leonese/
    # Navarro-Aragonese layers ride under osp until the works-table
    # language column is wired (an honest one-tag practice, recorded in
    # the postures row).
    #
    # == License (№45-1, recorded 2026-08-13)
    #
    # CC BY-NC-SA 4.0 — zenodo.org/records/18931376 is the deposit's
    # SOLE declared grant (verified 2026-08-13: the GitHub repo has no
    # LICENSE file; the reply's "an MIT and a CC BY-NC-SA 4.0 license"
    # stays uncorroborated — clarification asked, nc governs, owner
    # ruling "keep nc for now"). Class nc → MCP-excluded, never served.
    # CREDIT DUTY (the №45-1 citation ruling): the Zenodo record
    # citation on every surface + the per-text TEXT.xxx.txt identifier —
    # both ride every document's "citation" metadata.
    #
    # == Fetch
    #
    # Sparse GitFetch cone [transcriptions, tables, citation.cff,
    # README.md] (~234 MB of transcriptions; verticalized/ joins the
    # cone at 77-2). Upstream is a young repository (v1.0.0 deposited
    # 2026) → sync_policy manual.
    class Osta < Nabu::Adapter
      REPO_URL = "https://github.com/hispanicseminary/OSTA"

      SPARSE_PATHS = ["transcriptions", "tables", "citation.cff", "README.md"].freeze

      TRANSCRIPTIONS_DIR = "transcriptions"

      FILE_SHAPE = /\ATEXT\.([A-Za-z0-9]+)\.txt\z/

      LANGUAGE = "osp"

      # The №45-1 citation ruling, verbatim from the 2026-08-13 reply.
      ZENODO_CITATION = "Hispanic Seminary of Medieval Studies & Gago Jover, F. (2026). " \
                        "hispanicseminary/OSTA: Old Spanish Textual Archive materials " \
                        "(Version 1.0.0) [Dataset]. Zenodo. " \
                        "https://doi.org/10.5281/zenodo.18931376"

      MANIFEST = Nabu::SourceManifest.new(
        id: "osta",
        name: "OSTA — Old Spanish Textual Archive (Hispanic Seminary of Medieval Studies)",
        license: "CC BY-NC-SA 4.0 (zenodo.org/records/18931376 — the deposit's sole declared " \
                 "grant, verified 2026-08-13; the №45-1 reply's \"an MIT and a CC BY-NC-SA " \
                 "4.0 license\" stays uncorroborated in-repo — nc governs until MIT " \
                 "materializes; owner ruling 2026-08-13 \"keep nc for now\")",
        license_class: "nc",
        upstream_url: REPO_URL,
        parser_family: "hsms"
      )

      def self.manifest
        MANIFEST
      end

      # One DocumentRef per transcription, in siglum order. A workdir
      # without the tree (pre-fetch) yields nothing.
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        transcriptions(workdir).each do |siglum, path|
          yield Nabu::DocumentRef.new(
            source_id: manifest.id,
            id: "urn:nabu:osta:#{siglum.downcase}",
            path: path,
            metadata: { "file" => File.basename(path), "siglum" => siglum }
          )
        end
      end

      # Files under transcriptions/ that are not the TEXT.<siglum>.txt
      # shape can never mint a ref — flagged unrecognized (P11-7).
      def discovery_skips(workdir)
        strays = Dir[File.join(workdir, TRANSCRIPTIONS_DIR, "*")]
                 .select { |path| File.file?(path) }
                 .reject { |path| FILE_SHAPE.match?(File.basename(path)) }.sort
        DiscoverySkips.new(
          unrecognized: strays.size,
          notes: strays.map { |path| "#{File.basename(path)}: not the TEXT.<siglum>.txt shape" }
        )
      end

      def parse(document_ref)
        file = document_ref.metadata.fetch("file")
        HsmsParser.new.parse(
          document_ref.path,
          urn: document_ref.id,
          language: LANGUAGE,
          fallback_title: document_ref.metadata.fetch("siglum"),
          extra_metadata: { "citation" => "#{file}, in: #{ZENODO_CITATION}" }
        )
      end

      def fetch(workdir, progress: nil, force: false)
        git_fetch!(repo_url: repo_url, workdir: workdir, progress: progress, force: force,
                   sparse: SPARSE_PATHS)
      end

      private

      # Seam for tests (the house local-git pattern).
      def repo_url
        REPO_URL
      end

      def transcriptions(workdir)
        Dir[File.join(workdir, TRANSCRIPTIONS_DIR, "TEXT.*.txt")]
          .filter_map do |path|
            match = FILE_SHAPE.match(File.basename(path))
            [match[1], path] if match
          end
          .sort
      end
    end
  end
end

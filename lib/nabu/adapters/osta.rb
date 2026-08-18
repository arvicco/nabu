# frozen_string_literal: true

require_relative "hsms_parser"
require_relative "hsms_vrt_parser"
require_relative "osta_tables"

module Nabu
  module Adapters
    # The OSTA adapter (P77-1): the Old Spanish Textual Archive
    # (github.com/hispanicseminary/OSTA — Hispanic Seminary of Medieval
    # Studies; Gago Jover & Pueyo Mena), 663 semi-paleographic
    # transcriptions of medieval Spanish manuscripts and incunabula over
    # the NEW hsms family (HsmsParser — the curly-brace HSMS markup).
    # The headline of the P77 medieval content phase: the foundational
    # machine-readable record of Old Spanish, unblocked by the №45-1
    # grant — plus the verticalized/ lemma lane (P77-2): the 78
    # .vrt.html lemmatized/tagged token streams as SIBLING documents
    # (`-vrt` layer tail; two editions are two versions, never a
    # dedupe), whose "tokens" annotations feed the lemma index at
    # `lemma_tier: silver` — ruled on upstream evidence: Gago Jover &
    # Pueyo Mena (Scriptum Digital 7) document the lemmatization as
    # FreeLing + HSMS-app, i.e. AUTOMATIC (the GLAUx precedent).
    # The tables/ works metadata lane (P77-r6, №R-30 ruled 2026-08-13)
    # joins per-siglum: works rows + codex row + the lengua facet — see
    # OstaTables.
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
    # Per document from the works table (P77-r6, №R-30): the majority
    # OstaTables::LENGUA_CODES mapping over the codex's works — osp for
    # the castellano bulk, ast/roa-opt/arg/lat for the Leonese/Galician/
    # Navarro-Aragonese/Latin layers; `osp` stays the honest fallback
    # for an acquisition without the tables. Raw lengua values ride the
    # works metadata verbatim; the majority raw value is the "lengua"
    # facet (the future lect hook).
    #
    # == License (№45-1, recorded 2026-08-13)
    #
    # CC BY-NC-SA 4.0 — zenodo.org/records/18931376 is the deposit's
    # SOLE declared grant (verified 2026-08-13: the GitHub repo has no
    # LICENSE file; the reply's "an MIT and a CC BY-NC-SA 4.0 license"
    # stays uncorroborated — clarification asked, nc governs, owner
    # ruling "keep nc for now"). Class nc → MCP-excluded, never served.
    # CAVEAT recorded (P77-2): verticalized/ lives ONLY in the GitHub
    # repo — the Zenodo deposit holds transcriptions + tables — so the
    # lemma lane's grant basis is the №45-1 reply's own words ("They
    # can be found in our Github and Zenodo repositories"), same
    # rights holder, same nc class; the pending MIT-clarification
    # thread is the place any firmer word arrives. CREDIT DUTY (the
    # №45-1 citation ruling): the Zenodo record citation on every
    # surface + the per-text TEXT.xxx identifier — both ride every
    # document's "citation" metadata.
    #
    # == Fetch
    #
    # Sparse GitFetch cone [transcriptions, verticalized, tables,
    # citation.cff, README.md] (~234 MB of transcriptions + the vrt
    # lane). Upstream is a young repository (v1.0.0 deposited 2026) →
    # sync_policy manual.
    class Osta < Nabu::Adapter
      REPO_URL = "https://github.com/hispanicseminary/OSTA"

      SPARSE_PATHS = ["transcriptions", "verticalized", "tables", "citation.cff",
                      "README.md"].freeze

      TRANSCRIPTIONS_DIR = "transcriptions"

      FILE_SHAPE = /\ATEXT\.([A-Za-z0-9]+)\.txt\z/

      VRT_DIR = "verticalized"

      VRT_SHAPE = /\ATEXT\.([A-Za-z0-9]+)\.vrt\.html\z/

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

      # One DocumentRef per transcription in siglum order, then one per
      # verticalized file (the `-vrt` sibling tail), appended so the
      # transcription documents keep their positions (the ccmh
      # precedent). A workdir without the tree (pre-fetch) yields
      # nothing.
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        transcription_refs(workdir).each(&block)
        vrt_refs(workdir).each(&block)
      end

      # Files under either lane dir that are not the lane's shape can
      # never mint a ref — flagged unrecognized (P11-7).
      def discovery_skips(workdir)
        strays = lane_strays(workdir, TRANSCRIPTIONS_DIR, FILE_SHAPE) +
                 lane_strays(workdir, VRT_DIR, VRT_SHAPE)
        DiscoverySkips.new(
          unrecognized: strays.size,
          notes: strays.map { |path| "#{File.basename(path)}: not the lane's TEXT.<siglum> shape" }
        )
      end

      # Dispatch by extension: .vrt.html is the verticalized lane, .txt
      # the transcription lane (the ccmh two-parser shape). Both lanes
      # join the works tables by siglum (P77-r6) — the -vrt sibling is
      # the same work, so it carries the same rows and language.
      def parse(document_ref)
        file = document_ref.metadata.fetch("file")
        siglum = document_ref.metadata.fetch("siglum")
        tables = tables_for(document_ref.path)
        extra = { "citation" => "#{file}, in: #{ZENODO_CITATION}" }
        merge_tables!(extra, tables, siglum)
        language = tables&.language_for(siglum) || LANGUAGE
        if file.end_with?(".vrt.html")
          HsmsVrtParser.new.parse(
            document_ref.path, urn: document_ref.id, language: language,
                               siglum: siglum, extra_metadata: extra
          )
        else
          HsmsParser.new.parse(
            document_ref.path, urn: document_ref.id, language: language,
                               fallback_title: siglum, extra_metadata: extra
          )
        end
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

      # tables/ sits beside the lane dirs; single-slot memo so 663
      # parses read the xlsx once per acquisition tree.
      def tables_for(path)
        dir = File.join(File.dirname(path, 2), "tables")
        return @tables if @tables_dir == dir

        @tables_dir = dir
        @tables = OstaTables.load(dir)
      end

      def merge_tables!(extra, tables, siglum)
        return unless tables

        works = tables.works(siglum)
        extra["works"] = works if works
        codex = tables.codex(siglum)
        extra["codex"] = codex if codex
        lengua = tables.primary_lengua(siglum)
        extra["facets"] = { "lengua" => { "value" => lengua } } if lengua
      end

      def transcription_refs(workdir)
        lane_files(workdir, TRANSCRIPTIONS_DIR, FILE_SHAPE).map do |siglum, path|
          document_ref(siglum, path, urn: "urn:nabu:osta:#{siglum.downcase}")
        end
      end

      def vrt_refs(workdir)
        lane_files(workdir, VRT_DIR, VRT_SHAPE).map do |siglum, path|
          document_ref(siglum, path, urn: "urn:nabu:osta:#{siglum.downcase}-vrt")
        end
      end

      def document_ref(siglum, path, urn:)
        Nabu::DocumentRef.new(
          source_id: manifest.id, id: urn, path: path,
          metadata: { "file" => File.basename(path), "siglum" => siglum }
        )
      end

      def lane_files(workdir, dir, shape)
        Dir[File.join(workdir, dir, "TEXT.*")]
          .filter_map do |path|
            match = shape.match(File.basename(path))
            [match[1], path] if match
          end
          .sort
      end

      def lane_strays(workdir, dir, shape)
        Dir[File.join(workdir, dir, "*")]
          .select { |path| File.file?(path) }
          .reject { |path| shape.match?(File.basename(path)) }.sort
      end
    end
  end
end

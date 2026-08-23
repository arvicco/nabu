# frozen_string_literal: true

require_relative "tcp_xml_parser"
require_relative "../cme_fetch"

module Nabu
  module Adapters
    # The Corpus of Middle English Prose and Verse (P82-2) — the Middle
    # English Compendium's text corpus (University of Michigan Library):
    # ~297 Middle English texts (Chaucer, Gawain, the mystery cycles, wills,
    # medical treatises …) as TCP-schema XML, the May-2026 normalization
    # served by the corpus editors' own companion site, medictionary.info.
    # First rider of the `tcp-xml` family (TcpXmlParser) — the adapter
    # composes the family and owns none of it, so a future EEBO-TCP wave
    # rides the same machinery.
    #
    # == Identity
    #
    # The upstream FILENAME is the identity (mixed case verbatim — the
    # <IDG> id is a placeholder shared across files, censused):
    #
    #   document urn  urn:nabu:cme:<name>            (…:cme:tenwives)
    #   passage urn   <document-urn>:<div-path>.<unit>  (…:cme:tenwives:d2.l7)
    #
    # ref.id == parse(ref).urn (the conformance identity).
    #
    # == Passage grain
    #
    # The format's own reading units: verse <L> lines (l<k>), prose blocks
    # (p<k>: P/Q/ITEM/CELL/OPENER/…), and <HEAD> rubrics (h<k> — CME heads
    # are transcribed medieval rubrics, reading text). ~1.3M passages at
    # full-corpus scale (censused on the 2026-08-23 scout copy).
    #
    # == Language
    #
    # Every passage claims bare `enm` (Middle English, registry band
    # 1100–1500) — the corpus's own definition is the claim. Upstream
    # LANGUSAGE declarations are inconsistent (censused: 150 files declare
    # enm, 61 declare "eng", others list only their FOREIGN languages —
    # Latin/French/German editorial matter); they ride document metadata
    # verbatim (language_usage / text_lang), never the passage claim.
    #
    # == License (grant №77-2)
    #
    # OPEN: the downloads page verbatim — "available for free downloading,
    # with no restrictions on use or reuse" — plus one uniform per-file
    # public-domain AVAILABILITY statement (censused identical across all
    # 297 files), plus the personal grant (P.F. Schaffner, MED editor and
    # TCP text manager, 2026-08-20: "free to use both the CME and the TCP
    # files in any way you choose, and obtain them by any means
    # convenient"). Credit appreciated-not-insisted — the manifest credit
    # seam carries it anyway.
    class Cme < Nabu::Adapter
      BASE_URL = "http://www.medictionary.info"

      LANGUAGE = "enm"
      URN_PREFIX = "urn:nabu:cme:"

      MANIFEST = Nabu::SourceManifest.new(
        id: "cme",
        name: "Corpus of Middle English Prose and Verse (Middle English Compendium, Univ. of Michigan)",
        license: "OPEN — medictionary.info downloads page verbatim (2026-08-23): the raw corpus " \
                 "files are \"available for free downloading, with no restrictions on use or " \
                 "reuse\"; every file carries the U-M Library public-domain statement (\"You may " \
                 "copy, modify, distribute and perform the work, even for commercial purposes, " \
                 "all without asking permission\" — censused identical across all 297 files). " \
                 "Personal grant №77-2 (P.F. Schaffner, MED editor / TCP text manager, " \
                 "2026-08-20): \"free to use both the CME and the TCP files in any way you " \
                 "choose, and obtain them by any means convenient\"; credit appreciated.",
        license_class: "open",
        upstream_url: BASE_URL,
        parser_family: "tcp-xml",
        credit: "Corpus of Middle English Prose and Verse — Middle English Compendium, " \
                "University of Michigan Library (medictionary.info)"
      )

      def self.manifest
        MANIFEST
      end

      # P11-2/P79-2: no git repo; the crawl's state file pins an aggregate
      # sha the probe cannot diff URL-by-URL — a liveness-only HEAD of the
      # autoindex is the honest posture (the kitab/corpus-corporum mold).
      def self.remote_probe_strategy = :http_zip

      def self.http_probe_targets
        [Nabu::Adapter::HttpProbeTarget.new(
          label: "texts autoindex",
          zip_url: Nabu::CmeFetch.listing_url(BASE_URL),
          metadata_url: nil, state_subdir: "",
          state_file: Nabu::CmeFetch::STATE_FILE,
          liveness_only: true
        )]
      end

      # +delay+ exists for the WebMock'd tests (0); real syncs keep the
      # polite default.
      def initialize(delay: Nabu::CmeFetch::DELAY)
        super()
        @delay = delay
      end

      # One DocumentRef per texts/<name>.xml, urn = the filename verbatim,
      # sorted by urn. A pre-fetch workdir yields nothing (texts/ absent);
      # the listing fixture, state file and attic never match.
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        document_refs(workdir).each(&block)
      end

      # Delegate to the tcp-xml family. No license_mapper: the per-file
      # AVAILABILITY is one uniform PD statement (censused) and the source
      # class already says `open` — a per-document override would be
      # machinery with nothing to decide. The statement itself still rides
      # metadata verbatim.
      def parse(document_ref)
        TcpXmlParser.new.parse(
          document_ref.path,
          urn: document_ref.id, language: LANGUAGE
        )
      rescue Nabu::ValidationError => e
        raise ParseError, "#{document_ref.path}: #{e.message}"
      end

      # The polite autoindex crawl (never in tests — WebMock blocks the
      # network): one listing GET + per-text downloads, file-grain
      # resumable, non-destructive (attic + breaker).
      def fetch(workdir, progress: nil, force: false)
        result = Nabu::CmeFetch.sync!(
          base_url: BASE_URL, dir: workdir, attic_dir: File.join(workdir, ATTIC_DIRNAME),
          delay: @delay, progress: progress,
          guard: ->(doomed) { guard_mass_deletion!(workdir, doomed, force: force) }
        )
        Nabu::FetchReport.new(sha: result.sha, fetched_at: Time.now, notes: fetch_notes(result))
      rescue Nabu::CmeFetch::Error => e
        raise Nabu::FetchError, "cme fetch failed into #{workdir}: #{e.message}"
      end

      private

      def document_refs(workdir)
        Dir.glob(File.join(workdir, Nabu::CmeFetch::TEXTS_DIR, "*.xml")).map do |path|
          name = File.basename(path, ".xml")
          Nabu::DocumentRef.new(
            source_id: manifest.id,
            id: "#{URN_PREFIX}#{name}",
            path: File.expand_path(path),
            metadata: { "filename" => File.basename(path) }
          )
        end.sort_by(&:id)
      end

      def fetch_notes(result)
        base = "autoindex walked (#{result.listed} texts listed, #{result.fetched} fetched, " \
               "#{result.cached} already on disk)"
        [base, attic_notes(result.atticked)].compact.join("; ")
      end
    end
  end
end

# frozen_string_literal: true

require_relative "corpus_corporum_tei_parser"
require_relative "../corpus_corporum_fetch"

module Nabu
  module Adapters
    # Corpus Córporum (P80-1/80-2) — mlat.uzh.ch, the University of Zurich's
    # Latin (meta-)repository (dir. Philipp Roelli): 30 corpora / ~10k texts /
    # 226M words. The v1 SCOPE is corpus idno 38, the Patrologia Latina —
    # Migne's 221-volume patristic-to-medieval series, 5,277 texts / 85.5M
    # words (census 2026-08-19) — but the fetch walk is corpus-generic
    # (CorpusCorporumFetch), so widening scope is a constant, not a rewrite.
    #
    # == Identity
    #
    # The de-facto API keys every text on a globally-unique cc idno; the
    # fetch lands one TEI file per text at texts/<idno>.xml, so:
    #
    #   document urn  urn:nabu:corpus-corporum:<idno>
    #   passage urn   <document-urn>:<div-path>.<unit>   (…:10468:d1.p2)
    #
    # ref.id == parse(ref).urn (the conformance identity).
    #
    # == License (80-1 — the ETCSL class-3 mold + the sefaria per-unit gate)
    #
    # Source-level nc; the homepage License section verbatim in the manifest.
    # Per-text: the parser captures each teiHeader's provenance (editor,
    # publisher, series/volume, availability verbatim when present) into
    # document metadata, and license_override_for maps an EXPLICIT header
    # grant onto the class enum. The sampled PL headers are license-silent →
    # override nil, the conservative source class governs (owner default).
    #
    # == fetch / sync policy
    #
    # The polite resumable catalog walk + per-text downloads (~12k requests
    # for full PL at 1 req/s — an owner-fired multi-hour first sync);
    # refusals are recorded skips, deletions attic behind the breaker.
    # sync_policy manual, wired: false until the owner-fired first sync.
    class CorpusCorporum < Nabu::Adapter
      BASE_URL = "https://mlat.uzh.ch"

      LANGUAGE = "lat"
      URN_PREFIX = "urn:nabu:corpus-corporum:"
      TEXT_FILENAME = /\A(\d+)\.xml\z/

      MANIFEST = Nabu::SourceManifest.new(
        id: "corpus-corporum",
        name: "Corpus Córporum — Patrologia Latina (mlat.uzh.ch, Univ. of Zurich)",
        license: "NC — homepage License section verbatim (2026-08-19): own transcriptions " \
                 "\"published under Creative Commons Share-Alike and may thus be reused freely " \
                 "(but non-commercially) as long as the source is indicated\"; most texts \"either " \
                 "in the public domain or their use was granted us by their owners\"; project goal: " \
                 "\"Texts may be downloaded as TEI xml for non-commercial use and can thus be " \
                 "reused by other researchers\". Per-text teiHeaders are license-silent (censused) — " \
                 "the source class governs; cite Corpus Corporum, mlat.uzh.ch",
        license_class: "nc",
        upstream_url: BASE_URL,
        parser_family: "corpus-corporum-tei"
      )

      def self.manifest
        MANIFEST
      end

      # P11-2/P79-2: no git repo, and the crawl's state file pins an
      # aggregate sha the probe cannot diff URL-by-URL — a liveness-only
      # HEAD of the catalog root is the honest posture (the kitab mold).
      def self.remote_probe_strategy = :http_zip

      def self.http_probe_targets
        [Nabu::Adapter::HttpProbeTarget.new(
          label: "navigate.php catalog root",
          zip_url: Nabu::CorpusCorporumFetch.navigate_url(BASE_URL, "/"),
          metadata_url: nil, state_subdir: "",
          state_file: Nabu::CorpusCorporumFetch::STATE_FILE,
          liveness_only: true
        )]
      end

      # The sefaria-mold per-text license map, for the day a teiHeader DOES
      # carry an <availability>/<licence> grant: only an explicit
      # machine-recognizable statement maps; anything else (including the
      # censused silence) returns nil and the source-level nc governs.
      def self.license_override_for(availability)
        return nil if availability.nil?

        case availability
        when /public\s+domain/i then "open"
        # share-alike maps nc: CC's own transcription grant couples SA with
        # the non-commercial wording (homepage License section).
        when /non.?commercial|\bnc\b|share.?alike/i then "nc"
        when /creative\s+commons\s+attribution|cc\s*by\b/i then "attribution"
        end
      end

      # +delay+ exists for the WebMock'd tests (0); real syncs keep the
      # polite default. +corpus_idnos+ is the scope seam (v1: PL).
      def initialize(delay: Nabu::CorpusCorporumFetch::DELAY,
                     corpus_idnos: Nabu::CorpusCorporumFetch::DEFAULT_CORPUS_IDNOS)
        super()
        @delay = delay
        @corpus_idnos = corpus_idnos
      end

      # One DocumentRef per texts/<idno>.xml, sorted by urn. A pre-fetch
      # workdir yields nothing (texts/ absent); catalog listings and the
      # state file never match.
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        document_refs(workdir).each(&block)
      end

      # Delegate to the corpus-corporum-tei parser; the license mapper turns
      # a captured availability into a per-document override (nil on the
      # censused silent headers — the source nc class governs).
      def parse(document_ref)
        CorpusCorporumTeiParser.new.parse(
          document_ref.path,
          urn: document_ref.id, language: LANGUAGE,
          license_mapper: self.class.method(:license_override_for)
        )
      rescue Nabu::ValidationError => e
        raise ParseError, "#{document_ref.path}: #{e.message}"
      end

      # The owner-fired catalog walk + per-text downloads (never in tests —
      # WebMock blocks the network): polite, two-grain resumable,
      # non-destructive (attic + breaker), refusals recorded.
      def fetch(workdir, progress: nil, force: false)
        result = Nabu::CorpusCorporumFetch.sync!(
          base_url: BASE_URL, dir: workdir, attic_dir: File.join(workdir, ATTIC_DIRNAME),
          corpus_idnos: @corpus_idnos, delay: @delay, progress: progress,
          guard: ->(doomed) { guard_mass_deletion!(workdir, doomed, force: force) }
        )
        Nabu::FetchReport.new(sha: result.sha, fetched_at: Time.now, notes: fetch_notes(result))
      rescue Nabu::CorpusCorporumFetch::Error => e
        raise Nabu::FetchError, "corpus-corporum fetch failed into #{workdir}: #{e.message}"
      end

      private

      def document_refs(workdir)
        Dir.glob(File.join(workdir, Nabu::CorpusCorporumFetch::TEXTS_DIR, "*.xml")).filter_map do |path|
          match = TEXT_FILENAME.match(File.basename(path)) or next
          Nabu::DocumentRef.new(
            source_id: manifest.id,
            id: "#{URN_PREFIX}#{match[1]}",
            path: File.expand_path(path),
            metadata: { "idno" => match[1] }
          )
        end.sort_by(&:id)
      end

      def fetch_notes(result)
        census = result.corpora.map { |row| "#{row['name']} #{row['texts_count']} texts" }.join(", ")
        base = "catalog walked (#{census}; #{result.texts} texts listed, #{result.fetched} fetched, " \
               "#{result.cached} already on disk)"
        [base, refusal_notes(result.refused), inaccessible_notes(result.inaccessible),
         attic_notes(result.atticked)].compact.join("; ")
      end

      def refusal_notes(refused)
        return nil if refused.empty?

        named = refused.first(3).join(", ")
        tail = refused.size > 3 ? ", …" : ""
        "#{refused.size} download#{'s' if refused.size > 1} refused upstream (idno #{named}#{tail} — " \
          "recorded skips, re-attempted next sync)"
      end

      def inaccessible_notes(inaccessible)
        return nil if inaccessible.zero?

        "#{inaccessible} catalog text#{'s' if inaccessible > 1} flagged inaccessible (never requested)"
      end
    end
  end
end

# frozen_string_literal: true

require_relative "elephantine_tei_parser"
require_relative "../elephantine_fetch"

module Nabu
  module Adapters
    # The Elephantine adapter (P47-1): the Berlin ERC project "Localizing
    # 4000 Years of Cultural History" (elephantine.smb.museum) — the
    # island's multilingual documentary corpus and the library's first
    # substantial Imperial Aramaic document shelf. A thin composition of
    # the ElephantineTeiParser family with the ElephantineFetch id-manifest
    # crawl.
    #
    # == The corpus (census 2026-07-26, ~250 polite requests, verified)
    #
    # 10,744 objects ("10744 Results", exactly matching the extracted id
    # set); 5,223 carry the site's transcription flag — but the flag is
    # advisory only (2/52 flagged samples were all-lacunae; the parser's
    # readable predicate rules). Per-language (total / with-text): Greek
    # 3,326/2,473 · Imperial Aramaic 1,193/892 · Demotic 1,427/833 ·
    # Coptic 454/417 · Old-Egyptian hieratic ostraca 2,080/26 · Middle
    # Egyptian family 941/320 · Arabic 962/72 · Phoenician 94/93 · Latin
    # 22/11 · plus Meroitic/Carian/Syriac slivers; 62 records lack a
    # primary language (→ und). The WHOLE corpus is crawled — catalog-only
    # records still feed metadata/dating/TM links (~315 MB total).
    #
    # == Layout (what fetch lands under <workdir>/)
    #
    #   elephantine_erc_db_<ID6>.tei.xml   one record per object (flat, as
    #                                      upstream's /xml/ dir serves them)
    #   elephantine_erc_db_{places,modern_persons,literature,
    #     ancient_persons}.tei.xml         the four authority files
    #   objects_index.html                 the persisted listing POST
    #                                      (metadata sidecar)
    #
    # == Identity (FROZEN minting)
    #
    # urn = urn:nabu:elephantine:<ID6> — the root TEI xml:id's zero-padded
    # object id, the canonical id of the frozen export. discover mints from
    # the filename; parse cross-checks the in-file xml:id (drift
    # quarantines). With `translations: true` (the registry posture)
    # discover also yields one <urn>-en sibling ref per record — the aes
    # -de / oracc -en parallel-document mold; records without a readable
    # English div skip by rule at parse (DocumentSkipped).
    #
    # == License (D46-a shape; owner pre-wire ruling flagged D47-d)
    #
    # Every record's own <licence target=".../by-sa/3.0/"> grants CC BY-SA
    # 3.0 Unported — zero deviations across 76 censused files, re-pinned at
    # every parse. The SITE's legal notice (/project/legal_notice.html)
    # contradicts it, claiming CC BY-NC-SA 3.0 DE for all site text — the
    # discrepancy is recorded verbatim in the manifest and the registry;
    # per the D46-a precedent the per-file grant governs → attribution.
    # Images (<surrogates> graphics) are OUT OF SCOPE and never fetched.
    #
    # == fetch / sync policy
    #
    # ElephantineFetch: one listing POST (session-truncation defense) +
    # per-id GETs at 1 req/s (~3 h whole corpus), resume at the file grain,
    # 404-on-a-promised-id loud, retention via the attic + the
    # mass-deletion breaker. Upstream is a single frozen 2022 export
    # (every sampled file Last-Modified 2022-11-24) — sync_policy: manual,
    # wired: false until the owner-fired first sync.
    class Elephantine < Nabu::Adapter
      BASE_URL = "https://elephantine.smb.museum"

      MANIFEST = Nabu::SourceManifest.new(
        id: "elephantine",
        name: "Elephantine — the Berlin ERC papyri and ostraca database",
        license: "CC BY-SA 3.0 Unported — the per-document in-file grant (<licence " \
                 "target=\"creativecommons.org/licenses/by-sa/3.0/\"> \"Licence for this TEI " \
                 "document: Creative Commons, Attribution-ShareAlike 3.0 Unported\", zero " \
                 "deviations censused, re-pinned at every parse); the SITE legal notice " \
                 "contradicts it, claiming CC BY-NC-SA 3.0 DE for all site text — recorded " \
                 "discrepancy, the per-file grant governs (D46-a precedent; owner pre-wire " \
                 "ruling D47-d)",
        license_class: "attribution",
        upstream_url: BASE_URL,
        parser_family: "elephantine-tei"
      )

      TRANSLATION_SUFFIX = "-en"

      # A record file as the crawl writes it; authority files (non-digit
      # stems) deliberately do not match.
      RECORD_FILENAME = Nabu::ElephantineFetch::RECORD_FILENAME

      def self.manifest
        MANIFEST
      end

      # P11-2: no git repo — the probe HEADs one stable record TEI
      # (reachability + Last-Modified drift against the ledger pin; the
      # frozen export serves ETag/Last-Modified). No license endpoint —
      # the grant lives in every file — so the license row reads unchecked.
      def self.remote_probe_strategy = :http_zip

      def self.http_probe_targets
        [Nabu::Adapter::HttpProbeTarget.new(
          label: "elephantine_erc_db_002881.tei.xml",
          zip_url: Nabu::ElephantineFetch.record_url(BASE_URL, "2881"),
          metadata_url: nil, state_subdir: "",
          state_file: Nabu::ElephantineFetch::STATE_FILE
        )]
      end

      # +translations+: when true (the registry row's posture), discover
      # also yields one -en sibling ref per record. +delay+ exists for the
      # WebMock'd tests (0); real syncs keep the polite default.
      def initialize(translations: false, delay: Nabu::ElephantineFetch::DELAY)
        super()
        @translations = translations
        @delay = delay
      end

      # One DocumentRef per record file (plus -en siblings when opted in),
      # sorted by urn. A workdir without records yields nothing (the
      # day-one pre-fetch state); authority files and the listing sidecar
      # never match.
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        document_refs(workdir).each(&block)
      end

      # The four authority files are content-pattern files discover
      # deliberately skips — an explicit, benign rule, censused here so the
      # accounting never hides them.
      def discovery_skips(workdir)
        skipped = Dir.glob(File.join(workdir, "elephantine_erc_db_*.tei.xml"))
                     .count { |path| !RECORD_FILENAME.match?(File.basename(path)) }
        DiscoverySkips.new(skipped_by_rule: skipped)
      end

      # Originals parse the edition div; -en refs (metadata
      # "kind" => "translation") mint the English sibling from the same
      # file.
      def parse(document_ref)
        parser = ElephantineTeiParser.new
        if document_ref.metadata["kind"] == "translation"
          parser.parse_translation(document_ref.path, urn: document_ref.id)
        else
          parser.parse(document_ref.path, urn: document_ref.id)
        end
      rescue Nabu::ValidationError => e
        raise ParseError, "#{document_ref.path}: #{e.message}"
      end

      # The owner-fired manifest crawl (never in tests — WebMock blocks the
      # network): listing POST + per-id TEI GETs + authority files, polite,
      # resumable, non-destructive (attic + breaker).
      def fetch(workdir, progress: nil, force: false)
        result = Nabu::ElephantineFetch.sync!(
          base_url: BASE_URL, dir: workdir, attic_dir: File.join(workdir, ATTIC_DIRNAME),
          delay: @delay, progress: progress,
          guard: ->(doomed) { guard_mass_deletion!(workdir, doomed, force: force) }
        )
        Nabu::FetchReport.new(sha: result.sha, fetched_at: Time.now, notes: fetch_notes(result))
      rescue Nabu::ElephantineFetch::Error => e
        raise Nabu::FetchError, "elephantine fetch failed into #{workdir}: #{e.message}"
      end

      private

      def document_refs(workdir)
        Dir.glob(File.join(workdir, "elephantine_erc_db_*.tei.xml")).flat_map do |path|
          match = RECORD_FILENAME.match(File.basename(path)) or next []
          urn = "#{ElephantineTeiParser::URN_PREFIX}#{match[1]}"
          refs = [Nabu::DocumentRef.new(source_id: manifest.id, id: urn, path: File.expand_path(path))]
          if @translations
            refs << Nabu::DocumentRef.new(
              source_id: manifest.id, id: "#{urn}#{TRANSLATION_SUFFIX}",
              path: File.expand_path(path), metadata: { "kind" => "translation" }
            )
          end
          refs
        end.sort_by(&:id)
      end

      def fetch_notes(result)
        base = "objects listing verified (#{result.manifest_count} ids, #{result.records} records; " \
               "#{result.fetched} fetched, #{result.cached} already on disk)"
        [base, missing_notes(result.missing), attic_notes(result.atticked)].compact.join("; ")
      end

      # P47-i1: promised-but-missing upstream records, censused by the
      # fetch — named (first 3) so the tail is honest, never a guessing
      # game.
      def missing_notes(missing)
        return nil if missing.empty?

        named = missing.first(3).join(", ")
        tail = missing.size > 3 ? ", …" : ""
        "#{missing.size} promised id#{'s' if missing.size > 1} 404 upstream " \
          "(#{named}#{tail} — the live listing outruns the frozen 2022 export)"
      end
    end
  end
end

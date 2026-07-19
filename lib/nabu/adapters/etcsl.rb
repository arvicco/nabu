# frozen_string_literal: true

require_relative "etcsl_tei_parser"
require_relative "../zip_fetch"

module Nabu
  module Adapters
    # The ETCSL adapter (P31-5): the Electronic Text Corpus of Sumerian
    # Literature, Revised edition (Oxford, October 2006; Black, Zólyomi,
    # Cunningham, Robson, Ebeling et al.) — 394 Sumerian composite
    # transliterations, hand-lemmatized to the editorial lexeme layer, with
    # 381 paired English prose translations. A thin composition of the
    # EtcslTeiParser family over one frozen zip.
    #
    # == Source of record: the OTA's LLDS home (fetch verified 2026-07-19)
    #
    # The delivery unit is etcsl.zip (4,910,212 bytes) on the Oxford Text
    # Archive record, whose CURRENT official home is the CLARIN-UK Language
    # and Linguistic Data Service (LLDS) repository — hdl 20.500.14106/2518.
    # The legacy ota.bodleian.ox.ac.uk record (hdl 20.500.12024/2518)
    # answered 502/504 throughout 2026-07-18/19: the Bodleian legacy server
    # is down after a major IT incident and "is not being updated"; since
    # 2021 the OTA collections live on LLDS (funding assured through 2029).
    # The corpus was COMPLETED in October 2006 and the artifact is frozen,
    # so the fetch pins its sha256 (the diorisis/IE-CoR choreography:
    # prepare → verify pin → breaker → complete; a mismatch aborts with the
    # tree untouched — a change would be corruption or a deliberate
    # re-deposit, either way an owner decision). sync_policy frozen.
    #
    # == License (record-level; the artifact carries none)
    #
    # The LLDS record states, verbatim: "This item is Publicly Available
    # and licensed under: Attribution-NonCommercial-ShareAlike 3.0 Unported
    # (CC BY-NC-SA 3.0)" (creativecommons.org/licenses/by-nc-sa/3.0/).
    # Nothing inside the zip (corphdr.xml, per-file teiHeaders, readme.txt)
    # carries any availability statement — the record-level grant is the
    # ONLY license layer, hence license_class "nc" and MCP exclusion
    # discipline downstream.
    #
    # == Second witness beside epsd2/literary (MW-beside-kaikki)
    #
    # The epsd2/literary ORACC project (sibling packet P31-0) edits the
    # same compositions with its own lemmatization. ETCSL mints as its OWN
    # source — deliberately unmerged, provenance-distinct editions; the
    # witnesses meet at the "etcsl:<num>" reference-edge key space
    # (reference_edges? + producer "etcsl"): every document asserts its own
    # composition number plus its body xref targets (metadata "related"),
    # and the ORACC side's Q-number↔ETCSL concordance mints into the same
    # compact keys.
    #
    # == Translations (registry `translations: true` — the riig pattern)
    #
    # Upstream pairs c.<num>.xml with t.<num>.xml (censused: every t has
    # its c; 13 c — the ancient literary catalogues — have no t). When the
    # registry opts in, discover mints one urn:nabu:etcsl:<num>-en sibling
    # per pair whose translation file carries prose — the minting decision
    # is the parser's own extraction (the P25-3 doctrine). Same record
    # grant (same artifact) — no license override.
    class Etcsl < Nabu::Adapter
      RECORD_URL = "https://llds.ling-phil.ox.ac.uk/llds/xmlui/handle/20.500.14106/2518"
      ZIP_URL = "https://llds.ling-phil.ox.ac.uk/llds/xmlui/bitstream/handle/20.500.14106/2518/" \
                "etcsl.zip?sequence=12&isAllowed=y"

      # sha256 of the 4,910,212-byte zip, pinned from the verified
      # 2026-07-19 download (fixture README documents the retrieval).
      ZIP_SHA256 = "d1a35b396399216deaeb483d5954ae603662e73c4e77f23e39f2e7b58466962b"

      TRANSLITERATIONS_DIRNAME = "transliterations"
      TRANSLATIONS_DIRNAME = "translations"

      URN_PREFIX = EtcslTeiParser::URN_PREFIX

      MANIFEST = Nabu::SourceManifest.new(
        id: "etcsl",
        name: "ETCSL — Electronic Text Corpus of Sumerian Literature (Oxford, revised edition 2006)",
        license: "CC BY-NC-SA 3.0 (the LLDS/OTA record, hdl 20.500.14106/2518, verbatim: \"This item " \
                 "is Publicly Available and licensed under: Attribution-NonCommercial-ShareAlike 3.0 " \
                 "Unported (CC BY-NC-SA 3.0)\" — the artifact itself carries no license statement; " \
                 "the record-level grant governs)",
        license_class: "nc",
        upstream_url: RECORD_URL,
        parser_family: "etcsl-tei"
      )

      def self.manifest
        MANIFEST
      end

      # P11-2: no git repo — the probe HEADs the LLDS zip bitstream
      # (reachability + Last-Modified drift vs the .zip-fetch.json pin).
      # metadata_url nil: the grant is record-page HTML, no machine
      # endpoint — the probe's license row honestly reads unchecked.
      def self.remote_probe_strategy = :http_zip

      def self.http_probe_targets
        [Nabu::Adapter::HttpProbeTarget.new(
          label: "etcsl.zip", zip_url: ZIP_URL, metadata_url: nil,
          state_subdir: "", state_file: Nabu::ZipFetch::STATE_FILE
        )]
      end

      # The "etcsl:<num>" concordance edges (class note).
      def self.reference_edges? = true

      def self.reference_producer(catalog:, journal:)
        LibraryReferences.new(catalog: catalog, journal: journal, producer: "etcsl")
      end

      # +translations+ arrives via SourceRegistry::Entry#build_adapter for
      # the opted-in registry row; +pin+ overrides the zip sha (tests; a
      # deliberate owner re-pin drill).
      def initialize(translations: false, pin: ZIP_SHA256)
        super()
        @translations = translations
        @pin = pin
      end

      # One DocumentRef per composite (plus the -en sibling for each paired
      # translation with prose when opted in), sorted by urn. A pre-fetch
      # workdir yields nothing.
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        document_refs(workdir).each(&block)
      end

      # The discovery census (P11-7): translation files that mint no sibling
      # — ALL of them when the registry has not opted in, the prose-less
      # ones when it has — are explicit, benign skips.
      def discovery_skips(workdir)
        skipped = translation_files(workdir).count { |path| !minting_translation?(path) }
        DiscoverySkips.new(skipped_by_rule: skipped)
      end

      def parse(document_ref)
        if document_ref.metadata["kind"] == "translation"
          EtcslTeiParser.new.parse_translation(document_ref.path, urn: document_ref.id)
        else
          EtcslTeiParser.new.parse_composite(document_ref.path, urn: document_ref.id)
        end
      end

      # ZipFetch with the phases driven by hand so the sha pin is checked
      # BETWEEN download and any tree mutation (class note); a 304 replays
      # the stored pin and touches nothing.
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
        raise Nabu::FetchError, "etcsl fetch failed into #{workdir}: #{e.message}"
      end

      private

      def verify_pin!(fetch)
        return if fetch.not_modified? || fetch.sha == @pin

        raise Nabu::FetchError,
              "etcsl: downloaded artifact misses the sha256 pin (expected #{@pin}, got " \
              "#{fetch.sha}) — the corpus was completed in 2006 and the LLDS artifact is " \
              "frozen, so this is corruption or a re-deposit; verify #{RECORD_URL} before re-pinning"
      end

      def fetch_notes(fetch)
        base = fetch.not_modified? ? "not modified (304)" : "2006 corpus sha pin verified"
        [base, attic_notes(fetch.atticked)].compact.join("; ")
      end

      # -- discovery -------------------------------------------------------------

      def document_refs(workdir)
        composite_files(workdir).flat_map { |path| composition_refs(workdir, path) }.sort_by(&:id)
      end

      def composition_refs(workdir, path)
        number = File.basename(path, ".xml").delete_prefix("c.")
        urn = "#{URN_PREFIX}#{number}"
        refs = [Nabu::DocumentRef.new(source_id: manifest.id, id: urn, path: File.expand_path(path))]
        translation = translation_path(workdir, number)
        if translation && minting_translation?(translation)
          refs << Nabu::DocumentRef.new(
            source_id: manifest.id, id: "#{urn}-en", path: File.expand_path(translation),
            metadata: { "kind" => "translation" }
          )
        end
        refs
      end

      def composite_files(workdir)
        Dir.glob(File.join(workdir, TRANSLITERATIONS_DIRNAME, "c.*.xml"))
      end

      def translation_files(workdir)
        Dir.glob(File.join(workdir, TRANSLATIONS_DIRNAME, "t.*.xml"))
      end

      def translation_path(workdir, number)
        path = File.join(workdir, TRANSLATIONS_DIRNAME, "t.#{number}.xml")
        File.file?(path) ? path : nil
      end

      # The sibling-minting decision is the parser's OWN prose extraction
      # (P25-3 doctrine): a -en ref exists iff parse_translation would find
      # paragraphs. An unreadable file mints nothing — the damage surfaces
      # on the owner's radar through the census, never as a doomed ref.
      def minting_translation?(path)
        @translations && EtcslTeiParser.new.translation_paragraphs(path).any?
      rescue ParseError
        false
      end
    end
  end
end

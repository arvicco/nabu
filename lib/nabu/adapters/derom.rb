# frozen_string_literal: true

require_relative "derom_xml_parser"
require_relative "../derom_fetch"

module Nabu
  module Adapters
    # DÉRom — Dictionnaire Étymologique Roman (P56-4; license clarification asked by email 2026-07-25):
    # the Latin→Romance etymological bridge. ~500 Proto-Romance etymon
    # articles (dir. Éva Buchi & Wolfgang Schweickard; ATILF, CNRS/
    # Université de Lorraine & Universität des Saarlandes) from the openly
    # downloadable Ortolang workspace `derom`, served by the diffusion
    # content API. One dictionary (slug derom, language la-vul): one entry
    # per etymon article (headword = the DÉRom phonological reconstruction,
    # ˈlakt-e / kaˈβall-u), the pan-Romance cognat sets as DictionaryReflex
    # rows feeding `nabu etym`'s walk.
    #
    # == Upstream (censused first-hand 2026-08-02, 21 bounded probes)
    #
    # ortolang.fr/market/corpora/derom → repository.ortolang.fr content API,
    # `latest` root (snapshot 4, market tag v1, published 2025-07-24). FIVE
    # open collections: DÉRom 1/2/3 article batches (110+40+38 full
    # articles), 45 renvoi stubs (Mertens 2021 -ura derivatives — gloss +
    # PDF link, no cognats) and 280 "potiches en attente" placeholders
    # (<NonRedige/> — skipped, upstream's own "not written yet" flag).
    # Collections 4 (future DÉRom 4) and 7 (English articles) are
    # AUTH-GATED (303 → Keycloak) and not crawled. Expected first sync:
    # 513 documents → ~233 entries / ~3–4k reflex rows. Next upstream
    # refresh announced for September 2026 (É. Buchi, correspondence
    # 2026-07-29) — a routine future re-sync.
    #
    # == License (the P56-4 gate — Ortolang item metadata, verbatim)
    #
    # The workspace's market item metadata (api/search/items/derom, fixture
    # ortolang-item-license.json): "Licence Creative Commons Attribution -
    # Pas d'Utilisation Commerciale - Partage dans les Mêmes Conditions 4.0
    # International" (license-cc-by-nc-sa-4_0, status "Free for non
    # commercial use") → CC BY-NC-SA 4.0, class `nc`: INGESTIBLE for the
    # owner's personal research catalog, excluded from the MCP serving
    # surface like every nc shelf.
    #
    # == Proto-Romance speaks la-vul (the packet's code decision)
    #
    # The catalog's reflex code space already carries Wiktionary's `la-vul`
    # (Vulgar Latin — 206 dictionary_reflexes rows at decision time), and
    # DÉRom's own doctrine is that Proto-Romance IS spoken Latin — so the
    # shelf adopts la-vul rather than minting a code. Consequence, stated
    # plainly: la-vul is not a `-pro` language, so the shelf gets the
    # wiktionary-cu treatment (direct reflex edges, no closure ascent hop,
    # no display asterisk, outside `define *x` recon scoping) — widening
    # the recon predicate to la-vul is a separate owner decision, not this
    # packet's.
    class Derom < Nabu::Adapter
      CREDIT = "DÉRom — Dictionnaire Étymologique Roman, dir. Éva Buchi & Wolfgang " \
               "Schweickard; ATILF (CNRS/Université de Lorraine) & Universität des " \
               "Saarlandes; Ortolang workspace `derom` (ortolang.fr/market/corpora/derom). " \
               "Cite: Buchi, Éva & Schweickard, Wolfgang (éd.) (2008–): Dictionnaire " \
               "Étymologique Roman (DÉRom), Nancy, ATILF, http://www.atilf.fr/DERom."

      MANIFEST = Nabu::SourceManifest.new(
        id: "derom",
        name: "DÉRom — Dictionnaire Étymologique Roman (ATILF/Ortolang)",
        license: "CC BY-NC-SA 4.0 (Ortolang workspace item metadata, verbatim: \"Licence " \
                 "Creative Commons Attribution - Pas d'Utilisation Commerciale - Partage " \
                 "dans les Mêmes Conditions 4.0 International\", status \"Free for non " \
                 "commercial use\"; retrieved 2026-08-02)",
        license_class: "nc",
        upstream_url: "https://repository.ortolang.fr/api/content/derom/latest",
        parser_family: "derom-xml",
        credit: CREDIT
      )

      DICTIONARY_SLUG = "derom"
      TITLE = "DÉRom — Dictionnaire Étymologique Roman (Proto-Romance etyma)"

      # The la-vul witness section (the liv/P18-5 rider contract):
      # per-record provenance "derom", accreted idempotently at load time.
      LANGUAGE_NOTES = [
        ["la-vul", "witness:derom",
         "DÉRom — Dictionnaire Étymologique Roman (dir. Buchi/Schweickard; ATILF & Universität " \
         "des Saarlandes, Ortolang workspace, CC BY-NC-SA 4.0): ~188 published Proto-Romance " \
         "etymon articles (DÉRom 1–3) + 45 renvoi stubs, phonological reconstruction notation " \
         "(*/ˈlakt-e/, */kaˈβall-u/), each with its pan-Romance cognat set (Romanian to " \
         "Portuguese, 20+ idiomes) as reflex edges. The comparative-reconstruction witness for " \
         "Proto-Romance — DÉRom's doctrine: Proto-Romance IS spoken (\"Vulgar\") Latin, hence " \
         "the la-vul code the crosswalk already speaks."].freeze
      ].freeze

      def self.manifest
        MANIFEST
      end

      def self.content_kind = :dictionary

      # P11-2: reachability probe of the first collection listing (the
      # content API serves index pages without Last-Modified — the ledger
      # pin never drifts from a probe).
      def self.remote_probe_strategy = :http_zip

      def self.http_probe_targets
        [Nabu::Adapter::HttpProbeTarget.new(
          label: Nabu::DeromFetch::COLLECTIONS.first,
          zip_url: Nabu::DeromFetch.collection_url(MANIFEST.upstream_url,
                                                   Nabu::DeromFetch::COLLECTIONS.first),
          metadata_url: nil, state_subdir: "",
          state_file: Nabu::DeromFetch::STATE_FILE
        )]
      end

      # [lang_code, kind, body] rows for the language-notes rider.
      def self.language_notes = LANGUAGE_NOTES

      # +delay+ exists for the WebMock'd tests (0); real syncs keep the
      # polite default. +base_url+ overrides the content API root in tests.
      def initialize(delay: Nabu::DeromFetch::DELAY, base_url: MANIFEST.upstream_url)
        super()
        @delay = delay
        @base_url = base_url
      end

      # One DocumentRef per article XML under its collection dir, path
      # order (the fetch lands the upstream layout verbatim). The id is
      # the upstream filename stem — DÉRom's own ASCII notation for the
      # etymon ('lakt-e, ka'Ball-u), the stable entry key.
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        Dir.glob(File.join(workdir, "*", "*.xml")).each do |path|
          yield Nabu::DocumentRef.new(
            source_id: manifest.id,
            id: "#{DICTIONARY_SLUG}:#{File.basename(path, '.xml')}",
            path: File.expand_path(path)
          )
        end
      end

      # One article → a DictionaryDocument with one entry — or zero for a
      # <NonRedige/> potiche placeholder (the article claims no entry).
      def parse(document_ref)
        entry = DeromXmlParser.new.parse_entry(
          document_ref.path,
          entry_id: File.basename(document_ref.path, ".xml")
        )
        document = Nabu::DictionaryDocument.new(
          slug: DICTIONARY_SLUG, language: DeromXmlParser::LANGUAGE, title: TITLE,
          canonical_path: document_ref.path
        )
        document << entry if entry
        document
      rescue Nabu::ValidationError => e
        raise Nabu::ParseError, "derom: #{document_ref.id}: #{e.message}"
      end

      # The owner-fired crawl (never in tests — WebMock blocks the
      # network): 5 open collection listings + one GET per article XML,
      # polite, resumable, non-destructive (attic + breaker).
      def fetch(workdir, progress: nil, force: false)
        result = Nabu::DeromFetch.sync!(
          base_url: @base_url, dir: workdir,
          attic_dir: File.join(workdir, ATTIC_DIRNAME),
          delay: @delay, progress: progress,
          guard: ->(doomed) { guard_mass_deletion!(workdir, doomed, force: force) }
        )
        Nabu::FetchReport.new(sha: result.sha, fetched_at: Time.now, notes: fetch_notes(result))
      rescue Nabu::DeromFetch::Error => e
        raise Nabu::FetchError, "derom fetch failed into #{workdir}: #{e.message}"
      end

      private

      def fetch_notes(result)
        base = "#{Nabu::DeromFetch::COLLECTIONS.size} open collection indexes verified " \
               "(#{result.manifest_count} article XMLs; #{result.fetched} fetched, " \
               "#{result.cached} already on disk)"
        [base, attic_notes(result.atticked)].compact.join("; ")
      end
    end
  end
end

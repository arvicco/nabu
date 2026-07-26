# frozen_string_literal: true

require_relative "betamasaheft_tei_parser"

module Nabu
  module Adapters
    # Beta maṣāḥǝft Works (P46-2): the Ethiopic (Gǝʿǝz) literature shelf —
    # the Hiob-Ludolf-Zentrum's TEI work-records repo (Univ. Hamburg), one
    # file per work under thousand-range directories (`1-1000/` …) plus a
    # `new/` overflow. Most of the 6,548 records are CATALOG-ONLY (no
    # transcription); the text-bearing minority carries the Gǝʿǝz Bible
    # (near-complete OT, all four Gospels), 1 Enoch, Jubilees, the Kebra
    # nagast, royal chronicles and more. A thin composition of the
    # `betamasaheft-tei` parser family; the adapter owns identity, the
    # selection rule, the licence gate and the fetch.
    #
    # == Identity
    #
    # The filename stem IS the BM work id (== the TEI/@xml:id, "LIT2711Mark"
    # — verified on the fixtures), so:
    #
    #   document urn  urn:nabu:betamasaheft-works:<stem>
    #   passage urn   <document-urn>:<div-path>.<unit>   (…:LIT2711Mark:1.1)
    #
    # ref.id == parse(ref).urn (the conformance identity the sync breaker
    # relies on).
    #
    # == The selection rule (discover, cheap string peeks)
    #
    # A file becomes a ref iff it (a) carries the in-file CC BY-SA <licence>
    # grant, AND (b) has a <div type="edition">, AND (c) shows Ethiopic
    # script in the edition region. Everything else — catalog-only records,
    # the 3 licence-less repo-root packaging files, foreign-language
    # editions — skips BY RULE, quietly (censused in discovery_skips; the
    # corpus norm, never quarantine noise). A file whose <licence> names a
    # DIFFERENT grant than BY-SA is counted UNRECOGNIZED, loudly: a licence
    # drift upstream must never skip silently.
    #
    # == License — D46-a (owner-ratified 2026-07-26)
    #
    # The PER-DOCUMENT in-file grant governs (house doctrine): 6,545 of
    # 6,548 files carry `<licence target=".../by-sa/4.0/">` verbatim →
    # class `attribution`. RECORDED DISCREPANCY: the project website
    # (betamasaheft.eu) blankets its pages CC BY-NC-SA 4.0 — that statement
    # covers the site, not these files; the in-file grant wins. Documents
    # carry the licence statement + per-document attribution (Genesis/the
    # Octateuch credit Ran HaCohen's transcription in-file) in metadata; no
    # license_override is minted (BY-SA == the source class).
    #
    # == fetch / sync policy
    #
    # Sparse GitFetch scoped to the `**/*.xml` cone (the TEI records ARE the
    # repo; schema/build cruft and images never materialize) through the
    # full attic + mass-deletion-breaker contract. The corpus is a living
    # edition → sync_policy manual, wired: false until the owner-fired
    # first real sync.
    class BetamasaheftWorks < Nabu::Adapter
      REPO_URL = "https://github.com/BetaMasaheft/Works"

      # "**/*.xml" both in git's sparse-pattern grammar (any depth) and in
      # Dir.glob's (the fetch-layer materialization probe).
      SPARSE_PATHS = ["**/*.xml"].freeze

      URN_PREFIX = "urn:nabu:betamasaheft-works:"

      BY_SA_TARGET = %r{creativecommons\.org/licenses/by-sa/}
      LICENCE_TAG = /<licence[\s>]/
      EDITION_DIV = /<div\s[^>]*type="edition"/
      ETHIOPIC = /\p{Ethiopic}/

      MANIFEST = Nabu::SourceManifest.new(
        id: "betamasaheft-works",
        name: "Beta maṣāḥǝft Works — Ethiopic literature (Hiob-Ludolf-Zentrum, Hamburg)",
        license: "CC BY-SA 4.0 — the D46-a per-document in-file grant governs (6,545 of 6,548 " \
                 "files carry <licence target=\".../by-sa/4.0/\"> verbatim; \"This file is " \
                 "licensed under the Creative Commons Attribution-ShareAlike 4.0.\"). RECORDED " \
                 "DISCREPANCY: the betamasaheft.eu website blankets its PAGES CC BY-NC-SA 4.0 — " \
                 "the site statement does not govern these files. Per-document transcription " \
                 "credits (e.g. Ran HaCohen's Octateuch) ride document metadata. Cite Beta " \
                 "maṣāḥǝft (betamasaheft.eu), Hiob-Ludolf-Zentrum für Äthiopistik, Hamburg",
        license_class: "attribution",
        upstream_url: REPO_URL,
        parser_family: "betamasaheft-tei"
      )

      def self.manifest
        MANIFEST
      end

      # One DocumentRef per text-bearing licensed record, sorted by urn. A
      # pre-fetch workdir yields nothing. Dir.glob's `**` never matches
      # dotdirs, so `.attic` stays out of live discovery while the same
      # walk works FOR the attic when the base class points it there.
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        scan(workdir).refs.each(&block)
      end

      # The discovery census (P11-7): catalog-only, licence-less and
      # non-Ethiopic files are EXPLICIT quiet skips; a file carrying a
      # non-BY-SA licence is UNRECOGNIZED — licence drift, rendered loudly.
      def discovery_skips(workdir)
        scan(workdir).skips
      end

      def parse(document_ref)
        BetamasaheftTeiParser.new.parse(document_ref.path, urn: document_ref.id)
      rescue Nabu::ValidationError => e
        raise ParseError, "#{document_ref.path}: #{e.message}"
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

      Scan = Data.define(:refs, :skips)
      private_constant :Scan

      # One pass over every XML in the tree (root packaging files included —
      # they fail the licence peek and are censused): cheap string peeks
      # only, no XML parsing.
      def scan(workdir)
        refs = []
        skipped = 0
        unrecognized = []
        xml_files(workdir).each do |path|
          case classify(File.read(path))
          when :text_bearing then refs << ref_for(workdir, path)
          when :unrecognized_licence
            unrecognized << "#{File.basename(path)}: in-file <licence> is not the BY-SA grant"
          else skipped += 1
          end
        end
        Scan.new(refs: refs.sort_by(&:id),
                 skips: DiscoverySkips.new(skipped_by_rule: skipped,
                                           unrecognized: unrecognized.size, notes: unrecognized))
      end

      def xml_files(workdir)
        Dir.glob(File.join(workdir, "**", "*.xml"))
      end

      def classify(content)
        return :no_licence unless content.match?(LICENCE_TAG)
        return :unrecognized_licence unless licence_target(content)&.match?(BY_SA_TARGET)

        edition_at = content.index(EDITION_DIV) or return :catalog_only
        return :no_ethiopic unless content[edition_at..].match?(ETHIOPIC)

        :text_bearing
      end

      def licence_target(content)
        content[/<licence\s[^>]*target="([^"]+)"/, 1]
      end

      def ref_for(_workdir, path)
        stem = File.basename(path, ".xml")
        Nabu::DocumentRef.new(
          source_id: manifest.id,
          id: "#{URN_PREFIX}#{stem}",
          path: File.expand_path(path),
          metadata: { "stem" => stem, "dir" => File.basename(File.dirname(path)) }
        )
      end
    end
  end
end

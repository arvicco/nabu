# frozen_string_literal: true

require_relative "iip_epidoc_parser"

module Nabu
  module Adapters
    # The Inscriptions of Israel/Palestine adapter (P30-6): Brown
    # University's IIP (Satlow; github.com/Brown-University-Library/
    # iip-texts) — Hebrew/Aramaic/Greek/Latin epigraphy of the southern
    # Levant, ~500 BCE–640 CE. A thin composition of the IipEpidocParser
    # family with the shared GitFetch choreography (the isicily shape:
    # one ordinary git repo).
    #
    # == Census (2026-07-18, commit 0b7dc835 — the fixture pin)
    #
    # 5,536 epidoc-files/*.xml (5,535 records + upstream's aaTestFile.xml
    # template, excluded by the filename shape and counted as
    # skipped-by-rule). textLang/@mainLang: grc 2,919 · arc 1,755 ·
    # he 376 · la 273 · phn 20 · syc 4 · xcl 4 · heb 2 · geo 2 ·
    # explicit-unknown/empty 8; 171 records add @otherLangs. The Jewish
    # Aramaic layer (arc, byte-verbatim under the P26-3 NFC exemption) is
    # the corpus's distinctive value. NO concordance idnos exist (the
    # only idno/@type corpus-wide is IIP itself) → no reference edges.
    #
    # == License (class nc — what the bytes say, three layers)
    #
    # - The repo has NO LICENSE file; GitHub's license field is null.
    # - Working epidoc-files/ defer their publicationStmt to an xi:include
    #   of a Brown server (not in the repo).
    # - The ARCHIVAL copies in the same repo (archival-files/, xi:includes
    #   resolved) carry it verbatim: "This work is licensed under a
    #   Creative Commons Attribution-NonCommercial 4.0 International
    #   License." + "Distributed under a Creative Commons licence
    #   CC BY-NC 4.0" + the DOI-link attribution requirement
    #   (doi.org/10.26300/pz1d-st89).
    # → nc: local research use only, never redistributed, never exposed
    # to any external or commercial surface.
    #
    # == fetch / sync policy
    #
    # One git repo through the shared non-destructive GitFetch
    # choreography (#git_fetch!). Upstream commits sporadically (master
    # tip 2024-07 at the census) → sync_policy manual, owner-fired.
    class Iip < Nabu::Adapter
      REPO_URL = "https://github.com/Brown-University-Library/iip-texts"

      RECORDS_DIRNAME = "epidoc-files"

      # A record file as the repo spells it: four-letter site sigil + four
      # digits + an occasional letter suffix (jeru0100a). The directory's
      # aaTestFile.xml template breaks the shape and is skipped by rule.
      RECORD_FILENAME = /\A[a-z]{4}\d{4}[a-z]?\.xml\z/

      MANIFEST = Nabu::SourceManifest.new(
        id: "iip",
        name: "Inscriptions of Israel/Palestine (Brown University)",
        license: "CC BY-NC 4.0. The repo itself has no LICENSE file (GitHub license field null) " \
                 "and the working files defer their publicationStmt to a Brown-server xi:include; " \
                 "the archival copies IN the repo (archival-files/, xi:includes resolved) state it " \
                 "verbatim: \"This work is licensed under a Creative Commons " \
                 "Attribution-NonCommercial 4.0 International License.\" (target " \
                 "creativecommons.org/licenses/by-nc/4.0/), reuse \"must contain somewhere a link " \
                 "to the DOI of the Inscriptions of Israel/Palestine Project: " \
                 "https://doi.org/10.26300/pz1d-st89\"",
        license_class: "nc",
        upstream_url: REPO_URL,
        parser_family: "iip-epidoc"
      )

      def self.manifest
        MANIFEST
      end

      # One DocumentRef per record file, sorted by urn. A workdir without
      # epidoc-files/ yields nothing (the day-one pre-clone state).
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        document_refs(workdir).each(&block)
      end

      # Non-record .xml beside the records (aaTestFile.xml — 1 at the
      # pinned commit) is an explicit, benign skip: visible, never silent.
      def discovery_skips(workdir)
        skipped = Dir.glob(File.join(workdir, RECORDS_DIRNAME, "*.xml"))
                     .count { |path| !RECORD_FILENAME.match?(File.basename(path)) }
        DiscoverySkips.new(skipped_by_rule: skipped)
      end

      def parse(document_ref)
        IipEpidocParser.new.parse(document_ref.path, urn: document_ref.id)
      end

      # One git repo, the shared non-destructive choreography (fetch →
      # breaker → attic → ff-merge).
      def fetch(workdir, progress: nil, force: false)
        git_fetch!(repo_url: REPO_URL, workdir: workdir, progress: progress, force: force)
      end

      private

      def document_refs(workdir)
        Dir.glob(File.join(workdir, RECORDS_DIRNAME, "*.xml"))
           .select { |path| RECORD_FILENAME.match?(File.basename(path)) }
           .map do |path|
          Nabu::DocumentRef.new(
            source_id: manifest.id,
            id: "#{IipEpidocParser::URN_PREFIX}#{File.basename(path, '.xml')}",
            path: File.expand_path(path)
          )
        end.sort_by(&:id)
      end
    end
  end
end

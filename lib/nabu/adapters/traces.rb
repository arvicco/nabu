# frozen_string_literal: true

require_relative "traces_ling_parser"

module Nabu
  module Adapters
    # TraCES (P46-2): the TEI-Ling export of the TraCES project ("From
    # Translation to Creation: Changes in Ethiopic Style and Lexicon from
    # Late Antiquity to the Middle Ages", ERC Advanced Grant 338756,
    # Hamburg) — 15 files / 75,440 morphologically analyzed Gǝʿǝz word
    # tokens: Matthew, the Kebra nagast prologue + 25 chapters, the ʿAmda
    # Ṣǝyon chronicle, Testamentum Domini, the "MM" and "AK" corpora, Gadla
    # Libānos excerpts, and seven Aksumite royal inscriptions (RIE 187-232).
    # Every token carries fidäl + transliteration + full morphology + a
    # `lex` lemma link whose L-prefixed half IS a Dillmann entry id — the
    # gold lemma lane of the Gǝʿǝz shelf, crosswalked into the dillmann
    # dictionary. A thin composition of the `traces-teiling` parser family.
    #
    # == Identity — the curated filename census
    #
    # Upstream filenames are working exports ("KN_Prolog-25 Ch_GeTa
    # Ver5_5February2019TEILing.xml", spaces and all) and only ten files
    # carry a TEI @corresp (one of them a typo: REI193 for RIE 193 II). So
    # document ids come from FILE_IDS — a curated census of the 15 known
    # files minting stable scholarly ids (urn:nabu:traces:matthew,
    # …:rie232) — with a deterministic sanitized-stem fallback for any file
    # upstream adds later (loud in review, never a crash). @corresp rides
    # document metadata verbatim, typo included. Passages are w<k> token
    # ordinals (the export has no chapter/verse apparatus).
    #
    # == License — D46-b (owner-ratified 2026-07-26)
    #
    # The repo itself carries NO license file or in-file grant. The same
    # export is deposited in the official Hamburg research-data archive —
    # fdr.uni-hamburg.de record 707, DOI 10.25592/uhhfdm.707 — under
    # CC BY-NC-ND 4.0, and those terms govern here → class `nc` (MCP
    # default-excluded, never redistributed).
    #
    # == fetch / sync policy
    #
    # Plain GitFetch of the whole flat repo (~137 MB working tree, 16 XML
    # files) through the attic + breaker contract. The project ended and
    # the export is effectively frozen → sync_policy manual, wired: false
    # until the owner-fired first sync.
    class Traces < Nabu::Adapter
      REPO_URL = "https://github.com/BetaMasaheft/traces"

      LANGUAGE = "gez"
      URN_PREFIX = "urn:nabu:traces:"

      # The curated census (class note): upstream filename → stable id.
      FILE_IDS = {
        "Matthew_GeTa Ver5_25Juni18TEILing.xml" => "matthew",
        "KN_Prolog-25 Ch_GeTa Ver5_5February2019TEILing.xml" => "kebra-nagast-prolog",
        "AmdaSeyonTEILing.xml" => "amda-seyon",
        "KidGeTa Ver5_25Juni18TEILing.xml" => "testamentum-domini",
        "MMTEILing.xml" => "mm",
        "AK_GeTa Ver5_25Juni18TEILing.xml" => "ak",
        "Libanos_1preambulo_Version_17_04_2019GeTa Ver5_2April2019TEILing.xml" =>
          "gadla-libanos-preambulo",
        "2nascita_vocazione_Version_17_05_10GeTa Ver5_2April2019TEILing.xml" =>
          "gadla-libanos-nascita-vocazione",
        "RIE187TEILing.xml" => "rie187",
        "Rie188TEILing.xml" => "rie188",
        "RIE189TEILing.xml" => "rie189",
        "RIE193ITEILing.xml" => "rie193i",
        "RIE193IITEILing.xml" => "rie193ii",
        "RIE195ITEILing.xml" => "rie195i",
        "RIE232TEILing.xml" => "rie232"
      }.freeze

      # Display titles for the censused files (the exports' own teiHeaders
      # are empty stubs).
      TITLES = {
        "matthew" => "Gospel of Matthew (TraCES analyzed text)",
        "kebra-nagast-prolog" => "Kebra nagast, prologue and chapters 1-25 (TraCES analyzed text)",
        "amda-seyon" => "Chronicle of ʿAmda Ṣǝyon (TraCES analyzed text)",
        "testamentum-domini" => "Testamentum Domini (TraCES analyzed text)",
        "mm" => "MM corpus (TraCES analyzed text)",
        "ak" => "AK corpus (TraCES analyzed text)",
        "gadla-libanos-preambulo" => "Gadla Libānos, preamble (TraCES analyzed text)",
        "gadla-libanos-nascita-vocazione" =>
          "Gadla Libānos, birth and vocation (TraCES analyzed text)",
        "rie187" => "RIE 187 — Aksumite royal inscription (TraCES analyzed text)",
        "rie188" => "RIE 188 — Aksumite royal inscription (TraCES analyzed text)",
        "rie189" => "RIE 189 — Aksumite royal inscription (TraCES analyzed text)",
        "rie193i" => "RIE 193 I — Aksumite royal inscription (TraCES analyzed text)",
        "rie193ii" => "RIE 193 II — Aksumite royal inscription (TraCES analyzed text)",
        "rie195i" => "RIE 195 I — Aksumite royal inscription (TraCES analyzed text)",
        "rie232" => "RIE 232 — funerary inscription of Giḥo (TraCES analyzed text)"
      }.freeze

      MANIFEST = Nabu::SourceManifest.new(
        id: "traces",
        name: "TraCES — TEI-Ling analyzed Gǝʿǝz corpus (ERC 338756, Hamburg)",
        license: "CC BY-NC-ND 4.0 (class nc). The GitHub export carries NO in-repo license; the " \
                 "governing terms are the official archive deposit's — fdr.uni-hamburg.de " \
                 "record 707, DOI 10.25592/uhhfdm.707, CC BY-NC-ND 4.0 (D46-b). Credit the " \
                 "TraCES project (A. Bausi et al., ERC Advanced Grant 338756), Hiob-Ludolf-" \
                 "Zentrum für Äthiopistik, Hamburg",
        license_class: "nc",
        upstream_url: REPO_URL,
        parser_family: "traces-teiling"
      )

      def self.manifest
        MANIFEST
      end

      # One DocumentRef per *TEILing.xml at the repo root, sorted by id.
      # The stray non-TEILing XML (the Alpheios tool export) skips by rule.
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        teiling_files(workdir).map { |path| ref_for(path) }.sort_by(&:id).each(&block)
      end

      # The discovery census (P11-7): non-TEILing xml files are the one
      # explicit quiet skip.
      def discovery_skips(workdir)
        strays = xml_files(workdir).reject { |path| teiling?(path) }
        DiscoverySkips.new(skipped_by_rule: strays.size)
      end

      def parse(document_ref)
        id = document_ref.metadata.fetch("file_id")
        TracesLingParser.new.parse(
          document_ref.path,
          urn: document_ref.id, language: LANGUAGE, title: TITLES[id] || id
        )
      rescue Nabu::ValidationError => e
        raise ParseError, "#{document_ref.path}: #{e.message}"
      end

      def fetch(workdir, progress: nil, force: false)
        git_fetch!(repo_url: repo_url, workdir: workdir, progress: progress, force: force)
      end

      private

      # Seam for tests (the house local-git pattern).
      def repo_url
        REPO_URL
      end

      def xml_files(workdir)
        Dir.glob(File.join(workdir, "*.xml"))
      end

      def teiling_files(workdir)
        xml_files(workdir).select { |path| teiling?(path) }
      end

      def teiling?(path)
        File.basename(path).end_with?("TEILing.xml")
      end

      def ref_for(path)
        basename = File.basename(path)
        id = FILE_IDS.fetch(basename) { fallback_id(basename) }
        Nabu::DocumentRef.new(
          source_id: manifest.id,
          id: "#{URN_PREFIX}#{id}",
          path: File.expand_path(path),
          metadata: { "file" => basename, "file_id" => id }
        )
      end

      # A file the census does not know yet: deterministic sanitized stem —
      # visible in review (an un-curated id reads like one), never a crash.
      def fallback_id(basename)
        basename.delete_suffix(".xml").delete_suffix("TEILing")
                .downcase.gsub(/[^a-z0-9]+/, "-").gsub(/\A-|-\z/, "")
      end
    end
  end
end

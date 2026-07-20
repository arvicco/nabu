# frozen_string_literal: true

require_relative "srophe_tei_parser"

module Nabu
  module Adapters
    # SyriacCorpus — the Digital Syriac Corpus (P31-4,
    # github.com/srophe/syriac-corpus; BYU/Oxford/Vanderbilt/Texas A&M):
    # 632 TEI documents of classical Syriac literature — Aphrahat's
    # Demonstrations, Ephrem and Jacob of Serugh verse, Peshitta NT
    # letters, hagiography — over the NEW srophe-tei family. The survey's
    # "lowest-friction big win": clean per-file licensing, one flat tree.
    #
    # == Fetch
    #
    # Sparse GitFetch cone ["data/tei"] (632 numeric TEI files ≈ 39 MB of
    # the repo; the webapp modules/build trees never materialize).
    # Upstream drifts slowly (last commit 2026-03) → sync_policy manual.
    #
    # == License (per-file, censused over ALL 632 files 2026-07-19)
    #
    # Every file's <availability> carries licence
    # target="http://creativecommons.org/licenses/by/4.0/" with the text
    # "Creative Commons — Attribution 4.0 International — CC BY 4.0" and
    # the note "This electronic edition is designed for open access
    # reuse. The Syriac base text is in the public domain. The TEI XML
    # edition is copyrighted … under a Creative Commons Attribution 4.0
    # International Public License (CC BY 4.0)." → class attribution.
    # Because the grant is PER-FILE, parse RE-VERIFIES it (the sarit
    # discipline) and quarantines any file whose licence drifts.
    #
    # == Identity and the ADDRESSABILITY VERDICT
    #
    # Document = file, urn:nabu:syriac-corpus:<file number> — the
    # syriaccorpus.org id. The <idno> is NOT trusted to mint: censused,
    # 69.xml carries idno …/61 (duplicating 61.xml's) and 126.xml carries
    # …/125 (a gap in the filename space) — upstream defects; the
    # filename mints, the idno rides metadata verbatim.
    #
    # Passage grain: the corpus has NO uniform citation scheme — numbered
    # section/chapter divs cover only part of it (1,958 of 6,801 divs
    # unnumbered; 5 sibling pairs share (type, n)), p is almost never
    # numbered, l only half the time. So passages are the family's
    # text-bearing blocks in document order, urn <doc>:<ordinal 1-based>
    # (the aspr line-ordinal precedent), and the citation material rides
    # annotations: "tag" (p/ab/lg/l/head), "n" (the block's own number
    # when upstream gives one), "divs" (the enclosing div path as
    # [type, n] pairs, nils preserved), "notes" (apparatus, verbatim,
    # stripped from text by the family). Refs are stable for fixed bytes;
    # an upstream re-edit revises the document (the loader's content
    # hash), never silently reshuffles.
    #
    # == Languages
    #
    # langUsage is censused uniformly "syr" → document language syc.
    # Blocks resolve xml:lang by nearest ancestor: syr → syc, en/eng →
    # eng (editorial heads, parallel translations), ar → ara (12 blocks
    # corpus-wide); anything else is a ParseError, never guessed.
    #
    # == Deep-extraction lanes riding document metadata
    #
    # "author" + "author_ref" (syriaca.org person URI), "work" (the
    # syriaca.org WORK URI from title/@ref — the future concordance
    # lane), "idno" (verbatim), "status" (revisionDesc quality label —
    # uncorrectedTranscription/Edited/ProofedDigitalEdition…: silver is
    # LABELED, the goo300k discipline), "orig_date" (profileDesc origDate
    # attrs + text — the timeline lane, extractor a future packet).
    class SyriacCorpus < Nabu::Adapter
      REPO_URL = "https://github.com/srophe/syriac-corpus"

      SPARSE_PATHS = ["data/tei"].freeze

      TEI_DIR = File.join("data", "tei").freeze

      CC_BY = "http://creativecommons.org/licenses/by/4.0/"

      MANIFEST = Nabu::SourceManifest.new(
        id: "syriac-corpus",
        name: "Digital Syriac Corpus (srophe, 632 TEI documents)",
        license: "CC BY 4.0, per-file <availability> censused over all 632 files (verbatim: " \
                 "\"Creative Commons — Attribution 4.0 International — CC BY 4.0\"; \"This electronic " \
                 "edition is designed for open access reuse. The Syriac base text is in the public " \
                 "domain. The TEI XML edition is copyrighted ... under a Creative Commons Attribution " \
                 "4.0 International Public License (CC BY 4.0)\"); parse re-verifies every file",
        license_class: "attribution",
        upstream_url: REPO_URL,
        parser_family: "srophe-tei"
      )

      URN_PREFIX = "urn:nabu:syriac-corpus:"

      FILE_SHAPE = /\A(\d+)\.xml\z/

      # Raw resolved xml:lang -> nabu language. nil (nothing declared)
      # inherits the corpus language. Anything else fails loudly.
      LANGUAGE_BY_XML = {
        nil => "syc", "syr" => "syc", "en" => "eng", "eng" => "eng", "ar" => "ara"
      }.freeze

      def self.manifest
        MANIFEST
      end

      # One DocumentRef per numeric TEI file, in numeric (= upstream id)
      # order. A workdir without the tree (pre-fetch) yields nothing.
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        numbered_files(workdir).each do |number, path|
          yield Nabu::DocumentRef.new(
            source_id: manifest.id,
            id: "#{URN_PREFIX}#{number}",
            path: path,
            metadata: { "file" => File.basename(path) }
          )
        end
      end

      # Non-numeric xml under data/tei matches the source's shape but can
      # never mint a ref — flagged unrecognized (P11-7), never silent.
      def discovery_skips(workdir)
        strays = Dir[File.join(workdir, TEI_DIR, "*.xml")]
                 .reject { |path| FILE_SHAPE.match?(File.basename(path)) }.sort
        DiscoverySkips.new(
          unrecognized: strays.size,
          notes: strays.map { |path| "#{File.basename(path)}: not the <number>.xml shape" }
        )
      end

      def parse(document_ref)
        edition = SropheTeiParser.parse(document_ref.path)
        license!(edition)
        document = Nabu::Document.new(
          urn: document_ref.id, language: "syc", title: edition.title,
          canonical_path: document_ref.path, metadata: metadata(edition)
        )
        edition.blocks.each_with_index do |block, index|
          document << passage(block, urn: document_ref.id, index: index)
        end
        document
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

      def numbered_files(workdir)
        Dir[File.join(workdir, TEI_DIR, "*.xml")]
          .filter_map do |path|
            match = FILE_SHAPE.match(File.basename(path))
            [Integer(match[1], 10), path] if match
          end
          .sort
      end

      # The per-file grant is the license of record — re-verify it on
      # every parse; drift quarantines the document, never ingests it.
      def license!(edition)
        return if edition.license_target == CC_BY

        raise ParseError, "#{edition.path}: licence target #{edition.license_target.inspect} is not " \
                          "#{CC_BY.inspect} — the per-file CC BY grant is the ingest condition"
      end

      def metadata(edition)
        metadata = {}
        metadata["idno"] = edition.idno if edition.idno
        metadata["author"] = edition.author if edition.author && !edition.author.empty?
        metadata["author_ref"] = edition.author_ref if edition.author_ref
        metadata["work"] = edition.work_ref if edition.work_ref
        metadata["status"] = edition.status if edition.status
        metadata["orig_date"] = edition.orig_date if edition.orig_date
        metadata
      end

      def passage(block, urn:, index:)
        annotations = { "tag" => block.tag }
        annotations["n"] = block.n if block.n
        annotations["divs"] = block.divs
        annotations["notes"] = block.notes unless block.notes.empty?
        Nabu::Passage.new(
          urn: "#{urn}:#{index + 1}",
          language: language(block),
          text: Nabu::Normalize.nfc(block.text),
          annotations: annotations,
          sequence: index
        )
      end

      def language(block)
        LANGUAGE_BY_XML.fetch(block.lang) do
          raise ParseError, "#{block.divs.inspect}: xml:lang #{block.lang.inspect} is not in the censused " \
                            "syr/en/eng/ar set — a language is never guessed"
        end
      end
    end
  end
end

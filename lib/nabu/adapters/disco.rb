# frozen_string_literal: true

require_relative "disco_tei_parser"

module Nabu
  module Adapters
    # The DISCO adapter (P77-4): the Diachronic Spanish Sonnet Corpus
    # (github.com/pruizf/disco, v5.0 2023-02; Ruiz Fabo, Bermúdez Sabel,
    # Calvo Tello, Martínez Cantón) — 4,530 sonnets by 1,216 authors,
    # 15th–20th century, over the small disco-tei family. The P77
    # medieval-content phase's Romance verse rung beside the cantigas.
    #
    # == Identity (FROZEN minting)
    #
    # Document = one per-author file from tei/all-periods-per-author/ —
    # the corpus's OWN complete aggregation (1,216 files, exact git-tree
    # count 2026-08-13; the per-period and per-sonnet dirs are the same
    # texts re-cut, never ingested — two layouts are not two editions).
    # urn = urn:nabu:disco:<id> from the filename's own id (disco001g →
    # 001g; the trailing letter is the period: g = 15th-17th, e = 18th,
    # n = 19th, t = 20th — upstream's period dir names, carried as
    # document metadata). Passage = one sonnet at the corpus's own
    # trailing ordinal (see DiscoTeiParser). Minting frozen once used.
    #
    # == Language and dating
    #
    # `spa` for every document — the code the derom/wold reflex lanes
    # already hold, so etym/cognate joins connect; the 15th–17th
    # century layer rides under it as the honest one-tag practice
    # (postures row identity). Dating material rides metadata (the
    # period band + the prosopography's birth/death centuries) — the
    # extractor is a future packet, the isicily discipline.
    #
    # == License
    #
    # README verbatim: "The corpus is available under: CC-BY license.";
    # the repo LICENSE file is CC-BY-4.0 → class attribution.
    #
    # == Fetch
    #
    # Sparse GitFetch cone [tei/all-periods-per-author, LICENSE,
    # README.md]. Upstream releases in waves (v5.0 Feb 2023, quiet
    # since) → sync_policy manual.
    class Disco < Nabu::Adapter
      REPO_URL = "https://github.com/pruizf/disco"

      SPARSE_PATHS = [File.join("tei", "all-periods-per-author"), "LICENSE", "README.md"].freeze

      TEI_DIR = File.join("tei", "all-periods-per-author").freeze

      FILE_SHAPE = /\Adisco(\d+[a-z])\.xml\z/

      LANGUAGE = "spa"

      # The id's trailing letter → upstream's own period dir name. An
      # unknown letter quarantines — a period is never guessed.
      PERIODS = { "g" => "15th-17th", "e" => "18th", "n" => "19th", "t" => "20th" }.freeze

      MANIFEST = Nabu::SourceManifest.new(
        id: "disco",
        name: "DISCO — Diachronic Spanish Sonnet Corpus (Ruiz Fabo et al., v5.0)",
        license: "CC BY (README verbatim: \"The corpus is available under: CC-BY license.\"; " \
                 "the repo LICENSE file is CC-BY-4.0)",
        license_class: "attribution",
        upstream_url: REPO_URL,
        parser_family: "disco-tei"
      )

      def self.manifest
        MANIFEST
      end

      # One DocumentRef per author-period file, in id order. A workdir
      # without the tree (pre-fetch) yields nothing.
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        author_files(workdir).each do |id, path|
          yield Nabu::DocumentRef.new(
            source_id: manifest.id, id: "urn:nabu:disco:#{id}", path: path,
            metadata: { "file" => File.basename(path), "id" => id }
          )
        end
      end

      def discovery_skips(workdir)
        strays = Dir[File.join(workdir, TEI_DIR, "*")]
                 .select { |path| File.file?(path) }
                 .reject { |path| FILE_SHAPE.match?(File.basename(path)) }.sort
        DiscoverySkips.new(
          unrecognized: strays.size,
          notes: strays.map { |path| "#{File.basename(path)}: not the disco<id>.xml shape" }
        )
      end

      def parse(document_ref)
        id = document_ref.metadata.fetch("id")
        period = PERIODS.fetch(id[-1]) do
          raise ParseError, "#{document_ref.path}: unknown period letter #{id[-1].inspect} — " \
                            "a period is never guessed"
        end
        DiscoTeiParser.new.parse(document_ref.path, urn: document_ref.id,
                                                    language: LANGUAGE, period: period)
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

      def author_files(workdir)
        Dir[File.join(workdir, TEI_DIR, "*.xml")]
          .filter_map do |path|
            match = FILE_SHAPE.match(File.basename(path))
            [match[1], path] if match
          end
          .sort
      end
    end
  end
end

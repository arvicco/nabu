# frozen_string_literal: true

require_relative "tipitaka_lk_json_parser"

module Nabu
  module Adapters
    # tipitaka.lk (Path Nirvana): the proofread Buddha Jayanthi Tripiṭaka
    # (BJT) — the Sri Lankan Buddha Jayanti edition of the Pāli canon,
    # printed in Sinhala script with a facing Sinhala translation — plus
    # the Chaṭṭha Saṅgāyana (CST) aṭṭhakathā and the Visuddhimagga with
    # their Sinhala translation, from the static JSON the website and apps
    # are built from: github.com/pathnirvana/tipitaka.lk, branch master,
    # public/static/text/*.json ("the ground truth edited by proofreaders.
    # Everything else is generated from it" — upstream README).
    #
    # == Delivery grains (enumerated at fixture time, 2026-10-22, commit
    #    4fe56eb)
    #
    # - public/static/text/<file>.json — 285 files / 355.6 MB: the canon
    #   (vp-*, dn-*, mn-*, sn-*, an-*, kn-*, ap-*) and the commentaries
    #   (atta-*), plus anya-vm* (the Visuddhimagga, which upstream files
    #   under collection "atta"). A file is one printed BJT volume or a
    #   part of one (an-10, an-10-2 …): upstream's own unit of
    #   distribution and of its build. ACCEPTED — the document grain.
    # - The pages and entries inside a file — the passage grain (see the
    #   parser family).
    # - public/static/data/ (tree.json navigation, file-map, sitemap, the
    #   footnote-sigla key), dev/alignments/ (Pāli↔Sinhala word alignments,
    #   partly machine-made), db/dict.db.zip and the dictionary submodule —
    #   generated or reference data, not text. REJECTED: outside the sparse
    #   fetch cone, never fetched (the fixture pins one data/ specimen to
    #   prove discovery never reaches it).
    #
    # == Identity (FROZEN minting)
    #
    # Document = (file × layer). The Pāli root is
    # urn:nabu:tipitaka-lk:<file> (language pli); the Sinhala translation
    # rides as the SIBLING urn:nabu:tipitaka-lk:<file>-si (language si; no
    # upstream filename ends in "-si" — censused, so the tail is a clean
    # sibling declaration), passage-aligned by the shared <page>.<entry>
    # suffix. Upstream's isPaliOnlyFile (/^ap-pat/ — the Paṭṭhāna's seven
    # files) serve an empty Sinhala column and mint no sibling; that is a
    # fact of the corpus, not a skip. A .json under the text dir that
    # upstream's own tree filter (filesFilter in build/tree.ts) would drop
    # is UNRECOGNIZED — upstream's build warns on it too.
    #
    # == Script and language
    #
    # The Pāli is held in Sinhala script (the BJT's own); it claims plain
    # pli (the registry has no Sinhala script tag; the script posture is
    # declared qualified). The translation is modern Sinhala, si.
    #
    # == License — no derivatives, keep in sync, attribute per passage
    #
    # LICENSE.md: CC BY-ND 4.0 for "the Buddha Jayanthi Pali text in
    # Tipitaka.lk", with three conditions — modifications not allowed
    # (errors are reported upstream and corrected there first), the text is
    # kept in sync with the repository by an automated method, attribution
    # to tipitaka.lk. The Sinhala translation and the CST aṭṭhakathā with
    # its Sinhala translation (which LICENSE.md does not name) are covered
    # on the same terms by Path Nirvana's grant, by email, 2026-10-22.
    # ND → research_private (the Freising precedent: local research only,
    # never redistributed, never a nabu-data input). The parse never
    # corrects text (upstream's own plain rendering, verbatim), and every
    # passage carries attribution "tipitaka.lk".
    #
    # == Kind, dates, places
    #
    # The root documents carry facets from upstream's own vocabulary:
    # collection (mula / atta — the JSON field, else upstream's isAttaFile
    # rule), pitaka (vinaya / sutta / abhidhamma from the file key) and
    # nikaya (dn mn sn an kn) — config/kind_map.yml folds collection.
    # Upstream carries no date or place field of any kind: undatable and
    # unplaced are the honest postures (the composition eras of the canon
    # and its commentaries are scholarship, not this asset's data).
    class TipitakaLk < Nabu::Adapter
      REPO_URL = "https://github.com/pathnirvana/tipitaka.lk"
      URN_PREFIX = "urn:nabu:tipitaka-lk:"
      TEXT_DIR = File.join("public", "static", "text")
      SPARSE_PATHS = [TEXT_DIR].freeze
      SIBLING_TAIL = "-si"

      # build/tree.ts filesFilter — the files upstream's own tree admits.
      FILES_FILTER = /\A(?:dn|mn|sn|an|kn|ap|vp|atta|anya)-/
      # shared/constants.ts isPaliOnlyFile.
      PALI_ONLY = /\Aap-pat/

      PITAKA = { "vp" => "vinaya", "dn" => "sutta", "mn" => "sutta", "sn" => "sutta", "an" => "sutta",
                 "kn" => "sutta", "ap" => "abhidhamma" }.freeze
      NIKAYAS = %w[dn mn sn an kn].freeze

      EDITIONS = {
        "mula" => "Buddha Jayanthi Tripiṭaka (BJT), proofread by tipitaka.lk",
        "atta" => "Chaṭṭha Saṅgāyana (CST) aṭṭhakathā, proofread by tipitaka.lk"
      }.freeze

      MANIFEST = Nabu::SourceManifest.new(
        id: "tipitaka-lk",
        name: "tipitaka.lk — Buddha Jayanthi Tripiṭaka and aṭṭhakathā, Pāli and Sinhala (Path Nirvana)",
        license: "CC BY-ND 4.0 with upstream's sync condition (LICENSE.md: modifications not " \
                 "allowed — errors are reported to path.nirvana@gmail.com and corrected upstream " \
                 "first; the text is kept in sync with the repository by an automated method; " \
                 "attribution to tipitaka.lk). LICENSE.md names the Buddha Jayanthi Pāli text; " \
                 "the Sinhala translation and the CST aṭṭhakathā with its Sinhala translation are " \
                 "covered on the same terms by Path Nirvana's grant (by email, 2026-10-22). " \
                 "NoDerivs: local research ingest only, never redistributed",
        license_class: "research_private",
        upstream_url: REPO_URL,
        parser_family: "tipitaka-lk-json"
      )

      def self.manifest
        MANIFEST
      end

      # #parse reads one file and keeps nothing between refs.
      def self.parallel_parse? = true

      # One ref per (file × layer), sorted by urn: the Pāli root for every
      # file upstream's tree admits, the -si sibling unless the file is
      # Pāli-only upstream.
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        text_files(workdir).select { |path| admitted?(path) }.flat_map { |path| refs_for(path) }
                                                             .sort_by(&:id).each(&block)
      end

      # A .json upstream's own tree filter would drop is unrecognized —
      # loud, never silently skipped.
      def discovery_skips(workdir)
        strays = text_files(workdir).reject { |path| admitted?(path) }
        DiscoverySkips.new(
          skipped_by_rule: 0, unrecognized: strays.size,
          notes: strays.map { |path| "#{File.basename(path)}: outside upstream's tree filter (build/tree.ts)" }
        )
      end

      def parse(document_ref)
        layer = document_ref.metadata.fetch("layer")
        key = document_ref.metadata.fetch("file")
        TipitakaLkJsonParser.new.parse(document_ref.path, urn: document_ref.id, layer: layer) do |metadata|
          layer_metadata(key, layer, metadata["collection"])
        end
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

      def text_files(workdir)
        Dir.glob(File.join(workdir, TEXT_DIR, "*.json")).map { |path| File.expand_path(path) }
      end

      def admitted?(path)
        FILES_FILTER.match?(File.basename(path, ".json"))
      end

      def refs_for(path)
        key = File.basename(path, ".json")
        root = ref(path, "#{URN_PREFIX}#{key}", key, "pali")
        return [root] if PALI_ONLY.match?(key)

        [root, ref(path, "#{URN_PREFIX}#{key}#{SIBLING_TAIL}", key, "sinh")]
      end

      def ref(path, urn, key, layer)
        Nabu::DocumentRef.new(source_id: manifest.id, id: urn, path: path,
                              metadata: { "file" => key, "layer" => layer })
      end

      # The layer-dependent document metadata: canon facets + edition on
      # the root, translation provenance on the sibling. +collection+ is
      # upstream's own field; files without it fall back to upstream's
      # isAttaFile rule (an atta- prefix).
      def layer_metadata(key, layer, collection)
        collection ||= key.start_with?("atta-") ? "atta" : "mula"
        edition = EDITIONS.fetch(collection) do
          raise ParseError, "#{key}: unknown upstream collection #{collection.inspect} — classify it first"
        end
        if layer == "pali"
          { "edition" => edition, "facets" => facets(key, collection) }
        else
          { "kind" => "translation", "translation_of" => "#{URN_PREFIX}#{key}",
            "edition" => "Sinhala translation (#{edition})" }
        end
      end

      def facets(key, collection)
        segment = key.delete_prefix("atta-").split("-").first
        {
          "collection" => facet(collection),
          "pitaka" => facet(PITAKA[segment]),
          "nikaya" => facet(NIKAYAS.include?(segment) ? segment : nil)
        }.compact
      end

      def facet(value)
        value.nil? ? nil : { "value" => value, "raw" => value }
      end
    end
  end
end

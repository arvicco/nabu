# frozen_string_literal: true

module Nabu
  module Adapters
    # OSHB — the Open Scriptures Hebrew Bible (P26-3): the Westminster
    # Leningrad Codex as OSIS XML, 39 books under wlc/, with the complete
    # OSHM morphology layer and augmented-Strong's lemmas. The MASORETIC
    # witness the alignment hub's `ot` work gains beside LXX-Swete and the
    # Clementine Vulgate — `align "GEN 1.1"` renders MT ↔ LXX ↔ Vulgate.
    #
    # == Layout and identity (FROZEN minting)
    #
    # One wlc/<Book>.xml = one document: urn = urn:nabu:oshb:<book-stem
    # downcased> (Gen.xml → urn:nabu:oshb:gen, 1Chr.xml → urn:nabu:oshb:1chr),
    # title = the OSIS book code, passage urns <doc-urn>:<chapter>.<verse>
    # from the native Masoretic osisIDs. wlc/VerseMap.xml is the upstream
    # WLC↔KJV versification concordance, not a book — excluded by name.
    #
    # == License per layer (verbatim, verified at fixture time 2026-07-18)
    #
    # WLC text: Public Domain — LICENSE.md: "This work is based on *The
    # Westminster Leningrad Codex*, which is in the public domain."
    # Morphology/lemma layer: CC BY 4.0 — README.md: "Lemma and morphology
    # data are licensed under a Creative Commons Attribution 4.0
    # International license. For attribution purposes, credit the Open
    # Scriptures Hebrew Bible Project." Source class `open`, the CC BY
    # credit carried in the manifest license text below so every serving
    # surface renders it.
    #
    # == The per-language NFC exemption (owner ruling 2026-07-18)
    #
    # WLC bytes are stored EXACTLY as upstream ships them — hbo/arc text is
    # NEVER NFC-normalized (Normalize::NFC_EXEMPT_LANGUAGES; the OSIS
    # parser's class note has the full why). Search folding still passes
    # lookup keys through NFC, so find-ability is unaffected.
    #
    # == fetch
    #
    # The shared git path (Adapter#git_fetch! → GitFetch: attic + pre-merge
    # mass-deletion breaker); the full clone is ~174 MB (wlc/ itself ~27 MB —
    # the rest is git history and the project's site/tooling directories).
    class Oshb < Nabu::Adapter
      MANIFEST = Nabu::SourceManifest.new(
        id: "oshb",
        name: "Open Scriptures Hebrew Bible (Westminster Leningrad Codex + OSHM morphology)",
        license: "WLC text: Public Domain (\"This work is based on The Westminster Leningrad Codex, " \
                 "which is in the public domain.\" — LICENSE.md). Lemma/morphology layer: CC BY 4.0 " \
                 "(\"Lemma and morphology data are licensed under a Creative Commons Attribution 4.0 " \
                 "International license. For attribution purposes, credit the Open Scriptures Hebrew " \
                 "Bible Project.\" — README.md)",
        license_class: "open",
        upstream_url: "https://github.com/openscriptures/morphhb",
        parser_family: "oshb-osis"
      )

      WLC_DIR = "wlc"

      # The WLC↔KJV versification concordance that lives beside the 39 book
      # files — upstream metadata, not a book document.
      NON_BOOK_FILES = %w[VerseMap.xml].freeze

      def self.manifest
        MANIFEST
      end

      # One DocumentRef per wlc/<Book>.xml, sorted by urn; VerseMap.xml is
      # excluded by name. Returns an Enumerator without a block (the adapter
      # contract's lazy shape).
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        document_refs(workdir).each(&block)
      end

      def parse(document_ref)
        OshbOsisParser.new.parse(document_ref.path, urn: document_ref.id)
      end

      def fetch(workdir, progress: nil, force: false)
        git_fetch!(repo_url: repo_url, workdir: workdir, progress: progress, force: force)
      end

      private

      # Split out so fetch tests can point a singleton at a local git tmpdir
      # (the house pattern), keeping fetch off the network.
      def repo_url
        manifest.upstream_url
      end

      def document_refs(workdir)
        Dir.glob(File.join(workdir, WLC_DIR, "*.xml")).filter_map do |path|
          stem = File.basename(path, ".xml")
          next if NON_BOOK_FILES.include?(File.basename(path))

          Nabu::DocumentRef.new(
            source_id: manifest.id,
            id: "urn:nabu:oshb:#{stem.downcase}",
            path: File.expand_path(path),
            metadata: { "book" => stem }
          )
        end.sort_by(&:id)
      end
    end
  end
end

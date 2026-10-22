# frozen_string_literal: true

require_relative "lasla_conllup_parser"

module Nabu
  module Adapters
    # LASLA — the Latin corpus of the Laboratoire d'Analyse Statistique des
    # Langues Anciennes (Université de Liège): classical Latin from Plautus
    # to the 2nd c. AD (Cicero, Caesar, Vergil, Horace, Ovid, Tacitus,
    # Seneca, Pliny …), "semi-automatically lemmatized and annotated with
    # morphosyntactical information, with full manual verification" (the
    # repo README) — GOLD lemmata and morphology on every word. Ingested via
    # CIRCSE's release github.com/CIRCSE/LASLA, which links every token to
    # the LiLa LemmaBank (held as the `lila` module); a thin composition of
    # the `lasla-conllup` family (LaslaConllupParser).
    #
    # == Delivery grains (censused 2026-10-21) and the document
    #
    # The repo serves: conllup/ — 242 CoNLL-U Plus files, one per WORK or per
    # BOOK of a long work (Caesar's Bellum Gallicum = CaesBG1…7), named
    # <Author>_<Work>_<LASLA code>.conllup; texts/ — 131 per-WORK Turtle
    # serializations (.ttl.gz, 65 MB) of the same annotation (upstream's
    # "~130 texts"); complete_lasla.ttl.gz — the whole corpus as one Turtle
    # file (102 MB); lemma_LiLaRef.tsv.gz — the lemma → LiLa crosswalk table.
    # Document = one conllup file (urn:nabu:lasla:<LASLA code>, the code
    # unique across all 242), passage = one sentence. The Turtle lanes and
    # the crosswalk carry the same annotation in RDF and stay outside the
    # sparse fetch cone; a texts/*.ttl.gz present in a workdir is skipped by
    # rule and counted (discovery_skips). Reconciliation: 242 conllup files =
    # upstream's 131 texts with the long works split by book; expected full
    # parse 242 documents / 95,974 passages / 1,875,776 token lines
    # (1,839,371 words + 36,405 multiword-token ranges). Six files (Livy 8,
    # Ovid Met. 6 / 7+11+14 / 9+10, Pliny NH 2 / 37; 92,011 words) carry no
    # LiLa link and no citation hierarchy upstream — gold lemmata all the
    # same, declared here.
    #
    # == Identity and metadata
    #
    # The filename is the only metadata the conllup lane carries: author
    # ("Cicero", "PseudoCaesar1" — verbatim), work ("BellumCivile",
    # "TacHistoriae" — verbatim) and the LASLA code ride document metadata
    # (author/work → facets); the title spaces the work name the way the
    # Turtle lane's own dc:title does ("Cum Quaestor Lilybaeo Decederet
    # Fragmenta"). DECLARED COARSENESS: the Turtle lane's dc:creator
    # Wikidata ids are not fetched (65 MB of RDF for one id per work); no
    # date, place or genre field exists in the asset — per-author floruit
    # dating or genre per work would be a curated overlay, not extraction.
    #
    # == Overlap with held Latin (kept, never deduped)
    #
    # Nearly every LASLA work is also held as a Perseus TEI edition
    # (perseus-latin: Caesar, Cicero, Vergil, Ovid, Tacitus …) and some at
    # treebank grain (ud latin-perseus). LASLA's text is its OWN edition —
    # "based on the available critical editions at the time of the
    # lemmatization but the annotators have modified the texts according to
    # their own editorial decisions" (README) — in LASLA's normalized
    # spelling (u for v, no punctuation). Distinct editions are distinct
    # witnesses: both kept (the sii/dharma-tamil and DipSGG-beside-CorPH
    # precedent).
    #
    # == LICENSE (repo README "Copyright", verbatim, re-read 2026-10-21)
    #
    # "These resources are licensed under a Creative Commons
    # Attribution-NonCommercial-ShareAlike 4.0 International License."
    # → class nc. The README also notes "LASLA texts are available through
    # data-sharing agreements" — the ORIGINAL LASLA files stay gated; this
    # adapter ingests only the openly licensed CIRCSE release.
    #
    # == fetch
    #
    # Sparse GitFetch cone [conllup, README.md] — the Turtle lanes (~170 MB)
    # never transfer. Last upstream push 2024-10-15; no release cadence →
    # sync_policy manual.
    class Lasla < Nabu::Adapter
      REPO_URL = "https://github.com/CIRCSE/LASLA"
      SPARSE_PATHS = ["conllup", "README.md"].freeze
      CONLLUP_DIR = "conllup"
      TEXTS_DIR = "texts"
      LANGUAGE = "lat"
      URN_PREFIX = "urn:nabu:lasla:"

      # <Author>_<Work>_<code>.conllup — three underscore fields on all 242.
      FILENAME = /\A(?<author>[^_]+)_(?<work>[^_]+)_(?<code>[^_]+)\.conllup\z/

      MANIFEST = Nabu::SourceManifest.new(
        id: "lasla",
        name: "LASLA — Latin corpus of the Laboratoire d'Analyse Statistique des Langues Anciennes " \
              "(Liège), CIRCSE LiLa-linked CoNLL-U release",
        license: "CC BY-NC-SA 4.0 (repo README \"Copyright\", verbatim: \"These resources are licensed " \
                 "under a Creative Commons Attribution-NonCommercial-ShareAlike 4.0 International License\"). " \
                 "Credit LASLA (Université de Liège) and LiLa: Linking Latin (ERC grant 769994; linking by " \
                 "M. Passarotti, P. Ruffolo, E. Litta, G. Moretti, M. Fantoli). The original LASLA files " \
                 "remain available only through data-sharing agreements.",
        license_class: "nc",
        upstream_url: REPO_URL,
        parser_family: "lasla-conllup"
      )

      def self.manifest = MANIFEST

      # One DocumentRef per conllup/<Author>_<Work>_<code>.conllup, sorted by
      # urn. A pre-fetch workdir yields nothing.
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        conllup_files(workdir).filter_map { |path| ref_for(path) }.sort_by(&:id).each(&block)
      end

      # The Turtle serialization (texts/*.ttl.gz) is a rejected grain —
      # counted, never a document; anything else in the conllup cone that
      # discover cannot name is unrecognized.
      def discovery_skips(workdir)
        ttl = Dir.glob(File.join(workdir, TEXTS_DIR, "*.ttl.gz"))
        stray = Dir.glob(File.join(workdir, CONLLUP_DIR, "*")).reject do |path|
          File.basename(path).match?(FILENAME)
        end
        notes = []
        notes << "#{ttl.size} texts/*.ttl.gz (the per-work Turtle serialization — same annotation as RDF)" if ttl.any?
        notes += stray.map { |path| "unrecognized file in #{CONLLUP_DIR}/: #{File.basename(path)}" }
        Nabu::Adapter::DiscoverySkips.new(skipped_by_rule: ttl.size, unrecognized: stray.size, notes: notes)
      end

      def parse(document_ref)
        metadata = document_ref.metadata
        LaslaConllupParser.new.parse(
          document_ref.path, urn: document_ref.id, language: LANGUAGE,
                             title: title(metadata), metadata: metadata.dup
        )
      end

      def fetch(workdir, progress: nil, force: false)
        git_fetch!(repo_url: repo_url, workdir: workdir, progress: progress, force: force, sparse: SPARSE_PATHS)
      end

      private

      # Seam for tests (the house local-git pattern).
      def repo_url = REPO_URL

      def conllup_files(workdir) = Dir.glob(File.join(workdir, CONLLUP_DIR, "*.conllup"))

      def ref_for(path)
        match = FILENAME.match(File.basename(path))
        return nil unless match

        Nabu::DocumentRef.new(
          source_id: MANIFEST.id, id: "#{URN_PREFIX}#{match[:code]}", path: File.expand_path(path),
          metadata: { "author" => match[:author], "work" => match[:work], "lasla_code" => match[:code] }
        )
      end

      # "Cicero — Cum Quaestor Lilybaeo Decederet Fragmenta (CicQuaest)".
      def title(metadata)
        work = metadata.fetch("work").gsub(/(?<=[a-z])(?=[A-Z])/, " ")
        "#{metadata.fetch('author')} — #{work} (#{metadata.fetch('lasla_code')})"
      end
    end
  end
end

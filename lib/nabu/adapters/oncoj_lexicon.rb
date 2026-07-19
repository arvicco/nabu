# frozen_string_literal: true

require_relative "oncoj_lexicon_parser"
require_relative "../git_fetch"

module Nabu
  module Adapters
    # The ONCOJ lexicon (P32-2): lexicon.xml of github.com/ONCOJ/data at the
    # PINNED "release" tag — "the dictionary database for the corpus"
    # (upstream README §B) as the ojp dictionary shelf: 5,871 entries in
    # 5,527 superEntry groups (censused at fixture time; one upstream
    # duplicate id re-minted "-b", see OncojLexiconParser).
    #
    # SIBLING of the `oncoj` corpus source: one content kind per adapter is
    # the house shape (the lexlep/lexlep-words precedent), so the repo's two
    # grains are two registry rows sharing the same pinned tag — each with
    # its own sparse cone (this one: lexicon.xml + README only). The join
    # contract: entry ids are exactly the w/@lemma id space corpus tokens
    # reference (measured 99.8% of distinct ids / 99.98% of occurrences
    # resolve; 5,793/5,871 entries are cited by the corpus), and the
    # headword here is the same first-orth form the corpus adapter mints as
    # each token's lemma — so `nabu define` meets `search --lemma` on
    # identical folds.
    class OncojLexicon < Nabu::Adapter
      REPO_URL = "https://github.com/ONCOJ/data"
      RELEASE_TAG = "release" # 2021-12-26, commit fd34a1b284c5dd1e8008df9d3abcb28cfaf464bf
      SPARSE_PATHS = ["/lexicon.xml", "/README"].freeze

      FILENAME = "lexicon.xml"
      DICTIONARY_SLUG = "oncoj-lexicon"
      LANGUAGE = "ojp"
      TITLE = "ONCOJ lexicon — the dictionary database of the Oxford-NINJAL Corpus of Old Japanese"

      MANIFEST = Nabu::SourceManifest.new(
        id: "oncoj-lexicon",
        name: "ONCOJ lexicon — Old Japanese dictionary database (release 2021-12-26)",
        license: "CC BY 4.0 — upstream README §D verbatim: \"The corpus annotation (the grammatical " \
                 "analysis) is licensed under the Creative Commons Attribution 4.0 International " \
                 "License.\" Prescribed citation (§C): \"National Institute for Japanese Language " \
                 "and Linguistics (2021) “Oxford-NINJAL Corpus of Old Japanese” " \
                 "http://oncoj.ninjal.ac.jp/ (accessed 26 December 2021)\"",
        license_class: "attribution",
        upstream_url: REPO_URL,
        parser_family: "oncoj-lexicon"
      )

      def self.manifest
        MANIFEST
      end

      # Entries, not passages (architecture §11) — SyncRunner/Rebuild route
      # through Store::DictionaryLoader.
      def self.content_kind = :dictionary

      # One DocumentRef for the one lexicon file (the bosworth-toller shape).
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        Dir.glob(File.join(workdir, FILENAME)).first(1).each do |path|
          yield Nabu::DocumentRef.new(
            source_id: manifest.id,
            id: "#{DICTIONARY_SLUG}:#{FILENAME}",
            path: File.expand_path(path),
            metadata: { "dictionary" => DICTIONARY_SLUG }
          )
        end
      end

      def parse(document_ref)
        document = Nabu::DictionaryDocument.new(
          slug: DICTIONARY_SLUG, language: LANGUAGE,
          title: TITLE, canonical_path: document_ref.path
        )
        parser.each_entry(document_ref.path) { |entry| document << entry }
        document
      rescue Nabu::ValidationError => e
        raise Nabu::ParseError, "oncoj-lexicon: #{document_ref.id}: #{e.message}"
      end

      def fetch(workdir, progress: nil, force: false)
        git_fetch!(repo_url: repo_url, workdir: workdir, progress: progress, force: force,
                   ref: RELEASE_TAG, sparse: SPARSE_PATHS)
      end

      private

      def parser
        OncojLexiconParser.new
      end

      # Seam for tests (the house local-git pattern).
      def repo_url
        REPO_URL
      end
    end
  end
end

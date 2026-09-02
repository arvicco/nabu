# frozen_string_literal: true

require_relative "../normalize"

module Nabu
  module Adapters
    # OJW — the Old Javanese Wordnet (P92-5; github.com/davidmoeljadi/OJW,
    # Moeljadi et al., LREC 2020): the SEA desk's glossary — the open
    # stand-in for the license-blocked Zoetmulder OJED, from whose
    # digitization it was extracted. One tab file (`wn-kaw.tab`, the Open
    # Multilingual Wordnet format): 5,019 sense rows —
    #
    #   <PWN 3.0 synset offset-pos> ⇥ kaw:lemma ⇥ <lemma> [⇥ <variant>]
    #
    # == The shelf shape
    #
    # One DictionaryEntry per unique LEMMA (rows grouped): the headword,
    # its Princeton WordNet 3.0 synset ids in the body (the cross-lexicon
    # join key — DictionaryCitation is a CORPUS-citation type, not this;
    # no glosses ship in the tab, PWN's are not copied in, the shelf
    # stays what upstream publishes), and the derived variant forms
    # (695 rows carry one, ma-prefixed verbal forms mostly). Language kaw. An
    # in-file duplicate row is idempotent-skipped; entry_id = the lemma
    # (the monlam occurrence idiom would apply on a collision, but lemmas
    # are grouped so none exists by construction).
    #
    # == License / fetch
    #
    # CC BY 4.0 (in-repo LICENSE, verified 2026-09-01; the tab's own
    # header line repeats it) → attribution. Sparse GitFetch on the one
    # data file + grant (the repo's docs/etc cone is build tooling).
    class Ojw < Nabu::Adapter
      REPO_URL = "https://github.com/davidmoeljadi/OJW"

      DICTIONARY_SLUG = "ojw"
      LANGUAGE = "kaw"
      TITLE = "OJW — the Old Javanese Wordnet (Moeljadi et al.)"
      DATA_FILE = "wn-kaw.tab"
      SPARSE_PATHS = [DATA_FILE, "LICENSE", "README.md"].freeze

      ROW_RE = /\A(\d{8}-[a-z])\t([a-z]+:lemma)\t(.+)\z/

      MANIFEST = Nabu::SourceManifest.new(
        id: DICTIONARY_SLUG,
        name: TITLE,
        license: "CC BY 4.0 (in-repo LICENSE + the tab header's own declaration, " \
                 "verified 2026-09-01). Cite Moeljadi et al., LREC 2020",
        license_class: "attribution",
        upstream_url: REPO_URL,
        parser_family: "omw-tab",
        credit: "Old Javanese Wordnet (Moeljadi et al., LREC 2020; extracted from the " \
                "digitized Zoetmulder OJED) — github.com/davidmoeljadi/OJW."
      )

      def self.manifest
        MANIFEST
      end

      def self.content_kind = :dictionary

      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        path = File.join(workdir, DATA_FILE)
        return unless File.file?(path)

        yield Nabu::DocumentRef.new(
          source_id: DICTIONARY_SLUG, id: "#{DICTIONARY_SLUG}:#{DATA_FILE}",
          path: File.expand_path(path), metadata: { "dictionary" => DICTIONARY_SLUG }
        )
      end

      def parse(document_ref)
        entries = group_rows(document_ref.path)
        raise Nabu::ParseError, "#{document_ref.id}: no lemma rows" if entries.empty?

        document = Nabu::DictionaryDocument.new(
          slug: DICTIONARY_SLUG, language: LANGUAGE, title: TITLE,
          canonical_path: document_ref.path
        )
        entries.each { |lemma, data| document << build_entry(lemma, data) }
        document
      end

      def fetch(workdir, progress: nil, force: false)
        git_fetch!(repo_url: repo_url, workdir: workdir, progress: progress, force: force,
                   sparse: SPARSE_PATHS)
      end

      private

      def repo_url
        REPO_URL
      end

      # lemma => { synsets: [...], variants: [...] }, first-appearance order.
      def group_rows(path)
        entries = {}
        File.open(path, "r:UTF-8") do |io|
          io.each_line do |line|
            line = line.chomp
            next if line.empty? || line.start_with?("#")

            m = line.match(ROW_RE) or
              raise Nabu::ParseError, "#{File.basename(path)}: unrecognized row #{line[0, 60].inspect}"
            lemma, *variants = m[3].split("\t")
            entry = entries[lemma] ||= { synsets: [], variants: [] }
            entry[:synsets] << m[1] unless entry[:synsets].include?(m[1])
            variants.each { |v| entry[:variants] << v unless entry[:variants].include?(v) }
          end
        end
        entries
      end

      def build_entry(lemma, data)
        variants = data[:variants]
        body = ["Old Javanese Wordnet sense(s) mapped to Princeton WordNet 3.0 " \
                "synset#{'s' if data[:synsets].size > 1} #{data[:synsets].join(', ')}.",
                (variants.empty? ? nil : "Derived form#{'s' if variants.size > 1}: #{variants.join(', ')}.")]
        Nabu::DictionaryEntry.new(
          entry_id: lemma, key_raw: lemma, language: LANGUAGE,
          headword: Normalize.nfc(lemma),
          headword_folded: Normalize.search_form(lemma, language: LANGUAGE),
          gloss: nil,
          body: body.compact.join(" "),
          citations: []
        )
      end
    end
  end
end

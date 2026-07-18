# frozen_string_literal: true

require_relative "oshb_lexicon_parser"

module Nabu
  module Adapters
    # The OSHB Hebrew Lexicon adapter (P30-1): openscriptures/HebrewLexicon —
    # the OSHB project's own lexicon, the `define` surface for the augmented
    # Strong's ids every OSHB lemma carries (the P26-3 gap: "no lexicon to
    # define against"). content_kind :dictionary, parser family oshb-lexicon.
    #
    # == THE JOIN CONTRACT (the packet's point)
    #
    # Entry ids on the hebrew-lexicon shelf are augmented-Strong ids VERBATIM
    # ("1254a") — exactly what an OSHB token lemma yields after ONE mechanical
    # normalization (.normalize_lemma below, shared so both sides speak it):
    #
    #   "b/1254 a" → final /-segment → collapse whitespace → strip trailing +
    #             → "1254a" → urn:nabu:dict:hebrew-lexicon:1254a
    #
    # so `define` (Define#by_urn / nabu show) resolves an OSHB lemma id
    # directly — the aed lemmaID→urn precedent. Measured: 49,946/49,946
    # tokens (100.000%) on the live catalog (hebrew survey 2026-07-18,
    # Gen+Ruth+Dan+Jer incl. Aramaic Daniel); 1,906/1,906 tokens (506/506
    # types) at fixture level. Aramaic entries live in the SAME number space
    # (H/A split is per entry via the LexicalIndex parts, hbo/arc).
    #
    # == The shelf grain (censused at fixture time)
    #
    # ONE source, TWO dictionaries (the lexica LSJ + Lewis-Short precedent):
    #
    # - "hebrew-lexicon" — the augmented-Strong shelf: one entry per AugIndex
    #   row (9,299 upstream), assembled from AugIndex + LexicalIndex +
    #   HebrewStrong (see OshbLexiconParser). The join-contract namespace.
    # - "bdb" — the Brown-Driver-Briggs OUTLINE (upstream's honest state: a
    #   work in progress, mean entry text ~77 chars): one entry per
    #   BrownDriverBriggs.xml entry (11,845 upstream), each with its
    #   <status p="NNN"> print page as an unresolved citation row — the
    #   deep-link key into the PD BDB 1906 scan once it lands in
    #   local-library. NOTE: the packet spec's "BdbMedium.xml" does not
    #   exist upstream; the BDB outline file is BrownDriverBriggs.xml.
    #
    # The two shelves meet at `define <hebrew-word>`: both fold the same
    # consonantal skeleton, so a lookup shows the Strong gloss body AND the
    # BDB outline with its print page (LSJ+LS side-by-side, deliberately
    # unmerged). The 922 LexicalIndex entries no aug id reaches (root/xref
    # scaffolding) mint no entries — their substance lives on the bdb shelf.
    #
    # Store-grain honesty: the dictionaries table keys ONE language per
    # dictionary; both shelves register hbo (the majority — 8,589 of 9,299
    # aug entries, 23 of 46 BDB parts). Per-entry hbo/arc is preserved on
    # the domain entries (and the fold is identical for both), but
    # `define --lang arc` filters at the dictionary grain and will surface
    # these shelves under hbo — recorded in 02-sources, not papered over.
    #
    # == Upstream / license
    #
    # github.com/openscriptures/HebrewLexicon (9.2 MB, same org as the
    # morphhb/oshb corpus). Plain GitFetch — no sparse cone needed at this
    # size. readme.md, verbatim: "These files are released under the
    # Creative Commons Attribution 4.0 International license. The actual
    # text of Brown, Driver, Briggs and Strong's Hebrew dictionary remain
    # in the public domain. For attribution purposes, credit the Open
    # Scriptures Hebrew Bible Project." → license_class "attribution".
    class HebrewLexicon < Nabu::Adapter
      MANIFEST = Nabu::SourceManifest.new(
        id: "hebrew-lexicon",
        name: "OSHB Hebrew Lexicon — augmented Strong's + BDB outline (openscriptures)",
        license: "CC BY 4.0 (verbatim readme.md: \"These files are released under the Creative Commons " \
                 "Attribution 4.0 International license. The actual text of Brown, Driver, Briggs and " \
                 "Strong’s Hebrew dictionary remain in the public domain. For attribution purposes, " \
                 "credit the Open Scriptures Hebrew Bible Project.\")",
        license_class: "attribution",
        upstream_url: "https://github.com/openscriptures/HebrewLexicon",
        parser_family: "oshb-lexicon"
      )

      # The two dictionaries this source carries (class note). :anchor is the
      # file discover keys the shelf on; the strongs shelf reads its two
      # sibling files from the same directory at parse time.
      DICTIONARIES = {
        "hebrew-lexicon" => {
          title: "OSHB Hebrew Lexicon — Strong's via the augmented index",
          anchor: "AugIndex.xml", siblings: %w[LexicalIndex.xml HebrewStrong.xml]
        },
        "bdb" => {
          title: "Brown-Driver-Briggs Hebrew Lexicon (OSHB outline)",
          anchor: "BrownDriverBriggs.xml", siblings: []
        }
      }.freeze

      # Both shelves register the majority object language (class note).
      LANGUAGE = "hbo"

      def self.manifest
        MANIFEST
      end

      # The routing declaration (architecture §11): entries, not passages —
      # SyncRunner/Rebuild load through Store::DictionaryLoader.
      def self.content_kind = :dictionary

      # The OSHB-side half of the join contract, shared so tests and future
      # define wiring speak the one rule: OSHB @lemma → augmented-Strong id.
      # "b/1254 a" → "1254a"; "c/6213 a" → "6213a"; "1008+" → "1008";
      # "l" → "l". Total on the live catalog — no exceptions found.
      def self.normalize_lemma(lemma)
        lemma.to_s.split("/").last.to_s.gsub(/\s+/, "").delete_suffix("+")
      end

      # One DocumentRef per dictionary anchor file, sorted by id. The same
      # relative shapes recur under the attic, so retention costs nothing.
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        DICTIONARIES.flat_map do |slug, config|
          Dir.glob(File.join(workdir, "**", config.fetch(:anchor))).first(1).map do |path|
            Nabu::DocumentRef.new(
              source_id: manifest.id,
              id: "#{slug}:#{config.fetch(:anchor)}",
              path: File.expand_path(path),
              metadata: { "dictionary" => slug }
            )
          end
        end.sort_by(&:id).each(&block)
      end

      def parse(document_ref)
        slug = document_ref.metadata.fetch("dictionary")
        config = DICTIONARIES.fetch(slug)
        document = Nabu::DictionaryDocument.new(
          slug: slug, language: LANGUAGE,
          title: config.fetch(:title), canonical_path: document_ref.path
        )
        entries_for(slug, document_ref).each { |entry| document << entry }
        document
      rescue Nabu::ValidationError => e
        raise Nabu::ParseError, "hebrew-lexicon: #{document_ref.id}: #{e.message}"
      end

      # Clone or non-destructively pull the HebrewLexicon repo via the shared
      # git path (GitFetch: attic + pre-merge mass-deletion breaker).
      def fetch(workdir, progress: nil, force: false)
        git_fetch!(repo_url: repo_url, workdir: workdir, progress: progress, force: force)
      end

      private

      # Split out so fetch tests can point a singleton at a local git tmpdir
      # (the house pattern), keeping fetch off the network.
      def repo_url
        manifest.upstream_url
      end

      def entries_for(slug, document_ref)
        parser = OshbLexiconParser.new
        return parser.bdb_entries(document_ref.path) if slug == "bdb"

        lexical, strong = sibling_paths(document_ref)
        parser.strongs_entries(aug_path: document_ref.path,
                               lexical_index_path: lexical, strong_path: strong)
      end

      # The strongs shelf is a three-file assembly; the siblings live beside
      # the AugIndex anchor. A missing sibling is damage (quarantine), not a
      # partial parse.
      def sibling_paths(document_ref)
        dir = File.dirname(document_ref.path)
        DICTIONARIES.fetch("hebrew-lexicon").fetch(:siblings).map do |basename|
          path = File.join(dir, basename)
          raise Nabu::ParseError, "hebrew-lexicon: #{document_ref.id}: missing sibling file #{basename}" \
            unless File.file?(path)

          path
        end
      end
    end
  end
end

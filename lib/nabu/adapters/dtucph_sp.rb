# frozen_string_literal: true

require_relative "text_fabric"

module Nabu
  module Adapters
    # The CACCHT Samaritan Pentateuch (github.com/DT-UCPH/sp; Højgaard,
    # Naaijer & Schorch, Zenodo 10.5281/zenodo.7734632): the Samaritan
    # Pentateuch as Text-Fabric features — the Samaritanus-project (Halle,
    # S. Schorch) transcription of MS Dublin Chester Beatty Library 751
    # (Gen 1–Deut 32:36a) + MS Garizim 1 (Deut 32:36b–34:12), with
    # BHSA-modelled word morphology, lexemes, glosses, a phonetic
    # transcription of the Samaritan reading tradition, clause/phrase
    # constituency, and (from v7.5.0) the Tal–Florentin edition's readings
    # as word annotations. A text-fabric registrant on the cuc shape (the
    # sibling CACCHT dataset): the SLOTS are consonantal signs and words
    # are non-slot nodes. All corpus policy lives here; the family stays
    # format-only (zero family edits).
    #
    # == Version pin and fetch
    #
    # PINNED to release tag v7.5.0 (commit e8a120f2, published 2026-11-13,
    # "Variations between Dublin 751 and Nablus 6 were added") AND its
    # dataset directory tf/7.5.0 — GitFetch clones at the tag (ref:) inside
    # the sparse cone ["tf/7.5.0", "README.md", "LICENSE"], so the 63 older
    # version dirs, the notebooks/app/scripts trees and the ML training
    # data never materialize. Upstream is declared "work in progress" (the
    # verbal stem `vs` is annotated for Genesis only — 5,098 words); a
    # re-pin moves tag and directory together and is an owner decision.
    #
    # == License (verbatim, retrieved 2026-11-16)
    #
    # README badge "License: CC BY-NC 4.0" and prose "You can use the
    # dataset freely for research and education. If you do so, please refer
    # to the papers. Also refer to the dataset in the following way:
    # Christian Canu Højgaard, Martijn Naaijer, & Stefan Schorch. (2023).
    # Text-Fabric Dataset of the Samaritan Pentateuch. Zenodo.
    # https://doi.org/10.5281/zenodo.7734632"; LICENSE = the CC BY-NC 4.0
    # legal code; every feature header "@licence=Creative Commons
    # Attribution-NonCommercial 4.0 International License" (British key,
    # as cuc). The Tal–Florentin readings come from Florentin & Tal 2024
    # (Open Book Publishers, doi 10.11647/OBP.0415), itself CC BY-NC 4.0 —
    # one class either way → nc, the bhsa/cuc posture.
    #
    # == Identity: document = book, passage = verse
    #
    # The corpus's own citation grain (otext sectionTypes book,chapter,
    # verse). urn:nabu:dtucph-sp:<OSIS stem downcased> — gen/exod/lev/num/
    # deut, the stems oshb and bhsa mint, so the hub's verse tokens agree;
    # an unknown book name is a ParseError. Passage urns <doc>:<chapter>.
    # <verse>; (book, chapter, verse) is censused unique (5,841 verses).
    # book/chapter/verse label only their own grain here, so a verse's
    # book and chapter are read by slot containment. Upstream's one
    # versification edit is inherited, not undone: the Samaritan additions
    # after Gen 30:36 (36a–c in the editio maior) are grouped under verse
    # 36 (README) — gen:30.36 holds 90 words. T&F's divergent numbering
    # rides the passage as "verse_ft" verbatim (58 verses, "6:19, 6:20").
    #
    # == Text and tokens
    #
    # Passage text is the corpus's own text-orig-full rendering — {sign}
    # per slot (otext.tf) — byte-verbatim, trailing space stripped: the
    # manuscript's consonants in Hebrew square-script transcription, 27
    # letters (finals distinct) + the space, NO shin/sin dots (the
    # manuscripts carry none). That stream is NFC-stable on its own; the
    # language is hbo, which rides the hbo/arc exemption anyway (the bhsa
    # stance), so token lanes carrying U+FB2A/FB2B presentation-form
    # shin/sin (g_cons_utf8, g_lex_utf8, lex_utf8 — 15.5k values) ride
    # byte-verbatim and are never normalized.
    #
    # Tokens are WORD-grain (the cuc shape): "n" (the stable TF word node),
    # "form" (the word's own sign render, trailing space stripped —
    # form+trailer rebuild the passage text; censused: every word's render
    # ends in a space exactly where trailer.tf says " "), "trailer", "lang"
    # (language.tf Hebrew/Aramaic → hbo/arc — the two Aramaic words are
    # Jegar-sahadutha, Gen 31:47 — anything else a ParseError), and EVERY
    # other word-grain feature verbatim under its upstream name
    # (TOKEN_FEATURES): the consonantal/dotted/raw transliteration lanes,
    # lexemes, glosses, morphology (sp/vs/vt/ps/nu/gn + suffix ps/nu/gn and
    # the g_* morpheme slots), the ETCBC parsing string and the neural
    # model's "prediction" beside it, phono_transcr (the reading tradition,
    # after Ben-Hayyim), mt_feat (upstream's own flag "features imposed
    # from MT" — 105,833 words), grammar_note (the 7.4.0 corrections'
    # Schorch 2004 page refs), and the Tal–Florentin layer var_ft_utf8 /
    # var_ft / var_ft_type / var_ft_span — upstream's model, kept as is:
    # the T&F reading stands on the FIRST word of the differing stretch,
    # var_ft_span counts the words it replaces (0 = T&F words stand after
    # this one), "-" = T&F have no words here. 1,074 differences in 927
    # verses; our text is never changed by them.
    #
    # Spans ride beside tokens in the bhsa shape (architecture §5):
    # clause and phrase constituents as 0-based inclusive index ranges into
    # the passage's token list ("node" = the TF node; discontinuous
    # constituents keep every piece — 720 clauses / 284 phrases; the 29
    # clauses and 9 phrases crossing a verse boundary ride each verse with
    # "partial": true), phrase typ/function and the one phrase grammar_note
    # verbatim. Constituents are censused never to cut a word. The atom
    # grains (clause_atom, phrase_atom) carry no feature of their own and
    # are not ingested as spans (the bhsa precedent).
    #
    # == The two manuscripts (declared coarseness)
    #
    # The data does NOT mark the witness per node: the only statement is
    # every feature header's "@manuscripts=MS Dublin Chester Beatty Library
    # 751 (Gen 1-Deut 32:36) + MS Garizim 1 (Deut 32:36b-34)". That range
    # claim is transcribed: documents carry "manuscripts" (Genesis–Numbers
    # Dublin alone; Deuteronomy both), and Deuteronomy's passages carry
    # their own "manuscripts" (Dublin to 32:35, both on 32:36 — the switch
    # falls mid-verse, so no finer claim is possible — Garizim 1 from 32:37).
    # Any change to the header is upstream drift and a ParseError, never a
    # re-guessed boundary.
    #
    # == Census (verified against otype.tf at the pin, 2026-11-16)
    #
    # 399,393 signs / 114,891 words / 5,841 verses / 187 chapters / 5 books
    # / 21,736 clauses / 22,530 clause_atoms / 66,043 phrases / 69,905
    # phrase_atoms. Verses per book: Genesis 1,533 · Exodus 1,203 ·
    # Leviticus 859 · Numbers 1,289 · Deuteronomy 957. Expected first sync:
    # 5 documents / 5,841 passages / 114,891 tokens, 0 skipped. Upstream
    # serves one document grain set — the five book nodes of the pinned
    # tf/ directory; every other grain (the older tf/<version> dirs, the
    # complete.zip release asset, notebooks, the ML phrase-boundary
    # training data) is outside the sparse cone, never fetched.
    class DtucphSp < Nabu::Adapter
      REPO_URL = "https://github.com/DT-UCPH/sp"

      RELEASE_TAG = "v7.5.0"

      TF_DIR = File.join("tf", "7.5.0").freeze

      # The sparse cone: the pinned dataset + the license-bearing pages.
      SPARSE_PATHS = [TF_DIR, "README.md", "LICENSE"].freeze

      MANIFEST = Nabu::SourceManifest.new(
        id: "dtucph-sp",
        name: "The CACCHT Samaritan Pentateuch (DT-UCPH, Text-Fabric tf/7.5.0)",
        license: "CC BY-NC 4.0 (README badge \"License: CC BY-NC 4.0\"; LICENSE = the CC BY-NC 4.0 " \
                 "legal code; every feature header \"@licence=Creative Commons Attribution-NonCommercial " \
                 "4.0 International License\"; cite Højgaard, Naaijer & Schorch 2023, DOI " \
                 "10.5281/zenodo.7734632, and the papers. Text: Samaritanus project, Halle (S. Schorch). " \
                 "Tal–Florentin readings: Florentin & Tal 2024, OBP, CC BY-NC 4.0)",
        license_class: "nc",
        upstream_url: REPO_URL,
        parser_family: "text-fabric"
      )

      URN_PREFIX = "urn:nabu:dtucph-sp:"

      OSIS_BY_BOOK = {
        "Genesis" => "Gen", "Exodus" => "Exod", "Leviticus" => "Lev",
        "Numbers" => "Num", "Deuteronomy" => "Deut"
      }.freeze

      LANGUAGE_BY_VALUE = { "Hebrew" => "hbo", "Aramaic" => "arc" }.freeze

      DEFAULT_LANGUAGE = "hbo"

      DUBLIN = "MS Dublin Chester Beatty Library 751"
      GARIZIM = "MS Garizim 1"

      # The header the witness split is transcribed from — verbatim.
      MANUSCRIPTS_HEADER = "#{DUBLIN} (Gen 1-Deut 32:36) + #{GARIZIM} (Deut 32:36b-34)".freeze

      # The switch: Deut 32:36 is shared (36a Dublin, 36b Garizim 1).
      SWITCH_BOOK = "Deuteronomy"
      SWITCH = [32, 36].freeze

      # Word-grain features riding tokens verbatim under upstream's names.
      TOKEN_FEATURES = %w[
        g_cons g_cons_raw g_cons_utf8 g_lex g_lex_utf8 lex lex_utf8 gloss
        sp vs vt ps nu gn prs_ps prs_nu prs_gn
        g_pfm g_pfm_utf8 g_vbs g_vbs_utf8 g_vbe g_vbe_utf8 g_nme g_nme_utf8
        g_prs g_prs_utf8 g_uvf g_uvf_utf8
        phono_transcr ETCBC_parsing prediction mt_feat grammar_note
        var_ft var_ft_utf8 var_ft_type var_ft_span
      ].freeze

      # Every other tf/7.5.0 file, with where it goes or why it does not
      # ride a token under its own name.
      DECLINED_FEATURES = {
        "sign" => "the slot lane — rides as the passage text and each token's \"form\"",
        "trailer" => "rides as \"trailer\"",
        "language" => "rides as \"lang\" (Hebrew/Aramaic → hbo/arc)",
        "book" => "section grain — mints the document",
        "chapter" => "section grain — mints the passage urn",
        "verse" => "section grain — mints the passage urn",
        "verse_ft" => "verse grain — rides the passage annotation \"verse_ft\"",
        "typ" => "phrase grain — rides the phrase spans",
        "function" => "phrase grain — rides the phrase spans",
        "oslots" => "structural EDGE — read for slot extents, never a token value",
        "otype" => "structural — types every node, never a token value",
        "otext" => "@config — documents the text format (text-orig-full = {sign})"
      }.freeze

      SPAN_FEATURES = {
        "clause" => [].freeze,
        "phrase" => %w[typ function grammar_note].freeze
      }.freeze

      SPAN_TYPE_ORDER = { "clause" => 0, "phrase" => 1 }.freeze

      def self.manifest
        MANIFEST
      end

      def self.osis!(book, context)
        OSIS_BY_BOOK.fetch(book) do
          raise ParseError, "#{context}: unknown book name #{book.inspect} — the table is fixed at the " \
                            "five books of the Pentateuch; a new name is upstream drift, never guessed at"
        end
      end

      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        document_refs(workdir).each(&block)
      end

      def parse(document_ref)
        corpus = corpus(document_ref.path)
        build_document(corpus, urn: document_ref.id, book: document_ref.metadata.fetch("book"),
                               node: document_ref.metadata.fetch("node"))
      end

      def fetch(workdir, progress: nil, force: false)
        git_fetch!(repo_url: repo_url, workdir: workdir, progress: progress, force: force,
                   ref: RELEASE_TAG, sparse: SPARSE_PATHS)
      end

      private

      # Seam for tests (the house local-git pattern).
      def repo_url
        REPO_URL
      end

      def document_refs(workdir)
        dir = File.join(workdir, TF_DIR)
        return [] unless File.file?(File.join(dir, "otype.tf")) && File.file?(File.join(dir, "book.tf"))

        corpus(dir).books.map do |node, name|
          Nabu::DocumentRef.new(source_id: manifest.id,
                                id: "#{URN_PREFIX}#{self.class.osis!(name, dir).downcase}",
                                path: dir, metadata: { "book" => name, "node" => node })
        end.sort_by(&:id)
      end

      def corpus(dir)
        @corpus ||= {}
        @corpus[dir] ||= Corpus.new(Nabu::Adapters::TextFabric::Dataset.new(dir))
      end

      def build_document(corpus, urn:, book:, node:)
        corpus.manuscripts_header!
        verses = corpus.verses_of(node)
        raise ParseError, "#{corpus.dir}: book #{book} (node #{node}) has no verses" if verses.empty?

        built = verses.map { |verse| build_verse(corpus, book, verse) }
        language = majority_language(built.flat_map { |verse| verse[:tokens] }) || DEFAULT_LANGUAGE
        document = Nabu::Document.new(
          urn: urn, language: language, title: book, canonical_path: corpus.dir,
          metadata: { "book" => book, "manuscripts" => book_manuscripts(book) }
        )
        built.each_with_index do |verse, sequence|
          document << passage(verse, urn: urn, sequence: sequence, fallback: language)
        end
        document
      end

      def book_manuscripts(book)
        book == SWITCH_BOOK ? [DUBLIN, GARIZIM] : [DUBLIN]
      end

      # Only the switch book's passages name their own witness.
      def verse_manuscripts(book, chapter, verse)
        return nil unless book == SWITCH_BOOK

        case [chapter, verse] <=> SWITCH
        when -1 then [DUBLIN]
        when 0 then [DUBLIN, GARIZIM]
        else [GARIZIM]
        end
      end

      def build_verse(corpus, book, verse)
        words = corpus.words_in(verse)
        raise ParseError, "#{corpus.dir}: verse node #{verse.node} has no words" if words.empty?

        text = corpus.render(verse.first, verse.last).rstrip
        raise ParseError, "#{corpus.dir}: verse node #{verse.node} renders empty" if text.empty?

        {
          chapter: verse.chapter, verse: verse.number, text: text,
          tokens: words.map { |word| token(corpus, word) },
          spans: spans(corpus, verse, words),
          verse_ft: corpus.verse_ft(verse.node),
          manuscripts: verse_manuscripts(book, verse.chapter, verse.number)
        }
      end

      def passage(verse, urn:, sequence:, fallback:)
        annotations = { "tokens" => verse[:tokens] }
        annotations["spans"] = verse[:spans] unless verse[:spans].empty?
        annotations["verse_ft"] = verse[:verse_ft] if verse[:verse_ft]
        annotations["manuscripts"] = verse[:manuscripts] if verse[:manuscripts]
        Nabu::Passage.new(
          urn: "#{urn}:#{verse[:chapter]}.#{verse[:verse]}",
          language: majority_language(verse[:tokens]) || fallback,
          text: verse[:text], annotations: annotations, sequence: sequence
        )
      end

      def token(corpus, word)
        token = { "n" => word.node }
        form = corpus.render(word.first, word.last).rstrip
        token["form"] = form unless form.empty?
        trailer = corpus.word_feature("trailer", word.node)
        token["trailer"] = trailer if trailer
        TOKEN_FEATURES.each do |name|
          value = corpus.word_feature(name, word.node)
          token[name] = value unless value.nil?
        end
        token["lang"] = corpus.language_of(word.node)
        token
      end

      # Clause/phrase constituents touching this verse, as passage-relative
      # token-index ranges (the bhsa span contract).
      def spans(corpus, verse, words)
        index_of = words.each_with_index.to_h { |word, index| [word.node, index] }
        built = corpus.constituents_of(verse.node).map do |constituent|
          covered = constituent.words.select { |word| index_of.key?(word.node) }
          span = { "type" => constituent.type, "node" => constituent.node,
                   "ranges" => index_ranges(covered.map { |word| index_of.fetch(word.node) }) }
          span["partial"] = true if covered.sum { |word| word.last - word.first + 1 } < constituent.slot_count
          span.merge(constituent.features)
        end
        built.sort_by { |span| [span["ranges"].first.first, SPAN_TYPE_ORDER.fetch(span["type"]), span["node"]] }
      end

      def index_ranges(indexes)
        indexes.slice_when { |a, b| b != a + 1 }.map { |run| [run.first, run.last] }
      end

      # Majority "lang" vote over tokens (insertion order breaks ties), or
      # nil when nothing votes — the bhsa rule.
      def majority_language(tokens)
        votes = tokens.filter_map { |token| token["lang"] }
        return nil if votes.empty?

        votes.tally.max_by { |_code, count| count }.first
      end

      # The SP-shaped view over a TextFabric::Dataset: which features ride
      # where is this adapter's POLICY, so it lives here, not in the family.
      class Corpus
        Verse = Data.define(:node, :chapter, :number, :first, :last)
        Word = Data.define(:node, :first, :last)
        Constituent = Data.define(:node, :type, :words, :slot_count, :features)

        def initialize(dataset)
          @dataset = dataset
        end

        def dir = @dataset.dir

        # { book node => name } within otype's book range.
        def books
          @books ||= begin
            first, last = type_span("book")
            @dataset.feature("book").each_pair.select { |node, _| node.between?(first, last) }.to_h
          end
        end

        # The witness split is transcribed from this header; drift fails.
        def manuscripts_header!
          value = @dataset.feature("otype").meta["manuscripts"]
          return if value == MANUSCRIPTS_HEADER

          raise Nabu::ParseError,
                "#{dir}: otype.tf @manuscripts is #{value.inspect}, not the pinned " \
                "#{MANUSCRIPTS_HEADER.inspect} — the witness split is never re-guessed"
        end

        # The book's verses in slot order, each with its chapter.
        def verses_of(book_node)
          ranges = @dataset.slot_ranges(book_node)
          return [] if ranges.nil? || ranges.empty?

          first = ranges.first.first
          last = ranges.last.last
          grain_spans("verse").filter_map do |vfirst, vlast, node|
            next unless vfirst.between?(first, last)

            Verse.new(node: node, chapter: @dataset.feature("chapter").fetch(container("chapter", vfirst)),
                      number: @dataset.feature("verse").fetch(node), first: vfirst, last: vlast)
          end
        end

        def render(first, last)
          sign = @dataset.feature("sign")
          (first..last).map { |slot| sign.fetch(slot, "") }.join
        end

        def word_feature(name, node) = @dataset.feature(name).fetch(node)
        def verse_ft(node) = @dataset.feature("verse_ft").fetch(node)

        def language_of(word_node)
          value = @dataset.feature("language").fetch(word_node)
          LANGUAGE_BY_VALUE.fetch(value) do
            raise Nabu::ParseError,
                  "#{dir}: language.tf says #{value.inspect} for word #{word_node} — not Hebrew/Aramaic, " \
                  "and a language is never guessed"
          end
        end

        # Words whose first slot lies in the verse, ascending (censused:
        # words are contiguous and never cross a verse boundary).
        def words_in(verse)
          list = word_list
          index = list.bsearch_index { |word| word.first >= verse.first } || list.size
          words = []
          while index < list.size && list[index].first <= verse.last
            words << list[index]
            index += 1
          end
          words
        end

        def constituents_of(verse_node)
          constituents_by_verse.fetch(verse_node, [])
        end

        private

        def type_span(type)
          ranges = @dataset.type_ranges.fetch(type) do
            raise Nabu::ParseError, "#{dir}: otype.tf declares no #{type.inspect} nodes"
          end
          [ranges.first.first, ranges.last.last]
        end

        # The node of +type+ whose slot span holds +slot+.
        def container(type, slot)
          list = grain_spans(type)
          index = list.bsearch_index { |_first, last, _node| last >= slot }
          span = index && list[index]
          raise Nabu::ParseError, "#{dir}: slot #{slot} lies in no #{type} node" unless span && slot >= span[0]

          span[2]
        end

        # Ascending [first_slot, last_slot, node] for one grain.
        def grain_spans(type)
          @grain_spans ||= {}
          @grain_spans[type] ||= begin
            first, last = type_span(type)
            spans = []
            each_oslot(first, last) { |node, ranges| spans << [ranges.first.first, ranges.last.last, node] }
            spans.sort
          end
        end

        def word_list
          @word_list ||= grain_spans("word").map { |first, last, node| Word.new(node: node, first: first, last: last) }
        end

        def each_oslot(first, last)
          path = File.join(dir, "oslots.tf")
          @dataset.feature("oslots").each_pair do |node, spec|
            next unless node.between?(first, last)

            yield node, TextFabric.parse_ranges(spec, path: path)
          end
        end

        # verse node => [Constituent], one pass per constituent type.
        def constituents_by_verse
          @constituents_by_verse ||= begin
            map = Hash.new { |hash, key| hash[key] = [] }
            SPAN_FEATURES.each do |type, names|
              next unless @dataset.type_ranges.key?(type)

              first, last = type_span(type)
              each_oslot(first, last) do |node, ranges|
                words = words_covering(node, ranges)
                constituent = Constituent.new(node: node, type: type, words: words,
                                              slot_count: ranges.sum { |a, b| b - a + 1 },
                                              features: span_features(node, names))
                words.map { |word| container("verse", word.first) }.uniq.each { |verse| map[verse] << constituent }
              end
            end
            map.default = nil
            map
          end
        end

        # The words a constituent's slot ranges comprise; a range edge
        # falling inside a word is damage (censused: never at the pin).
        def words_covering(node, ranges)
          ranges.flat_map do |first, last|
            [first, last].each do |edge|
              word = word_at(edge)
              next if word.nil? || (edge == first ? word.first : word.last) == edge

              raise Nabu::ParseError, "#{dir}: constituent #{node} slot range #{first}-#{last} cuts word #{word.node}"
            end
            words_in(Verse.new(node: nil, chapter: nil, number: nil, first: first, last: last))
          end
        end

        def word_at(slot)
          list = word_list
          word = list[list.bsearch_index { |w| w.last >= slot } || list.size]
          word if word && word.first <= slot
        end

        def span_features(node, names)
          names.each_with_object({}) do |name, out|
            value = @dataset.feature(name).fetch(node)
            out[name] = value unless value.nil?
          end
        end
      end
    end
  end
end

# frozen_string_literal: true

require_relative "text_fabric"

module Nabu
  module Adapters
    # ETCBC Targum Corpus — "Graph Datasets of the Jewish Aramaic
    # Pentateuch" (S. P. Swire, ETCBC; github.com/ETCBC/targum, Zenodo
    # 10.5281/zenodo.23785216, v1.0.0 2026-10-29): the Jewish Aramaic
    # Pentateuch targums as Text-Fabric features — Pseudo-Jonathan (Clark
    # 1984), the Fragment Targums P/V/N (Klein 1980), 39 Cairo Genizah
    # fragments (Klein 1992), Neofiti 1 under two editorial views, and
    # Onqelos (Sperber 1959). Word-level gold lemmas (lex/lex_utf8), English
    # glosses, part of speech, stem/state/number/gender and roots, with the
    # scribal/editorial layer (variants, interlinear and marginal readings,
    # deletions) kept as first-order data. A text-fabric registrant; all
    # corpus policy lives here, the family stays format-only.
    #
    # == Version pin and fetch
    #
    # PINNED to the tf/0.1 dataset directory (the Zenodo v1.0.0 release;
    # identical at tag v1.0.0 and at main 15f97ab4, 2026-10-30): the sparse
    # GitFetch cone declares tf/0.1 + README.md + LICENSE.md. Upstream ALSO
    # serves the same corpus as a PostgreSQL dump (sql/) and as XML (xml/)
    # — alternative serializations of the one dataset, never fetched (the
    # cone excludes them; nothing to skip at discovery).
    #
    # == License (verbatim, retrieved 2026-11-02)
    #
    # README badge "License: CC BY-NC 4.0"; LICENSE.md is the CC BY-NC 4.0
    # legal code; every feature header carries "@license=Attribution-
    # NonCommercial 4.0 International"; the Zenodo record's license field
    # is cc-by-nc-4.0 → class nc (the bhsa/peshitta posture).
    #
    # == Identity: document = text, passage = verse
    #
    # One document per `text` node — one manuscript witness under one
    # editorial view (otext structureTypes text,book,chapter,verse). Text
    # is the right grain, not book: Genizah fragments X, Y and FF are
    # festival compilations whose book nodes ALTERNATE (Exodus, Genesis,
    # Exodus, Genesis …), so a book-grain urn would collide. urn:nabu:
    # etcbc-targum:<text name>, verbatim except the one parenthesized name
    # (cairo_genizah_targum_fragment_aa(2) → …_aa_2). Neofiti ships as two
    # texts on purpose — neofiti_full (base text WITH the interlinear and
    # marginal variants) and neofiti_base (the raw base text, variants and
    # emendations excluded); both are first-order upstream views of one
    # codex (crossref label "view") and stay honest sibling documents, the
    # view riding metadata verbatim.
    #
    # Passage urns <doc>:<book>.<chapter>.<verse> (book name downcased:
    # genesis … deuteronomy), in slot order — the manuscript's order, not
    # canonical order. A `verse` is "a line of text, typically (though not
    # always) corresponding to a verse"; three addresses corpus-wide carry
    # repeat records in one text (crossref same_witness: Genizah DD Deut
    # 24:6 ×2, FF Exod 15:12 ×4 and 17:12 ×3 — six extra records) — the second
    # occurrence gets ":b2", the third ":b3" (the ccmh collision suffix),
    # never merged.
    #
    # == Text and tokens
    #
    # Passage text = line_utf8, upstream's OWN verse rendering in square
    # script, byte-verbatim (arc rides the hbo/arc NFC exemption, the
    # bhsa/sefaria targum stance), outer whitespace stripped. It is NOT the
    # {voc_utf8}{trailer} slot render: line_utf8 excludes "a reading
    # transcribed on a line of its own, marginal or a whole-verse variant"
    # (the long marginalia), while short interlinear variants ride inline
    # as upstream writes them (Neofiti full Gen 2:1 "בריתחילוות").
    # Upstream defects kept verbatim: both Deut 24:6 records of Genizah DD
    # carry the same whole-verse line, and DD's Deut 33:6 record carries it
    # too (its own slots hold only "ולא") — the tokens show each record's
    # own words.
    #
    # Omission records are SKIPPED BY RULE and named: 17 verse records
    # (Pseudo-Jonathan 8, Neofiti full 9) hold nothing but the edition's
    # omission dots — line "...", which the converter rendered in
    # line_utf8 as a bare run of U+05BC (the ETCBC transliteration's "."
    # is the dagesh) with no letter to carry it. No text, no passage; the
    # address rides document metadata "omitted_verses" (an omission still
    # counts toward an address collision, so :bN suffixes stay stable).
    # The same stray-dagesh rendering of inline omission dots elsewhere is
    # kept verbatim (canonical means canonical).
    #
    # Tokens cover EVERY slot of the verse node (marginal lines included),
    # per word: "n" (the stable TF slot), "form" (voc_utf8 — the vocalized
    # word where the edition points it, else its consonants), "trailer",
    # every word-grain scalar feature verbatim under its upstream name
    # (TOKEN_FEATURES), "segment_type" (the type of the enclosing segment —
    # variant, addition, marginal, interlinear, editorial_deletion … —
    # absent for the default unmarked_text) and "reading" (the enclosing
    # word group's reading rank — absent for the printed reading 0).
    # Everything else is DECLINED with its reason (DECLINED_FEATURES).
    #
    # == Census (verified against otype.tf at the pin, 2026-11-02)
    #
    # 624,612 words / 47 texts / 91 books / 1,225 chapters / 25,447 verses /
    # 70,389 segments / 461,201 word groups / 7,023 lexemes. Passages per
    # text (verse records less omissions, full-data parse 2026-11-02):
    # Onqelos 5,852 · Neofiti full 5,835 · Neofiti base 5,827 ·
    # Pseudo-Jonathan 5,823 · Fragment Targum V 920 · P 594 · N 7 · PA 4 ·
    # the 39 Genizah texts 568. Expected first sync: 47 documents /
    # 25,430 passages (25,447 verse records less the 17 omission records) /
    # 624,595 tokens, 0 skipped documents. Upstream advertises no count of
    # its own beyond the README's text list, which the 47 text nodes match
    # (Pseudo-Jonathan, FT P/PA/V/N, the README's 38 Genizah sigla plus a
    # second AA text "aa(2)", the two Neofiti views, Onqelos).
    class EtcbcTargum < Nabu::Adapter
      REPO_URL = "https://github.com/ETCBC/targum"

      # The sparse cone: the pinned dataset + the license-bearing pages.
      SPARSE_PATHS = ["tf/0.1", "README.md", "LICENSE.md"].freeze

      TF_DIR = File.join("tf", "0.1").freeze

      LANGUAGE = "arc"

      MANIFEST = Nabu::SourceManifest.new(
        id: "etcbc-targum",
        name: "ETCBC Targum Corpus — Jewish Aramaic Pentateuch targums (Text-Fabric tf/0.1)",
        license: "CC BY-NC 4.0 (README badge \"License: CC BY-NC 4.0\"; LICENSE.md = the CC BY-NC 4.0 " \
                 "legal code; every feature header \"@license=Attribution-NonCommercial 4.0 " \
                 "International\"; cite DOI 10.5281/zenodo.23785216)",
        license_class: "nc",
        upstream_url: REPO_URL,
        parser_family: "text-fabric"
      )

      URN_PREFIX = "urn:nabu:etcbc-targum:"

      # Word-grain scalar features carried verbatim under their own names.
      TOKEN_FEATURES = %w[cons cons_utf8 voc lex lex0 lex_utf8 gloss sp vs gn nu st root part source uid].freeze

      # Every other tf/0.1 feature, with why it does not ride the token.
      DECLINED_FEATURES = {
        "voc_utf8" => "rides as \"form\"",
        "definition" => "lexeme-grain dictionary prose (4,452 distinct values) repeated on every word — " \
                        "77 MB; joinable by lex, belongs to a lexicon shelf, not 578k token copies",
        "description" => "a 31-value prose paraphrase of sp/st/vs (\"noun, singular emphatic\") — " \
                         "carried by the features it paraphrases",
        "start_idx" => "character offsets into the transliterated `line` — positional plumbing",
        "end_idx" => "character offsets into the transliterated `line` — positional plumbing",
        "g_cons" => "word-group surface; the group's words ride as tokens",
        "g_cons_utf8" => "word-group surface; the group's words ride as tokens",
        "g_voc" => "word-group surface; the group's words ride as tokens",
        "g_voc_utf8" => "word-group surface; the group's words ride as tokens",
        "segment_utf8" => "segment surface; the segment's words ride as tokens (its type as segment_type)",
        "id" => "the SQL primary key of upstream's own database — internal",
        "rank" => "sibling ordinal within the line — positional plumbing",
        "freq_lex" => "lexeme-node statistic (no word→lexeme edge ships)",
        "rank_lex" => "lexeme-node statistic (no word→lexeme edge ships)",
        "parent" => "the containment edge; containment is read from oslots",
        "sibling" => "@edgeValues distance edge — not parsed by the family",
        "crossref" => "@edgeValues parallel-witness edge — the shared (book, chapter, verse) address " \
                      "the passage urns already carry is what it encodes"
      }.freeze

      GENIZAH_PREFIX = "cairo_genizah_targum_fragment_"

      # The transliterated line of an omission-only verse record.
      OMISSION_LINE = /\A[.\s]+\z/

      # README's own description of each witness ("## Texts"), verbatim.
      WITNESSES = {
        "pseudo_jonathan" => { "title" => "Targum Pseudo-Jonathan", "collection" => "Pseudo-Jonathan",
                               "shelfmark" => "British Library Add. Ms. 2703", "base_edition" => "Clark, 1984" },
        "fragment_targum_p" => { "title" => "Fragment Targum P", "collection" => "Fragment Targums",
                                 "shelfmark" => "Paris, ms. hebr. 110", "base_edition" => "Klein, 1980" },
        "fragment_targum_pa" => { "title" => "Fragment Targum PA", "collection" => "Fragment Targums",
                                  "base_edition" => "Klein, 1980" },
        "fragment_targum_v" => { "title" => "Fragment Targum V", "collection" => "Fragment Targums",
                                 "shelfmark" => "Biblioteca Apostolica, Vatican, Ebr. 440",
                                 "base_edition" => "Klein, 1980" },
        "fragment_targum_n" => { "title" => "Fragment Targum N", "collection" => "Fragment Targums",
                                 "shelfmark" => "Nürnberg Stadtbibliothek, Solg. 2,2",
                                 "base_edition" => "Klein, 1980" },
        "neofiti_full" => { "title" => "Targum Neofiti 1 (full text)", "collection" => "Neofiti",
                            "shelfmark" => "MS Neofiti, no. 1" },
        "neofiti_base" => { "title" => "Targum Neofiti 1 (base text)", "collection" => "Neofiti",
                            "shelfmark" => "MS Neofiti, no. 1" },
        "onqelos" => { "title" => "Targum Onqelos", "collection" => "Onqelos",
                       "base_edition" => "Sperber 1959, Bible in Aramaic Vol I" }
      }.freeze

      def self.manifest
        MANIFEST
      end

      # The urn slug of a text name: verbatim, any run outside [a-z0-9_]
      # folded to "_" (only "…_aa(2)" carries one).
      def self.slug(name)
        name.downcase.gsub(/[^a-z0-9_]+/, "_").delete_suffix("_")
      end

      # The README's facts for a text name; an unknown name is a
      # ParseError, never a guess.
      def self.witness_info(name)
        return WITNESSES.fetch(name) if WITNESSES.key?(name)

        if name.start_with?(GENIZAH_PREFIX)
          siglum = name.delete_prefix(GENIZAH_PREFIX).upcase.sub(/\((\d+)\)\z/, ' (\1)')
          return { "title" => "Cairo Genizah Targum Fragment #{siglum}",
                   "collection" => "Cairo Genizah Targum Fragments",
                   "base_edition" => "Klein, 1992", "place" => "Cairo Genizah" }
        end
        raise Nabu::ParseError, "etcbc-targum: unknown text #{name.inspect} — extend WITNESSES from the README"
      end

      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        document_refs(workdir).each(&block)
      end

      def parse(document_ref)
        corpus = corpus(document_ref.path)
        build_document(corpus, urn: document_ref.id, name: document_ref.metadata.fetch("text"),
                               node: document_ref.metadata.fetch("node"))
      end

      def fetch(workdir, progress: nil, force: false)
        git_fetch!(repo_url: repo_url, workdir: workdir, progress: progress, force: force,
                   sparse: SPARSE_PATHS)
      end

      private

      def repo_url
        REPO_URL
      end

      def document_refs(workdir)
        dir = File.join(workdir, TF_DIR)
        return [] unless File.file?(File.join(dir, "otype.tf")) && File.file?(File.join(dir, "text.tf"))

        corpus(dir).texts.map do |node, name|
          Nabu::DocumentRef.new(source_id: manifest.id, id: "#{URN_PREFIX}#{self.class.slug(name)}",
                                path: dir, metadata: { "text" => name, "node" => node })
        end.sort_by(&:id)
      end

      def corpus(dir)
        @corpus ||= {}
        @corpus[dir] ||= Corpus.new(Nabu::Adapters::TextFabric::Dataset.new(dir))
      end

      def build_document(corpus, urn:, name:, node:)
        info = self.class.witness_info(name)
        verses = corpus.verses_of(node)
        raise ParseError, "#{corpus.dir}: text #{name} (node #{node}) has no verses" if verses.empty?

        document = Nabu::Document.new(
          urn: urn, language: LANGUAGE, title: info.fetch("title"), canonical_path: corpus.dir,
          metadata: document_metadata(corpus, name: name, node: node, info: info, verses: verses)
        )
        seen = Hash.new(0)
        sequence = 0
        verses.each do |verse|
          address = "#{book_slug(verse.book)}.#{verse.chapter}.#{verse.verse}"
          seen[address] += 1
          address = "#{address}:b#{seen[address]}" if seen[address] > 1
          next if omission?(corpus, verse)

          document << passage(corpus, verse, urn: "#{urn}:#{address}", sequence: sequence)
          sequence += 1
        end
        document
      end

      # A verse record holding nothing but the edition's omission dots
      # (line "...", rendered in line_utf8 as bare U+05BC — the class note).
      def omission?(corpus, verse)
        OMISSION_LINE.match?(corpus.line(verse.node).to_s)
      end

      def omitted_addresses(corpus, verses)
        verses.select { |verse| omission?(corpus, verse) }
              .map { |verse| "#{book_slug(verse.book)}.#{verse.chapter}.#{verse.verse}" }
      end

      def document_metadata(corpus, name:, node:, info:, verses:)
        {
          "text" => name,
          "manuscript" => corpus.manuscript(node),
          "view" => corpus.view(node),
          "books" => verses.map(&:book).uniq,
          "collection" => info["collection"],
          "shelfmark" => info["shelfmark"],
          "base_edition" => info["base_edition"],
          "place" => info["place"],
          "omitted_verses" => omitted_addresses(corpus, verses).then { |list| list.empty? ? nil : list }
        }.compact
      end

      def book_slug(book)
        book.downcase.gsub(/[^a-z0-9]+/, "-")
      end

      def passage(corpus, verse, urn:, sequence:)
        text = corpus.line_utf8(verse.node).to_s.strip
        raise ParseError, "#{corpus.dir}: verse node #{verse.node} carries no line_utf8" if text.empty?

        annotations = { "tokens" => tokens(corpus, verse) }
        line = corpus.line(verse.node)
        annotations["line"] = line if line
        Nabu::Passage.new(urn: urn, language: LANGUAGE, text: text, annotations: annotations, sequence: sequence)
      end

      def tokens(corpus, verse)
        (verse.first..verse.last).map do |slot|
          token = { "n" => slot }
          form = corpus.value("voc_utf8", slot)
          token["form"] = form if form
          trailer = corpus.value("trailer", slot)
          token["trailer"] = trailer if trailer
          TOKEN_FEATURES.each do |name|
            value = corpus.value(name, slot)
            token[name] = value unless value.nil?
          end
          segment_type = corpus.segment_type(slot)
          token["segment_type"] = segment_type if segment_type
          reading = corpus.reading(slot)
          token["reading"] = reading if reading
          token
        end
      end

      # The targum-shaped view over a TextFabric::Dataset.
      class Corpus
        Verse = Data.define(:node, :book, :chapter, :verse, :first, :last)

        DEFAULT_SEGMENT = "unmarked_text"

        def initialize(dataset)
          @dataset = dataset
        end

        def dir = @dataset.dir

        # { text node => name } in node order.
        def texts
          @texts ||= begin
            first, last = type_span("text")
            @dataset.feature("text").each_pair.select { |node, _| node.between?(first, last) }.to_h
          end
        end

        def manuscript(node) = @dataset.feature("manuscript").fetch(node)
        def view(node) = @dataset.feature("view").fetch(node)
        def line_utf8(node) = @dataset.feature("line_utf8").fetch(node)
        def line(node) = @dataset.feature("line").fetch(node)
        def value(name, slot) = @dataset.feature(name).fetch(slot)

        def segment_type(slot) = slot_maps.fetch(:segment)[slot]
        def reading(slot) = slot_maps.fetch(:reading)[slot]

        # The text's verses in slot order, each with its containing book
        # and chapter.
        def verses_of(text_node)
          first, last = slot_span(text_node) || (return [])
          spans.fetch("verse").filter_map do |vfirst, vlast, node|
            next unless vfirst.between?(first, last)

            Verse.new(node: node, book: label("book", vfirst), chapter: label("chapter", vfirst),
                      verse: @dataset.feature("verse").fetch(node), first: vfirst, last: vlast)
          end
        end

        private

        def slot_span(node)
          ranges = @dataset.slot_ranges(node)
          ranges && !ranges.empty? ? [ranges.first.first, ranges.last.last] : nil
        end

        def type_span(type)
          ranges = @dataset.type_ranges.fetch(type) do
            raise Nabu::ParseError, "#{dir}: otype.tf declares no #{type.inspect} nodes"
          end
          [ranges.first.first, ranges.last.last]
        end

        # The feature value of the +type+ node containing +slot+.
        def label(type, slot)
          list = spans.fetch(type)
          index = list.bsearch_index { |_first, last, _node| last >= slot }
          span = index && list[index]
          raise Nabu::ParseError, "#{dir}: slot #{slot} lies in no #{type} node" unless span && slot >= span[0]

          @dataset.feature(type).fetch(span[2])
        end

        # Ascending [first, last, node] per structural type, from ONE pass
        # over oslots; the segment-type and reading slot maps ride the same
        # pass (only non-default values are kept).
        def spans
          build_structure unless @spans
          @spans
        end

        def slot_maps
          build_structure unless @slot_maps
          @slot_maps
        end

        def build_structure
          ranges = %w[text book chapter verse segment word_group].to_h do |type|
            [type, @dataset.type_ranges.key?(type) ? type_span(type) : nil]
          end
          @spans = { "text" => [], "book" => [], "chapter" => [], "verse" => [] }
          @slot_maps = { segment: {}, reading: {} }
          path = File.join(dir, "oslots.tf")
          @dataset.feature("oslots").each_pair do |node, spec|
            type = ranges.find { |_, span| span && node.between?(*span) }&.first
            next if type.nil?

            node_ranges = TextFabric.parse_ranges(spec, path: path)
            if @spans.key?(type)
              @spans[type] << [node_ranges.first.first, node_ranges.last.last, node]
            else
              stamp(type, node, node_ranges)
            end
          end
          @spans.each_value(&:sort!)
        end

        def stamp(type, node, node_ranges)
          if type == "segment"
            value = @dataset.feature("type").fetch(node)
            return if value.nil? || value == DEFAULT_SEGMENT

            map = @slot_maps[:segment]
          else
            value = @dataset.feature("reading").fetch(node)
            return if value.nil? || value.to_i.zero?

            map = @slot_maps[:reading]
          end
          node_ranges.each { |first, last| (first..last).each { |slot| map[slot] = value } }
        end
      end
    end
  end
end

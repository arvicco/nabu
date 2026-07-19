# frozen_string_literal: true

require_relative "text_fabric"

module Nabu
  module Adapters
    # CUC — the Copenhagen Ugaritic Corpus (P31-4): the CACCHT project's
    # Text-Fabric edition of the KTU tablets (github.com/DT-UCPH/cuc), the
    # THIRD text-fabric registrant and nabu's first Ugaritic — a NEW axis
    # language (uga, Northwest Semitic). All corpus policy lives here; the
    # family stays format-only (zero family edits, as designed).
    #
    # == Version pin and fetch
    #
    # PINNED to the tf/0.2.8 dataset directory (19 files ≈ 3.5 MB): the
    # sparse GitFetch cone declares ["tf/0.2.8", "README.md"] (the README
    # carries the human license badge + the KTU coverage list). The repo is
    # "work in progress" upstream — new versions land in NEW dirs
    # (tf/0.2.9…), so the pin holds until an owner decision moves it.
    #
    # == License (verbatim, retrieved 2026-07-19)
    #
    # Every .tf header carries the machine-readable pair — NB upstream's
    # BRITISH spelling of the key: "@licence=Creative Commons
    # Attribution-NonCommercial 4.0 International License" +
    # "@licenceUrl=http://creativecommons.org/licenses/by-nc/4.0/"; the
    # README badge and Zenodo DOI 10.5281/zenodo.10695308 agree → class nc,
    # the bhsa/dss posture: recorded on every serving surface so
    # query/export/MCP filters never over-share.
    #
    # == Identity: document = tablet, passage = column + line
    #
    # The corpus's OWN citation grain (otext sectionTypes
    # tablet,column,line). tablet.tf names are uniformly "KTU <n>.<n>"
    # (censused, 279 names, all unique) → urn:nabu:cuc:ktu-<n>.<n>; any
    # other shape is upstream drift (ParseError, never guessed). Passage
    # urns <doc-urn>:<column>.<line> from the corpus's own roman-numeral
    # column labels and integer line numbers; every line is censused inside
    # exactly one column, and (tablet, stripped column, line) is censused
    # globally unique. One column label corpus-wide carries a trailing
    # space ("I " on KTU 1.50) — STRIPPED in the urn (a citation, not
    # content), VERBATIM in the passage's "column" annotation.
    #
    # == Text and tokens
    #
    # Passage text is the corpus's own text-orig-full rendering — {sign}
    # per slot (otext.tf) — assembled byte-verbatim then NFC at the model
    # boundary, trailing whitespace stripped. The sign stream is
    # consonantal Latin transliteration (38 censused single-char values):
    # word-internal spaces pad word ends, "x" is the illegible sign, "."/
    # "?"/"-"/"…"/NBSP are upstream's damage-and-divider marks — all kept
    # as shipped. 72 lines corpus-wide render whitespace-only (fully
    # illegible/restored-blank regions): those are SKIPPED — a text store
    # cannot hold an empty passage and content is never invented — and
    # listed in document metadata "empty_lines" (citation labels), so the
    # gap is visible, not silent.
    #
    # Tokens are WORD-grain. Each carries: "n" (stable TF word node),
    # "form" (g_cons, the consonantal word — absent for words with no
    # transcription, the dss empty-form precedent), "trailer"/"utrailer"
    # (the interword material: transliterated "." / cuneiform 𐎟 word
    # divider), "trailer_emen" (trailer emendation), and "signs" — the
    # per-slot lane, one entry per sign slot of the word: "sign"
    # (transliteration) + "usign" (Ugaritic cuneiform, the text-orig-
    # unicode lane riding sub-token so nothing is lost) + the text-critical
    # flags VERBATIM when present: "cert" (KTU's italic uncertainty,
    # upstream's own "True"/"False" strings), "emen" (restored/redundant/
    # excised/missing/remark), "alt" (alternative reading letter), "cont"
    # (line-continuation mark). Sub-token placement is exact: a
    # half-restored word shows which letters are restored.
    #
    # language.tf is censused uniformly "Ugaritic" → uga on document and
    # every passage; any other value is a ParseError (upstream adding
    # Hurrian texts later must be a deliberate decision, never a guess).
    # side.tf (line grain) rides passage annotations verbatim when present
    # — including upstream's whitespace/uncertainty quirks ("rev. ",
    # "rev.\t", "rev.?"); absent is absent (only 12 lines say "obv.").
    # tablet_info.tf (2 notes corpus-wide) rides document metadata "info".
    # KTU concordance: the KTU number IS the document identity — no
    # separate concordance lane exists in the dataset (censused).
    #
    # == Census (verified against otype.tf at the pin, 2026-07-19)
    #
    # 146,017 signs / 27,770 words / 7,616 lines / 334 columns / 279
    # tablets — every briefed number exact (upstream README's "278
    # tablets" undercounts its own otype by one).
    class Cuc < Nabu::Adapter
      REPO_URL = "https://github.com/DT-UCPH/cuc"

      # The sparse cone: the pinned dataset + the README carrying the human
      # license badge and coverage list.
      SPARSE_PATHS = ["tf/0.2.8", "README.md"].freeze

      TF_DIR = File.join("tf", "0.2.8").freeze

      MANIFEST = Nabu::SourceManifest.new(
        id: "cuc",
        name: "CUC — Copenhagen Ugaritic Corpus (CACCHT/DT-UCPH, Text-Fabric tf/0.2.8)",
        license: "CC BY-NC 4.0 (every .tf header verbatim, upstream's British spelling of the key: " \
                 "\"@licence=Creative Commons Attribution-NonCommercial 4.0 International License\" + " \
                 "\"@licenceUrl=http://creativecommons.org/licenses/by-nc/4.0/\"; README badge and " \
                 "Zenodo DOI 10.5281/zenodo.10695308 agree)",
        license_class: "nc",
        upstream_url: REPO_URL,
        parser_family: "text-fabric"
      )

      URN_PREFIX = "urn:nabu:cuc:"

      # tablet.tf names are uniformly this shape at the pin (censused);
      # anything else is upstream drift, never guessed at.
      TABLET_NAME = /\AKTU (\d+\.\d+)\z/

      # language.tf word values: censused uniformly Ugaritic. A new value
      # (upstream ingesting Hurrian?) must fail loudly, never guess.
      LANGUAGE_BY_VALUE = { "Ugaritic" => "uga" }.freeze

      # Sign-grain features riding each token's "signs" entries verbatim.
      SIGN_FLAGS = %w[cert emen alt cont].freeze

      # Word-grain features riding tokens verbatim (beside form = g_cons).
      WORD_FEATURES = %w[trailer utrailer trailer_emen].freeze

      def self.manifest
        MANIFEST
      end

      # One DocumentRef per tablet node named by tablet.tf, sorted by urn.
      # A workdir without the pinned dataset (pre-fetch) yields nothing.
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        document_refs(workdir).each(&block)
      end

      def parse(document_ref)
        corpus = corpus(document_ref.path)
        build_document(
          corpus,
          urn: document_ref.id,
          tablet: document_ref.metadata.fetch("tablet"),
          node: document_ref.metadata.fetch("node")
        )
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

      def document_refs(workdir)
        dir = File.join(workdir, TF_DIR)
        return [] unless File.file?(File.join(dir, "otype.tf")) && File.file?(File.join(dir, "tablet.tf"))

        corpus = corpus(dir)
        corpus.tablets.map do |node, name|
          Nabu::DocumentRef.new(
            source_id: manifest.id,
            id: "#{URN_PREFIX}#{urn_tail!(name, dir)}",
            path: dir,
            metadata: { "tablet" => name, "node" => node }
          )
        end.sort_by(&:id)
      end

      def urn_tail!(name, context)
        match = TABLET_NAME.match(name)
        if match.nil?
          raise ParseError, "#{context}: tablet name #{name.inspect} is not the censused \"KTU <n>.<n>\" " \
                            "shape — upstream drift, never guessed at"
        end

        "ktu-#{match[1]}"
      end

      def corpus(dir)
        @corpus ||= {}
        @corpus[dir] ||= Corpus.new(Nabu::Adapters::TextFabric::Dataset.new(dir))
      end

      def build_document(corpus, urn:, tablet:, node:)
        lines = corpus.lines_of(node)
        raise ParseError, "#{corpus.dir}: tablet #{tablet} (node #{node}) has no lines" if lines.empty?

        built = lines.map { |line| build_line(corpus, line) }
        kept, empty = built.partition { |line| line[:text] }
        raise ParseError, "#{corpus.dir}: tablet #{tablet} renders entirely whitespace" if kept.empty?

        metadata = { "tablet" => tablet }
        info = corpus.info(node)
        metadata["info"] = info if info
        metadata["empty_lines"] = empty.map { |line| line[:cite] } unless empty.empty?
        document = Nabu::Document.new(
          urn: urn, language: "uga", title: tablet, canonical_path: corpus.dir, metadata: metadata
        )
        kept.each_with_index do |line, sequence|
          document << passage(line, urn: urn, sequence: sequence)
        end
        document
      end

      def passage(line, urn:, sequence:)
        annotations = { "column" => line[:column], "line" => line[:line], "tokens" => line[:tokens] }
        annotations["side"] = line[:side] if line[:side]
        Nabu::Passage.new(
          urn: "#{urn}:#{line[:cite]}",
          language: "uga",
          text: line[:text],
          annotations: annotations,
          sequence: sequence
        )
      end

      # One line of a tablet. :text is nil for a whitespace-only render —
      # the 72 corpus-wide fully illegible lines — which the document
      # builder records instead of minting an empty passage.
      def build_line(corpus, line)
        span = corpus.slot_span(line.node)
        raise ParseError, "#{corpus.dir}: line node #{line.node} has no slots" if span.nil?

        text = Nabu::Normalize.nfc((span.first..span.last).map { |slot| corpus.sign(slot) }.join.rstrip)
        {
          cite: "#{line.column.strip}.#{line.number}",
          column: line.column, line: line.number, side: corpus.side(line.node),
          text: (text.strip.empty? ? nil : text),
          tokens: corpus.words_in(span).map { |word| token(corpus, word) }
        }
      end

      def token(corpus, word)
        token = { "n" => word.node }
        form = corpus.word_feature("g_cons", word.node)
        token["form"] = form if form
        WORD_FEATURES.each do |name|
          value = corpus.word_feature(name, word.node)
          token[name] = value unless value.nil?
        end
        corpus.language!(word.node)
        token["signs"] = (word.first..word.last).map { |slot| sign_entry(corpus, slot) }
        token
      end

      def sign_entry(corpus, slot)
        entry = { "sign" => corpus.sign(slot), "usign" => corpus.usign(slot) }
        SIGN_FLAGS.each do |name|
          value = corpus.sign_flag(name, slot)
          entry[name] = value unless value.nil?
        end
        entry
      end

      # The CUC-shaped view over a TextFabric::Dataset: which features ride
      # where is cuc POLICY, so it lives here, not in the family.
      class Corpus
        Line = Data.define(:node, :number, :column)
        Word = Data.define(:node, :first, :last)

        def initialize(dataset)
          @dataset = dataset
        end

        def dir = @dataset.dir

        # { tablet node => name } in node order — restricted to otype's
        # tablet range (the section features label only their own grain in
        # this corpus, but the guard is cheap and censusproof).
        def tablets
          @tablets ||= begin
            first, last = type_span("tablet")
            @dataset.feature("tablet").each_pair
                    .select { |node, _name| node.between?(first, last) }.to_h
          end
        end

        def info(tablet_node)
          @dataset.feature("tablet_info").fetch(tablet_node)
        end

        # Lines of a tablet in node order (== slot order, censused), each
        # with its line number and enclosing column label (every line is
        # censused inside exactly one column).
        def lines_of(tablet_node)
          span = slot_span(tablet_node)
          return [] if span.nil?

          line_slot_spans.filter_map do |first, _last, node|
            next unless first.between?(span.first, span.last)

            Line.new(node: node, number: @dataset.feature("line").fetch(node), column: column_of(first))
          end
        end

        def slot_span(node)
          ranges = @dataset.slot_ranges(node)
          return nil if ranges.nil? || ranges.empty?

          [ranges.first.first, ranges.last.last]
        end

        def sign(slot) = @dataset.feature("sign").fetch(slot, "")
        def usign(slot) = @dataset.feature("usign").fetch(slot, "")
        def side(line_node) = @dataset.feature("side").fetch(line_node)

        def sign_flag(name, slot)
          @dataset.feature(name).fetch(slot)
        end

        def word_feature(name, node)
          @dataset.feature(name).fetch(node)
        end

        # Every word is censused Ugaritic; anything else fails loudly.
        def language!(word_node)
          value = @dataset.feature("language").fetch(word_node)
          Cuc::LANGUAGE_BY_VALUE.fetch(value) do
            raise Nabu::ParseError,
                  "#{dir}: language.tf says #{value.inspect} for word #{word_node} — not Ugaritic, " \
                  "and a language is never guessed"
          end
        end

        # Words whose first slot lies in +span+, ascending (words are
        # censused contiguous and never crossing line boundaries).
        def words_in(span)
          list = word_list
          index = list.bsearch_index { |word| word.first >= span.first } || list.size
          words = []
          while index < list.size && list[index].first <= span.last
            words << list[index]
            index += 1
          end
          words
        end

        private

        def type_span(type)
          ranges = @dataset.type_ranges.fetch(type) do
            raise Nabu::ParseError, "#{dir}: otype.tf declares no #{type.inspect} nodes"
          end
          [ranges.first.first, ranges.last.last]
        end

        # The column label enclosing +slot+ — every line is censused inside
        # exactly one column, so a miss is damage.
        def column_of(slot)
          spans = column_slot_spans
          index = spans.bsearch_index { |first, _last, _node| first > slot }
          index = index.nil? ? spans.size - 1 : index - 1
          if index.negative? || slot > spans[index][1]
            raise Nabu::ParseError, "#{dir}: slot #{slot} lies in no column — otext promises " \
                                    "tablet,column,line sectioning"
          end

          @dataset.feature("column").fetch(spans[index][2])
        end

        def column_slot_spans
          @column_slot_spans ||= grain_slot_spans("column")
        end

        def line_slot_spans
          @line_slot_spans ||= grain_slot_spans("line")
        end

        # Ascending [first_slot, last_slot, node] for one grain.
        def grain_slot_spans(type)
          first, last = type_span(type)
          spans = []
          @dataset.feature("oslots").each_pair do |node, spec|
            next unless node.between?(first, last)

            ranges = TextFabric.parse_ranges(spec, path: File.join(dir, "oslots.tf"))
            spans << [ranges.first.first, ranges.last.last, node]
          end
          spans.sort
        end

        # Ascending Words (first-slot order == node order at the pin).
        def word_list
          @word_list ||= begin
            first, last = type_span("word")
            list = []
            @dataset.feature("oslots").each_pair do |node, spec|
              next unless node.between?(first, last)

              ranges = TextFabric.parse_ranges(spec, path: File.join(dir, "oslots.tf"))
              list << Word.new(node: node, first: ranges.first.first, last: ranges.last.last)
            end
            list.sort_by(&:first)
          end
        end
      end
    end
  end
end

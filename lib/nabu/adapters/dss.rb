# frozen_string_literal: true

require_relative "text_fabric"

module Nabu
  module Adapters
    # DSS — the ETCBC Dead Sea Scrolls (P30-5): Martin Abegg's
    # transcriptions and morphological tagging of the Qumran/Judaean Desert
    # scrolls as Text-Fabric features (github.com/ETCBC/dss), the SECOND
    # text-fabric registrant. All corpus policy lives here; the family
    # stays format-only.
    #
    # == Version pin and fetch
    #
    # PINNED to the frozen tf/2.0 dataset directory (79 files ≈ 139 MB of
    # the 206 MB repo): the sparse GitFetch cone declares ["tf/2.0",
    # "docs/about.md"] (about.md carries the Abegg license grant). Older
    # version dirs (tf/0.1..1.9) and the docs/programs/log trees never
    # materialize.
    #
    # == License (both quoted verbatim, retrieved 2026-07-18)
    #
    # Every .tf header carries the machine-readable pair
    # "@license=Creative Commons Attribution-NonCommercial 4.0
    # International License" + "@licenseUrl=http://creativecommons.org/
    # licenses/by-nc/4.0/", and docs/about.md carries the human grant:
    # "Upon learning of the current project, Martin Abegg graciously gave
    # permission to Jarod Jacobs to use his data and to distribute the
    # results under a CC-BY-NC license." (also: "The data in this repo,
    # notably the contents of its `.tf` subdirectory, is available under a
    # CC-BY-NC license"; the MIT grant covers "the program code in this
    # repo" only) → class nc, the bhsa/proiel/gretil posture: recorded on
    # every serving surface so query/export/MCP filters never over-share.
    #
    # == Identity: document = scroll, passage = fragment + line
    #
    # The corpus's OWN citation grain (1QS f1:3): sectionTypes in otext.tf
    # are scroll,fragment,line. One document per scroll node, named by
    # scroll.tf ("1QS", "3Q15", "Xhev/se2" — urn:nabu:dss:<name downcased
    # VERBATIM, slashes and all>; censused collision-free at the pin).
    # FOUR names each label TWO scroll nodes (4Q88, 4Q483, 11Q5, 11Q6 —
    # the biblical/non-biblical source-file split the conversion did not
    # reunite); the second node in node order gets a "-2" suffix, stable
    # under the frozen version pin. One passage per line node,
    # <doc-urn>:<fragment>.<line> from the line node's own fragment/line
    # features (labels verbatim, case preserved — "f1R.2"; line labels are
    # all-integer at the pin, fragment labels never contain "."; the
    # (scroll, fragment, line) triple censused globally unique).
    #
    # == Text and tokens
    #
    # Passage text is the corpus's own text-orig-full rendering —
    # {glyph}{punc}{after} per sign slot (otext.tf; punc is word-grain
    # upstream, so signs contribute glyph+after) — assembled byte-verbatim,
    # trailing whitespace stripped. The transcription is CONSONANTAL
    # HEBREW SCRIPT (upstream maps Abegg's transliteration to Hebrew
    # UNICODE; lexemes are pointed), so hbo/arc text rides the P26-3 NFC
    # exemption byte-verbatim; upstream's improvised marks are kept as
    # shipped (ε missing signs, ╱ end-of-line tokens, paleo-Hebrew numeral
    # glyphs like א֜ק֜).
    #
    # Tokens are WORD-grain. Each carries: "n" (stable TF word node),
    # "form" (glyph — letters only; punct words and empty transcriptions
    # have none and keep their place, the bhsa empty-form precedent),
    # "full" (the flagged transcription VERBATIM — brackets, uncertainty
    # flags and inner spaces exactly as upstream ships them: "ח##פנו?׳ה##[ י ]"
    # — the byte-honest text-critical layer), "punc", "after", "lang"
    # (absent→hbo, "a"→arc, "g"→grc — 3Q15's Greek letter clusters; any
    # other value is a ParseError), the word "type" (glyph/punct/numr),
    # "lex" (pointed lexeme, verbatim including "_1" homograph suffixes
    # and uncertainty placeholders like " # "), Abegg's morphology
    # DECOMPOSED (sp/cl/ps/gn/nu/st/vs/vt/md) beside the original tag
    # ("morpho") verbatim, "script" (paleohebrew/greekcapital), "merr"
    # (the parser's honest error, one word corpus-wide), "intl"
    # (interlinear), and the biblical reference lane when present:
    # "biblical" (1 = biblical file, 2 = in both files) + "book"/
    # "chapter"/"verse"/"halfverse" verbatim (N.B. upstream's own caveat:
    # "book" is sometimes a scroll siglum like "1Q1", and chapter/verse
    # are sometimes fragment/line refs). Censused invariants the token
    # builder relies on: words never cross line boundaries, and word slot
    # specs are contiguous at the pin.
    #
    # == Clusters: the text-critical spans (VERBATIM, never flattened)
    #
    # Upstream groups flagged signs into cluster NODES typed cor/cor2/
    # cor3 (modern/ancient/supralinear correction), rem/rem2 (removed),
    # rec (modern reconstruction), alt (alternative), unc2 (uncertainty
    # degree 2), vac (vacat — empty unwritten space). These ride passage
    # annotations as "clusters" — the bhsa "spans" shape (architecture
    # §5): {"type" (upstream's own value verbatim, degrees intact),
    # "node" (TF cluster node — the stable global identity), "ranges"
    # (0-based inclusive token-index pairs into this passage's tokens,
    # tokens whose sign spans intersect the cluster)}. A vac cluster
    # contains only an empty sign belonging to NO word — it rides with
    # "ranges": [] (a positioned gap, not a defect). Six clusters
    # corpus-wide cross line boundaries; each affected passage carries its
    # clipped ranges with "partial": true, joined by the shared node id.
    # Sub-token bracket placement is NOT flattened away — it lives in each
    # token's "full" bytes; per-sign degree flags (unc 1-4) likewise ride
    # "full" verbatim.
    #
    # == What is deliberately NOT ingested (journaled, 02-sources row 88)
    #
    # - The ML-derived ETCBC extras — every *_etcbc feature and the v2.0
    #   clause/phrase nodes (125 clauses / 315 phrases, ALL in 1Qisaa) —
    #   are SILVER (about.md: models "trained on BHSA... applied to the
    #   DSS. This is experimental"): skipped entirely, the goo300k/imp
    #   discipline (label or omit, never pass off as gold).
    # - The lex-NODE lane (10,450 lexeme nodes + occ edges) — tokens carry
    #   the word-grain lex verbatim; a lexeme shelf is a future packet.
    #   OSHB join measured at fixture time by consonantal folding: 301 of
    #   372 foldable distinct fixture lexemes (80.9%) match an augmented-
    #   Strong headword — measured, reported, not wired.
    # - The transliteration lanes (*e/*o variants, g_cons, srcLn, nr,
    #   sim, note_etcbc) — the Unicode main variants are the surface.
    # - No timeline: tf/2.0 carries NO period/dating feature (censused —
    #   "script" is paleohebrew/greekcapital, a script fact riding tokens,
    #   not a date). The isicily verdict: nothing structured to extract.
    #
    # == Census (verified against otype.tf at the pin, 2026-07-18)
    #
    # 1,430,241 signs / 500,995 words / 52,895 lines / 11,182 fragments /
    # 1,001 scroll nodes (997 names) / 10,450 lexemes — every briefed
    # number exact — plus 101,099 clusters and the 125/315 silver
    # clause/phrase nodes above.
    class Dss < Nabu::Adapter
      REPO_URL = "https://github.com/ETCBC/dss"

      # The sparse cone: the pinned dataset + the license grant.
      SPARSE_PATHS = ["tf/2.0", "docs/about.md"].freeze

      TF_DIR = File.join("tf", "2.0").freeze

      MANIFEST = Nabu::SourceManifest.new(
        id: "dss",
        name: "DSS — Dead Sea Scrolls (Abegg/ETCBC, Text-Fabric tf/2.0)",
        license: "CC BY-NC 4.0 (every .tf header verbatim: \"@license=Creative Commons " \
                 "Attribution-NonCommercial 4.0 International License\"; docs/about.md verbatim: " \
                 "\"Martin Abegg graciously gave permission to Jarod Jacobs to use his data and to " \
                 "distribute the results under a CC-BY-NC license\". The repo's MIT grant covers " \
                 "\"the program code\" only, never the data)",
        license_class: "nc",
        upstream_url: REPO_URL,
        parser_family: "text-fabric"
      )

      URN_PREFIX = "urn:nabu:dss:"

      # lang.tf word values: ABSENT means Hebrew (upstream's own encoding);
      # "a" Aramaic, "g" Greek (3Q15's letter clusters). Anything else is
      # upstream drift, never guessed at.
      LANGUAGE_BY_VALUE = { nil => "hbo", "a" => "arc", "g" => "grc" }.freeze

      # Word-grain features riding tokens verbatim, key = feature name.
      TOKEN_FEATURES = %w[type lex sp cl ps gn nu st vs vt md morpho script merr intl
                          biblical book chapter verse halfverse].freeze

      def self.manifest
        MANIFEST
      end

      # One DocumentRef per scroll node named by scroll.tf, sorted by urn.
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
          scroll: document_ref.metadata.fetch("scroll"),
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
        return [] unless File.file?(File.join(dir, "otype.tf")) && File.file?(File.join(dir, "scroll.tf"))

        corpus = corpus(dir)
        seen = Hash.new(0)
        corpus.scrolls.map do |node, name|
          ordinal = (seen[name] += 1)
          Nabu::DocumentRef.new(
            source_id: manifest.id,
            id: "#{URN_PREFIX}#{name.downcase}#{"-#{ordinal}" if ordinal > 1}",
            path: dir,
            metadata: { "scroll" => name, "node" => node }
          )
        end.sort_by(&:id)
      end

      # One Corpus per dataset dir per adapter instance: the scroll parse
      # calls share the loaded features and the line/cluster indexes.
      def corpus(dir)
        @corpus ||= {}
        @corpus[dir] ||= Corpus.new(Nabu::Adapters::TextFabric::Dataset.new(dir))
      end

      def build_document(corpus, urn:, scroll:, node:)
        lines = corpus.lines_of(node)
        raise ParseError, "#{corpus.dir}: scroll #{scroll} (node #{node}) has no lines" if lines.empty?

        built = lines.map { |line_node| build_line(corpus, line_node) }
        language = majority_language(built.flat_map { |line| line[:tokens] }) || "hbo"
        metadata = { "scroll" => scroll }
        biblical = corpus.biblical(node)
        metadata["biblical"] = biblical if biblical
        document = Nabu::Document.new(
          urn: urn, language: language, title: scroll, canonical_path: corpus.dir,
          metadata: metadata
        )
        built.each_with_index do |line, sequence|
          document << passage(line, urn: urn, sequence: sequence, fallback: language)
        end
        document
      end

      def passage(line, urn:, sequence:, fallback:)
        annotations = { "tokens" => line[:tokens] }
        annotations["clusters"] = line[:clusters] unless line[:clusters].empty?
        Nabu::Passage.new(
          urn: "#{urn}:#{line[:fragment]}.#{line[:line]}",
          language: majority_language(line[:tokens]) || fallback,
          text: line[:text],
          annotations: annotations,
          sequence: sequence
        )
      end

      def build_line(corpus, line_node)
        span = corpus.slot_span(line_node)
        raise ParseError, "#{corpus.dir}: line node #{line_node} has no slots" if span.nil?

        words = corpus.words_in(span)
        {
          fragment: corpus.fragment_of(line_node), line: corpus.line_of(line_node),
          text: line_text(corpus, span, line_node),
          tokens: words.map { |word| token(corpus, word) },
          clusters: clusters(corpus, line_node, span, words)
        }
      end

      # The corpus's own text-orig-full rendering ({glyph}{punc}{after} per
      # sign slot), byte-verbatim, trailing whitespace stripped.
      def line_text(corpus, span, line_node)
        text = (span.first..span.last).map { |slot| corpus.sign_text(slot) }.join.rstrip
        raise ParseError, "#{corpus.dir}: line node #{line_node} renders empty" if text.empty?

        text
      end

      def token(corpus, word)
        token = { "n" => word.node }
        form = corpus.word_feature("glyph", word.node)
        token["form"] = form if form
        %w[full punc after].each do |name|
          value = corpus.word_feature(name, word.node)
          token[name] = value if value
        end
        token["lang"] = corpus.language_of(word.node)
        TOKEN_FEATURES.each do |name|
          value = corpus.word_feature(name, word.node)
          token[name] = value unless value.nil?
        end
        token
      end

      # The text-critical layer: upstream's own cluster nodes intersecting
      # this line, as passage-relative token-index ranges (the bhsa spans
      # shape). A vac cluster covers no word and rides with empty ranges.
      def clusters(corpus, line_node, span, words)
        corpus.clusters_of(line_node).map do |cluster|
          covered = words.each_index.select { |i| words[i].intersects?(cluster.first, cluster.last) }
          entry = {
            "type" => cluster.type, "node" => cluster.node,
            "ranges" => index_ranges(covered)
          }
          entry["partial"] = true unless span.first <= cluster.first && cluster.last <= span.last
          entry
        end
      end

      # Compress ascending indexes into inclusive [from, to] pairs.
      def index_ranges(indexes)
        indexes.slice_when { |a, b| b != a + 1 }.map { |run| [run.first, run.last] }
      end

      # Majority "lang" vote over tokens (insertion order breaks ties —
      # deterministic; the corph/oshb/bhsa precedent), nil when none vote.
      def majority_language(tokens)
        votes = tokens.filter_map { |token| token["lang"] }
        return nil if votes.empty?

        votes.tally.max_by { |_code, count| count }.first
      end

      # The DSS-shaped view over a TextFabric::Dataset: which features ride
      # where is dss POLICY, so it lives here, not in the family.
      class Corpus
        Word = Data.define(:node, :first, :last) do
          def intersects?(from, to) = first <= to && from <= last
        end

        Cluster = Data.define(:node, :type, :first, :last)

        def initialize(dataset)
          @dataset = dataset
        end

        def dir = @dataset.dir

        # { scroll node => name } in node order — scroll.tf also labels
        # fragment/line nodes, so restrict to otype's scroll range.
        def scrolls
          @scrolls ||= begin
            first, last = type_span("scroll")
            @dataset.feature("scroll").each_pair
                    .select { |node, _name| node.between?(first, last) }.to_h
          end
        end

        def biblical(node)
          @dataset.feature("biblical").fetch(node)
        end

        # Line nodes of a scroll, in node order (== canonical order: the
        # censused invariant that line node order follows slot order).
        def lines_of(scroll_node)
          span = slot_span(scroll_node)
          return [] if span.nil?

          line_slot_spans.each_pair.filter_map do |node, (first, _last)|
            node if first.between?(span.first, span.last)
          end
        end

        # The inclusive [first, last] slot span of a node (line/scroll
        # spans are contiguous at the pin).
        def slot_span(node)
          ranges = @dataset.slot_ranges(node)
          return nil if ranges.nil? || ranges.empty?

          [ranges.first.first, ranges.last.last]
        end

        def fragment_of(line_node) = @dataset.feature("fragment").fetch(line_node)
        def line_of(line_node) = @dataset.feature("line").fetch(line_node)

        def sign_text(slot)
          "#{@dataset.feature('glyph').fetch(slot)}#{@dataset.feature('punc').fetch(slot)}" \
            "#{@dataset.feature('after').fetch(slot)}"
        end

        def word_feature(name, node)
          @dataset.feature(name).fetch(node)
        end

        def language_of(word_node)
          value = @dataset.feature("lang").fetch(word_node)
          Dss::LANGUAGE_BY_VALUE.fetch(value) do
            raise Nabu::ParseError,
                  "#{dir}: lang.tf says #{value.inspect} for word #{word_node} — not absent/a/g, " \
                  "and a language is never guessed"
          end
        end

        # Words whose first slot lies in +span+, ascending (words never
        # cross line boundaries — censused invariant).
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

        # Clusters whose slots intersect this line's span, ascending by
        # first slot — from a once-per-dataset assignment pass (the bhsa
        # constituents_by_verse pattern): line spans are ascending and
        # non-overlapping, so each cluster lands on a contiguous run of
        # lines found by binary search.
        def clusters_of(line_node)
          clusters_by_line.fetch(line_node, [])
        end

        private

        def type_span(type)
          ranges = @dataset.type_ranges.fetch(type) do
            raise Nabu::ParseError, "#{dir}: otype.tf declares no #{type.inspect} nodes"
          end
          [ranges.first.first, ranges.last.last]
        end

        # { line node => [first_slot, last_slot] }, insertion in node order.
        def line_slot_spans
          @line_slot_spans ||= begin
            first, last = type_span("line")
            spans = {}
            @dataset.feature("oslots").each_pair do |node, spec|
              next unless node.between?(first, last)

              ranges = TextFabric.parse_ranges(spec, path: File.join(dir, "oslots.tf"))
              spans[node] = [ranges.first.first, ranges.last.last]
            end
            spans
          end
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

        # { line node => [Cluster] }, each cluster (upstream's own type
        # feature, degrees intact: cor/cor2/cor3, rem/rem2, rec, alt,
        # unc2, vac) assigned to every line its slots intersect.
        def clusters_by_line
          @clusters_by_line ||= begin
            first, last = type_span("cluster")
            typef = @dataset.feature("type")
            lines = line_slot_spans.map { |node, (from, to)| [from, to, node] }.sort
            firsts = lines.map(&:first)
            map = Hash.new { |hash, key| hash[key] = [] }
            @dataset.feature("oslots").each_pair do |node, spec|
              next unless node.between?(first, last)

              ranges = TextFabric.parse_ranges(spec, path: File.join(dir, "oslots.tf"))
              cluster = Cluster.new(node: node, type: typef.fetch(node),
                                    first: ranges.first.first, last: ranges.last.last)
              index = (firsts.bsearch_index { |slot| slot > cluster.first } || lines.size) - 1
              index = 0 if index.negative?
              while index < lines.size && lines[index][0] <= cluster.last
                map[lines[index][2]] << cluster if cluster.first <= lines[index][1]
                index += 1
              end
            end
            map.each_value { |list| list.sort_by!(&:first) }
            map.default = nil
            map
          end
        end
      end
    end
  end
end

# frozen_string_literal: true

require_relative "text_fabric"

module Nabu
  module Adapters
    # BHSA — the ETCBC Biblia Hebraica Stuttgartensia Amstelodamensis
    # (P30-4): the Amsterdam syntax corpus of the Hebrew Bible as
    # Text-Fabric features, the FIRST text-fabric registrant and nabu's
    # first constituency data. The SECOND Masoretic witness beside oshb at a
    # deliberately different grain (the MW-beside-kaikki precedent, never
    # merged): oshb carries the WLC with Strong's lemmas and OSHM morphology;
    # BHSA carries the same text with the ETCBC's linguistic database —
    # per-lexeme English glosses and frequencies, H/A language per word, and
    # the full clause/phrase constituency.
    #
    # == Version pin and fetch
    #
    # PINNED to the frozen tf/2021 dataset directory (118 files ≈ 173 MB of
    # the 1.6 GB repo): the sparse GitFetch cone (the dcs recipe) declares
    # ["tf/2021", "README.md"], so older versions (tf/3..tf/2017), the
    # continuous "c" edition, and the heavyweight docs/programs trees never
    # materialize. The dataset itself is versioned by directory — a re-sync
    # only ever refreshes the same frozen 2021 files.
    #
    # == License (verbatim, README.md, verified 2026-07-18)
    #
    # "This work is licensed under a Attribution-NonCommercial 4.0
    # International (CC BY-NC 4.0). … give proper attribution to the data
    # when you use it in new applications, by citing this persistent
    # identifier: 10.17026/dans-z6y-skyh. … do not use the data for
    # commercial applications without consent; for any commercial use,
    # please contact the German Bible Society." The GitHub MIT badge covers
    # the repo's CODE only — the data grant is the README's CC BY-NC 4.0 →
    # class nc, the proiel/gretil discipline: recorded on every serving
    # surface so query/export/MCP filters never over-share.
    #
    # == Identity (FROZEN minting) and the ot hub
    #
    # Document = book, passage = verse — the corpus's own citation grain.
    # urn:nabu:bhsa:<osis-book downcased> from the FIXED table below (BHSA's
    # Latin book names — "Jona", "Threni", "Chronica_I" — map to the same
    # OSIS stems oshb mints, so the alignment hub's work tokens agree);
    # passage urns <doc-urn>:<chapter>.<verse> from the corpus's own
    # book/chapter/verse section features. The ot + psalms works register
    # BHSA as a witness via cts-verse with oshb's exact conservative book
    # map (same MT versification, same holdouts). An unknown book name is a
    # ParseError, never a guess.
    #
    # == Text and tokens
    #
    # Verse text is the corpus's own ketiv rendering — otext.tf's
    # text-orig-full-ketiv format {g_word_utf8}{trailer_utf8} — assembled
    # byte-verbatim (hbo/arc ride the P26-3 NFC exemption; trailers carry
    # the maqqef/sof pasuq/samekh-pe parashah marks). The qere rides the
    # token as "qere" word hashes — the SAME shape oshb mints, so the P27
    # qere display contract (qere_display: qere, docs/display.md) applies
    # unchanged; kq_hybrid_utf8 (the ETCBC's ketiv-consonants/qere-points
    # hybrid) rides beside it verbatim. Tokens carry, per word slot: "n"
    # (the stable TF slot number), "form", "trailer", "lex" (ETCBC
    # transliterated lexeme id), "gloss" + "freq_lex" (the per-lexeme
    # English gloss and corpus frequency, word-grain as upstream ships
    # them), "lang" (language.tf Hebrew/Aramaic → hbo/arc — anything else
    # is a ParseError), and the six morphology features sp/vs/vt/gn/nu/ps
    # verbatim (including upstream's honest "NA"/"unknown"). Empty forms
    # are REAL (6,488 elided-article slots — בַּ = בְּ + a surfaceless הַ);
    # the token keeps its place with no "form" key. The transliteration
    # lanes (g_word, lex0, …) and the version-map omap@* edges are
    # deliberately not ingested.
    #
    # == Constituency spans (THE DESIGN NOTE, implemented below)
    #
    # Nabu's first syntax-bearing corpus must carry clause/phrase extents
    # WITHOUT a new table. The note: spans ride the same per-passage
    # annotations JSON that already carries tokens — a "spans" array beside
    # "tokens", each span {"type", "node", "ranges", …}:
    #
    #   - "ranges" are 0-based INCLUSIVE INDEX PAIRS INTO THIS PASSAGE'S
    #     OWN tokens array ([[0,1],[8,10]]) — passage-relative, so a
    #     consumer needs no global slot table, and a span survives storage,
    #     display and MCP exactly as tokens do. A list, not a pair: 2,454
    #     BHSA clauses / 672 phrases are genuinely discontinuous.
    #   - "node" is the upstream TF node id — the span's stable global
    #     identity. 50 clauses / 15 phrases cross verse boundaries; each
    #     affected passage carries its own clipped ranges with
    #     "partial": true, and the shared node id is what joins the pieces
    #     (and, later, the bridging crosswalk and any cross-corpus syntax
    #     work).
    #   - the span's own features ride beside it verbatim — "kind" for
    #     clauses (VC/NC/WP), "function" for phrases (Pred/Subj/Objc…) —
    #     the deep-extraction layer that makes spans queryable rather than
    #     decorative.
    #
    # Spans order by first covered token, clauses before phrases at a tie
    # (containment order), node id last. This generalizes: any adapter with
    # constituent extents over its tokens (dss v2.0's ML clause/phrase
    # boundaries next, P30-5) emits the same shape; the contract lives in
    # architecture §5 beside the tokens contract.
    #
    # == What the file-grain breaker cannot see (honest limitation)
    #
    # Refs point at the dataset DIRECTORY (a book is not a file), so the
    # pre-merge mass-deletion breaker's path intersection cannot attribute
    # deleted .tf files to refs; GitFetch still attics deletions, and the
    # load-side withdrawal guard still trips when books vanish from
    # discover. Sized acceptable for a frozen, manually-synced dataset.
    #
    # == Census (verified against otype.tf at fixture time, 2026-07-18)
    #
    # 426,590 words / 39 books / 929 chapters / 23,213 verses / 88,131
    # clauses / 253,203 phrases / 9,230 lexemes (the backlog's "64,514
    # sentences" is the sentence_ATOM count; sentence proper = 63,717 —
    # both honest, neither ingested as spans yet: journaled). The sibling
    # repo ETCBC/bridging (MIT — the OSHB↔BHSA word-level crosswalk) is
    # journaled in docs/02-sources.md and NOT wired.
    class Bhsa < Nabu::Adapter
      REPO_URL = "https://github.com/ETCBC/bhsa"

      # The sparse cone: the pinned dataset + the README carrying the
      # license grant.
      SPARSE_PATHS = ["tf/2021", "README.md"].freeze

      TF_DIR = File.join("tf", "2021").freeze

      MANIFEST = Nabu::SourceManifest.new(
        id: "bhsa",
        name: "BHSA — Biblia Hebraica Stuttgartensia Amstelodamensis (ETCBC, Text-Fabric tf/2021)",
        license: "CC BY-NC 4.0 (README.md verbatim: \"This work is licensed under a " \
                 "Attribution-NonCommercial 4.0 International (CC BY-NC 4.0)\"; attribution by citing " \
                 "DOI 10.17026/dans-z6y-skyh; commercial use requires German Bible Society consent. " \
                 "The repo's MIT badge covers code only, never the data)",
        license_class: "nc",
        upstream_url: REPO_URL,
        parser_family: "text-fabric"
      )

      URN_PREFIX = "urn:nabu:bhsa:"

      # BHSA Latin book name -> OSIS stem (downcased into urns) — the same
      # stems oshb mints, so hub work tokens land on both MT witnesses.
      OSIS_BY_BOOK = {
        "Genesis" => "Gen", "Exodus" => "Exod", "Leviticus" => "Lev", "Numeri" => "Num",
        "Deuteronomium" => "Deut", "Josua" => "Josh", "Judices" => "Judg",
        "Samuel_I" => "1Sam", "Samuel_II" => "2Sam", "Reges_I" => "1Kgs", "Reges_II" => "2Kgs",
        "Jesaia" => "Isa", "Jeremia" => "Jer", "Ezechiel" => "Ezek",
        "Hosea" => "Hos", "Joel" => "Joel", "Amos" => "Amos", "Obadia" => "Obad",
        "Jona" => "Jonah", "Micha" => "Mic", "Nahum" => "Nah", "Habakuk" => "Hab",
        "Zephania" => "Zeph", "Haggai" => "Hag", "Sacharia" => "Zech", "Maleachi" => "Mal",
        "Psalmi" => "Ps", "Iob" => "Job", "Proverbia" => "Prov", "Ruth" => "Ruth",
        "Canticum" => "Song", "Ecclesiastes" => "Eccl", "Threni" => "Lam", "Esther" => "Esth",
        "Daniel" => "Dan", "Esra" => "Ezra", "Nehemia" => "Neh",
        "Chronica_I" => "1Chr", "Chronica_II" => "2Chr"
      }.freeze

      LANGUAGE_BY_VALUE = { "Hebrew" => "hbo", "Aramaic" => "arc" }.freeze

      # Cannot happen upstream (language.tf covers every word) — but a book
      # whose fixture slice somehow carried no voting tokens must fall back
      # honestly, never guess per-verse.
      DEFAULT_LANGUAGE = "hbo"

      # Word-grain features riding tokens verbatim, key = feature name.
      TOKEN_FEATURES = %w[lex gloss freq_lex sp vs vt gn nu ps].freeze

      # Constituent types carried as spans, with their per-type feature.
      SPAN_FEATURES = { "clause" => "kind", "phrase" => "function" }.freeze
      SPAN_TYPE_ORDER = { "clause" => 0, "phrase" => 1 }.freeze

      def self.manifest
        MANIFEST
      end

      # One DocumentRef per book node named by book.tf, sorted by urn. A
      # workdir without the pinned dataset (pre-fetch) yields nothing.
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        document_refs(workdir).each(&block)
      end

      def parse(document_ref)
        corpus = corpus(document_ref.path)
        book = document_ref.metadata.fetch("book")
        node = document_ref.metadata.fetch("node")
        build_document(corpus, urn: document_ref.id, book: book, node: node)
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
        return [] unless File.file?(File.join(dir, "otype.tf")) && File.file?(File.join(dir, "book.tf"))

        corpus = corpus(dir)
        corpus.books.map do |node, name|
          Nabu::DocumentRef.new(
            source_id: manifest.id,
            id: "#{URN_PREFIX}#{osis!(name, dir).downcase}",
            path: dir,
            metadata: { "book" => name, "node" => node }
          )
        end.sort_by(&:id)
      end

      def osis!(book, context)
        OSIS_BY_BOOK.fetch(book) do
          raise ParseError, "#{context}: unknown BHSA book name #{book.inspect} — the OSIS table is " \
                            "fixed at 39 books; a new name is upstream drift, never guessed at"
        end
      end

      # One Corpus per dataset dir per adapter instance: 39 parse calls
      # share the loaded features and the verse/constituent indexes.
      def corpus(dir)
        @corpus ||= {}
        @corpus[dir] ||= Corpus.new(Nabu::Adapters::TextFabric::Dataset.new(dir))
      end

      def build_document(corpus, urn:, book:, node:)
        verses = corpus.verses_of(book)
        raise ParseError, "#{corpus.dir}: book #{book} (node #{node}) has no verses" if verses.empty?

        built = verses.map { |verse_node| build_verse(corpus, verse_node) }
        language = majority_language(built.flat_map { |verse| verse[:tokens] }) || DEFAULT_LANGUAGE
        document = Nabu::Document.new(
          urn: urn, language: language, title: book, canonical_path: corpus.dir,
          metadata: { "book" => book }
        )
        built.each_with_index do |verse, sequence|
          document << passage(verse, urn: urn, sequence: sequence, fallback: language)
        end
        document
      end

      def passage(verse, urn:, sequence:, fallback:)
        annotations = { "tokens" => verse[:tokens] }
        annotations["spans"] = verse[:spans] unless verse[:spans].empty?
        Nabu::Passage.new(
          urn: "#{urn}:#{verse[:chapter]}.#{verse[:verse]}",
          language: majority_language(verse[:tokens]) || fallback,
          text: verse[:text],
          annotations: annotations,
          sequence: sequence
        )
      end

      def build_verse(corpus, verse_node)
        slots = corpus.slots(verse_node)
        raise ParseError, "#{corpus.dir}: verse node #{verse_node} has no slots" if slots.empty?

        text = verse_text(corpus, slots, verse_node)
        {
          chapter: corpus.chapter_of(verse_node), verse: corpus.verse_of(verse_node),
          text: text, tokens: slots.map { |slot| token(corpus, slot) },
          spans: spans(corpus, verse_node, slots)
        }
      end

      # The ketiv rendering (otext.tf text-orig-full-ketiv):
      # {g_word_utf8}{trailer_utf8} per slot, trailing whitespace stripped.
      def verse_text(corpus, slots, verse_node)
        text = slots.map { |slot| "#{corpus.form(slot)}#{corpus.trailer(slot)}" }.join.rstrip
        raise ParseError, "#{corpus.dir}: verse node #{verse_node} has no text" if text.empty?

        text
      end

      def token(corpus, slot)
        token = { "n" => slot }
        form = corpus.form(slot)
        token["form"] = form unless form.empty?
        trailer = corpus.trailer(slot)
        token["trailer"] = trailer unless trailer.empty?
        TOKEN_FEATURES.each do |name|
          value = corpus.token_feature(name, slot)
          token[name] = value unless value.nil?
        end
        token["lang"] = corpus.language_of(slot)
        qere = corpus.qere(slot)
        token["qere"] = qere if qere
        hybrid = corpus.kq_hybrid(slot)
        token["kq_hybrid"] = hybrid if hybrid
        token
      end

      # The design note, executed: clause/phrase constituents intersecting
      # this verse, as passage-relative token-index ranges.
      def spans(corpus, verse_node, slots)
        index_of = slots.each_with_index.to_h
        built = corpus.constituents_of(verse_node).map { |constituent| span(constituent, index_of) }
        built.sort_by { |span| [span["ranges"].first.first, SPAN_TYPE_ORDER.fetch(span["type"]), span["node"]] }
      end

      def span(constituent, index_of)
        covered = constituent.slot_ranges.flat_map { |first, last| (first..last).to_a }
                                         .filter_map { |slot| index_of[slot] }
        span = {
          "type" => constituent.type, "node" => constituent.node,
          "ranges" => index_ranges(covered)
        }
        span["partial"] = true if covered.size < constituent.slot_count
        span[constituent.feature_key] = constituent.feature_value if constituent.feature_value
        span
      end

      # Compress ascending indexes into inclusive [from, to] pairs.
      def index_ranges(indexes)
        indexes.slice_when { |a, b| b != a + 1 }.map { |run| [run.first, run.last] }
      end

      # Majority "lang" vote over tokens (insertion order breaks ties —
      # deterministic; the corph/oshb precedent), or nil when nothing votes.
      def majority_language(tokens)
        votes = tokens.filter_map { |token| token["lang"] }
        return nil if votes.empty?

        votes.tally.max_by { |_code, count| count }.first
      end

      # The BHSA-shaped view over a TextFabric::Dataset: which features ride
      # where is bhsa POLICY, so it lives here, not in the family.
      class Corpus
        Constituent = Data.define(:node, :type, :slot_ranges, :slot_count, :feature_key, :feature_value)

        def initialize(dataset)
          @dataset = dataset
        end

        def dir = @dataset.dir

        # { book node => Latin name } — book.tf entries within otype's book
        # range (the feature also covers chapter/verse nodes).
        def books
          @books ||= grain_entries("book", "book")
        end

        def verses_of(book)
          verse_books.each_pair.filter_map { |node, name| node if name == book && verse?(node) }
        end

        def chapter_of(verse_node) = @dataset.feature("chapter").fetch(verse_node)
        def verse_of(verse_node) = @dataset.feature("verse").fetch(verse_node)

        def slots(node)
          (@dataset.slot_ranges(node) || []).flat_map { |first, last| (first..last).to_a }
        end

        def form(slot) = @dataset.feature("g_word_utf8").fetch(slot, "")
        def trailer(slot) = @dataset.feature("trailer_utf8").fetch(slot, "")

        def token_feature(name, slot)
          @dataset.feature(name).fetch(slot)
        end

        def language_of(slot)
          value = @dataset.feature("language").fetch(slot)
          LANGUAGE_BY_VALUE.fetch(value) do
            raise Nabu::ParseError,
                  "#{dir}: language.tf says #{value.inspect} for word #{slot} — not Hebrew/Aramaic, " \
                  "and a language is never guessed"
          end
        end

        # The qere reading as the oshb-shaped word-hash list (the P27
        # display contract reads "form").
        def qere(slot)
          form = @dataset.feature("qere_utf8").fetch(slot)
          return nil if form.nil?

          word = { "form" => form }
          trailer = @dataset.feature("qere_trailer_utf8").fetch(slot, "")
          word["trailer"] = trailer unless trailer.strip.empty?
          [word]
        end

        def kq_hybrid(slot)
          @dataset.feature("kq_hybrid_utf8").fetch(slot)
        end

        # Constituents (clauses/phrases) intersecting a verse, via the
        # once-per-dataset slot index.
        def constituents_of(verse_node)
          constituents_by_verse.fetch(verse_node, [])
        end

        private

        def verse?(node)
          node.between?(verse_range.first, verse_range.last)
        end

        def verse_range
          @verse_range ||= type_span("verse")
        end

        def type_span(type)
          ranges = @dataset.type_ranges.fetch(type) do
            raise Nabu::ParseError, "#{dir}: otype.tf declares no #{type.inspect} nodes"
          end
          [ranges.first.first, ranges.last.last]
        end

        def verse_books
          @dataset.feature("book")
        end

        def grain_entries(feature, type)
          span = type_span(type)
          @dataset.feature(feature).each_pair.select { |node, _v| node.between?(span.first, span.last) }.to_h
        end

        # verse node => [Constituent] — one pass over the clause/phrase
        # entries in oslots, each assigned to every verse its slots touch.
        def constituents_by_verse
          @constituents_by_verse ||= begin
            map = Hash.new { |hash, key| hash[key] = [] }
            SPAN_FEATURES.each do |type, feature_name|
              each_constituent(type, feature_name) do |constituent|
                verses_touching(constituent.slot_ranges).each { |verse_node| map[verse_node] << constituent }
              end
            end
            map.each_value(&:freeze)
            map.default = nil
            map
          end
        end

        def each_constituent(type, feature_name)
          span = type_span(type)
          feature = @dataset.feature(feature_name)
          @dataset.feature("oslots").each_pair do |node, spec|
            next unless node.between?(span.first, span.last)

            ranges = Nabu::Adapters::TextFabric.parse_ranges(spec, path: File.join(dir, "oslots.tf"))
            yield Constituent.new(
              node: node, type: type, slot_ranges: ranges,
              slot_count: ranges.sum { |first, last| last - first + 1 },
              feature_key: SPAN_FEATURES.fetch(type), feature_value: feature.fetch(node)
            )
          end
        end

        # Verse nodes whose slot spans intersect +ranges+ — binary search
        # over the ascending (first_slot, verse_node) list. Verses are
        # ascending and non-overlapping, so scanning back from the first
        # span past the range and breaking once spans end before it is
        # exact.
        def verses_touching(ranges)
          spans = verse_slot_spans
          ranges.flat_map do |first, last|
            from = verse_slot_firsts.bsearch_index { |slot| slot > last } || spans.size
            hits = []
            (from - 1).downto(0) do |i|
              slot_first, slot_last, verse_node = spans[i]
              break if slot_last < first && slot_first < first

              hits << verse_node if slot_last >= first
            end
            hits.reverse
          end.uniq
        end

        def verse_slot_firsts
          @verse_slot_firsts ||= verse_slot_spans.map(&:first)
        end

        # Ascending [first_slot, last_slot, verse_node] for every verse.
        def verse_slot_spans
          @verse_slot_spans ||= verse_books.each_pair.filter_map do |node, _name|
            next unless verse?(node)

            ranges = @dataset.slot_ranges(node)
            next if ranges.nil? || ranges.empty?

            [ranges.first.first, ranges.last.last, node]
          end.sort
        end
      end
    end
  end
end

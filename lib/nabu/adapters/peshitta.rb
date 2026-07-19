# frozen_string_literal: true

require_relative "text_fabric"

module Nabu
  module Adapters
    # Peshitta — the ETCBC Peshitta Old Testament incl. deuterocanon
    # (P31-4, github.com/ETCBC/peshitta): the classical Syriac Bible as
    # Text-Fabric features, the FOURTH text-fabric registrant. The
    # electronic text is an OCR (syrocr) of the Leiden Vetus Testamentum
    # Syriace edition — Codex Ambrosianus where VTS has not appeared —
    # WITHOUT the (Brill-copyrighted) critical apparatus. All corpus
    # policy lives here; the family stays format-only.
    #
    # == Version pin and fetch
    #
    # PINNED to the tf/0.2 dataset directory (13 files ≈ 9 MB): the sparse
    # GitFetch cone declares ["tf/0.2", "docs/about.md"] (about.md carries
    # the license grant and provenance). Upstream is archived/unsupported
    # (repostatus badge; last data release 2021) — effectively frozen.
    #
    # == License (verbatim, docs/about.md, retrieved 2026-07-19)
    #
    # "The plain text of the Peshitta, its conversion to Text-Fabric
    # format, is subject to the CC-BY-NC license … If you would like to
    # use the textual data commercially, contact the ETCBC or Brill." (the
    # conversion program alone is MIT) → class nc, the bhsa/dss posture:
    # recorded on every serving surface so query/export/MCP filters never
    # over-share. Citation: DOI 10.5281/zenodo.1464757.
    #
    # == Identity: document = book, passage = verse
    #
    # The corpus's own citation grain (otext sectionTypes
    # book,chapter,verse). One document per book node, urn:nabu:peshitta:
    # <siglum downcased verbatim — gn, thr, orm_a>; book@en rides as the
    # document title ("Genesis") and metadata "book_en". The A/B pairs
    # (EpBar, Mc1, OrM, ApcPs, Tb — parallel MANUSCRIPT RECENSIONS the
    # edition ships side by side) stay honest sibling documents; the
    # witness.tf letter rides document metadata and each verse's
    # annotations verbatim, never merged. Passage urns
    # <doc-urn>:<chapter>.<verse> from the corpus's own section features;
    # (book, chapter, verse) censused globally unique.
    #
    # == Versification (MEASURED, the ot-hub verdict)
    #
    # Chapter-grain census over all 39 protocanonical books matches the
    # MASORETIC grid exactly (Joel 4 chapters, Malachi 3, Proverbs 31,
    # Psalms 150 — Hebrew numbering; verse spot-checks: Jonah 1:16 + 2:11
    # against the MT split, Ps 22:2 = "my God, my God", Ps 23:1 = the
    # shepherd) → the Peshitta joins the ot alignment hub as the SEVENTH
    # leg with the OSHB/BHSA/Targum conservative book map VERBATIM, and
    # the psalter joins the psalms work through the P13-5 Hebrew→Greek
    # remap (config/alignments.yml). Titulus psalms carry the MT
    # convention with the (unprinted) superscription as verse 1 — Ps 22
    # opens at verse 2; absent verses simply attest per-witness.
    #
    # == Text and tokens
    #
    # Verse text is the corpus's own text-orig-full rendering —
    # {word}{trailer} per slot — assembled then NFC at the adapter
    # boundary (house rule: syc is NOT on the exemption list, that is
    # hbo/arc only; ~492 upstream word forms carry seyame/points in
    # non-canonical combining order). Tokens carry, per word slot: "n"
    # (the stable TF slot), "form" (Syriac script, NFC), "trailer"
    # (interword material verbatim — space, ". ", the Syriac punctuation
    # marks ܆܇܈܉), "etcbc" + "trailer_etcbc" (the ETCBC transliteration
    # lanes verbatim), and "witness" when the verse's node carries the
    # A/B stamp. ONE word slot corpus-wide (40311, in Leviticus) has no
    # word value: the token keeps its place with no "form" key (the
    # bhsa/dss empty-form precedent).
    #
    # == Census (verified against otype.tf at the pin, 2026-07-19)
    #
    # 426,835 words / 65 books / 1,269 chapters / 31,341 verses.
    class Peshitta < Nabu::Adapter
      REPO_URL = "https://github.com/ETCBC/peshitta"

      # The sparse cone: the pinned dataset + the license/provenance page.
      SPARSE_PATHS = ["tf/0.2", "docs/about.md"].freeze

      TF_DIR = File.join("tf", "0.2").freeze

      MANIFEST = Nabu::SourceManifest.new(
        id: "peshitta",
        name: "Peshitta OT incl. deuterocanon (ETCBC, Text-Fabric tf/0.2)",
        license: "CC BY-NC (docs/about.md verbatim: \"The plain text of the Peshitta, its conversion " \
                 "to Text-Fabric format, is subject to the CC-BY-NC license\"; commercial use via ETCBC " \
                 "or Brill; the conversion program alone is MIT; cite DOI 10.5281/zenodo.1464757)",
        license_class: "nc",
        upstream_url: REPO_URL,
        parser_family: "text-fabric"
      )

      URN_PREFIX = "urn:nabu:peshitta:"

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
        build_document(
          corpus,
          urn: document_ref.id,
          book: document_ref.metadata.fetch("book"),
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
        return [] unless File.file?(File.join(dir, "otype.tf")) && File.file?(File.join(dir, "book.tf"))

        corpus = corpus(dir)
        corpus.books.map do |node, siglum|
          Nabu::DocumentRef.new(
            source_id: manifest.id,
            id: "#{URN_PREFIX}#{siglum.downcase}",
            path: dir,
            metadata: { "book" => siglum, "book_en" => corpus.book_en(node), "node" => node }
          )
        end.sort_by(&:id)
      end

      def corpus(dir)
        @corpus ||= {}
        @corpus[dir] ||= Corpus.new(Nabu::Adapters::TextFabric::Dataset.new(dir))
      end

      def build_document(corpus, urn:, book:, node:)
        verses = corpus.verses_of(node)
        raise ParseError, "#{corpus.dir}: book #{book} (node #{node}) has no verses" if verses.empty?

        metadata = { "book" => book }
        book_en = corpus.book_en(node)
        metadata["book_en"] = book_en if book_en
        witness = corpus.witness(node)
        metadata["witness"] = witness if witness
        document = Nabu::Document.new(
          urn: urn, language: "syc", title: book_en || book, canonical_path: corpus.dir,
          metadata: metadata
        )
        verses.each_with_index do |verse, sequence|
          document << passage(corpus, verse, urn: urn, sequence: sequence)
        end
        document
      end

      def passage(corpus, verse, urn:, sequence:)
        text = verse_text(corpus, verse)
        annotations = { "tokens" => tokens(corpus, verse) }
        witness = corpus.witness(verse.node)
        annotations["witness"] = witness if witness
        Nabu::Passage.new(
          urn: "#{urn}:#{verse.chapter}.#{verse.verse}",
          language: "syc",
          text: text,
          annotations: annotations,
          sequence: sequence
        )
      end

      # The corpus's own text-orig-full rendering ({word}{trailer} per
      # slot), NFC at the boundary, trailing whitespace stripped.
      def verse_text(corpus, verse)
        text = (verse.first..verse.last).map { |slot| "#{corpus.word(slot)}#{corpus.trailer(slot)}" }
                                        .join.rstrip
        raise ParseError, "#{corpus.dir}: verse node #{verse.node} renders empty" if text.empty?

        Nabu::Normalize.nfc(text)
      end

      def tokens(corpus, verse)
        (verse.first..verse.last).map do |slot|
          token = { "n" => slot }
          form = corpus.word(slot)
          token["form"] = Nabu::Normalize.nfc(form) unless form.empty?
          trailer = corpus.trailer(slot)
          token["trailer"] = trailer unless trailer.empty?
          etcbc = corpus.word_etcbc(slot)
          token["etcbc"] = etcbc unless etcbc.nil?
          trailer_etcbc = corpus.trailer_etcbc(slot)
          token["trailer_etcbc"] = trailer_etcbc unless trailer_etcbc.nil?
          token
        end
      end

      # The Peshitta-shaped view over a TextFabric::Dataset: which features
      # ride where is peshitta POLICY, so it lives here, not in the family.
      class Corpus
        Verse = Data.define(:node, :chapter, :verse, :first, :last)

        def initialize(dataset)
          @dataset = dataset
        end

        def dir = @dataset.dir

        # { book node => siglum } in node order — book.tf labels only book
        # nodes in this corpus, but the range guard is cheap.
        def books
          @books ||= begin
            first, last = type_span("book")
            @dataset.feature("book").each_pair
                    .select { |node, _name| node.between?(first, last) }.to_h
          end
        end

        def book_en(node)
          @dataset.feature("book@en").fetch(node)
        end

        def witness(node)
          @dataset.feature("witness").fetch(node)
        end

        # Verses of a book in node order (== canonical order: verse node
        # order is censused equal to slot order), with their own
        # chapter/verse section labels.
        def verses_of(book_node)
          span = slot_span(book_node)
          return [] if span.nil?

          verse_slot_spans.filter_map do |first, last, node|
            next unless first.between?(span.first, span.last)

            Verse.new(node: node, chapter: @dataset.feature("chapter").fetch(node),
                      verse: @dataset.feature("verse").fetch(node), first: first, last: last)
          end
        end

        def word(slot) = @dataset.feature("word").fetch(slot, "")
        def trailer(slot) = @dataset.feature("trailer").fetch(slot, "")
        def word_etcbc(slot) = @dataset.feature("word_etcbc").fetch(slot)
        def trailer_etcbc(slot) = @dataset.feature("trailer_etcbc").fetch(slot)

        def slot_span(node)
          ranges = @dataset.slot_ranges(node)
          return nil if ranges.nil? || ranges.empty?

          [ranges.first.first, ranges.last.last]
        end

        private

        def type_span(type)
          ranges = @dataset.type_ranges.fetch(type) do
            raise Nabu::ParseError, "#{dir}: otype.tf declares no #{type.inspect} nodes"
          end
          [ranges.first.first, ranges.last.last]
        end

        # Ascending [first_slot, last_slot, verse_node].
        def verse_slot_spans
          @verse_slot_spans ||= begin
            first, last = type_span("verse")
            spans = []
            @dataset.feature("oslots").each_pair do |node, spec|
              next unless node.between?(first, last)

              ranges = TextFabric.parse_ranges(spec, path: File.join(dir, "oslots.tf"))
              spans << [ranges.first.first, ranges.last.last, node]
            end
            spans.sort
          end
        end
      end
    end
  end
end

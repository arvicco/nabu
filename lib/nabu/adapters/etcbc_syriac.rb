# frozen_string_literal: true

require_relative "text_fabric"

module Nabu
  module Adapters
    # ETCBC Syriac Corpus — the ETCBC database of Syriac literature
    # (ETCBC + the CACCHT project; github.com/ETCBC/syriac, Zenodo
    # 10.5281/zenodo.23525343, v0.92 2026-10-21): morphologically parsed
    # Classical Syriac as Text-Fabric features — Peshitta books (Gen–Deut,
    # Josh, Judg, Ps 1–30, 1–2 Kgs, Jer, Ezek, Jonah, Zech, Dan, Sirach,
    # 3–4 Esdras, the Epistle of Baruch and the Prayer of Manasseh in two
    # versions each), the Syrohexapla Psalms 1–32, the Psalms of Solomon,
    # the Book of the Laws of the Countries, Ephrem's Prose Refutation
    # against Mani and his Sermon on Nineveh and Jonah, Pseudo-Methodius,
    # and the Apocalypses of Pseudo-Ezra, Daniel and Baruch. Every word
    # carries its lexeme, English gloss, part of speech, stem/tense/person/
    # gender/number/state/voice and the realized + paradigmatic morphemes.
    # A text-fabric registrant beside `peshitta` (the same Leiden text for
    # the overlapping books, there as running text without morphology).
    #
    # == Version pin and fetch
    #
    # PINNED to tf/0.92 (the tagged v0.92 release; the repo keeps every
    # earlier version 0.1 … 0.91 beside it): the sparse GitFetch cone
    # declares tf/0.92 + README.md + LICENSE. Only Text-Fabric is served.
    #
    # == License — class nc, DELIBERATELY (verbatim, retrieved 2026-11-02)
    #
    # README "## License": "This work is licensed under a Attribution-
    # NonCommercial 4.0 International (CC BY-NC 4.0)"; LICENSE is the CC
    # BY-NC 4.0 legal code. The Zenodo record's license field says
    # cc-by-4.0 — it conflicts with the repository and is NOT followed:
    # the ETCBC directorate stated by email (2026-10-15) that all ETCBC
    # data is CC BY-NC, so the repository's own grant governs → nc.
    # The README thanks the editors of the base editions "for their
    # permission to use them" (Vetus Testamentum Syriace for the
    # Peshitta, apparatus excluded; Drijvers for the Book of the Laws of
    # the Countries; Beck's CSCO edition for Ephrem; Reinink's for
    # Pseudo-Methodius; L. L. Estes for Pseudo-Ezra).
    #
    # == Identity: document = book, passage = verse
    #
    # The corpus's own citation grain (otext sectionTypes book,chapter,
    # verse). urn:nabu:etcbc-syriac:<book name downcased verbatim —
    # genesis, 1_kings, ormana, psh, blc>; passages <doc>:<chapter>.<verse>
    # from the section features, unique per book (censused). The A/B
    # versions (EpBarA/B, OrManA/B) are sibling documents, never merged.
    # Superscriptions ride as verse 0 (OrMan 1:0) — canonical means
    # canonical. Titles come from the README's own text list (BOOKS); an
    # unknown book name is a ParseError, never a guess.
    #
    # == Text and tokens
    #
    # Verse text is otext's text-orig-full {g_cons_utf8}{trailer} over the
    # verse's OWN slot ranges, NFC at the boundary (syc is not exempt;
    # tf/0.92 ships zero non-NFC forms, the boundary stays). Nine verses
    # are discontiguous (README: Deut 14:16–17, Josh 21:34, Sir 5:6, 9:9,
    # 27:14, 28:24–25, 33:20 — "a single verse node consisting of both
    # parts, with a gap in between"): their text and tokens take only
    # their own ranges, and the ranges ride annotations "slot_ranges".
    # Tokens: "n" (the stable TF slot), "form" (g_cons_utf8), "trailer"
    # (absent on proclitics), and every other word-grain feature verbatim
    # under its upstream name (TOKEN_FEATURES — the transliteration
    # g_word/g_cons, lex, gloss, the morphology, the morpheme pairs).
    #
    # == Census (verified against otype.tf at the pin, 2026-11-02)
    #
    # 407,319 words / 31 books / 807 chapters / 18,132 verses. Expected
    # first sync: 31 documents / 18,132 passages, 0 skipped. Upstream
    # advertises no count; the 31 book nodes reconcile with the README's
    # text list exactly (18 Peshitta books, the two A/B pairs, and the
    # nine further texts).
    class EtcbcSyriac < Nabu::Adapter
      REPO_URL = "https://github.com/ETCBC/syriac"

      SPARSE_PATHS = ["tf/0.92", "README.md", "LICENSE"].freeze

      TF_DIR = File.join("tf", "0.92").freeze

      LANGUAGE = "syc"

      MANIFEST = Nabu::SourceManifest.new(
        id: "etcbc-syriac",
        name: "ETCBC Syriac Corpus — morphologically parsed Classical Syriac (Text-Fabric tf/0.92)",
        license: "CC BY-NC 4.0 (README verbatim: \"This work is licensed under a Attribution-" \
                 "NonCommercial 4.0 International (CC BY-NC 4.0)\"; LICENSE = the CC BY-NC 4.0 legal " \
                 "code; the Zenodo record's cc-by-4.0 field conflicts and is not followed — the ETCBC " \
                 "directorate, by email 2026-10-15: all ETCBC data is CC BY-NC; cite DOI " \
                 "10.5281/zenodo.23525343)",
        license_class: "nc",
        upstream_url: REPO_URL,
        parser_family: "text-fabric"
      )

      URN_PREFIX = "urn:nabu:etcbc-syriac:"

      # Every word-grain feature tf/0.92 ships beside the form and trailer.
      TOKEN_FEATURES = %w[
        g_word g_cons lex gloss sp vs vt ps gn nu st vo ls vpm
        g_lex g_emf emf g_nme nme g_pfm pfm g_pfx pfx g_vbe vbe g_vbs vbs
      ].freeze

      # The README's own text list ("## Texts"), grouped as it groups them.
      CORPORA = {
        "Peshitta" => %w[Genesis Exodus Leviticus Numbers Deuteronomy Joshua Judges Psalms 1_Kings
                         2_Kings Jeremiah Ezekiel Jonah Zechariah Daniel Sir 3Esr 4Esr
                         EpBarA EpBarB OrManA OrManB],
        "Syrohexapla" => %w[PsH],
        "Pseudepigrapha" => %w[PsS ApBar ApDn PsE PsM],
        "Syriac literature" => %w[BLC Eprx ESNJ]
      }.freeze

      # Document titles where the upstream name is a siglum (else verbatim).
      TITLES = {
        "Psalms" => "Psalms 1–30", "1_Kings" => "1 Kings", "2_Kings" => "2 Kings", "Sir" => "Sirach",
        "3Esr" => "3 Esdras", "4Esr" => "4 Esdras",
        "EpBarA" => "Epistle of Baruch (A)", "EpBarB" => "Epistle of Baruch (B)",
        "OrManA" => "Prayer of Manasseh (A)", "OrManB" => "Prayer of Manasseh (B)",
        "PsH" => "Syrohexapla Psalms 1–32", "PsS" => "Psalms of Solomon",
        "ApBar" => "Apocalypse of Baruch", "ApDn" => "Apocalypse of Daniel",
        "PsE" => "Apocalypse of Pseudo-Ezra", "PsM" => "Pseudo-Methodius",
        "BLC" => "The Book of the Laws of the Countries",
        "Eprx" => "Ephrem, Prose Refutation against Mani",
        "ESNJ" => "Ephrem, Sermon on Nineveh and Jonah"
      }.freeze

      def self.manifest
        MANIFEST
      end

      # [title, corpus] for an upstream book name; unknown → ParseError.
      def self.book_info(name)
        corpus = CORPORA.find { |_, books| books.include?(name) }&.first
        if corpus.nil?
          raise Nabu::ParseError, "etcbc-syriac: unknown book #{name.inspect} — extend CORPORA from the README"
        end

        [TITLES.fetch(name, name), corpus]
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
                   sparse: SPARSE_PATHS)
      end

      private

      def repo_url
        REPO_URL
      end

      def document_refs(workdir)
        dir = File.join(workdir, TF_DIR)
        return [] unless File.file?(File.join(dir, "otype.tf")) && File.file?(File.join(dir, "book.tf"))

        corpus(dir).books.map do |node, name|
          Nabu::DocumentRef.new(source_id: manifest.id, id: "#{URN_PREFIX}#{name.downcase}", path: dir,
                                metadata: { "book" => name, "node" => node })
        end.sort_by(&:id)
      end

      def corpus(dir)
        @corpus ||= {}
        @corpus[dir] ||= Corpus.new(Nabu::Adapters::TextFabric::Dataset.new(dir))
      end

      def build_document(corpus, urn:, book:, node:)
        title, group = self.class.book_info(book)
        verses = corpus.verses_of(node)
        raise ParseError, "#{corpus.dir}: book #{book} (node #{node}) has no verses" if verses.empty?

        document = Nabu::Document.new(urn: urn, language: LANGUAGE, title: title, canonical_path: corpus.dir,
                                      metadata: { "book" => book, "corpus" => group })
        verses.each_with_index do |verse, sequence|
          document << passage(corpus, verse, urn: "#{urn}:#{verse.chapter}.#{verse.verse}", sequence: sequence)
        end
        document
      end

      def passage(corpus, verse, urn:, sequence:)
        slots = verse.ranges.flat_map { |first, last| (first..last).to_a }
        text = slots.map { |slot| "#{corpus.value('g_cons_utf8', slot)}#{corpus.value('trailer', slot)}" }
                    .join.strip
        raise ParseError, "#{corpus.dir}: verse node #{verse.node} renders empty" if text.empty?

        annotations = { "tokens" => slots.map { |slot| token(corpus, slot) } }
        annotations["slot_ranges"] = verse.ranges if verse.ranges.size > 1
        Nabu::Passage.new(urn: urn, language: LANGUAGE, text: Nabu::Normalize.nfc(text),
                          annotations: annotations, sequence: sequence)
      end

      def token(corpus, slot)
        token = { "n" => slot }
        form = corpus.value("g_cons_utf8", slot)
        token["form"] = Nabu::Normalize.nfc(form) if form
        trailer = corpus.value("trailer", slot)
        token["trailer"] = trailer if trailer
        TOKEN_FEATURES.each do |name|
          value = corpus.value(name, slot)
          token[name] = value unless value.nil?
        end
        token
      end

      # The Syriac-corpus view over a TextFabric::Dataset.
      class Corpus
        Verse = Data.define(:node, :chapter, :verse, :ranges)

        def initialize(dataset)
          @dataset = dataset
        end

        def dir = @dataset.dir

        def books
          @books ||= begin
            first, last = type_span("book")
            @dataset.feature("book").each_pair.select { |node, _| node.between?(first, last) }.to_h
          end
        end

        def value(name, slot) = @dataset.feature(name).fetch(slot)

        # A book's verses in slot order, each with its chapter label and
        # its own (possibly discontiguous) slot ranges.
        def verses_of(book_node)
          ranges = @dataset.slot_ranges(book_node)
          return [] if ranges.nil? || ranges.empty?

          first = ranges.first.first
          last = ranges.last.last
          structure.fetch("verse").filter_map do |vranges, node|
            next unless vranges.first.first.between?(first, last)

            Verse.new(node: node, chapter: chapter_of(vranges.first.first),
                      verse: @dataset.feature("verse").fetch(node), ranges: vranges)
          end
        end

        private

        def type_span(type)
          ranges = @dataset.type_ranges.fetch(type) do
            raise Nabu::ParseError, "#{dir}: otype.tf declares no #{type.inspect} nodes"
          end
          [ranges.first.first, ranges.last.last]
        end

        def chapter_of(slot)
          list = structure.fetch("chapter")
          index = list.bsearch_index { |ranges, _node| ranges.last.last >= slot }
          hit = index && list[index]
          raise Nabu::ParseError, "#{dir}: slot #{slot} lies in no chapter" unless hit && slot >= hit[0].first.first

          @dataset.feature("chapter").fetch(hit[1])
        end

        # { "chapter" | "verse" => ascending [[ranges], node] } from one
        # pass over oslots.
        def structure
          @structure ||= begin
            spans = { "chapter" => type_span("chapter"), "verse" => type_span("verse") }
            out = { "chapter" => [], "verse" => [] }
            path = File.join(dir, "oslots.tf")
            @dataset.feature("oslots").each_pair do |node, spec|
              type = spans.find { |_, (first, last)| node.between?(first, last) }&.first
              out[type] << [TextFabric.parse_ranges(spec, path: path), node] if type
            end
            out.each_value { |list| list.sort_by! { |ranges, node| [ranges.first.first, node] } }
          end
        end
      end
    end
  end
end

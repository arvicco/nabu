# frozen_string_literal: true

require_relative "text_fabric"

module Nabu
  module Adapters
    # ETCBC SyrNT — the Syriac New Testament in Text-Fabric
    # (github.com/ETCBC/syrnt; Hannes Vlaardingerbroek and Dirk Roorda,
    # ETCBC; Zenodo 10.5281/zenodo.1464787). The source data is a SEDRA
    # database export made by George A. Kiraz and James W. Bennett —
    # "The data base version is 3.0, March 1996" (docs/about.md) — "based
    # on manuscripts from the Ancient Biblical Manuscript Center". All 27
    # books, the Peshitta NT with the five books the Peshitta canon lacks
    # (2 Peter, 2–3 John, Jude, Revelation) as SEDRA carries them. Every
    # word carries its lexeme, root and stem in Syriac script and in the
    # ETCBC and SEDRA transcriptions, its prefix/suffix, part of speech
    # and the full morphology. The fifth text-fabric registrant, the NT
    # sibling of `peshitta` (README: "we treat the Syriac New Testament
    # and the (Old Testament) Peshitta as two different corpora").
    #
    # == Version pin and fetch
    #
    # PINNED to tf/0.1 (the only released version; tf/0.1/__checkout__.txt
    # records the TF data release 0.3, g72f2ead): the sparse GitFetch cone
    # declares tf/0.1 + docs/about.md (the provenance page). Upstream is
    # unsupported (repostatus badge; last push 2023-11-14) → effectively
    # frozen.
    #
    # == Delivery grains (enumerated 2026-11-22 at master dae3eb6f)
    #
    # The repo serves: tf/0.1 (43 .tf feature files — THE document source),
    # source/0.1/all-ordered.txt (the raw SEDRA export the TF was built
    # from), plain/0.1/<Book>.txt (27 plain-text renderings, derived),
    # docs/ (feature documentation), app/, programs/ and tutorial/ (code
    # and notebooks). Only tf/0.1 and docs/about.md are fetched; every
    # other grain is out of scope by rule and never lands in canonical/.
    # Inside the cone, tf/0.1/__checkout__.txt (TF release bookkeeping, not
    # a feature) is skipped by rule in discovery_skips; any other non-.tf
    # file under tf/0.1 is UNRECOGNIZED (loud, never silent).
    #
    # == License — class nc, conservatively (read first-hand 2026-11-22)
    #
    # The repository LICENSE is the MIT License ("Copyright (c) 2019 Dirk
    # Roorda") — a SOFTWARE grant ("the Software"). The data carries no
    # explicit license: README.md and docs/about.md state only the
    # provenance ("The source data in this repo is a SEDRA database export
    # made by George A. Kiraz and James W. Bennett", database version 3.0,
    # March 1996), and the .tf headers name the encoders ("Ancient
    # Biblical Manuscript Center (transcription), George A. Kiraz and
    # James W. Bennett (database) and Hannes Vlaardingerbroek and Dirk
    # Roorda (TF)") with @source=SEDRA. SEDRA's current data release is
    # CC BY-NC 4.0 (Beth Mardutho), and the sister ETCBC corpora are
    # CC BY-NC → class nc, the peshitta/etcbc-syriac posture; credit
    # SEDRA (Kiraz and Bennett) and the ETCBC conversion.
    #
    # == Identity: document = book, passage = verse
    #
    # The corpus's own citation grain (otext sectionTypes book,chapter,
    # verse). urn:nabu:etcbc-syrnt:<book.tf name downcased verbatim —
    # matt, 1cor, james, 1peter, rev>; title = book@en with "_" as a space
    # ("1 Corinthians"). Passages <doc>:<chapter>.<verse> from the verse
    # node's own chapter/verse features; (book, chapter, verse) censused
    # unique, every verse contiguous, verse node order == slot order.
    #
    # == Text and tokens
    #
    # Verse text is otext's text-orig-full {word} plus the format's
    # trailing space, i.e. the words single-space joined (the SEDRA text
    # carries no punctuation), NFC at the boundary (zero non-NFC forms at
    # the pin; the boundary stays). Tokens: "n" (the stable TF slot),
    # "form" (word, Syriac script) and every other word-grain feature under
    # its upstream name (TOKEN_FEATURES). Declared compaction: the "NA"
    # value (upstream's not-applicable filler on vs/vt/ps/gn/nu/st and the
    # type features — 35,608 to 108,020 slots each) and the 0 of the two
    # int flags (seyame, fmhdot) are stored ABSENT; the empty prefix/suffix
    # values are absent in the format itself. The lexeme node type (3,038
    # nodes linking a lexeme to its occurrences) is not a citation grain:
    # its value rides every token as "lexeme".
    #
    # == Census (verified against the full tf/0.1 at the pin, 2026-11-22)
    #
    # 109,640 words / 27 books / 260 chapters / 7,957 verses / 3,038
    # lexemes (otype.tf). Expected first sync: 27 documents / 7,957
    # passages / 109,640 tokens, 1 file skipped by rule. Upstream
    # advertises no count; the 27 book nodes are the 27 NT books.
    class EtcbcSyrnt < Nabu::Adapter
      REPO_URL = "https://github.com/ETCBC/syrnt"

      SPARSE_PATHS = ["tf/0.1", "docs/about.md"].freeze

      TF_DIR = File.join("tf", "0.1").freeze

      CHECKOUT_FILE = File.join(TF_DIR, "__checkout__.txt").freeze

      LANGUAGE = "syc"

      URN_PREFIX = "urn:nabu:etcbc-syrnt:"

      MANIFEST = Nabu::SourceManifest.new(
        id: "etcbc-syrnt",
        name: "ETCBC SyrNT — the Syriac New Testament (SEDRA III export, Text-Fabric tf/0.1)",
        license: "Non-commercial (class nc, conservatively): the repository LICENSE is the MIT " \
                 "License (\"Copyright (c) 2019 Dirk Roorda\") — a software grant; the data carries " \
                 "no explicit license (README/docs/about.md: \"a SEDRA database export made by George A. " \
                 "Kiraz and James W. Bennett\", database version 3.0, March 1996; SEDRA's data is " \
                 "CC BY-NC 4.0 today) — read 2026-11-22. Credit SEDRA (Kiraz and Bennett), the Ancient " \
                 "Biblical Manuscript Center (transcription) and the ETCBC conversion (Vlaardingerbroek, " \
                 "Roorda); cite DOI 10.5281/zenodo.1464787",
        license_class: "nc",
        upstream_url: REPO_URL,
        parser_family: "text-fabric"
      )

      # Every word-grain feature tf/0.1 ships beside the form (word.tf).
      TOKEN_FEATURES = %w[
        word_etcbc word_sedra lexeme lexeme_etcbc lexeme_sedra root root_etcbc root_sedra
        stem stem_etcbc stem_sedra prefix prefix_etcbc prefix_sedra suffix suffix_etcbc suffix_sedra
        sp vs vt ps gn nu st ntyp nmtyp prtyp ptctyp demcat sfcontract sfgn sfnu sfps seyame fmhdot
      ].freeze

      # Upstream's not-applicable fillers, stored absent (class note).
      ABSENT_VALUES = ["NA", 0].freeze

      def self.manifest
        MANIFEST
      end

      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        document_refs(workdir).each(&block)
      end

      # The TF bookkeeping file by rule; any other non-.tf file inside the
      # pinned dataset directory is unrecognized.
      def discovery_skips(workdir)
        dir = File.join(workdir, TF_DIR)
        return DiscoverySkips.new unless File.directory?(dir)

        others = Dir.children(dir).reject { |name| name.end_with?(".tf") }.sort
        checkout, strays = others.partition { |name| name == File.basename(CHECKOUT_FILE) }
        notes = checkout.map { |name| "#{TF_DIR}/#{name}: Text-Fabric release bookkeeping, not a feature" } +
                strays.map { |name| "#{TF_DIR}/#{name}: not a .tf feature file" }
        DiscoverySkips.new(skipped_by_rule: checkout.size, unrecognized: strays.size, notes: notes)
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

      # Seam for tests (the house local-git pattern).
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
        verses = corpus.verses_of(node)
        raise ParseError, "#{corpus.dir}: book #{book} (node #{node}) has no verses" if verses.empty?

        book_en = corpus.book_en(node)
        metadata = { "book" => book }
        metadata["book_en"] = book_en if book_en
        document = Nabu::Document.new(urn: urn, language: LANGUAGE, title: (book_en || book).tr("_", " "),
                                      canonical_path: corpus.dir, metadata: metadata)
        verses.each_with_index do |verse, sequence|
          document << passage(corpus, verse, urn: "#{urn}:#{verse.chapter}.#{verse.verse}", sequence: sequence)
        end
        document
      end

      def passage(corpus, verse, urn:, sequence:)
        slots = (verse.first..verse.last).to_a
        text = slots.map { |slot| corpus.value("word", slot) }.compact.join(" ").strip
        raise ParseError, "#{corpus.dir}: verse node #{verse.node} renders empty" if text.empty?

        Nabu::Passage.new(urn: urn, language: LANGUAGE, text: Nabu::Normalize.nfc(text),
                          annotations: { "tokens" => slots.map { |slot| token(corpus, slot) } },
                          sequence: sequence)
      end

      def token(corpus, slot)
        token = { "n" => slot }
        form = corpus.value("word", slot)
        token["form"] = Nabu::Normalize.nfc(form) if form
        TOKEN_FEATURES.each do |name|
          value = corpus.value(name, slot)
          next if value.nil? || ABSENT_VALUES.include?(value)

          token[name] = value.is_a?(String) ? Nabu::Normalize.nfc(value) : value
        end
        token
      end

      # The SyrNT view over a TextFabric::Dataset.
      class Corpus
        Verse = Data.define(:node, :chapter, :verse, :first, :last)

        def initialize(dataset)
          @dataset = dataset
        end

        def dir = @dataset.dir

        # { book node => book name } in node order — book.tf also labels
        # chapter and verse nodes, so the book type's own span selects.
        def books
          @books ||= begin
            first, last = type_span("book")
            @dataset.feature("book").each_pair.select { |node, _| node.between?(first, last) }.to_h
          end
        end

        def book_en(node) = @dataset.feature("book@en").fetch(node)

        def value(name, slot) = @dataset.feature(name).fetch(slot)

        # A book's verses in slot order, each with its own section labels.
        def verses_of(book_node)
          ranges = @dataset.slot_ranges(book_node)
          return [] if ranges.nil? || ranges.empty?

          first = ranges.first.first
          last = ranges.last.last
          verse_spans.filter_map do |vfirst, vlast, node|
            next unless vfirst.between?(first, last)

            Verse.new(node: node, chapter: @dataset.feature("chapter").fetch(node),
                      verse: @dataset.feature("verse").fetch(node), first: vfirst, last: vlast)
          end
        end

        private

        def type_span(type)
          ranges = @dataset.type_ranges.fetch(type) do
            raise Nabu::ParseError, "#{dir}: otype.tf declares no #{type.inspect} nodes"
          end
          [ranges.first.first, ranges.last.last]
        end

        # Ascending [first_slot, last_slot, verse_node]; a discontiguous
        # verse is damage here (censused: none), never papered over.
        def verse_spans
          @verse_spans ||= begin
            first, last = type_span("verse")
            path = File.join(dir, "oslots.tf")
            spans = []
            @dataset.feature("oslots").each_pair do |node, spec|
              next unless node.between?(first, last)

              ranges = TextFabric.parse_ranges(spec, path: path)
              raise Nabu::ParseError, "#{path}: verse node #{node} is discontiguous (#{spec})" if ranges.size > 1

              spans << [ranges.first.first, ranges.first.last, node]
            end
            spans.sort
          end
        end
      end
    end
  end
end

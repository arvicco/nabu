# frozen_string_literal: true

require_relative "text_fabric"

module Nabu
  module Adapters
    # Hexapla — the Göttingen Hexapla Database of the Niedersächsische
    # Akademie der Wissenschaften zu Göttingen (API v3) in Text-Fabric
    # (conversion by R. Taylor, github.com/rdtaylorjr/hexapla, tf/0.1,
    # 2026-10-09): 2 Samuel and the Psalms laid out column by column —
    # the LXX edition, Field's Ο′, the MT, the Secunda (Hebrew in Greek
    # letters), Aquila, Symmachus, Origen's Septuagint, Quinta, Sexta,
    # Theodotion, "the others" (οἱ λοιποί), Notes and Field's Latin —
    # stichos by stichos, every reading with the sigla of its witnesses. A
    # text-fabric registrant; all corpus policy lives here.
    #
    # == Version pin and fetch
    #
    # PINNED to tf/0.1 (main 02bf17c3, 2026-10-10): the sparse GitFetch cone
    # declares tf/0.1 + docs/about.md + docs/transcription.md + LICENSE.
    # The repository also ships the database's raw API responses (source/,
    # one JSON per passage) — the same data in its upstream serialization,
    # outside the cone.
    #
    # == License (verified first-hand, retrieved 2026-11-02)
    #
    # Every database response carries "license": {"label": "CC BY-NC-SA
    # 4.0"} and the copyright "Die Editio critica maior des griechischen
    # Psalters. Niedersächsische Akademie der Wissenschaften zu Göttingen."
    # (checked on the live API for a 2 Samuel passage, versekey
    # 1010001001); the NAWG imprint: "Die Erschließungsdaten einschließlich
    # statistischer Auswertungen und Visualisierungen werden unter CC
    # BY-NC-SA 4.0 veröffentlicht"; the TF headers carry
    # "@license=Creative Commons Attribution-NonCommercial-ShareAlike 4.0
    # International"; docs/about.md licenses source + TF data under CC
    # BY-NC-SA 4.0 → class nc.
    #
    # == Identity: document = column × book, passage = verse
    #
    # A column is a `text` node (the ETCBC-targum model the converter
    # follows), so one document per book node inside it: urn:nabu:hexapla:
    # <column>:<book@en downcased> (aquila:psalms, lxx_edition:2_samuel).
    # Passages <doc>:<chapter>.<verse> in the database's GREEK numbering;
    # the psalm title is verse 0, a book's inscriptio chapter 0 verse 0.
    # The Notes column is SKIPPED BY RULE: editorial annotation in mixed
    # Latin and Greek ("Alia exempl."), not a witness text, and upstream
    # gives it no language code (2 books).
    #
    # == Text and tokens
    #
    # Verse text is otext's text-orig-full {text}{trailer} over the verse
    # slots — every reading of every cell in database order, as the corpus
    # renders it — NFC at the boundary except the hbo columns (MT; the
    # Secunda as hbo-Grek), which ride byte-verbatim under the hbo/arc
    # exemption. A verse whose words are all the database's "-" placeholder
    # (or empty readings) carries no text: SKIPPED BY RULE and named in
    # document metadata "omitted_verses" (Field's two columns leave
    # 1,428 verses blank). Tokens: "n", "form" (text), "trailer", "id" (the
    # database token id), "alt" (the database's alternative mark), and the
    # enclosing reading's "rank" / "reading" (absent for 0) / "siglum" /
    # "prefix", plus the stichos letter.
    #
    # == Census (verified against otype.tf at the pin, 2026-11-02)
    #
    # 182,462 words / 13 columns / 21 column books / 1,630 chapters /
    # 18,048 verses / 36,929 stichoi / 131,805 readings. Expected first
    # sync: 19 documents / 16,302 passages / 169,420 tokens (18,048 verse
    # records less the Notes column's 314 and 1,432 placeholder-only
    # verses — Field 707, Field Latin 721, four elsewhere), 2 skipped by
    # rule.
    class Hexapla < Nabu::Adapter
      REPO_URL = "https://github.com/rdtaylorjr/hexapla"

      SPARSE_PATHS = ["tf/0.1", "docs/about.md", "docs/transcription.md", "LICENSE"].freeze

      TF_DIR = File.join("tf", "0.1").freeze

      MANIFEST = Nabu::SourceManifest.new(
        id: "hexapla",
        name: "Göttingen Hexapla Database (NAWG) — 2 Samuel and the Psalms (Text-Fabric tf/0.1)",
        license: "CC BY-NC-SA 4.0 (every database response: \"license\": {\"label\": \"CC BY-NC-SA 4.0\"}, " \
                 "copyright \"Die Editio critica maior des griechischen Psalters. Niedersächsische Akademie " \
                 "der Wissenschaften zu Göttingen.\"; NAWG imprint: \"Die Erschließungsdaten … werden unter " \
                 "CC BY-NC-SA 4.0 veröffentlicht\"; TF conversion R. Taylor under the same license)",
        license_class: "nc",
        upstream_url: REPO_URL,
        parser_family: "text-fabric"
      )

      URN_PREFIX = "urn:nabu:hexapla:"

      # column (text name) => document title (transcription.md's labels).
      COLUMN_TITLES = {
        "lxx_edition" => "LXX edition", "field" => "Field (Ο′)", "mt" => "MT", "secunda" => "Secunda",
        "aquila" => "Aquila", "symmachus" => "Symmachus", "origen" => "Septuaginta (Origen)",
        "quinta" => "Quinta", "sexta" => "Sexta", "theodotion" => "Theodotion",
        "others" => "Others (οἱ λοιποί)", "field_latin" => "Field (Latin)"
      }.freeze

      # column => language. languageISO is per column upstream (heb → hbo,
      # heb-Grek → hbo-Grek); "others" carries none — its readings are
      # Greek (οἱ λοιποί), declared here.
      COLUMN_LANGUAGES = {
        "mt" => "hbo", "secunda" => "hbo-Grek", "field_latin" => "lat"
      }.tap { |map| (COLUMN_TITLES.keys - map.keys).each { |column| map[column] = "grc" } }.freeze

      # Columns skipped by rule, with the reason.
      REJECTED_COLUMNS = {
        "notes" => "editorial notes in mixed Latin and Greek, not a witness text (no languageISO upstream)"
      }.freeze

      PLACEHOLDER = "-"

      def self.manifest
        MANIFEST
      end

      # [title, language] for a column; an unknown column is a ParseError.
      def self.column_info(name)
        title = COLUMN_TITLES.fetch(name) do
          raise Nabu::ParseError,
                "hexapla: unknown column #{name.inspect} — extend COLUMN_TITLES from the transcription"
        end
        [title, COLUMN_LANGUAGES.fetch(name)]
      end

      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        document_refs(workdir).each(&block)
      end

      def discovery_skips(workdir)
        dir = File.join(workdir, TF_DIR)
        rejected = present?(dir) ? corpus(dir).column_books.select { |column, _, _| REJECTED_COLUMNS.key?(column) } : []
        Nabu::Adapter::DiscoverySkips.new(
          skipped_by_rule: rejected.size, unrecognized: 0,
          notes: rejected.map { |column, _, book| "#{column}/#{book}: #{REJECTED_COLUMNS.fetch(column)}" }
        )
      end

      def parse(document_ref)
        corpus = corpus(document_ref.path)
        meta = document_ref.metadata
        title, language = self.class.column_info(meta.fetch("column"))
        verses = corpus.verses_of(meta.fetch("node"))
        raise ParseError, "#{corpus.dir}: book node #{meta.fetch('node')} has no verses" if verses.empty?

        blank, kept = verses.partition { |verse| corpus.placeholder_only?(verse) }
        document = Nabu::Document.new(
          urn: document_ref.id, language: language,
          title: "Hexapla: #{title} — #{meta.fetch('book_en').tr('_', ' ')}", canonical_path: corpus.dir,
          metadata: document_metadata(meta, blank.map { |verse| "#{verse.chapter}.#{verse.verse}" })
        )
        kept.each_with_index do |verse, sequence|
          document << passage(corpus, verse, urn: "#{document_ref.id}:#{verse.chapter}.#{verse.verse}",
                                             language: language, sequence: sequence)
        end
        document
      end

      def fetch(workdir, progress: nil, force: false)
        git_fetch!(repo_url: repo_url, workdir: workdir, progress: progress, force: force, sparse: SPARSE_PATHS)
      end

      private

      def repo_url
        REPO_URL
      end

      def present?(dir)
        File.file?(File.join(dir, "otype.tf")) && File.file?(File.join(dir, "text.tf"))
      end

      def document_refs(workdir)
        dir = File.join(workdir, TF_DIR)
        return [] unless present?(dir)

        corpus(dir).column_books.filter_map do |column, node, book|
          next if REJECTED_COLUMNS.key?(column)

          self.class.column_info(column)
          book_en = corpus(dir).book_en(node)
          Nabu::DocumentRef.new(
            source_id: manifest.id, id: "#{URN_PREFIX}#{column}:#{book_en.downcase}", path: dir,
            metadata: { "column" => column, "node" => node, "book" => book, "book_en" => book_en }
          )
        end.sort_by(&:id)
      end

      def corpus(dir)
        @corpus ||= {}
        @corpus[dir] ||= Corpus.new(Nabu::Adapters::TextFabric::Dataset.new(dir))
      end

      def document_metadata(meta, omitted)
        { "column" => meta.fetch("column"), "book" => meta.fetch("book"), "book_en" => meta.fetch("book_en"),
          "numbering" => "Greek", "omitted_verses" => omitted.empty? ? nil : omitted }.compact
      end

      def passage(corpus, verse, urn:, language:, sequence:)
        slots = (verse.first..verse.last).to_a
        text = slots.map { |slot| "#{corpus.value('text', slot)}#{corpus.value('trailer', slot)}" }.join.strip
        text = Nabu::Normalize.nfc(text) unless Nabu::Normalize.nfc_exempt?(language)
        Nabu::Passage.new(urn: urn, language: language, text: text,
                          annotations: { "tokens" => slots.map { |slot| token(corpus, slot, language) } },
                          sequence: sequence)
      end

      def token(corpus, slot, language)
        token = { "n" => slot }
        form = corpus.value("text", slot)
        token["form"] = Nabu::Normalize.nfc_exempt?(language) ? form : Nabu::Normalize.nfc(form) if form
        trailer = corpus.value("trailer", slot)
        token["trailer"] = trailer if trailer
        %w[id alt].each do |name|
          value = corpus.value(name, slot)
          token[name] = value unless value.nil?
        end
        token.merge!(corpus.reading_of(slot))
        stichos = corpus.stichos_of(slot)
        token["stichos"] = stichos if stichos
        token
      end

      # The Hexapla-shaped view over a TextFabric::Dataset.
      class Corpus
        Verse = Data.define(:node, :chapter, :verse, :first, :last)

        def initialize(dataset)
          @dataset = dataset
        end

        def dir = @dataset.dir
        def value(name, slot) = @dataset.feature(name).fetch(slot)
        def book_en(node) = @dataset.feature("book@en").fetch(node)

        # [column, book node, book name] for every book node, in node order.
        def column_books
          @column_books ||= spans.fetch("book").sort_by(&:last).map do |first, _last, node|
            column = containing("text", first) or raise Nabu::ParseError, "#{dir}: book #{node} lies in no column"
            [@dataset.feature("text").fetch(column), node, @dataset.feature("book").fetch(node)]
          end
        end

        def verses_of(book_node)
          ranges = @dataset.slot_ranges(book_node)
          return [] if ranges.nil? || ranges.empty?

          spans.fetch("verse").filter_map do |first, last, node|
            next unless ranges.any? { |a, b| first.between?(a, b) }

            chapter = containing("chapter", first) or raise Nabu::ParseError, "#{dir}: verse #{node} has no chapter"
            Verse.new(node: node, chapter: @dataset.feature("chapter").fetch(chapter),
                      verse: @dataset.feature("verse").fetch(node), first: first, last: last)
          end
        end

        def placeholder_only?(verse)
          (verse.first..verse.last).all? { |slot| [nil, PLACEHOLDER].include?(value("text", slot)) }
        end

        # The enclosing reading's features (reading absent when 0).
        def reading_of(slot)
          group = containing("word_group", slot)
          return {} if group.nil?

          out = {}
          %w[rank siglum prefix].each do |name|
            v = @dataset.feature(name).fetch(group)
            out[name] = v unless v.nil?
          end
          reading = @dataset.feature("reading").fetch(group)
          out["reading"] = reading if reading.to_i.positive?
          out
        end

        def stichos_of(slot)
          node = containing("stichos", slot)
          node && @dataset.feature("stichos").fetch(node)
        end

        private

        # The +type+ node whose slot span holds +slot+ (spans of one type
        # never overlap in this corpus — censused), or nil.
        def containing(type, slot)
          list = spans.fetch(type)
          index = list.bsearch_index { |_first, last, _node| last >= slot }
          hit = index && list[index]
          hit && slot >= hit[0] ? hit[2] : nil
        end

        # Ascending [first, last, node] per type, from one pass over oslots.
        def spans
          @spans ||= begin
            types = %w[text book chapter verse stichos word_group]
            ranges = types.to_h { |t| [t, @dataset.type_ranges.fetch(t).then { |r| [r.first.first, r.last.last] }] }
            out = types.to_h { |t| [t, []] }
            path = File.join(dir, "oslots.tf")
            @dataset.feature("oslots").each_pair do |node, spec|
              type = ranges.find { |_, (a, b)| node.between?(a, b) }&.first or next
              parts = TextFabric.parse_ranges(spec, path: path)
              out[type] << [parts.first.first, parts.last.last, node]
            end
            out.each_value(&:sort!)
          end
        end
      end
    end
  end
end

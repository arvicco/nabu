# frozen_string_literal: true

require_relative "text_fabric"
require_relative "source_read"

module Nabu
  module Adapters
    # ETCBC extrabiblical — "Non Masoretic Texts related to the Hebrew
    # Bible" (github.com/ETCBC/extrabiblical): the ETCBC's linguistic
    # database for texts outside the Masoretic canon, as Text-Fabric
    # features — the Iron Age inscriptions (the Arad and Lachish ostraca,
    # Kuntillet ʿAjrud, the Siloam tunnel inscription, the Ketef Hinnom
    # amulets, the Mesad Hashavyahu petition), the Mesha Stele, the Deir
    # ʿAlla plaster text, three Qumran Cave 1 scrolls (1QS, 1QM, 1QHa) and
    # two rabbinic works (Pirqe Avot, Mekhilta tractate Shirata). The
    # third text-fabric registrant on the ETCBC feature vocabulary BHSA
    # uses (lex/sp/vs/vt/gn/nu/ps, the morpheme lanes, clause/phrase
    # constituency), converted from the ETCBC's MQL by Martijn Naaijer and
    # Dirk Roorda (SYNVAR project, MQL source v0.2 of 2019-01-22).
    #
    # == Version pin, fetch, and the delivery grains
    #
    # Upstream serves four grains (README census at commit 9a56288e,
    # 2026-08-10; the repo is ~9 MB and marked "unsupported" — frozen
    # since 2019):
    #   - tf/0.2 — the current Text-Fabric dataset: ACCEPTED, the pin.
    #     Document = one of its 13 book nodes.
    #   - tf/0.1 — the superseded 2017 dataset (10 book nodes; no 1QHa,
    #     Pirqe or Shirata): fetched (the cone takes tf/ whole, so a NEW
    #     version dir surfaces as drift) and SKIPPED BY RULE per book node
    #     (discovery_skips). A version dir above the pin is UNRECOGNIZED —
    #     a re-pin decision, never silently ignored or silently taken.
    #   - source/0.x/extraBiblical.mql.bz2 — the MQL exports the TF data
    #     was converted from (the same corpus in its pre-conversion form):
    #     refused at fetch (outside the sparse cone).
    #   - programs/ — the conversion notebook, its helper and images:
    #     code, refused at fetch.
    # Reconciliation: tf/0.2's otype.tf declares 13 book nodes = the 13
    # documents; tf/0.1's 10 book nodes are skipped by rule; residue 0.
    #
    # == License
    #
    # README.md, verbatim: "This dataset is licensed under a Creative
    # Commons Attribution-NonCommercial 4.0 International License (CC
    # BY-NC 4.0)." Confirmed by the ETCBC directorate (W. van Peursen), by
    # email, 2026-10-15: all ETCBC-created data — the BHSA, the
    # extrabiblical corpora and their annotations — are CC BY-NC 4.0;
    # software MIT. The repo's LICENSE file (MIT, Dirk Roorda 2019) covers
    # the conversion code only → class nc, the bhsa posture.
    #
    # == Identity and text
    #
    # urn:nabu:extrabiblical:<slug> from the FIXED BOOKS table (an unknown
    # book name is a ParseError, never a guess); passage =
    # <doc-urn>:<chapter>.<verse> from the corpus's own section features —
    # the inscription/column number and line (most ostraca are encoded as
    # ONE undivided verse: lachish:3.1 is the whole of Lachish 3). Verse
    # text is otext.tf's text-orig-full format {g_word_utf8}{g_suffix_utf8}
    # (consonantal square script with the shin/sin dots — NFC-stable as
    # shipped, censused over all 39,416 forms), trailing space stripped.
    # Empty forms are real (the elided article): the token keeps its slot
    # with no "form" key.
    #
    # == Languages (the per-book table; declared)
    #
    # language.tf says "Hebrew" for every one of the 39,862 words — the
    # ETCBC's morphology frame, kept verbatim as metadata "etcbc_language"
    # (any other value is a ParseError). The document language follows the
    # BOOKS table: hbo throughout, except the Mesha Stele, which is Moabite
    # (obm — no nabu-lects anchor yet; the lect posture is pending on it).
    # The Deir ʿAlla text's language is CONTESTED (Aramaic, Canaanite, or
    # a dialect of its own) — it rides the registry's qda local-use
    # anchor, which carries the dispute without settling it; upstream's
    # Hebrew processing claim stays as metadata. Pirqe Avot and Shirata are Rabbinic
    # Hebrew (the heb:rab stage exists; its rule waits with the pending
    # package); 1QS/1QM/1QHa stay bare hbo (the dss precedent).
    #
    # == Tokens and spans
    #
    # Tokens carry "n" (the TF slot), "form", "trailer", and every
    # word-grain scalar feature tf/0.2 ships verbatim under its upstream
    # name (TOKEN_FEATURES); the rest is DECLINED with its reason
    # (DECLINED_TOKEN_FEATURES). Clause and phrase constituents ride the
    # passage "spans" annotation in the bhsa shape (architecture §5):
    # passage-relative inclusive token-index ranges, the TF node id,
    # "partial" when clipped, every clause/phrase-grain scalar feature
    # (SPAN_FEATURES) and the "mother" dependency edge as a node id.
    #
    # == Axes (aggressive mining; nothing date- or place-shaped ships)
    #
    # The asset carries no date, findspot or genre field — but each book
    # IS a known artifact or work, so the axes are attributed per book:
    # the find-site (with its Pleiades id where the held gazetteer has
    # one) rides the "place" hash from BOOKS; the dating rides
    # config/work_eras.yml keyed on metadata "book" (MetadataDates
    # :work_era, composition class, precision era); the kind folds over
    # the same key in config/kind_map.yml. Deliberate coarseness: the
    # dating is per book, so a multi-inscription book (Arad 1, 2 and 40)
    # carries one envelope spanning its pieces.
    #
    # == Census (tf/0.2 otype.tf, 2026-10-22)
    #
    # 39,862 words / 13 books / 79 chapters / 1,800 verses / 8,908
    # clauses / 22,770 phrases (also 9,160 clause_atoms, 23,370
    # phrase_atoms, 6,429 sentences, 6,665 sentence_atoms, 15,351
    # subphrases, 1,800 half_verses — not ingested as spans).
    class Extrabiblical < Nabu::Adapter
      REPO_URL = "https://github.com/ETCBC/extrabiblical"

      # The sparse cone: every dataset version (so drift is visible) plus
      # the README carrying the data grant; the MQL source dumps and the
      # conversion programs are refused at fetch.
      SPARSE_PATHS = ["tf", "README.md"].freeze

      PINNED_VERSION = "0.2"
      TF_ROOT = "tf"
      TF_DIR = File.join(TF_ROOT, PINNED_VERSION).freeze

      MANIFEST = Nabu::SourceManifest.new(
        id: "extrabiblical",
        name: "ETCBC extrabiblical — Non-Masoretic texts related to the Hebrew Bible (Text-Fabric tf/0.2)",
        license: "CC BY-NC 4.0 (README.md verbatim: \"This dataset is licensed under a Creative Commons " \
                 "Attribution-NonCommercial 4.0 International License (CC BY-NC 4.0)\"; confirmed by the " \
                 "ETCBC directorate (W. van Peursen), by email, 2026-10-15: all ETCBC-created data CC " \
                 "BY-NC 4.0, software MIT. The repo's MIT LICENSE covers the conversion code only)",
        license_class: "nc",
        upstream_url: REPO_URL,
        parser_family: "text-fabric"
      )

      URN_PREFIX = "urn:nabu:extrabiblical:"

      # The ETCBC morphology frame: language.tf names Hebrew for every word.
      UPSTREAM_LANGUAGE = "Hebrew"

      # Upstream book name → slug (urn), title, document language, find
      # site. Places: the "ancient" name with the Pleiades id where the
      # held gazetteer carries the site (checked 2026-10-22); Tell Deir
      # ʿAlla and Mesad Hashavyahu have no entry of their own (the latter
      # lies ~1.5 km south of Yavneh-Yam, a separate site — no borrowed
      # id); the rabbinic works are compositions, not finds — no place.
      BOOKS = {
        "B_1QHa" => { slug: "1qha", title: "Hodayot (1QHa), the Thanksgiving Hymns", language: "hbo",
                      place: { "ancient" => "Qumran", "pleiades" => "688011" } },
        "B_1QM" => { slug: "1qm", title: "The War Scroll (1QM)", language: "hbo",
                     place: { "ancient" => "Qumran", "pleiades" => "688011" } },
        "B_1QS" => { slug: "1qs", title: "The Community Rule (1QS)", language: "hbo",
                     place: { "ancient" => "Qumran", "pleiades" => "688011" } },
        "Ajrud" => { slug: "ajrud", title: "Kuntillet ʿAjrud inscriptions", language: "hbo",
                     place: { "ancient" => "Kuntillet ʿAjrud", "pleiades" => "686550284" } },
        "Arad" => { slug: "arad", title: "Arad ostraca", language: "hbo",
                    place: { "ancient" => "Tel Arad", "pleiades" => "87764825" } },
        "Balaam" => { slug: "balaam", title: "The Deir ʿAlla plaster text (the Balaam inscription)",
                      language: "qda", place: { "ancient" => "Tell Deir ʿAlla" },
                      language_basis: "CONTESTED: the Deir ʿAlla dialect is read as Aramaic, as " \
                                      "Canaanite, or as a Transjordanian dialect of its own — the " \
                                      "registry's qda local-use anchor carries the dispute; the ETCBC " \
                                      "encodes the text in its Hebrew morphology and that claim rides " \
                                      "as metadata" },
        "Ketef_Hinnom" => { slug: "ketef-hinnom", title: "Ketef Hinnom silver amulets", language: "hbo",
                            place: { "ancient" => "Ketef Hinnom", "pleiades" => "252614720" } },
        "Lachish" => { slug: "lachish", title: "Lachish letters", language: "hbo",
                       place: { "ancient" => "Lachish", "pleiades" => "687951" } },
        "Mesa" => { slug: "mesa", title: "The Mesha Stele", language: "obm",
                    place: { "ancient" => "Dibon", "pleiades" => "697654" },
                    language_basis: "Moabite: the Mesha Stele's language (attributed); the ETCBC " \
                                    "encodes it in its Hebrew morphology (etcbc_language)" },
        "Mesad_Hashavyahu" => { slug: "mesad-hashavyahu",
                                title: "Mesad Hashavyahu ostracon (the reaper's petition)",
                                language: "hbo", place: { "ancient" => "Mesad Hashavyahu" } },
        "Pirqe" => { slug: "pirqe", title: "Pirqe Avot", language: "hbo", place: nil },
        "Shirata" => { slug: "shirata", title: "Mekhilta de-Rabbi Ishmael, tractate Shirata",
                       language: "hbo", place: nil },
        "Siloam" => { slug: "siloam", title: "The Siloam tunnel inscription", language: "hbo",
                      place: { "ancient" => "Jerusalem", "pleiades" => "687928" } }
      }.freeze

      # Word-grain SCALAR features riding tokens verbatim, key = upstream
      # feature name — the full word-grain census of tf/0.2 (2026-10-22).
      # Absent upstream = absent key; ints stay ints. Upstream's constant
      # "NA"/"n/a" lanes (prs*, suffix_*) ride as shipped, the bhsa stance.
      TOKEN_FEATURES = %w[
        lex lex_utf8 sp pdp vs vt gn nu ps st ls number
        g_word g_cons g_cons_utf8 g_lex g_lex_utf8 g_nme g_nme_utf8 g_pfm g_pfm_utf8
        g_uvf g_uvf_utf8 g_vbe g_vbe_utf8 g_vbs g_vbs_utf8
        nme pfm prs prs_gn prs_nu prs_ps uvf vbe vbs suffix_gender suffix_number suffix_person
      ].freeze

      # DECLARED COARSENESS — every tf/0.2 feature that does NOT ride a
      # token under its own name, with why.
      DECLINED_TOKEN_FEATURES = {
        "g_word_utf8" => "rides as \"form\" (otext text-orig-full)",
        "g_suffix_utf8" => "rides as \"trailer\" (otext text-orig-full)",
        "g_suffix" => "transliterated twin of g_suffix_utf8, whose alias already owns the key \"trailer\"",
        "language" => "\"Hebrew\" on every word (the ETCBC morphology frame) — rides once as document " \
                      "metadata etcbc_language; any other value is a ParseError",
        "lexeme_count" => "\"0\" on every word upstream — an unpopulated statistic, not a count",
        "qere" => "header-only upstream: no word carries a qere in this corpus",
        "qere_utf8" => "header-only upstream: no word carries a qere in this corpus",
        "g_prs" => "shipped as an empty @config file — no values",
        "g_prs_utf8" => "shipped as an empty @config file — no values",
        "book" => "section grain — mints the document",
        "book@en" => "book grain — rides as document metadata book_en",
        "chapter" => "section grain — mints the passage urn",
        "verse" => "section grain — mints the passage urn",
        "label" => "verse/half_verse grain (\"MESA 01,01\") — the urn already carries the citation",
        "code" => "clause_atom grain — atoms are not ingested as spans",
        "is_root" => "clause_atom grain — atoms are not ingested as spans",
        "tab" => "clause_atom grain — atoms are not ingested as spans",
        "functional_parent" => "containment EDGE — phrase-in-clause is already the spans' shared token " \
                               "ranges; atoms and sentences are not ingested as spans",
        "distributional_parent" => "atom-grain EDGE only — atoms are not ingested as spans",
        "oslots" => "structural EDGE — read for slot extents, never a token value",
        "otype" => "structural — types every node, never a token value",
        "otext" => "@config — documents the text formats (form/trailer follow text-orig-full)"
      }.freeze

      # Constituent types carried as spans, with every scalar node feature
      # tf/0.2 ships at that grain, verbatim under upstream's name
      # (censused 2026-10-22: kind/txt/domain cover all 8,908 clauses;
      # function/det all 22,770 phrases; dist/dist_unit/mother_object_type
      # only the clauses and phrases that have a mother).
      SPAN_FEATURES = {
        "clause" => %w[kind typ txt domain rela dist dist_unit mother_object_type].freeze,
        "phrase" => %w[function typ det rela dist dist_unit].freeze
      }.freeze

      # The dependency EDGE (mother.tf), single-target throughout
      # (censused), riding each span as the target's TF node id.
      SPAN_EDGE = "mother"

      SPAN_TYPE_ORDER = { "clause" => 0, "phrase" => 1 }.freeze

      VERSION_DIR = /\A\d+(?:\.\d+)*\z/

      def self.manifest
        MANIFEST
      end

      # One DocumentRef per book node of the pinned dataset, sorted by urn.
      # A workdir without the pinned dataset (pre-fetch) yields nothing.
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        document_refs(workdir).each(&block)
      end

      # The grain census: book nodes of a superseded dataset version skip by
      # rule; a version dir above the pin (or a non-version dir under tf/)
      # is unrecognized drift.
      def discovery_skips(workdir)
        skipped = []
        strays = []
        root = File.join(workdir, TF_ROOT)
        entries = Dir.exist?(root) ? Dir.children(root).sort : []
        entries.each do |name|
          next if name == PINNED_VERSION || !File.directory?(File.join(root, name))

          if superseded?(name)
            skipped.concat(superseded_books(File.join(root, name)).map do |book|
              "superseded dataset version tf/#{name} (tf/#{PINNED_VERSION} is pinned): #{book}"
            end)
          else
            strays << "unrecognized dataset dir tf/#{name} — above the tf/#{PINNED_VERSION} pin or not a " \
                      "version: a re-pin decision"
          end
        end
        Nabu::Adapter::DiscoverySkips.new(skipped_by_rule: skipped.size, unrecognized: strays.size,
                                          notes: skipped + strays)
      end

      def parse(document_ref)
        corpus = corpus(document_ref.path)
        build_document(corpus, urn: document_ref.id, book: document_ref.metadata.fetch("book"))
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

        corpus(dir).books.map do |_node, name|
          Nabu::DocumentRef.new(
            source_id: manifest.id, id: "#{URN_PREFIX}#{book!(name, dir)[:slug]}",
            path: dir, metadata: { "book" => name }
          )
        end.sort_by(&:id)
      end

      def book!(name, context)
        BOOKS.fetch(name) do
          raise ParseError, "#{context}: unknown extrabiblical book name #{name.inspect} — the table is " \
                            "fixed at the 13 tf/#{PINNED_VERSION} books; a new name is upstream drift"
        end
      end

      def superseded?(name)
        name.match?(VERSION_DIR) && Gem::Version.new(name) < Gem::Version.new(PINNED_VERSION)
      end

      # Book names of a superseded version dir, from its own otype/book —
      # one skip per book node; a dir without them is one opaque skip.
      def superseded_books(dir)
        return ["(no otype.tf/book.tf)"] unless File.file?(File.join(dir, "otype.tf")) &&
                                                File.file?(File.join(dir, "book.tf"))

        Corpus.new(Nabu::Adapters::TextFabric::Dataset.new(dir)).books.values
      end

      # One Corpus per dataset dir per adapter instance: parse calls share
      # the loaded features and the verse/constituent indexes.
      def corpus(dir)
        @corpus ||= {}
        @corpus[dir] ||= Corpus.new(Nabu::Adapters::TextFabric::Dataset.new(dir))
      end

      def build_document(corpus, urn:, book:)
        entry = book!(book, corpus.dir)
        language = entry.fetch(:language)
        verses = corpus.verses_of(book)
        raise ParseError, "#{corpus.dir}: book #{book} has no verses" if verses.empty?

        document = Nabu::Document.new(
          urn: urn, language: language, title: entry.fetch(:title), canonical_path: corpus.dir,
          metadata: metadata_for(corpus, book, entry)
        )
        verses.each_with_index do |verse_node, sequence|
          document << passage(corpus, verse_node, urn: urn, sequence: sequence, language: language)
        end
        document
      end

      def metadata_for(corpus, book, entry)
        {
          "book" => book,
          "book_en" => corpus.book_en(book),
          "dataset_version" => PINNED_VERSION,
          "etcbc_language" => UPSTREAM_LANGUAGE,
          "language_basis" => entry[:language_basis],
          "place" => entry[:place]
        }.compact
      end

      def passage(corpus, verse_node, urn:, sequence:, language:)
        slots = corpus.slots(verse_node)
        raise ParseError, "#{corpus.dir}: verse node #{verse_node} has no slots" if slots.empty?

        slots.each { |slot| corpus.check_language!(slot) }
        annotations = { "tokens" => slots.map { |slot| token(corpus, slot) } }
        spans = spans(corpus, verse_node, slots)
        annotations["spans"] = spans unless spans.empty?
        Nabu::Passage.new(
          urn: "#{urn}:#{corpus.chapter_of(verse_node)}.#{corpus.verse_of(verse_node)}",
          language: language, text: verse_text(corpus, slots, verse_node, language),
          annotations: annotations, sequence: sequence
        )
      end

      # text-orig-full: {g_word_utf8}{g_suffix_utf8} per slot, trailing
      # whitespace stripped; NFC at the boundary unless the language is
      # exempt (hbo rides verbatim).
      def verse_text(corpus, slots, verse_node, language)
        text = slots.map { |slot| "#{corpus.form(slot)}#{corpus.trailer(slot)}" }.join.rstrip
        raise ParseError, "#{corpus.dir}: verse node #{verse_node} has no text" if text.empty?

        SourceRead.nfc(text, language: language)
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
        token
      end

      # Clause/phrase constituents intersecting this verse, as
      # passage-relative token-index ranges (the bhsa span shape).
      def spans(corpus, verse_node, slots)
        index_of = slots.each_with_index.to_h
        built = corpus.constituents_of(verse_node).map { |constituent| span(constituent, index_of) }
        built.sort_by { |span| [span["ranges"].first.first, SPAN_TYPE_ORDER.fetch(span["type"]), span["node"]] }
      end

      def span(constituent, index_of)
        covered = constituent.slots.filter_map { |slot| index_of[slot] }
        span = { "type" => constituent.type, "node" => constituent.node, "ranges" => index_ranges(covered) }
        span["partial"] = true if covered.size < constituent.slots.size
        span.merge(constituent.features)
      end

      def index_ranges(indexes)
        indexes.slice_when { |a, b| b != a + 1 }.map { |run| [run.first, run.last] }
      end

      # The extrabiblical-shaped view over a TextFabric::Dataset: which
      # features ride where is this adapter's POLICY, so it lives here.
      class Corpus
        Constituent = Data.define(:node, :type, :slots, :features)

        def initialize(dataset)
          @dataset = dataset
        end

        def dir = @dataset.dir

        # { book node => upstream name } — book.tf entries within otype's
        # book range (the feature also covers chapter/verse nodes).
        def books
          @books ||= grain_entries("book", "book")
        end

        def book_en(book)
          node = books.key(book)
          node && @dataset.feature?("book@en") ? @dataset.feature("book@en").fetch(node) : nil
        end

        def verses_of(book)
          @dataset.feature("book").each_pair.filter_map { |node, name| node if name == book && verse?(node) }
        end

        def chapter_of(verse_node) = @dataset.feature("chapter").fetch(verse_node)
        def verse_of(verse_node) = @dataset.feature("verse").fetch(verse_node)

        def slots(node)
          (@dataset.slot_ranges(node) || []).flat_map { |first, last| (first..last).to_a }
        end

        def form(slot) = @dataset.feature("g_word_utf8").fetch(slot, "")
        def trailer(slot) = @dataset.feature("g_suffix_utf8").fetch(slot, "")
        def token_feature(name, slot) = @dataset.feature(name).fetch(slot)

        def check_language!(slot)
          value = @dataset.feature("language").fetch(slot)
          return if value == UPSTREAM_LANGUAGE

          raise Nabu::ParseError,
                "#{dir}: language.tf says #{value.inspect} for word #{slot} — tf/#{PINNED_VERSION} names " \
                "#{UPSTREAM_LANGUAGE} throughout, and a language is never guessed"
        end

        def constituents_of(verse_node)
          constituents_by_verse.fetch(verse_node, [])
        end

        private

        def verse?(node)
          range = type_span("verse")
          node.between?(range.first, range.last)
        end

        def type_span(type)
          ranges = @dataset.type_ranges.fetch(type) do
            raise Nabu::ParseError, "#{dir}: otype.tf declares no #{type.inspect} nodes"
          end
          [ranges.first.first, ranges.last.last]
        end

        def grain_entries(feature, type)
          span = type_span(type)
          @dataset.feature(feature).each_pair.select { |node, _v| node.between?(span.first, span.last) }.to_h
        end

        # slot => verse node, over every verse the dataset carries.
        def verse_of_slot
          @verse_of_slot ||= @dataset.feature("book").each_pair.with_object({}) do |(node, _name), map|
            next unless verse?(node)

            slots(node).each { |slot| map[slot] = node }
          end
        end

        # verse node => [Constituent] — one pass over the clause/phrase
        # entries in oslots, each assigned to every verse its slots touch.
        def constituents_by_verse
          @constituents_by_verse ||= begin
            map = Hash.new { |hash, key| hash[key] = [] }
            SPAN_FEATURES.each do |type, names|
              features = names.to_h { |name| [name, @dataset.feature(name)] }
              each_constituent(type, features) do |constituent|
                constituent.slots.filter_map { |slot| verse_of_slot[slot] }.uniq
                           .each { |verse_node| map[verse_node] << constituent }
              end
            end
            map.default = nil
            map.each_value(&:freeze)
          end
        end

        def each_constituent(type, features)
          span = type_span(type)
          @dataset.feature("oslots").each_pair do |node, spec|
            next unless node.between?(span.first, span.last)

            ranges = Nabu::Adapters::TextFabric.parse_ranges(spec, path: File.join(dir, "oslots.tf"))
            yield Constituent.new(node: node, type: type, slots: ranges.flat_map { |a, b| (a..b).to_a },
                                  features: span_features(node, features))
          end
        end

        def span_features(node, features)
          out = features.each_with_object({}) do |(name, feature), hash|
            value = feature.fetch(node)
            hash[name] = value unless value.nil?
          end
          mother = mother_of(node)
          out[SPAN_EDGE] = mother if mother
          out
        end

        # mother.tf is single-target at the pin (censused); a multi-target
        # spec is upstream drift and refuses loudly rather than truncating.
        def mother_of(node)
          edges = @dataset.feature(SPAN_EDGE)
          spec = edges.fetch(node)
          return nil if spec.nil?

          ranges = Nabu::Adapters::TextFabric.parse_ranges(spec.to_s, path: edges.path)
          return ranges.first.first if ranges.size == 1 && ranges.first.first == ranges.first.last

          raise Nabu::ParseError,
                "#{edges.path}: node #{node} has a multi-target mother #{spec.inspect} — tf/#{PINNED_VERSION} " \
                "is single-target throughout; never truncated to one"
        end
      end
    end
  end
end

# frozen_string_literal: true

require "csv"

require_relative "../file_fetch"

module Nabu
  module Adapters
    # CEIPoM (P29-1): the Corpus of the Epigraphy of the Italian Peninsula
    # in the 1st Millennium BCE — Reuben Pitts (KU Leuven), Zenodo record
    # 6475427 v1.3 (2022-04-21; concept DOI 10.5281/zenodo.4759134). The
    # pre-Roman-Italy corpus: Latin (incl. Faliscan), the Sabellic languages
    # (Oscan, Umbrian, South Picene/Old Sabellic), Messapic, Venetic and a
    # little epigraphic Greek — 3,875 texts / 5,303 sentences / 37,041
    # dependency-annotated tokens with a curated analysis layer.
    #
    # == Shape and grain (censused whole, 2026-07-18)
    #
    # Five relational CSVs: texts.csv (one row per text: reference, name,
    # language/variety/family, script, signed-year dates, provenance +
    # WGS84), sentences.csv (Sentence_ID globally unique; Sentence_position
    # 1-based per text; Section names the Iguvine tablets), tokens.csv
    # (Relation SBJ/OBJ/PRED… + Head pointers), analysis.csv (lemma ID,
    # morphology, POS, English meaning, Classical Latin equivalent),
    # links.csv (3,630 Trismegistos ids). Document = the TEXT
    # (urn:nabu:ceipom:<Text_ID>), passage = the SENTENCE
    # (<doc-urn>:<Sentence_ID>), sequence = Sentence_position order.
    # 4 texts carry no sentence row at all (793/2911/3102/3184) — nothing
    # citable, skipped by rule and censused in discovery_skips.
    #
    # == THE ENCODING FIRST: UTF-16LE + BOM flat CSV
    #
    # Every upstream CSV is UTF-16LE with a BOM (FF FE), CRLF rows — a
    # first for the flat-CSV family. Decoded at the boundary
    # (BOM|UTF-16LE → UTF-8, then Normalize.nfc; 519 sentences carry
    # decomposed combining marks that compose here). The fixture preserves
    # the BOM byte-verbatim and the test pins it.
    #
    # == Language mapping (closed census set; varieties verbatim)
    #
    #   Latin → lat        (variety Faliscan → xfa; the 35 mixed
    #                       "Faliscan / Latin" texts STAY lat — a mixed
    #                       variety is not pure Faliscan)
    #   Oscan → osc        (incl. Paelignian/Marrucinian varieties)
    #   Messapic → cms · Venetic → xve
    #   Umbrian → xum      (incl. the 7 Volscian-variety texts — the corpus
    #                       files them under Umbrian; variety rides verbatim)
    #   Old Sabellic → spx (South Picene + Old Samnite varieties — spx is
    #                       the ISO code for the South Picene/"Old Sabellic"
    #                       group the corpus uses)
    #   Greek → grc
    #
    # An unmapped language value raises ParseError (loud quarantine): the
    # set was censused complete, so a new value means upstream changed.
    #
    # == THE LEMMA REALITY (deviation from the packet brief, censused)
    #
    # analysis.csv `Lemma` is an OPAQUE LEMMA ID ("12444a"; 33,442 of
    # 36,874 analyses carry one), not a citation form — the corpus's lemma
    # dictionary is not part of the deposit. The indexer's contract says a
    # lemma is a dictionary form in the passage's language, so NO "lemma"
    # key is minted (zero passage_lemmas rows, honest) and the ID rides
    # verbatim as "lemma_id". The bridge candidate is
    # `Classical_Latin_equivalent` (32,415 analyses / 3,952 distinct Latin
    # citation forms — measured 2026-07-18 against the live catalog's gold
    # Latin lemma keys: 1,440/3,897 distinct folded keys = 37.0%, 79.9%
    # token-weighted; misses are dominated by onomastics) — wiring it into
    # the lemma index is journaled as v2, an owner call (it would put Latin
    # lemma keys on non-Latin passages).
    #
    # == Annotations (lean; only present keys; "-" is the corpus null)
    #
    #   passage: {"section" => "Table 1a (native Umbrian alphabet)"} when
    #            the corpus sections the text (the Iguvine tablets),
    #            {"tokens" => [{"form","clean"(only when differing),
    #             "relation","head"(integer; 0 = root),
    #             "lemma_id","lemma_simplex","language","morphological_type",
    #             "pos","pos_code","tags","stem","tense","mood","diathesis",
    #             "person","number","gender","case","category","meaning",
    #             "meaning_category","meaning_subcategory","latin_equivalent",
    #             "latin_form","tam","standard_aligned","form_aligned",
    #             "alternatives" (the 12 censused multi-analysis tokens)}…]}
    #
    # `Lemma_frequency` (a derived corpus statistic) and `Analysis_ID`
    # (joins nothing in the deposit) are deliberately not ingested.
    #
    # == Reference edges + timeline + facets
    #
    # links.csv Trismegistos ids ride as metadata "related" ["tm:256173"]
    # → kind=reference edges via the shared reference_producer seam
    # (producer "ceipom", the riig `rig:` compact-key precedent). EDCS/CIL/
    # Imagines Italicae reference strings ride verbatim as metadata
    # "reference". Dates (signed-year floats, e.g. "-675.0") and WGS84
    # coordinates ride verbatim in metadata; Store::TimelineBuilder::CeipomDates
    # re-reads texts.csv for the timeline (3,872/3,875 dated,
    # 3,815 placed — the residues counted honestly). The per-text Script
    # column mints the `script` facet (8 censused single values slugged;
    # any "/"-mixed value → "mixed"; empty → no facet, verbatim metadata
    # always).
    #
    # == License / fetch / freshness
    #
    # Zenodo license field cc-by-sa-4.0 → attribution, with the SA
    # share-alike rider recorded in docs/02-sources.md. Fetch = five
    # FileFetch single-file syncs (one subdir per CSV — FileFetch is
    # one-file-per-dir), the wiktionary-recon two-phase choreography: all
    # prepare, the breaker sees the combined doomed set, all complete.
    # 16.8 MB total. Zenodo versions are immutable (a new version = a NEW
    # record id) → sync_policy: frozen.
    class Ceipom < Nabu::Adapter
      RECORD_URL = "https://zenodo.org/records/6475427"

      MANIFEST = Nabu::SourceManifest.new(
        id: "ceipom",
        name: "CEIPoM — Corpus of the Epigraphy of the Italian Peninsula in the 1st Millennium BCE " \
              "(Pitts, KU Leuven; Zenodo v1.3)",
        license: "CC BY-SA 4.0 (Zenodo record 6475427 license field cc-by-sa-4.0; share-alike rider " \
                 "recorded — cite: Reuben Pitts, CEIPoM v1.3, Zenodo (2022), doi:10.5281/zenodo.6475427)",
        license_class: "attribution",
        upstream_url: RECORD_URL,
        parser_family: "ceipom-csv"
      )

      URN_PREFIX = "urn:nabu:ceipom:"

      # One CSV per subdir (FileFetch one-file-per-dir); iteration order is
      # fetch/probe order.
      FILES = {
        "texts" => { subdir: "texts", url: "#{RECORD_URL}/files/texts.csv?download=1" }.freeze,
        "sentences" => { subdir: "sentences", url: "#{RECORD_URL}/files/sentences.csv?download=1" }.freeze,
        "tokens" => { subdir: "tokens", url: "#{RECORD_URL}/files/tokens.csv?download=1" }.freeze,
        "analysis" => { subdir: "analysis", url: "#{RECORD_URL}/files/analysis.csv?download=1" }.freeze,
        "links" => { subdir: "links", url: "#{RECORD_URL}/files/links.csv?download=1" }.freeze
      }.freeze

      # The corpus's language → ISO 639-3 mapping (class note; censused
      # complete 2026-07-18) and the one variety override.
      LANGUAGES = {
        "Latin" => "lat", "Oscan" => "osc", "Messapic" => "cms", "Venetic" => "xve",
        "Umbrian" => "xum", "Old Sabellic" => "spx", "Greek" => "grc"
      }.freeze
      VARIETY_LANGUAGES = { "Faliscan" => "xfa" }.freeze

      # The censused single-script vocabulary → facet slugs; a "/"-carrying
      # value facets as "mixed" (raw verbatim); empty mints no facet.
      SCRIPT_FACETS = {
        "Latin" => "latin", "Oscan" => "oscan", "Messapic" => "messapic",
        "Venetic" => "venetic", "Greek" => "greek", "Etruscan" => "etruscan",
        "South Picene" => "south-picene", "Nocera" => "nocera"
      }.freeze

      # The corpus-wide null.
      NULL = "-"

      # The per-workdir index over the five decoded CSVs (private cache
      # shape, see #corpus).
      Corpus = Data.define(:texts, :sentences, :tokens, :analyses, :links)

      # Analysis columns copied (lean, "-"-skipping) onto the token
      # annotation under their snake_case keys.
      ANALYSIS_FIELDS = {
        "Lemma" => "lemma_id",
        "Lemma_simplex" => "lemma_simplex",
        "Language" => "language",
        "Morphological_type" => "morphological_type",
        "Part_of_speech" => "pos",
        "POS_code" => "pos_code",
        "Tags" => "tags",
        "Stem" => "stem",
        "Tense" => "tense",
        "Mood" => "mood",
        "Diathesis" => "diathesis",
        "Person" => "person",
        "Number" => "number",
        "Gender" => "gender",
        "Case" => "case",
        "Category" => "category",
        "Meaning" => "meaning",
        "Meaning_category" => "meaning_category",
        "Meaning_subcategory" => "meaning_subcategory",
        "Classical_Latin_equivalent" => "latin_equivalent",
        "Classical_Latin_form" => "latin_form",
        "TAM_analysis" => "tam",
        "Standard_aligned" => "standard_aligned",
        "Form_aligned" => "form_aligned"
      }.freeze

      def self.manifest
        MANIFEST
      end

      # One HEAD per download URL against its subdir's FileFetch state.
      # metadata_url nil: Zenodo's record API serves the license, but the
      # deposit is frozen — drift is a new record id, not changed bytes.
      def self.remote_probe_strategy = :http_zip

      def self.http_probe_targets
        FILES.map do |name, file|
          Nabu::Adapter::HttpProbeTarget.new(
            label: "#{name}.csv", zip_url: file.fetch(:url), metadata_url: nil,
            state_subdir: file.fetch(:subdir), state_file: Nabu::FileFetch::STATE_FILE
          )
        end
      end

      # The Trismegistos concordance edges (class note).
      def self.reference_edges? = true

      def self.reference_producer(catalog:, journal:)
        LibraryReferences.new(catalog: catalog, journal: journal, producer: "ceipom")
      end

      def initialize
        super
        @cache = nil
      end

      # One DocumentRef per text with at least one sentence, urn-sorted. A
      # workdir without the CSVs yields nothing (the day-one pre-fetch
      # state).
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        corpus = corpus(workdir) or return
        corpus.texts.filter_map do |text_id, _row|
          next unless corpus.sentences.key?(text_id)

          Nabu::DocumentRef.new(
            source_id: MANIFEST.id, id: "#{URN_PREFIX}#{text_id}",
            path: File.join(File.expand_path(workdir), FILES.fetch("texts").fetch(:subdir), "texts.csv"),
            metadata: { "text_id" => text_id }
          )
        end.sort_by(&:id).each(&block)
      end

      # Sentence-less texts (4 censused corpus-wide) have nothing citable —
      # an explicit, benign skip.
      def discovery_skips(workdir)
        corpus = corpus(workdir) or return DiscoverySkips.new

        skipped = corpus.texts.count { |text_id, _row| !corpus.sentences.key?(text_id) }
        DiscoverySkips.new(skipped_by_rule: skipped)
      end

      def parse(document_ref)
        workdir = File.dirname(document_ref.path, 2)
        corpus = corpus(workdir) or
          raise ParseError, "#{document_ref.path}: CEIPoM CSVs not found for #{document_ref.id}"
        text_id = document_ref.metadata.fetch("text_id")
        row = corpus.texts[text_id] or
          raise ParseError, "#{document_ref.path}: text #{text_id.inspect} not found"
        build_document(document_ref, corpus, text_id, row)
      rescue Nabu::ValidationError => e
        raise ParseError, "#{document_ref.id}: #{e.message}"
      end

      # Five FileFetch single-file syncs, two-phase (the wiktionary-recon
      # choreography): all prepare with the live tree untouched, the
      # mass-deletion breaker sees the combined doomed set, then all
      # complete.
      def fetch(workdir, progress: nil, force: false)
        fetches = file_fetches(workdir, progress)
        fetches.each_value(&:prepare!)
        guard_mass_deletion!(workdir, fetches.values.flat_map(&:doomed_paths), force: force)
        fetches.each_value(&:complete!)
        Nabu::FetchReport.new(sha: fetches.values.last.sha, fetched_at: Time.now,
                              notes: fetch_notes(fetches))
      rescue FileFetch::Error => e
        raise Nabu::FetchError, "ceipom fetch failed into #{workdir}: #{e.message}"
      end

      private

      def file_fetches(workdir, progress)
        FILES.each_with_object({}) do |(name, file), fetches|
          fetches[name] = Nabu::FileFetch.new(
            url: file.fetch(:url), dir: File.join(workdir, file.fetch(:subdir)),
            filename: "#{name}.csv",
            attic_dir: File.join(workdir, ATTIC_DIRNAME, file.fetch(:subdir)),
            progress: progress
          )
        end
      end

      def fetch_notes(fetches)
        shas = fetches.map { |name, fetch| "#{name}.csv #{fetch.sha[0, 8]}" }
        [shas.join(" · "), attic_notes(fetches.values.flat_map(&:atticked))].compact.join("; ")
      end

      # -- the per-workdir corpus index (one decode pass over the five CSVs) --

      # Parsed and indexed once per workdir, cached for the last workdir
      # read (refs sort by urn, so a sequential parse pass decodes the five
      # files once, not once per text). nil when the texts/sentences CSVs
      # are absent (the day-one pre-fetch state).
      def corpus(workdir)
        expanded = File.expand_path(workdir)
        return @cache[1] if @cache && @cache[0] == expanded

        texts_path = csv_path(expanded, "texts")
        sentences_path = csv_path(expanded, "sentences")
        return nil unless File.file?(texts_path) && File.file?(sentences_path)

        corpus = build_corpus(expanded, texts_path, sentences_path)
        @cache = [expanded, corpus]
        corpus
      end

      def csv_path(workdir, name)
        File.join(workdir, FILES.fetch(name).fetch(:subdir), "#{name}.csv")
      end

      def build_corpus(workdir, texts_path, sentences_path)
        texts = {}
        each_row(texts_path) { |row| texts[row["Text_ID"].to_s] = row }
        sentences = Hash.new { |hash, key| hash[key] = [] }
        each_row(sentences_path) { |row| sentences[row["Text_ID"].to_s] << row }
        sentences.each_value { |rows| rows.sort_by! { |row| row["Sentence_position"].to_i } }
        sentences.default = nil
        Corpus.new(texts: texts, sentences: sentences,
                   tokens: tokens_by_sentence(workdir), analyses: analyses_by_token(workdir),
                   links: links_by_text(workdir))
      end

      def tokens_by_sentence(workdir)
        tokens = Hash.new { |hash, key| hash[key] = [] }
        each_row_if_present(csv_path(workdir, "tokens")) { |row| tokens[row["Sentence_ID"].to_s] << row }
        tokens.each_value { |rows| rows.sort_by! { |row| row["Token_position"].to_i } }
        tokens.default = nil
        tokens
      end

      def analyses_by_token(workdir)
        analyses = Hash.new { |hash, key| hash[key] = [] }
        each_row_if_present(csv_path(workdir, "analysis")) { |row| analyses[row["Token_ID"].to_s] << row }
        analyses.default = nil
        analyses
      end

      def links_by_text(workdir)
        links = Hash.new { |hash, key| hash[key] = [] }
        each_row_if_present(csv_path(workdir, "links")) do |row|
          links[row["Text_ID"].to_s] << row["Trismegistos_ID"].to_s
        end
        links.default = nil
        links
      end

      # The boundary decode: BOM|UTF-16LE → UTF-8 (the censused upstream
      # encoding — the BOM is consumed, never stored). Malformed bytes or
      # CSV raise ParseError.
      def each_row(path, &)
        CSV.foreach(path, headers: true, encoding: "BOM|UTF-16LE:UTF-8", &)
      rescue CSV::MalformedCSVError, ::EncodingError => e
        raise ParseError, "#{path}: malformed CEIPoM CSV: #{e.message}"
      end

      def each_row_if_present(path, &)
        return unless File.file?(path)

        each_row(path, &)
      end

      # -- the document ------------------------------------------------------

      def build_document(document_ref, corpus, text_id, row)
        document = Nabu::Document.new(
          urn: document_ref.id, language: language_of(row), title: presence(row["Name"]),
          canonical_path: document_ref.path,
          metadata: document_metadata(corpus, text_id, row)
        )
        corpus.sentences.fetch(text_id, []).each_with_index do |sentence, sequence|
          document << build_passage(document, corpus, sentence, sequence)
        end
        raise ParseError, "#{document_ref.id}: no sentences for text #{text_id.inspect}" if document.empty?

        document
      end

      def build_passage(document, corpus, sentence, sequence)
        annotations = {}
        section = presence(sentence["Section"])
        annotations["section"] = section if section
        tokens = passage_tokens(corpus, sentence["Sentence_ID"].to_s)
        annotations["tokens"] = tokens unless tokens.empty?
        Nabu::Passage.new(
          urn: "#{document.urn}:#{sentence['Sentence_ID']}", language: document.language,
          text: Normalize.nfc(sentence["Sentence"].to_s), sequence: sequence,
          annotations: annotations
        )
      end

      # The mapped language code (class note): the variety override first,
      # then the language column; anything else is loud.
      def language_of(row)
        variety = row["Language_variety"].to_s
        code = VARIETY_LANGUAGES[variety] || LANGUAGES[row["Language"].to_s]
        return code if code

        raise ParseError,
              "text #{row['Text_ID'].inspect}: unmapped language #{row['Language'].inspect} " \
              "(variety #{variety.inspect}) — the censused set was complete, upstream changed"
      end

      # Verbatim text metadata + the script facet + the Trismegistos
      # related targets. Dates/coordinates ride verbatim as upstream spells
      # them (signed-year floats, WGS84) — the timeline extractor re-reads
      # canonical, the EDH coordinates decision keeps them out of the timeline.
      def document_metadata(corpus, text_id, row)
        metadata = {
          "text_id" => text_id,
          "reference" => presence(row["Reference"]),
          "name" => presence(row["Name"]),
          "language" => presence(row["Language"]),
          "language_variety" => presence(row["Language_variety"]),
          "language_family" => presence(row["Language_family"]),
          "script" => presence(row["Script"]),
          "date_after" => presence(row["Date_after"]),
          "date_before" => presence(row["Date_before"]),
          "provenance" => presence(row["Provenance"]),
          "geo_id" => presence(row["GeoID"]),
          "latitude" => presence(row["Latitude"]),
          "longitude" => presence(row["Longitude"]),
          "finite_verb" => presence(row["Finite_verb"]),
          "analysable_token" => presence(row["Analysable_token"]),
          "text_length" => presence(row["Text_length"])
        }
        facet = script_facet(row["Script"].to_s)
        metadata["facets"] = { "script" => facet } if facet
        tm_ids = corpus.links.fetch(text_id, [])
        metadata["related"] = tm_ids.map { |id| "tm:#{id}" } unless tm_ids.empty?
        metadata.compact
      end

      def script_facet(script)
        value =
          if script.include?("/")
            "mixed"
          else
            SCRIPT_FACETS[script]
          end
        return nil unless value

        { "value" => value, "raw" => Normalize.nfc(script) }
      end

      # -- tokens ------------------------------------------------------------

      def passage_tokens(corpus, sentence_id)
        corpus.tokens.fetch(sentence_id, []).map do |row|
          token = {}
          token["form"] = Normalize.nfc(row["Token"].to_s)
          clean = presence(row["Token_clean"])
          token["clean"] = clean if clean && clean != token["form"]
          relation = presence(row["Relation"])
          token["relation"] = relation if relation
          head = head_of(row["Head"])
          token["head"] = head if head
          merge_analysis(token, corpus.analyses.fetch(row["Token_ID"].to_s, []))
          token
        end
      end

      # Head arrives as a float string ("165254.0"; "0.0" = the root
      # pointer, kept as 0).
      def head_of(raw)
        raw = raw.to_s.strip
        return nil if raw.empty?

        raw.to_f.to_i
      end

      # The first analysis flattens onto the token; the censused 12
      # multi-analysis tokens keep the rest under "alternatives".
      def merge_analysis(token, analyses)
        return if analyses.empty?

        token.merge!(analysis_fields(analyses.first))
        return if analyses.size == 1

        token["alternatives"] = analyses.drop(1).map { |row| analysis_fields(row) }
      end

      def analysis_fields(row)
        ANALYSIS_FIELDS.each_with_object({}) do |(column, key), fields|
          value = presence(row[column])
          fields[key] = value if value
        end
      end

      # NFC presence: nil for empty and for the corpus's "-" null.
      def presence(value)
        value = value.to_s.strip
        return nil if value.empty? || value == NULL

        Normalize.nfc(value)
      end
    end
  end
end

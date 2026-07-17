# frozen_string_literal: true

module Nabu
  module Adapters
    # CorPH — Corpus PalaeoHibernicum (P25-0): 78 Early Irish texts of the
    # 7th–10th centuries (Annals of Ulster, Vita Columbae, Blathmac, the
    # Milan/St Gall/Würzburg gloss corpora, Armagh, law, poetry, computus),
    # deep-annotated by the ERC ChronHib project (Maynooth). It absorbed the
    # earlier standalone Milan and St Gall digital editions. THE FIRST CELTIC
    # SOURCE — and the first sga GOLD lemmas in the catalog.
    #
    # == Canonical artifact: one MySQL dump, pinned
    #
    # Bulk access is the full dump `chronhibdev_2020.sql` (39,102,512 bytes)
    # in the project website repo github.com/chronhib-MU/Chronhib-Website,
    # fetched via the ordinary GitFetch path. The repo is dormant (last
    # commit 2021-05-11); the sync is PINNED to that commit: fetch verifies
    # the merged HEAD against PINNED_SHA and STOPS loudly on drift (an
    # upstream that moves is an owner review + re-pin decision, never a
    # silent content/license change). GitFetch's ref pinning is branch/tag
    # only, so the pin is verified after the fetch rather than passed to it.
    #
    # == License (verbatim, and the CODECS trap)
    #
    # The repo LICENSE is "MIT License / Copyright (c) 2020 [Chronologicon
    # Hibernicum]" and covers the repo including the dump → class
    # `attribution`. The CorPH site itself publishes no license; the CC
    # BY-SA 3.0 footer on CODECS (the *other* Celtic portal) is CODECS's
    # own and must never be cited for CorPH.
    #
    # == Shape: six tables → documents, passages, gold tokens
    #
    # TEXT (78 rows) → one document per row, urn:nabu:corph:<Text_ID>
    # (FROZEN minting; titles render upstream underscores as spaces).
    # SENTENCES → one passage per text unit, urn <doc>:<Text_Unit_ID>, text =
    # Textual_Unit VERBATIM (NFC only — multi-line computus tables keep their
    # CRLFs), ordered by Sort_ID (ID tiebreak); loci, the English
    # translation, the glossed Latin context (Latin_Text) and the upstream
    # notes ride in the annotations. MORPHOLOGY → the per-word gold layer as
    # token annotations in the P7-5 "tokens"/"lemma"/"form" contract (the
    # ORACC cf precedent, so passage_lemmas lights up with no new plumbing):
    # form/expected morph, the citation-form lemma (upstream homonym indices
    # "macc 1" split into lemma "macc" + "homonym" so lemma search hits the
    # headword), analysis, the mutation columns, verbal feature flags,
    # Onomastic_*/Problematic_Form/Var_Status verbatim. LEMMATA joins each
    # token's lemma to its language and its DIL_Headword dil.ie ids (carried
    # per token as "dil" — the eDIL bridge Nabu::CorphDilReferences journals
    # after every load). BIBLIOGRAPHY resolves the TEXT rows' edition
    # abbreviations into full references (document metadata).
    #
    # == Language honesty (censused on the full dump, 2026-07-17)
    #
    # The corpus code-mixes: 80.5% of joined tokens are Early Irish, 12.4%
    # Latin, plus Old English/Old Norse/Greek and honestly-unmappable rarities
    # (Pictish, British…). Language therefore lives at THREE grains: each
    # token carries its LEMMATA language ("lang" = mapped ISO code, or
    # "lang_source" verbatim when no honest code exists); each PASSAGE takes
    # the majority over its tokens (the grain the gold lemma index keys on —
    # a pure Old Irish gloss inside a Latin computus stays sga, a pure Latin
    # annal stays lat); each document the majority over all its tokens
    # (71 sga + 4 lat documents on the full dump). Sentences with no voting
    # tokens fall back to the document majority, and a document with none at
    # all to DEFAULT_LANGUAGE.
    #
    # == Honest residues
    #
    # Two TEXT rows (0067/0068) have no sentences — catalog-only skeletons,
    # skipped by rule (DocumentSkipped), never quarantined. One SENTENCES row
    # has an empty Textual_Unit and one carries a Text_ID ("6") matching no
    # TEXT row — both skipped by rule and counted by discovery_skips.
    class Corph < Nabu::Adapter
      REPO_URL = "https://github.com/chronhib-MU/Chronhib-Website"

      # The dormant repo's HEAD (2021-05-11 "new build"), verified at fixture
      # time 2026-07-17. Drift from this sha aborts the sync (class note).
      PINNED_SHA = "e7ef75d5f9a6ea97210f028b7389fa9539fbe8c0"

      DUMP_FILENAME = "chronhibdev_2020.sql"

      URN_PREFIX = "urn:nabu:corph:"

      # Upstream LEMMATA.Lang values with an honest ISO 639 code. Anything
      # else (Pictish, British, mixtures, blank) stays verbatim in the
      # token's "lang_source" — never a guessed code.
      LANGUAGE_CODES = {
        "Early Irish" => "sga",
        "Latin" => "lat",
        "Old English" => "ang",
        "Old Norse" => "non",
        "Greek" => "grc"
      }.freeze

      # The corpus language of record — the fallback when a document has no
      # language-voting tokens at all.
      DEFAULT_LANGUAGE = "sga"

      # MORPHOLOGY column → token annotation key, copied verbatim when
      # non-empty (lemma/language/dil are derived separately).
      TOKEN_FIELDS = {
        "Expected_Morph" => "expected",
        "Analysis" => "analysis",
        "Augm" => "augm",
        "Rel" => "rel",
        "Trans" => "trans",
        "Depend" => "depend",
        "Depon" => "depon",
        "Contr" => "contr",
        "Hiat" => "hiat",
        "Mut" => "mut",
        "Causing_Mut" => "causing_mut",
        "Hybrid_form" => "hybrid_form",
        "Problematic_Form" => "problematic",
        "Onomastic_Complex" => "onomastic_complex",
        "Onomastic_Usage" => "onomastic_usage",
        "Var_Status" => "var_status"
      }.freeze

      # SENTENCES column → passage annotation key (verbatim when non-empty).
      SENTENCE_FIELDS = {
        "Translation" => "translation",
        "Latin_Text" => "latin_text",
        "Translation_From_Latin" => "translation_from_latin",
        "Textual_Notes" => "textual_notes",
        "Translation_Notes" => "translation_notes"
      }.freeze

      # TEXT column → document metadata key (verbatim when non-empty).
      METADATA_FIELDS = {
        "Date" => "date",
        "Dating_Criteria" => "dating_criteria",
        "Edition" => "edition",
        "MSS" => "mss",
        "Digital_MSS" => "digital_mss",
        "Contributor" => "contributor"
      }.freeze

      # An upstream citation-form lemma with a homonym index: "macc 1",
      # "com- 2". Split so lemma search matches the headword.
      HOMONYM = /\A(.+?)\s+(\d+)\z/

      DIL_ID = %r{dil\.ie/(\d+)}

      MANIFEST = Nabu::SourceManifest.new(
        id: "corph",
        name: "CorPH — Corpus PalaeoHibernicum (ChronHib, Maynooth)",
        license: "MIT License / Copyright (c) 2020 [Chronologicon Hibernicum] (repo LICENSE, covers the dump)",
        license_class: "attribution",
        upstream_url: REPO_URL,
        parser_family: "corph-sql"
      )

      def self.manifest
        MANIFEST
      end

      # The DIL_Headword ids are journaled as kind=reference edges into
      # eDIL's stable id space after every load (P25-0) — producer corph,
      # Nabu::CorphDilReferences, via the shared reference_producer seam.
      def self.reference_edges? = true

      def self.reference_producer(catalog:, journal:)
        CorphDilReferences.new(catalog: catalog, journal: journal)
      end

      # +repo_url+/+pinned_sha+ exist for the tests (local upstream repos);
      # real syncs keep the constants. No-arg construction stays the
      # registry contract.
      def initialize(repo_url: REPO_URL, pinned_sha: PINNED_SHA)
        super()
        @repo_url = repo_url
        @pinned_sha = pinned_sha
        @corpus = {}
      end

      # Ordinary GitFetch (attic + breaker), then the pin gate: a HEAD other
      # than the pinned commit aborts the sync loudly (class note).
      def fetch(workdir, progress: nil, force: false)
        report = git_fetch!(repo_url: @repo_url, workdir: workdir, progress: progress, force: force)
        return report if report.sha == @pinned_sha

        raise Nabu::FetchError,
              "corph: upstream #{@repo_url} is at #{report.sha[0, 12]}, but the source is pinned to " \
              "#{@pinned_sha[0, 12]} — review the new commit (license + dump) and re-pin (owner decision)"
      end

      # One DocumentRef per TEXT row of the dump, sorted by urn. A workdir
      # without the dump (never fetched) yields nothing.
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        dump = File.join(workdir, DUMP_FILENAME)
        return unless File.file?(dump)

        refs = CorphSqlParser.new(dump).each_row("TEXT").map do |row|
          text_id = row.fetch("Text_ID").to_s
          Nabu::DocumentRef.new(
            source_id: MANIFEST.id,
            id: "#{URN_PREFIX}#{text_id}",
            path: File.expand_path(dump),
            metadata: { "text_id" => text_id, "title" => title_of(row) }
          )
        end
        refs.sort_by(&:id).each(&block)
      end

      # The sentence-grain skips parse applies silently (class note): rows
      # with an empty Textual_Unit, and rows whose Text_ID matches no TEXT
      # row. One cheap extra scan per sync, never in the load loop.
      def discovery_skips(workdir)
        dump = File.join(workdir, DUMP_FILENAME)
        return Nabu::Adapter::DiscoverySkips.new unless File.file?(dump)

        parser = CorphSqlParser.new(dump)
        text_ids = parser.each_row("TEXT").to_set { |row| row.fetch("Text_ID").to_s }
        skipped = parser.each_row("SENTENCES").count do |row|
          blank?(row["Textual_Unit"]) || !text_ids.include?(row.fetch("Text_ID").to_s)
        end
        Nabu::Adapter::DiscoverySkips.new(skipped_by_rule: skipped)
      end

      def parse(document_ref)
        corpus = corpus_for(document_ref.path)
        text_id = document_ref.id.delete_prefix(URN_PREFIX)
        row = corpus.texts[text_id]
        raise Nabu::ParseError, "#{document_ref.path}: no TEXT row for #{document_ref.id}" if row.nil?

        build_document(corpus, row, urn: document_ref.id, path: document_ref.path)
      rescue ValidationError => e
        raise Nabu::ParseError, "#{document_ref.path}: #{e.message}"
      end

      private

      def title_of(row)
        title = row.fetch("Title").to_s.tr("_", " ").strip
        title.empty? ? nil : Normalize.nfc(title)
      end

      def blank?(value)
        value.to_s.strip.empty?
      end

      # -- corpus loading (one streaming pass per table, memoized per dump) --

      Corpus = Data.define(:texts, :sentences, :tokens, :lemmata, :bibliography)
      private_constant :Corpus

      def corpus_for(path)
        @corpus[path] ||= load_corpus(path)
      end

      def load_corpus(path)
        parser = CorphSqlParser.new(path)
        Corpus.new(
          texts: parser.each_row("TEXT").to_h { |row| [row.fetch("Text_ID").to_s, row] },
          sentences: rows_by(parser, "SENTENCES", "Text_ID"),
          tokens: rows_by(parser, "MORPHOLOGY", "Text_Unit_ID"),
          lemmata: parser.each_row("LEMMATA").with_object({}) do |row, map|
            map[row.fetch("Lemma").to_s] ||= row
          end,
          bibliography: parser.each_row("BIBLIOGRAPHY").to_a
        )
      end

      def rows_by(parser, table, key)
        parser.each_row(table).with_object({}) do |row, map|
          (map[row.fetch(key).to_s] ||= []) << row
        end
      end

      # -- document building --------------------------------------------------

      def build_document(corpus, text_row, urn:, path:)
        text_id = text_row.fetch("Text_ID").to_s
        sentences = ordered(corpus.sentences[text_id] || []).reject { |row| blank?(row["Textual_Unit"]) }
        if sentences.empty?
          raise DocumentSkipped.new("#{urn}: TEXT row without sentences (catalog-only skeleton)",
                                    reason: "no sentences (metadata-only text row)")
        end

        units = sentences.map { |row| [row, unit_tokens(corpus, row)] }
        document_language = majority_language(units.flat_map(&:last)) || DEFAULT_LANGUAGE
        document = Document.new(
          urn: urn, language: document_language, title: title_of(text_row),
          canonical_path: path, metadata: document_metadata(corpus, text_row)
        )
        units.each_with_index do |(row, tokens), sequence|
          document << passage(row, tokens, urn: urn, sequence: sequence, fallback: document_language)
        end
        document
      end

      def passage(row, tokens, urn:, sequence:, fallback:)
        Passage.new(
          urn: "#{urn}:#{row.fetch('Text_Unit_ID')}",
          language: majority_language(tokens) || fallback,
          text: Normalize.nfc(row.fetch("Textual_Unit").to_s),
          annotations: passage_annotations(row, tokens),
          sequence: sequence
        )
      end

      def ordered(rows)
        rows.sort_by { |row| [row["Sort_ID"] ? 0 : 1, row["Sort_ID"] || 0, row["ID"] || 0] }
      end

      def unit_tokens(corpus, sentence_row)
        rows = corpus.tokens[sentence_row.fetch("Text_Unit_ID").to_s] || []
        ordered(rows).map { |row| token(row, corpus.lemmata) }
      end

      def passage_annotations(row, tokens)
        annotations = { "tokens" => tokens }
        locus = %w[Locus1 Locus2 Locus3].map { |key| row[key].to_s }.reject(&:empty?)
        annotations["locus"] = locus.map { |value| Normalize.nfc(value) } unless locus.empty?
        SENTENCE_FIELDS.each do |column, key|
          annotations[key] = Normalize.nfc(row[column].to_s) unless blank?(row[column])
        end
        annotations
      end

      # One MORPHOLOGY row → the P7-5 token contract, plus the LEMMATA join
      # (language + dil.ie ids). Only non-empty keys.
      def token(row, lemmata)
        token = {}
        token["form"] = Normalize.nfc(row["Morph"].to_s) unless blank?(row["Morph"])
        apply_lemma(token, row["Lemma"].to_s)
        TOKEN_FIELDS.each do |column, key|
          token[key] = Normalize.nfc(row[column].to_s) unless blank?(row[column])
        end
        apply_lemmata_join(token, lemmata[row["Lemma"].to_s])
        token
      end

      def apply_lemma(token, raw)
        return if raw.strip.empty?

        if (m = HOMONYM.match(raw))
          token["lemma"] = Normalize.nfc(m[1])
          token["homonym"] = m[2]
        else
          token["lemma"] = Normalize.nfc(raw)
        end
      end

      def apply_lemmata_join(token, lemma_row)
        return if lemma_row.nil?

        source = lemma_row["Lang"].to_s.strip
        unless source.empty?
          code = LANGUAGE_CODES[source]
          code ? token["lang"] = code : token["lang_source"] = Normalize.nfc(source)
        end
        dil = lemma_row["DIL_Headword"].to_s.scan(DIL_ID).flatten.uniq
        token["dil"] = dil unless dil.empty?
      end

      # Majority mapped language over the tokens' "lang" values (insertion
      # order breaks ties — deterministic), or nil when nothing votes.
      def majority_language(tokens)
        votes = tokens.filter_map { |token| token["lang"] }
        return nil if votes.empty?

        votes.tally.max_by { |_code, count| count }.first
      end

      # -- document metadata ---------------------------------------------------

      # TEXT row prose verbatim (non-empty fields only), plus the edition
      # abbreviations resolved against BIBLIOGRAPHY into full references.
      def document_metadata(corpus, text_row)
        metadata = { "text_id" => text_row.fetch("Text_ID").to_s }
        METADATA_FIELDS.each do |column, key|
          metadata[key] = Normalize.nfc(text_row[column].to_s) unless blank?(text_row[column])
        end
        references = resolve_references(corpus.bibliography, text_row)
        metadata["references"] = references unless references.empty?
        metadata
      end

      def resolve_references(bibliography, text_row)
        cited = "#{text_row['Edition']}\n#{text_row['Reference']}"
        bibliography.filter_map do |row|
          abbreviation = row["Abbreviation"].to_s.strip
          next nil if abbreviation.empty? || !cited.include?(abbreviation)

          Normalize.nfc(row["Reference"].to_s)
        end
      end
    end
  end
end

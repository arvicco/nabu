# frozen_string_literal: true

require_relative "../normalize"
require_relative "catalog_join"
require_relative "search"

module Nabu
  module Query
    # Passage-anchored intertext: "who quotes THIS passage? where does this line
    # echo?" (P15-1, docs/intertext-design.md §1). Not to be confused with
    # Query::Parallel (the translation-column hub) — this is the classicist's
    # quotation/allusion finder, query-time over the SAME FTS index Search and
    # Proximity use, with NO new n-gram schema (the design's measured verdict:
    # per-gram phrase probes answer 1–111 ms/passage on the live 3.76M-passage
    # index, so Phase 15 ships a query surface, not a materialized gram table).
    #
    # == The engine (design §1 option (b): query-time per-gram FTS phrase probes)
    #
    # Fold the anchor passage to its stored search form (already minted at the
    # adapter boundary — text_normalized), emit its word 4-grams, and run each as
    # a quoted FTS5 phrase MATCH against the index. A passage that shares a gram
    # is a candidate; score candidates by shared-gram count WEIGHTED BY RARITY
    # (1/document-frequency — the df is the probe's own hit count, free), so a
    # rare shared phrase (a real quotation) outscores a pile of common function-
    # word grams. Measured on the live index: Odyssey 1.1 → Polybius 12.27.10
    # quoting the proem (top hit); John 1:1 → the Fathers' reception; Matthew 4:4
    # → Luke 4:4 and, once elision marks are folded, LXX Deuteronomy 8:3.
    #
    # == Rider (i): elision folding at gram-build (the measured edition gap)
    #
    # The elision apostrophe splits editions: SBLGNT writes it U+02BC (MODIFIER
    # LETTER APOSTROPHE — a LETTER to unicode61, so "επʼ" indexes as ONE token
    # "επʼ") while First1KGreek/Swete writes U+2019 (punctuation — "επ’" indexes
    # as the bare token "επ"). A surface gram built from an SBLGNT anchor
    # therefore misses its U+2019 twin until the apostrophe is stripped at
    # gram-build time — measured, without the strip LXX Deut 8:3 shares only 3
    # grams with Matthew 4:4; with it, 9 (tying canonical Matthew). We strip
    # every elision apostrophe (both encodings + ASCII/oxia relatives) here, in
    # the gram builder — the cheapest fix, local to this query. (Folding U+02BC
    # in text_normalized itself is the deeper fix but re-mints shas — a fable
    # decision, not this packet's; design §1 rider i.)
    #
    # == Rider (ii): duplicate witnesses → group to document grain
    #
    # The corpus deliberately holds texts more than once (PROIEL greek-nt ≡ UD
    # greek-proiel; multi-edition works). Every probe's top ranks fill with them,
    # so candidates GROUP BY document: one hit per document, its best-scoring
    # passage the representative, sibling loci counted (`loci`). Cross-source
    # identical texts stay TWO hits (they are two documents; we hold no
    # cross-source work identity) — stated honestly, not hidden.
    #
    # == The exclusion set, argued
    #
    # Only the anchor's OWN document is excluded. Everything else the design's
    # "trivially expected" worry names is handled by the surface-gram mechanic
    # itself: a translation (or any other-language witness) shares no folded
    # tokens with the anchor's language, so it self-excludes — no rule needed.
    # Same-work SAME-language editions (a second Greek Matthew) are NOT excluded:
    # they are exactly the corroborating parallels the design wants surfaced (its
    # Matt 4:4 probe measures LXX Deut 8:3 "tying canonical Matthew", i.e. a
    # different Greek edition of the anchor's own work is a wanted hit).
    #
    # == Second signal (design §1 option (c)): rare-lemma co-occurrence
    #
    # Surface grams catch verbatim quotation; re-inflected or reordered allusion
    # slips them. For the gold-lemmatized slice (10.3% of the corpus), a
    # Tesserae-style pass rides along: take the anchor's folded lemmas, keep the
    # RARE ones (global df below a cap), and find passages sharing ≥2 of them,
    # rarity-weighted the same way. It fires only when the anchor carries gold
    # lemmas (else the anchor-lemma lookup returns empty and we skip in one
    # query); its speed depends on the passage_lemmas(urn) index this packet
    # adds (Indexer#create_lemma_table). Rendered as a separate "lemma echoes"
    # section so the two signals never masquerade as one.
    class Parallels
      include CatalogJoin

      # The gram size the design measured (4-grams: Odyssey 8 tokens → 5 grams,
      # John 17 → 14, Thucydides 120 → 117 — all n−4+1).
      GRAM_SIZE = 4

      # A gram in ≥ this many passages is not distinctive evidence (its rank
      # weight would be ≤ 1/COMMON_GRAM_DF ≈ 0) AND enumerating its hits would be
      # wasteful — so we cap the probe here and drop the gram from scoring. Pure
      # cost/relevance bound: a real quotation's grams are far rarer than this.
      COMMON_GRAM_DF = 500

      # Join+dedupe this many top-scored candidate passages to fill the page
      # (enough that document-grain grouping still yields `limit` documents).
      CANDIDATE_FACTOR = 30
      MIN_CANDIDATES = 300

      # Elision apostrophes stripped at gram-build (rider i): U+02BC modifier
      # letter (SBLGNT), U+2019/U+2018 quotes and ASCII ' (First1K/Swete/others),
      # U+02B9 prime, plus the Greek oxia/psili spacing accents (U+0384 U+1FBD
      # U+1FBF) that ride the same apostrophe slot in some editions.
      ELISION = /[ʼʹ‘’'΄᾽᾿]/

      # A rarity cap on the lemma-co-occurrence signal: a lemma attested in more
      # than this many passages is too common to diagnose an echo (and bounds the
      # IN-list probe). Content words in the live corpus sit well under it.
      RARE_LEMMA_DF = 2_000

      # One intertext hit, grouped to document grain. `score` is the summed
      # rarity weight; `shared_gram_count` the distinct anchor grams matched;
      # `loci` how many passages of this document matched (the representative is
      # the best-scoring one); `evidence` the shared phrase spans (folded, marks
      # stripped — they mark WHAT matched, like Search's snippet).
      Hit = Data.define(
        :urn, :language, :document_title, :license_class,
        :score, :shared_gram_count, :loci, :evidence
      )

      # One lemma-echo hit (second signal). `shared_lemmas` are the rare lemma
      # dictionary forms the anchor and this passage share.
      LemmaEcho = Data.define(
        :urn, :language, :document_title, :license_class, :score, :shared_lemmas
      )

      # anchor_urn/anchor_title identify the passage; gram_count is how many
      # grams it yielded; hits is the surface-gram parallels; lemma_echoes the
      # second signal (empty unless the anchor is gold-lemmatized).
      Result = Data.define(:anchor_urn, :anchor_title, :gram_count, :hits, :lemma_echoes)

      def initialize(catalog:, fulltext:)
        @catalog = catalog
        @fulltext = fulltext
      end

      # Parallels for the passage at +urn+. Returns a Result, or nil when the urn
      # resolves to no live passage (the caller distinguishes "unknown urn" from
      # "no parallels found"). +lang+/+license+ filter candidates catalog-side
      # exactly as Search does. +limit+ caps each signal's hit list.
      def run(urn, limit: 15, lang: nil, license: nil)
        anchor = load_anchor(urn)
        return nil if anchor.nil?

        tokens = gram_tokens(anchor.fetch(:text_normalized))
        grams = shingle(tokens)
        scores, matched = probe_grams(grams, anchor_passage_id: anchor.fetch(:passage_id))
        hits = assemble(scores, matched,
                        tokens: tokens, anchor_document_id: anchor.fetch(:document_id),
                        lang: lang, license: license, limit: limit)
        echoes = lemma_echoes(anchor, lang: lang, license: license, limit: limit)
        Result.new(anchor_urn: anchor.fetch(:urn), anchor_title: anchor.fetch(:title),
                   gram_count: grams.size, hits: hits, lemma_echoes: echoes)
      end

      private

      # The anchor row from the CATALOG (urn is uniquely indexed there, so this
      # is one B-tree hit — no scan of the UNINDEXED urn column in the FTS table).
      def load_anchor(urn)
        @catalog[:passages]
          .join(:documents, id: Sequel[:passages][:document_id])
          .where(Sequel[:passages][:urn] => urn, Sequel[:passages][:withdrawn] => false)
          .select(
            Sequel[:passages][:id].as(:passage_id),
            Sequel[:passages][:urn].as(:urn),
            Sequel[:passages][:document_id].as(:document_id),
            Sequel[:passages][:text_normalized].as(:text_normalized),
            Sequel[:documents][:title].as(:title)
          ).first
      end

      # Anchor tokens for gramming: strip elision apostrophes (rider i), then
      # take maximal letter/number runs — reproducing unicode61's tokenization
      # (punctuation is a separator) so a phrase built here re-tokenizes, and
      # matches the index, identically.
      def gram_tokens(text_normalized)
        text_normalized.gsub(ELISION, "").scan(/[\p{L}\p{N}]+/)
      end

      def shingle(tokens)
        return [] if tokens.size < GRAM_SIZE

        (0..(tokens.size - GRAM_SIZE)).map { |i| tokens[i, GRAM_SIZE] }
      end

      # Probe each distinct gram once; accumulate rarity-weighted score and the
      # matched gram indices per candidate passage. Returns [scores, matched]
      # where scores[pid] is Σ 1/df and matched[pid] the anchor gram indices it
      # hit (for the evidence-span reconstruction).
      def probe_grams(grams, anchor_passage_id:)
        scores = Hash.new(0.0)
        matched = Hash.new { |hash, key| hash[key] = [] }
        gram_index = index_grams(grams)

        gram_index.each do |gram, indices|
          rows = fts_probe(gram)
          df = rows.size
          next if df.zero? || df >= COMMON_GRAM_DF

          weight = 1.0 / df
          rows.each do |row|
            pid = row.fetch(:passage_id)
            next if pid == anchor_passage_id

            scores[pid] += weight * indices.size
            matched[pid].concat(indices)
          end
        end
        [scores, matched]
      end

      # Distinct grams → the anchor positions each occupies (a gram can recur in
      # the anchor; every position counts toward the span reconstruction and the
      # weight, so a repeated shared phrase is stronger evidence).
      def index_grams(grams)
        positions = {}
        grams.each_with_index { |gram, position| (positions[gram] ||= []) << position }
        positions
      end

      def fts_probe(gram)
        @fulltext[Store::Indexer::TABLE]
          .where(Sequel.lit("passages_fts MATCH ?", phrase(gram)))
          .select(:passage_id)
          .limit(COMMON_GRAM_DF)
          .all
      end

      # An FTS5 phrase: the folded gram tokens space-joined and double-quoted,
      # embedded quotes doubled (the Proximity#phrase discipline).
      def phrase(tokens)
        %("#{tokens.join(' ').gsub('"', '""')}")
      end

      # Group scored candidates to document grain, exclude the anchor's own
      # document, rank by score, and reconstruct evidence spans for the page.
      def assemble(scores, matched, tokens:, anchor_document_id:, lang:, license:, limit:)
        return [] if scores.empty?

        cap = [limit * CANDIDATE_FACTOR, MIN_CANDIDATES].max
        top_ids = scores.keys.sort_by { |id| -scores[id] }.first(cap)
        rows = candidate_rows(top_ids, lang: lang, license: license)
               .reject { |row| row.fetch(:document_id) == anchor_document_id }

        rows.group_by { |row| row.fetch(:document_id) }
            .map { |_doc, doc_rows| document_hit(doc_rows, scores, matched, tokens) }
            .sort_by { |hit| [-hit.score, hit.urn] }
            .first(limit)
      end

      def document_hit(doc_rows, scores, matched, tokens)
        best = doc_rows.max_by { |row| scores[row.fetch(:passage_id)] }
        indices = matched[best.fetch(:passage_id)].uniq.sort
        Hit.new(
          urn: best.fetch(:urn), language: best.fetch(:language),
          document_title: best.fetch(:document_title), license_class: best.fetch(:license_class),
          score: scores[best.fetch(:passage_id)].round(4),
          shared_gram_count: indices.size, loci: doc_rows.size,
          evidence: evidence_spans(indices, tokens)
        )
      end

      # Merge consecutive matched gram indices back into contiguous anchor token
      # spans — so the evidence reads as the shared PHRASE ("ανδρα μοι εννεπε
      # μουσα πολυτροπον"), not a bag of overlapping 4-grams.
      def evidence_spans(indices, tokens)
        indices.slice_when { |a, b| b != a + 1 }.map do |run|
          tokens[run.first..(run.last + GRAM_SIZE - 1)].join(" ")
        end
      end

      # Candidate passages with the document id/title/license needed for grouping
      # and display, through the shared visibility+filter join (CatalogJoin).
      def candidate_rows(passage_ids, lang:, license:)
        visible_passages(lang: lang, license: license)
          .where(Sequel[:passages][:id] => passage_ids)
          .select(
            Sequel[:passages][:id].as(:passage_id),
            Sequel[:passages][:urn],
            Sequel[:passages][:language],
            Sequel[:documents][:id].as(:document_id),
            Sequel[:documents][:title].as(:document_title),
            license_expr.as(:license_class)
          ).all
      end

      # -- second signal: rare-lemma co-occurrence -----------------------------

      # Passages sharing ≥2 of the anchor's RARE gold lemmas, rarity-weighted.
      # Empty (one cheap query) unless the anchor carries gold lemmas.
      def lemma_echoes(anchor, lang:, license:, limit:)
        rare = rare_anchor_lemmas(anchor.fetch(:urn))
        return [] if rare.size < 2

        weights = rare.transform_values { |df| 1.0 / df }
        rows = @fulltext[Store::Indexer::LEMMA_TABLE]
               .where(lemma_folded: rare.keys)
               .exclude(urn: anchor.fetch(:urn))
               .select(:passage_id, :lemma_folded, :lemma_raw)
               .all
        assemble_echoes(rows, weights, anchor: anchor, lang: lang, license: license, limit: limit)
      end

      # The anchor's folded lemmas mapped to their global df, keeping only the
      # rare ones (2 ≤ df ≤ RARE_LEMMA_DF): df==1 co-occurs with nothing, common
      # lemmas do not diagnose an echo and would balloon the IN-list probe.
      def rare_anchor_lemmas(urn)
        folded = @fulltext[Store::Indexer::LEMMA_TABLE].where(urn: urn).distinct.select_map(:lemma_folded)
        folded.each_with_object({}) do |lemma, acc|
          df = @fulltext[Store::Indexer::LEMMA_TABLE].where(lemma_folded: lemma).count
          acc[lemma] = df if df.between?(2, RARE_LEMMA_DF)
        end
      end

      def assemble_echoes(rows, weights, anchor:, lang:, license:, limit:)
        shared = Hash.new { |hash, key| hash[key] = {} }
        rows.each do |row|
          shared[row.fetch(:passage_id)][row.fetch(:lemma_folded)] = row.fetch(:lemma_raw)
        end
        candidates = shared.select { |_pid, lemmas| lemmas.size >= 2 }
        return [] if candidates.empty?

        rank_echoes(candidates, weights, anchor: anchor, lang: lang, license: license, limit: limit)
      end

      def rank_echoes(candidates, weights, anchor:, lang:, license:, limit:)
        rows = candidate_rows(candidates.keys, lang: lang, license: license)
               .reject { |row| row.fetch(:document_id) == anchor.fetch(:document_id) }
        rows.group_by { |row| row.fetch(:document_id) }
            .map { |_doc, doc_rows| echo_hit(doc_rows, candidates, weights) }
            .sort_by { |echo| [-echo.score, echo.urn] }
            .first(limit)
      end

      def echo_hit(doc_rows, candidates, weights)
        best = doc_rows.max_by { |row| candidates[row.fetch(:passage_id)].sum { |folded, _| weights[folded] } }
        lemmas = candidates[best.fetch(:passage_id)]
        LemmaEcho.new(
          urn: best.fetch(:urn), language: best.fetch(:language),
          document_title: best.fetch(:document_title), license_class: best.fetch(:license_class),
          score: lemmas.sum { |folded, _| weights[folded] }.round(4),
          shared_lemmas: lemmas.values.sort
        )
      end
    end
  end
end

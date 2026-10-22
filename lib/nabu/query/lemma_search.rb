# frozen_string_literal: true

require "json"

require_relative "../lemma_keys"
require_relative "../normalize"
require_relative "../store/indexer"
require_relative "catalog_join"
require_relative "define"
require_relative "morph_facets"

module Nabu
  module Query
    # Lemma search (P7-5): exact-lemma lookup over the gold-treebank lemma
    # index (Store::Indexer::LEMMA_TABLE in fulltext.sqlite3), then the shared
    # catalog join for the pristine text, language, and license filtering.
    # `bin/nabu search --lemma λέγω` finds every inflected attestation —
    # λέγουσι, εἶπας, εἰπεῖν — because the match is on the annotation's
    # dictionary form, not the surface text.
    #
    # == Folding: the same both-sides contract as full-text search
    #
    # The index carries lemma_folded = Normalize.search_form(lemma, language)
    # — a lemma is a dictionary form in its passage's language, so it folds
    # exactly like text (grc final-sigma λόγος → λογοσ, lat v→u/j→i). The
    # query carries NO language, so it matches the Normalize.query_forms
    # UNION, the P6-4 argument verbatim: the variant set always contains
    # extra_L(generic(query)), so a lemma spelled the way the treebank spells
    # it folds, on that variant, exactly the way the index folded it; and the
    # variants are a plain IN-list, so the generic variant still matches
    # languages with no extra rule.
    #
    # == Ranking
    #
    # There is none: an exact-lemma hit has no bm25-style relevance. Hits come
    # back in PASSAGE order (catalog passage id — load order, which keeps a
    # loaded document's passages together) — deterministic, and answerable from
    # the lemma table alone, which stores no urn (Store::Indexer class note).
    # A v1 table, which still stores the urn, keeps its urn order until the
    # next full rebuild narrows it.
    class LemmaSearch
      include CatalogJoin

      # One hit. `lemma` is the index's raw upstream spelling (the dictionary
      # form as the treebank wrote it); `surface_forms` the distinct pristine
      # inflected forms attesting it in this passage (", "-joined); `text` the
      # pristine passage text for display; `gloss` (P11-4) the short dictionary
      # shelf gloss for the lemma in this passage's language, nil when no
      # dictionary of that language holds it — honest absence; `morph` (P13-6)
      # the decoded morphology evidence of the matching token(s) when a
      # `--morph` filter narrowed the hit, nil otherwise — so every morph hit
      # SHOWS why it matched; `tier` (P26-0) the hit's lemma tier ("gold" |
      # "silver") — renderers label silver hits so an automatic lemmatization
      # is never mistakable for a verified one.
      Result = Data.define(:urn, :language, :lemma, :surface_forms, :text,
                           :document_title, :license_class, :gloss, :morph, :tier) do
        def initialize(gloss: nil, morph: nil, tier: Store::Indexer::GOLD_TIER, **rest) = super
      end

      # Pull more index hits than the caller's limit so that catalog-side
      # filtering (language/license/withdrawn) can drop rows and still fill
      # the page (same factor as Search). Exhaustion is ANNOUNCED (P35-6)
      # via incomplete_hint, as in Search.
      # P96 audit re-stamp (mechanisms verified scale-safe at 106.9M).
      # census: 106877441, 2026-09-04, live passages (P57 full rebuild; 3.76M at tuning,
      # re-affirmed at 24.4M and 68.4M — exhaustion stays ANNOUNCED, class note)
      INNER_LIMIT_FACTOR = 10

      def initialize(catalog:, fulltext:)
        @catalog = catalog
        @fulltext = fulltext
      end

      # Search +lemma+ and return up to +limit+ Result values in passage order.
      # +lang+ / +license+ filter catalog-side exactly as in Search. +urn+
      # restricts the match to one passage — the ranking-independent golden
      # replay probe (health), not a pagination knob. +morph+ (P13-6), when
      # present, is a `case=dat,number=pl` facet string that further restricts
      # each hit to passages attesting the lemma with a token bearing that
      # morphology (see #run_with_morph); it REQUIRES the lemma anchor — bare
      # morph search is deliberately out of scope (it would scan every
      # annotated passage, not a lemma-narrowed handful). +gold_only+ (P26-0)
      # drops the silver (automatic-lemmatization) rows at the index — the
      # pre-tier gold-treebanks-only scope; on a pre-tier index it is a no-op
      # (every row IS gold there). +loans+ (P34-2) narrows to passages whose
      # stored annotations carry that loan-origin code — the loans corpus is
      # gold-lemmatized (cop, P17-1), so unlike the document facets this
      # filter deliberately composes with the lemma anchor.
      def run(lemma, lang: nil, license: nil, limit: 20, urn: nil, morph: nil, source: nil,
              sources: nil, gold_only: false, loans: nil)
        @incomplete_hint = nil
        variants = Nabu::Normalize.query_forms(lemma.to_s)
        return [] if variants.first.strip.empty? # generic form first; extras never add characters

        facets = morph.to_s.strip.empty? ? nil : MorphFacets.parse(morph)
        if facets
          # The morph path pulls the WHOLE candidate set (no inner window —
          # see #run_with_morph), so its pages are always complete.
          return run_with_morph(variants, facets, lang: lang, license: license, limit: limit,
                                                  urn: urn, source: source, sources: sources,
                                                  gold_only: gold_only, loans: loans)
        end

        inner_limit = limit * INNER_LIMIT_FACTOR
        hits = lemma_hits(variants, inner_limit: inner_limit, urn: urn, gold_only: gold_only,
                                    lang: lang)
        return [] if hits.empty?

        ordered_ids = hits.map { |row| row.fetch(:passage_id) }
        rows = catalog_rows(ordered_ids, lang: lang, license: license, source: source, sources: sources,
                                         loans: loans)
               .to_h { |row| [row.fetch(:passage_id), row] }
        by_id = hits.to_h { |row| [row.fetch(:passage_id), row] }

        page = ordered_ids.filter_map { |id| rows[id] }.first(limit)
        note_page_completeness(
          window_exhausted: hits.size >= inner_limit,
          filters_active: [lang, license, source, loans].compact.any? || Array(sources).any?,
          page_size: page.size, limit: limit
        )
        results = page.map { |row| build_result(row, by_id.fetch(row.fetch(:passage_id))) }
        attach_glosses(results)
      end

      private

      # The `--morph` path (P13-6). The lemma index is a fold-both-sides
      # EQUALITY index; morphology is NOT indexed (measured verdict: a facet
      # index would multiply the 1.9M lemma rows and needs a rebuild, while the
      # lemma anchor already narrows the search to the passages attesting the
      # lemma — even the pathological article ὁ post-filters sub-second, and a
      # real content-word query in tens of ms; conventions §6.1). So:
      #
      #   1. take EVERY candidate passage attesting the folded lemma (all of
      #      them, in passage order — NOT the inner-limit slice: morph is far more
      #      selective than license, so truncating before filtering would
      #      silently drop pages),
      #   2. load their stored annotations and, per passage, keep the tokens
      #      whose morphology satisfies the facets AND whose folded lemma is in
      #      the query variant set (the same membership the index encodes),
      #   3. a passage with ≥1 such token is a hit — its surface_forms and morph
      #      evidence restricted to the MATCHING tokens (not the whole lemma's
      #      attestations), then the ordinary catalog page-fill and glossing.
      def run_with_morph(variants, facets, lang:, license:, limit:, urn:, source: nil, sources: nil,
                         gold_only: false, loans: nil)
        passage_ids, tiers = candidate_passages(variants, urn: urn, gold_only: gold_only)
        return [] if passage_ids.empty?

        variant_set = variants.to_set
        rows = annotated_catalog_rows(passage_ids, lang: lang, license: license, source: source,
                                                   sources: sources, loans: loans)
               .to_h { |row| [row.fetch(:passage_id), row] }
        results = passage_ids.filter_map do |id|
          row = rows[id] and morph_hit(row, variant_set, facets, tier: tiers[id])
        end
        attach_glosses(results.first(limit))
      end

      # [passage ids, { passage_id => tier }] for every distinct passage
      # attesting the folded lemma, in passage order. Unlike #lemma_hits this
      # pulls the WHOLE candidate set (morph filtering happens after) — the
      # lemma anchor bounds it to that lemma's attestations.
      def candidate_passages(variants, urn:, gold_only:)
        dataset = passage_scoped(@fulltext[Store::Indexer::LEMMA_TABLE].where(lemma_folded: variants), urn)
        dataset = dataset.where(tier: Store::Indexer::GOLD_TIER) if gold_only && tier_column?
        columns = tier_column? ? %i[passage_id tier] : %i[passage_id]
        tiers = {}
        ids = dataset.order(order_key).select(*columns).all.map do |row|
          id = row.fetch(:passage_id)
          tiers[id] ||= row[:tier] || Store::Indexer::GOLD_TIER
          id
        end
        [ids.uniq, tiers]
      end

      # Narrow +dataset+ to the one passage +urn+ names (nil = no narrowing),
      # through the live shape's passage key: the catalog resolves the urn
      # to its id on the narrow table (an unknown urn → no rows); a v1 table
      # still filters its stored urn.
      def passage_scoped(dataset, urn)
        return dataset unless urn
        return dataset.where(urn: urn) if order_key == :urn

        dataset.where(passage_id: @catalog[:passages].where(urn: urn).select_map(:id))
      end

      # The hit order (class note): passage id, or the stored urn on a v1
      # table (its pre-narrowing order, unchanged until the rebuild).
      def order_key
        @order_key ||= Store::Indexer.lemma_passage_key(@fulltext)
      end

      # Pre-tier fulltext tolerance (P26-0): an index built before the tier
      # column serves every row as gold — which is what those rows are.
      def tier_column?
        return @tier_column unless @tier_column.nil?

        @tier_column = @fulltext[Store::Indexer::LEMMA_TABLE].columns.include?(:tier)
      end

      # Catalog rows for the candidate passages, carrying annotations_json for
      # the morph post-filter alongside the usual display/visibility columns,
      # plus the source slug: the façade's scoped decoders and the per-source
      # lemma keys (LemmaKeys — bhsa/dss read their own lexeme fields) both
      # key on it.
      def annotated_catalog_rows(passage_ids, lang:, license:, source: nil, sources: nil, loans: nil)
        visible_passages(lang: lang, license: license, source: source, sources: sources, loans: loans)
          .where(Sequel[:passages][:id] => passage_ids)
          .select(*catalog_columns, Sequel[:passages][:annotations_json].as(:annotations_json),
                  Sequel[:sources][:slug].as(:source_slug))
          .all
      end

      # A morph hit for one candidate passage, or nil. Keeps the tokens whose
      # morphology matches the facets and whose folded lemma is in the variant
      # set; the surface forms and the morph evidence come from THOSE tokens
      # only. The morph filter (cheap string ops) runs before the fold (the
      # per-language Normalize pass) so a selective facet folds only survivors.
      # The passage's source slug scopes the façade's tagset rows and picks
      # the lemma keys (LemmaKeys), so the morph path reads a token's
      # dictionary form exactly as the index did.
      def morph_hit(row, variant_set, facets, tier: nil)
        slug = row[:source_slug]
        spec = LemmaKeys.spec_for(slug)
        tokens = passage_tokens(row.fetch(:annotations_json), spec)
        return nil if tokens.empty?

        language = row.fetch(:language)
        matches = tokens.select do |token|
          MorphFacets.match?(token, facets, source: slug) && lemma_in?(token, variant_set, language, spec)
        end
        return nil if matches.empty?

        forms = matches.filter_map { |token| token["form"] }.reject(&:empty?).uniq
        build_morph_result(row, matches, forms, tier: tier, spec: spec, facets: facets)
      end

      def passage_tokens(json, spec)
        return [] if json.nil? || !LemmaKeys.probe?(json, spec)

        tokens = JSON.parse(json)["tokens"]
        tokens.is_a?(Array) ? tokens.grep(Hash) : []
      end

      def lemma_in?(token, variant_set, language, spec)
        LemmaKeys.lemmas(token, spec).any? do |lemma|
          variant_set.include?(Nabu::Normalize.search_form(lemma, language: language))
        end
      end

      def build_morph_result(row, matches, forms, tier:, spec:, facets:)
        slug = row[:source_slug]
        Result.new(
          urn: row.fetch(:urn), language: row.fetch(:language),
          lemma: LemmaKeys.lemmas(matches.first, spec).first, surface_forms: forms.join(", "),
          text: row.fetch(:text), document_title: row.fetch(:document_title),
          license_class: row.fetch(:license_class),
          morph: matches.map { |token| MorphFacets.describe(token, source: slug, facets: facets) }
                        .uniq.join("; "),
          tier: tier || Store::Indexer::GOLD_TIER
        )
      end

      # Exact folded-lemma lookup: a plain indexed equality/IN dataset — no
      # FTS, no raw SQL. Distinct on passage_id: a passage row per folded
      # lemma means one passage could match twice only if two distinct folded
      # lemmas both sit in the variant set (contrived, but dedup is one line).
      # +lang+ narrows INDEX-side (P40-r2): the lemma index carries each
      # row's language, and a windowed catalog-side language filter starves
      # on cross-language homographs (the live case: Sanskrit latā's
      # hundreds of rows sort before every Icelandic láta row, so
      # `--lemma láta --lang is` returned an empty page at any realistic
      # --limit). License/withdrawn stay catalog-side visibility checks.
      def lemma_hits(variants, inner_limit:, urn: nil, gold_only: false, lang: nil)
        dataset = passage_scoped(@fulltext[Store::Indexer::LEMMA_TABLE].where(lemma_folded: variants), urn)
        dataset = dataset.where(language: Nabu::Languages.code_variants(lang)) if lang
        dataset = dataset.where(tier: Store::Indexer::GOLD_TIER) if gold_only && tier_column?
        columns = %i[passage_id lemma_raw surface_forms]
        columns << :tier if tier_column?
        dataset.order(order_key)
               .limit(inner_limit)
               .select(*columns)
               .all
               .uniq { |row| row.fetch(:passage_id) }
      end

      # The dictionary-shelf integration (P11-4): one batched lookup fills
      # each hit's gloss from a dictionary of the hit's language (Define owns
      # the folding and the missing-shelf degradation).
      def attach_glosses(results)
        pairs = results.filter_map { |result| [result.lemma, result.language] if result.language }
        return results if pairs.empty?

        glosses = Define.new(catalog: @catalog).glosses(pairs)
        return results if glosses.empty?

        results.map { |result| result.with(gloss: glosses[[result.lemma, result.language]]) }
      end

      def build_result(row, hit)
        Result.new(
          urn: row.fetch(:urn),
          language: row.fetch(:language),
          lemma: hit.fetch(:lemma_raw),
          surface_forms: hit.fetch(:surface_forms),
          text: row.fetch(:text),
          document_title: row.fetch(:document_title),
          license_class: row.fetch(:license_class),
          tier: hit[:tier] || Store::Indexer::GOLD_TIER
        )
      end
    end
  end
end

# frozen_string_literal: true

require_relative "indexer"
require_relative "silver_lemma_indexer"

module Nabu
  module Store
    # The lemma attestation instrument's builder (P121-2): three precompiled
    # catalog rollups (migration 038) so the `lemma` and `language --curve /
    # --mixing` desks read a handful of indexed rows — never a live scan of
    # passages or passage_lemmas (the desk-commands law).
    #
    # - lemma_rollup: attestations per (lemma, language, century, basis,
    #   grade, source). lemma is passage_lemmas.lemma_folded — the folded
    #   lookup key, so the desk folds its query exactly like search --lemma.
    #   language is the stored PASSAGE code the lemma was folded under
    #   (passage_lemmas.language): in a monolingual document that is the
    #   document's own code, and in a mixed one it keeps a Greek lemma inside
    #   a Latin-tagged document under grc, where its fold belongs. grade is
    #   the passage_lemmas tier — "gold" (treebank / verified annotation) or
    #   "silver" (automatic: the local-lemmas shelf projection plus any source
    #   declared lemma_tier: silver); the equivalence tier is not a lemma
    #   attestation and stays out. occurrences counts passage attestations —
    #   the passage_lemmas grain (one row per distinct lemma per passage);
    #   per-token counts are not stored anywhere derived, and re-reading
    #   annotations_json here would be the live scan this table exists to
    #   avoid. documents counts distinct documents.
    # - language_curve: documents + passages per (language, century, basis,
    #   source), language = the passage code falling back to the document's.
    # - language_mix: one row per live document — its sorted distinct
    #   passage-language inventory and how many times the language changes
    #   between adjacent passages in sequence order.
    #
    # == Century semantics: the envelope MIDPOINT
    #
    # A document's date is the envelope of its document-grain axis rows
    # (passage_seq_from NULL): MIN(not_before) .. MAX(not_after), an open end
    # falling back to the other bound. The rollup buckets the envelope's
    # MIDPOINT — unlike vocab --by-century's earliest-year bucketing, which
    # shifts every ranged document early; a lemma's first/last attestation
    # read off midpoints is the less biased point estimate for a profile
    # built from many documents of mixed precision. The arithmetic runs on
    # astronomical years (1 BCE = 0) so the missing year 0 cannot skew a
    # BCE/CE-straddling midpoint, floors the half, converts back to
    # historical years, then takes Nabu::Timeline's signed century index
    # (-2 = 2nd c. BCE, 1 = 1st c. CE). All in SQL — the build stays
    # set-based over millions of rows. basis is the envelope's date class
    # (document_axes.date_class): "composition" for author-era dating,
    # "artifact" for the object/witness dates the NULL class means; a
    # document mixing both reads as artifact (MIN). P122-1: silver
    # estimates (Store::SilverDates) date ONLY documents no upstream row
    # dates, and then under basis "silver" — an estimate never widens or
    # relabels an upstream envelope. Undated documents keep century AND
    # basis NULL — one honest undated row per remaining key.
    #
    # == Placement and the cross-file join
    #
    # passage_lemmas lives in fulltext.sqlite3; dates and documents live in
    # the catalog. The build ATTACHes the fulltext FILE onto the catalog
    # connection for the duration of one INSERT-SELECT (read-only use), so
    # the whole derivation is grouped SQL — no per-row Ruby. No fulltext
    # file (or one without passage_lemmas) leaves lemma_rollup empty, the
    # honest absence the desk words as "not built". The two catalog-only
    # rollups build regardless.
    #
    # Derived by construction: f(catalog + fulltext) — drop-and-reproject
    # wholesale at rebuild, incremental rebuild and builders:refresh; per
    # source after a sync; lemma rows again after a standalone silver-lemma
    # projection (lemma-enrich --index-only).
    module LemmaRollup
      LEMMA_TABLE = :lemma_rollup
      CURVE_TABLE = :language_curve
      MIX_TABLE = :language_mix
      TABLES = [LEMMA_TABLE, CURVE_TABLE, MIX_TABLE].freeze

      # The insert column lists, in projection order (named, never read off
      # the dataset — Dataset#columns would execute the grouped query).
      COLUMNS = {
        LEMMA_TABLE => %i[lemma language century basis grade source_id occurrences documents],
        CURVE_TABLE => %i[language century basis source_id documents passages],
        MIX_TABLE => %i[document_id source_id urn languages language_count switches]
      }.freeze

      GRADES = [Indexer::GOLD_TIER, SilverLemmaIndexer::TIER].freeze

      # The date class a NULL document_axes.date_class stands for (migration
      # 034: the artifact/typed date the source asserts about the object).
      ARTIFACT_BASIS = "artifact"

      # The schema alias the fulltext file is attached under, and the
      # connection-scoped temp table holding one dated row per document.
      FULLTEXT_ALIAS = :rollup_fulltext
      DATES_TABLE = :rollup_document_dates

      # What one build wrote, with its elapsed wall time.
      Summary = Data.define(:lemma_rows, :curve_rows, :mix_rows, :seconds)

      module_function

      # Feature detection: a catalog predating migration 038 has none of the
      # tables — every builder entry point is then a clean no-op.
      def available?(catalog)
        catalog.table_exists?(LEMMA_TABLE)
      end

      # Wholesale recompute of all three rollups. +fulltext_path+ names the
      # fulltext.sqlite3 file (nil / absent = no lemma rows). Callers
      # announce the one "lemma rollups" stage themselves.
      def rebuild!(catalog:, fulltext_path:)
        started = clock
        return Summary.new(lemma_rows: 0, curve_rows: 0, mix_rows: 0, seconds: 0.0) unless available?(catalog)

        with_dates(catalog) do
          mix = replace!(catalog, MIX_TABLE, mix_dataset(catalog, nil))
          curve = replace!(catalog, CURVE_TABLE, curve_dataset(catalog, nil))
          lemmas = replace_lemmas!(catalog, fulltext_path, nil)
          Summary.new(lemma_rows: lemmas, curve_rows: curve, mix_rows: mix, seconds: clock - started)
        end
      end

      # Drop and re-derive ONE source's rows in all three rollups (the sync
      # seam). An unknown slug reports zeros.
      def refresh_source!(catalog:, fulltext_path:, slug:)
        started = clock
        zero = Summary.new(lemma_rows: 0, curve_rows: 0, mix_rows: 0, seconds: 0.0)
        return zero unless available?(catalog)

        source_id = catalog[:sources].where(slug: slug).get(:id)
        return zero if source_id.nil?

        with_dates(catalog) do
          mix = replace!(catalog, MIX_TABLE, mix_dataset(catalog, source_id), source_id: source_id)
          curve = replace!(catalog, CURVE_TABLE, curve_dataset(catalog, source_id), source_id: source_id)
          lemmas = replace_lemmas!(catalog, fulltext_path, source_id)
          Summary.new(lemma_rows: lemmas, curve_rows: curve, mix_rows: mix, seconds: clock - started)
        end
      end

      # Re-derive lemma_rollup alone (the standalone silver projection moves
      # only lemma rows). Returns the row count.
      def refresh_lemmas!(catalog:, fulltext_path:)
        return 0 unless available?(catalog)

        with_dates(catalog) { replace_lemmas!(catalog, fulltext_path, nil) }
      end

      # -- the date bucket ------------------------------------------------

      # One row per DATED document: document_id, century (signed index of
      # the envelope midpoint), basis. See the class note for the math.
      def document_dates(catalog)
        dated = Sequel.|(Sequel.~(not_before: nil), Sequel.~(not_after: nil))
        dated_basis = Sequel.case([[dated, Sequel.function(:coalesce, :date_class, ARTIFACT_BASIS)]], nil)
        document_grain = catalog[:document_axes].where(passage_seq_from: nil)
        upstream_dated = SilverDates.upstream(document_grain).where(dated).select(:document_id)
        envelope = document_grain
                   .where(Sequel.|(Sequel.~(axis_source: SilverDates::AXIS_SOURCE),
                                   Sequel.~(document_id: upstream_dated)))
                   .group(:document_id)
                   .select(:document_id,
                           Sequel.function(:min, :not_before).as(:nb),
                           Sequel.function(:max, :not_after).as(:na),
                           Sequel.function(:min, dated_basis).as(:basis))
        low = Sequel.function(:coalesce, :nb, :na)
        high = Sequel.function(:coalesce, :na, :nb)
        sums = envelope.from_self(alias: :envelope)
                       .exclude(low => nil)
                       .select(:document_id, :basis, (astronomical(low) + astronomical(high)).as(:span_sum))
        mids = sums.from_self(alias: :sums).select(:document_id, :basis, floor_half(Sequel[:span_sum]).as(:mid))
        mids.from_self(alias: :mids).select(:document_id, century_of_astronomical(Sequel[:mid]).as(:century), :basis)
      end

      # The three helpers below compose SQL expressions: `x < 0` builds a
      # comparison node, so the Integer predicates (negative?/positive?)
      # do not apply.
      # rubocop:disable Style/NumericPredicate

      # Historical → astronomical year (1 BCE = 0, 2 BCE = -1; CE unchanged).
      def astronomical(year)
        Sequel.case([[year < 0, year + 1]], year)
      end

      # floor(value / 2) under SQLite's truncating integer division.
      def floor_half(value)
        Sequel.case([[value < 0, (value - 1) / 2]], value / 2)
      end

      # Signed century index of an astronomical year: a positive year is CE
      # ((y + 99) / 100); year a ≤ 0 is historical (a - 1) BCE, whose index
      # -((1 - a + 99) / 100) simplifies to -((100 - a) / 100).
      def century_of_astronomical(year)
        Sequel.case([[year > 0, (year + 99) / 100]], Sequel.expr(0) - ((Sequel.expr(100) - year) / 100))
      end
      # rubocop:enable Style/NumericPredicate

      # -- the three projections -------------------------------------------

      def mix_dataset(catalog, source_id)
        language = Sequel.function(:coalesce, Sequel[:passages][:language], Sequel[:documents][:language])
        ordered = live_passages(catalog, source_id)
                  .select(Sequel[:passages][:document_id], Sequel[:documents][:source_id],
                          Sequel[:documents][:urn], language.as(:language),
                          Sequel.function(:lag, language)
                                .over(partition: Sequel[:passages][:document_id],
                                      order: Sequel[:passages][:sequence]).as(:previous))
        switch = Sequel.case([[Sequel.&(Sequel.~(previous: nil), Sequel.~(language: nil),
                                        Sequel.~(Sequel[:previous] => Sequel[:language])), 1]], 0)
        ordered.from_self(alias: :ordered)
               .group(:document_id, :source_id, :urn)
               .select(:document_id, :source_id, :urn,
                       Sequel.function(:coalesce,
                                       Sequel.function(:group_concat, :language).distinct.order(:language),
                                       "").as(:languages),
                       Sequel.function(:count, :language).distinct.as(:language_count),
                       Sequel.function(:sum, switch).as(:switches))
      end

      def curve_dataset(catalog, source_id)
        language = Sequel.function(:coalesce, Sequel[:passages][:language], Sequel[:documents][:language])
        dates = Sequel[:dates]
        live_passages(catalog, source_id)
          .left_join(Sequel.as(DATES_TABLE, :dates), document_id: Sequel[:documents][:id])
          .exclude(language => nil)
          .group(language, dates[:century], dates[:basis], Sequel[:documents][:source_id])
          .select(language.as(:language), dates[:century], dates[:basis], Sequel[:documents][:source_id],
                  Sequel.function(:count, Sequel[:documents][:id]).distinct.as(:documents),
                  Sequel.function(:count).*.as(:passages))
      end

      # Wholesale: drive from passage_lemmas and hop to passages by primary
      # key (CROSS JOIN pins SQLite's join order — the cross-file planner has
      # no statistics at build time). Per source: drive from the source's
      # documents → passages → passage_lemmas by its urn index.
      def lemma_dataset(catalog, source_id)
        lemmas = Sequel[:pl]
        documents = Sequel[:documents]
        passages = Sequel[:passages]
        ds = if source_id
               catalog[:documents].where(documents[:source_id] => source_id)
                                  .cross_join(:passages)
                                  .where(passages[:document_id] => documents[:id])
                                  .cross_join(Sequel.as(Sequel[FULLTEXT_ALIAS][:passage_lemmas], :pl))
                                  .where(lemmas[:urn] => passages[:urn])
             else
               catalog.from(Sequel.as(Sequel[FULLTEXT_ALIAS][:passage_lemmas], :pl))
                      .cross_join(:passages)
                      .where(passages[:id] => lemmas[:passage_id])
                      .join(:documents, id: passages[:document_id])
             end
        dates = Sequel[:dates]
        ds.left_join(Sequel.as(DATES_TABLE, :dates), document_id: documents[:id])
          .where(lemmas[:tier] => GRADES, passages[:withdrawn] => false, documents[:withdrawn] => false)
          .group(lemmas[:lemma_folded], lemmas[:language], dates[:century], dates[:basis],
                 lemmas[:tier], documents[:source_id])
          .select(lemmas[:lemma_folded].as(:lemma), lemmas[:language], dates[:century], dates[:basis],
                  lemmas[:tier].as(:grade), documents[:source_id],
                  Sequel.function(:count).*.as(:occurrences),
                  Sequel.function(:count, documents[:id]).distinct.as(:documents))
      end

      def live_passages(catalog, source_id)
        ds = catalog[:passages]
             .join(:documents, id: Sequel[:passages][:document_id])
             .where(Sequel[:passages][:withdrawn] => false, Sequel[:documents][:withdrawn] => false)
        source_id ? ds.where(Sequel[:documents][:source_id] => source_id) : ds
      end

      # -- write plumbing ----------------------------------------------------

      # Materialize document_dates into a connection-scoped temp table with
      # a primary key (the three projections join it), run the block on that
      # same pinned connection, drop it after.
      def with_dates(catalog)
        catalog.synchronize do
          catalog.drop_table?(DATES_TABLE)
          catalog.create_table(DATES_TABLE, temp: true) do
            Integer :document_id, primary_key: true
            Integer :century
            String :basis
          end
          catalog[DATES_TABLE].import(%i[document_id century basis], document_dates(catalog))
          begin
            yield
          ensure
            catalog.drop_table?(DATES_TABLE)
          end
        end
      end

      def replace!(catalog, table, dataset, source_id: nil)
        catalog.transaction do
          scope = source_id ? catalog[table].where(source_id: source_id) : catalog[table]
          scope.delete
          before = catalog[table].count
          catalog[table].import(COLUMNS.fetch(table), dataset)
          catalog[table].count - before
        end
      end

      # lemma_rollup needs the fulltext file attached; ATTACH cannot run
      # inside a transaction, so it brackets replace!.
      def replace_lemmas!(catalog, fulltext_path, source_id)
        unless attachable?(fulltext_path)
          scope = source_id ? catalog[LEMMA_TABLE].where(source_id: source_id) : catalog[LEMMA_TABLE]
          scope.delete
          return 0
        end

        catalog.run(Sequel.lit("ATTACH DATABASE ? AS #{FULLTEXT_ALIAS}", fulltext_path.to_s))
        begin
          unless lemma_source?(catalog)
            (source_id ? catalog[LEMMA_TABLE].where(source_id: source_id) : catalog[LEMMA_TABLE]).delete
            return 0
          end

          replace!(catalog, LEMMA_TABLE, lemma_dataset(catalog, source_id), source_id: source_id)
        ensure
          catalog.run("DETACH DATABASE #{FULLTEXT_ALIAS}")
        end
      end

      def attachable?(path)
        !path.nil? && File.file?(path.to_s)
      end

      def lemma_source?(catalog)
        catalog[Sequel[FULLTEXT_ALIAS][:sqlite_master]]
          .where(type: "table", name: Indexer::LEMMA_TABLE.to_s).any?
      end

      def clock = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      private_class_method :astronomical, :floor_half, :century_of_astronomical, :mix_dataset,
                           :curve_dataset, :lemma_dataset, :live_passages, :with_dates, :replace!,
                           :replace_lemmas!, :attachable?, :lemma_source?, :clock
    end
  end
end

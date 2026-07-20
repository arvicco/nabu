# frozen_string_literal: true

require_relative "catalog_join"

module Nabu
  module Query
    # `nabu cognates <work-or-ref>` (P15-3, intertext design §6): the
    # comparativist's join no other tool holds both halves of — verses of an
    # alignment work where witnesses in TWO OR MORE languages use reflexes of
    # the same reconstruction root (got salt ~ chu соль under PIE *sḗh₂l in
    # the salt saying). The hub (§10) says which passages share a verse; the
    # crosswalk closure (Store::ReflexRootsIndexer, §12) says which gold
    # lemmas share a root; this class is the GROUP BY that marries them.
    #
    # == Honesty rules (design §6 + the fable closure review)
    #
    # - A root is a hit only when ≥2 DISTINCT languages reach it — two codices
    #   of one language sharing a word is transmission, not comparison.
    # - The meet SHELF is part of the answer: two words meeting at a gem-pro
    #   entry while one witness is Slavic is very likely a BORROWING
    #   (Wiktionary descendants trees include loans — hlaifs ~ хлѣбъ), and
    #   renderers must be able to say so. Root.shelf carries it. Since
    #   P17-3 the closure also carries the per-edge `borrowed` flag
    #   (WitnessWord.borrowed → "(loan)" labels); the shelf heuristic stays
    #   the caption for unflagged/NULL edges — upstream flags are
    #   high-precision, low-recall.
    # - Common-word suppression: a participating lemma attested in ≥
    #   max(50, 10% of its language's gold passages) is dropped by default
    #   (grc ὁ at 72% and got sa at 36% would otherwise flood every verse);
    #   `all: true` lifts it and `suppressed` counts what fell. Frequency is
    #   a coarse proxy — богъ (4.9%) and нъ (4.7%) are inseparable by df —
    #   so the note in renderers says "common-word", never "function-word".
    # - Roots are stored as URNs and resolved against the CURRENT catalog
    #   with the withdrawn filter: a root withdrawn since the index was
    #   built silently vanishes rather than serving stale content.
    # - Grouping is duplicate-proof by construction (P18-3, the prīmus ×3
    #   audit): the accumulator is hash-keyed at every level — (ref, root
    #   urn) → language → folded lemma — and surfaces/documents/passages
    #   are Sets, so duplicate closure rows or repeated lemma rows can only
    #   MERGE into a witness word, never render it twice (pinned by test).
    #   A word/roman double-fold cannot double-match either: the closure
    #   keys word and roman folds as distinct lemma_folded strings and a
    #   gold lemma carries exactly one folded form.
    # - GOLD TIER ONLY (P26-4, the P26-0 journaled decision): cognates is
    #   RECONSTRUCTION EVIDENCE — a witness word claims "this verse attests
    #   a reflex of this root", and an automatic (silver) lemmatization is
    #   not that claim. Both the witness lookup and the suppression df are
    #   scoped to gold rows, matching ReflexRootsIndexer's gold-scoped
    #   closure and stats (numerator and denominator agree). A silver
    #   witness edition simply contributes no cognate evidence — honest
    #   absence, exactly like a witness with no annotations at all. A
    #   pre-tier index has no tier column and reads all-gold (the
    #   borrowed_column? precedent).
    class Cognates
      # A caller-fixable problem (unknown work, unattested ref, index not
      # built): CLI/MCP turn the message into exit 1 / isError.
      class Error < Nabu::Error; end

      # One language's use of the root at this verse: the display lemma, the
      # distinct attested surface forms, and the attesting witness documents
      # and passages (+passage_urns+ — the edge-grain anchor BatchCognates
      # persists; hits are pre-filtered to surviving documents, so these urns
      # never leak an excluded witness). +borrowed+ (P17-3) is the closure's
      # path-ORed loan flag for THIS witness's lemma→root edge: true = the
      # crosswalk marks the descent a borrowing (renderers label "(loan)" —
      # chu хлѣбъ (loan) ~ got hlaifs at *hlaibaz), false = parsed unflagged
      # (the meet-shelf heuristic still applies), nil = the closure predates
      # the flag (honest unknown).
      WitnessWord = Data.define(:language, :lemma, :surfaces, :document_urns,
                                :passage_urns, :borrowed)

      # The reconstruction entry the witnesses meet at. +shelf+ is the
      # dictionary language (ine-pro/gem-pro/sla-pro) — the borrowing signal.
      Root = Data.define(:urn, :headword, :shelf, :dictionary_title, :gloss,
                         :license, :license_class, :source_slug)

      # One (verse, root) hit with its per-language witness words.
      Group = Data.define(:ref, :root, :witnesses)

      # +documents+ maps witness document urns to their catalog identity
      # (title/language/license_class/source_slug) for label rendering.
      # +suppressed+ counts groups dropped by common-word suppression.
      Result = Data.define(:work, :query, :groups, :total, :truncated,
                           :suppressed, :documents)

      # Rendered-group ceiling for the compact default (house rule, as
      # align's MAX_REFS): --long lifts it.
      # const: compact-render ceiling, announced via truncated: and lifted by
      # --long — a UX bound, not a corpus claim
      MAX_GROUPS = 200

      # Common-word suppression: df ≥ max(STOP_MIN_DF, STOP_RATIO × the
      # language's gold passages). The ratio is calibrated on the live corpus
      # (function words 36–72%, wanted cognates ≤ 8.4%); the absolute floor
      # keeps tiny gold corpora (uga: 125 passages) from judging everything
      # common. The ratio is corpus-RELATIVE by design; the absolute floor
      # binds only tiny gold corpora and LOOSENS (not tightens) as they grow.
      # census: 24415015, 2026-07-20, live fulltext gold lemmas (settled full
      # rebuild): 23 gold languages, per-language gold PASSAGE counts spanning
      # sux 1,277,906 / san 780,275 … down to the tiny floors — uga 125 (the
      # calibration example, UNCHANGED), elx 162, xhu 247, arc 268. The absolute
      # floor still binds exactly those tiny corpora (0.10 × 125 = 12.5 < 50) and
      # the ratio the large ones (0.10 × 49,176 grc). P15-3 calibration stands.
      STOP_RATIO = 0.10
      STOP_MIN_DF = 50

      # passage-urn IN() batching (SQLite bound-parameter comfort).
      # const: SQLite bound-parameter comfort, not a corpus claim
      URN_BATCH = 500

      include CatalogJoin

      def initialize(catalog:, fulltext:, registry:)
        @catalog = catalog
        @fulltext = fulltext
        @registry = registry
      end

      # +target+ is a registered work id ("nt" — batch the whole work), a
      # citation ref ("LUKE 14.34"), a chapter ("LUKE 14"), or a book
      # ("LUKE"). +langs+ restricts the comparison to the named languages
      # (≥2). +all+ lifts common-word suppression; +long+ lifts the group
      # ceiling. +exclude_license+ drops witness documents of those effective
      # license classes before joining (the MCP restricted contract).
      def run(target, work: nil, langs: nil, all: false, long: false, exclude_license: [])
        ensure_ready!
        langs = validate_langs(langs)
        target_work, query, hits = resolve_target(target.to_s.strip, work)
        documents = witness_documents(hits, exclude_license)
        hits = hits.select { |hit| documents.key?(hit.fetch(:document_urn)) }
        groups, suppressed = build_groups(hits, documents, langs: langs, all: all)
        total = groups.size
        truncated = !long && total > MAX_GROUPS
        Result.new(work: target_work.id, query: query,
                   groups: truncated ? groups.first(MAX_GROUPS) : groups,
                   total: total, truncated: truncated, suppressed: suppressed,
                   documents: documents)
      end

      private

      def ensure_ready!
        if @registry.empty?
          raise Error, "no alignment works registered — add one to config/alignments.yml " \
                       "(architecture §10)"
        end
        unless @fulltext.table_exists?(Store::AlignmentIndexer::TABLE)
          raise Error, "alignment index not built — run nabu sync or nabu rebuild"
        end
        return if @fulltext.table_exists?(Store::ReflexRootsIndexer::TABLE)

        raise Error, "cognate root index not built — run nabu sync or nabu rebuild " \
                     "(and sync wiktionary-recon if the shelf is missing)"
      end

      def validate_langs(langs)
        return nil if langs.nil? || langs.empty?

        cleaned = langs.map(&:to_s).map(&:strip).reject(&:empty?).uniq
        raise Error, "cognates: give at least two languages to compare (--langs got,chu)" if cleaned.size < 2

        cleaned
      end

      # -- target resolution ---------------------------------------------------

      # [work, normalized query string, alignment_refs hit rows].
      def resolve_target(target, work_id)
        raise Error, "cognates: give a work id (nt) or a citation ref (LUKE 14.34)" if target.empty?

        if work_id.nil? && (whole = @registry.work(target))
          return [whole, whole.id, ref_hits(whole)]
        end

        norm = AlignmentRegistry.normalize_ref(target) or
          raise Error, "cognates: give a work id (#{@registry.works.map(&:id).join(', ')}) " \
                       "or a citation ref (e.g. LUKE 14.34)"
        target_work = resolve_work(norm, work_id)
        hits = ref_hits(target_work, norm)
        if hits.empty?
          raise Error, "#{norm} is not attested in work #{target_work.id.inspect} — check the " \
                       "ref, or that its witnesses are synced (nabu status)"
        end
        [target_work, norm, hits]
      end

      # Explicit --work wins; a sole registered work needs no choosing;
      # otherwise the works attesting the ref decide (align's semantics).
      def resolve_work(norm, work_id)
        if work_id
          return @registry.work(work_id) ||
                 raise(Error, "unknown alignment work #{work_id.inspect} — registered: " \
                              "#{@registry.works.map(&:id).join(', ')}")
        end
        return @registry.sole_work if @registry.sole_work

        attesters = @registry.works.select { |candidate| ref_hits(candidate, norm).any? }
        case attesters.size
        when 1 then attesters.first
        when 0
          raise Error, "#{norm} is not attested in any registered work " \
                       "(#{@registry.works.map(&:id).join(', ')}) — check the ref, or pick " \
                       "a work with --work"
        else
          raise Error, "several works attest #{norm} (#{attesters.map(&:id).join(', ')}) — " \
                       "pick one with --work"
        end
      end

      # The work's alignment rows for the query grain: whole work (norm nil),
      # exact verse ("LUKE 14.34"), or chapter/book prefix ("LUKE 14",
      # "LUKE"). Book tokens are alphanumeric, so the LIKE patterns carry no
      # metacharacters.
      def ref_hits(work, norm = nil)
        dataset = @fulltext[Store::AlignmentIndexer::TABLE].where(work: work.id)
        unless norm.nil?
          dataset = if norm.include?(" ")
                      dataset.where(Sequel.|({ ref: norm }, Sequel.like(:ref, "#{norm}.%")))
                    else
                      dataset.where(Sequel.like(:ref, "#{norm} %"))
                    end
        end
        dataset.select(:ref, :passage_urn, :document_urn).all
      end

      # -- the join --------------------------------------------------------------

      # Witness documents by urn with effective license, excluded classes
      # dropped (their hits vanish before the lemma fetch — restricted
      # material never even joins).
      def witness_documents(hits, exclude_license)
        urns = hits.map { |hit| hit.fetch(:document_urn) }.uniq
        rows = @catalog[:documents]
               .join(:sources, id: Sequel[:documents][:source_id])
               .where(Sequel[:documents][:urn] => urns, Sequel[:documents][:withdrawn] => false)
               .select(Sequel[:documents][:urn], Sequel[:documents][:title],
                       Sequel[:documents][:language], Sequel[:sources][:slug].as(:source_slug),
                       license_expr.as(:license_class))
        rows.each_with_object({}) do |row, map|
          next if exclude_license.include?(row.fetch(:license_class))

          map[row.fetch(:urn)] = { title: row.fetch(:title), language: row.fetch(:language),
                                   license_class: row.fetch(:license_class),
                                   source_slug: row.fetch(:source_slug) }
        end
      end

      # [sorted groups, suppressed count].
      def build_groups(hits, documents, langs:, all:)
        lemma_rows = lemma_rows_for(hits, langs)
        roots = roots_for(lemma_rows)
        common = all ? {} : common_pairs(lemma_rows)
        doc_of = hits.to_h { |hit| [hit.fetch(:passage_urn), hit.fetch(:document_urn)] }
        raw = accumulate(hits, lemma_rows, roots, doc_of)
        finish_groups(raw, common, documents)
      end

      # passage_urn => its GOLD lemma index rows (language-filtered when
      # --langs is active; silver rows are not reconstruction evidence —
      # class note). Batched IN() — a whole-work query holds ~65k urns.
      def lemma_rows_for(hits, langs)
        rows = Hash.new { |hash, key| hash[key] = [] }
        hits.map { |hit| hit.fetch(:passage_urn) }.uniq.each_slice(URN_BATCH) do |batch|
          dataset = gold_lemma_rows.where(urn: batch)
          dataset = dataset.where(language: langs) if langs
          dataset.select(:urn, :language, :lemma_folded, :lemma_raw, :surface_forms)
                 .each { |row| rows[row.fetch(:urn)] << row }
        end
        rows
      end

      # (language, lemma_folded) => [[root urn, borrowed], …], one query per
      # language. On a closure built before the P17-3 flag the column is
      # absent and every flag reads nil (honest unknown, no crash — the
      # read-surface migration stance).
      def roots_for(lemma_rows)
        columns = %i[lemma_folded root_urn]
        columns << :borrowed if @fulltext[Store::ReflexRootsIndexer::TABLE].columns.include?(:borrowed)
        pairs = lemma_rows.values.flatten.group_by { |row| row.fetch(:language) }
        pairs.each_with_object({}) do |(language, rows), map|
          @fulltext[Store::ReflexRootsIndexer::TABLE]
            .where(language: language, lemma_folded: rows.map { |row| row.fetch(:lemma_folded) }.uniq)
            .select(*columns)
            .each do |row|
              (map[[language, row.fetch(:lemma_folded)]] ||= []) << [row.fetch(:root_urn), row[:borrowed]]
            end
        end
      end

      # The (language, lemma_folded) pairs the suppression judges common:
      # corpus GOLD df ≥ max(floor, ratio × the language's gold passages) —
      # tier-scoped on both sides of the division (the stats table is
      # gold-scoped too), so a silver flood can never re-judge a word common.
      def common_pairs(lemma_rows)
        totals = @fulltext[Store::ReflexRootsIndexer::STATS_TABLE].as_hash(:language, :gold_passages)
        lemma_rows.values.flatten.group_by { |row| row.fetch(:language) }
                                 .each_with_object({}) do |(language, rows), common|
          threshold = [STOP_MIN_DF, (totals.fetch(language, 0) * STOP_RATIO)].max
          gold_lemma_rows
            .where(language: language, lemma_folded: rows.map { |row| row.fetch(:lemma_folded) }.uniq)
            .group_and_count(:lemma_folded)
            .each do |row|
            if row.fetch(:count) >= threshold
              common[[language, row.fetch(:lemma_folded)]] =
                true
            end
          end
        end
      end

      # (ref, root_urn) => language => lemma_folded => { lemma:, surfaces:,
      # documents: } — the raw meet accumulator.
      def accumulate(hits, lemma_rows, roots, doc_of)
        raw = {}
        hits.each do |hit|
          lemma_rows.fetch(hit.fetch(:passage_urn), []).each do |row|
            key = [row.fetch(:language), row.fetch(:lemma_folded)]
            roots.fetch(key, []).each do |root_urn, borrowed|
              slot = ((raw[[hit.fetch(:ref), root_urn]] ||= {})[row.fetch(:language)] ||= {})
              entry = slot[row.fetch(:lemma_folded)] ||=
                { lemma: row.fetch(:lemma_raw), borrowed: borrowed,
                  surfaces: Set.new, documents: Set.new, passages: Set.new }
              entry[:surfaces].merge(row.fetch(:surface_forms).split(", ").reject(&:empty?))
              entry[:documents].add(doc_of.fetch(row.fetch(:urn)))
              entry[:passages].add(row.fetch(:urn))
            end
          end
        end
        raw
      end

      # The gold-tier lemma dataset (class note; P26-4). A pre-tier index
      # has no tier column — and no silver rows — so the unfiltered dataset
      # is the same gold-only set (the borrowed_column? precedent).
      def gold_lemma_rows
        dataset = @fulltext[Store::Indexer::LEMMA_TABLE]
        return dataset unless tier_column?

        dataset.where(tier: Store::Indexer::GOLD_TIER)
      end

      def tier_column?
        return @tier_column unless @tier_column.nil?

        @tier_column = @fulltext[Store::Indexer::LEMMA_TABLE].columns.include?(:tier)
      end

      # Apply suppression + the ≥2-distinct-languages rule, resolve roots,
      # sort by citation then headword. Returns [groups, suppressed count].
      def finish_groups(raw, common, documents)
        suppressed = 0
        kept = raw.filter_map do |(ref, root_urn), by_language|
          survivors = prune_common(by_language, common)
          if survivors.size < 2
            suppressed += 1 if by_language.size >= 2
            next
          end
          [ref, root_urn, survivors]
        end
        resolved = resolve_roots(kept.map { |_, root_urn, _| root_urn }.uniq)
        groups = kept.filter_map do |ref, root_urn, survivors|
          root = resolved[root_urn] or next # withdrawn since the index build
          Group.new(ref: ref, root: root, witnesses: witness_words(survivors, documents))
        end
        [groups.sort_by { |group| [cite_key(group.ref), group.root.headword] }, suppressed]
      end

      def prune_common(by_language, common)
        by_language.each_with_object({}) do |(language, lemmas), out|
          keep = lemmas.reject { |folded, _| common[[language, folded]] }
          out[language] = keep unless keep.empty?
        end
      end

      def witness_words(survivors, documents)
        survivors.flat_map do |language, lemmas|
          lemmas.map do |_, entry|
            WitnessWord.new(language: language, lemma: entry.fetch(:lemma),
                            surfaces: entry.fetch(:surfaces).sort,
                            document_urns: entry.fetch(:documents).to_a.sort
                                                .select { |urn| documents.key?(urn) },
                            passage_urns: entry.fetch(:passages).to_a.sort,
                            borrowed: entry.fetch(:borrowed))
          end
        end.sort_by(&:language)
      end

      # root urn => Root, resolved against the LIVE shelf (withdrawn out).
      def resolve_roots(urns)
        return {} if urns.empty?

        @catalog[:dictionary_entries]
          .join(:dictionaries, id: Sequel[:dictionary_entries][:dictionary_id])
          .join(:sources, id: Sequel[:dictionaries][:source_id])
          .where(Sequel[:dictionary_entries][:urn] => urns,
                 Sequel[:dictionary_entries][:withdrawn] => false)
          .select(Sequel[:dictionary_entries][:urn], Sequel[:dictionary_entries][:headword],
                  Sequel[:dictionary_entries][:gloss],
                  Sequel[:dictionaries][:language].as(:shelf),
                  Sequel[:dictionaries][:title].as(:dictionary_title),
                  Sequel[:sources][:license], Sequel[:sources][:license_class],
                  Sequel[:sources][:slug].as(:source_slug))
          .to_h do |row|
            [row.fetch(:urn),
             Root.new(urn: row.fetch(:urn), headword: "*#{row.fetch(:headword)}",
                      shelf: row.fetch(:shelf), dictionary_title: row.fetch(:dictionary_title),
                      gloss: row.fetch(:gloss), license: row.fetch(:license),
                      license_class: row.fetch(:license_class),
                      source_slug: row.fetch(:source_slug))]
          end
      end

      # Citation sort key: book token alphabetical, then citation segments in
      # numeric document order (align's cite semantics; "1.9" before "1.10").
      # Mixed segments compare as [numeric-flag, value] pairs so integers and
      # subverse strings never collide in the sort.
      def cite_key(ref)
        book, cite = ref.split(" ", 2)
        segments = (cite || "").split(".").map do |segment|
          segment.match?(/\A\d+\z/) ? [0, segment.to_i] : [1, segment]
        end
        [book.to_s, segments]
      end
    end
  end
end

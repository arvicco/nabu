# frozen_string_literal: true

# Nabu::Store::Indexer — the fulltext stage stamps and reconcile_stages!.
# A partial of lib/nabu/store/indexer.rb, which loads it.
module Nabu
  module Store
    module Indexer
      module_function

      # -- fulltext stage stamps (P87-3, Q52a) ------------------------------
      # Each heavy fulltext-side stage records the derivation VERSION it
      # was built under. `--incremental` (whose kept catalog makes carrying
      # sound) compares and surgically re-runs exactly the stage a version
      # bump dirtied; plain `rebuild` stays the reference and re-mints all
      # stamps. A missing stamps TABLE means a pre-P87 index: incremental
      # keeps its legacy behavior (no stage protection existed then either)
      # and says so — the next full rebuild, or --trust-stages, mints them.

      STAGE_STAMPS_TABLE = :stage_stamps

      # const: derivation-version tokens per stage — bump a stage's token
      # whenever ITS derivation semantics change (the P86-3 postings
      # widening is the type specimen; its class token doubles here).
      # Display choices/census claims live elsewhere; these are code-era
      # markers.
      STAGE_VERSIONS = {
        # v2: passage_lemmas sheds its urn column; passage_id is the
        # passage key (class note). Not reconcilable standalone — the full
        # rebuild recreates the table narrow.
        "fts_lemma" => "v2-passage-keyed",
        "char_postings" => POSTINGS_CLASS,
        "trigram" => "v1",
        # P93-3: the run class + mint grammar era. An index stamped before
        # the lane existed reads stale here, so `--incremental` builds the
        # lane standalone — the lane's arrival path beside the full
        # rebuild and the flagged-sync bootstrap.
        "cjk" => "v1-han-kana",
        "passage_chars" => "v1",
        "sign_coverage" => "v1-tokenize-once",
        "alignment" => "v1",
        "reflex" => "v1",
        # The clarify lane (nabu_clarify): an index stamped before it existed
        # reads stale here, so `--incremental` builds it standalone.
        # v2: clarify_fold expands æ/œ — names folded under v1 keep the
        # ligature and miss the new query fold until re-derived.
        "clarify" => "v2-ligatures",
        # The translations lane (Store::TranslationIndex): an index
        # stamped before it existed reads stale here, so `--incremental`
        # (or `rake index:translations`) builds it standalone.
        "translations" => "v1",
        # The token-gloss lane (Store::GlossIndex): likewise built
        # standalone by `--incremental` (or `rake index:glosses`) on an
        # index stamped before it existed.
        "glosses" => "v1",
        # The annotations lane (Store::AnnotationIndex): likewise built
        # standalone by `--incremental` (or `rake index:annotations`) on an
        # index stamped before it existed.
        "annotations" => "v1",
        # The gloss-lines lane (Store::GlossLineIndex): likewise built
        # standalone by `--incremental` (or `rake index:gloss_lines`) on an
        # index stamped before it existed.
        "gloss_lines" => "v1"
      }.freeze

      # The stages reconcile_stages! can re-derive standalone against a
      # kept catalog. A stale stage OUTSIDE this set (fts_lemma — the
      # composite streaming pass; trigram — its scope memory) refuses
      # loudly: a full rebuild is the honest answer there.
      RECONCILABLE_STAGES = %w[char_postings cjk passage_chars sign_coverage alignment reflex clarify
                               translations glosses annotations gloss_lines].freeze

      def stamp_stages!(fulltext, versions: STAGE_VERSIONS)
        create_stage_stamps_table(fulltext)
        now = Time.now.utc.iso8601
        versions.each do |stage, version|
          fulltext[STAGE_STAMPS_TABLE]
            .insert_conflict(target: :stage, update: { version: version, stamped_at: now })
            .insert(stage: stage, version: version, stamped_at: now)
        end
      end

      def create_stage_stamps_table(fulltext)
        fulltext.create_table?(STAGE_STAMPS_TABLE) do
          String :stage, primary_key: true
          String :version, null: false
          String :stamped_at, null: false
        end
      end

      # Stage names whose stamped version differs from +versions+ (all of
      # them when the table is absent — the caller decides how to treat a
      # pre-P87 index).
      def stale_stages(fulltext, versions: STAGE_VERSIONS)
        return versions.keys unless fulltext.table_exists?(STAGE_STAMPS_TABLE)

        stamped = fulltext[STAGE_STAMPS_TABLE].select_hash(:stage, :version)
        versions.reject { |stage, version| stamped[stage] == version }.keys
      end

      # P87-3: the incremental path's stage reconciliation. Returns
      # [redone_stage_names, refusal_or_nil, note_or_nil]:
      # - pre-P87 index (no stamps table): no-op with an honest note
      #   (legacy behavior — no protection existed before either);
      # - +trust+: mint stamps at current versions without re-deriving
      #   (the documented bridge for an index KNOWN built by current code);
      # - a stale stage in RECONCILABLE_STAGES re-derives corpus-wide and
      #   re-stamps; any other stale stage refuses — full rebuild required.
      def reconcile_stages!(catalog:, fulltext:, sign_list: nil, alignments: nil, cjk_slugs: nil,
                            versions: STAGE_VERSIONS, trust: false, progress: nil)
        unless fulltext.table_exists?(STAGE_STAMPS_TABLE)
          if trust
            stamp_stages!(fulltext, versions: versions)
            return [[], nil, "stage stamps minted at current versions (--trust-stages)"]
          end
          return [[], nil,
                  "fulltext stages are unstamped (pre-P87 index) — derivation-change " \
                  "protection starts at the next full rebuild (or --trust-stages if this " \
                  "index was built by the current code)"]
        end

        stale = stale_stages(fulltext, versions: versions)
        return [[], nil, nil] if stale.empty?

        if trust
          stamp_stages!(fulltext, versions: versions)
          return [[], nil, "stage stamps advanced without re-derive (--trust-stages)"]
        end
        unreconcilable = stale - RECONCILABLE_STAGES
        unless unreconcilable.empty?
          return [[], "derivation changed for stage(s) #{unreconcilable.join(', ')} — no " \
                      "standalone corpus re-run exists for them; a full rebuild is required",
                  nil]
        end

        stale.each do |stage|
          progress&.stage("stage re-derive: #{stage} (derivation version moved)")
          case stage
          when "char_postings" then rebuild_char_postings!(catalog: catalog, fulltext: fulltext)
          when "cjk"
            rebuild_cjk!(catalog: catalog, fulltext: fulltext, cjk_slugs: Array(cjk_slugs), progress: progress)
          when "passage_chars" then rebuild_passage_chars!(catalog: catalog, fulltext: fulltext)
          when "sign_coverage"
            rebuild_sign_coverage!(catalog: catalog, fulltext: fulltext, sign_list: sign_list,
                                   progress: progress)
          when "alignment"
            AlignmentIndexer.rebuild!(catalog: catalog, fulltext: fulltext, registry: alignments)
          when "reflex" then ReflexRootsIndexer.rebuild!(catalog: catalog, fulltext: fulltext)
          when "clarify" then rebuild_clarify!(catalog: catalog, fulltext: fulltext)
          when "translations" then TranslationIndex.rebuild!(catalog: catalog, fulltext: fulltext)
          when "glosses" then GlossIndex.rebuild!(catalog: catalog, fulltext: fulltext)
          when "annotations" then AnnotationIndex.rebuild!(catalog: catalog, fulltext: fulltext)
          when "gloss_lines" then GlossLineIndex.rebuild!(catalog: catalog, fulltext: fulltext)
          end
          stamp_stages!(fulltext, versions: { stage => versions.fetch(stage) })
        end
        [stale, nil, nil]
      end

      # Is silver ARMED — has the owner projected the shelf into
      # this index? Read from lemma_frequencies (small, tier-keyed — the
      # projection always maintains it) rather than scanning the 100M-row
      # lemma table for a tier value.
      def silver_armed?(fulltext)
        return false unless fulltext.table_exists?(LemmaFrequencies::TABLE)

        !fulltext[LemmaFrequencies::TABLE].where(tier: SilverLemmaIndexer::TIER).empty?
      end
    end
  end
end

# frozen_string_literal: true

# Nabu::Store::Indexer — the sync-time slice refresh (refresh_source!, the wave refresh) and its internals.
# A partial of lib/nabu/store/indexer.rb, which loads it.
module Nabu
  module Store
    module Indexer
      module_function

      # Incrementally refresh ONE source's slice of the index (P26-5) — the
      # sync-time replacement for the full drop-and-rebuild above, which stays
      # `nabu rebuild`'s from-scratch guarantee. The contract is ROW IDENTITY:
      # after refresh_source!, the fulltext state equals what rebuild! would
      # produce from the same catalog (pinned by test).
      #
      # Mechanism, table by table:
      # - passages_fts in the P93-1 contentless shape deletes BY KEY: rowid
      #   is the catalog passage id and contentless_delete=1 makes per-row
      #   DELETE real, so the source's slice goes in indexed batches —
      #   withdrawn rows included, since the loader never hard-deletes a
      #   passage row, every indexed id resolves against the catalog
      #   forever. A legacy contentful file (and passages_trigram, still
      #   contentful) instead pays ONE streaming scan collecting the doomed
      #   rowids by their stored passage_id (UNINDEXED — per-IN-batch scans
      #   would each rescan the table), then deletes by rowid. ~4.3M-row
      #   scan, seconds — against the minutes of a full rebuild.
      # - passage_lemmas deletes by passage_id IN-batches (B-tree indexed;
      #   a retired v1 table refuses — require_v2_lemmas!).
      # - trigram: only touched when the source is in scope — flagged now
      #   (fuzzy_slugs) or indexed by the last build (the scope table); a
      #   de-flagged source loses its rows AND its scope row, so coverage
      #   reads honestly. Live scope: papyri/oracc/edh, 1.71M rows total.
      # - alignment_refs: rebuilt via AlignmentIndexer ONLY when the source
      #   holds a registry witness document — the index is registry-scoped
      #   (157k rows live) so the full rebuild is cheap, and a non-witness
      #   sync skips it entirely.
      # - reflex_roots/stats: rebuilt when the source's lemma rows changed
      #   (84k rows live, ~seconds) or when +reflexes_changed+ says the
      #   crosswalk itself did (dictionary syncs); a lemma-less source skips.
      #
      # Fallback: a fulltext db missing any table (first-ever sync) or whose
      # lemma table predates the tier column falls back to the full rebuild!.
      # Returns the SOURCE's live passage count — never the corpus total.
      # +delta+ (P112-1) is the load's Store::IndexDelta or nil. With a
      # usable delta the refresh works the DELTA GRAIN: it deletes exactly
      # the changed rowids from the passage-keyed tables and re-derives
      # exactly the upserted rows, so sync index cost is proportional to what
      # the load actually changed — never the slice size (the measured
      # pathology: an 8.9M-row cbeta rewrite serving a 35-document heal).
      # The whole-slice rewrite remains the fallback for: no delta (callers
      # predating the grain, dictionary-lane syncs), an OVERFLOWED delta
      # (the sets were freed — at that volume the slice costs the same), and
      # a HEALING refresh (pending marker at entry: the crashed run's work
      # is not in this load's delta, so only the full rewrite is honest).
      # char_postings, a per-source AGGREGATE, moves by exact decrements +
      # increments at the delta grain (char_postings_basis) — never a
      # whole-source scan; where the grain cannot recover a revised row's
      # OLD contribution the source's postings are flagged stale for the
      # maintenance rail (Store::StaleAggregates) instead.
      def refresh_source!(catalog:, fulltext:, slug:, alignments: nil, fuzzy_slugs: nil,
                          cjk_slugs: nil, lemma_tiers: nil, reflexes_changed: false,
                          sign_list: nil, progress: nil,
                          ledger: nil, lemma_shelf: nil, lemma_filter_slugs: nil,
                          bulk_threshold: BULK_SLICE_THRESHOLD, delta: nil,
                          row_budget: IN_PLACE_ROW_BUDGET, plan: nil, fts_prebuilt: false)
        unless incremental_ready?(fulltext)
          rebuild!(catalog: catalog, fulltext: fulltext, alignments: alignments,
                   fuzzy_slugs: fuzzy_slugs, cjk_slugs: cjk_slugs, lemma_tiers: lemma_tiers,
                   sign_list: sign_list,
                   progress: progress, lemma_shelf: lemma_shelf, lemma_filter_slugs: lemma_filter_slugs)
          return source_live_count(catalog, slug)
        end

        source_id = catalog[:sources].where(slug: slug).get(:id)
        return 0 if source_id.nil?

        # The run's entry state and key sets (slice_plan). A wave
        # (refresh_sources!) hands in the plan it took BEFORE its own
        # pending markers and shadow swap, so the entry state read here is
        # the source's own, never the wave's.
        plan ||= slice_plan(catalog, fulltext, slug: slug, source_id: source_id, delta: delta)
        healing = plan.healing
        prior_shape = plan.prior_shape
        use_delta = plan.use_delta
        heal = plan.heal
        ids = plan.ids
        urns = plan.urns
        slice_ids = plan.slice_ids
        count = 0
        lemmas_changed = false
        # P77-r16d (owner ruling 2026-08-18, applied to the WHOLE sync
        # reindex path): every sub-step that can run minutes announces
        # itself — a lemma-bearing source rewrites its fts+lemma slice
        # (hundreds of thousands of rows) and then triggers the
        # corpus-wide reflex closure; both sat silent behind the load
        # counter and read as hangs.
        # P78-r3 (the sillok first-sync lesson: r2 gave sync only the
        # whole-run banner — the SLOW stages, these, still announced bare):
        # each multi-second sub-step records its wall time to the ledger's
        # stage_timings under kind "sync" and announces with the estimate
        # the LAST sync of this source earned.
        # The deferred-deletemerge recipe governs EVERY slice write against
        # the contentless shape (constants note: the hazard is the index's
        # tombstone debt, not the write's size). The WRITE VOLUME binds only
        # the transaction shape: the slice size on the rewrite path, the
        # changed-row count at the delta grain — small deltas on a huge
        # source keep the atomic swap (P112-1: tombstone volume stays
        # proportional to churn).
        governed = governed_fts_tables(fulltext)
        bulk = !governed.empty? && ids.size >= bulk_threshold
        # The in-place row budget (SHADOW_TABLE note): over it, the lane is
        # built as an append-only shadow instead. A killed build's orphan
        # goes first, whatever this run decides. +fts_prebuilt+: a wave
        # (refresh_sources!) already swapped in a shadow holding this
        # source's live rows — the run's fts half is done, exactly as
        # after its own shadow build, and no second build runs.
        fulltext.drop_table?(SHADOW_TABLE)
        build_shadow = !fts_prebuilt && shadow_main?(catalog, fulltext, ids, row_budget, source_id: source_id,
                                                                                         slug: slug,
                                                                                         progress: progress)
        shadow = fts_prebuilt || build_shadow
        trigram_ids = use_delta ? delta.changed_ids : slice_ids
        trigram_shadow = trigram_ids.size > row_budget && trigram_touched?(fulltext, slug, Array(fuzzy_slugs))
        # The shadow writes passages_fts nowhere in place — its deferral
        # recipe has nothing to govern (the cjk lane, when present, keeps it).
        governed -= [TABLE] if shadow
        progress&.stage("index slice: #{slug} — bulk mode (#{ids.size} rows): merges deferred") if bulk
        # The census grain (CENSUS_BASELINES_TABLE note): a bulk run — or
        # any run over a standing baseline a crashed bulk run left — moves
        # the lemma census by the source's WHOLE contribution against that
        # baseline; every other run by its own before/after delta.
        census_whole = bulk || census_baseline?(fulltext, slug)
        whole_ids = (census_whole_ids(catalog, source_id, ids, heal, use_delta) if census_whole)
        if use_delta
          progress&.stage("index delta: #{slug} — #{delta.upserted_ids.size} changed / " \
                          "#{delta.removed_ids.size} removed rows")
        end
        if heal
          progress&.stage("index heal: #{slug} — exact diff against the row-sha sidecar: " \
                          "#{heal.upserted_ids.size} rows to re-derive / #{ids.size} to clear")
        end
        # A full-slice rewrite is where the sidecar arrives on a fulltext
        # predating it (ROW_SHAS_TABLE note) — it populates the whole slice.
        create_row_shas_table(fulltext) if !use_delta && !heal && fts_contentless?(fulltext)
        # The bulk run's census baseline lands BEFORE its marker and its
        # first destructive write — and never over a standing one (that
        # one is the last consistent point).
        write_census_baseline!(fulltext, slug, whole_ids) if bulk && !census_baseline?(fulltext, slug)
        mark_slice_pending!(fulltext, slug, shape: bulk ? "bulk" : "atomic")
        census_moves = nil
        if build_shadow
          timed_sync_stage(ledger, slug, "fts_shadow",
                           "index slice: #{slug} — passages_fts shadow build (#{ids.size} rows over the " \
                           "#{row_budget}-row in-place budget: append-only, swapped in whole)", progress,
                           rows_of: :itself.to_proc) do
            written = build_fts_shadow!(catalog: catalog, fulltext: fulltext, source_id: source_id, progress: progress)
            swap_fts_shadow!(fulltext)
            written
          end
        end
        with_bulk_write_mode(fulltext, governed) do
          timed_sync_stage(ledger, slug, "index_slice",
                           "index slice: #{slug} (fts + lemma rows)", progress) do
            slice_write_unit(fulltext, bulk: bulk, progress: progress) do
              # P42-1: snapshot this source's lemma-frequency contribution BEFORE
              # the rewrite, re-snapshot AFTER, and apply the delta to the corpus
              # freq table (same transaction). incremental_ready? guarantees the
              # table exists here; both snapshots are passage-keyed and B-tree bounded.
              unless census_whole
                before = LemmaFrequencies.snapshot(fulltext, ids: ids)
                before_stats = ReflexRootsIndexer.stats_snapshot(fulltext, ids: ids)
              end
              # The postings decrements read the sidecar, so they are taken
              # before its rows go (char_postings_basis).
              postings_basis = (char_postings_basis(catalog, fulltext, source_id, slug, ids) if use_delta)
              # FIRST destructive write: the doomed rows' sidecar shas
              # (ROW_SHAS_TABLE invariant — removed before their fts/lemma rows).
              delete_row_shas(fulltext, ids)
              deleted = delete_source_lemma_rows(fulltext, ids: ids)
              # Under a shadow the swapped-in table already holds the
              # source's current rows — its fts half is done, in neither
              # direction in place.
              if shadow
                nil
              elsif fts_contentless?(fulltext)
                delete_fts_rows_by_rowid(fulltext, TABLE, ids, progress: progress)
              else
                delete_fts_rows(fulltext, TABLE, ids)
              end
              insert_scope =
                if use_delta
                  ids_scoped(live_passages(catalog), delta.upserted_ids)
                elsif heal
                  ids_scoped(live_passages(catalog), heal.upserted_ids)
                else
                  live_passages(catalog).where(Sequel[:documents][:source_id] => source_id)
                end
              count, inserted, chars = insert_passage_batches(
                fulltext, insert_scope,
                source_tiers(catalog, lemma_tiers || {}), source_slugs(catalog), progress: progress,
                                                                                 fts: !shadow
              )
              # P84-1: re-apply the silver-lemma slice — the delete above
              # stripped any shelf-projected rows for these urns, and the
              # annotation re-derivation never re-mints them. Scoped to this
              # source's urns; the frequency delta below counts the re-landed
              # rows because the after-snapshot runs later in this txn.
              # ARM-GATE (owner-ruled 2026-08-29): only when the owner has projected the shelf
              # (any silver row standing) — an unarmed index stays
              # silver-free through syncs.
              # An exact heal re-applies over the WHOLE slice's urns: the
              # crashed run's silver pass (after its insert loop) may never
              # have run, and the apply is insert-if-absent.
              if lemma_shelf && silver_armed?(fulltext)
                silver = SilverLemmaIndexer.apply!(catalog: catalog, fulltext: fulltext, shelf: lemma_shelf,
                                                   urns: (heal ? heal.slice_urns : urns).to_set,
                                                   dictionary_filter_slugs: Array(lemma_filter_slugs))
                inserted += silver.rows_inserted
              end
              lemmas_changed = deleted.positive? || inserted.positive?
              # The exact heal moves only drifted rows; whether the crashed
              # run left the census drifted is the shape's question
              # (CENSUS_BASELINES_TABLE note), answered without a corpus read.
              lemmas_changed ||= heal && source_lemma_rows?(fulltext, ids: heal.slice_ids)
              census_moves =
                if census_whole
                  apply_census_from_baseline!(fulltext, slug, whole_ids)
                else
                  after = LemmaFrequencies.snapshot(fulltext, ids: ids)
                  LemmaFrequencies.apply_delta(fulltext, before: before, after: after)
                  ReflexRootsIndexer.apply_stats_delta!(
                    fulltext, before: before_stats, after: ReflexRootsIndexer.stats_snapshot(fulltext, ids: ids)
                  )
                end
              if healing && prior_shape.nil? && !census_whole && lemmas_changed
                # A crash of unrecorded shape (a marker minted before shapes
                # were) may have drifted the census beyond this source's
                # rows: the delta above is exact for THIS run, the base is
                # owed to the maintenance rail.
                StaleAggregates.mark!(fulltext, aggregate: CENSUS_AGGREGATE, scope: "corpus",
                                                reason: "#{slug}: heal over a pending marker of unrecorded shape")
              end
              # The cjk lane is REBUILD-CADENCE (2026-11-11 ruling): no
              # slice or delta write here, ever — +cjk_slugs+ feeds only
              # the full-rebuild fallback above; the lane catches up at
              # the next rebuild (refresh_cjk_lane!).
              # An over-budget trigram write rebuilds the lane file whole
              # below, outside this unit (Lanes.build! refuses a transaction).
              if trigram_shadow
                nil
              elsif use_delta
                refresh_trigram_delta(catalog, fulltext, slug, Array(fuzzy_slugs), delta)
              else
                refresh_trigram_slice(catalog, fulltext, slug, Array(fuzzy_slugs), slice_ids)
              end
              # P65: swap this source's char-postings slice; a pre-P65 fulltext
              # file (no table) gets the whole postings build below instead —
              # NEVER a full FTS rebuild for a missing derived sub-table.
              # Delta mode moves the aggregate by exact arithmetic (decrements
              # taken above, increments = this pass's +chars+) or flags it
              # stale; the whole-slice rewrite re-derives it outright (and so
              # clears any flag); a heal re-reads the source (its insert pass
              # covers only the drifted rows).
              if fulltext.table_exists?(CHAR_POSTINGS_TABLE)
                if use_delta
                  apply_char_postings_delta!(fulltext, slug: slug, source_id: source_id,
                                                       basis: postings_basis, increments: chars)
                else
                  fulltext[CHAR_POSTINGS_TABLE].where(source_id: source_id).delete
                  chars = source_char_postings(catalog, source_id) if heal
                  write_char_postings(fulltext, chars)
                  StaleAggregates.clear!(fulltext, aggregate: POSTINGS_AGGREGATE, scope: slug)
                end
              end
              # P72-1: swap this source's coverage-index slice too (ranks from
              # current postings — performance-only, the exact check verifies).
              # Delta mode swaps by rowid: the changed rows' coverage goes, the
              # upserted rows' coverage lands, untouched rows keep theirs.
              if fulltext.table_exists?(PASSAGE_CHARS_TABLE)
                if use_delta
                  delete_rowid_slices(fulltext, PASSAGE_CHARS_TABLE, delta.changed_ids)
                  write_passage_chars(fulltext,
                                      passage_chars_rows(catalog, fulltext, ids: delta.upserted_ids))
                else
                  fulltext[PASSAGE_CHARS_TABLE].where(source_id: source_id).delete
                  write_passage_chars(fulltext, passage_chars_rows(catalog, fulltext, source_id: source_id))
                end
              end
              # P77-r16: swap this source's SIGN-coverage slice (SIGN_SOURCES
              # only; ranks from the standing sign_postings — performance-only;
              # a nil sign_list leaves the slice deleted, honest to the load).
              # Delta mode re-tokenizes ONLY the upserted rows (the heavy part
              # of this lane is tokenization — the whole point of the grain).
              if fulltext.table_exists?(PASSAGE_SIGNS_TABLE) && SIGN_SOURCES.include?(slug)
                if use_delta
                  delete_rowid_slices(fulltext, PASSAGE_SIGNS_TABLE, delta.changed_ids)
                else
                  fulltext[PASSAGE_SIGNS_TABLE].where(source_id: source_id).delete
                end
                if sign_list
                  progress&.stage("sign coverage: re-tokenizing the #{slug} #{use_delta ? 'delta' : 'slice'}")
                  sign_ids = (delta.upserted_ids if use_delta)
                  write_passage_signs(fulltext,
                                      passage_signs_rows(catalog, fulltext, sign_list, source_id: source_id,
                                                                                       ids: sign_ids,
                                                                                       progress: progress))
                end
              end
            end
          end
        end
        consolidate_deferred_merges!(fulltext, governed, slug: slug, ledger: ledger, progress: progress)
        if trigram_shadow
          timed_sync_stage(ledger, slug, "trigram_shadow",
                           "trigram lane: shadow build (#{trigram_ids.size} rows over the #{row_budget}-row " \
                           "in-place budget — the lane file rebuilt whole)", progress) do
            rebuild_trigram!(catalog: catalog, fulltext: fulltext, fuzzy_slugs: Array(fuzzy_slugs))
          end
        end
        timed_sync_stage(ledger, slug, "postings_swaps",
                         "index slice: #{slug} — postings/coverage swaps", progress) do
          unless fulltext.table_exists?(CHAR_POSTINGS_TABLE)
            rebuild_char_postings!(catalog: catalog,
                                   fulltext: fulltext)
          end
          unless fulltext.table_exists?(PASSAGE_CHARS_TABLE)
            rebuild_passage_chars!(catalog: catalog,
                                   fulltext: fulltext)
          end
          # P77-r16b (the 2026-08-18 "hang"): the sign-coverage bootstrap is
          # HEAVY (two tokenize+resolve passes over the whole ATF corpora —
          # hours, not the char bootstrap's cheap regex sweep), so it fires
          # ONLY when the synced source is itself a sign corpus — the sign
          # corpora pay their own indexing cost, an unrelated source's sync
          # is never ambushed. Elsewhere it arrives at the next full rebuild.
          if SIGN_SOURCES.include?(slug) && !fulltext.table_exists?(PASSAGE_SIGNS_TABLE)
            rebuild_sign_coverage!(catalog: catalog, fulltext: fulltext, sign_list: sign_list,
                                   progress: progress)
          end
          refresh_alignment(catalog, fulltext, alignments, source_id)
        end
        # The closure at the delta grain (ReflexRootsIndexer class note):
        # a crosswalk change re-walks the closure alone (O(crosswalk), the
        # dictionary's own arrival); a lemma change moves it only by the
        # gold languages that crossed zero. The corpus pass is the rebuild's
        # and the maintenance rail's.
        if reflexes_changed
          timed_sync_stage(ledger, slug, "reflex_rewalk",
                           "reflex root closure (crosswalk changed — re-walked; gold stats kept)", progress) do
            ReflexRootsIndexer.rebuild_closure!(catalog: catalog, fulltext: fulltext)
          end
        elsif census_moves && !(census_moves[:entered].empty? && census_moves[:left].empty?)
          timed_sync_stage(ledger, slug, "reflex_closure",
                           "reflex root closure: gold languages moved (+#{census_moves[:entered].join(',')} " \
                           "-#{census_moves[:left].join(',')})", progress) do
            ReflexRootsIndexer.apply_language_moves!(catalog: catalog, fulltext: fulltext, **census_moves)
          end
        end
        # The clarify lane's slice (names only — cheap; skipped on a
        # fulltext predating the lane, which the reconcile/rake path builds).
        refresh_clarify_source!(catalog: catalog, fulltext: fulltext, slug: slug)
        # The translations lane's slice (registry sources only; hands-off
        # on a fulltext predating the lane — no bootstrap, the clarify
        # stance). Rides the load's delta when this refresh does.
        TranslationIndex.refresh_source!(catalog: catalog, fulltext: fulltext, slug: slug,
                                         delta: (delta if use_delta))
        # The token-gloss lane's slice (registry sources only, whole-slice
        # grain — a word row aggregates across passages; hands-off on a
        # fulltext predating the lane).
        GlossIndex.refresh_source!(catalog: catalog, fulltext: fulltext, slug: slug)
        # The annotations lane's slice (declared sources only; delta grain
        # like translations; hands-off on a fulltext predating the lane).
        AnnotationIndex.refresh_source!(catalog: catalog, fulltext: fulltext, slug: slug,
                                        delta: (delta if use_delta))
        # The gloss-lines lane's slice (declared gloss sources only;
        # passage-keyed, so delta grain like annotations).
        GlossLineIndex.refresh_source!(catalog: catalog, fulltext: fulltext, slug: slug,
                                       delta: (delta if use_delta))
        # P112-3: the finish stamp records the catalog state this slice now
        # serves — health's freshness cross-check reads it back.
        live_rows, max_id = source_live_stats(catalog, slug)
        mark_slice_finished!(fulltext, slug, live_rows: live_rows, max_passage_id: max_id)
        # The bulk pass's final reclaim — AFTER the last write, so the WAL
        # file ends the refresh truncated, not holding the postings swaps.
        checkpoint_wal!(fulltext, progress: progress) if bulk
        # The slice rewrite's insert count IS the source's live total; the
        # delta grain inserts only the changed rows, so the honest
        # "indexed N" is counted from the catalog instead.
        use_delta || heal ? live_rows : count
      end

      # A slice refresh's entry state and key sets — what refresh_source!
      # reads before its first write: whether it heals (+healing+, the
      # crashed run's +prior_shape+, the exact +heal+ diff), whether it
      # works the load's delta, and the +ids+/+urns+ it rewrites
      # (+slice_ids+ the whole-slice lanes' key set).
      SlicePlan = Data.define(:healing, :prior_shape, :use_delta, :heal, :ids, :urns, :slice_ids)

      def slice_plan(catalog, fulltext, slug:, source_id:, delta: nil)
        # P111-1b: a refresh entered over an unfinished marker is a HEAL —
        # the prior run crashed mid-slice, so a load delta cannot cover the
        # crashed run's missing work. The crashed run's recorded transaction
        # SHAPE decides how its lemma census heals (CENSUS_BASELINES_TABLE
        # note) — never by an absolute corpus re-census.
        # (The slice_behind? case — a landed load whose reindex never
        # started — heals through the runner instead: it passes delta nil,
        # which takes the full-slice path here. Probing behind-ness at this
        # depth would misread every content-adding refresh, whose new max
        # id is legitimately unindexed on entry.)
        healing = slice_pending?(fulltext, slug)
        prior_shape = (slice_shape(fulltext, slug) if healing)
        use_delta = !delta.nil? && !delta.overflowed? && !healing
        # The exact heal (ROW_SHAS_TABLE note): with the sidecar on hand the
        # fts+lemma grain re-does exactly the drifted rows. EVERY other lane
        # keeps its whole-slice heal on +slice_ids+: the cjk and trigram
        # lanes carry no sidecar (the asymmetry is deliberate — the main
        # index's multi-GB churn is what the sidecar kills; the cjk lane is
        # ~2.3 GB and governed), and the coverage/annotation lanes write
        # after the fts+lemma batches, so a current sidecar sha says
        # nothing about them.
        heal = (exact_heal_diff(catalog, fulltext, source_id) if healing)
        ids, urns =
          if use_delta
            [delta.changed_ids, delta.changed_urns.to_a]
          elsif heal
            [heal.changed_ids, heal.changed_urns]
          else
            source_passage_keys(catalog, source_id)
          end
        SlicePlan.new(healing: healing, prior_shape: prior_shape, use_delta: use_delta, heal: heal,
                      ids: ids, urns: urns, slice_ids: heal ? heal.slice_ids : ids)
      end

      # == The wave refresh: one shadow pass for many sources
      #
      # The economics: an over-budget slice pays a FULL-CORPUS shadow pass
      # (the shadow holds every indexed row, not just the refreshed
      # source's — ~25-30 min measured at the live corpus scale), so N
      # deferred sources (index_policy: deferred) refreshed one after the
      # other pay N corpus passes for what is one rebuild's worth of
      # passages_fts content. refresh_sources! refreshes a WAVE of sources
      # so that an over-budget passages_fts write happens AT MOST ONCE:
      #
      #   1. every member's slice_plan is taken first (its own entry state —
      #      heal or not — before the wave touches anything);
      #   2. the wave's write volume (the members' summed key sets) is
      #      measured against +row_budget+ — a wave of individually small
      #      slices whose union is over budget still takes the shadow, since
      #      N in-place writes summing past the budget are exactly the churn
      #      the budget exists to stop;
      #   3. over budget, with the sidecar complete OUTSIDE the wave
      #      (shadow_ready? over the members' ids), ONE shadow is built whose
      #      membership is the union of every non-member's recorded rows and
      #      every member's live rows, and swapped in once (stage
      #      "fts_shadow", scope "corpus" — the pass is corpus-sized and
      #      belongs to no one member);
      #   4. each member then runs refresh_source! with its plan and
      #      +fts_prebuilt+ — its lemma/sidecar/aggregate/lane stages in
      #      place, per source, with their per-slug stage timings — exactly
      #      the single-source shadow path minus its own build.
      #
      # Crash honesty (the SHADOW_TABLE note, wave-wide): the orphan shadow
      # is dropped at entry; every member not already pending is marked
      # pending ("atomic" — no lemma write has happened, so a heal's own
      # delta is exact) BEFORE the build, which precedes every destructive
      # write; a member already pending keeps its recorded shape. A death
      # mid-build leaves the old table serving; a death after the swap
      # leaves the index AHEAD of every unrun member's sidecar, never
      # behind, with its pending marker standing for the next refresh to
      # heal. Over budget but with an incomplete sidecar outside the wave,
      # the wave says so and each member refreshes on its own path (its
      # own shadow decision and fallback, the documented contract).
      #
      # A single slug is refresh_source! unchanged. The wave works whole
      # slices (no load delta — the `index refresh` grain). +opts+ go to
      # every member's refresh_source!, +member_opts+ ({ slug => kwargs })
      # to that member's alone (a dictionary's reflexes_changed). Returns
      # { slug => the source's live passage count }.
      def refresh_sources!(catalog:, fulltext:, slugs:, row_budget: IN_PLACE_ROW_BUDGET, ledger: nil,
                           progress: nil, member_opts: {}, **opts)
        slugs = slugs.uniq
        each_member = lambda do |slug, **extra|
          refresh_source!(catalog: catalog, fulltext: fulltext, slug: slug, row_budget: row_budget,
                          ledger: ledger, progress: progress, **opts, **member_opts.fetch(slug, {}), **extra)
        end
        return slugs.to_h { |slug| [slug, each_member.call(slug)] } if slugs.size < 2

        unless incremental_ready?(fulltext)
          # The first member's refresh falls back to the full rebuild,
          # which indexes every member at once.
          first = each_member.call(slugs.first)
          return slugs.to_h { |slug| [slug, slug == slugs.first ? first : source_live_count(catalog, slug)] }
        end

        source_ids = catalog[:sources].where(slug: slugs).to_hash(:slug, :id)
        members = slugs.select { |slug| source_ids[slug] }
        plans = members.to_h do |slug|
          [slug, slice_plan(catalog, fulltext, slug: slug, source_id: source_ids[slug])]
        end
        wave = wave_shadow?(catalog, fulltext, plans, source_ids, row_budget, progress: progress)
        build_wave_shadow!(catalog, fulltext, plans, source_ids, row_budget, ledger: ledger, progress: progress) if
          wave
        slugs.to_h do |slug|
          extra = plans.key?(slug) ? { plan: plans[slug], fts_prebuilt: wave } : {}
          [slug, each_member.call(slug, **extra)]
        end
      end

      # Whether the wave's passages_fts write goes to ONE shadow
      # (refresh_sources! note): more than one member, the summed volume
      # over budget, the contentless shape, and a sidecar complete enough
      # to name every non-member's membership — else announced, per source.
      def wave_shadow?(catalog, fulltext, plans, source_ids, row_budget, progress: nil)
        volume = plans.values.sum { |plan| plan.ids.size }
        return false unless plans.size > 1 && volume > row_budget && fts_contentless?(fulltext)
        return true if shadow_ready?(catalog, fulltext, plans.keys.map { |slug| source_ids[slug] })

        progress&.stage("index wave: #{plans.keys.join(', ')} — #{volume} rows over the #{row_budget}-row " \
                        "in-place budget, but the row-sha sidecar incomplete outside the wave (a slice " \
                        "predating it): each source refreshes on its own path")
        false
      end

      def build_wave_shadow!(catalog, fulltext, plans, source_ids, row_budget, ledger: nil, progress: nil)
        volume = plans.values.sum { |plan| plan.ids.size }
        fulltext.drop_table?(SHADOW_TABLE) # a killed build's orphan
        plans.each { |slug, plan| mark_slice_pending!(fulltext, slug, shape: "atomic") unless plan.healing }
        timed_sync_stage(ledger, "corpus", "fts_shadow",
                         "index wave: #{plans.keys.join(', ')} — passages_fts shadow build (#{volume} rows " \
                         "over the #{row_budget}-row in-place budget: ONE append-only pass for the wave, " \
                         "swapped in whole)", progress, rows_of: :itself.to_proc) do
          written = build_fts_shadow!(catalog: catalog, fulltext: fulltext,
                                      source_id: plans.keys.map { |slug| source_ids[slug] }, progress: progress)
          swap_fts_shadow!(fulltext)
          written
        end
      end

      # P78-r3: announce with the last sync's estimate, run, record the
      # wall time (kind "sync"). A nil ledger announces bare and records
      # nothing — the rebuild path keeps its own profiler lane. The stage
      # must DECLARE its cost class first (Store::IndexCostClasses — the
      # proportionality law): an undeclared stage refuses to time.
      # +rows_of+ (optional) maps the block's result to the stage's work
      # size, recorded beside the seconds so a later estimate scales by
      # drift (the shadow builds: the rows they wrote).
      # Split note: also times the bulk-slice merge stage; kept with its primary user (refresh_source!).
      def timed_sync_stage(ledger, scope, stage, label, progress, rows_of: nil, &)
        IndexCostClasses.for("sync", stage)
        eta = ledger && Nabu::Eta.for(ledger, kind: "sync", scope: scope, stage: stage)
        progress&.stage(label, eta: eta)
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        result = yield
        if ledger
          StageTimings.record!(ledger, kind: "sync", scope: scope, stage: stage,
                                       seconds: Process.clock_gettime(Process::CLOCK_MONOTONIC) - started,
                                       rows: rows_of&.call(result))
        end
        result
      end

      # -- refresh_source! internals (P26-5) ---------------------------------

      # Every table refresh_source! maintains must already exist in its
      # CURRENT shape (the tier column is the probe precedent: a pre-tier
      # lemma table cannot take tiered inserts). Anything missing → the
      # caller falls back to the full rebuild, which creates them all.
      def incremental_ready?(fulltext)
        [TABLE, LEMMA_TABLE, LemmaFrequencies::TABLE, TRIGRAM_TABLE, TRIGRAM_SCOPE_TABLE,
         AlignmentIndexer::TABLE, ReflexRootsIndexer::TABLE, ReflexRootsIndexer::STATS_TABLE]
          .all? { |table| fulltext.table_exists?(table) } &&
          fulltext[LEMMA_TABLE].columns.include?(:tier)
      end

      # Full alignment rebuild, but ONLY when the source holds a document the
      # registry names as a witness — the index is registry-scoped (157k rows
      # live), so regenerating it whole is cheap and keeps AlignmentIndexer
      # the single owner of its semantics; every other sync skips it.
      # A changed registry (AlignmentIndexer.registry_changed?) also counts a
      # source whose documents the STANDING refs index, so a witness the edit
      # dropped is cleared by its own source's next sync.
      def refresh_alignment(catalog, fulltext, registry, source_id)
        return if registry.nil?

        changed = AlignmentIndexer.registry_changed?(fulltext, registry)
        return unless alignment_witness_source?(catalog, registry, source_id) ||
                      (changed && alignment_indexed_source?(catalog, fulltext, source_id))

        AlignmentIndexer.rebuild!(catalog: catalog, fulltext: fulltext, registry: registry)
      end

      # The registry-only path (the sync skip, SyncRunner): a sync whose load
      # changed no passage byte skips the whole slice, but alignment_refs =
      # f(catalog, config/alignments.yml) — so when the registry's
      # fingerprint (AlignmentIndexer.fingerprint) differs from the stamped
      # one, rebuild the alignment refs
      # (and only them) for a source the old or new registry touches. Returns
      # the ref count when it rebuilt, nil when there was nothing to do (an
      # unchanged registry, an uninvolved source, or a fulltext predating the
      # alignment table — the full rebuild owns that).
      def refresh_alignment_registry!(catalog:, fulltext:, slug:, alignments:)
        return nil if alignments.nil? || !fulltext.table_exists?(AlignmentIndexer::TABLE)
        return nil unless AlignmentIndexer.registry_changed?(fulltext, alignments)

        source_id = catalog[:sources].where(slug: slug).get(:id) or return nil
        return nil unless alignment_witness_source?(catalog, alignments, source_id) ||
                          alignment_indexed_source?(catalog, fulltext, source_id)

        AlignmentIndexer.rebuild!(catalog: catalog, fulltext: fulltext, registry: alignments)
      end

      def alignment_witness_source?(catalog, registry, source_id)
        witness_urns = registry.works.flat_map(&:witnesses).flat_map(&:document_urns)
        !witness_urns.empty? && !catalog[:documents].where(source_id: source_id, urn: witness_urns).empty?
      end

      # The standing refs name few documents (one per witness book), so the
      # distinct urn list is small.
      def alignment_indexed_source?(catalog, fulltext, source_id)
        return false unless fulltext.table_exists?(AlignmentIndexer::TABLE)

        urns = fulltext[AlignmentIndexer::TABLE].distinct.select_map(:document_urn)
        !urns.empty? && !catalog[:documents].where(source_id: source_id, urn: urns).empty?
      end

      # The source's live passage count (two-level visibility) — what the
      # rebuild-fallback path reports, keeping "indexed N" per-source honest.
      def source_live_count(catalog, slug)
        catalog[:passages]
          .join(:documents, id: Sequel[:passages][:document_id])
          .join(:sources, id: Sequel[:documents][:source_id])
          .where(Sequel[:passages][:withdrawn] => false, Sequel[:documents][:withdrawn] => false)
          .where(Sequel[:sources][:slug] => slug)
          .count
      end
    end
  end
end

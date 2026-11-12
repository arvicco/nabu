# frozen_string_literal: true

module Nabu
  module Store
    # The lane-coverage check behind `nabu index doctor` (the Nov 2026
    # crash-loss incident): for each lane, the CONFIG FLAGS (sources.yml
    # `cjk_index:` / `fuzzy_index:`) vs the lane's BUILT SCOPE (its scope
    # table — what the last build indexed) vs per-source ROW PRESENCE.
    #
    # Why three-way: the rebuild that died mid-reindex on 2026-11-10 left
    # the cjk lane empty with an empty scope while all fourteen flags
    # stood. Every reader degraded politely ("no lane hits"), so the loss
    # read as a design gap for days. Any one disagreement between the
    # three is now a finding the doctor prints LOUDLY:
    #
    #   :absent    — the lane table is missing while sources are flagged;
    #   :unbuilt   — a flagged source is not in the built scope (the lane
    #                predates the flag, or a build lost it);
    #   :deflagged — a scope row whose flag is gone (the next lane build
    #                drops it — honest staleness, still worth a line);
    #   :empty     — flagged AND in scope, yet ZERO rows for the source.
    #
    # Row presence is a bounded probe per source, never a census: on the
    # cjk lane one indexed MATCH of the source's sentinel token (the
    # lane carries the main table's `source` column) with LIMIT 1; on the
    # trigram lane (contentful, no source column, rowid not the passage
    # id) a passage_id range filter over the source's live id span, LIMIT
    # 1 — it stops at the first hit, so its full cost is paid only in the
    # finding case. The span probe can be fooled by ANOTHER fuzzy source's
    # rows interleaved inside the span (a false "present", never a false
    # alarm) — the price of not scanning; the cjk probe is exact. Reads
    # only; read-only gauge code like FtsStructure.
    module LaneCoverage
      Finding = Data.define(:lane, :slug, :problem) do
        def message
          case problem
          when :absent then "#{slug} is flagged but the #{lane} lane is ABSENT — no lane search at all"
          when :unbuilt then "#{slug} is flagged but absent from the built scope — rebuild the lane"
          when :deflagged then "#{slug} is in the built scope but no longer flagged — the next lane build drops it"
          when :empty then "#{slug} is flagged and in scope but has ZERO lane rows — lane search is silently empty"
          end
        end
      end

      module_function

      # Every finding across both lanes, cjk first, slugs sorted.
      def findings(catalog:, fulltext:, cjk_slugs:, fuzzy_slugs:)
        lane_findings(catalog, fulltext, :cjk, Indexer::CJK_TABLE, Indexer::CJK_SCOPE_TABLE, cjk_slugs) +
          lane_findings(catalog, fulltext, :trigram, Indexer::TRIGRAM_TABLE, Indexer::TRIGRAM_SCOPE_TABLE,
                        fuzzy_slugs)
      end

      # One summary line per lane for the doctor's header (flag / scope
      # counts), nil when the lane is absent.
      def summary(fulltext, scope_table, flags)
        return nil unless fulltext.table_exists?(scope_table)

        "#{Array(flags).size} flagged · #{fulltext[scope_table].count} in the built scope"
      end

      def lane_findings(catalog, fulltext, lane, table, scope_table, flags)
        flags = Array(flags).sort
        unless fulltext.table_exists?(table) && fulltext.table_exists?(scope_table)
          return flags.map { |slug| Finding.new(lane: lane, slug: slug, problem: :absent) }
        end

        scope = fulltext[scope_table].select_map(:slug).sort
        found = (flags - scope).map { |slug| Finding.new(lane: lane, slug: slug, problem: :unbuilt) }
        found += (scope - flags).map { |slug| Finding.new(lane: lane, slug: slug, problem: :deflagged) }
        (flags & scope).each do |slug|
          found << Finding.new(lane: lane, slug: slug, problem: :empty) unless rows?(catalog, fulltext, lane, slug)
        end
        found.sort_by(&:slug)
      end

      def rows?(catalog, fulltext, lane, slug)
        if lane == :cjk
          token = Indexer.source_token(slug)
          return !fulltext[Indexer::CJK_TABLE].where(Sequel.lit("passages_cjk MATCH ?", %(source : "#{token}")))
                                              .limit(1).select_map(Sequel.lit("rowid")).empty?
        end

        _count, max_id = Indexer.source_live_stats(catalog, slug)
        return false if max_id.nil?

        min_id = live_min_id(catalog, slug)
        !fulltext[Indexer::TRIGRAM_TABLE].where(passage_id: min_id..max_id).limit(1).select_map(:passage_id).empty?
      end

      def live_min_id(catalog, slug)
        catalog[:passages]
          .join(:documents, id: Sequel[:passages][:document_id])
          .join(:sources, id: Sequel[:documents][:source_id])
          .where(Sequel[:passages][:withdrawn] => false, Sequel[:documents][:withdrawn] => false)
          .where(Sequel[:sources][:slug] => slug)
          .min(Sequel[:passages][:id])
      end
    end
  end
end

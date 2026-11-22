# frozen_string_literal: true

# Nabu::Store::Indexer — passage_signs and the sign-coverage twins.
# A partial of lib/nabu/store/indexer.rb, which loads it.
module Nabu
  module Store
    module Indexer
      module_function

      # -- passage_signs (P77-r16, the sign-coverage twins) ------------------

      # Drop and rebuild both sign tables: pass 1 tallies the postings
      # (rarity source + corpus census), pass 2 writes the coverage rows.
      # Two streaming passes over SIGN_SOURCES only; nil sign_list (no
      # osl synced) leaves both tables absent — the honest non-answer.
      # BOTH passes announce themselves and tick (owner ruling 2026-08-18:
      # "all parsing passes should INDICATE what the hell it's doing" —
      # this is hours-scale work on the live ATF corpora, and it sat
      # silent on its first live firing).
      def rebuild_sign_coverage!(catalog:, fulltext:, sign_list:, progress: nil)
        fulltext.drop_table?(PASSAGE_SIGNS_TABLE)
        fulltext.drop_table?(SIGN_POSTINGS_TABLE)
        return 0 if sign_list.nil?

        inventory = Nabu::SignInventory.new(sign_list)
        create_sign_postings_table(fulltext)
        create_passage_signs_table(fulltext)
        # P87-4 (Q52b): ONE tokenization feeds BOTH tables — the P77-r16
        # shape tokenized the same 4.36M ATF documents twice (the
        # 2026-08-29 profile: 98m census + 66m re-tokenize). Passage rows
        # land rank-less in the census pass; only r1..r4 need the COMPLETED
        # census, and they stamp in a cheap by-rowid update sweep after.
        progress&.stage("sign coverage: tokenizing #{SIGN_SOURCES.join('/')} " \
                        "(single pass — postings census + passage index)")
        posts = Hash.new(0)
        seen = 0
        count = 0
        batch = []
        each_sign_passage(catalog, inventory: inventory) do |row, line|
          progress&.load_tick(seen, 0) if ((seen += 1) % TICK_EVERY).zero?
          line.signs.each { |name| posts[[row.fetch(:source_id), name, row[:language]]] += 1 }
          next if line.signs.empty?

          sorted = line.signs.sort
          batch << { rowid: row.fetch(:passage_id), source_id: row.fetch(:source_id),
                     language: row[:language], nsigns: sorted.size, signs: sorted.join(SIGN_SEP),
                     strays: line.strays, r1: nil, r2: nil, r3: nil, r4: nil }
          next if batch.size < BATCH_SIZE

          fulltext[PASSAGE_SIGNS_TABLE].multi_insert(batch)
          count += batch.size
          batch = []
        end
        unless batch.empty?
          fulltext[PASSAGE_SIGNS_TABLE].multi_insert(batch)
          count += batch.size
        end
        fulltext.transaction do
          posts.each_slice(BATCH_SIZE) do |post_batch|
            fulltext[SIGN_POSTINGS_TABLE].multi_insert(
              post_batch.map do |(source_id, sign, language), docs|
                { source_id: source_id, sign: sign, language: language, docs: docs }
              end
            )
          end
        end
        stamp_sign_ranks(fulltext, posts, progress: progress)
        index_passage_signs(fulltext)
        count
      end

      # The r1..r4 rarity stamp (P87-4): the same [global docs-rank, name]
      # ordering pass 2 used, computed from the census just taken and
      # applied by rowid over the rank-less rows — string splits and point
      # updates, never a second tokenization. Runs BEFORE
      # index_passage_signs, so the updates pay no index maintenance.
      def stamp_sign_ranks(fulltext, posts, progress: nil)
        progress&.stage("sign coverage: stamping rarity ranks")
        totals = Hash.new(0)
        posts.each { |(_, name, _), docs| totals[name] += docs }
        last = -1
        seen = 0
        loop do
          page = fulltext[PASSAGE_SIGNS_TABLE].where { rowid > last }.order(:rowid)
                                              .limit(BATCH_SIZE).select_map(%i[rowid signs])
          break if page.empty?

          fulltext.transaction do
            page.each do |rowid, signs|
              rarest = signs.split(SIGN_SEP)
                            .min_by(RAREST_SLOTS) { |name| [totals.fetch(name, -1), name] }
              fulltext[PASSAGE_SIGNS_TABLE].where(rowid: rowid)
                                           .update(r1: rarest[0], r2: rarest[1],
                                                   r3: rarest[2], r4: rarest[3])
            end
          end
          last = page.last[0]
          seen += page.size
          progress&.load_tick(seen, 0)
        end
      end

      # One progress tick per this many sign passages — frequent enough
      # that the terminal counter visibly moves, cheap against the
      # tokenize cost per row.
      TICK_EVERY = 2_000

      def create_sign_postings_table(fulltext)
        fulltext.create_table(SIGN_POSTINGS_TABLE) do
          Integer :source_id, null: false
          String :sign, null: false
          String :language
          Integer :docs, null: false
          index :sign
          index :source_id
        end
      end

      def create_passage_signs_table(fulltext)
        fulltext.create_table(PASSAGE_SIGNS_TABLE) do
          Integer :rowid, primary_key: true # = passages.id, the FTS rowid convention
          Integer :source_id, null: false
          String :language
          Integer :nsigns, null: false
          String :signs, null: false # SIGN_SEP-joined sorted distinct names
          Integer :strays, null: false
          String :r1
          String :r2
          String :r3
          String :r4
        end
      end

      def index_passage_signs(fulltext)
        fulltext.alter_table(PASSAGE_SIGNS_TABLE) do
          add_index :r1
          add_index :r2
          add_index :r3
          add_index :r4
          add_index :source_id
        end
      end

      # The coverage-row stream (whole SIGN_SOURCES scope, or one source's
      # slice). Rarity = ascending global passage total from the postings;
      # an unseen sign ranks rarest. Sign-less rows (all numbers, or all
      # strays) are not indexed — they can never be candidates.
      def passage_signs_rows(catalog, fulltext, sign_list, source_id: nil, inventory: nil, progress: nil,
                             ids: nil)
        inventory ||= Nabu::SignInventory.new(sign_list)
        ranks = sign_rarity_ranks(fulltext)
        seen = 0
        Enumerator.new do |y|
          each_sign_passage(catalog, source_id: source_id, inventory: inventory, ids: ids) do |row, line|
            progress&.load_tick(seen, 0) if ((seen += 1) % TICK_EVERY).zero?
            next if line.signs.empty?

            sorted = line.signs.sort
            rarest = sorted.min_by(RAREST_SLOTS) { |name| [ranks.fetch(name, -1), name] }
            y << { rowid: row.fetch(:passage_id), source_id: row.fetch(:source_id),
                   language: row[:language], nsigns: sorted.size, signs: sorted.join(SIGN_SEP),
                   strays: line.strays, r1: rarest[0], r2: rarest[1], r3: rarest[2], r4: rarest[3] }
          end
        end
      end

      def write_passage_signs(fulltext, rows)
        count = 0
        fulltext.transaction do
          rows.each_slice(BATCH_SIZE) do |batch|
            fulltext[PASSAGE_SIGNS_TABLE].multi_insert(batch)
            count += batch.size
          end
        end
        count
      end

      def sign_rarity_ranks(fulltext)
        return {} unless fulltext.table_exists?(SIGN_POSTINGS_TABLE)

        fulltext[SIGN_POSTINGS_TABLE].group(:sign).select(:sign) { sum(:docs).as(:total) }
                                                  .to_h { |row| [row[:sign], row[:total]] }
      end

      # Stream the LIVE passages of the sign-indexed sources (or one of
      # them; +ids:+ (P112-1) narrows to exactly those passage ids),
      # yielding [row, SignInventory::Line] for each passage whose
      # text tokenizes at all.
      def each_sign_passage(catalog, source_id: nil, inventory: nil, ids: nil, &block)
        source_ids = sign_source_ids(catalog)
        source_ids &= [source_id] if source_id
        return if source_ids.empty?

        scope = live_passages(catalog)
                .where(Sequel[:documents][:source_id] => source_ids)
                .select(Sequel[:passages][:id].as(:passage_id),
                        Sequel[:passages][:text_search].as(:text_normalized), Sequel[:passages][:language],
                        Sequel[:documents][:source_id].as(:source_id))
                .order(Sequel[:passages][:id])
        if ids
          ids_scoped(scope, ids).each { |row| yield_sign_line(inventory, row, &block) }
        else
          scope.paged_each { |row| yield_sign_line(inventory, row, &block) }
        end
      end

      def yield_sign_line(inventory, row)
        line = inventory.scan(row.fetch(:text_normalized))
        yield(row, line) if line
      end

      def sign_source_ids(catalog)
        catalog[:sources].where(slug: SIGN_SOURCES).select_map(:id)
      end
    end
  end
end

# frozen_string_literal: true

# Nabu::Store::Indexer — char postings and passage_chars (full and delta grain).
# A partial of lib/nabu/store/indexer.rb, which loads it.
module Nabu
  module Store
    module Indexer
      module_function

      def create_char_postings_table(fulltext)
        fulltext.create_table(CHAR_POSTINGS_TABLE) do
          Integer :source_id, null: false
          String :char, null: false
          String :language
          Integer :docs, null: false
          index :char
          index :source_id
        end
      end

      # +stamp_class+: only a FULL build (fresh table) stamps the class
      # sentinel — a per-source slice refresh must never upgrade a legacy
      # (Han-only) index's stamp, because the class describes the WHOLE
      # index and only a full re-accumulation makes the claim true.
      def write_char_postings(fulltext, chars, stamp_class: false)
        chars.each_slice(BATCH_SIZE) do |batch|
          fulltext[CHAR_POSTINGS_TABLE].multi_insert(
            batch.map do |(source_id, char, language), docs|
              { source_id: source_id, char: char, language: language, docs: docs }
            end
          )
        end
        return unless stamp_class

        fulltext[CHAR_POSTINGS_TABLE].insert(
          source_id: POSTINGS_CLASS_SOURCE, char: "", language: POSTINGS_CLASS, docs: 0
        )
      end

      # The standalone postings (re)build — ONE lean streaming pass (three
      # columns, no annotations_json) over the live passages. Used to
      # bootstrap a pre-P65 fulltext file without paying a full FTS rebuild,
      # and by refresh_source! when the table is absent.
      def rebuild_char_postings!(catalog:, fulltext:)
        fulltext.drop_table?(CHAR_POSTINGS_TABLE)
        create_char_postings_table(fulltext)
        chars = Hash.new(0)
        live_passages(catalog)
          .select(Sequel[:passages][:text_search].as(:text_normalized), Sequel[:passages][:language],
                  Sequel[:documents][:source_id].as(:source_id))
          .each { |row| accumulate_char_postings(chars, row) }
        fulltext.transaction { write_char_postings(fulltext, chars, stamp_class: true) }
        chars.size
      end

      # P72-1: drop and rebuild the whole coverage index — one streaming
      # pass over the live passages (needs the postings for rarity ranks).
      def rebuild_passage_chars!(catalog:, fulltext:)
        fulltext.drop_table?(PASSAGE_CHARS_TABLE)
        fulltext.create_table(PASSAGE_CHARS_TABLE) do
          Integer :rowid, primary_key: true # = passages.id, the FTS rowid convention
          Integer :source_id, null: false
          String :language
          Integer :nchars, null: false
          String :chars, null: false
          String :r1
          String :r2
          String :r3
          String :r4
        end
        write_passage_chars(fulltext, passage_chars_rows(catalog, fulltext))
        fulltext.alter_table(PASSAGE_CHARS_TABLE) do
          add_index :r1
          add_index :r2
          add_index :r3
          add_index :r4
          add_index :source_id
        end
      end

      # The row stream for the coverage index (whole corpus, one source's
      # slice, or — +ids:+ (P112-1) — exactly the delta's upserted rows).
      # Rarity rank = ascending global docs total from the postings;
      # a char the postings have not seen ranks rarest of all.
      def passage_chars_rows(catalog, fulltext, source_id: nil, ids: nil)
        ranks = char_rarity_ranks(fulltext)
        scope = live_passages(catalog)
        scope = scope.where(Sequel[:documents][:source_id] => source_id) if source_id
        scope = scope.select(Sequel[:passages][:id].as(:passage_id),
                             Sequel[:passages][:text_search].as(:text_normalized), Sequel[:passages][:language],
                             Sequel[:documents][:source_id].as(:source_id))
        scope = ids_scoped(scope, ids) if ids
        Enumerator.new do |y|
          scope.each do |row|
            text = row.fetch(:text_normalized).to_s
            next unless text.match?(HAN)

            distinct = text.scan(HAN).uniq.sort
            rarest = distinct.min_by(RAREST_SLOTS) { |c| [ranks.fetch(c, -1), c] }
            y << { rowid: row.fetch(:passage_id), source_id: row.fetch(:source_id),
                   language: row[:language], nchars: distinct.size, chars: distinct.join,
                   r1: rarest[0], r2: rarest[1], r3: rarest[2], r4: rarest[3] }
          end
        end
      end

      def write_passage_chars(fulltext, rows)
        fulltext.transaction do
          rows.each_slice(BATCH_SIZE) { |batch| fulltext[PASSAGE_CHARS_TABLE].multi_insert(batch) }
        end
      end

      # char -> ascending global docs total (smaller = rarer), read from the
      # postings written moments earlier in the same pass.
      def char_rarity_ranks(fulltext)
        return {} unless fulltext.table_exists?(CHAR_POSTINGS_TABLE)

        fulltext[CHAR_POSTINGS_TABLE].group(:char).select(:char) { sum(:docs).as(:total) }
                                                  .to_h { |row| [row[:char], row[:total]] }
      end

      # -- char postings at the delta grain (the incrementality review) ------
      #
      # char_postings is DECOMPOSABLE: per (source, char, language), the
      # count of the source's live passages carrying that char — a sum over
      # rows. So a delta moves it exactly by subtracting the changed rows'
      # OLD contribution and adding the upserted rows' new one (the insert
      # pass already accumulates the latter), replacing the whole-source
      # catalog scan that used to re-run on EVERY delta (the review's
      # "recomputed whole, re-done next slice"). The hard half is the OLD
      # contribution, read BEFORE the slice's first destructive write:
      #
      #   - a changed row the sidecar does not record was never indexed (an
      #     insert, or a re-entry whose sha left at withdrawal): nothing to
      #     subtract;
      #   - a recorded row whose sha still matches the catalog (a
      #     withdrawal, an unchanged re-entry): the catalog holds exactly
      #     the indexed text (the sha covers text AND language) — subtract
      #     its posted chars;
      #   - a recorded row whose sha moved (a REVISION): the replaced text is
      #     gone. passage_chars still holds the row's old distinct HAN set,
      #     and when every char the source posts is Han (a Han-pure source)
      #     that set IS its old posted set — subtract it. Otherwise the
      #     grain is unsound for this source.
      #
      # Unsound (a mixed-script revision, a slice predating the sidecar, a
      # source already flagged) returns nil, and the delta flags the
      # source's postings stale (Store::StaleAggregates) — the maintenance
      # rail recomputes them; nothing O(source) runs inline.
      POSTINGS_AGGREGATE = "char_postings"

      def char_postings_basis(catalog, fulltext, source_id, slug, ids)
        return nil unless fulltext.table_exists?(CHAR_POSTINGS_TABLE) && fulltext.table_exists?(ROW_SHAS_TABLE)
        return nil if StaleAggregates.stale?(fulltext, aggregate: POSTINGS_AGGREGATE, scope: slug)

        posted = fulltext[CHAR_POSTINGS_TABLE].where(source_id: source_id)
        # A slice predating the sidecar records nothing — no row could be
        # told from an insert.
        return nil if fulltext[ROW_SHAS_TABLE].where(source_id: source_id).empty? && !posted.empty?

        han_pure = posted.select_map(:char).all? { |char| char.match?(HAN) }
        decrements = Hash.new(0)
        ids.to_a.each_slice(BATCH_SIZE) do |batch|
          revised = old_postings_by_sidecar(catalog, fulltext, batch, decrements)
          next if revised.empty?
          return nil unless han_pure && fulltext.table_exists?(PASSAGE_CHARS_TABLE)

          fulltext[PASSAGE_CHARS_TABLE].where(rowid: revised).select(:chars, :language).each do |row|
            row[:chars].each_char { |char| decrements[[source_id, char, row[:language]]] += 1 }
          end
        end
        decrements
      end

      # One batch's sidecar-vouched old contribution, accumulated into
      # +decrements+; returns the batch's REVISED rowids (recorded, sha
      # moved) for the caller's Han-pure rule.
      def old_postings_by_sidecar(catalog, fulltext, batch, decrements)
        recorded = fulltext[ROW_SHAS_TABLE].where(rowid: batch).select_hash(:rowid, :sha)
        return [] if recorded.empty?

        revised = []
        catalog[:passages].join(:documents, id: Sequel[:passages][:document_id])
                          .where(Sequel[:passages][:id] => recorded.keys)
                          .select(Sequel[:passages][:id].as(:passage_id),
                                  Sequel[:passages][:text_search].as(:text_normalized),
                                  Sequel[:passages][:language], Sequel[:passages][:content_sha256],
                                  Sequel[:documents][:source_id].as(:source_id))
                          .each do |row|
          if row_sha(row[:content_sha256]).b == recorded.fetch(row[:passage_id]).to_s.b
            accumulate_char_postings(decrements, row)
          else
            revised << row[:passage_id]
          end
        end
        revised
      end

      # Apply a delta's arithmetic to the source's postings rows, or flag
      # them stale when +basis+ is nil (char_postings_basis note). Rows
      # reaching zero are pruned — the same row set a full recompute mints.
      def apply_char_postings_delta!(fulltext, slug:, source_id:, basis:, increments:)
        if basis.nil?
          StaleAggregates.mark!(fulltext, aggregate: POSTINGS_AGGREGATE, scope: slug,
                                          reason: "a delta's old contribution was unrecoverable at the row grain")
          return
        end

        (basis.keys | increments.keys).each do |key|
          net = increments.fetch(key, 0) - basis.fetch(key, 0)
          upsert_char_posting(fulltext, source_id, key, net) unless net.zero?
        end
      end

      def upsert_char_posting(fulltext, source_id, key, net)
        _source, char, language = key
        scope = fulltext[CHAR_POSTINGS_TABLE].where(source_id: source_id, char: char, language: language)
        current = scope.get(:docs)
        total = (current || 0) + net
        if total <= 0
          scope.delete
        elsif current
          scope.update(docs: total)
        else
          fulltext[CHAR_POSTINGS_TABLE].insert(source_id: source_id, char: char, language: language, docs: total)
        end
      end

      # The maintenance rail's recompute of ONE source's postings (the
      # O(source) re-read the delta grain refuses to run inline): swap the
      # source's rows for a fresh accumulation, clear its stale flag.
      # Returns the rows written.
      def recompute_char_postings!(catalog:, fulltext:, slug:)
        source_id = catalog[:sources].where(slug: slug).get(:id)
        fulltext.transaction do
          if source_id && fulltext.table_exists?(CHAR_POSTINGS_TABLE)
            fulltext[CHAR_POSTINGS_TABLE].where(source_id: source_id).delete
            chars = source_char_postings(catalog, source_id)
            write_char_postings(fulltext, chars)
          end
          StaleAggregates.clear!(fulltext, aggregate: POSTINGS_AGGREGATE, scope: slug)
          chars&.size || 0
        end
      end

      # The char-postings aggregate for ONE source, recomputed from a lean
      # three-column catalog scan — the heal path and the maintenance
      # rail's recompute; the delta grain never calls it.
      def source_char_postings(catalog, source_id)
        chars = Hash.new(0)
        live_passages(catalog)
          .where(Sequel[:documents][:source_id] => source_id)
          .select(Sequel[:passages][:text_search].as(:text_normalized), Sequel[:passages][:language],
                  Sequel[:documents][:source_id].as(:source_id))
          .each { |row| accumulate_char_postings(chars, row) }
        chars
      end
    end
  end
end

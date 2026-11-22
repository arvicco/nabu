# frozen_string_literal: true

require_relative "../errors"

module Nabu
  module Store
    # The main fulltext lane's EXACT token streams, asked of SQLite itself
    # (the reuse-postings census, Nabu::ReuseCensus — both sides of its
    # fold-both-sides contract).
    #
    # == Why SQLite, not a Ruby regex
    #
    # The postings engine must find exactly the passages a quoted FTS5
    # phrase MATCH finds, and that is decided by passages_fts's tokenizer
    # (`unicode61 remove_diacritics 2`), not by the Ruby gram builder.
    # Probed on the bundled 3.54.1 engine, the two disagree in ways that
    # move matches: unicode61 case-folds and maps final sigma (λόγος indexes
    # as λόγοσ), strips combining DIACRITICS (U+0300–U+036F) inside a
    # token while treating other combining marks (Hebrew points, the
    # Devanagari virama) as SEPARATORS, folds fullwidth Latin, and keeps
    # private-use characters as token characters. A hand-rolled emulation
    # would drift from that table on every edge; this class instead feeds
    # text through an in-memory FTS5 table with the SAME tokenizer spec and
    # reads the indexed token stream back out of an fts5vocab 'instance'
    # table — the index's own bytes, so the emulation is the engine.
    #
    # Two uses, one tokenizer: #streams for a passage's indexed stream (the
    # census's main-lane windows) and #fold for the anchor side (a quoted
    # phrase's tokens fold through the same tokenizer at MATCH time, so a
    # gram's probe key is its tokens folded here).
    #
    # The DDL is raw (FTS5 virtual tables have no Sequel DSL — the
    # Indexer's own sanctioned exception); every read and write after it is
    # a dataset. The table is contentless and cleared with FTS5's
    # 'delete-all' command between batches, so it never grows.
    class Fts5Tokens
      # passages_fts's tokenizer, verbatim (Indexer::CREATE_TABLE — pinned
      # equal by fts5_tokens_test, so the two can never drift).
      MAIN_TOKENIZE = "unicode61 remove_diacritics 2"

      # Texts per insert/read round (bounded memory per call).
      BATCH = 2_000

      # Distinct folded tokens memoized per instance (a process-lifetime
      # cache for one census/scoring worker; bounded so a pathological
      # vocabulary cannot grow it without limit).
      FOLD_MEMO_LIMIT = 2_000_000

      def initialize(tokenize: MAIN_TOKENIZE)
        @db = Store.connect("sqlite::memory:")
        @db.run("CREATE VIRTUAL TABLE tok USING fts5(t, content = '', tokenize = '#{tokenize}')")
        @db.run("CREATE VIRTUAL TABLE tok_instance USING fts5vocab(tok, 'instance')")
        @fold = {}
      end

      # The indexed token stream of each text (index-aligned Arrays of
      # folded terms, in token order) — exactly what passages_fts stores
      # for that text.
      def streams(texts)
        out = Array.new(texts.size) { [] }
        texts.each_slice(BATCH).with_index do |slice, round|
          base = round * BATCH
          rows = slice.each_with_index.map { |text, i| { rowid: i + 1, t: text.to_s } }
          positions = Array.new(slice.size) { [] }
          @db.transaction do
            @db[:tok].multi_insert(rows)
            @db[:tok_instance].select(:doc, :offset, :term).each do |row|
              positions[row[:doc] - 1] << [row[:offset], row[:term]]
            end
            @db[:tok].insert(tok: "delete-all")
          end
          positions.each_with_index { |pairs, i| out[base + i] = pairs.sort_by(&:first).map(&:last) }
        end
        out
      end

      # The folded form of each of +tokens+ as a phrase query would
      # tokenize it: a String when the token stays ONE indexed token, nil
      # when the tokenizer splits or drops it (a character Ruby's newer
      # Unicode tables call a letter but SQLite's do not — the postings
      # engine cannot emulate that phrase's arity and counts it instead).
      def fold(tokens)
        missing = tokens.uniq.reject { |token| @fold.key?(token) }
        unless missing.empty?
          @fold.clear if @fold.size + missing.size > FOLD_MEMO_LIMIT
          streams(missing).each_with_index do |stream, i|
            @fold[missing[i]] = stream.size == 1 ? stream.first : nil
          end
        end
        tokens.map { |token| @fold.fetch(token) { fold([token]).first } }
      end

      def close
        @db.disconnect
      end
    end
  end
end

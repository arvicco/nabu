# frozen_string_literal: true

module Nabu
  module Query
    # The fts5vocab document-frequency probe (P42-2) behind the search
    # ubiquitous-term guard: FTS5's `ORDER BY rank` computes bm25 for EVERY
    # row matching the query before LIMIT applies, so a term present in a
    # large fraction of the corpus (الله, και) costs millions of scores per
    # page. Whether a query is in that class is a one-seek question to the
    # index's own vocabulary — this class asks it.
    #
    # == How the vocabulary table is created (and why at query time)
    #
    # `fts5vocab` is a zero-storage virtual table that reads the fts5 index's
    # shadow tables live — it holds no data of its own, needs no reindex, and
    # works over contentful and contentless fts5 tables alike. Created in the
    # connection's TEMP schema (the three-argument form reaches main's
    # passages_fts from temp), it never writes the fulltext FILE's schema, so
    # it works on a READONLY handle too — the MCP server's posture (P8-1).
    # That is why creation happens lazily here, at query time, not in the
    # indexer: there is nothing to persist, and a pre-P42 index probes
    # exactly as well as a fresh one. TEMP tables are PER-CONNECTION, so the
    # create-if-not-exists and the lookups run inside one #synchronize block
    # (one pooled connection) rather than trusting pool affinity.
    #
    # The DDL is a raw-SQL exception of the Indexer's documented kind:
    # virtual-table DDL has no Sequel API. It touches only the temp schema.
    #
    # == The candidate-set ceiling
    #
    # bm25 cost is driven by the CANDIDATE SET — rows matching the WHOLE
    # query. For one variant's implicit-AND terms that set is at most the
    # rarest term's df (a rare term ANDed with a ubiquitous one makes ranking
    # cheap, so the guard must NOT fire on it); the fold variants are ORed in
    # the MATCH, so the union is at most the sum of the per-variant minima.
    # Everything fails OPEN toward ranking: a token the tokenizer would not
    # emit verbatim (a "quoted phrase", a prefix*, punctuation) misses the
    # vocabulary and bounds its variant at 0, so power queries and mistyped
    # terms keep today's ranked behavior; any database error (no fts table
    # yet, an engine without fts5vocab) yields nil and the caller skips the
    # guard entirely.
    class TermFrequency
      VOCAB_TABLE = :passages_fts_vocab

      # The 'row' variant: one row per term, `doc` = number of fts rows
      # containing it — document frequency, exactly the guard's question.
      CREATE_VOCAB = "CREATE VIRTUAL TABLE IF NOT EXISTS temp.#{VOCAB_TABLE} " \
                     "USING fts5vocab('main', 'passages_fts', 'row')".freeze

      def initialize(fulltext:)
        @fulltext = fulltext
      end

      # Upper bound on the rows a ranked MATCH over ORed +variants+ (each an
      # implicit-AND token list, the plain-query shape) would have to score —
      # or nil when the vocabulary cannot be consulted (skip the guard).
      def candidate_ceiling(variants)
        @fulltext.synchronize do
          @fulltext.run(CREATE_VOCAB)
          variants.sum { |variant| variant_ceiling(variant) }
        end
      rescue Sequel::DatabaseError
        nil
      end

      private

      # min df across the variant's whitespace tokens (0 for an empty or
      # vocabulary-missing token — fail-open, see the class note).
      def variant_ceiling(variant)
        variant.split.map { |token| document_frequency(token) }.min || 0
      end

      def document_frequency(term)
        @fulltext[Sequel[:temp][VOCAB_TABLE]].where(term: term).get(:doc) || 0
      end
    end
  end
end

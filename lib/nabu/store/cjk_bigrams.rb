# frozen_string_literal: true

module Nabu
  module Store
    # The CJK character-pair mint (P93-3, №R-39 option b).
    #
    # The problem, measured at the 2026-08-21 census (~18.5M CJK passages;
    # ~22M by 2026-09-02): unicode61 tokenizes an unbroken Han/kana run as
    # ONE token, so a search for 六龍 misses every passage where those
    # characters sit inside a longer run. The lane indexes each run as its
    # overlapping character pairs, so any substring of a run becomes a
    # phrase of consecutive bigram tokens.
    #
    # == The mint grammar (fold-both-sides — this module is BOTH sides)
    #
    # Index side, per run of RUN chars in the folded text_normalized:
    # every overlapping pair, then the run's FINAL char as a lone token —
    # 六龍飛天 → "六龍 龍飛 飛天 天". The trailing unigram makes every
    # char position reachable (a single-char query is a prefix match:
    # any bigram starting with it, or a run-final unigram), and doubles
    # as the phrase-breaker: bigrams of two DIFFERENT runs are never
    # adjacent in the token stream, so a query phrase cannot bridge runs.
    #
    # Query side: a variant serves the lane only when every whitespace
    # token is one pure RUN — mixed or Latin queries stay on the main
    # lane, honestly. A run of n≥2 chars compiles to the phrase of its
    # n-1 bigrams; a single char to a prefix query.
    #
    # == The run class
    #
    # Han + hiragana + katakana + the iteration/prolonged-sound marks
    # (々 ー) — the scripts written without word breaks. Hangul stays
    # OUT: modern Korean is space-segmented and already served by
    # unicode61 (the sillok-family sources' CJK content is their Han
    # text). Widening the class is a mint-version event (the lane
    # rebuilds; it is derived data).
    module CjkBigrams
      RUN = /[\p{Han}\p{Hiragana}\p{Katakana}々ー]+/
      PURE_RUN = /\A#{RUN.source}\z/

      module_function

      # The index-side token stream for +text+, space-joined — or nil when
      # the text carries no run at all (the passage contributes no row).
      def index_text(text)
        tokens = text.to_s.scan(RUN).flat_map { |run| run_tokens(run) }
        tokens.empty? ? nil : tokens.join(" ")
      end

      # One run's tokens: overlapping bigrams plus the trailing unigram; a
      # single-char run is its lone char.
      def run_tokens(run)
        chars = run.chars
        return [run] if chars.one?

        chars.each_cons(2).map(&:join) << chars.last
      end

      # The FTS5 expression for one query variant, or nil when any
      # whitespace token is not a pure run (the lane declines — main lane
      # semantics stay untouched for mixed queries).
      def query_expression(variant)
        tokens = variant.to_s.split
        return nil if tokens.empty?

        parts = tokens.map { |token| token_expression(token) }
        return nil if parts.any?(&:nil?)

        parts.join(" ")
      end

      # A single pure-run token: n≥2 chars → the quoted phrase of its
      # overlapping bigrams (consecutive positions — the substring
      # semantics); one char → a quoted prefix query (reaches every bigram
      # starting with it AND the run-final unigram).
      def token_expression(token)
        return nil unless token.match?(PURE_RUN)

        chars = token.chars
        return "\"#{token}\" *" if chars.one?

        "\"#{chars.each_cons(2).map(&:join).join(' ')}\""
      end

      # The lane's expression over the query's fold variants (the
      # Normalize.query_forms union): unservable variants drop; nil when
      # none serves — the caller's signal that the lane stays out.
      def search_expression(variants)
        expressions = Array(variants).filter_map { |variant| query_expression(variant) }
        return nil if expressions.empty?
        return expressions.first if expressions.one?

        expressions.map { |expression| "(#{expression})" }.join(" OR ")
      end
    end
  end
end

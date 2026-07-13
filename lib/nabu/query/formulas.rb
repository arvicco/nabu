# frozen_string_literal: true

require_relative "catalog_join"
require_relative "grams"
require_relative "scope"

module Nabu
  module Query
    # Intra-corpus formula miner (P15-5, docs/intertext-design.md §5): "what are
    # the recurring formulas of THIS tradition, and where does each occur?" — the
    # oral-formulaic scholar's question (Homeric hexameter, Old English
    # alliterative verse). The SAME gram machinery as Parallels (§1) pointed
    # INWARD: instead of probing one anchor's grams against the whole index,
    # stream every passage of a SLICE, count its n-grams in memory, and rank the
    # repeaters. Design option (b), the measured pick: per-slice streaming count
    # at query time — zero schema (no materialized gram table), ~0.2 s per
    # ~200k-token slice on the live corpus (Homer grc, ASPR ang).
    #
    # == Scope: a source slug or a urn prefix
    #
    # +scope+ is a source slug (exact — "aspr") when one exists, else a urn
    # prefix. A document urn is a prefix of its passages' urns, so a whole work
    # ("urn:cts:greekLit:tlg0012.tlg001.perseus-grc2") OR a super-prefix spanning
    # several works ("urn:cts:greekLit:tlg0012" = the whole Homeric corpus,
    # Iliad + Odyssey) scopes its passages through the join. Matched as a byte-
    # range (urn >= prefix AND urn < prefix+max), no LIKE wildcards to escape.
    #
    # == Language filtering is not optional in practice (design §5)
    #
    # A translation-bearing source rides the SAME urn prefix as its base text
    # (perseus-greek holds grc originals AND aligned eng editions). An unfiltered
    # Homer run mixes traditions — the design measured a first unfiltered pass
    # returning "the son of peleus" (an English formula) beside ὣς ἔφαθ' οἵ δ'.
    # So `--lang` is offered and, for such a slice, wanted: slice AND lang both
    # apply. (A single-language source — ASPR is all ang — needs no lang.)
    #
    # == Ranking, and the stopword verdict (argued, measured)
    #
    # Rank by count × gram-length. THE VERDICT ON TRIVIAL GRAMS: no stoplist, no
    # df filter — the ranking is self-filtering. Measured on the live Homer grc
    # slice, the top formulas are ὣς ἔφαθ' οἵ δ' (72×), τὸν δ' αὖτε προσέειπε
    # (68×), the τὸν δ' ἀπαμειβόμενος προσέφη πολύμητις Ὀδυσσεύς chain (50×) —
    # genuine formulas, zero pure-function-word mush. Under a GENEROUS data-
    # derived stopword definition (a token in ≥10% of the slice's passages: δ
    # 22%, καί 18%, δέ 15%), NOT ONE all-stopword 4-gram reaches the top 40:
    # function words combine too freely to recur as often as a real oral formula,
    # and length rewards the longer contentful span. So the two rejected
    # alternatives lose on the merits:
    #   (a) a per-language stoplist is a NEW maintained artifact per language
    #       (grc, lat, ang, orv, chu, got, san, akk, …) — unbounded, opinionated,
    #       exactly the "clever registry" the house rules forbid; and it buys
    #       nothing the ranking does not already give.
    #   (b) a data-derived token-df filter MISFIRES on small slices: a formula's
    #       own content tokens have elevated df BY CONSTRUCTION (a formula repeats,
    #       so its words repeat), so on a short slice the filter would eat the very
    #       formulas we mine for.
    # We therefore rank and report honestly; --min-count is the user's lever
    # against a noisy tail, and the scholar's eye is the final filter — which has
    # almost nothing to reject. (At a FIXED gram size the count × length ranking
    # reduces to count; the × length is the general form, and the discriminator
    # once mixed sizes are mined — the natural extension of the fixed-size v1.)
    #
    # == One streaming pass; --long re-walks for full loci
    #
    # The hot pass counts every gram and keeps up to EXAMPLE_LOCI example urns per
    # gram (a bounded ≤3-urn array — cheap). --long makes a SECOND streaming pass
    # that gathers EVERY locus of the (few) reported grams, so --long pays its own
    # cost and the default pass stays lean. Reads text_normalized straight from
    # the catalog — no fulltext index needed (unlike Parallels).
    #
    # == MCP: not a v1 tool (argued)
    #
    # nabu_formulas is deliberately NOT exposed over MCP in v1. The MCP surface is
    # passage-lookup-flavored (bounded hits for a citation); the miner is batch-
    # flavored — it STREAMS a whole slice and returns a ranked table, not a
    # per-urn answer. A future batch/links surface (§7) is its natural home.
    class Formulas
      include CatalogJoin
      include Grams
      include Scope

      DEFAULT_GRAM_SIZE = 4
      DEFAULT_MIN_COUNT = 3
      DEFAULT_LIMIT = 25
      # Sane shingle bounds (the design measured 3..5; 2 is the floor a bigram
      # needs, 8 an ample ceiling before grams stop recurring at all).
      GRAM_SIZE_RANGE = (2..8)
      # Example loci kept per gram in the lean pass (compact render shows these;
      # --long re-walks for the complete list).
      EXAMPLE_LOCI = 3

      # One mined formula: the folded gram (marks stripped, like Search's
      # highlight), its slice count, the gram length, the rank key (count ×
      # length), and example/full loci (urns where it occurs).
      Formula = Data.define(:gram, :count, :length, :rank, :loci)

      # The mining result. +recurring_count+ is how many distinct grams cleared
      # +min_count+ (the page shows the top +formulas+ of these); passage/token
      # counts describe the slice actually streamed.
      Result = Data.define(:scope, :lang, :gram_size, :min_count,
                           :passage_count, :token_count, :recurring_count, :formulas)

      def initialize(catalog:)
        @catalog = catalog
      end

      # Mine the repeated +gram_size+-grams of the slice named by +scope+ (a
      # source slug or urn prefix), keeping those recurring ≥ +min_count+, ranked
      # by count × length, top +limit+. +lang+ scopes the slice by passage
      # language (design §5). +long+ gathers every locus of each reported gram.
      def run(scope, gram_size: DEFAULT_GRAM_SIZE, min_count: DEFAULT_MIN_COUNT,
              lang: nil, limit: DEFAULT_LIMIT, long: false)
        gram_size = gram_size.to_i
        unless GRAM_SIZE_RANGE.cover?(gram_size)
          raise ArgumentError, "gram size must be #{GRAM_SIZE_RANGE.first}–#{GRAM_SIZE_RANGE.last}"
        end

        dataset = slice(scope, lang: lang)
        counts, examples, passage_count, token_count = tally(dataset, gram_size)
        recurring = counts.select { |_gram, count| count >= min_count }
        top = ranked(recurring, gram_size).first([limit, 0].max)
        loci = long ? full_loci(dataset, top.map(&:first), gram_size) : examples
        formulas = top.map { |gram, count| build(gram, count, gram_size, loci) }
        Result.new(scope: scope, lang: lang, gram_size: gram_size, min_count: min_count,
                   passage_count: passage_count, token_count: token_count,
                   recurring_count: recurring.size, formulas: formulas)
      end

      private

      # The passages in scope, selecting just what the pass needs (urn +
      # text_normalized), through the shared scope grammar (Query::Scope — a
      # source slug, exact, else a document-urn prefix) over the shared
      # visibility+filter join (CatalogJoin). --lang filters passage-side
      # exactly as Search does.
      def slice(scope, lang:)
        scoped_passages(scope, lang: lang)
          .select(Sequel[:passages][:urn].as(:urn),
                  Sequel[:passages][:text_normalized].as(:text_normalized))
      end

      # ONE streaming pass: tokenize each passage, shingle, count every gram, and
      # keep up to EXAMPLE_LOCI DISTINCT-passage example urns per gram (a gram may
      # recur within a line — counted for +count+, but a locus is a passage, so
      # the same urn is not repeated).
      def tally(dataset, gram_size)
        counts = Hash.new(0)
        examples = Hash.new { |hash, key| hash[key] = [] }
        passage_count = 0
        token_count = 0
        dataset.each do |row|
          tokens = gram_tokens(row[:text_normalized])
          passage_count += 1
          token_count += tokens.size
          shingle(tokens, gram_size).each do |gram_tokens_arr|
            gram = gram_tokens_arr.join(" ")
            counts[gram] += 1
            store = examples[gram]
            store << row[:urn] if store.size < EXAMPLE_LOCI && store.last != row[:urn]
          end
        end
        [counts, examples, passage_count, token_count]
      end

      # Rank by count × gram length, then count, then the gram (stable, so equal-
      # score grams sort deterministically). See the class doc's stopword verdict:
      # this ranking is the whole filter — no stoplist.
      def ranked(recurring, gram_size)
        recurring.sort_by { |gram, count| [-(count * gram_size), -count, gram] }
      end

      def build(gram, count, gram_size, loci)
        Formula.new(gram: gram, count: count, length: gram_size,
                    rank: count * gram_size, loci: loci.fetch(gram, []))
      end

      # --long: a SECOND streaming pass gathering EVERY locus (distinct passage)
      # of the reported grams — only the ≤limit reported grams are tracked, so the
      # hot pass stays lean and --long pays its own re-walk (~0.2 s).
      def full_loci(dataset, grams, gram_size)
        wanted = grams.to_set
        return {} if wanted.empty?

        loci = Hash.new { |hash, key| hash[key] = [] }
        dataset.each do |row|
          seen = Set.new
          shingle(gram_tokens(row[:text_normalized]), gram_size).each do |gram_tokens_arr|
            gram = gram_tokens_arr.join(" ")
            loci[gram] << row[:urn] if wanted.include?(gram) && seen.add?(gram)
          end
        end
        loci
      end
    end
  end
end

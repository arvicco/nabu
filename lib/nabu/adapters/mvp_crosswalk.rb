# frozen_string_literal: true

module Nabu
  module Adapters
    # Producer #15 for the links journal: the Mahāvyutpatti crosswalk. The
    # 9th-century imperial glossary states, entry by entry, that Sanskrit X
    # is rendered Tibetan Y (and, in the later layer, Chinese Z). The mvp
    # shelf holds that statement in its labeled body lanes; this producer
    # turns it into kind=equivalent edges from each Mvy. entry onto the
    # LEMMA NODES the held corpora actually carry, so `nabu links
    # urn:nabu:dict:mvp:625` walks from bodhisattvaḥ to the DCS lemma and
    # to every 84000 glossary entry that renders byang chub sems dpa'.
    #
    # == The legs (exact normalized-form joins only — no fuzzy matching)
    #
    # - san → dcs-lexicon: the DCS gold lexicon is the one Sanskrit lemma
    #   index the held corpora carry (GRETIL and SARIT are unlemmatized
    #   text). The Mahāvyutpatti cites NOMINATIVES (bodhisattvaḥ), DCS
    #   cites STEMS (bodhisattva), so the join runs on the exact IAST
    #   headword (NFC, lowercased — never the diacritic-stripped search
    #   fold, which merges ānanda with ananda) AND the house's D48-a
    #   nominative↔stem candidates (Query::Define.sanskrit_stem_variants —
    #   the owner-ruled rule `define` already applies), every candidate
    #   validated by existence: an edge mints only onto a real lexicon
    #   entry. The basis rides the detail ("exact" / "stem") so the two
    #   grades stay distinguishable.
    # - bod → e84000-glossary: the 84000 per-publication glossaries are the
    #   Tibetan lemma index held for the Derge canon (each glossary entry
    #   belongs to one 84000 translation of a Derge text). The join is the
    #   mvp Tibetan lane (Wylie, or the Tibetan-script quote when Wylie is
    #   absent) folded by Normalize.search_form(…, language: "bod") — the
    #   Xct transcoder the shelves' own headword_folded went through — equal
    #   to the glossary entry's headword_folded.
    # - GRETIL, SARIT, CBETA, and the Derge text itself: NO leg. None
    #   carries a lemma index (unlemmatized running text; CBETA has no
    #   Buddhist-Chinese lemma shelf), so an equivalent could only be found
    #   as a token or substring of passages — attestation, not a lemma
    #   bridge, and at a grain the journal cannot hold (the Tibetan
    #   equivalents alone score ~32M entry×passage hits across the two
    #   Derge shelves).
    #
    # == Census (live catalog, 2026-10-22; 9,379 entries, every one
    #    carrying all three language lanes)
    #
    # san → dcs-lexicon: 3,068 entries matched (573 on the exact headword,
    # the rest through the stem rule) → 4,652 edges (667 exact, 3,985
    # stem). bod → e84000-glossary: 2,362 entries → 19,090 edges (a common
    # term recurs across many publications' glossaries — Mvy. 2 bcom ldan
    # 'das fans out to 203). 4,205 entries reach at least one target;
    # 23,742 edges in ~8 s. The misses are honest: 928 headwords carry
    # upstream's parenthetical alternates and 158 a ". "-joined variant
    # pair, which the exact join does not split.
    #
    # Upstream editorial markup carried in the lanes is honored the way the
    # parser rendered it: a "sic (corr. corr)" quote contributes BOTH forms
    # (the transmitted text and DDBC's correction are each upstream text);
    # <del>-deleted equivalents never reached the lanes.
    #
    # == Edge shape
    #
    # from_urn = the Mvy. entry (the asserting side, carrying the
    # provenance: its urn IS the Mvy. number); to_urn = the target lemma
    # entry; score nil (a curated glossary equation is not a mined
    # similarity); detail = "Mvy. 625 · san bodhisattvaḥ → bodhisattva
    # (stem)" / "Mvy. 625 · bod byang chub sems dpa'". Kind "equivalent" is
    # new and honest: not "reference" (no citation is asserted), not
    # "etymology" (no descent), not "translation" (that kind joins whole
    # documents) — a glossary's statement that two lemmas render each other.
    #
    # == Refresh mechanics (the standing producer contract)
    #
    # Edges are a pure function of the catalog (the mvp entries and the two
    # target shelves) and code: SyncRunner re-runs this producer after every
    # mvp sync through the reference_producer seam, and the rebuild links
    # stage replays it after every load, superseding the prior (producer,
    # scope) run atomically. A target shelf not yet in the catalog simply
    # contributes no edges; the next mvp refresh (or rebuild) picks it up.
    # A dcs or e84000 sync does NOT re-run it (a source has one reference
    # producer, and both already declare theirs): after either shelf
    # changes, `nabu sync mvp --parse-only` refreshes the crosswalk.
    #
    # Lives under adapters/ beside the mvp adapter (the lane-helper
    # placement) so it rides the mvp parser closure instead of the shared
    # derivation core: editing it dirties one cheap source, never every
    # stamp.
    class MvpCrosswalk
      PRODUCER = "mvp"
      KIND = "equivalent"
      CODE_VERSION = "mvp-crosswalk/1 nabu/#{VERSION}".freeze

      SANSKRIT_SHELF = "dcs-lexicon"
      TIBETAN_SHELF = "e84000-glossary"
      MVP_SHELF = "mvp"

      TIBETAN_LANE = "Tibetan: "
      LANE_SEPARATOR = " — "
      QUOTE_SEPARATOR = " · "
      SIC_CORR = /\A(.*?) \(corr\. (.*)\)\z/

      # What one refresh did — the LibraryReferences::Result shape (so the CLI
      # sync tail renders every producer identically) plus the per-leg match
      # census: entries with at least one target, per leg.
      Result = Data.define(:scope, :run_id, :edges_written, :edges_refreshed,
                           :superseded_runs, :superseded_edges, :entries, :matched)

      def initialize(catalog:, journal:)
        @catalog = catalog
        @journal = journal
      end

      # Re-derive every equivalent edge for the mvp shelf, superseding the
      # prior (producer, scope) run. +workdir+ rides the producer seam; the
      # crosswalk derives everything from the catalog and ignores it.
      def run(slug, workdir: nil) # rubocop:disable Lint/UnusedMethodArgument
        entries = mvp_entries(slug)
        sanskrit = shelf_index(SANSKRIT_SHELF) { |row| self.class.sanskrit_key(row[:headword]) }
        tibetan = shelf_index(TIBETAN_SHELF) { |row| row[:headword_folded] }
        counts = Hash.new(0)
        run_id = superseded = nil
        @journal.transaction do
          superseded = Store::LinksJournal.supersede!(@journal, producer: PRODUCER, scope: slug)
          run_id = Store::LinksJournal.record_run!(@journal, producer: PRODUCER, scope: slug,
                                                             params: { kind: KIND }, code_version: CODE_VERSION)
          entries.each do |entry|
            write_all(sanskrit_edges(entry, sanskrit), run_id, counts, :san)
            write_all(tibetan_edges(entry, tibetan), run_id, counts, :bod)
          end
        end
        Result.new(scope: slug, run_id: run_id,
                   edges_written: counts[:inserted], edges_refreshed: counts[:refreshed],
                   superseded_runs: superseded[0], superseded_edges: superseded[1],
                   entries: entries.size, matched: { san: counts[:matched_san], bod: counts[:matched_bod] })
      end

      # The folded Tibetan join keys of one mvp entry body: every quote of
      # the Wylie half of the "Tibetan:" lane (the script half when the lane
      # carries no Wylie), sic and corr both, through the bod fold.
      def self.tibetan_keys(body)
        line = body.to_s.each_line.map(&:chomp).find { |l| l.start_with?(TIBETAN_LANE) }
        return [] unless line

        quotes(line.delete_prefix(TIBETAN_LANE).split(LANE_SEPARATOR).first)
          .map { |quote| Normalize.search_form(quote, language: "bod") }
          .reject(&:empty?).uniq
      end

      # A lane's quotes, split on the parser's " · " join, a rendered
      # "sic (corr. corr)" contributing both forms.
      def self.quotes(text)
        forms = text.to_s.split(QUOTE_SEPARATOR).flat_map do |quote|
          (m = SIC_CORR.match(quote)) ? [m[1], m[2]] : [quote]
        end
        forms.map(&:strip).reject(&:empty?).uniq
      end

      # The Sanskrit join keys of one mvp headword, each with its basis: the
      # IAST headword itself ("exact"), then the D48-a nominative↔stem
      # candidates ("stem"). Keys are NFC + lowercase IAST, NOT the
      # diacritic-stripped search fold: the fold merges ānanda (joy; the
      # disciple's name) with ananda (joyless) — a search widening, never a
      # lemma identity.
      def self.sanskrit_keys(headword)
        keys = { sanskrit_key(headword) => "exact" }
        Query::Define.sanskrit_stem_variants(headword).each { |variant| keys[sanskrit_key(variant)] ||= "stem" }
        keys
      end

      def self.sanskrit_key(form) = Normalize.nfc(form.to_s.strip).downcase

      private

      # One edge per distinct target (the first key reaching it wins — exact
      # before stem, the keys' insertion order).
      def sanskrit_edges(entry, index)
        edges = self.class.sanskrit_keys(entry[:headword]).flat_map do |key, basis|
          index.fetch(key, []).map do |target|
            { from: entry[:urn], to: target[:urn],
              detail: "Mvy. #{entry[:entry_id]} · san #{entry[:headword]} → #{target[:headword]} (#{basis})" }
          end
        end
        edges.uniq { |edge| edge[:to] }
      end

      def tibetan_edges(entry, index)
        edges = self.class.tibetan_keys(entry[:body]).flat_map do |key|
          index.fetch(key, []).map do |target|
            { from: entry[:urn], to: target[:urn], detail: "Mvy. #{entry[:entry_id]} · bod #{key}" }
          end
        end
        edges.uniq { |edge| edge[:to] }
      end

      def write_all(edges, run_id, counts, leg)
        return if edges.empty?

        counts[:"matched_#{leg}"] += 1
        edges.each do |edge|
          outcome = Store::LinksJournal.write_edge!(
            @journal, from_urn: edge[:from], to_urn: edge[:to], kind: KIND,
                      score: nil, run_id: run_id, detail: edge[:detail]
          )
          counts[outcome == :inserted ? :inserted : :refreshed] += 1
        end
      end

      # The live entries of +slug+'s mvp shelf, urn-ordered.
      def mvp_entries(slug)
        entry_rows(MVP_SHELF)
          .join(:sources, id: Sequel[:dictionaries][:source_id])
          .where(Sequel[:sources][:slug] => slug)
          .order(Sequel[:dictionary_entries][:urn])
          .select(Sequel[:dictionary_entries][:urn], Sequel[:dictionary_entries][:entry_id],
                  Sequel[:dictionary_entries][:headword], Sequel[:dictionary_entries][:body])
          .all
      end

      # { join key => [{urn:, headword:}] } over a target shelf's live
      # entries, the key computed per row by the block — one scan; an
      # absent shelf is an empty index.
      def shelf_index(dictionary, &join_key)
        entry_rows(dictionary)
          .order(Sequel[:dictionary_entries][:urn])
          .select(Sequel[:dictionary_entries][:urn], Sequel[:dictionary_entries][:headword],
                  Sequel[:dictionary_entries][:headword_folded])
          .each_with_object(Hash.new { |hash, missing| hash[missing] = [] }) do |row, index|
            index[join_key.call(row)] << { urn: row[:urn], headword: row[:headword] }
          end
      end

      def entry_rows(dictionary)
        @catalog[:dictionary_entries]
          .join(:dictionaries, id: Sequel[:dictionary_entries][:dictionary_id])
          .where(Sequel[:dictionaries][:slug] => dictionary, Sequel[:dictionary_entries][:withdrawn] => false)
      end
    end
  end
end

# frozen_string_literal: true

# Nabu::CLI — `nabu concord` (KWIC).
# A partial of lib/nabu/cli/query.rb, which loads it.
module Nabu
  class CLI < Thor
    desc "concord QUERY", "Concordance (KWIC): keyword-in-context lines, one per hit"
    long_desc <<~HELP, wrap: false
      Keyword-in-context concordance: every hit as one line — left context, the
      matched keyword, right context — with the keyword aligned in a fixed
      column so you can scan a word's usage down the page. The keyword is
      located in the PRISTINE edition text (accents and all), not the folded
      search form: a concordance is for reading real usage.

      Matching is exactly `nabu search`: diacritic- and case-insensitive on both
      sides (μηνιν finds μῆνιν), implicit-AND multiple words, "quoted phrase",
      prefix* — and --lemma FORM for exact dictionary-form lookup over the gold
      treebanks (finds every inflected attestation). Rows come in CORPUS order
      (urn/citation), not relevance order — the point is scanning, not ranking.
      One row per passage: a passage with the keyword twice shows its first
      occurrence.

      Layout: left context is trimmed to --width cells per side (default 40)
      and right-justified so the keyword column lines up; the right context is
      trimmed to the same width; clipped context is marked with …. Each row
      ends with the passage urn and [language]. Alignment counts East-Asian
      display width (Nabu::Display.width), so a lzh/ojp Han line lines up its
      keyword column exactly where a grc line does — each ideograph two cells.

      Filters (as in search): --lang, --license, --limit (default 20).

      Examples:
        nabu concord μῆνιν                       # every attestation of μῆνιν, KWIC
        nabu concord μηνιν --width 30            # tighter context, accents optional
        nabu concord ἄειδε --lang grc --limit 50
        nabu concord --lemma λέγω --lang grc     # every inflection in context:
                                                 #   λέγουσι, εἶπας, εἰπεῖν…
        nabu concord sapientia --lang lat        # a Latin word across the corpus

      Use cases: see how a word is actually used across six corpora at once;
      spot collocations and formulae; build a hand concordance for a term before
      writing about it.
    HELP
    option :lang, type: :string, desc: "Restrict to a passage language (e.g. grc, lat)"
    option :license, type: :string,
                     desc: "Restrict to an exact license class (open, attribution, nc, …)"
    option :limit, type: :numeric, default: 20, desc: "Maximum number of KWIC lines"
    option :width, type: :numeric, default: Nabu::Query::Concord::DEFAULT_WIDTH,
                   desc: "Context characters per side (default #{Nabu::Query::Concord::DEFAULT_WIDTH})"
    option :lemma, type: :string, banner: "FORM",
                   desc: "Exact-lemma concordance over the gold treebanks (replaces the text query)"
    display_option
    def concord(query = nil)
      query = query.to_s.strip
      display_mode
      lemma = options[:lemma]
      if lemma
        raise Thor::Error, "concord: --lemma replaces the text query — give one or the other" unless query.empty?

        lemma = lemma.strip
        raise Thor::Error, "concord: --lemma needs a lemma" if lemma.empty?
      elsif query.empty?
        raise Thor::Error, "concord: give a query"
      end

      validate_license!(options[:license])
      config = Nabu::Config.load
      catalog = open_catalog(config)
      fulltext = open_fulltext(config)
      raise Thor::Error, "no index — run nabu sync or nabu rebuild" unless catalog && fulltext
      if lemma && !fulltext.table_exists?(Nabu::Store::Indexer::LEMMA_TABLE)
        raise Thor::Error, "no lemma index (the fulltext index predates lemma search) — " \
                           "run nabu sync or nabu rebuild"
      end

      rows = Nabu::Query::Concord.new(catalog: catalog, fulltext: fulltext).run(
        query.empty? ? nil : query, lemma: lemma, lang: options[:lang],
                                    license: options[:license], limit: options[:limit].to_i, width: options[:width].to_i
      )
      print_concord_rows(rows)
      print_display_footer
    ensure
      catalog&.disconnect
      fulltext&.disconnect
    end

    no_commands do
      # Render KWIC rows (P8-3): left + keyword + right (each side already
      # trimmed to width by Concord), then the urn + [language] tag. The left
      # context is a fixed width, so keyword columns align down the page.
      # Non-gold lemma-mode rows carry the search --lemma tag (P26-4 silver,
      # P34-3 equivalence); gold and text-mode rows render exactly as before.
      # The footer totals each non-gold share so a mixed page is never
      # silently mixed.
      def print_concord_rows(rows)
        return say("no matches") if rows.empty?

        width = options[:width].to_i
        rows.each do |row|
          tier = row.tier && row.tier != "gold" ? " [#{row.tier}]" : ""
          left, keyword, right = concord_display_pieces(row, width)
          say "#{left}#{keyword}#{right}  #{row.urn}#{" [#{row.language}]" if row.language}#{tier}"
        end
        footer = "#{rows.size} #{rows.size == 1 ? 'line' : 'lines'} (KWIC; keyword in pristine text, corpus order)"
        silver = rows.count { |row| row.tier == "silver" }
        footer += " — #{silver} silver (automatic lemmatization)" if silver.positive?
        equivalence = rows.count { |row| row.tier == "equivalence" }
        footer += " — #{equivalence} equivalence (Classical-Latin equivalents)" if equivalence.positive?
        say footer
      end

      # Concord's columns were padded by Concord over the PRE-display pieces;
      # a display transform (stripped marks, isolate wrapping, token coloring)
      # changes their cell width, so re-pad here over DISPLAY CELLS
      # (Nabu::Display.rjust/ljust — ANSI SGR and isolates count 0, wide
      # clusters count 2) to keep the keyword column at exactly +width+ cells.
      def concord_display_pieces(row, width)
        left = display_text(row.left.sub(/\A +/, ""), row.language)
        right = display_text(row.right.sub(/ +\z/, ""), row.language)
        keyword = display_text(row.keyword, row.language)
        [Nabu::Display.rjust(left, width), keyword, Nabu::Display.ljust(right, width)]
      end
    end
  end
end

# frozen_string_literal: true

# Nabu::CLI — `nabu vocab` (lemma-frequency profiles).
# A partial of lib/nabu/cli/query.rb, which loads it.
module Nabu
  class CLI < Thor
    desc "vocab URN", "Lemma-frequency profile of a document/range vs the corpus (gold shelves only)"
    long_desc <<~HELP, wrap: false
      Profile the gold-lemma vocabulary of one document, a citation range, or a
      single passage (P14-3, improvements §1.7): total tokens carrying a gold
      lemma, how many distinct lemmas, the most DISTINCTIVE vocabulary, and the
      in-document hapax legomena (lemmas attested exactly once).

      "Distinctive" means over-represented HERE versus the whole corpus, ranked
      by a log-odds-ratio with an informative Dirichlet prior (Monroe et al.
      2008) — the z-score damps rare-lemma noise a plain frequency ratio would
      let blow up, so the list is the text's real subject vocabulary, not its
      accidental singletons (those get their own hapax line). Each row shows the
      lemma's document token count and its corpus passage-frequency.

      Gold lemmas exist only for the treebank shelves (PROIEL, TOROT, ISWOC, the
      UD treebanks) and the ORACC cuneiform layer — about 8% of the corpus. A
      document without gold lemmas (Perseus, First1K, the papyri, ASPR poetry)
      is not an error: it says so plainly and lists the gold-bearing languages
      so you can profile something that works. --limit caps both the distinctive
      list and the hapax spellings printed (default #{Nabu::Query::Vocab::DEFAULT_LIMIT}).

      DIACHRONY (--by-century): instead of one document's lemmas, plot the DATED
      corpus across centuries (P15-2, the timeline). Bare, it is the shape
      of your dated holdings — one row per century (BCE/CE), the document count.
      With a text QUERY it becomes "plot this word across centuries": how many
      dated documents attest the term in each century. Composes with --lang,
      --license, --from/--to/--century, and --place; counts are per DOCUMENT and
      bucketed by EARLIEST year (a ranged papyrus lands in its first century), so
      the footer names how many span more than one century. Most of the corpus is
      undated (papyri via HGV, Slovene goo300k/IMP carry dates); undated
      documents are simply absent here, never an error.

      Examples:
        nabu vocab urn:nabu:proiel:caes-gal          # Caesar's Gallic War
        nabu vocab urn:nabu:proiel:cic-off --limit 30
        nabu vocab urn:nabu:proiel:hdt:1.1-1.100     # a citation range
        nabu vocab --by-century                      # the dated corpus over time
        nabu vocab --by-century στρατηγ --lang grc   # a word plotted across centuries
        nabu vocab --by-century --place oxyrhynch%   # Oxyrhynchus, century by century
    HELP
    option :limit, type: :numeric, default: Nabu::Query::Vocab::DEFAULT_LIMIT,
                   desc: "Cap the distinctive list and hapax spellings printed"
    option :long, type: :boolean, default: false,
                  desc: "List every hapax legomenon (and every gold-bearing language) in full, " \
                        "escaping the --limit display cap (the distinctive ranking stays top-N)"
    option :by_century, type: :boolean, default: false,
                        desc: "Diachronic mode: bucket the DATED corpus (or a text query) by century"
    option :lang, type: :string, desc: "With --by-century: restrict to a language (grc, lat, …)"
    option :license, type: :string, desc: "With --by-century: restrict to an exact license class"
    option :from, type: :numeric, banner: "YEAR", desc: "With --by-century: earliest year (negative = BCE)"
    option :to, type: :numeric, banner: "YEAR", desc: "With --by-century: latest year"
    option :century, type: :numeric, banner: "N", desc: "With --by-century: one century's window (6, -2)"
    option :place, type: :string, banner: "PATTERN", desc: "With --by-century: provenance place LIKE filter"
    option :chars, type: :boolean, default: false,
                   desc: "Character-grain profile (P72-4): per-document Han character frequencies " \
                         "— the sinograph instrument for unlemmatized documents (kanripo/cbeta/aozora)"
    option :coverage, type: :string, banner: "CHARS",
                      desc: "With --chars: coverage of the document against this character set " \
                            "(fold-aware) — occurrence %, distinct split, and the top strangers"
    option :json, type: :boolean, default: false,
                  desc: "With --chars: emit the frozen machine contract instead of the card"
    def vocab(urn = nil)
      urn = urn.to_s.strip
      return vocab_by_century(urn) if options[:by_century]
      raise Thor::Error, "vocab: give a document, range, or passage urn" if urn.empty?
      return char_vocab(urn) if options[:chars]
      raise Thor::Error, "vocab: --coverage/--json ride the --chars profile" if options[:coverage] || options[:json]

      config = Nabu::Config.load
      catalog = open_catalog(config)
      fulltext = open_fulltext(config)
      raise Thor::Error, "no index — run nabu sync or nabu rebuild" unless catalog && fulltext
      unless fulltext.table_exists?(Nabu::Store::Indexer::LEMMA_TABLE)
        raise Thor::Error, "no lemma index (the fulltext index predates lemma search) — " \
                           "run nabu sync or nabu rebuild"
      end

      profile = Nabu::Query::Vocab.new(catalog: catalog, fulltext: fulltext)
                                  .run(urn, limit: options[:limit].to_i)
      print_vocab(profile)
    rescue Nabu::Query::Vocab::NotFound, Nabu::Query::Range::Error => e
      raise Thor::Error, e.message
    ensure
      catalog&.disconnect
      fulltext&.disconnect
    end

    no_commands do
      # Render a vocab profile (P14-3): the header (urn, title, language, scope),
      # then either the gold-lemma summary + distinctive table + hapax line, or
      # the honest no-gold-lemmas notice naming the gold-bearing languages.
      def print_vocab(profile)
        header = "#{profile.urn}#{" — #{profile.title}" if profile.title}"
        header += " [#{profile.language}]" if profile.language
        say header
        say "  #{profile.kind}, #{pluralize(profile.passages, 'passage')}"
        return print_vocab_no_gold(profile) if profile.total_tokens.zero?

        # The tier label (P26-4): a silver document profiles, but its counts
        # never render under the gold name — the line SAYS silver, plus an
        # explicit automatic-lemmatization warning. Gold (and pre-tier nil)
        # keeps the exact pre-tier render.
        silver = profile.lemma_tier == "silver"
        say "  #{silver ? 'silver' : 'gold'} lemmas: #{commafy(profile.total_tokens)} tokens · " \
            "#{commafy(profile.distinct_lemmas)} distinct lemmas · " \
            "#{commafy(profile.hapax_count)} hapax legomena " \
            "(#{profile.annotated_passages} of #{profile.passages} passages annotated)"
        if silver
          say "  lemma tier: silver (automatic lemmatization — token counts are not gold " \
              "attestation; corpus reference frequencies stay gold-only)"
        end
        print_vocab_distinctive(profile.distinctive)
        print_vocab_hapax(profile.hapax, profile.hapax_count)
      end

      # The distinctive-vocabulary table: lemma, its token count here, its corpus
      # passage-frequency, and the log-odds z-score, most distinctive first.
      def print_vocab_distinctive(distinctive)
        return if distinctive.empty?

        say ""
        say "  distinctive vocabulary (log-odds vs corpus, top #{distinctive.size}):"
        # Pad the lemma column by display cells (P35-7): a lzh/ojp lemma of Han
        # is two cells per ideograph, so char-count ljust would drift the table.
        width = distinctive.map { |e| Nabu::Display.width(e.lemma) }.max
        distinctive.each do |entry|
          say "    #{Nabu::Display.ljust(entry.lemma, width)}  #{entry.doc_count}× here · " \
              "#{commafy(entry.corpus_freq)}× corpus  (z=#{format('%.1f', entry.score)})"
        end
      end

      # The hapax legomena line: attested exactly once in this document. The full
      # count, then up to --limit spellings (they can number in the hundreds) —
      # or, under --long (house rule P15-8), every spelling with no "(+N more)"
      # tail. The full list already rides in the profile; --limit only caps the
      # print, so --long is a pure render concern here.
      def print_vocab_hapax(hapax, hapax_count)
        return if hapax_count.zero?

        say ""
        shown = options[:long] ? hapax : hapax.first(options[:limit].to_i)
        more = hapax_count - shown.size
        tail = more.positive? ? " (+#{commafy(more)} more)" : ""
        say "  hapax legomena (#{commafy(hapax_count)}, once each): #{shown.join(', ')}#{tail}"
      end

      # `vocab --by-century` (P15-2): the diachronic histogram of the dated
      # corpus, optionally filtered by a text query (plot a word across
      # centuries) and by --lang/--license/date/--place.
      # P72-4: the character-grain profile + coverage instrument.
      def char_vocab(urn)
        config = Nabu::Config.load
        catalog = open_catalog(config)
        raise Thor::Error, "no corpus — run nabu sync or nabu rebuild" unless catalog

        profile = Nabu::Query::CharVocab.new(catalog: catalog)
                                        .run(urn, limit: options[:limit].to_i,
                                                  coverage: options[:coverage])
        if options[:json]
          say JSON.pretty_generate(Nabu::Query::CharVocab.json_payload(urn, profile))
          return
        end
        raise Thor::Error, "vocab: no document #{urn}" unless profile

        print_char_vocab(profile)
      rescue Nabu::Error => e
        raise Thor::Error, e.message
      ensure
        catalog&.disconnect
      end

      def print_char_vocab(profile)
        say "#{profile.urn}  #{profile.title}  [#{profile.language}]"
        if profile.total.zero?
          say "  no Han characters in this document — the char-grain profile is for sinograph texts"
          return
        end
        say "  #{profile.total} Han character occurrences · #{profile.distinct} distinct · " \
            "#{profile.passages} passages · #{profile.hapax_count} hapax"
        say ""
        say "  top characters:"
        profile.top.each { |row| say format("    %<char>s  %<count>6d", char: row.char, count: row.count) }
        say ""
        say "  hapax (once only): #{profile.hapax.join(' ')}#{' …' if profile.hapax_count > profile.hapax.size}"
        return unless profile.coverage

        c = profile.coverage
        say ""
        say "  coverage vs #{c.charset_size}-character set: #{c.occurrence_pct}% of occurrences · " \
            "#{c.distinct_covered}/#{c.distinct_total} distinct characters inside"
        return if c.strangers.empty?

        strangers = c.strangers.map { |row| "#{row.char} #{row.count}" }.join("  ·  ")
        say "  top strangers (teach next): #{strangers}"
      end

      def vocab_by_century(query)
        validate_license!(options[:license])
        from, to = date_window
        config = Nabu::Config.load
        catalog = open_catalog(config)
        raise Thor::Error, "no catalog — run nabu sync or nabu rebuild" unless catalog

        require_timeline!(catalog)
        fulltext = open_fulltext(config) unless query.empty?
        raise Thor::Error, "no index — run nabu sync or nabu rebuild" if !query.empty? && fulltext.nil?

        result = Nabu::Query::Century.new(catalog: catalog, fulltext: fulltext).run(
          query: query.empty? ? nil : query, lang: options[:lang], license: options[:license],
          from: from, to: to, place: options[:place]
        )
        print_century(result)
      ensure
        catalog&.disconnect
        fulltext&.disconnect
      end

      def print_century(result)
        say(if result.query
              "diachrony of #{result.query.inspect} (dated documents by century)"
            else
              "dated corpus by century"
            end)
        return say("  no dated documents match") if result.buckets.empty?

        width = result.buckets.map { |bucket| bucket.label.length }.max
        result.buckets.each do |bucket|
          say "  #{bucket.label.ljust(width)}  #{commafy(bucket.documents)} " \
              "#{bucket.documents == 1 ? 'document' : 'documents'}"
        end
        multi = result.multi_century.positive? ? "; #{commafy(result.multi_century)} span multiple centuries" : ""
        say "  #{commafy(result.total_documents)} dated documents (bucketed by earliest year#{multi})"
      end

      # A document with no gold lemmas: say so plainly and name the gold-bearing
      # languages (from the lemma index) so the user can profile something real.
      def print_vocab_no_gold(profile)
        say "  no gold lemmas — this document is not linguistically annotated " \
            "(0 of #{pluralize(profile.passages, 'passage')} carry one)."
        say "  Gold lemmas come from the treebank shelves (PROIEL, TOROT, ISWOC, " \
            "Universal Dependencies) and the ORACC cuneiform layer."
        # --long (house rule P15-8) lists every gold-bearing language; the compact
        # default shows the first eight with a "…" elision marker.
        shown = options[:long] ? profile.gold_languages : profile.gold_languages.first(8)
        langs = shown.map { |lang, count| "#{lang} (#{commafy(count)})" }
        ellipsis = profile.gold_languages.size > shown.size ? ", …" : ""
        say "  gold-bearing languages: #{langs.join(', ')}#{ellipsis}"
        say "  Try e.g. nabu vocab urn:nabu:proiel:caes-gal"
      end
    end
  end
end

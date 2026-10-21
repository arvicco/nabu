# frozen_string_literal: true

# Nabu::CLI — lexical desks: align, define, etym, lemma. Carved out of
# lib/nabu/cli.rb, the registry that loads it.
module Nabu
  class CLI < Thor
    desc "align REF", "Render one citation across every witness of a registered work (the alignment hub)"
    long_desc <<~HELP, wrap: false
      Cross-source alignment (architecture §10): one citation of a registered
      WORK rendered in every witness the alignment registry
      (config/alignments.yml) names — the same verse in Greek, Latin, Gothic,
      Classical Armenian, and Old Church Slavonic, in one screen. Witnesses
      render in registry order, each with its language and its EFFECTIVE
      license class (the five NT witnesses are all nc — mind the labels when
      quoting).

      REF is a citation in the work's scheme — for the `nt` work,
      BOOK chapter.verse ("MARK 2.3"; quote it or let Thor join the words).
      Matching is forgiving: case, extra spaces, and chapter:verse colons all
      normalize ("mark 2:3" finds MARK 2.3). REF may also be a PASSAGE URN
      (pivot from a show/search hit): the sentence's verse is looked up and
      aligned across the other witnesses.

      Alignment is at citation grain over the treebanks' verse annotations,
      and sentence≠verse: a witness's sentence that spans a verse boundary is
      shown once, labeled with everything it covers. Honesty rules: a witness
      that simply lacks the verse (the Armenian sample holds only scattered
      chapters; Gothic is fragmentary) reads "not attested"; a registered
      witness whose source was never synced reads "not synced". Adding a
      witness (say, the ISWOC Old English Mark) is a registry entry, not code.

      --work names the work explicitly. Without it, a ref resolves through
      the index: when exactly one registered work attests it, that work is
      picked automatically (nt for "MARK 2.3", ot for "GEN 1.1"); a ref
      several works attest asks you to pick among the attesters.

      Examples:
        nabu align MARK 2.3                 # the paralytic, five ways
        nabu align "mark 2:3"               # same — refs normalize
        nabu align urn:nabu:proiel:marianus:36421
                                            # pivot: this OCS sentence, aligned
        nabu align MATT 5.25 --work nt      # explicit work id

      Use cases: read the Vorlage beside the translation (THE working method
      of comparative philology); check how each witness renders a
      construction; learn OCS/Gothic against the Greek you can already read.
    HELP
    option :work, type: :string, banner: "ID",
                  desc: "Alignment work id from config/alignments.yml (optional when only one is registered)"
    option :collate, type: :boolean, default: false,
                     desc: "Diff the witnesses instead of listing them: a raw-token apparatus per " \
                           "(language, script) group — base reading, then per-witness divergences only " \
                           "(cross-script witnesses rendered undiffed, honestly)"
    option :base, type: :string, banner: "LABEL",
                  desc: "With --collate: the base witness (label or document urn) each group diffs " \
                        "against (default: the first witness in registry order)"
    option :long, type: :boolean, default: false,
                  desc: "Lift the #{Nabu::Query::Align::MAX_REFS}-ref range ceiling and render every ref " \
                        "(compact clips a huge range by default); with --collate, also print each " \
                        "witness's full tokens instead of only its divergences"
    display_option
    def align(*ref_parts)
      ref = ref_parts.join(" ").strip
      raise Thor::Error, "align: give a citation ref (e.g. MARK 2.3) or a passage urn" if ref.empty?

      display_mode
      config = Nabu::Config.load
      catalog = open_catalog(config)
      fulltext = open_fulltext(config)
      raise Thor::Error, "no corpus — run nabu sync or nabu rebuild" unless catalog && fulltext

      registry = Nabu::AlignmentRegistry.load(config.alignments_path)
      if options[:collate]
        result = Nabu::Query::Collation.new(catalog: catalog, fulltext: fulltext, registry: registry)
                                       .run(ref, work: options[:work], base: options[:base], long: options[:long])
        print_collation(result, long: options[:long])
      else
        raise Thor::Error, "align: --base only applies with --collate" if options[:base]

        result = Nabu::Query::Align.new(catalog: catalog, fulltext: fulltext, registry: registry)
                                   .run(ref, work: options[:work], long: options[:long])
        print_align(result)
      end
      print_display_footer
    rescue Nabu::Query::Align::Error, Nabu::ValidationError => e
      raise Thor::Error, e.message
    ensure
      catalog&.disconnect
      fulltext&.disconnect
    end

    desc "define LEMMA", "Look up a lemma in the dictionary shelf (LSJ, L&S, Bosworth-Toller, MW, Wiktionary-OCS)"
    long_desc <<~HELP, wrap: false
      The dictionary shelf (architecture §11): look a dictionary form up in
      the lexica the corpus holds locally — LSJ (A Greek-English Lexicon,
      grc) and Lewis & Short (A Latin Dictionary, lat), both CC BY-SA from
      the Perseus Digital Library, Bosworth-Toller (An Anglo-Saxon
      Dictionary, ang; CC BY 4.0, LINDAT dump), Monier-Williams (A
      Sanskrit-English Dictionary, san; CC BY-NC-SA 3.0, Cologne CDSL —
      SLP1 transcoded to IAST, so aṃśa and amsa both reach the entry, and
      RV./BhP. citations resolve into the GRETIL shelf), and Wiktionary Old
      Church Slavonic (chu; kaikki.org extract, CC-BY-SA + GFDL —
      etymologies with their Proto-Slavic/PIE chains kept in the body).
      Entries print whole:
      headword, short gloss, then the full entry body as structured plain
      text with sense labels on their own lines (the MCP nabu_define surface
      is the bounded sibling).

      Matching folds like lemma search (conventions §9): diacritics optional
      (μηνις finds μῆνις), final sigma both ways (λόγος/λογοσ), Latin v/u j/i
      merged, Old English æ/þ/ð typeable in ASCII (aethele finds æðele,
      thing finds þing). Homographs are separate entries and all print (volo
      the verb, volo the flyer). LEMMA must be a dictionary form —
      `nabu search --lemma` finds the attestations, and its hits carry these
      glosses.

      Citations inside an entry stay as text; those that point at a work THIS
      corpus holds are additionally resolved to passage urns and listed at
      the end of the entry — `nabu show <urn>` opens the cited line. LSJ
      cites editions we may not hold (perseus-grc1 vs our grc2); resolution
      re-anchors to the in-catalog edition of the same work, preferring the
      original language over translations. Unresolvable citations (works not
      ingested, inscriptions, fragment collections) are honest misses, not
      links.

      The reconstruction shelves (P14-1, architecture §12) join in with the
      comparativist's asterisk: `define '*bogъ'` (quote the star — zsh globs
      a bare `*`) scopes to the Wiktionary Proto-Slavic/PIE/Proto-Germanic
      extracts (sla-pro/ine-pro/gem-pro), and a reconstruction entry also
      lists its descendant reflexes — with corpus attestation counts where
      the reflex is a gold lemma here. Proto headwords fold to ASCII (§9:
      ʰ→h, ʷ→w), so `define '*gʷʰew-'` and `define '*gwhew-'` reach the same
      root. `nabu etym` walks the same crosswalk from the attested side.

      An entry that STATES its etymology (the Wiktionary inherited /
      derived / borrowed templates) prints an "etymon:" line under the
      headword — its ascent, each arrow labeled with its relation, climbing
      through any etymon the shelf holds as an entry of its own (--long:
      one step per line, with that entry's urn).

      --lang grc|lat|ang|san|chu|sla-pro|ine-pro|gem-pro restricts to one
      shelf; --limit caps the entries.

      --facet NAME=PATTERN (repeatable, each must hold) keeps only entries
      the dictionary-entry facet surface tags: JMdict's domain / usage /
      dialect / loan_source labels, WOLD's semantic_field / word_class /
      borrowed_status, TLS's concept. The pattern matches the value or its
      ref, case-insensitively; LIKE patterns pass through.

      Examples:
        nabu define μῆνις              # LSJ: wrath — with Il. 1.1 resolved
        nabu define λόγος              # the long one, whole
        nabu define virtus --lang lat  # Lewis & Short only
        nabu define aethele --lang ang # Bosworth-Toller: æðele, noble
        nabu define amsa --lang san    # Monier-Williams: aṃśa/aṃsa, RV. resolved into GRETIL
        nabu define богъ --lang chu    # Wiktionary-OCS: god, ex Proto-Slavic *bogъ
        nabu define '*bogъ'            # the reconstruction, with its reflexes (quote *)
        nabu define 経 --facet domain=Buddhism  # JMdict's Buddhist-domain senses only
    HELP
    option :lang, type: :string,
                  desc: "Restrict to one dictionary language (any language on the live " \
                        "shelf — the miss message lists what is held)"
    option :limit, type: :numeric, default: Nabu::Query::Define::DEFAULT_LIMIT,
                   desc: "Maximum entries printed (homographs are separate entries)"
    option :long, type: :boolean, default: false,
                  desc: "Expand every truncated reflex list in full, grouped by language " \
                        "(compact is the default; MCP nabu_define stays bounded)"
    option :lect, type: :string, banner: "LECT-ID",
                  desc: "Restrict to shelves whose (language, source) RESOLUTION is this lect id " \
                        "or under it (P59-3; per-source overrides included — derom's la-vul " \
                        "scopes under roa, never lat); errors if the nabu-lects module is not synced"
    option :facet, type: :string, repeatable: true, banner: "NAME=PATTERN",
                   desc: "Entry facet filter — domain=medicine, usage=archaic, semantic_field=Kinship, " \
                         "concept=WORLD: matches value or ref, LIKE patterns pass through; repeatable (AND)"
    def define(*lemma_parts)
      lemma = lemma_parts.join(" ").strip
      raise Thor::Error, "define: give a lemma (e.g. λόγος, virtus)" if lemma.empty?

      facets = facet_specs(command: "define", example: "domain=Buddhism")
      config = Nabu::Config.load
      catalog = open_catalog(config)
      raise Thor::Error, "no corpus — run nabu sync or nabu rebuild" unless catalog
      unless catalog.table_exists?(:dictionary_entries)
        raise Thor::Error, "no dictionary shelf in this catalog yet — run nabu sync lexica " \
                           "(or nabu rebuild after one)"
      end
      # P106-3: the header answers from the dictionary_stats census when
      # one is derived (the desk-commands law); the live distinct scan
      # stays the pre-036/underived fallback, byte-identical.
      shelf_langs, shelf_count =
        if catalog.table_exists?(:dictionary_stats) && !catalog[:dictionary_stats].empty?
          [catalog[:dictionary_stats].distinct.order(:language).select_map(:language),
           catalog[:dictionary_stats].count]
        else
          [catalog[:dictionaries].distinct.order(:language).select_map(:language),
           catalog[:dictionaries].count]
        end
      @shelf_summary = "the shelf holds #{shelf_count} dictionaries " \
                       "(#{shelf_langs.join(', ')})"
      unless facets.empty?
        @shelf_summary += "; entry facets #{facets.map { |name, pattern| "#{name}=#{pattern}" }.join(', ')}"
      end
      if options[:lang] && !Nabu::Languages.code_variants(options[:lang]).intersect?(shelf_langs)
        raise Thor::Error, "define: --lang must be a language on the live shelf " \
                           "(#{shelf_langs.join(', ')})"
      end

      fulltext = open_fulltext(config)
      @languages = Nabu::Languages.new(catalog: catalog)
      # Fetch every matching shelf, cap at render (P34-r2): with the CJK
      # shelves live a Han headword matches 6+ dictionaries, and the old
      # fetch-time cap hid the tail silently (the gate found `define 棄`
      # missing tls-words). --long lifts the cap; compact announces it.
      results = Nabu::Query::Define.new(catalog: catalog, fulltext: fulltext)
                                   .run(lemma, lang: options[:lang], limit: nil, lect: options[:lect],
                                               facets: facets)
      shown = options[:long] ? results : results.first(options[:limit].to_i)
      print_define_results(lemma, shown, catalog: catalog)
      if (hidden = results.size - shown.size).positive?
        say format("… %<n>d more %<verb>s (--long shows all; --limit raises the cap)",
                   n: hidden, verb: hidden == 1 ? "entry matches" : "entries match")
      end
    ensure
      catalog&.disconnect
      fulltext&.disconnect
    end

    desc "etym LEMMA", "Walk an attested lemma to its reconstructions and cognates (architecture §12)"
    long_desc <<~HELP, wrap: false
      The comparativist's walk: from an ATTESTED lemma (богъ, guþ, deus) to
      every reconstruction whose descendants name it — the Wiktionary proto
      shelves (Proto-Slavic, Proto-Indo-European, Proto-Germanic, and
      (P17-3) Proto-Balto-Slavic, Proto-West Germanic, Proto-Italic,
      Proto-Indo-Iranian; kaikki.org extracts, CC-BY-SA + GFDL) and every
      other shelf carrying reflex edges (StarLing bases, MW comparanda —
      the miss message lists what is live) — then UP the ancestor chain, one indent
      per shelf hop (each shelf enters a walk once, so the chain is bounded
      and cycle-safe): прьстъ reaches *pьrstъ ← *pírštan ← *per- end to
      end. A loan-flagged edge labels its arrow "←(loan)", and a
      loan-flagged cognate reads "(loan)" (the P17-3 borrowed flag; rows
      not yet reparsed carry no label — honest unknown, not a claim).
      Each entry that states its own etymology also prints its "etymon:"
      ascent line (the `nabu define` line, relation-labeled arrows).

      Every cognate reflex that is a gold lemma in this catalog carries its
      attestation count (searchable via `nabu search --lemma`); the rest
      are listed honestly as "not attested here". Romanization bridges
      scripts — guþ reaches *gudą through Gothic 𐌲𐌿𐌸 — and the folding is
      the conventions §9 contract (diacritics optional).

      An unstarred lemma that names no descendant FALLS BACK to a
      reconstruction-headword lookup, so the proto form itself resolves —
      typed with its phonetic superscripts (`etym bʰewgʰ`) or in pure ASCII
      (`etym bhewgh`, the §9 fold ʰ→h/ʷ→w), root hyphen optional. A quoted
      leading asterisk looks a reconstruction up directly (`etym '*bogъ'`,
      like `define '*bogъ'`) — quote the star, zsh globs a bare `*`; the
      bare-form fallback makes it mostly unnecessary. --lang scopes the
      attested match; --limit caps the entries. The MCP sibling is nabu_etym
      (bounded); this CLI prints everything.

      A lemma with NO crosswalk path at all falls back once more (P24-2) —
      to the same lookup `nabu define` runs: a prose etymological article
      (Vasmer's Russian dictionary carries no reflex edges) still answers,
      rendered in the define format under an honest "no reconstruction
      path in the crosswalk" header. A genuine total miss enumerates the
      crosswalk's live shelves, derived from the catalog.

      Examples:
        nabu etym богъ --lang chu     # Zographensis god → *bogъ → *bʰeh₂g-
        nabu etym guþ --lang got      # Gothic → *gudą → *ǵʰutós
        nabu etym bhewgh              # bare ASCII proto form → *bʰewgʰ-
        nabu etym '*kaisaraz'         # direct lookup (quoted — zsh globs *)
    HELP
    option :lang, type: :string, banner: "chu|orv|got|grc|lat|…",
                  desc: "Scope the attested-lemma match to one language"
    option :limit, type: :numeric, default: Nabu::Query::Etym::DEFAULT_LIMIT,
                   desc: "Maximum reconstruction entries printed"
    option :long, type: :boolean, default: false,
                  desc: "Expand every truncated cognate list in full, grouped by language " \
                        "(compact is the default; MCP nabu_etym stays bounded)"
    def etym(*lemma_parts)
      lemma = lemma_parts.join(" ").strip
      raise Thor::Error, "etym: give a lemma (e.g. богъ, guþ) or *reconstruction" if lemma.empty?

      config = Nabu::Config.load
      catalog = open_catalog(config)
      raise Thor::Error, "no corpus — run nabu sync or nabu rebuild" unless catalog
      unless catalog.table_exists?(:dictionary_reflexes)
        raise Thor::Error, "no reconstruction shelf in this catalog yet — run " \
                           "nabu sync wiktionary-recon (or nabu rebuild after one)"
      end

      fulltext = open_fulltext(config)
      @languages = Nabu::Languages.new(catalog: catalog)
      @lects = Nabu::Lects.load_default(config: config)
      query = Nabu::Query::Etym.new(catalog: catalog, fulltext: fulltext)
      results = query.run(lemma, lang: options[:lang], limit: options[:limit].to_i)
      if results.empty?
        # P24-2 coordination (owner incident 2026-07-16: define found the
        # Vasmer сигать article, etym missed flat): on a crosswalk miss,
        # fall back to the SAME Query::Define lookup the define command
        # runs — one execution path, rendered in the define house format.
        # Fallback fires ONLY on a miss: etym's primary contract stays the
        # walk, hits are never mixed.
        entries = Nabu::Query::Define.new(catalog: catalog, fulltext: fulltext)
                                     .run(lemma, lang: options[:lang], limit: options[:limit].to_i)
        print_etym_fallback(lemma, entries, shelves: query.crosswalk_shelves)
      else
        print_etym_results(results)
      end
    ensure
      catalog&.disconnect
      fulltext&.disconnect
    end

    desc "lemma FORM", "A lemma's attestation profile: first/last century, the gold/silver curve, sources"
    long_desc <<~HELP, wrap: false
      Reads the precompiled lemma rollup (built at rebuild and by
      `rake builders:refresh`, refreshed per source after every sync) — never
      the passages themselves, so the card is instant at any corpus size.

      - FIRST / LAST attested century, each with its date basis: "artifact"
        (the object/witness date the source asserts) or "composition"
        (author-era dating). A document's century is the MIDPOINT of its
        date envelope (300–30 BCE buckets as 2nd c. BCE).
      - The per-century curve, gold (verified annotation) and silver
        (automatic lemmatization) kept apart: attestations / documents per
        century, then one sparkline row per grade on a shared scale.
        Undated attestations close the table.
      - The top sources, and the dictionary shelves carrying the form.

      An attestation is one passage attesting the lemma (the lemma-index
      grain). FORM folds like `search --lemma`; --lang scopes to one
      language (every stored spelling of the code).

        nabu lemma hostis --lang lat
        nabu lemma λόγος --lang grc
    HELP
    option :lang, type: :string, aliases: ["--language"], banner: "CODE",
                  desc: "Scope to one language (lat, grc…; --language is an alias)"
    def lemma(form)
      config = Nabu::Config.load
      catalog = open_catalog(config)
      raise Thor::Error, "lemma: no catalog — run nabu sync or nabu rebuild" if catalog.nil?

      result = Nabu::Query::LemmaProfile.new(catalog: catalog).run(form, language: options[:lang])
      print_lemma_profile(result)
    ensure
      catalog&.disconnect
    end

    SPARK_LEVELS = %w[▁ ▂ ▃ ▄ ▅ ▆ ▇ █].freeze

    ROLLUP_REFRESH_HINT = "run `bundle exec rake builders:refresh` (or the next nabu rebuild)"

    ROLLUP_MIGRATION_HINT = "this catalog predates the lemma rollups (migration 038) — " \
                            "the next nabu rebuild builds them"

    no_commands do
      # The honest hints of the absent/unbuilt rollup (the desk law: a hint,
      # never a scan).
      def rollup_status_error(command, status)
        case status
        when :absent then raise Thor::Error, "#{command}: #{ROLLUP_MIGRATION_HINT}"
        when :unbuilt then raise Thor::Error, "#{command}: the rollup is not built yet — #{ROLLUP_REFRESH_HINT}"
        end
      end

      def print_lemma_profile(result)
        rollup_status_error("lemma", result.status)
        scope = result.language ? " [#{result.language}]" : ""
        if result.status == :unattested
          say "lemma #{result.form}#{scope}: not attested in the lemma rollup (gold or silver)"
          print_lemma_dictionary(result.dictionary)
          return say("lemma: 0 attestations (#{format_duration(result.seconds)})")
        end

        say "lemma #{result.form}#{scope_label(result)} — #{lemma_span(result)}"
        print_lemma_curve(result.curve)
        print_lemma_sources(result.sources)
        print_lemma_dictionary(result.dictionary)
        total = result.curve.sum { |point| point.gold[:occurrences] + point.silver[:occurrences] }
        say "lemma: #{commafy(total)} attestations · " \
            "#{dated_centuries(result.curve.count(&:century))} " \
            "(#{format_duration(result.seconds)})"
      end

      def dated_centuries(count) = "#{count} dated #{count == 1 ? 'century' : 'centuries'}"

      def scope_label(result)
        result.language ? " [#{result.language}]" : " [#{result.languages.join(', ')}]"
      end

      def lemma_span(result)
        return "no dated attestation (every attestation is undated)" unless result.first

        edge = ->(point) { "#{point.label}#{" (#{point.bases.join(', ')})" if point.bases.any?}" }
        return "attested in #{edge.call(result.first)} only" if result.first.century == result.last.century

        "first attested #{edge.call(result.first)} · last #{edge.call(result.last)}"
      end

      def print_lemma_curve(curve)
        width = (curve.map { |point| point.label.length } + [7]).max
        say "  #{'century'.ljust(width)}  #{'gold att/docs'.rjust(16)}  #{'silver att/docs'.rjust(16)}"
        curve.each do |point|
          say "  #{point.label.ljust(width)}  #{grade_cell(point.gold).rjust(16)}  " \
              "#{grade_cell(point.silver).rjust(16)}"
        end
        dated = curve.reject { |point| point.century.nil? }
        return if dated.empty?

        peak = dated.flat_map { |point| [point.gold[:occurrences], point.silver[:occurrences]] }.max
        %i[gold silver].each do |grade|
          next if dated.all? { |point| point.public_send(grade)[:occurrences].zero? }

          say "  #{grade.to_s.ljust(6)} #{sparkline(dated, grade, peak)}  " \
              "(#{dated.first.label} → #{dated.last.label}, one cell per century)"
        end
      end

      def grade_cell(tally)
        tally[:occurrences].zero? ? "—" : "#{commafy(tally[:occurrences])} / #{commafy(tally[:documents])}"
      end

      # One cell per century across the contiguous dated span (no century
      # 0 — the signed index skips it), on a scale shared by both grades so
      # the rows compare; "·" = no attestation that century.
      def sparkline(dated, grade, peak)
        by_century = dated.to_h { |point| [point.century, point.public_send(grade)[:occurrences]] }
        (dated.first.century..dated.last.century).reject(&:zero?).map do |century|
          count = by_century.fetch(century, 0)
          next "·" if count.zero?

          SPARK_LEVELS[((count.to_f / peak) * (SPARK_LEVELS.size - 1)).round]
        end.join
      end

      def print_lemma_sources(sources)
        return if sources.empty?

        cells = sources.map do |share|
          grades = []
          grades << "#{commafy(share.gold)} gold" if share.gold.positive?
          grades << "#{commafy(share.silver)} silver" if share.silver.positive?
          "#{share.slug} #{grades.join(' + ')}"
        end
        say "  top sources: #{cells.join(' · ')}"
      end

      def print_lemma_dictionary(links)
        return if links.empty?

        say "  dictionaries (nabu define for the full entry):"
        links.each do |link|
          gloss = link.gloss ? " — #{truncate_line(link.gloss, 70)}" : ""
          say "    #{link.slug}: #{link.headword}#{gloss}  #{link.urn}"
        end
      end

      # -- align (P11-3) ----------------------------------------------------

      # Render the cross-source alignment: the ref + work header with an
      # honest attestation count, then one block per witness in registry
      # order — title, language, license label, and the sentences (urn line,
      # text line), a multi-verse sentence labeled with its full span.
      def print_align(result)
        return print_align_range(result) if result.is_a?(Nabu::Query::Align::RangeResult)

        attesting = result.witnesses.count { |witness| witness.status == :ok }
        say "#{result.ref} — #{result.title}"
        say "  #{attesting} of #{result.witnesses.size} witnesses attest this ref"
        result.witnesses.each { |witness| print_align_witness(witness, result.ref) }
      end

      # A range/chapter query (P11-8): the query header, a one-line witness
      # legend (title/lang/license shown ONCE, not repeated per ref), then one
      # compact block per ref in document order — ref line, then one line per
      # witness (its text, or an honest not-attested/not-synced dash).
      def print_align_range(result)
        say "#{result.query} — #{result.title}"
        say "  #{result.total} refs; witnesses: #{align_range_legend(result).join('; ')}"
        say "  #{absent_range_summary(result.absent)}" unless result.absent.empty?
        if result.truncated
          say "  showing first #{result.groups.size} of #{result.total} refs " \
              "(cap #{Nabu::Query::Align::MAX_REFS}) — narrow the range, or pass --long to render all"
        end
        result.groups.each { |group| print_align_range_group(group) }
      end

      # P11-9: witnesses absent from every rendered ref are summarized here once
      # (grouped by reason) rather than dashed on every ref line — the owner's
      # readability fix. Partially-attested witnesses stay in the per-ref blocks.
      def absent_range_summary(absent)
        by_reason = absent.group_by(&:reason)
        parts = []
        if (rows = by_reason[:not_attested])
          parts << "not attested in this range: #{rows.map(&:label).join(', ')}"
        end
        if (rows = by_reason[:not_synced])
          parts << "not synced: #{rows.map(&:label).join(', ')}"
        end
        parts.join("; ")
      end

      # One legend entry per witness (registry order): its language + license
      # from the richest view across the shown refs, or "not synced" when the
      # witness holds no data anywhere in the range.
      def align_range_legend(result)
        result.groups.first.witnesses.map(&:label).map do |label|
          views = result.groups.map { |group| group.witnesses.find { |witness| witness.label == label } }
          synced = views.find { |witness| witness.status != :not_synced }
          if synced
            "#{label} [#{synced.language}] license: #{synced.license_class}#{align_numbering_note(synced)}"
          else
            "#{label} not synced"
          end
        end
      end

      def print_align_range_group(group)
        say ""
        say group.ref
        group.witnesses.each { |witness| print_align_range_witness(witness, group.ref) }
      end

      def print_align_range_witness(witness, ref)
        case witness.status
        when :not_synced then say "    #{witness.label} — not synced"
        when :no_match   then say "    #{witness.label} — not attested"
        else
          witness.sentences.each do |sentence|
            say "    #{witness.label}  #{display_text(sentence.text, witness.language)}" \
                "#{align_native_note(witness, sentence)}#{align_span_note(sentence, ref)}"
          end
        end
      end

      def print_align_witness(witness, ref)
        say ""
        if witness.status == :not_synced
          # A nil urn = a multi-book witness whose map lacks this ref's book;
          # naming an unrelated book's urn would mislead — phrase neutrally.
          detail = if witness.document_urn
                     "#{witness.document_urn} is registered but not in the catalog"
                   else
                     "its registered documents are not in the catalog"
                   end
          say "#{witness.label} — not synced (#{detail})"
          return
        end

        # A multi-document witness misses without a book to name — no title.
        say "#{witness.label}#{" — #{witness.title}" if witness.title} [#{witness.language}]   " \
            "license: #{witness.license_class}#{align_numbering_note(witness)}"
        return say "  not attested (this witness lacks #{ref})" if witness.status == :no_match

        witness.sentences.each do |sentence|
          say "  #{sentence.urn}#{align_native_note(witness, sentence)}#{align_span_note(sentence, ref)}"
          say "    #{display_text(sentence.text, witness.language)}"
        end
      end

      # "  · Hebrew (Masoretic) numbering" — flags a witness whose psalter is
      # numbered in a different system than the work vocabulary (P13-5), so the
      # reader knows its refs were remapped to align.
      def align_numbering_note(witness)
        witness.numbering ? "   · #{witness.numbering} numbering" : ""
      end

      # "  [Hebrew (Masoretic): PSA 23.1]" — the witness's OWN ref for this
      # sentence, shown only when its numbering diverges from the queried ref.
      def align_native_note(witness, sentence)
        return "" unless sentence.native_ref

        "  [#{witness.numbering}: #{sentence.native_ref}]"
      end

      # "  [covers MARK 2.3, MARK 2.4]" — only when the sentence spans beyond
      # the queried ref (sentence≠verse, stated honestly).
      def align_span_note(sentence, ref)
        return "" if sentence.refs == [ref]

        "  [covers #{sentence.refs.join(', ')}]"
      end

      # -- align --collate (P15-4) ------------------------------------------------

      # The collation apparatus (intertext-design §2): the query/work header,
      # then one block per ref — each (language, script) cell as a base reading
      # plus the per-witness divergences, uncollated cross-script/sole witnesses
      # rendered undiffed and honestly, and any missing witnesses named once.
      def print_collation(result, long:)
        say "#{result.query} — #{result.title} · collation"
        if result.truncated
          say "  showing first #{result.refs.size} of #{result.total} refs " \
              "(cap #{Nabu::Query::Align::MAX_REFS}) — narrow the range, or pass --long to render all"
        end
        result.refs.each do |ref_collation|
          say ""
          say ref_collation.ref if result.refs.size > 1
          print_collation_ref(ref_collation, long: long)
        end
      end

      def print_collation_ref(ref_collation, long:)
        say "  no witness attests this ref" if ref_collation.cells.empty? && ref_collation.asides.empty?
        ref_collation.cells.each { |cell| print_collation_cell(cell, long: long) }
        ref_collation.asides.each { |aside| print_collation_aside(aside) }
        print_collation_missing(ref_collation.missing)
      end

      # One collated cell: the base line in full, then each other witness — its
      # full tokens under --long, "(agrees with base)" when identical, else its
      # apparatus of divergences (agreements elided).
      def print_collation_cell(cell, long:)
        base = cell.readings.find(&:is_base)
        say "  [#{cell.language}/#{cell.script}] #{cell.readings.size} witnesses, base #{cell.base_label}"
        say "    = #{base.label}  #{display_text(base.tokens.join(' '), cell.language)}"
        cell.readings.reject(&:is_base).each do |reading|
          say "      #{reading.label}  #{collation_reading_body(reading, long: long, language: cell.language)}"
        end
      end

      def collation_reading_body(reading, long:, language:)
        return display_text(reading.tokens.join(" "), language) if long
        return "(agrees with base)" if reading.edits.empty?

        reading.edits.map { |edit| format_collation_edit(edit, language) }.join("; ")
      end

      # Apparatus marks: a substitution as "base → variant", an omission as
      # "om. base" (the witness lacks it), an insertion as "add. variant".
      def format_collation_edit(edit, language)
        case edit.op
        when :sub
          "#{display_text(edit.base.join(' '), language)} → #{display_text(edit.witness.join(' '), language)}"
        when :del then "om. #{display_text(edit.base.join(' '), language)}"
        when :ins then "add. #{display_text(edit.witness.join(' '), language)}"
        end
      end

      # An uncollated witness: rendered undiffed, its reason stated plainly —
      # cross-script (the fold cannot bridge the transcription systems) or the
      # sole witness of its language here.
      def print_collation_aside(aside)
        reason = if aside.reason == :cross_script
                   "not collated — different transcription system, the fold cannot bridge it"
                 else
                   "not collated — sole witness of its language here"
                 end
        say "  [#{aside.language}/#{aside.script}] #{aside.label}  license: #{aside.license_class}  (#{reason})"
        say "    #{display_text(aside.text, aside.language)}"
      end

      def print_collation_missing(missing)
        no_match = missing.select { |witness| witness.status == :no_match }.map(&:label)
        not_synced = missing.select { |witness| witness.status == :not_synced }.map(&:label)
        withheld = missing.select { |witness| witness.status == :withheld }.map(&:label)
        say "  not attested here: #{no_match.join(', ')}" unless no_match.empty?
        say "  not synced: #{not_synced.join(', ')}" unless not_synced.empty?
        say "  license-withheld: #{withheld.join(', ')}" unless withheld.empty?
      end

      # Render dictionary entries whole (the CLI is the unbounded surface):
      # header with license label, gloss, the structured body, then the
      # resolved citations as show-able urns. Unresolved citations already
      # read inline in the body text.
      # +catalog+ (P24-1): when given, each entry's owner notes render after
      # its body — the note lane on the dictionary surface.
      def print_define_results(lemma, results, catalog: nil)
        if results.empty?
          return say("no dictionary entry for #{lemma} — #{@shelf_summary}; " \
                     "give a dictionary form (search --lemma finds attestations)")
        end

        crosswalk = define_crosswalk(results)
        results.each_with_index do |result, index|
          say "" if index.positive?
          print_define_entry(result)
          print_define_crosswalk(result, crosswalk, catalog)
          print_notes_footer(catalog, result) if catalog
        end
      end

      # P96 rider (the owner's 2026-09-04 challenge): the entry
      # crosswalk's value surfaces ON the card, not behind `nabu links`.
      # Per entry: a "first attested" line whenever a reference edge
      # carries one, and a "=" crosslink ONLY when the counterpart's
      # folded headword DIFFERS (the fold-invisible pairs — balzam↔bolzam
      # — where the curated identity does what no string search can;
      # same-headword pairs stay silent, define already shows them).
      # Absent links db = absent section, never an error.
      def define_crosswalk(results)
        config = Nabu::Config.load
        return {} unless File.exist?(config.links_path)

        journal = Nabu::Store::LinksJournal.connect(config.links_path, readonly: true)
        urns = results.map(&:urn)
        edges = journal[:links]
                .where(kind: "reference")
                .where(Sequel.|({ from_urn: urns }, { to_urn: urns }))
                .select(:from_urn, :to_urn, :detail).all
        edges.group_by { |e| urns.include?(e[:from_urn]) ? e[:from_urn] : e[:to_urn] }
      rescue Sequel::Error
        {}
      ensure
        journal&.disconnect
      end

      def print_define_crosswalk(result, crosswalk, catalog)
        own_folded = Nabu::Normalize.search_form(result.headword, language: result.language)
        Array(crosswalk[result.urn]).each do |edge|
          other = edge[:from_urn] == result.urn ? edge[:to_urn] : edge[:from_urn]
          if (attested = edge[:detail].to_s[/first attested: (.+)\z/, 1])
            say "  first attested: #{attested.strip}"
          end
          counterpart = dict_entry_headword(catalog, other)
          next unless counterpart && counterpart[:headword_folded] != own_folded

          say "  = #{counterpart[:headword]} — #{other} (the crosswalk joins spellings " \
              "no string search connects)"
        end
      end

      def dict_entry_headword(catalog, urn)
        return nil unless catalog

        @define_headwords ||= {}
        return @define_headwords[urn] if @define_headwords.key?(urn)

        @define_headwords[urn] =
          catalog[:dictionary_entries].where(urn: urn).select(:headword, :headword_folded).first
      end

      # One entry, the define house format — shared verbatim by `show` on a
      # dictionary-entry urn (P22-2), where a withdrawn entry reads honestly.
      # The language code rides the header (P46-r6, owner report: a WOLD hit
      # named no language — obvious for LSJ, load-bearing for the
      # multi-language shelves), the etym-entry style.
      def print_define_entry(result)
        lang = result.language.to_s.empty? ? "" : " [#{result.language}]"
        say "#{result.headword}#{lang} — #{result.dictionary_title} [#{result.license_class}]" \
            "#{' (withdrawn)' if result.withdrawn}  #{result.urn}"
        say "  gloss: #{result.gloss}" if result.gloss
        print_etymon_line(result.etymons)
        say ""
        say result.body
        print_reflexes(result.reflexes)
        print_etymon_ascent(result.etymons) if options[:long]
        print_resolved_citations(result)
        print_crossrefs(result)
      end

      # The etymon line: the entry's OWN stated etymology (the typed UP
      # edges — inherited / derived / borrowed / learned-borrowing) climbed
      # up the shelf (Query::EtymonAscent), one compact line under the
      # headword, each arrow labeled with its relation — the etym chain's
      # "←(loan)" idiom. Compact by default (house rule): the first
      # six steps, the tail counted; --long lists every step with
      # its held entry's urn below the body instead. No stated etymology,
      # no line.
      def print_etymon_line(etymons, indent: "")
        etymons = Array(etymons)
        return if etymons.empty? || options[:long]

        shown = etymons.first(6)
        line = shown.map { |step| "#{etymon_arrow(step)} #{etymon_form(step)} [#{step.lang_code}]" }.join(" ")
        rest = etymons.size - shown.size
        line += " … and #{rest} more (--long shows all)" if rest.positive?
        say "#{indent}  etymon: #{line}"
      end

      # --long: one step per line, indented by climb hop, the code named
      # (reflex_group_label — the --long reflex groups' label), a held
      # etymon's own entry urn beside it.
      def print_etymon_ascent(etymons)
        etymons = Array(etymons)
        return if etymons.empty?

        say ""
        say "etymon (stated ascent):"
        etymons.each do |step|
          urn = step.urn ? "  #{step.urn}" : ""
          say "#{'  ' * (step.hop + 1)}#{etymon_arrow(step)} #{etymon_form(step)} " \
              "#{reflex_group_label(step.lang_code)}#{urn}"
        end
      end

      def etymon_arrow(step) = "←(#{step.relation})"

      def etymon_form(step) = step.roman && step.roman != step.word ? "#{step.word} (#{step.roman})" : step.word

      # P123-1: entry→entry cross-references — a resolved pointer names
      # its target entry's urn (one `nabu show` away); an unresolved one
      # renders as its verbatim text, never a dead link. Compact cap like
      # the citations; --long shows all.
      def print_crossrefs(result)
        crossrefs = Array(result.crossrefs)
        return if crossrefs.empty?

        say ""
        say "cross-references:"
        shown = options[:long] ? crossrefs : crossrefs.first(12)
        shown.each do |crossref|
          line = "  #{crossref.label} (#{crossref.kind})"
          line += " → #{crossref.resolved_headword} #{crossref.resolved_urn}" if crossref.resolved_urn
          say line
        end
        rest = crossrefs.size - shown.size
        say "  … and #{rest} more (--long shows all)" if rest.positive?
      end

      # A reconstruction entry's descendant reflexes (P14-1): attested-here
      # cognates first with their gold-lemma passage counts, then an honest
      # one-line summary of the rest (the full tree is in the data; the
      # attested ones are the actionable ones).
      #
      # The tier rule (P26-0): attested_count IS the gold count — a silver
      # (automatic-lemmatization) count renders beside it as "(+N silver)",
      # and a silver-ONLY reflex gets its own labeled section, "silver N
      # passages". NEVER a bare number that could read as gold. The
      # equivalence tier (P34-3) rides the same contract with its own name:
      # "(+N equivalence)" beside gold, an equivalence-only section below —
      # scholar-curated Classical-Latin equivalents on non-Latin passages,
      # never attestation.
      def print_reflexes(reflexes)
        return if reflexes.empty?

        attested, uncounted = reflexes.partition(&:attested_count)
        silver_only, unattested = uncounted.partition(&:silver_count)
        equivalence_only, rest = unattested.partition(&:equivalence_count)
        unless attested.empty?
          say ""
          say "attested in this corpus (nabu search --lemma):"
          attested.sort_by { |r| -r.attested_count }.each do |r|
            say "  [#{r.language}] #{reflex_form(r)} — #{r.attested_count} " \
                "#{r.attested_count == 1 ? 'passage' : 'passages'}#{tier_suffixes(r)}"
          end
        end
        unless silver_only.empty?
          say ""
          say "silver-only (automatic lemmatization — not gold-attested; nabu search --lemma):"
          silver_only.sort_by { |r| -r.silver_count }.each do |r|
            say "  [#{r.language}] #{reflex_form(r)} — silver #{r.silver_count} " \
                "#{r.silver_count == 1 ? 'passage' : 'passages'}"
          end
        end
        unless equivalence_only.empty?
          say ""
          say "equivalence-only (scholar-curated Classical-Latin equivalents on non-Latin " \
              "passages — not attested in this language; nabu search --lemma):"
          equivalence_only.sort_by { |r| -r.equivalence_count }.each do |r|
            say "  [#{r.language}] #{reflex_form(r)} — equivalence #{r.equivalence_count} " \
                "#{r.equivalence_count == 1 ? 'passage' : 'passages'}"
          end
        end
        return if rest.empty?

        say ""
        options[:long] ? print_reflexes_expanded(rest) : print_reflexes_capped(rest)
      end

      # The labeled non-gold riders on a gold-attested line (P26-0 silver,
      # P34-3 equivalence) — each tier under its own name, never summed.
      def tier_suffixes(reflex)
        suffix = reflex.silver_count ? " (+#{reflex.silver_count} silver)" : ""
        suffix += " (+#{reflex.equivalence_count} equivalence)" if reflex.equivalence_count
        suffix
      end

      # Compact default (house compact-CLI rule): the first ten non-attested
      # reflexes inline, the tail honestly summarised as "… and N more".
      def print_reflexes_capped(rest)
        say "other reflexes (not attested here): " \
            "#{rest.first(10).map { |r| "[#{r.lang_code}] #{reflex_form(r)}" }.join(', ')}" \
            "#{" … and #{rest.size - 10} more" if rest.size > 10}"
      end

      # --long (P14-11): the WHOLE non-attested list, grouped by language so a
      # long tail (a Proto-Slavic root can name 25+ descendants) stays readable
      # — languages in first-seen (stored depth-first) order, forms within a
      # language in stored order. Nothing is elided under the flag.
      # P18-4 render verdict: each group header carries the code's NAME
      # inline when the library knows one ("[gkm · Medieval Greek]") — one
      # name per LINE, so the compact rule holds exactly where the owner's
      # pain was; the capped default stays code-only (ten names inline would
      # blow the line) and etym's footer points at `nabu language` instead.
      # P57-4: when Nabu::Lects is present the label prefers the RESOLVED
      # lect id + its composed registry name ("[grc:byz · Byzantine Greek]"
      # for gkm — the codemap default) over the old kaikki-census reading;
      # absent Lects, or a resolved id with no registry entry, unchanged.
      def print_reflexes_expanded(rest)
        say "other reflexes (not attested here) — all #{rest.size}, grouped by language:"
        rest.group_by(&:lang_code).each do |lang_code, group|
          say "  #{reflex_group_label(lang_code)} #{group.map { |r| reflex_form(r) }.join(', ')}"
        end
      end

      def reflex_group_label(lang_code)
        if @lects
          resolved = @lects.resolve(lang_code)
          lect = @lects.lect(resolved)
          return "[#{resolved} · #{lect.name}]" if lect
        end
        name = @languages&.name(lang_code)
        name ? "[#{lang_code} · #{name}]" : "[#{lang_code}]"
      end

      # P17-3: the per-edge loan label — a borrowed-flagged reflex reads
      # "(loan)"; unflagged and not-yet-reparsed (NULL) edges stay bare.
      # P76 U-6: the kaikki doubt tag appends " (uncertain)" — the WOLD
      # idiom, upstream word verbatim (conventions §12).
      def reflex_form(reflex)
        base = reflex.roman && reflex.roman != reflex.word ? "#{reflex.word} (#{reflex.roman})" : reflex.word
        base = "#{base} (loan)" if reflex.borrowed
        base = "#{base} (uncertain)" if reflex.respond_to?(:uncertain) && reflex.uncertain
        base
      end

      # etym (P14-1; multi-hop P17-3): one block per entry — where the walk
      # entered (matched reflex → *headword), the entry's own reflex list,
      # then the ancestor CHAIN, indented one step per shelf hop (the
      # shelf-visited walk: богъ → *bogъ ← *bogù ← *bʰag-). A loan edge
      # labels its arrow: "←(loan)". --long expands the cognate lists; the
      # chain itself is already bounded (each shelf enters once per walk).
      def print_etym_results(results)
        results.each_with_index do |result, index|
          say "" if index.positive?
          print_etym_entry(result, 0)
        end
        # P18-4: one footer line, the desk-reference pointer — the compact
        # render keeps raw codes, this names the way out.
        say ""
        say "codes: nabu language CODE — name, context, and what this library holds"
      end

      # P24-2: the crosswalk-miss path. When the dictionary shelf holds the
      # lemma (Vasmer's prose etymologies carry no reflex edges), render
      # those entries in the define house format under an honest header —
      # print_define_entry, zero renderer divergence. A genuine total miss
      # enumerates the crosswalk shelves DB-DRIVEN (Query::Etym
      # #crosswalk_shelves — the P11 DEFINE_LANGS hardcoded-list lesson),
      # keeping the '*form' quoting hint.
      def print_etym_fallback(lemma, entries, shelves:)
        if entries.empty?
          covered = shelves.empty? ? "no shelves yet (run nabu sync wiktionary-recon)" : shelves.join(", ")
          return say("no reconstruction names #{lemma} as a descendant, no reconstruction " \
                     "headword matches it, and no dictionary entry defines it — the crosswalk " \
                     "covers #{covered} (nabu language CODE explains any). Try the lemma's " \
                     "dictionary form, or a quoted '*form' for a direct lookup (quote the " \
                     "star — zsh expands a bare *)")
        end

        say "no reconstruction path in the crosswalk for #{lemma} — the dictionary shelf holds:"
        entries.each do |result|
          say ""
          print_define_entry(result)
        end
      end

      def print_etym_entry(result, depth)
        indent = "  " * depth
        arrow = if depth.positive?
                  result.edge_borrowed ? "←(loan) " : "← "
                else
                  ""
                end
        say "#{indent}#{arrow}#{etym_entry_line(result)}  #{result.urn}"
        say "#{indent}  gloss: #{result.gloss}" if result.gloss
        print_etymon_line(result.etymons, indent: indent)
        print_reflexes(result.cognates)
        print_etymon_ascent(result.etymons) if options[:long]
        result.ancestors.each do |ancestor|
          say ""
          print_etym_entry(ancestor, depth + 1)
        end
      end

      def etym_entry_line(result)
        via = result.matched_reflex
        prefix =
          if via
            "#{via.word} [#{lect_bracket(via.language, via.lect_id, via.lect_name)}]" \
              "#{' (loan)' if via.borrowed}#{' (uncertain)' if via.uncertain} → "
          else
            ""
          end
        "#{prefix}#{result.headword} [#{lect_bracket(result.language, result.lect_id, result.lect_name)}] — " \
          "#{result.dictionary_title} [#{result.license_class}]"
      end

      # P57-4 (etym display through the mapping): when Nabu::Lects is
      # present AND the resolved id has a registry entry, render "id ·
      # name" instead of the bare stored code — display-only, the raw code
      # is never touched. Absent either condition, the bracket is exactly
      # the raw code, unchanged.
      def lect_bracket(code, lect_id, lect_name)
        lect_id && lect_name ? "#{lect_id} · #{lect_name}" : code
      end

      # Compact default (house compact-CLI rule, the print_reflexes
      # precedent's inline-cap shape): TLS attestation citations (P34-4)
      # put thousands of resolved rows on common words (之 carries 2,587
      # attestations), so the first 12 print inline and the tail is
      # summarised; --long expands every one. LSJ/MW-scale entries sit
      # under the cap and never see it.
      def print_resolved_citations(result)
        resolved = result.citations.select(&:resolved_urn)
        return if resolved.empty?

        say ""
        say "resolved citations (in this corpus — nabu show <urn>):"
        shown = options[:long] ? resolved : resolved.first(12)
        shown.each { |citation| say "  #{citation.label} → #{citation.resolved_urn}" }
        rest = resolved.size - shown.size
        say "  … and #{rest} more (--long shows all)" if rest.positive?
      end
    end
  end
end

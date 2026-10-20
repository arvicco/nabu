# frozen_string_literal: true

require "io/console"
require "thor"
require_relative "version"
require_relative "display"
require_relative "duration_format"
require_relative "cli/data"
require_relative "cli/lect"
require_relative "cli/layer"
require_relative "cli/index"
require_relative "cli/creds"
require_relative "cli/export"

# CLI flag conventions (P90-3 standing rules, applied whenever a command is
# next touched — never as a sweep):
#   ① `--lang` is the ONE language-filter spelling, accepting a comma list
#      where plural makes sense; legacy spellings (`--langs`, `--languages`)
#      stay as quiet aliases of it.
#   ② `--json` is the machine-readable opt-in convention (`--format` is
#      reserved for commands with more than two real formats).
module Nabu
  # Command-line entry point. Only `version` is functional in Phase 0; the
  # ingest/query subcommands are stubs that report "not implemented" and exit 1
  # so scripts and CI can rely on the failure signal before the real work lands.
  class CLI < Thor
    include DurationFormat

    # The DataCLI namespace note applies at the root too: without it Thor
    # 1.5's `tree` labels its root with the class auto-namespace ("nabu:c_l_i").
    namespace "nabu"

    # The tag-semantics note the axis-grouped surfaces (`list --axis`,
    # `status --axis`, P35-1) state ONCE: axes are TAGS over the source list,
    # so a source appears under every axis it serves — never a folder owning it.
    AXIS_TAG_NOTE = "Axes are tags, not folders — a source appears under every desk it serves."

    # Raise Thor::Error (rather than aborting the process abruptly) so failures
    # surface a clean stderr message and a non-zero exit status.
    def self.exit_on_failure?
      true
    end

    # `nabu search --help` (owner report 2026-07-18): this Thor build does
    # not intercept a help flag AFTER a command name, so "--help" reached
    # FTS5 as the literal query. Route `nabu CMD --help|-h` to `nabu help
    # CMD` for every known command; a literal "--help" stays searchable via
    # quoting inside a longer query (the fts literal fallback).
    def self.start(given_args = ARGV, config = {})
      if Thor::HELP_MAPPINGS.include?(given_args[1]) &&
         all_commands.key?(normalize_command_name(given_args.first.to_s))
        given_args = ["help", given_args.first]
      end
      # P44-i1b: a ^C is an OPERATOR DECISION, not a crash — one honest line
      # and the conventional 130, never a thread-backtrace storm. (Open3's
      # internal reader threads also die noisily at interrupt; bin/nabu turns
      # their report_on_exception chatter off.) State safety is the atomic
      # fetchers' job — an interrupted acquisition leaves staging debris the
      # next run sweeps, announced.
      super
    rescue Interrupt
      warn "\ninterrupted — partial work is staged safely; the next run cleans up and starts fresh."
      exit 130
    end

    # The --display flag, shared by every command that renders passage text to
    # the terminal (P27-0: show, align, search, concord, parallels, cognates).
    # Modes come from the Nabu::Display registry so sibling packets can add
    # modes (reading, …) without touching this declaration.
    def self.display_option
      option :display, type: :string, default: Nabu::Display::DEFAULT_MODE, banner: "MODE",
                       desc: "Display mode: default (config/display.yml policies), " \
                             "full (every stored byte, no transforms), plain (strip all " \
                             "defined mark classes), reading (edition apparatus simplified, " \
                             "qere read), diplomatic (edition marks as stored), " \
                             "translit (romanized rendering), " \
                             "mono (default without token colors) — see docs/display.md"
    end

    desc "version", "Print the Nabu version"
    def version
      say Nabu::VERSION
    end

    desc "data SUBCOMMAND ...ARGS", "The nabu-data production rail: document and build publishable derived datasets"
    subcommand "data", DataCLI

    desc "lect SUBCOMMAND ...ARGS", "Per-document lect rulings: the journaled overlay tier of lect resolution"
    subcommand "lect", LectCLI

    desc "creds SUBCOMMAND ...ARGS", "Stored upstream credentials (gated member areas): set, list"
    subcommand "creds", CredsCLI

    # P61-2: `nabu layer` is the core-layers front door — today one
    # command, `suggest`, the generalized census (lect + dating + places +
    # script sections). `nabu lect suggest` stays as the historical alias;
    # both run the same report.
    desc "layer SUBCOMMAND ...ARGS", "Core-layer postures: the generalized suggest front door"
    subcommand "layer", LayerCLI

    # P112-3: the fulltext-index operations surface — gauges,
    # freshness stamps, and the standalone merge consolidation.
    desc "index SUBCOMMAND ...ARGS", "Fulltext-index operations: doctor (gauges + freshness)"
    subcommand "index", IndexCLI

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

    desc "char CHAR", "The character/sign desk card: Han, Cuneiform, or Egyptian Hieroglyphs"
    long_desc <<~HELP, wrap: false
      The character card (P37-4; sign legs P65): one glyph in, the full held
      identity out — dispatched by script. A Han character gets the P37-4
      dictionary-shelf card below; a CUNEIFORM glyph (𒊬, compounds like
      𒋀𒀊 included) gets the OSL sign card (name · @aka · MZL/LAK/ABZL/
      HZL/ŠL list concordances · values by language · CDLI meaning glosses ·
      variant forms · fulltext attestation); an EGYPTIAN HIEROGLYPH (𓅃)
      gets the Unikemet card (Gardiner-plus catalog code · description ·
      function · phonetic value · JSesh/Hieroglyphica/IFAO concordances ·
      aes corpus attestation). Multi-character input is the sign-NAME lane,
      never a text lane: an OSL sign name or value spelling (SAR, szesz,
      |ŠEŠ.AB| — C-ATF ASCII folds apply, and a trailing x reads as the ₓ
      subscript: idx → idₓ), then a sign-list concordance number — MZL535
      qualified, or bare 535/852 matched across every held list (MZL, LAK,
      ABZL, HZL, ŠL, …), each hit naming the token that matched — then a
      Gardiner-style code (G5, N35). The sign cards need their modules
      synced: nabu sync osl / nabu sync unikemet. A Han READING also
      resolves: pinyin (wen · wén — toneless input folds tones) via Unihan
      kMandarin, and Japanese via KANJIDIC2 on/kun — as kana (ひと · タイ,
      hiragana/katakana fold together, okurigana dots are notation) or as
      ROMAJI on the dictionary-caps convention, no kana keyboard needed:
      ALL-CAPS is an on'yomi (TAI · KOKU), lowercase a kun'yomi (hito ·
      kuni; lowercase also answers as pinyin, each hit labeled). Every
      lane lists every character that carries the reading.

      --json emits the frozen machine contract the Edubba downstream
      consumes — the cuneiform/hieroglyph sign cards (P65) and the Han
      card (P72-2) alike; an ambiguous value input lists ALL candidate
      signs, never one silently.

      The Han card composes every shelf the library holds — the join no
      single dictionary site offers. It matches Jisho's synchronic
      completeness field-for-field where a shelf backs it, and exceeds it
      diachronically with a column no online dictionary carries. The binding
      rule everywhere: a field whose shelf can't back THIS character is
      ABSENT, never rendered "—".

      Sections, in render order (each names its backing shelf; absent
      sections are silently omitted):

        header        glyph · total strokes · KangXi radical number+name
                      (Unihan kRSUnicode/kTotalStrokes)
        decomposition the IDS structure + its components, each with the
                      follow-up commands to walk into it (BabelStone IDS)
        components    the flat component index Jisho searches (KRADFILE)
        variants      trad/simp/semantic/z-variant forms (Unihan)
        readings ja   on/kun/nanori + meanings (KANJIDIC2)
        readings      Mandarin/Korean/Vietnamese + the Unihan kJapanese layer
        pedagogy      Jōyō grade · JLPT · newspaper frequency (KANJIDIC2)
        desk-ref      the reference codes, zero suppressed — Unicode always,
                      four-corner/SKIP/JIS/dic numbers where KANJIDIC2 holds
                      them
        — the diachronic column (where nabu exceeds Jisho) —
        Old Chinese   Baxter-Sagart reconstruction + gloss
        Middle Chinese Qieyun reading, 反切, 音韻地位 (tshet-uinh)
        early Japan   positions in the Heian hanzi dictionaries (HDIC)
        TLS           sense-level concepts + classical attestation counts
        corpus        attestation frequency across the held corpora
        search        the printed `search CHAR*`-family follow-ups

      The card's grain is ONE glyph (or one sign name/code). The
      component-search siblings are `nabu search --radical N`,
      `--strokes A-B` and `--char-component C`.

      Examples:
        nabu char 棄       # reject/abandon — radical 75 木, the whole card
        nabu char 木       # the component itself; its containment neighbours
        nabu char 𒊬       # the cuneiform sign card (SAR)
        nabu char idₓ      # an ambiguous value — every candidate listed
        nabu char 𓅃       # the falcon — Unikemet card
        nabu char G5       # the same sign by Gardiner-style code
        nabu char wen      # every Han character read wén/wěn/wèn…
        nabu char ひと     # every kanji with the kun reading ひと
        nabu char TAI      # CAPS romaji = on'yomi タイ
        nabu char kuni     # lowercase romaji = kun'yomi くに
    HELP
    option :json, type: :boolean, default: false,
                  desc: "Sign cards only: emit the frozen machine-readable contract"
    option :as, type: :string,
                desc: "Narrow an ambiguous input to ONE lens: identity · reading · sign · han " \
                      "(P86-5 — `char a` is a Latin letter AND a reading AND a sign value)"
    def char(glyph = nil)
      input = Nabu::Normalize.nfc(glyph.to_s.strip)
      if input.empty?
        raise Thor::Error, "char: give a character (e.g. nabu char 棄) or a sign name/code " \
                           "(nabu char SAR · nabu char G5)"
      end

      config = Nabu::Config.load
      return char_as_lens(config, input) if options[:as]

      case Nabu::CharDispatch.lane(input)
      when :cuneiform then cuneiform_char_card(config, input)
      when :hieroglyphic then hieroglyphic_char_card(config, input)
      when :marks then editorial_marks_char_card(config, input)
      when :name then name_char_card(config, input)
      else han_char_card(config, input)
      end
    end

    desc "signs URN|TEXT", "Sign-by-sign reading of ATF transliteration through the Oracc Sign List"
    long_desc <<~HELP, wrap: false
      The cuneiform sign desk (P53-2): ATF transliteration resolved token by
      token through the Oracc Sign List (the osl module, `nabu sync osl`)
      into sign identities — value → sign name → Unicode codepoint(s)/glyph.
      The sign list adds IDENTITY, not curriculum: what each spelled value
      is, never what to make of it.

      Input is EITHER a passage/document urn out of the ATF corpora
      (cdli/oracc/ebl/etcsl shelves — the catalog is opened read-only,
      language taken from the row) OR raw ATF transliteration text
      (language via --lang; no catalog needed). C-ATF ASCII folds apply
      (sz→š, s,→ṣ, t,→ṭ, '→ʾ, u2→u₂); the ETCSL romanization (c→š, j→ŋ)
      folds automatically for etcsl urns and under --dialect etcsl for raw
      text.

      Every token carries one honest status: deterministic · qualified
      (valueₓ(SIGN) — the explicit sign resolved) · ambiguous (ALL candidate
      signs listed, never one silently) · no-codepoint (sign resolved,
      honestly unencoded upstream) · broken (x, [...]) · unknown (not in the
      OSL — said plainly). Determinatives ({d}, {gesz}) are unbraced and
      marked det. Absent data is ABSENT, never "—".

      --json emits the frozen machine contract (one object: mode/urn/
      language/dialect/source envelope, per-line token records with
      input_value · status · sign_name · codepoints[] · candidates[] ·
      language_qualifier) — the same shape the MCP nabu_signs tool serves;
      downstream consumers (Edubba reading panels) script against it.

      Examples:
        nabu signs 'lugal-e {d}en-lil2-ra'      # raw C-ATF, folded and resolved
        nabu signs --dialect etcsl 'cag4-ta'    # ETCSL romanization
        nabu signs urn:nabu:cdli:p469841        # every line of the tablet
        nabu signs --json 'szesz' | jq .        # the frozen contract
    HELP
    option :lang, type: :string, banner: "CODE",
                  desc: "Language filter for %lang-qualified sign readings (urn mode " \
                        "defaults to the passage's language)"
    option :dialect, type: :string, banner: "NAME",
                     desc: "Transliteration dialect: etcsl (c→š, j→ŋ; auto for etcsl urns)"
    option :json, type: :boolean, default: false,
                  desc: "Emit the frozen machine-readable contract instead of columns"
    def signs(*input)
      raw = input.join(" ").strip
      if raw.empty?
        raise Thor::Error, "signs: give a passage urn or raw ATF transliteration " \
                           "(e.g. nabu signs 'lugal-e {d}en-lil2-ra')"
      end

      config = Nabu::Config.load
      list = Nabu::SignList.load_default(config: config)
      if list.nil?
        raise Thor::Error, "signs: no sign list on this box yet — run `nabu sync osl` " \
                           "(the Oracc Sign List module), then retry"
      end

      dialect = signs_dialect(options[:dialect])
      catalog = nil
      if raw.start_with?("urn:")
        catalog = open_catalog(config)
        raise Thor::Error, "signs: no corpus — run nabu sync or nabu rebuild" unless catalog

        result = signs_urn_result(raw, list: list, catalog: catalog, dialect: dialect)
      else
        result = Nabu::Query::Signs.new(sign_list: list)
                                   .run_text(raw, language: options[:lang], dialect: dialect || :catf)
      end

      if options[:json]
        say JSON.generate(Nabu::Query::Signs.json_payload(result))
      else
        print_signs(result)
      end
    ensure
      catalog&.disconnect
    end

    desc "info QUERY", "One front door: the character, language/lect, or script dossier card for QUERY"
    long_desc <<~HELP, wrap: false
      The dossier front door (P90-5): one command that answers "what is
      this?" across the three desk namespaces, dispatching to the existing
      cards byte-identically — an alias, never a reimplementation:

        1. a single character (any non-ASCII grapheme) or a Gardiner-style
           sign code (G5, Aa27)                → the `nabu char` card
        2. a known language code or lect id (chu, grc:koi, sla-pro)
                                               → the `nabu language` card
        3. a script tag or script name (glag / Glagolitic — the curated
           dossiers of config/script_dossiers.yml) → the script card

      Earlier rungs win; when a language code shadows a script tag the
      language card renders and a footer names the shadowed reading.
      Anything else misses honestly, naming all three namespaces.
    HELP
    def info(query = nil)
      term = Nabu::Normalize.nfc(query.to_s.strip)
      raise Thor::Error, "info: give a character, a language/lect code, or a script tag/name" if term.empty?
      return char(term) if term.grapheme_clusters.size == 1 && !term.match?(/\A[[:ascii:]]\z/)
      return char(term) if term.match?(/\A[A-Z][a-z]?\d+[a-z]?\z/) # Gardiner-style sign codes

      config = Nabu::Config.load
      lects = Nabu::Lects.load_default(config: config, overlay: {})
      if info_language?(config, term, lects)
        language(term)
        if (tag = info_script_tag(term))
          say "(#{term.inspect} is also script tag #{tag.inspect} — languages resolve first; " \
              "`nabu info #{Nabu::ScriptDossiers.lookup(tag).name}` shows the script card)"
        end
        return
      end
      return print_script_card(tag, lects) if (tag = info_script_tag(term))

      raise Thor::Error,
            "info: #{term.inspect} is not a known character, language/lect code, or script — " \
            "try nabu char CHAR, nabu language --list, or a script tag from config/script_dossiers.yml"
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
    CURVE_BAR_WIDTH = 30

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
    end

    desc "language [CODE]", "The language-code desk reference: name, family, context, holdings"
    long_desc <<~HELP, wrap: false
      Explains any language code the library surfaces — the corpus tags
      (chu, orv, san-Latn) and the Wiktionary etymology codes the etym
      cognate lists are full of (gkm, zle-ort, zlw-opl…). The card merges
      three layers:

      - NAME, derived from the held kaikki extracts: every descendants node
        carries the human name next to its code, censused into the catalog
        with the dictionary shelves (a catalog predating that census shows
        names only for curated codes until the next rebuild or parse-only
        shelf resync).
      - CONTEXT, curated in the canonical/local-language dossier shelf
        (P19-1: one Markdown file per code — edit it in any editor, then
        `nabu sync local-language` re-derives): period, family, what the
        library holds — every held language, plus family-level entries for
        the etymology tail (zle-* East Slavic stages, gkm Medieval Greek…).
        A code without its own dossier falls back to its family; without
        either it says so honestly. (Libraries that predate the dossier
        migration keep reading the ledger's language notes unchanged.)
      - RELEVANCE, live from the db: documents/passages, gold-lemma rows,
        dictionary shelves, reconstruction-crosswalk edges, and the related
        research axes (the desks whose member sources hold the code, in
        ratified order — nabu axis NAME for any desk card). Zero fields
        are suppressed.

      --long adds where-it-appears detail: per-source document counts and
      the upstream-code split of the etymology edges (chu's edges arrive
      as Wiktionary's "cu"). --list shows the held languages only — the
      ~800-code etymology tail is what `language CODE` is for.
      --curve draws the code's documents + passages per century (each
      document at its date-envelope midpoint; undated last). --mixing (no
      CODE) is the multilingualism census: documents by how many passage
      languages they hold, the commonest mixed inventories, and per source
      how the mixing runs — "block" (each language one contiguous run) or
      "interleaved" (switching back and forth). Both read the precompiled
      rollups only.
      --export-dossiers is THE one-shot canonical-memory migration
      (owner-fired): it writes the ledger's language notes out as dossier
      files, absence-filling only, idempotent; --dry-run previews it.

      Examples:
        nabu language zle-ort      # the code from an etym cognate list
        nabu language chu --long   # a held language, full holdings
        nabu language --list       # every held language
        nabu lang lat --curve      # Latin documents/passages by century
        nabu lang --mixing         # the multilingualism census
        nabu language --export-dossiers --dry-run   # preview the migration
    HELP
    option :list, type: :boolean, default: false,
                  desc: "List the held languages (corpus documents, gold lemmas, or a shelf)"
    option :"export-dossiers", type: :boolean, default: false,
                               desc: "One-shot migration: write ledger language notes out as " \
                                     "canonical/local-language dossiers (idempotent, absence-filling)"
    option :"dry-run", type: :boolean, default: false,
                       desc: "With --export-dossiers: report what would be written, touch nothing"
    option :long, type: :boolean, default: false,
                  desc: "Add per-source document counts and the upstream-code edge split"
    option :curve, type: :boolean, default: false,
                   desc: "Documents + passages per century for CODE (precompiled curve)"
    option :mixing, type: :boolean, default: false,
                    desc: "The multilingualism census: inventory sizes, mixed inventories, switch grain"
    def language(code = nil)
      config = Nabu::Config.load
      return export_language_dossiers(config) if options[:"export-dossiers"]
      return language_census(config, code) if options[:curve] || options[:mixing]

      catalog = open_catalog(config)
      fulltext = open_fulltext(config)
      languages = Nabu::Languages.new(catalog: catalog)
      info = catalog && Nabu::Query::LanguageInfo.new(catalog: catalog, fulltext: fulltext)
      if options[:list]
        print_language_list(languages, info, Nabu::Lects.load_default(config: config, overlay: {}))
      else
        term = code.to_s.strip
        raise Thor::Error, "language: give a code (chu, gkm, zle-ort…) or --list" if term.empty?

        registry = Nabu::SourceRegistry.load(config.sources_path)
        lects = Nabu::Lects.load_default(config: config)
        dossiers = Nabu::LanguageDossiers.load_default(config: config)
        notes = catalog ? Nabu::Query::Notes.new(catalog: catalog).for_urn(Nabu::LanguageNote.urn(term)) : []
        print_language_card(term, languages, info, registry: registry, lects: lects,
                                                   dossiers: dossiers, notes: notes)
      end
    ensure
      catalog&.disconnect
      fulltext&.disconnect
    end

    no_commands do
      # P121-2: the two rollup-backed language desks (--curve / --mixing).
      def language_census(config, code)
        catalog = open_catalog(config)
        raise Thor::Error, "language: no catalog — run nabu sync or nabu rebuild" if catalog.nil?

        census = Nabu::Query::LanguageCensus.new(catalog: catalog)
        if options[:mixing]
          print_language_mixing(census.mixing)
        else
          term = code.to_s.strip
          raise Thor::Error, "language --curve: give a code (lat, grc…)" if term.empty?

          print_language_curve(census.curve(term))
        end
      ensure
        catalog&.disconnect
      end

      def print_language_curve(result)
        rollup_status_error("language --curve", result.status)
        if result.points.empty?
          return say("language --curve #{result.code}: no documents hold this code " \
                     "(#{format_duration(result.seconds)})")
        end

        say "#{result.code} — documents and passages per century (each document at its date-envelope midpoint)"
        width = (result.points.map { |point| point.label.length } + [7]).max
        peak = result.points.map(&:passages).max
        result.points.each do |point|
          bar = "█" * [(CURVE_BAR_WIDTH * point.passages.to_f / peak).round, 1].max
          bases = point.bases.any? ? "  (#{point.bases.join(', ')})" : ""
          say "  #{point.label.ljust(width)}  #{commafy(point.documents).rjust(9)} docs · " \
              "#{commafy(point.passages).rjust(11)} passages  #{bar}#{bases}"
        end
        say "curve: #{commafy(result.documents)} docs · #{commafy(result.passages)} passages over " \
            "#{dated_centuries(result.points.count(&:century))} " \
            "(#{format_duration(result.seconds)})"
      end

      def print_language_mixing(result)
        rollup_status_error("language --mixing", result.status)
        say "language mixing — #{commafy(result.documents)} documents by passage-language inventory size"
        result.by_size.each do |size, count|
          share = (100.0 * count / result.documents).round(1)
          say "  #{pluralize(size, 'language').ljust(12)}  #{commafy(count).rjust(11)} docs (#{share}%)"
        end
        print_mixing_inventories(result.inventories)
        print_mixing_sources(result.sources)
        mixed = result.by_size.sum { |size, count| size > 1 ? count : 0 }
        share = result.documents.zero? ? 0 : (100.0 * mixed / result.documents).round(1)
        say "mixing: #{commafy(mixed)} mixed of #{commafy(result.documents)} documents (#{share}%) " \
            "(#{format_duration(result.seconds)})"
      end

      def print_mixing_inventories(inventories)
        return if inventories.empty?

        say "top mixed inventories:"
        width = inventories.map { |languages, _| languages.length }.max
        inventories.each { |languages, count| say "  #{languages.ljust(width)}  #{commafy(count).rjust(9)} docs" }
      end

      def print_mixing_sources(sources)
        return if sources.empty?

        say "switch grain by source (mixed docs · block / interleaved · total switches):"
        width = sources.map { |grain| grain.slug.length }.max
        sources.each do |grain|
          say "  #{grain.slug.ljust(width)}  #{commafy(grain.mixed).rjust(9)} mixed · " \
              "#{commafy(grain.block)} block / #{commafy(grain.interleaved)} interleaved · " \
              "#{commafy(grain.switches)} switches"
        end
      end
    end

    desc "kind census", "The document-kind axis: cross-corpus class counts"
    option :unmapped, type: :boolean, default: false,
                      desc: "List the unmapped raw values by count per source — the curation worklist"
    option :uncovered, type: :boolean, default: false,
                       desc: "List the open-vocabulary values no rule covers (they mint nothing)"
    option :limit, type: :numeric, default: 50, desc: "Rows shown by --uncovered (the full count is announced)"
    long_desc <<~HELP, wrap: false
      The fourth document axis: what KIND of document is this? Upstream
      genre vocabularies fold onto the ruled cross-corpus classes
      (config/kind_classes.yml; the per-source folds live in
      config/kind_map.yml). `census` shows every class family with its
      document and source spread, the honesty buckets (unknown = upstream's
      own "cannot determine"; unmapped = values awaiting a fold rule), the
      open-vocabulary misses (uncovered = subject headings and the like
      that no rule covers — a source declared `vocabulary: open` folds
      them to nothing, counted here instead), and the unclassified
      remainder. Filter the corpus with `nabu search --kind CLASS[/SUB]`.

        nabu kind census              # the class board
        nabu kind census --unmapped   # raw values awaiting a rule
        nabu kind census --uncovered  # open-vocabulary values no rule covers (top 50; --limit N)
    HELP
    def kind(subcommand = "census")
      raise Thor::Error, "usage: nabu kind census [--unmapped|--uncovered]" unless subcommand == "census"

      config = Nabu::Config.load
      catalog = open_catalog(config)
      raise Thor::Error, "kind census: no catalog — run nabu sync or nabu rebuild" if catalog.nil?

      census = Nabu::Query::KindCensus.new(catalog: catalog)
      if options[:unmapped]
        print_kind_unmapped(census, Nabu::Kinds.load_default(config: config))
      elsif options[:uncovered]
        print_kind_uncovered(census, limit: options[:limit].to_i)
      else
        report = census.run
        if report.nil?
          raise Thor::Error,
                "kind census: the kind_stats table is not built yet — run nabu sync or nabu rebuild"
        end

        print_kind_census(report)
      end
    ensure
      catalog&.disconnect
    end

    desc "person NAME|REF", "The person desk card: the derived prosopography index (CBDB, EDH, …)"
    long_desc <<~HELP, wrap: false
      Look a person up in the derived person index: the CBDB thin slice
      (~658k persons of Chinese history), EDH's attested persons (~93.6k
      Latin inscription persons, one card per attestation — the ref names
      the inscription), the Elephantine ancient persons, the Aozora Bunko
      author/translator index (1,335 persons) and the kokubunken waka-poet
      personographies (266). Input is an authority ref (cbdb:1762,
      edh:HD000001/3, aozora:001257, kokubunken:紀貫之) or a name — hanzi,
      pinyin, courtesy/studio names, kana readings, romaji, a Roman name
      as inscribed or in the nominative all key through the shared fold;
      matching is exact under the fold, never fuzzy; homonyms print
      several cards (cbdb first, then edh, elephantine, aozora, kokubunken).

      `nabu person mine SOURCE` runs the CENSUS-ONLY name scan over a held
      source's passages (the PlaceMine Han-lane shape). It writes nothing —
      The apply gate stays closed until an owner ruling on the census.

      Examples:
        nabu person 王安石          # by name
        nabu person "Wang Anshi"   # pinyin, same person
        nabu person 介甫           # the courtesy name resolves too
        nabu person cbdb:1762      # by authority ref
        nabu person "Iulius Optatus"   # an EDH person, nominative form
        nabu person edh:HD000001/3     # by EDH ref (inscription HD000001, person 3)
        nabu person sillok:M_0006771   # a NIKH index-markup person, per source
        nabu person nikh:p094190       # the passage-annotation ref: every NIKH slice holding it
        nabu person mine kanripo   # census the person-name attestations
    HELP
    def person(*query_parts)
      return run_person_mine(query_parts[1..]) if query_parts.first == "mine"

      query = query_parts.join(" ").strip
      config = Nabu::Config.load
      catalog = open_catalog(config)
      raise Thor::Error, "no catalog — run nabu sync or nabu rebuild" unless catalog

      result = Nabu::Query::Person.new(catalog: catalog).run(query)
      result.cards.each { |card| print_person_card(card) }
    rescue Nabu::Query::Person::Error => e
      raise Thor::Error, e.message
    ensure
      catalog&.disconnect
    end

    desc "place NAME|ID", "The place desk card: Pleiades gazetteer facts + the library's holdings there"
    long_desc <<~HELP, wrap: false
      The third dimension of the library (after language and time): one
      ancient place, resolved through the local Pleiades gazetteer dump,
      plus every source's holdings AT that place — counted over the
      Pleiades ids the epigraphic parsers capture from their upstream
      headers (isicily, edh, iip, itant). Only upstream-asserted ids ever
      count: no fuzzy geo-matching anywhere in the pipeline.

      Input is a Pleiades NUMERIC id (or a pleiades.stoa.org/places URL),
      a NAMESPACED ref (P66-2: tm:2810 · cigs:GIR · pleiades:462281 —
      tm/cigs resolve through their own derived index slices), or an EXACT
      place title, matched case-insensitively against the dump — "Segesta"
      works, "Seges" does not (exact only, by design). Homonym titles
      print one card each.

      The card: title, Pleiades id, place types, the attested time-period
      span, and the representative point (lat, lon — display only; no maps,
      no coordinate math). Then the holdings line, per source, descending —
      and (P66-2) the AXIS holdings line: documents whose place_ref axis
      cites the place (adapter-asserted refs + the nabu-places registry's
      applied decisions, both spellings, one count per document) — labeled
      apart because the provenance differs.

      An honest labelled tail follows when id-less documents mention the
      name in their captured findspot TEXT (exact substring, case-
      insensitive): "unlinked findspot mentions" — never merged into the
      id-matched counts.

      The gazetteer dump is the pleiades module's canonical asset
      (`nabu sync pleiades`, ~42k places). Since P45-6 the sync also
      derives a place index into the catalog, so lookups here read it
      instantly; the ~3 s in-memory dump load is paid only while that
      index is not yet derived (re-sync or rebuild derives it). Without
      the dump on disk, a numeric id still counts holdings (the catalog
      side needs no dump); a name lookup is refused with the sync hint.

      Examples:
        nabu place Segesta          # exact title → card + holdings
        nabu place 462281           # Lilybaeum by Pleiades id
        nabu place https://pleiades.stoa.org/places/462281   # same
        nabu place tm:2788          # Pompeii through the TM gazetteer slice
        nabu place cigs:GIR         # Girsu through the CIGS slice
        nabu place mine kanripo --dry-run   # Q9: census Han place-name hits (writes nothing)
        nabu place mine kanripo             # mine place-candidate edges into the links journal
        nabu place mine report kanripo      # review the mined candidates, ranked by document spread
        nabu place mine report kanripo --board   # the per-NAME verdict board (discriminators + snippets)
    HELP
    option :verbose, type: :boolean, default: false,
                     desc: "place apply: #{Nabu::Ops::StageGuide::OPTION_DESC}"
    def place(*query_parts)
      return run_place_apply if query_parts == ["apply"]
      return run_place_mine(query_parts[1..]) if query_parts.first == "mine"
      return run_place_link(query_parts[1..]) if query_parts.first == "link"

      query = query_parts.join(" ").strip
      raise Thor::Error, "place: give a Pleiades numeric id or an exact place title" if query.empty?

      config = Nabu::Config.load
      catalog = open_catalog(config)
      raise Thor::Error, "no catalog — run nabu sync or nabu rebuild" unless catalog

      resolver = Nabu::Pleiades.load_default(config: config, catalog: catalog)
      result = Nabu::Query::Place.new(catalog: catalog, pleiades: resolver,
                                      place_shelf_dir: config.source_workdir(Nabu::PlaceDossiers::DIRNAME))
                                 .run(query)
      print_place(result)
    rescue Nabu::Query::Place::Error => e
      raise Thor::Error, e.message
    ensure
      catalog&.disconnect
    end

    no_commands do
      # The person card renderer (P97-2): one line of identity, one of
      # dates/dynasty — thin by design, like the slice.
      def print_person_card(card)
        years = [card.birth_year, card.death_year].compact.join("–")
        dynasty = [card.dynasty_han, card.dynasty].compact.join(" ")
        headline = [card.name_han, card.name].compact.join(" · ")
        say "#{headline}  #{card.authority}:#{card.person_id}"
        details = []
        details << years unless years.empty?
        details << dynasty unless dynasty.empty?
        details << "female" if card.female
        say "  #{details.join(' · ')}" unless details.empty?
      end

      # `nabu person mine SOURCE` (P97-2): the census-only scan; the
      # apply gate stays closed until an owner ruling, so there is no --dry-run — dry is
      # the only mode.
      def run_person_mine(args)
        source = Array(args).first
        raise Thor::Error, "usage: nabu person mine SOURCE" if source.to_s.empty?

        config = Nabu::Config.load
        catalog = Nabu::Store.connect(config.catalog_path)
        unless Nabu::Store::PersonIndex.populated?(catalog)
          raise Thor::Error, "person mine: the person index is not derived — run `nabu sync cbdb` first"
        end

        census = Nabu::PersonMine.new(catalog: catalog, progress: progress_reporter)
                                 .census(source: source)
        say "person mine: #{census.source} × #{census.authority} — #{census.passages} passages " \
            "scanned against #{census.names_loaded} Han name keys " \
            "(#{census.names_non_han} non-Han filtered, #{census.names_ambiguous} ambiguous capped; " \
            "#{format_duration(census.seconds)})"
        census.name_hits.first(15).each do |name, count|
          say format("  %<name>-12s %<count>d passages", name: name, count: count)
        end
        say "  … #{census.name_hits.size - 15} more attested names" if census.name_hits.size > 15
        census.names_stopped.each do |name, count|
          say "  STOPPED #{name} — #{count} passages (above the derived ceiling)"
        end
        say "  census only — the person apply gate stays closed until an owner ruling on these numbers"
      rescue Nabu::CatalogBusyError => e
        raise Thor::Error, e.message
      ensure
        catalog&.disconnect
      end

      # `nabu place mine SOURCE [GAZETTEER] [--dry-run]` (P96-3 — Q9 v0):
      # mine the gazetteer's Han name keys against SOURCE's passage text
      # into place-candidate edges (review fuel for the np: doctrine,
      # never place_ref). --dry-run prints the census — per-name hit
      # counts, the derived stop set, every filtered class — and writes
      # nothing. Default gazetteer: chgis.
      def run_place_mine(args)
        args = Array(args)
        return run_place_mine_report(args[1..]) if args.first == "report"

        dry = args.delete("--dry-run") ? true : false
        source, gazetteer = args
        raise Thor::Error, "usage: nabu place mine SOURCE [GAZETTEER] [--dry-run]" if source.to_s.empty?

        gazetteer ||= "chgis"
        config = Nabu::Config.load
        Nabu::Store.assert_writable!(config.catalog_path) unless dry
        catalog = Nabu::Store.connect(config.catalog_path)
        unless Nabu::Store::PlaceIndex.populated?(catalog, gazetteer: gazetteer)
          raise Thor::Error,
                "place mine: the #{gazetteer.inspect} place-index slice is not derived — " \
                "sync the gazetteer module first (nabu sync #{gazetteer})"
        end

        journal = if dry
                    nil
                  else
                    Nabu::Store::LinksJournal.migrate!(
                      Nabu::Store::LinksJournal.connect("sqlite://#{config.links_path}")
                    )
                  end
        miner = Nabu::PlaceMine.new(catalog: catalog, journal: journal, gazetteer: gazetteer,
                                    progress: progress_reporter)
        if dry
          print_mine_census(miner.census(source: source), applied: false)
        else
          result = miner.apply!(source: source)
          # Since the 2026-09-27 rebuild dropped the mine run, the scope
          # joins the P70 derivability record so the rebuild links stage
          # re-mints it — the batch-CLI contract, closed for this producer.
          Nabu::LinkScopes.record!(config.link_scopes_path, producer: "place-mine",
                                                            scope: source, params: { "gazetteer" => gazetteer })
          print_mine_census(result.census, applied: true)
          say "place mine: #{result.edges_written} candidate edges written " \
              "(#{result.superseded_edges} superseded) in #{format_duration(result.seconds)} " \
              "— review fuel for np: decisions; read back with `nabu links <passage urn>`"
        end
      rescue Nabu::CatalogBusyError => e
        raise Thor::Error, e.message
      ensure
        journal&.disconnect
        catalog&.disconnect
      end

      # `nabu place mine report [SOURCE] [GAZETTEER] [--limit N]` (P97-1):
      # the aggregate review surface — mined candidates grouped by
      # place, ranked by document spread, each row carrying its evidence
      # and the two exits (stop-list line, place card).
      def run_place_mine_report(args)
        args = Array(args)
        board = args.delete("--board") ? true : false
        limit = Nabu::PlaceMineReport::DEFAULT_LIMIT
        if (i = args.index("--limit"))
          limit = begin
            Integer(args[i + 1])
          rescue TypeError, ArgumentError
            raise Thor::Error, "place mine report: --limit needs a number"
          end
          args.slice!(i, 2)
        end
        source, gazetteer = args
        raise Thor::Error, "place mine report --board needs a SOURCE (verdicts are per source)" if board && source.nil?

        config = Nabu::Config.load
        journal = Nabu::Store::LinksJournal.open_readonly(config.links_path)
        if journal.nil?
          raise Thor::Error, "place mine report: no links journal yet — run `nabu place mine SOURCE` first"
        end

        catalog = Nabu::Store.connect(config.catalog_path)
        reporter = Nabu::PlaceMineReport.new(catalog: catalog, journal: journal)
        if board
          result = reporter.board(source: source, gazetteer: gazetteer || "chgis", limit: limit,
                                  registry: Nabu::Places.load_default(canonical_dir: config.canonical_dir),
                                  stop_names: Nabu::PlaceMine.hand_stop_names)
          print_mine_board(result)
        else
          print_mine_report(reporter.run(source: source, gazetteer: gazetteer, limit: limit))
        end
      rescue Nabu::CatalogBusyError => e
        raise Thor::Error, e.message
      ensure
        journal&.disconnect
        catalog&.disconnect
      end

      # The P105-1 verdict surface: one block per NAME — candidates with
      # their discriminators, attestations in context, both exits.
      def print_mine_board(result)
        say "place-mine board: #{result.source} × #{result.gazetteer} — #{result.edges} candidate " \
            "edges · #{result.total_names} undecided names (#{format_duration(result.seconds)})"
        unless result.decided.empty?
          say "  decided already in nabu-places (off the board): " \
              "#{result.decided.map { |name, status| "#{name}=#{status}" }.join(' · ')}"
        end
        say "  stopped since mined (place_stop_names.yml): #{result.stopped.join(' · ')}" unless result.stopped.empty?
        if result.rows.empty?
          say "  nothing undecided in this scope — the board is clean"
          return
        end

        say "  ranked by document spread; exact spread computed over the top #{result.prerank_window} by passages"
        result.rows.each_with_index do |row, i|
          say format("  %<rank>2d. %<name>s — %<docs>d docs · %<passages>d passages · %<n>d candidate%<s>s",
                     rank: i + 1, name: row.name, docs: row.documents, passages: row.passages,
                     n: row.candidates.size, s: row.candidates.size == 1 ? "" : "s")
          row.candidates.each do |c|
            bits = [c.title, c.place_types.first, c.time_periods.join(" "),
                    c.parent && "parent #{c.parent}",
                    c.lat && format("%<lat>.2f,%<lon>.2f", lat: c.lat, lon: c.lon)].compact.reject(&:empty?)
            say "      · #{c.ref}  #{bits.join(' · ')}"
          end
          row.snippets.each { |urn, text| say "      ▸ #{urn}  #{text}" }
          say "      exits: link → names.yml (#{result.source}) · stop → place_stop_names.yml: - \"#{row.name}\""
        end
      end

      def print_mine_report(report)
        scope = [report.source || "all sources", report.gazetteer || "all gazetteers"].join(" × ")
        say "place-mine report: #{scope} — #{report.edges} candidate edges over " \
            "#{report.total_places} places (#{format_duration(report.seconds)})"
        if report.rows.empty?
          say "  nothing mined in this scope — `nabu place mine SOURCE [GAZETTEER]` writes candidates"
          return
        end

        say "  ranked by document spread; exact spread computed over the top #{report.prerank_window} by passages"
        report.rows.each_with_index do |row, i|
          names = row.names.map { |n, c| "「#{n}」×#{c}" }.join(" ")
          say format("  %<rank>2d. %<title>s  %<ref>s — %<docs>d docs · %<passages>d passages · %<names>s",
                     rank: i + 1, title: row.title || "(no title in slice)", ref: row.ref,
                     docs: row.documents, passages: row.passages, names: names)
          say "      sample: #{row.samples.join(' · ')}"
          say "      exits: card `nabu place #{row.ref}` · stop-list (config/place_stop_names.yml): " \
              "#{row.stop_lines.join(' ')}"
        end
        clipped = report.total_places - report.rows.size
        say "  … #{clipped} more places below the cut (--limit raises the cap)" if clipped.positive?
      end

      def print_mine_census(census, applied:)
        say "place mine: #{census.source} × #{census.gazetteer} — #{census.passages} passages " \
            "scanned against #{census.names_loaded} Han name keys " \
            "(#{census.names_non_han} non-Han filtered, #{census.names_ambiguous} ambiguous capped)"
        census.name_hits.first(15).each do |name, count|
          say format("  %<name>-12s %<count>d passages", name: name, count: count)
        end
        say "  … #{census.name_hits.size - 15} more attested names" if census.name_hits.size > 15
        census.names_stopped.each do |name, count|
          say "  STOPPED #{name} — #{count} passages (above the derived ceiling; " \
              "a genuinely geographic name lost here is an allow_names: ruling " \
              "in config/place_stop_names.yml)"
        end
        census.names_allowed.each do |name, count|
          say "  ALLOWED #{name} — #{count} passages (over the ceiling, mined anyway " \
              "by allow_names: ruling)"
        end
        say "  candidate edges#{' (dry run — nothing written)' unless applied}: " \
            "#{census.candidate_edges} across #{census.name_hits.size} attested names " \
            "(census pass: #{format_duration(census.seconds)})"
      end

      # `nabu place link SOURCE [GAZETTEER]` (P105-4 — the place-mine apply lane):
      # promote the registry's MATCHED mined names to ruled attestation
      # edges (kind "place") in the links journal. Passage-grain by
      # design — never document_axes.place_ref.
      def run_place_link(args)
        source, gazetteer = Array(args)
        raise Thor::Error, "usage: nabu place link SOURCE [GAZETTEER]" if source.to_s.empty?

        gazetteer ||= "chgis"
        config = Nabu::Config.load
        registry = Nabu::Places.load_default(canonical_dir: config.canonical_dir)
        if registry.nil?
          raise Thor::Error, "place link: no nabu-places registry under canonical/ — " \
                             "run `nabu sync nabu-places` first"
        end

        catalog = Nabu::Store.connect(config.catalog_path)
        journal = Nabu::Store::LinksJournal.migrate!(
          Nabu::Store::LinksJournal.connect("sqlite://#{config.links_path}")
        )
        result = Nabu::PlaceLink.new(catalog: catalog, journal: journal, registry: registry,
                                     gazetteer: gazetteer, progress: progress_reporter)
                                .apply!(source: source)
        # Recorded like every batch scope — the replay runs it AFTER
        # place-mine (LinkScopeReplay.order), promotion needs candidates.
        Nabu::LinkScopes.record!(config.link_scopes_path, producer: "place-link",
                                                          scope: source, params: { "gazetteer" => gazetteer })
        say "place link: #{result.source} × #{result.gazetteer} — #{result.names} ruled " \
            "names → #{result.edges_written} attestation edges written " \
            "(#{result.edges_refreshed} refreshed; superseded #{result.superseded_runs} " \
            "prior runs / #{result.superseded_edges} edges; #{format_duration(result.seconds)}) " \
            "— read back with `nabu links <passage urn>`"
      rescue Nabu::CatalogBusyError => e
        raise Thor::Error, e.message
      ensure
        journal&.disconnect
        catalog&.disconnect
      end

      # `nabu place apply` (P63-7): project the nabu-places registry into
      # document_axes.place_ref — NULL rows only (adapter-asserted refs
      # always win), idempotent, censused per source. Write-guarded by the
      # P62 probe; a missing registry is a polite posture, not a stack.
      def run_place_apply
        config = Nabu::Config.load
        Nabu::Store.assert_writable!(config.catalog_path)
        catalog = Nabu::Store.connect(config.catalog_path)
        Nabu::Store.migrate!(catalog)
        explain_command(:place_apply)
        apply_started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        census = Nabu::PlaceApply.run(catalog: catalog, canonical_dir: config.canonical_dir)
        if census.nil?
          say "place apply: no nabu-places registry under canonical/ — " \
              "run `nabu sync nabu-places` first (owner queue, P63)"
          return
        end
        census.except(:total).each do |slug, c|
          say "  #{slug}: #{c[:rows_updated]} rows gained refs across #{c[:names_applied]} names"
          # P81 U-3: a below-certain registry decision no longer dies at
          # apply — each applied low-certainty name reports its rows with
          # the Certainty gloss, upstream word verbatim.
          (c[:uncertain] || {}).each do |name, info|
            say "    #{name} — #{info[:rows]} #{info[:rows] == 1 ? 'row' : 'rows'} " \
                "(#{Nabu::Certainty.gloss(:places_certainty, info[:certainty])})"
          end
        end
        say "place apply: #{census[:total]} axis rows updated " \
            "(#{format_duration(Process.clock_gettime(Process::CLOCK_MONOTONIC) - apply_started)})"
      rescue Nabu::CatalogBusyError => e
        raise Thor::Error, e.message
      ensure
        catalog&.disconnect
      end
    end

    desc "axis [NAME]", "The research-axis desk card: persona, members, holdings, gold coverage (config/axes.yml)"
    long_desc <<~HELP, wrap: false
      The research axes are the owner's desks — TAGS over the source list
      (config/axes.yml), a source appearing under every desk it serves
      (dual-tagging is the point, D35). This is their reference card, the
      `nabu language` mold pointed at a whole desk instead of a code.

      Bare `nabu axis` lists every desk in ratified (file) order — name and
      persona, one line each. `nabu axis NAME` prints the full card:

      - PERSONA, the hat's one-liner, verbatim from config/axes.yml, and the
        membership rationale (desc) beneath it.
      - MEMBERS, every source the desk tags, each with its enablement (on/off,
        from the registry — the authoritative flip) and its live holdings
        (documents/passages, dictionary entries, dossiers, languages, license
        mix — the same census fragments `nabu list` prints). Zero fields are
        suppressed; a member holding nothing yet says so.
      - LANGUAGES, the codes the member sources hold, one merged doc-or-entry
        count each, holdings descending — the counts keep a multilingual
        pack's spillover honest (kat 3 beside hbo 40,000 explains itself).
        Compact shows ten codes with an honest "… and N more"; --long lifts.
      - GOLD COVERAGE, the aggregate gold-lemma rows across the desk's held
        languages (nabu search --lemma) — honest zero when none are gold.
      - the shipped affordances: `nabu list --axis NAME`, `nabu sync NAME`.

      An unknown axis is refused naming the known set (the slug/axis collision
      guarantee makes a bare name unambiguous). No corpus yet is not an error:
      the persona and membership still print, holdings say "no database".

      Examples:
        nabu axis                  # every desk, one persona line each
        nabu axis celtic           # the Celticist's desk, full card
        nabu axis biblical --long  # the scripture hat, every language code
    HELP
    option :long, type: :boolean, default: false,
                  desc: "Lift the languages-line cap (compact shows ten codes)"
    def axis(name = nil)
      config = Nabu::Config.load
      registry = Nabu::SourceRegistry.load(config.sources_path)
      axes = registry.axes
      raise Thor::Error, "axis: no research axes are defined (config/axes.yml)" if axes.empty?

      catalog = open_catalog(config)
      fulltext = catalog ? open_fulltext(config) : nil
      name = name.to_s.strip
      if name.empty?
        print_axis_list(axes)
      else
        definition = axes[name] ||
                     raise(Thor::Error, "axis: unknown axis #{name.inspect} — known axes: #{axes.names.join(', ')}")
        census = catalog ? Nabu::Query::List.new(catalog: catalog).census : nil
        info = catalog ? Nabu::Query::LanguageInfo.new(catalog: catalog, fulltext: fulltext) : nil
        print_axis_card(definition, registry: registry, census: census, info: info)
      end
    ensure
      catalog&.disconnect
      fulltext&.disconnect
    end

    # P121-1: `nabu export` is a command family — the research tables
    # (documents, links: a file + license manifest under exports/) and the
    # passage stream, which stays the DEFAULT command so `nabu export
    # --format jsonl ...` is byte-unchanged (ExportCLI).
    desc "export SUBCOMMAND ...ARGS",
         "Research exports — documents/links tables with a license manifest — and the passage stream"
    subcommand "export", ExportCLI

    # Language codes shown by the `nabu axis` desk card's languages line
    # before the "… and N more" tail (P48-r3; --long lists all — the same
    # house render-cap rule).
    AXIS_LANGUAGES_ITEMS = 10
    # Crosswalk equivalences shown on the place card's "=" line before the
    # "… and N more" tail (P75 C-3, the same house render-cap rule).
    # const: a render cap, not a corpus census
    PLACE_EQUIVALENCES_SHOWN = 8

    no_commands do
      # -- display policy (P27-0) ------------------------------------------
      # Passage text reaches the terminal ONLY through display_text, which
      # applies the per-language display.yml policy under the --display mode
      # and records what changed; print_display_footer then hints ONCE per
      # invocation — never silent alteration, never a hint when nothing
      # happened. MCP and export never touch this path: pristine text.

      # Resolve --display MODE against the registry; validate before any
      # output so an unknown mode is a clean named error.
      def display_mode
        @display_mode ||= Nabu::Display.mode(options[:display] || Nabu::Display::DEFAULT_MODE)
      rescue Nabu::Display::UnknownModeError => e
        raise Thor::Error, e.message
      end

      def display_policies
        @display_policies ||= Nabu::Display.load_policies(Nabu::Config.load.display_path)
      rescue Nabu::Display::ConfigError => e
        raise Thor::Error, e.message
      end

      def display_source_policies
        @display_source_policies ||= Nabu::Display.load_source_policies(Nabu::Config.load.display_path)
      rescue Nabu::Display::ConfigError => e
        raise Thor::Error, e.message
      end

      # Render one run of text for the terminal and remember which transforms
      # actually applied (for the footer hint). +source+/+annotations+
      # (P27-1) are the optional edition context — call sites that know the
      # passage's source (the show family) pass them so `--display reading`
      # can apply the per-source convention rules and the ketiv/qere choice;
      # everywhere else the language-level policies alone apply.
      def display_text(text, language, source: nil, annotations: nil)
        @display_gaiji_ladder = true if source && display_source_policies[source]&.gaiji == "ladder"
        rendered = Nabu::Display.render(text.to_s, language: language,
                                                   mode: display_mode, policies: display_policies,
                                                   source: source, annotations: annotations,
                                                   source_policies: display_source_policies,
                                                   gaiji_map: gaiji_map_for(source),
                                                   gaiji_ids: gaiji_ids_for(source),
                                                   gaiji_substitutes: gaiji_substitutes_for(source))
        display_applied.merge(rendered.applied)
        record_gaiji(rendered.gaiji)
        rendered.text
      end

      def display_applied
        @display_applied ||= Set.new
      end

      # The source's three gaiji ladder lanes (P37-3/P38-2), each memoized per
      # source: config/gaiji/<source>.tsv (faithful), <source>-ids.tsv (IDS)
      # and <source>-substitutes.tsv (substitutes) — only kanripo ships them
      # today. A missing file is an empty map (that rung degrades to the next),
      # and the non-show call sites (no source) never load a map at all.
      def gaiji_map_for(source) = gaiji_lane(source, "")

      def gaiji_ids_for(source) = gaiji_lane(source, "-ids")

      def gaiji_substitutes_for(source) = gaiji_lane(source, "-substitutes")

      def gaiji_lane(source, suffix)
        return {} unless source

        (@gaiji_lanes ||= {})[[source, suffix]] ||=
          Nabu::Display.load_gaiji_map(File.join(Nabu::Config.load.gaiji_dir, "#{source}#{suffix}.tsv"))
      end

      # Running per-rung gaiji tallies for the once-per-invocation footer
      # ([faithful, ids, substitute, placeholder], summed across every passage a
      # show-family command renders).
      def display_gaiji
        @display_gaiji ||= [0, 0, 0, 0]
      end

      def record_gaiji(tally)
        return unless tally

        display_gaiji[0] += tally.faithful
        display_gaiji[1] += tally.ids
        display_gaiji[2] += tally.substitute
        display_gaiji[3] += tally.placeholder
      end

      # The once-per-invocation honesty footer: named only when a transform
      # actually changed something (compact rule — zero-signal silence).
      #   display: cantillation stripped (--display full shows all marks)
      #   display: cantillation stripped · rtl isolates (--display full shows all marks)
      # One footer per invocation, composing every applied transform's
      # vocabulary (P27-0 strips · P27-1 edition · P27-2 translit/colors/
      # spacing); the escape hatch names diplomatic when edition transforms
      # applied, else full.
      def print_display_footer
        gaiji_text = gaiji_clause(*display_gaiji)
        return if display_applied.empty? && gaiji_text.nil?

        labels = display_applied.to_a
        edition = Nabu::Display::EDITION_LABELS & labels
        parts = []
        parts << "transliterated" if labels.delete("translit")
        colors = labels.select { |label| label.start_with?("token colors") }
        strips = labels - colors - edition - ["spacing", Nabu::Display::ISOLATES]
        parts << "#{strips.join(', ')} stripped" unless strips.empty?
        parts << "apparatus simplified: #{edition.join(', ')}" unless edition.empty?
        parts << gaiji_text if gaiji_text
        parts << "spacing" if labels.include?("spacing")
        parts.concat(colors)
        parts << Nabu::Display::ISOLATES if labels.include?(Nabu::Display::ISOLATES)
        say "display: #{parts.join(' · ')} (#{display_footer_hint(edition, !gaiji_text.nil?)})"
      end

      # The escape-hatch hint: diplomatic when any edition-level transform ran
      # (apparatus OR gaiji — both are "shown as stored" under diplomatic),
      # naming "refs" when gaiji is the only edition transform; else full.
      def display_footer_hint(edition, gaiji)
        return "--display diplomatic shows the edition marks" unless edition.empty?
        return "--display diplomatic shows the gaiji refs" if gaiji

        "--display full shows all marks"
      end

      # The gaiji footer clause, per rung. Returns nil when there is nothing to
      # announce. Two shapes, honest to the policy:
      #   ladder (P38-2)     — FAITHFUL is silent (it IS the character); the
      #                        lossy rungs (substitutes, IDS compositions) and
      #                        the ⬚ placeholders DO get announced ("never
      #                        silent"). An all-faithful render says nothing.
      #   placeholder (P37-3) — the preserved rungs-1+4 vocabulary: unresolved
      #                        (⬚) refs and how many resolved to a real glyph.
      def gaiji_clause(faithful, ids, substitute, placeholder)
        return ladder_gaiji_clause(ids, substitute, placeholder) if @display_gaiji_ladder

        placeholder_gaiji_clause(faithful, placeholder)
      end

      def ladder_gaiji_clause(ids, substitute, placeholder)
        bits = []
        bits << "#{substitute} substituted" if substitute.positive?
        bits << "#{ids} composed" if ids.positive?
        bits << "#{placeholder} unresolved gaiji" if placeholder.positive?
        bits.empty? ? nil : bits.join(", ")
      end

      def placeholder_gaiji_clause(resolved, unresolved)
        if unresolved.positive? && resolved.positive?
          "#{unresolved} unresolved gaiji (#{resolved} resolved)"
        elsif unresolved.positive?
          "#{unresolved} unresolved gaiji"
        elsif resolved.positive?
          "#{resolved} gaiji resolved"
        end
      end

      # Bare `nabu axis` (P37-8): one line per desk — name and persona — in
      # ratified (file) order, the `nabu language --list` mold. The full card
      # is one `nabu axis NAME` away.
      def print_axis_list(axes)
        say "research axes — the library's desks (#{axes.size}):"
        width = axes.names.map(&:length).max || 0
        axes.each_axis { |axis| say "  #{axis.name.ljust(width)}  #{axis.persona}" }
        say "nabu axis NAME for the full desk card (members, holdings, gold coverage)"
      end

      # `nabu axis NAME` (P37-8): the research-axis desk card, the `nabu
      # language` mold pointed at a whole desk. The persona rides verbatim
      # (first-class render data), then the membership rationale (desc); then
      # every member the desk tags with its enablement (on/off, from the
      # authoritative registry) and its live holdings (the same census
      # fragments `nabu list` prints); then the aggregate gold-lemma coverage
      # across the desk's held languages; then the shipped affordances. Zero
      # fields suppressed — a member holding nothing says so, a desk with no
      # gold says so, no corpus at all still prints persona + membership.
      def print_axis_card(axis, registry:, census:, info:)
        say "#{axis.name} — #{axis.persona}"
        say_wrapped(axis.desc, indent: 2)
        members = registry.axis_members(axis.name)
        by_slug = (census || []).to_h { |row| [row.slug, row] }
        say "  members (#{members.size}):"
        width = members.map(&:length).max || 0
        members.each do |slug|
          entry = registry[slug]
          # P46-r1: a kind: module row is PERMANENTLY wired: false (nothing
          # mints, nothing to flip) — its cell names the nature; "unwired"
          # is reserved for adapters genuinely awaiting first-sync proof.
          state = if entry&.feature_module?
                    "module "
                  else
                    entry&.wired ? "wired  " : "unwired"
                  end
          say "    #{slug.ljust(width)}  #{state}  #{axis_member_holdings(by_slug[slug], census: census)}"
        end
        print_axis_languages(members, info)
        print_axis_gold(members, by_slug, info, registry: registry)
        say "  commands: nabu list --axis #{axis.name} · nabu sync #{axis.name}"
      end

      # The desk's held language codes (P48-r3): one merged doc-or-entry
      # count per code over the member sources, holdings descending. The
      # counts ARE the honesty mechanism — a multilingual pack's 3-doc
      # spillover reads as 3 beside a 40K holding, never hidden. No catalog,
      # no line (the member cells already say "no database"); a desk holding
      # nothing says so.
      # P49-r4, the deliberate asymmetry: this line KEEPS multilingual pack
      # members (the counts self-explain), while the count-less attribution
      # surfaces (print_language_axes, print_axis_gold) exclude them.
      def print_axis_languages(members, info)
        return unless info

        holdings = info.language_holdings_for(members)
        return say("  languages: none held yet") if holdings.empty?

        shown = options[:long] ? holdings : holdings.first(AXIS_LANGUAGES_ITEMS)
        line = shown.map { |code, count| "#{code} #{commas(count)}" }.join(" · ")
        hidden = holdings.size - shown.size
        line += " … and #{hidden} more (--long lists all)" if hidden.positive?
        say "  languages: #{line}"
      end

      # One member's holdings cell: the census fragments when the source holds
      # something, an honest "nothing held yet" when it is in the registry but
      # empty, and "no database" when the corpus was never built.
      def axis_member_holdings(row, census:)
        return "no database (run nabu sync)" if census.nil?
        return "nothing held yet" if row.nil?

        census_fragments(row).join("  ")
      end

      # The desk's aggregate gold-lemma coverage: gold lemma rows summed over
      # the languages its members actually hold (nabu search --lemma). Honest
      # zero when the held languages carry no gold, honest "no held languages"
      # when the desk holds nothing dated in a language yet.
      # P49-r4: languages reachable ONLY via multilingual pack members stay
      # off the gold claim — the same exclusion rule (and the same rejected-
      # threshold reasoning) as the language card's axes: line, so the hebrew
      # desk stops claiming a treebank pack's kat/phn/xcl gold rows. The
      # languages: line above deliberately KEEPS pack holdings: its per-code
      # counts self-explain a three-doc spillover; this count-less language
      # list cannot.
      def print_axis_gold(members, by_slug, info, registry:)
        attributable = members.reject { |slug| registry.multilingual?(slug) }
        langs = attributable.flat_map { |slug| by_slug[slug]&.languages || [] }.uniq.sort
        return say("  gold lemmas: no held languages yet") if langs.empty?

        total = info ? info.gold_rows_for(langs) : 0
        if total.positive?
          say "  gold lemmas: #{commas(total)} rows across #{langs.join(', ')} (nabu search --lemma)"
        else
          say "  gold lemmas: none in the held languages (#{langs.join(', ')})"
        end
      end

      def pluralize(count, noun) = "#{count} #{noun}#{'s' unless count == 1}"

      # Render `place` (P44-2): one card per matched place — headline,
      # holdings per source — then the labelled unlinked tail once. The
      # spec shape: "Lilybaeum, Pleiades 462281 — settlement · archaic…roman
      # · 37.80, 12.43" over "holdings: 214 isicily · 12 edh · 2 iip".
      def print_place(result)
        result.cards.each_with_index do |card, index|
          say "" if index.positive?
          print_place_card(card, dump_loaded: result.dump_loaded)
        end
        return if result.unlinked.empty?

        say "  unlinked findspot mentions of #{result.unlinked_term.inspect} " \
            "(text match, no Pleiades id — not counted above): #{format_source_counts(result.unlinked)}"
      end

      # P81 U-3 (survey A3): a gazetteer's own "?"-suffixed title — the
      # Barrington less-certain lineage — glosses right after the title via
      # the shared cataloguer's-"?" helper; unmarked titles stay ink-free.
      def print_place_card(card, dump_loaded:)
        place = card.place
        if card.pleiades_id.nil?
          # P66-2: a namespaced ref card (tm:2810, cigs:GIR) — the title
          # resolves through that gazetteer's own index slice where derived.
          if place
            say "#{place.title}#{place_query_gloss(place.title)}, #{card.ref}#{place_card_tail(place)}"
          else
            say "#{card.ref} — not in the derived place index"
          end
        elsif place
          say "#{place.title}#{place_query_gloss(place.title)}, Pleiades #{place.id}#{place_card_tail(place)}"
        elsif dump_loaded
          say "Pleiades #{card.pleiades_id} — not in the local gazetteer dump"
        else
          say "Pleiades #{card.pleiades_id} — gazetteer dump not synced " \
              "(`nabu sync pleiades` adds the card)"
        end
        # P75 C-3: the crosswalk line — the derived equivalences this
        # identity is asserted equal to, capped with the cut announced.
        unless card.equivalences.empty?
          shown = card.equivalences.first(PLACE_EQUIVALENCES_SHOWN)
          extra = card.equivalences.size - shown.size
          line = shown.map { |namespace, id| "#{namespace}:#{id}" }.join(" = ")
          line += " … and #{extra} more" if extra.positive?
          say "  = #{line}"
        end
        unless card.pleiades_id.nil? && card.holdings.empty?
          say "  holdings: #{card.holdings.empty? ? 'none' : format_source_counts(card.holdings)}"
        end
        unless card.axis_holdings.empty?
          say "  axis holdings (place_ref — adapter-asserted + registry decisions): " \
              "#{format_source_counts(card.axis_holdings)}"
        end
        card.dossiers.each do |dossier|
          say "  ── dossier: #{dossier.title} ──"
          dossier.body.each_line { |line| say "  #{line.chomp}" }
        end
      end

      # " — types · first…last period · lat, lon", each section only when
      # the dump carries it. Periods render as the attested span endpoints
      # (dump attestation order, not re-sorted — honest to upstream).
      # P76 U-4: the CIGS coordinate-accuracy grade rides the tail verbatim
      # (0–3, higher = more accurate; 0 = unlocated) — a precision fact,
      # never a certainty tier (conventions §12).
      def place_card_tail(place)
        sections = [
          place.place_types.join(" · "),
          period_span(place.time_periods),
          place.lat && place.lon ? format("%<lat>.2f, %<lon>.2f", lat: place.lat, lon: place.lon) : nil,
          place.accuracy ? "coordinate accuracy #{place.accuracy}/3 (CIGS grade)" : nil
        ].compact.reject(&:empty?)
        sections.empty? ? "" : " — #{sections.join(' · ')}"
      end

      def period_span(periods)
        return nil if periods.nil? || periods.empty?
        return periods.first if periods.size == 1

        "#{periods.first}…#{periods.last}"
      end

      def format_source_counts(counts)
        counts.map { |slug, count| "#{count} #{slug}" }.join(" · ")
      end

      # The cataloguer's trailing "?" on a place name (P76 U-2): the
      # Barrington-lineage doubt mark glosses as probable, upstream mark
      # kept verbatim in the name itself.
      def place_query_gloss(name)
        return "" unless name.to_s.strip.end_with?("?")

        " (#{Nabu::Certainty.gloss(:cataloguer_query, '?')})"
      end

      # The kind census board (P99-3): class families ranked by document
      # spread, the honesty buckets rendered apart from the classes, the
      # unclassified remainder announced, one summary line with elapsed.
      def print_kind_census(report)
        width = (report.classes.map { |row| row.head.length } + [10]).max
        report.classes.each do |row|
          say "  #{row.head.ljust(width)}  #{commafy(row.documents).rjust(9)} docs · " \
              "#{pluralize(row.sources, 'source')}"
        end
        say "  #{'unknown'.ljust(width)}  #{commafy(report.unknown_documents).rjust(9)} docs " \
            "(upstream's own \"cannot determine\")"
        say "  #{'unmapped'.ljust(width)}  #{commafy(report.unmapped_documents).rjust(9)} docs " \
            "(values awaiting a fold rule — `nabu kind census --unmapped`)"
        if report.uncovered_values.positive?
          say "uncovered: #{pluralize(report.uncovered_values, 'value')} · " \
              "#{commafy(report.uncovered_documents)} docs in #{pluralize(report.uncovered_sources, 'source')} " \
              "(open vocabularies — no rule covers them, so they mint nothing; " \
              "`nabu kind census --uncovered`)"
        end
        say "no classification: #{pluralize(report.unclassified_sources, 'source')} · " \
            "#{commafy(report.unclassified_documents)} docs (their postures speak)"
        total = report.classified_documents + report.unclassified_documents
        share = total.zero? ? 0 : (100.0 * report.classified_documents / total).round(1)
        say "kind census: #{report.classes.size} class families · " \
            "#{commafy(report.classified_documents)} classified docs (#{share}%) " \
            "(#{format_duration(report.seconds)})"
      end

      # The curation worklist (reworked P101 after the owner read the
      # bare dump and could not tell what it was saying): LEAD with what
      # the list is and what to do with a line, list the TODO tail, then
      # the reviewed not-genre declarations as their own section.
      def print_kind_unmapped(census, kinds)
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        rows = census.unmapped_worklist
        print_kind_worklist(rows, census)
        print_kind_deliberate(kinds)
        say "kind census: #{pluralize(rows.size, 'unmapped value')} " \
            "(#{format_duration(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started)})"
      end

      def print_kind_worklist(rows, census)
        return say("kind census: nothing unmapped — every held value has a fold rule") if rows.empty?

        docs = census.run&.unmapped_documents
        say "kind census: #{pluralize(rows.size, 'upstream value')} with no fold rule" \
            "#{" (#{commafy(docs)} documents)" if docs} — each line is a candidate " \
            "config/kind_map.yml entry: fold it to a class, to `unknown` (upstream's " \
            "own cannot-determine), or declare it not-genre under `deliberate:`."
        rows.each do |row|
          say "  #{row.slug.ljust(14)}  #{row.raw.inspect}  ×#{commafy(row.documents)}"
        end
      end

      # The open-vocabulary worklist: values a `vocabulary: open` source
      # carries that no rule covers — they minted no kind row, so this is
      # where they stay visible. Capped at +limit+, the full count
      # announced (cap at render, never a silent truncation).
      def print_kind_uncovered(census, limit:)
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        worklist = census.uncovered_worklist(limit: [limit, 1].max)
        if worklist.total.zero?
          say "kind census: nothing uncovered — no open-vocabulary source carries a value its rules miss"
        else
          say "kind census: open-vocabulary values no rule covers (they mint no kind row) — " \
              "a genre-shaped line is a candidate config/kind_map.yml rule; a topical one needs nothing."
          worklist.rows.each do |row|
            say "  #{row.slug.ljust(14)}  #{row.raw.inspect}  ×#{commafy(row.documents)}"
          end
        end
        shown = worklist.rows.size
        scope = shown < worklist.total ? "showing #{commafy(shown)} of " : ""
        say "kind census: #{scope}#{pluralize(worklist.total, 'uncovered value')} " \
            "(#{format_duration(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started)})"
      end

      # The reviewed non-claims: values config declares NOT genre at all
      # (physical layout, cult context, copy markers) — folded to
      # nothing, listed here so the review stays visible, never noise.
      def print_kind_deliberate(kinds)
        declarations = kinds&.deliberate_declarations || []
        return if declarations.empty?

        say "declared not-genre (config/kind_map.yml `deliberate:` — reviewed, fold to nothing):"
        declarations.each do |slug, value, reason|
          say "  #{slug.ljust(14)}  #{value.inspect} — #{reason}"
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

      def plural(count, noun)
        "#{count} #{noun}#{'s' unless count == 1}"
      end

      # Open the fulltext index for reading; nil when the file is absent OR the
      # FTS table was never built (both mean "no index" → the sync/rebuild hint).
      def open_fulltext(config)
        return nil unless File.exist?(config.fulltext_path)

        db = Nabu::Store.connect_fulltext(config.fulltext_path)
        return db if db.table_exists?(Nabu::Store::Indexer::TABLE)

        db.disconnect
        nil
      end

      # Group an integer's digits into thousands (12345 → "12,345"). Plain string
      # work — no locale gem for one display nicety.
      def commafy(number)
        number.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse
      end

      # One display line of pristine text: newlines flattened, capped at 100
      # chars (treebank sentences are single lines; the cap guards outliers).
      def truncate_line(text, max = 100)
        line = text.tr("\n", " ")
        line.length > max ? "#{line[0, max]}…" : line
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
        say ""
        say result.body
        print_reflexes(result.reflexes)
        print_resolved_citations(result)
        print_crossrefs(result)
      end

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

      # -- nabu signs (P53-2) ----------------------------------------------------

      def signs_dialect(name)
        return nil if name.nil?
        return name.to_sym if Nabu::AtfTokenizer::DIALECTS.map(&:to_s).include?(name)

        raise Thor::Error, "signs: unknown dialect #{name.inspect} — the known dialects are " \
                           "#{Nabu::AtfTokenizer::DIALECTS.join(', ')} (catf is the default)"
      end

      # Urn mode: language from the row (--lang overrides), the :etcsl
      # dialect auto-selected for the etcsl shelf (--dialect overrides).
      def signs_urn_result(urn, list:, catalog:, dialect:)
        result = Nabu::Query::Signs.new(sign_list: list, catalog: catalog)
                                   .run_urn(urn, language: options[:lang], dialect: dialect)
        raise Thor::Error, "signs: urn not found: #{urn}" if result.nil?

        result
      rescue Nabu::Query::Signs::Error => e
        raise Thor::Error, "signs: #{e.message}"
      end

      # The `nabu char` mold: readable columns, absent data ABSENT (a broken
      # token's row is its status; an unknown one says so plainly).
      def print_signs(result)
        say signs_header(result)
        result.lines.each do |line|
          say ""
          say "#{line.urn || "line #{line.number}"}  ·  #{line.text}"
          line.tokens.each { |token| print_signs_token(token) }
        end
        say ""
        say signs_footer(result)
      end

      def signs_header(result)
        parts = [result.mode == :urn ? result.urn : "raw ATF"]
        parts << result.language if result.language
        parts << "[#{result.source_slug}]" if result.source_slug
        parts << "dialect etcsl (c→š, j→ŋ)" if result.dialect == :etcsl
        parts.join("  ·  ")
      end

      def print_signs_token(token)
        columns = [token.input_value.ljust(14), (token.determinative ? "det" : "   "),
                   token.status.ljust(13), signs_token_detail(token)]
        say "  #{columns.join(' ')}".rstrip
        token.candidates.each do |candidate|
          say "  #{' ' * 19}#{candidate.status.ljust(13)} #{signs_candidate_detail(candidate)}"
        end
      end

      def signs_token_detail(token)
        case token.status
        when "ambiguous" then "#{token.candidates.size} candidates:"
        when "unknown" then "not in the sign list"
        when "broken" then nil
        else signs_candidate_detail(token)
        end
      end

      # sign name · codepoints · glyph · (%lang) · (form of X) — only what
      # the record holds; an unencoded sign says "unencoded". The form-of
      # tail is the kunga₃ fix: a sign and its same-named variant form of
      # ANOTHER sign must never render as indistinguishable twins.
      def signs_candidate_detail(token)
        parts = [token.sign_name]
        parts << (token.codepoints ? token.codepoints.join(" ") : "unencoded")
        parts << token.glyph if token.glyph
        parts << "(%#{token.language_qualifier})" if token.language_qualifier
        parts << "(form of #{token.form_of})" if token.form_of
        parts.compact.join("  ")
      end

      def signs_footer(result)
        tokens = result.lines.flat_map(&:tokens)
        tally = tokens.group_by(&:status).transform_values(&:size)
        parts = ["#{tokens.size} token(s)"]
        %w[deterministic qualified ambiguous no-codepoint broken unknown].each do |status|
          parts << "#{status} #{tally[status]}" if tally[status]
        end
        parts << "#{result.skipped_lines} structural line(s) skipped" if result.skipped_lines.positive?
        parts.join("  ·  ")
      end

      # -- the P65 `nabu char` dispatch lanes --------------------------------

      # The original P37-4 Han path; --json emits the P72-2 frozen contract
      # (the sign cards' P65 pattern extended to the Han card). A single
      # glyph OUTSIDE \p{Han} takes the reduced lane (P84-5) — the Han
      # card's shelf pipeline must never run for it (the define join's
      # Sanskrit stem expansion turned "a" into the TLS concept "AS").
      def han_char_card(config, input)
        return non_han_char_card(config, input) unless input.match?(/\p{Han}/)

        catalog = open_catalog(config)
        raise Thor::Error, "no corpus — run nabu sync or nabu rebuild" unless catalog
        unless catalog.table_exists?(:dictionary_entries)
          raise Thor::Error, "no dictionary shelf in this catalog yet — run nabu sync unihan " \
                             "(or nabu rebuild after one)"
        end

        fulltext = open_fulltext(config)
        query = Nabu::Query::Char.new(catalog: catalog, fulltext: fulltext)
        card = query.run(input)
        if options[:json]
          say JSON.pretty_generate(Nabu::Query::Char.json_payload(input, card))
        else
          print_char_card(card, held_cjk: query.held_cjk_sources)
        end
      ensure
        catalog&.disconnect
        fulltext&.disconnect
      end

      # The non-Han card. With the UCD identity floor synced (P85-B2) this is
      # the UNIVERSAL card (owner ruling: Shape C): name, category, numeric value and
      # decomposition for any writing system. Without it, the P84-5 reduced
      # card — glyph, codepoint, script probe — byte-identical (the feature-
      # module law). Pure Unicode either way, so no catalog is opened.
      def non_han_char_card(config, input, panels: nil)
        panels ||= char_ambiguity_panels(config, input)
        universal = Nabu::Ucd.load_default(config: config)&.then do |ucd|
          Nabu::Query::Char.universal(input, ucd)
        end
        return print_universal_char_card(input, universal, panels: panels) if universal

        reduced = Nabu::Query::Char.reduced(input)
        if options[:json]
          payload = Nabu::Query::Char.reduced_json_payload(input, reduced)
                                     .merge(char_panels_json(panels))
          return say(JSON.pretty_generate(payload))
        end

        say "#{reduced.glyph}  #{reduced.codepoint}#{"  ·  #{reduced.script}" if reduced.script}"
        noun = case reduced.script
               when "Hangul" then "a Hangul syllable"
               when nil then "not a Han character"
               else "a #{reduced.script} letter"
               end
        say ""
        say "#{reduced.glyph} is #{noun} — the char card's shelf lanes cover Han characters; " \
            "no CJK shelf claims it"
        print_ambiguity_panels(input, panels)
        say ""
        say "search: nabu search #{reduced.glyph}"
      end

      # -- the ambiguity layer (P86-5) ---------------------------------------
      # A single glyph can carry several identities at once: `a` is a Latin
      # letter AND a pinyin/romaji reading; `と` is a hiragana letter AND a
      # kun reading; `α` looks like `a` and `а`. The card leads with the
      # IDENTITY and composes every other lens as a labeled, capped panel;
      # `--as <lens>` narrows to one.

      def char_as_lens(config, input)
        case options[:as]
        when "identity" then identity_char_card(config, input)
        when "reading" then reading_lens_card(config, input)
        when "sign" then sign_lens_card(config, input)
        when "han" then han_char_card(config, input)
        else
          raise Thor::Error, "char --as: one of identity · reading · sign · han (got #{options[:as]})"
        end
      end

      # The pure identity lens: the universal card with no panels — works for
      # ANY code point, Han included (`char 木 --as identity`).
      def identity_char_card(config, input)
        raise Thor::Error, "char --as identity: the identity lens is one glyph (#{input})" unless input.each_char.one?

        non_han_char_card(config, input, panels: {})
      end

      def reading_lens_card(config, input)
        return if reading_char_card(config, input)

        raise Thor::Error, "#{input}: no held Han reading matches (kana kun/on · CAPS/lowercase " \
                           "romaji · pinyin) — is a dictionary shelf synced?"
      end

      def sign_lens_card(config, input)
        return cuneiform_char_card(config, input) if
          Nabu::CharDispatch.lane(input) == :cuneiform

        name_char_card(config, input)
      end

      # Gather the other-lens panels for a single glyph: the reverse-reading
      # matches (the same query the :name lane runs), the UTS #39 confusables
      # cluster, and (non-ASCII only — plain letters occur everywhere and
      # attest nothing) the corpus-attestation postings. Multi-char input
      # never panels.
      def char_ambiguity_panels(config, input)
        return {} unless input.each_char.one?

        panels = {}
        if (ucd = Nabu::Ucd.load_default(config: config))
          partners = ucd.confusables(input.each_char.first.ord)
                        .map { |other| [format("U+%04X", other), ucd.lookup(other)] }
          panels[:looks_like] = partners if partners.any?
        end
        catalog = open_catalog(config)
        if catalog&.table_exists?(:dictionary_entries)
          matches = Nabu::Query::Char.new(catalog: catalog).characters_for_reading(input)
          panels[:readings] = matches if matches.any?
        end
        if catalog && input.match?(/[^\x00-\x7F]/)
          fulltext = open_fulltext(config)
          corpus = Nabu::Query::Char.new(catalog: catalog, fulltext: fulltext)
                                    .universal_corpus(input)
          panels[:corpus] = corpus if corpus
        end
        panels
      ensure
        fulltext&.disconnect
        catalog&.disconnect
      end

      def print_ambiguity_panels(input, panels)
        if (matches = panels[:readings])
          shown = matches.first(Nabu::Query::Char::READING_PANEL_CAP)
          labels = shown.map do |match|
            kind = match.kind == "pinyin" ? "" : " (#{match.kind})"
            "#{match.glyph} #{match.reading}#{kind}"
          end
          say ""
          say "also a #{reading_panel_noun(matches)} — #{matches.size} Han character(s): " \
              "#{labels.join(' · ')}"
          say "  … nabu char #{input} --as reading for all #{matches.size}" if matches.size > shown.size
        end
        if (partners = panels[:looks_like])
          shown = partners.first(Nabu::Query::Char::LOOKS_LIKE_CAP)
          pieces = shown.map do |(hex, char)|
            [char&.glyph, hex, char&.display_name].compact.join(" ")
          end
          say ""
          say "looks like: #{pieces.join(' · ')}" \
              "#{" · … #{partners.size - shown.size} more" if partners.size > shown.size}"
        end
        print_corpus_panel(panels[:corpus])
      end

      # 88-B2: the last option-(a) members (owner-ruled 2026-08-28) render — encoded variants, named
      # sequences (capped, truncation announced), discouraged-sequence
      # warnings, Tangut/Nushu source fields. Absent = absent.
      def print_universal_extras(card)
        card.variants.each do |variant|
          say format("encoded variants: %<desc>s (U+%<sel>04X)",
                     desc: variant.description, sel: variant.selector)
        end
        shown = card.named_sequences.first(3) # const: a render cap, not a corpus census
        say "named sequences: #{shown.join(' · ')}" if shown.any?
        if card.named_sequences.size > shown.size
          say "named sequences: … #{card.named_sequences.size - shown.size} more"
        end
        card.discouraged.first(2).each do |row| # const: a render cap, not a corpus census
          preferred = row.preferred.split.map { |hex| Integer(hex, 16).chr(Encoding::UTF_8) }.join
          say "discouraged sequence (#{row.type}): heads #{row.sequence} — prefer #{preferred}"
        end
        return unless card.char_sources

        register, fields = card.char_sources
        pairs = fields.sort.map { |key, value| "#{key} #{value}" }
        say "#{register} sources: #{pairs.join(' · ')}"
      end

      # The B3 corpus line, era-honest: counts from a current-class index;
      # zero on a current-class index is a real zero; a miss on a legacy
      # (pre-widening) index names the rebuild instead of lying "0".
      def print_corpus_panel(corpus)
        return unless corpus

        say ""
        if corpus.counts.any?
          ranked = corpus.counts.sort_by { |_, docs| -docs }
          say "corpus attestation: #{ranked.map { |lang, docs| "#{lang || '?'} #{docs}" }.join(' · ')}"
        elsif corpus.class_stamp
          say "corpus attestation: no live passage carries it"
        else
          say "corpus attestation: the char index predates the P86 non-ASCII widening — " \
              "the next rebuild re-accumulates it"
        end
      end

      def reading_panel_noun(matches)
        kinds = matches.map(&:kind).uniq
        return "pinyin reading" if kinds == ["pinyin"]
        return "Japanese reading" if (kinds - %w[kun on]).empty?

        "Han reading"
      end

      def char_panels_json(panels)
        out = {}
        if (matches = panels[:readings])
          out["readings"] = matches.map do |match|
            { "glyph" => match.glyph, "reading" => match.reading, "kind" => match.kind }
          end
        end
        if (partners = panels[:looks_like])
          out["looks_like"] = partners.map do |(hex, char)|
            { "codepoint" => hex, "glyph" => char&.glyph, "name" => char&.display_name }
          end
        end
        if (corpus = panels[:corpus])
          out["corpus"] = { "counts" => corpus.counts, "class" => corpus.class_stamp }
        end
        out.empty? ? {} : { "panels" => out }
      end

      # The universal char card (P85-B2): the UCD identity layer, rendered.
      # Absent layers stay absent (binding-honesty) — numeric value, combining
      # class and decomposition print only when the character carries them.
      def print_universal_char_card(input, card, panels: {})
        payload = Nabu::Query::Char.universal_json_payload(input, card)
                                   .merge(char_panels_json(panels))
        return say(JSON.pretty_generate(payload)) if options[:json]

        say "#{card.glyph}  #{card.codepoint}#{"  ·  #{card.script}" if card.script}"
        say ""
        say "#{card.name} — #{card.category}"
        print_universal_context(card)
        say "numeric value: #{card.numeric}" if card.numeric
        say "combining class: #{card.combining_class}" if card.combining_class.positive?
        print_universal_decomposition(card.decomposition) if card.decomposition
        print_universal_charts(card)
        print_universal_extras(card)
        print_ambiguity_panels(input, panels)
        say ""
        say "search: nabu search #{card.glyph}"
      end

      # The member-context tier (P86-1): block, script identity, age, formal
      # aliases. Absent member → absent line (the P85 floor, byte-identical).
      def print_universal_context(card)
        say "block: #{card.block}" if card.block
        say "script: #{card.script} (#{card.script_code})" if card.script_code
        say "in Unicode since #{card.age}" if card.age
        card.numerals.each do |numeral|
          suffix = numeral.extended ? ", extended/sofit convention" : ""
          say "numeric (#{numeral.scheme}): #{numeral.value}#{suffix} — #{numeral.name}"
        end
        say "script context: #{card.script_context}" if card.script_context
        say "desk: #{card.script_desk}" if card.script_desk
        say "reading: #{card.reading}" if card.reading
        card.aliases.each do |a|
          say "#{a.type == 'correction' ? 'corrected name' : "#{a.type} alias"}: #{a.name}"
        end
      end

      # The NamesList charts annotation layer — informative, labeled as the
      # charts' voice, capped at render (truncation announced; caps live on
      # Nabu::Query::Char beside the card shape).
      def print_universal_charts(card)
        card.chart_aliases.each { |a| say "charts: = #{a}" }
        card.chart_notes.first(Nabu::Query::Char::CHART_NOTE_CAP).each { |n| say "charts: * #{n}" }
        if card.chart_notes.size > Nabu::Query::Char::CHART_NOTE_CAP
          say "charts: … #{card.chart_notes.size - Nabu::Query::Char::CHART_NOTE_CAP} more note(s)"
        end
        card.see_also.first(Nabu::Query::Char::CHART_SEE_ALSO_CAP).each do |ref|
          say "see also: #{"#{ref.glyph} " if ref.glyph}#{ref.codepoint} #{ref.text}".rstrip
        end
        return unless card.see_also.size > Nabu::Query::Char::CHART_SEE_ALSO_CAP

        say "see also: … #{card.see_also.size - Nabu::Query::Char::CHART_SEE_ALSO_CAP} more"
      end

      def print_universal_decomposition(decomp)
        pieces = decomp.parts.map do |part|
          "#{part.glyph} (#{part.codepoint}#{" #{part.name}" if part.name})"
        end
        label = decomp.kind ? "decomposes (#{decomp.kind})" : "decomposes"
        say "#{label}: #{pieces.join(' + ')}"
      end

      # The editorial/house-mark card (P85): what a single mark (⟦ ⌈ ⸀ ⿰ …)
      # MEANS in this library — its convention, the `--display` knob that
      # transforms it, and where it comes from. Pure config read (Nabu's own
      # convention, config/editorial_marks.yml), no catalog. The one card no
      # external Unicode tool can supply.
      def editorial_marks_char_card(config, input)
        mark = Nabu::EditorialMarks.lookup(input)
        # The dispatch set and the table are pinned to agree, so a routed mark
        # is always found; fall back to the universal/reduced card if it drifts.
        return non_han_char_card(config, input) unless mark

        if options[:json]
          return say(JSON.pretty_generate(
                       "glyph" => mark.glyph, "codepoint" => mark.codepoint, "class" => "editorial-mark",
                       "name" => mark.name, "meaning" => mark.meaning,
                       "display" => mark.display_rule, "seen_in" => mark.seen_in
                     ))
        end

        say "#{mark.glyph}  #{mark.codepoint}  ·  editorial mark"
        say ""
        say "#{mark.name} — #{mark.meaning}"
        say ""
        say "display: #{mark.display_rule}" if mark.display_rule
        say "seen in: #{mark.seen_in}" if mark.seen_in
      end

      def cuneiform_char_card(config, input)
        result = run_sign_card(config, input)
        emit_sign_card(result)
      end

      def hieroglyphic_char_card(config, input)
        emit_hiero_card(run_hiero_card(config, input))
      end

      # The multi-char NAME lane (P65-3): an OSL sign name/value first
      # (SZESZ, szesz, |ŠEŠ.AB| — C-ATF folds apply), then a Gardiner-style
      # Unikemet code (G5) — whichever held module resolves it wins; both
      # absent = name the modules. Non-name-shaped input (multi-char text
      # in another script) keeps the classic one-glyph grain error.
      def name_char_card(config, input)
        kana = input.match?(Nabu::Query::Char::KANA_INPUT)
        name_shaped = input.match?(Nabu::CharDispatch::NAME_SHAPE)
        reading_shaped = input.match?(Nabu::Query::Char::PINYIN_INPUT)
        unless kana || name_shaped || reading_shaped
          raise Thor::Error, "char: the card's grain is a single character — give one glyph " \
                             "(#{input}); search --char-component #{input.each_char.first} finds " \
                             "characters that contain one"
        end

        if name_shaped
          if Nabu::SignList.load_default(config: config)
            result = run_sign_card(config, input)
            return emit_sign_card(result) if result.card || result.candidates.any?
          end
          if Nabu::Hieroglyphs.load_default(config: config) && input.match?(Nabu::Query::HieroCard::CODE)
            hiero = run_hiero_card(config, input)
            return emit_hiero_card(hiero) if hiero.card
          end
        end
        return if (kana || reading_shaped) && reading_char_card(config, input)

        if options[:json]
          empty = Nabu::Query::SignCard::Result.new(input: input, card: nil, candidates: [])
          say JSON.pretty_generate(Nabu::Query::SignCard.json_payload(empty))
        else
          say "#{input}: resolved neither as an OSL sign name/value/list number, a Unikemet " \
              "Gardiner-style code, nor a held Han reading — said plainly (input shapes: " \
              "SAR · szesz · idx · MZL535 · 852 · G5 · wen · ひと)"
        end
      end

      # The reading→character lane (P65 gate feedback): pinyin against
      # unihan kMandarin, kana against kanjidic2 on/kun. Prints the match
      # list and answers true; false (silently) when no dictionary shelf or
      # no match, so the caller's honest miss line runs. --json emits the
      # frozen reading contract (P77-r15 — the last char lane to freeze).
      def reading_char_card(config, input)
        catalog = open_catalog(config)
        return false unless catalog&.table_exists?(:dictionary_entries)

        matches = Nabu::Query::Char.new(catalog: catalog).characters_for_reading(input)
        return false if matches.empty?

        if options[:json]
          say JSON.pretty_generate(Nabu::Query::Char.reading_json_payload(input, matches))
        else
          print_reading_matches(input, matches)
        end
        true
      ensure
        catalog&.disconnect
      end

      def print_reading_matches(input, matches)
        say "#{input}: #{matches.size} Han character(s) carry this reading — " \
            "nabu char <glyph> for a card:"
        labels = matches.map do |match|
          kind = match.kind == "pinyin" ? "" : " (#{match.kind})"
          "#{match.glyph} #{match.reading}#{kind}"
        end
        labels.each_slice(6) { |slice| say "  #{slice.join('   ')}" }
      end

      def run_sign_card(config, input)
        list = Nabu::SignList.load_default(config: config)
        unless list
          raise Thor::Error, "char: no cuneiform sign list held — run nabu sync osl (the sign " \
                             "card reads canonical/osl)"
        end

        fulltext = open_fulltext(config)
        catalog = open_catalog(config)
        begin
          Nabu::Query::SignCard.new(
            sign_list: list, readings: Nabu::CdliSignReadings.load_default(config: config),
            fulltext: fulltext, catalog: catalog,
            overlay: Nabu::EdubbaOverlay.load_default(config: config)
          ).run(input)
        ensure
          fulltext&.disconnect
          catalog&.disconnect
        end
      end

      def run_hiero_card(config, input)
        signs = Nabu::Hieroglyphs.load_default(config: config)
        raise Thor::Error, "char: no Egyptian sign spine held — run nabu sync unikemet" unless signs

        catalog = open_catalog(config)
        begin
          Nabu::Query::HieroCard.new(hieroglyphs: signs, catalog: catalog,
                                     overlay: Nabu::EdubbaOverlay.load_default(config: config)).run(input)
        ensure
          catalog&.disconnect
        end
      end

      def emit_sign_card(result)
        if options[:json]
          say JSON.pretty_generate(Nabu::Query::SignCard.json_payload(result))
        else
          print_sign_card(result)
        end
      end

      def emit_hiero_card(result)
        if options[:json]
          say JSON.pretty_generate(Nabu::Query::HieroCard.json_payload(result))
        else
          print_hiero_card(result)
        end
      end

      # The cuneiform sign card (P65-1): sections only where the held OSL /
      # CDLI readings / fulltext back them — the "absent, never —" rule.
      # Ambiguity lists ALL candidates, never one silently.
      def print_sign_card(result)
        return print_sign_card_miss(result) if result.card.nil?

        card = result.card
        header = [card.glyph, card.name].compact.join("  ")
        header += "  (deprecated)" if card.deprecated
        header += "  ·  #{(card.codepoints || ['unencoded']).join(' ')}"
        say header
        say card.uname if card.uname
        say "form of #{card.parent} — nabu char '#{card.parent}'" if card.parent
        say "aka: #{card.aka.join(' · ')}" if card.aka.any?
        print_sign_card_lists(card)
        print_sign_card_values(card)
        print_sign_card_glosses(card)
        print_sign_card_senses(card)
        print_sign_card_forms(card)
        print_sign_card_corpus(card)
        print_sign_didactic(card.didactic)
        print_sign_card_search(card)
      end

      # The Edubba cuneiform overlay section (P77-8, the hiero mold): the
      # certainty grade is LOAD-BEARING — "unclear" prints IN FRONT of
      # the meaning, never as a footnote.
      def print_sign_didactic(overlay)
        return if overlay.nil?

        say ""
        head = ["keyword \"#{overlay['keyword']}\"", overlay["value"] && "value #{overlay['value']}"]
               .compact.join("  ·  ")
        say "didactic (#{[overlay['course'],
                          overlay['chapter'] && "ch. #{overlay['chapter']}"].compact.join(' ')}): #{head}"
        if overlay["meaning"]
          grade = overlay["certainty"] == "unclear" ? "UNCLEAR (origin debated — not fact): " : ""
          say "  meaning: #{grade}#{overlay['meaning']}"
        end
        say "  origin: #{overlay['iconicity']}" if overlay["iconicity"]
        unless Array(overlay["confusables"]).empty?
          follow = overlay["confusables"].map { |name| "#{name} (nabu char #{name})" }.join("  ·  ")
          say "  confusable with: #{follow}"
        end
        say "  #{overlay['description']}" if overlay["description"]
        say "  codex: #{overlay['link']}" if overlay["link"]
        say "  #{overlay['attribution']}"
      end

      # P75 C-4: the follow-up affordance — a sign with reading values can
      # be searched as an OR over them (the inverse of this card).
      def print_sign_card_search(card)
        return if card.values.empty?

        say "search: nabu search --sign '#{card.glyph || card.name}'  (any reading value)"
      end

      def print_sign_card_senses(card)
        return if card.senses.empty?

        say ""
        say "senses (Wiktionary, kaikki extract):"
        card.senses.each { |sense| say "  #{sense.gloss}#{" (#{sense.pos})" if sense.pos}" }
      end

      def print_sign_card_miss(result)
        if result.candidates.any?
          say "#{result.input}: ambiguous — #{result.candidates.size} candidate signs " \
              "(all listed, never one silently):"
          result.candidates.each do |candidate|
            tail = +""
            tail << "  (form of #{candidate.form_of})" if candidate.form_of
            tail << "  (via #{candidate.via})" if candidate.via
            say "  #{candidate.glyph || 'unencoded'}  #{candidate.name}#{tail}  " \
                "—  nabu char '#{candidate.name}'"
          end
        else
          say "#{result.input}: not in the held OSL — said plainly"
        end
      end

      def print_sign_card_lists(card)
        return if card.lists.empty?

        say ""
        say "sign lists: #{card.lists.map { |list, nums| "#{list} #{nums.join(',')}" }.join('  ·  ')}"
      end

      def print_sign_card_values(card)
        return if card.values.empty?

        say ""
        rendered = card.values.map do |value|
          tail = +""
          tail << " (%#{value.language})" if value.language
          tail << " (deprecated)" if value.deprecated
          "#{value.value}#{tail}"
        end
        say "values (OSL): #{rendered.join(' · ')}"
      end

      def print_sign_card_glosses(card)
        glossed = card.glosses.select(&:meaning)
        return if glossed.empty?

        say ""
        say "meanings (CDLI sign readings):"
        glossed.each { |gloss| say "  #{gloss.reading} → #{gloss.meaning}" }
      end

      def print_sign_card_forms(card)
        return if card.forms.empty?

        say ""
        say "variant forms:"
        card.forms.each do |form|
          say "  #{form.glyph || 'unencoded'}  #{form.name}  —  nabu char '#{form.name}'"
        end
      end

      def print_sign_card_corpus(card)
        return if card.corpus.empty?

        say ""
        top = card.corpus.sort_by { |_, count| -count }
                         .map { |value, count| "#{value} #{count}" }.join("  ·  ")
        say "in the corpus (fulltext document counts, by spelled value): #{top}"
      end

      # The Egyptian sign card (P65-2): the Unikemet identity + the aes
      # hiero_inventar panel — absent upstream fields are absent lines.
      def print_hiero_card(result)
        card = result.card
        return say("#{result.input}: not in the held Unikemet file — said plainly") if card.nil?

        header = [card.glyph, card.codepoint].compact.join("  ")
        header += "  ·  #{card.jsesh} (Gardiner/JSesh)" if card.jsesh
        core = { "C" => "core", "L" => "legacy" }[card.core]
        header += "  ·  #{core}" if core
        say header
        say card.desc if card.desc
        say ""
        say "catalog: #{card.cat} (Unicode kEH_Cat)  ·  UniK #{card.unik}"
        say "function: #{card.func}" if card.func
        say "value: #{card.fval}" if card.fval
        concordances = []
        concordances << "Hieroglyphica #{card.hg}" if card.hg
        concordances << "IFAO #{card.ifao}" if card.ifao
        say "concordances: #{concordances.join('  ·  ')}" if concordances.any?
        say "alternate sequence: #{card.alt_seq}" if card.alt_seq
        print_hiero_didactic(card.didactic)
        return if card.corpus.empty?

        say ""
        lines = []
        if card.corpus["passages"]
          lines << "#{card.corpus['signs']} sign(s) across #{card.corpus['passages']} " \
                   "passage(s) (#{Nabu::Query::HieroCard::HIERO_SOURCES.keys.join(' + ')} annotations)"
        end
        # The AED per-text postings (P103-2) — text grain, its own line,
        # with the word-token grain and the damaged (<unclear>) share.
        lines << format_aed_hiero_postings(card.corpus) if card.corpus["aed_texts"]
        say "in the wild: #{lines.join(' · ')}"
      end

      def format_aed_hiero_postings(corpus)
        damaged = corpus["aed_unclear"].to_i.positive? ? ", #{corpus['aed_unclear']} damaged" : ""
        "#{corpus['aed_signs']} sign(s) in #{corpus['aed_words']} word(s) across " \
          "#{corpus['aed_texts']} text(s)#{damaged} (aed hieroglyph transcriptions)"
      end

      # The Edubba overlay section (P72-6). The certainty grade is
      # LOAD-BEARING: "unclear" is Edubba's never-present-as-fact rule,
      # so it prints IN FRONT of the gloss, not as a footnote.
      def print_hiero_didactic(overlay)
        return if overlay.nil?

        say ""
        head = ["keyword \"#{overlay['keyword']}\"", overlay["label"]].compact.join("  ·  ")
        say "didactic (#{[overlay['course'],
                          overlay['chapter'] && "ch. #{overlay['chapter']}"].compact.join(' ')}): #{head}"
        if overlay["voice"]
          grade = overlay["certainty"] == "unclear" ? "UNCLEAR (origin debated — not fact): " : ""
          say "  #{overlay['voice_kind']}: #{grade}#{overlay['voice']}"
        end
        unless Array(overlay["confusables"]).empty?
          follow = overlay["confusables"].map { |code| "#{code} (nabu char #{code})" }.join("  ·  ")
          say "  confusable with: #{follow}"
        end
        say "  #{overlay['description']}" if overlay["description"]
        say "  codex: #{overlay['link']}" if overlay["link"]
        say "  #{overlay['attribution']}"
      end

      # The character card (P37-4): each section printed only when a held
      # shelf backs it for this glyph (the "absent, never —" rule). The
      # diachronic column is what nabu adds over Jisho; the synchronic
      # sections match it field-for-field where the shelves reach.
      def print_char_card(card, held_cjk: [])
        return say("no dictionary shelf in this catalog yet — run nabu sync unihan") if card.nil?

        say "#{card.glyph}  #{card.codepoint}#{char_header_tail(card)}"
        print_char_decomposition(card)
        print_char_components(card)
        print_char_variants(card)
        print_char_ja_readings(card)
        print_char_sinoxenic(card)
        print_char_pedagogy(card)
        print_char_desk_reference(card)
        print_char_diachronic(card)
        print_char_corpus(card)
        print_char_search_affordances(card)
        print_char_absence(card, held_cjk)
      end

      # glyph · N strokes · radical M NAME — only the parts Unihan backs.
      def char_header_tail(card)
        parts = []
        parts << "#{card.total_strokes} strokes" if card.total_strokes
        parts << "radical #{card.radical.number} #{card.radical.glyph} #{card.radical.name}" if card.radical
        parts.empty? ? "" : "  ·  #{parts.join('  ·  ')}"
      end

      def print_char_decomposition(card)
        return if card.ids.empty?

        say ""
        say "decomposition (BabelStone IDS):"
        card.ids.each do |ids|
          tag = ids.sources ? " (#{ids.sources})" : ""
          say "  #{ids.sequence}#{tag}"
          ids.components.each do |component|
            say "    #{component} — nabu char #{component} · nabu search --char-component #{component}"
          end
        end
      end

      def print_char_components(card)
        return if card.components.empty?

        say ""
        say "components (KRADFILE index): #{card.components.join(' ')}"
      end

      def print_char_variants(card)
        return if card.variants.empty?

        say ""
        say "variants:"
        card.variants.each do |variant|
          say "  #{variant.relation}: #{variant.glyph} (#{variant.codepoint}) — nabu char #{variant.glyph}"
        end
      end

      def print_char_ja_readings(card)
        readings = card.readings_ja or return
        say ""
        say "readings (ja, KANJIDIC2):"
        say "  on: #{readings[:on].join('、')}" if readings[:on].any?
        say "  kun: #{readings[:kun].join('、')}" if readings[:kun].any?
        say "  nanori: #{readings[:nanori].join('、')}" if readings[:nanori].any?
        say "  meanings: #{readings[:meanings].join('; ')}" if readings[:meanings].any?
      end

      def print_char_sinoxenic(card)
        return if card.readings_sinoxenic.empty?

        say ""
        say "readings (sinoxenic, Unihan):"
        card.readings_sinoxenic.each { |label, value| say "  #{label}: #{value}" }
      end

      def print_char_pedagogy(card)
        pedagogy = card.pedagogy or return
        say ""
        labels = { "grade" => "Jōyō grade", "jlpt" => "JLPT", "freq" => "newspaper freq" }
        say "pedagogy: #{pedagogy.map { |k, v| "#{labels[k]} #{v}" }.join('  ·  ')}"
      end

      def print_char_desk_reference(card)
        return if card.desk_reference.empty?

        say ""
        say "desk reference: #{card.desk_reference.map { |k, v| "#{k} #{v}" }.join('  ·  ')}"
      end

      # The diachronic column — the half no dictionary site carries.
      def print_char_diachronic(card)
        print_char_shelf_block("Old Chinese (Baxter-Sagart)", card.old_chinese)
        print_char_shelf_block("Middle Chinese (Qieyun / Baxter-Sagart)", card.middle_chinese)
        print_char_shelf_block("early-Japan lexicography (HDIC)", card.early_japan)
        print_char_tls(card.tls)
      end

      def print_char_shelf_block(label, entries)
        return if entries.empty?

        say ""
        say "#{label}:"
        entries.each do |entry|
          say "  [#{entry.slug}] #{entry.gloss || entry.lines.first}"
          entry.lines.each { |line| say "    #{line}" }
        end
      end

      def print_char_tls(entries)
        return if entries.empty?

        say ""
        say "TLS (Thesaurus Linguae Sericae):"
        entries.each do |entry|
          attest = entry.attestations.positive? ? " — #{entry.attestations} attestation(s)" : ""
          say "  [#{entry.slug}] #{entry.gloss}#{attest}"
          entry.lines.each { |line| say "    #{line}" }
        end
      end

      def print_char_corpus(card)
        if card.corpus.nil?
          say ""
          say "corpus attestation: not indexed yet — nabu rebuild (or the next sync) builds " \
              "the char-postings index"
          return
        end
        return if card.corpus.empty?

        say ""
        totals = card.corpus.sort_by { |_, count| -count }
                            .map { |lang, count| "#{lang} #{count}" }.join("  ·  ")
        say "corpus attestation: #{totals}"
        # P72-5: the per-source provenance split, when more than one source
        # attests (a single-source panel would just repeat the line above).
        split = card.corpus_by_source || []
        return unless split.map(&:first).uniq.size > 1

        say "  by source: #{split.map { |slug, lang, docs| "#{slug} #{lang} #{docs}" }.join('  ·  ')}"
      end

      def print_char_search_affordances(card)
        say ""
        say "search: nabu search #{card.glyph}  ·  nabu search --char-component #{card.glyph}" \
            "#{"  ·  nabu search --radical #{card.radical.number}" if card.radical}"
      end

      # When NOTHING backed the card, say so honestly (the glyph is unknown to
      # every held shelf) rather than printing a bare header. P84-5: the hint
      # tells shelves-absent apart from char-not-covered — held CJK shelves
      # that stay silent on this glyph are named as held, and the sync points
      # only at the shelves actually missing from the dictionaries table.
      def print_char_absence(card, held_cjk)
        return unless card.held_shelves.empty? && card.ids.empty? && card.components.empty? &&
                      card.radical.nil? && (card.corpus || {}).empty?

        missing = Nabu::Query::Char::CJK_SHELF_SOURCES.keys - held_cjk
        say ""
        if held_cjk.empty?
          say "no held shelf carries #{card.glyph} yet — sync the CJK shelves (#{missing.join(', ')})"
        elsif missing.empty?
          say "the held CJK shelves (#{held_cjk.join(', ')}) don't carry #{card.glyph}"
        else
          say "the held CJK shelves (#{held_cjk.join(', ')}) don't carry #{card.glyph} — " \
              "sync the missing CJK shelves (#{missing.join(', ')})"
        end
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
        print_reflexes(result.cognates)
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

      # -- language (P18-4, rehomed P19-1): the code desk reference ---------------

      # THE canonical-memory migration (P19-1, owner-fired): ledger
      # language_notes (+ the retired seed yml, when a checkout still has
      # one) → canonical/local-language/<code>.md dossiers. Absence-filling
      # and idempotent — safe to re-run; a dossier lane that already exists
      # (a redirected accretion landed first, or the owner edited) is never
      # overwritten. After it: bin/nabu sync local-language derives the
      # catalog records the card reads.
      def export_language_dossiers(config)
        ledger = open_ledger(config)
        dir = Nabu::LanguageShelf.dir(config)
        seed = File.join(config.config_dir, "languages.yml")
        report = Nabu::LanguageDossierExport.new(ledger: ledger, dir: dir,
                                                 seed_path: File.file?(seed) ? seed : nil)
                                            .run!(dry_run: options[:"dry-run"])
        verb = options[:"dry-run"] ? "would write" : "wrote"
        line = "dossiers: #{verb} #{report.written}, #{report.unchanged} unchanged"
        line += ", #{report.lanes_kept} lane(s) kept (already in a dossier)" if report.lanes_kept.positive?
        say "#{line} → #{dir}"
        say "next: bin/nabu sync local-language (derives the catalog records)" unless options[:"dry-run"]
      ensure
        ledger&.disconnect
      end

      # The card: headline (code — name), family line, curated context (or
      # the family's, labeled; or an honest absence), accreted extra-kind
      # notes (P18-5 — "iecor: IE-CoR variety: …", one line per kind), then
      # live relevance with zero fields suppressed, then the P57-4 stage
      # ladder (when Lects is present and the anchor has registered stages —
      # card-worthy on its own even when nothing else about the bare code is
      # curated: a real ladder is content, not a miss). An unknown code
      # misses honestly, with a family hint when the prefix is a known family.
      def print_language_card(code, languages, info, registry: nil, lects: nil, dossiers: nil, notes: [])
        # P85-A4: the published curated overlay (nabu-data mul/language-
        # dossiers) fills any curated lane the instance's own local dossiers
        # leave absent — identical content on the originating box (local wins),
        # the same context on a fresh install that has only the overlay.
        overlay = dossiers&.dossier(code)
        name = languages.name(code) || overlay&.name
        context = languages.context(code) || overlay&.context
        extras = languages.extra_notes(code)
        extras = overlay.extras.merge(extras) if overlay
        fallback = languages.family_fallback(code)
        relevance = info&.relevance(code)
        held = relevance && !relevance.empty?
        stages = lects&.stages_of(code) || []
        # P67-2: a registered lect anchor is never an unknown code —
        # the registry names it and its descent line renders even with zero
        # holdings (the Aramaic-fan anchors are exactly this case).
        registry_record = lects&.lect(code)
        override_readings = lects&.override_sources(code) || {}
        unless name || context || held || extras.any? || stages.any? || registry_record || overlay ||
               notes.any? || override_readings.any?
          return print_language_miss(code, fallback)
        end

        say "#{code} — #{name || registry_record&.name || '(no name in the held kaikki extracts)'}"
        print_language_override_readings(code, override_readings, lects)
        print_language_family(code, languages, fallback, overlay_family: overlay&.family)
        print_language_descent(code, lects)
        print_language_context(context, fallback)
        # The accreted dossier "stages" section (Nabu::LectDossiers) never
        # renders here — the card owns the LIVE ladder below (same registry
        # facts plus per-stage holdings); printing both would double the
        # surface. Every other accreted kind renders as before.
        extras.except(Nabu::LectDossiers::KIND).each { |kind, body| say_wrapped("#{kind}: #{body}", indent: 2) }
        print_language_witnesses(code, languages)
        print_language_notes(notes)
        print_language_relevance(code, relevance) if relevance
        print_language_dictionary_group(code, info, lects) if info
        print_language_axes(code, info, registry)
        print_language_stage_ladder(code, stages, lects, info)
      end

      # The claim gloss for per-source override codes (owner ruling
      # 2026-10-12): where a collection's legacy code is overridden onto a
      # registered lect, the card states that reading in words — the bare
      # code's ISO assignment may name a different language entirely, and
      # a count surface listing the raw code must never leave that
      # unglossed.
      def print_language_override_readings(code, readings, lects)
        readings.each do |source, lect_id|
          record = lects.lect(lect_id)
          named = record ? "#{record.name} (#{lect_id})" : lect_id
          say_wrapped("collection override: #{source} reads #{code} as #{named} — " \
                      "the collection's own usage, not the code's ISO assignment",
                      indent: 2)
        end
      end

      # P67-2: the descent line — the registry's parent arc, code →
      # root (jpa ← arc ← …), each ancestor named through the same
      # stage-aware walk `parent_of` defines (chu ← sla:pro ← ine-bsl ←
      # ine). Absent registry or a rootless code: no line. A cycle guard
      # rides belt-and-braces (the registry validator already refuses
      # cycles upstream).
      def print_language_descent(code, lects)
        return unless lects

        chain = []
        seen = { code.to_s => true }
        cursor = code.to_s
        while (parent = lects.parent_of(cursor))
          break if seen[parent]

          seen[parent] = true
          chain << parent
          cursor = parent
        end
        return if chain.empty?

        rendered = chain.map do |id|
          record = lects.lect(id)
          record ? "#{id} (#{record.name})" : id
        end
        say "  descent (nabu-lects): #{code} ← #{rendered.join(' ← ')}"
      end

      # P57-4: the stage ladder — every registered stage of +code+ (ord-
      # sorted, already Nabu::Lects#stages_of's contract), each with its
      # band and LIVE holdings: every (language, source) pair the catalog
      # actually carries, resolved through Nabu::Lects#resolve and grouped
      # by resolved lect. A bare-anchor resolution (no stage of its own —
      # still filed under the anchor itself, or reached one whose stage this
      # card does not list) groups under one honest "unstaged" line. A
      # resolution to a DIFFERENT anchor entirely (derom's la-vul -> roa:pro)
      # never enters this ladder — it is a different code's holdings.
      # Reconstructed stages (registry mode: reconstructed) carry the same
      # leading asterisk the etym/define shelves use.
      def print_language_stage_ladder(code, stages, lects, info)
        varieties = lects&.varieties_of(code) || []
        return if (stages.empty? && varieties.empty?) || !info

        totals, variety_totals =
          if info.lect_materialized?
            ladder_totals_from_facets(code, info)
          else
            ladder_totals_from_pairs(code, lects, info)
          end
        return if totals.values.sum.zero? && variety_totals.values.sum.zero?

        if stages.any?
          say "  stages:"
          stages.each do |stage|
            star = stage.mode == :reconstructed ? "*" : ""
            # P76 U-7: an approximate/conventional band_note renders as
            # "ca." on the span — the doctrine's probable tier, the note's
            # own word staying in the registry (conventions §12).
            circa = Nabu::Certainty.tier(:band_note, stage.band_note) == "probable" ? "ca. " : ""
            band = stage.band ? " (#{circa}#{Nabu::Timeline.format_span(stage.band[0], stage.band[1])})" : ""
            say "    #{star}#{stage.stage}  #{stage.name}#{band} — #{plural(totals[stage.id], 'document')}"
          end
        end
        # P58 rider (the owner's zho probe): registered REGISTERS are ladder
        # content — zho/lit is wenyan, not "unstaged". P59-2 (the compose
        # rules): the register line counts EVERY document carrying the
        # variety — stage-less resolutions AND staged-and-varietied ones
        # (akk:na/lit); the latter still fold under their stage above, so
        # the stage column sums to the corpus while the register column
        # reads as an overlay.
        if varieties.any?
          say "  registers:"
          varieties.each do |variety|
            title = variety.name.split(" — ", 2).last
            say "    /#{variety.variety}  #{title} — #{plural(variety_totals[variety.variety], 'document')}"
          end
        end
        unstaged = totals[:unstaged]
        say "    unstaged  — #{plural(unstaged, 'document')}" if unstaged.positive?
      end

      # P58-6: once a materialization exists, the ladder reads the lect
      # facet — the only source that sees per-DOCUMENT journal rulings.
      # Values under other anchors (derom's la-vul -> roa:pro) drop here
      # exactly as they did on the pairs path.
      # Returns [totals, variety_totals]: totals keys stage/register ladder
      # lines (staged-and-varietied folds under its stage); variety_totals
      # counts every carrier of a variety, staged or not — the register
      # line's overlay count (P59-2).
      def ladder_totals_from_facets(code, info)
        totals = Hash.new(0)
        variety_totals = Hash.new(0)
        facet_counts, identity = info.lect_facet_totals(code)
        facet_counts.each do |value, count|
          match = Nabu::Lects.parse_id(value)
          next unless match && match[:anchor] == code.to_s

          totals[ladder_key(code, match)] += count
          variety_totals[match[:variety]] += count if match[:variety]
        end
        totals[:unstaged] += identity if identity.positive?
        [totals, variety_totals]
      end

      # Stage wins (lat:late/ecc groups under lat:late); a stage-less
      # variety is a register line (zho/lit); everything else is honest
      # unstaged.
      def ladder_key(code, match)
        return "#{code}:#{match[:stage]}" if match[:stage]
        return "#{code}/#{match[:variety]}" if match[:variety]

        :unstaged
      end

      # The P57-4 path — a never-materialized catalog resolves (language,
      # source) pairs live, byte-identically to before.
      def ladder_totals_from_pairs(code, lects, info)
        totals = Hash.new(0)
        variety_totals = Hash.new(0)
        info.language_source_pairs.each do |(language, source_slug), count|
          resolved = lects.resolve(language, source: source_slug)
          match = Nabu::Lects.parse_id(resolved)
          next unless match && match[:anchor] == code.to_s

          totals[ladder_key(code, match)] += count
          variety_totals[match[:variety]] += count if match[:variety]
        end
        [totals, variety_totals]
      end

      # P48-r3: the related research desks — every axis whose member
      # sources hold this code (≥1 live document or a dictionary shelf),
      # in ratified (file) order. A code held by no axis-tagged source
      # prints nothing (the house zero-field rule).
      # P49-r4: multilingual packs (the registry marker) never attribute —
      # a pack's whole-grain axes union describes no single held language,
      # so its three hbo docs must not drag twelve desks onto the hbo card.
      # The desks keep the code via any DEDICATED source that holds it.
      # The simple exclusion was chosen over a dominance/share threshold
      # deliberately (era-bound-constants doctrine): any tuned cutoff is a
      # census claim that rots as packs grow, while "packs never attribute,
      # dedicated holders always do" stays true at every census. A pack-only
      # code honestly gets no axes line; its desks still surface the code
      # WITH COUNTS on the axis card's languages: line — the deliberate
      # asymmetry (counts are the honesty mechanism there, print_axis_languages).
      def print_language_axes(code, info, registry)
        return unless info && registry && !registry.axes.empty?

        slugs = info.holding_slugs(code).reject { |slug| registry.multilingual?(slug) }
        return if slugs.empty?

        names = registry.axes.each_axis.map(&:name)
                        .select { |name| registry.axis_members(name).intersect?(slugs) }
        say "  axes: #{names.join(', ')}" unless names.empty?
      end

      # P18-6: the per-source witness notes (kind "witness:<slug>" — what
      # each held source says about this language stage; LIV/EDL accrete
      # them at sync with per-record provenance). One wrapped line per
      # source, quiet when none.
      def print_language_witnesses(code, languages)
        languages.witnesses(code).each do |source, body|
          say_wrapped("witness (#{source}): #{body}", indent: 2)
        end
      end

      def print_language_miss(code, fallback)
        say "#{code} — unknown here: no held text, no shelf, no etymology edge, " \
            "and no name in the held kaikki extracts"
        if fallback
          hint = [fallback.name, fallback.context].compact.join(": ")
          say_wrapped("family hint: #{fallback.code}-* — #{hint}", indent: 2)
        end
        say "  held languages: nabu language --list"
      end

      def print_language_family(code, languages, fallback, overlay_family: nil)
        family = languages.family(code) || overlay_family
        if family
          say_wrapped("family: #{family}", indent: 2)
        elsif fallback&.name
          say_wrapped("family: #{fallback.code}-* — #{fallback.name}", indent: 2)
        end
      end

      # P85-A (owner-ruled 2026-08-28): the private language-note layer — the owner's own
      # per-language notes (`nabu note <code> "…"`), kept local/ and never
      # published, composed beneath the universal overlay. Absent = nothing
      # printed (binding honesty).
      def print_language_notes(notes)
        return if notes.empty?

        say "  notes (private):"
        notes.each { |note| say_wrapped("#{note.note}#{note_tags_fragment(note)}", indent: 4) }
      end

      def print_language_context(context, fallback)
        if context
          say_wrapped(context, indent: 2)
        elsif fallback&.context
          say_wrapped("(no curated note for this code — its #{fallback.code}-* family:) " \
                      "#{fallback.context}", indent: 2)
        else
          say "  (no curated note)"
        end
      end

      def print_language_relevance(code, rel)
        corpus = []
        corpus << plural(rel.documents, "document") if rel.documents.positive?
        corpus << "#{commas(rel.passages)} passages" if rel.passages.positive?
        say "  corpus: #{corpus.join(' · ')}" unless corpus.empty?
        say "  gold lemmas: #{commas(rel.lemma_rows)} rows (nabu search --lemma)" if rel.lemma_rows.positive?
        unless rel.shelves.empty?
          shelf_list = rel.shelves.map { |shelf| "#{shelf.title} (#{commas(shelf.entries)} entries)" }
          say "  dictionary: #{shelf_list.join(' · ')}"
        end
        say "  etymology: #{commas(rel.reflex_edges)} reflex #{rel.reflex_edges == 1 ? 'edge' : 'edges'}" \
          if rel.reflex_edges.positive?
        print_language_long(code, rel) if options[:long]
      end

      # P106-3 (owner ruling, generalization 2): the dictionary GROUP — every shelf whose lect
      # resolution lands at or under this code's node, off the
      # dictionary_stats census. Renders only when the group is WIDER than
      # the code's own shelves (the relevance block above already lists
      # those); a group of one code adds nothing. Feature-off (no census
      # derived yet, or no group): silent — the card is unchanged.
      def print_language_dictionary_group(code, info, lects)
        # const: render cap — the group line is a summary, not a listing
        cap = 8
        group = info.dictionary_group(code, lects: lects)
        return unless group&.node
        return if group.rows.empty? || group.rows.all? { |row| row[:language] == code.to_s }

        count = group.rows.size
        say "  dictionary group (#{group.node}): #{count} #{count == 1 ? 'dictionary' : 'dictionaries'} · " \
            "#{commas(group.total)} entries"
        shown = group.rows.first(cap)
        shown.each do |row|
          code_note = row[:language] == code.to_s ? "" : " · #{row[:language]}"
          say "    #{row[:slug]} — #{commas(row[:entries])} entries#{code_note}"
        end
        hidden = group.rows.size - shown.size
        say "    … #{hidden} more" if hidden.positive?
      end

      # --long: per-source document counts and the upstream-code split of
      # the etymology edges (chu's edges arrive as Wiktionary's "cu").
      def print_language_long(code, rel)
        unless rel.sources.empty?
          say "  by source: #{rel.sources.map { |slug, docs| "#{slug} #{commas(docs)}" }.join(' · ')}"
        end
        return unless rel.edge_codes.any? && rel.edge_codes.keys != [code]

        say "  edge codes: #{rel.edge_codes.map { |edge_code, n| "#{edge_code} #{commas(n)}" }.join(' · ')}"
      end

      # --list: the held languages only (a full dump of the ~800-code
      # etymology tail would be unusable and unpageable; the tail is what
      # `language CODE` is for — stated in the footer, never implied away).
      def print_language_list(languages, info, lects = nil)
        raise Thor::Error, "no corpus — run nabu sync or nabu rebuild" unless info

        held = info.held
        say "held languages (#{held.size} with corpus documents, gold lemmas, or a shelf):"
        width = held.map { |entry| entry.code.length }.max || 0
        held.each do |entry|
          say "  #{entry.code.ljust(width)}  #{languages.name(entry.code) || '(unnamed)'} — " \
              "#{held_line(entry)}"
        end
        print_registry_extension(lects)
        say "etymology tail: ~800 more codes appear in reflex edges — nabu language CODE explains any"
      end

      # P90-5 (lane 3): is +term+ a language the desks know — a lect id
      # the registry parses, or a code the names census can name? (The
      # membership test the front door needs; the language command itself
      # renders unknown codes as honest misses, which would swallow every
      # string.)
      def info_language?(config, term, lects)
        return true if lects&.lect(term)

        catalog = open_catalog(config)
        return false unless catalog

        !Nabu::Languages.new(catalog: catalog).name(term).nil?
      ensure
        catalog&.disconnect
      end

      # A script-dossier tag for +term+: the tag itself, or a case-blind
      # script NAME alias (glag / Glagolitic), else nil.
      def info_script_tag(term)
        tag = term.downcase
        return tag if Nabu::ScriptDossiers.lookup(tag)

        Nabu::ScriptDossiers.table.find { |_t, row| row["name"].to_s.casecmp?(term) }&.first
      end

      # P90-5 (lane 2): the script dossier card — the curated context
      # config/script_dossiers.yml holds (published as nabu-data
      # mul/script-dossiers) finally readable from the CLI.
      def print_script_card(tag, lects)
        dossier = Nabu::ScriptDossiers.lookup(tag)
        say "script #{dossier.name} (#{dossier.tag})"
        say_wrapped(dossier.context, indent: 2)
        if dossier.desk
          say "  desk:"
          say_wrapped(dossier.desk, indent: 4)
        end
        row = lects&.script_rows&.dig(dossier.tag)
        if row
          iso = row["iso15924"] ? ", ISO 15924 #{row['iso15924']}" : ""
          say "  registry: minted in the nabu-lects scripts table#{iso}"
        else
          say "  registry: nabu-lects not synced — the scripts-table row is unavailable"
        end
      end

      # P90-5 (lane 1): the nabu-lects layer the listing was missing —
      # every anchor with minted stages/varieties, i.e. the lect ids the
      # cards, `search --lect` and the postures accept beyond bare codes.
      def print_registry_extension(lects)
        unless lects
          say "registry extension: nabu-lects not synced (nabu sync nabu-lects)"
          return
        end
        ladders = lects.ladders
        say "registry extension (nabu-lects): #{ladders.size} anchors carry minted stages/varieties " \
            "— ids like grc:koi work on cards, --lect and postures:"
        width = ladders.map { |ladder| ladder.anchor.length }.max || 0
        ladders.each do |ladder|
          bits = []
          bits << "stages: #{ladder.stages.join(' ')}" unless ladder.stages.empty?
          bits << "varieties: #{ladder.varieties.join(' ')}" unless ladder.varieties.empty?
          say "  #{ladder.anchor.ljust(width)}  #{ladder.name} — #{bits.join(' · ')}"
        end
      end

      def held_line(entry)
        bits = []
        bits << "#{commas(entry.documents)} docs" if entry.documents.positive?
        bits << "#{commas(entry.lemma_rows)} lemma rows" if entry.lemma_rows.positive?
        (bits + entry.shelves).join(" · ")
      end

      def commas(count)
        count.to_s.gsub(/\B(?=(\d{3})+\z)/, ",")
      end

      # Wrap prose to the card's width, every line indented.
      def say_wrapped(text, indent:, width: 78)
        pad = " " * indent
        line = +""
        text.split(/\s+/).each do |word|
          if line.empty?
            line << word
          elsif pad.length + line.length + 1 + word.length > width
            say "#{pad}#{line}"
            line = +word
          else
            line << " " << word
          end
        end
        say "#{pad}#{line}" unless line.empty?
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

      # A print-free runner needs a sink for live progress; the CLI owns all
      # formatting and tty decisions here. Progress goes to $stderr (final counts
      # go to $stdout via `say`, so scripts piping stdout are unaffected). When
      # $stderr is a tty: git output streams raw (its own \r overwrites the line)
      # and a \r-updating "loading…" counter refreshes each tick. Non-tty: no git
      # streaming (callbacks stay nil) and one plain line per 100 documents.
      def progress_reporter
        tty = $stderr.tty?
        state = { stage: nil, started: nil, processed: 0, errored: 0, last: 0 }
        @progress_state = state
        Nabu::ProgressReporter.new(
          on_fetch_line: tty ? ->(line) { $stderr.print(line) } : nil,
          on_load_tick: load_tick(tty, state),
          on_stage: stage_tick(tty, state),
          on_note: progress_note(state),
          on_explain: verbose_narrator
        )
      end

      # --verbose (Ops::StageGuide): ONE narrator per invocation, so each
      # stage explains once however many reporters the command builds
      # (an axis sync builds one per member). Green on stderr beside the
      # stage lines; nil when not verbose, so the reporter's explain seam
      # is a no-op. +before+ closes an open \r stage line first.
      def verbose_narrator
        return nil unless options[:verbose]

        @verbose_narrator ||= Nabu::Ops::StageGuide::Narrator.new(
          io: $stderr, sources: verbose_source_slugs,
          before: -> { close_stage(@progress_state) if @progress_state }
        )
      end

      # The command's intro (what the run is about to do to the library),
      # printed before any work when --verbose is on.
      def explain_command(key)
        verbose_narrator&.intro(key)
      end

      # The registered slugs, so a bare-slug replay stage resolves to the
      # source-replay explanation.
      def verbose_source_slugs
        Nabu::SourceRegistry.load(Nabu::Config.load.sources_path).each_source.map(&:slug)
      rescue Nabu::Error
        []
      end

      # A durable header/tally line (owner UX rule 2026-10-07 — the
      # incremental verdict sweep's ETA header and closing tally): closes
      # any open stage first, then prints on tty and non-tty alike.
      def progress_note(state)
        lambda do |line|
          close_stage(state)
          $stderr.tty? ? $stderr.print("\r\e[K  #{line}\n") : warn("  #{line}")
        end
      end

      # Owner feedback (2026-07-18): a long rebuild must name the source it
      # is on and how long each stage took. A stage closes when the next one
      # opens (or at finish_progress), its line ending in final counts +
      # elapsed; sync paths never call stage, so they keep the bare counter.
      # +eta+ (P78-r2): when the runner consulted the stage_timings
      # history, the open line SPEAKS the estimate — including the honest
      # "first run — no estimate" — and non-tty (the caffeinate/drill logs,
      # where every owner-perceived "hang" of P77 was read) gets the open
      # line too, so the log names what is running BEFORE it finishes.
      def stage_tick(tty, state)
        lambda do |label, eta = nil|
          close_stage(state)
          state[:stage] = label
          state[:eta] = eta
          state[:started] = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          state[:processed] = state[:errored] = state[:last] = 0
          suffix = eta ? "#{eta.render} " : ""
          if tty
            $stderr.print("\r\e[K  #{label}… #{suffix}")
          elsif eta&.real?
            # Non-tty prints the open line only when there is a REAL
            # estimate to speak (P78-r3: "first run — no estimate" on
            # every tiny shelf sync is noise in a log; the close line
            # with counts + elapsed is the record either way).
            warn("  #{label}… #{suffix}")
          end
        end
      end

      def close_stage(state)
        return if state[:stage].nil?

        line = "  #{state[:stage]}… #{stage_counts(state)}#{format_elapsed(state)}"
        $stderr.tty? ? $stderr.print("\r\e[K#{line}\n") : warn(line)
        state[:stage] = nil
      end

      # Zero docs is a timeline/facet/index stage, not an empty shelf — show
      # only the timing (compact-output convention: suppress zero fields).
      def stage_counts(state)
        return "" if state[:processed].zero? && state[:errored].zero?

        "#{state[:processed]} docs#{quarantine_suffix(state[:errored])} "
      end

      def format_elapsed(state)
        format_duration(Process.clock_gettime(Process::CLOCK_MONOTONIC) - state[:started])
      end

      def load_tick(tty, state)
        lambda do |processed, errored|
          state[:processed] = processed
          state[:errored] = errored
          label = state[:stage] || "loading"
          left = time_left_suffix(state, processed)
          if tty
            $stderr.print("\r\e[K  #{label}… #{processed} docs#{quarantine_suffix(errored)}#{left}  ")
          elsif processed - state[:last] >= (state[:stage] ? 1000 : 100)
            state[:last] = processed
            warn("  #{label}… #{processed} docs#{quarantine_suffix(errored)}#{left}")
          end
        end
      end

      # P78-r2: the in-stage extrapolation — once ticks flow and the last
      # run recorded a row count, the observed rate projects the remainder
      # (" ~3m left"). Guarded: enough ticks and elapsed time to trust the
      # rate, and only while the recorded total still lies ahead (past it,
      # the estimate would be a lie — drift means more rows this run).
      def time_left_suffix(state, processed)
        basis = state[:eta].respond_to?(:basis_rows) ? state[:eta].basis_rows : nil
        return "" unless basis&.positive? && processed >= 100 && processed < basis

        elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - state[:started]
        return "" if elapsed < 5

        " ~#{Nabu::Eta.format_seconds(elapsed / processed * (basis - processed))} left"
      end

      def quarantine_suffix(errored)
        errored.positive? ? " (#{errored} quarantined)" : ""
      end

      # Break off the \r-updated counter line before the final counts —
      # closing the open stage (with its timing) when there is one.
      def finish_progress
        if @progress_state && @progress_state[:stage]
          close_stage(@progress_state)
        elsif $stderr.tty?
          $stderr.print("\n")
        end
      end

      # P42-4: the one honest planner-hygiene line — printed only when a bulk
      # load or a rebuild actually refreshed the query-planner statistics,
      # silent otherwise (a sub-threshold sync, a clean-swept incremental run).
      def print_analyzed(analyzed)
        return unless analyzed

        say "  analyzed #{analyzed.scope} (planner stats refreshed, #{format('%.1f', analyzed.seconds)}s)"
      end

      # P39-4: the within-pass collision tail — silent at zero (house
      # compact-zero rule; collisions are pathological), loud when one bit.
      def format_collided(report)
        report.collided.positive? ? "  !#{report.collided} collision" : ""
      end

      # Open the catalog db for reading if it has been built; nil otherwise so
      # status degrades gracefully to registry-only output.
      def open_catalog(config)
        return nil unless File.exist?(config.catalog_path)

        db = Nabu::Store.connect(config.catalog_path)
        Nabu::Store.setup!(db)
        db
      end

      # Open the catalog for writing, creating + migrating it if this is the
      # first sync before any rebuild. Migrations are idempotent (only pending
      # ones run), so this is safe on an existing db too. Callers that also
      # open the ledger MUST open it first (open_or_create_ledger lifts a
      # pre-P7-1 catalog's history before migration 005 drops those tables).
      def open_or_create_catalog(config)
        require "fileutils"
        FileUtils.mkdir_p(File.dirname(config.catalog_path))
        db = Nabu::Store.connect(config.catalog_path)
        Nabu::Store.migrate!(db)
        Nabu::Store.setup!(db)
        db
      end

      # Open the history ledger for reading; nil when absent (fresh machine —
      # read paths treat that as empty history) or not yet migrated.
      def open_ledger(config)
        return nil unless File.exist?(config.history_path)

        db = Nabu::Store::Ledger.connect(config.history_path)
        return Nabu::Store::Ledger.setup!(db) if db.table_exists?(:runs)

        db.disconnect
        nil
      end

      # Open the history ledger for writing: create + migrate it, and lift a
      # pre-P7-1 catalog's runs/pins/baselines into it (one-shot; the catalog
      # is then migrated forward, dropping the moved tables).
      def open_or_create_ledger(config)
        Nabu::Store::Ledger.open_with_lift!(
          history_path: config.history_path, catalog_path: config.catalog_path
        )
      end
    end
  end
end

# The CLI command areas (pure carve-outs of the one CLI class above).
require_relative "cli/sync"
require_relative "cli/census"
require_relative "cli/profile"
require_relative "cli/admin"
require_relative "cli/query"
require_relative "cli/links"
require_relative "cli/enrich"

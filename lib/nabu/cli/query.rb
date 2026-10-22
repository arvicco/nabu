# frozen_string_literal: true

# Nabu::CLI — corpus query commands: search, concord, show, note, vocab.
# Carved out of lib/nabu/cli.rb, the registry that loads it.
module Nabu
  class CLI < Thor
    desc "search QUERY", "Full-text search the corpus (FTS5 over folded text)"
    long_desc <<~HELP, wrap: false
      Full-text search over every live passage, bm25-ranked. Matching is
      diacritic- and case-insensitive on BOTH sides: μηνιν finds μῆνιν,
      ΜΗΝΙΝ finds both — type without accents, breathings, or iota
      subscripts and still hit the polytonic editions. The fold also matches
      modern Japanese reading habits: 学 finds 學, 弁 finds 辨/瓣/辯.

      EXACT (--exact): glyph-literal match — the query must appear in the
      passage's stored text exactly as typed (NFC-normalized, but nothing
      else: no diacritic strip, no case fold, no reform fold). Use it to tell a
      literal 弁 apart from the default's 弁/辨/瓣/辯. It runs the normal folded
      search for candidates, then keeps only glyph-literal hits — so it does
      not combine with --fuzzy/--near/--lemma/--morph or the character filters.

      WHOLE-WORD (--word): keep only hits where the query lands on a WORD
      BOUNDARY in the stored text — a fold-aware whole-word match. ἦ finds the
      standalone particle ἦ but NOT ἦμαρ (the query sits mid-word there); 学
      still folds to 學 but only as a whole word. A boundary is the start/end
      of the text or a non-letter (whitespace, punctuation — combining marks
      are word-internal, so accents never break a word). --word composes with
      --exact (word-AND-glyph exact: ἦ finds ἦ, not ἦμαρ nor a folded ἠ) and,
      alone, with the plain fold; it does NOT combine with
      --fuzzy/--near/--lemma/--morph or the character filters. Spaceless scripts
      have no word boundaries: --word on a query containing Han or kana is
      REFUSED (use --exact for glyph-literal matching there). Hangul is
      space-delimited, so --word treats it like any alphabetic script.

      BROWSE (term-less): run search with NO query to LIST the corpus, but only
      when at least one CONTENT-NARROWING filter is present — a date window
      (--from/--to/--century), --date-basis, --place, a genre facet (--type/--province/
      --material), or --loans. The page is served in corpus order (no ranking),
      the standard hit rendering with a stored-text window per passage, --limit
      honored. --lang/--license/--source/--axis select whole shelves and are NOT
      sufficient on their own — a term-less listing of a whole language is a
      dump, not a browse — so combine them WITH a content filter to scope one
      (`--century 2 --axis epigraphy` lists the 2nd-c. inscriptions). The
      character-structure filters (--radical/--strokes/--char-component) are a
      separate term-less path of their own.

      Query syntax (SQLite FTS5 over the folded text):
        μηνιν αειδε          all words must appear in the passage (implicit AND)
        '"μηνιν αειδε"'      exact adjacent phrase — FTS quotes, so shell-quote them
        μηνι*                prefix match (μῆνιν, μηνίω, μήνιμα, …)
      Boolean OR/NOT are not supported: operators are folded to lowercase
      and become ordinary search terms.

      Each hit prints the passage urn, its language, and a folded snippet
      with the match in [brackets] (on an interactive terminal, RTL scripts
      highlight the match in reverse video instead — bracket glyphs do not
      survive bidi reordering; piped output keeps the brackets). The snippet is the SEARCH form, not the
      edition text — `nabu show <urn>` gives the pristine passage. DDbDP
      papyri render lost text as the […] gap marker.

      Filters (combinable):
        --lang     ISO-639-3 passage language: grc, lat, got, chu, orv, san, …
        --license  effective license class (document override beats source):
                   open, attribution, nc, research_private, restricted
        --source   one source slug (nabu list names them); composes with
                   every other filter, --lemma/--near/--fuzzy included
        --limit    maximum hits, default 20

      LEMMA SEARCH (--lemma FORM): exact dictionary-form lookup over the
      gold treebank annotations (UD, PROIEL, TOROT — the sources that carry
      per-token lemmas). One lemma finds every inflected attestation, even
      suppletive stems no text query can reach: --lemma λέγω hits λέγουσι,
      λέγοιεν, AND εἶπας/εἰπεῖν. Hits show the dictionary form, the surface
      form(s) that matched, and the pristine passage line. Diacritics are
      optional on the query, exactly as in text search (λεγω works; so does
      final-sigma-insensitive λόγος/λογοσ). --lemma REPLACES the text query
      (combining both is not supported); it composes with --lang, --limit,
      and --license. Passages outside the treebanks carry no lemma
      annotations and are honestly absent here.

      MORPH FACETS (--morph case=dat,number=pl): with --lemma, narrow to
      attestations whose morphology matches the given facets (comma-joined
      key=value, all required). The vocabulary is Universal Dependencies
      feature names — case, number, gender, person, tense, mood, voice,
      degree (values dat, pl/sg, masc, aor, opt, sub…); UD treebanks match on
      their `feats`; PROIEL/TOROT, GLAUx (AGDT postag), Diorisis, BHSA/DSS,
      OSHB, ReM/ReN (CorA msd), goo300k (IMP msd) and Menota (msa) are
      decoded into the same names — Hebrew/Aramaic add state, stem and
      conjugation (e.g. --morph stem=piel,conjugation=wayq). Ambiguous
      analyses match when any reading fits. Each hit shows the matching
      surface form(s) and the decoded morph evidence. --morph REQUIRES --lemma (bare morphology search
      is out of scope); ORACC carries no inflectional morphology, so
      inflectional facets never match it (honest absence). See conventions §6.1.

      TOKEN GLOSSES (--gloss WORD): sources that store upstream's own word
      meaning on each token (bhsa, achemenet: English; aes, tlhdig: German)
      show it on every lemma hit in ‘quotes’, beside any dictionary gloss.
      With --lemma, --gloss keeps only attestations whose token gloss
      contains WORD (whole word, case-insensitive) — e.g. BHSA's consonantal
      דבר as "word" vs "speak". Composes with --morph; not with --near.

      PROXIMITY (A --near B [--window N]): keep only hits where B occurs
      within N words of A in the SAME passage — λόγος near θεός is John 1:1.
      Built on FTS5 NEAR over the folded search forms: --window N is the max
      words BETWEEN the two terms (default 10; 0 = immediately adjacent), and
      NEAR is order-independent (A…B and B…A both count). The window counts
      folded tokens, so for cuneiform (akk/sux), where sign-joins and
      determinatives fold to spaces, one transliterated word spans several
      tokens and the window reads tighter. --near composes with --lemma (the
      anchor then expands to the lemma's attested surface forms before the
      NEAR: --lemma λέγω --near κύριος finds εἶπε near κύριος too), and with
      --lang/--license/--limit. Cross-passage adjacency is OUT — the passage
      is the unit. --morph does not compose with --near (out of scope). Both
      matched terms are bracketed in the snippet, shown in the stored text
      (the pristine spelling, not the folded search form).

      FUZZY (--fuzzy): substring/fragment search for damaged texts — matches
      the fragment ANYWHERE in a passage, mid-word included, where normal
      search sees only whole words and prefixes. Type the fragment straight
      off the edition: editorial square brackets are stripped from the query
      before matching, so `']μηνιν αει['` works as typed. Built on a
      character-trigram index over the folded search form (same
      diacritic/case folding as plain search), so fragments need at least 3
      characters. Scope is DOCUMENTARY sources only (papyri-ddbdp, oracc,
      edh, open-etruscan, edr, elephantine — registry `fuzzy_index: true`):
      papyrus lines, tablets and damaged inscriptions are where fragment
      search earns its index bytes; every result footer names the
      live scope. For half-remembered LITERARY quotations use plain search
      or `nabu parallels` — the literary corpus is deliberately not
      trigram-indexed (it would grow the index 15×). Composes with --lang,
      --limit, --license, and --from/--to/--century/--place; --long prints
      the full folded passage instead of the windowed snippet. --fuzzy
      replaces the FTS query syntax: the fragment is matched literally
      (no AND/phrase/prefix operators) and does not combine with
      --lemma/--near/--morph.

      DATE BASIS (--date-basis CLASS[,CLASS...]): keep only documents whose
      PRIMARY date — the one `nabu show` renders — is of the named class:
      artifact (the source's own typed date of the object or witness),
      composition (attributed author-era dating), edition (a print year) or
      silver (a model/tool ESTIMATE from the local-dates shelf, projected by
      `nabu silver-dates --project`; any upstream date outranks it). With
      --from/--to/--century the window then reads that same primary date,
      so `--date-basis artifact --century 2` holds out author-era datings
      instead of mixing them in. Without --date-basis the date window reads
      upstream dates only — silver estimates answer only when named. An
      unknown class is refused naming the known set. Text search, --fuzzy,
      --scan and a term-less browse.

      FACETS (--type / --province / --material): document-grained categorical
      filters over the facet table (P17-2 — EDH inscriptions seed it: 22
      EAGLE inscription types, 103 Roman provinces, materials). Patterns are
      case-insensitive and match the normalized term OR the upstream raw code
      (--type epitaph and --type titsep both work; % wildcards as in
      --place). They compose with the text query, --fuzzy, and every
      date/place filter — the epigraphist's slice is
      `--type epitaph --province "Pannonia inferior" --century 2`. A document
      with no facet row falls out under an active filter (honest absence:
      only faceted sources — inscriptions — can match). Like the date
      filters they do not combine with --lemma/--near. Facet rows land at
      `nabu rebuild` (like the timeline).

      --facet NAME=PATTERN is the generic form: any facet name, repeatable
      (each one must hold). A name is one axis across both grains — the
      document facets (okhc collection, cdli material, author …) AND the
      passage facets projected from per-article annotations (sillok
      subject, itkc genre), which narrow to the very passage that carries
      the claim: `--facet subject=왕실-%` lists Sillok articles under the
      royal-house subject tree. The pattern matches the value or the
      authority ref. --type/--province/--material are shorthands for
      --facet genre=/province=/material=.

      LOANS (--loans CODE): the language-contact facet (P34-2, reading the
      P17-1 annotations) — keep only passages carrying at least one token
      the corpus tags as borrowed from CODE. Passage-grained and read
      straight off each passage's stored token annotations: no reparse, no
      rebuild step. Codes are the mapped origins grc / hbo / arc / lat /
      egy plus any verbatim upstream name (Akkadian, Arabic, Phoenician,
      Persian…), matched case-insensitively; an unattested code finds
      nothing, honestly. Today the Coptic Scriptorium shelf carries the
      layer (~56k of its passages bear Greek loan tokens). Unlike the
      document facets, --loans composes with EVERYTHING: the text query,
      --fuzzy, --lemma/--morph, --near, and all of --lang/--license/
      --source/date/place/facet filters — the loans corpus is
      gold-lemmatized, so `--lemma ⲛⲟⲩⲧⲉ --loans grc` is the designed
      move (attestations of a Coptic lemma in Greek-loan-bearing verses).
      `nabu list coptic-scriptorium --loans` is the census view.

      Sources ingesting parallel translations (registry `translations: true`,
      P7-4) make those English passages ordinary search hits; --lang eng
      scopes to them, --lang grc keeps them out. `show <hit> --parallel`
      jumps from either side to the aligned line in the other.

      TRANSLATIONS (--translations): search the translations a source keeps
      INSIDE its passages' annotations rather than as sibling documents —
      Coptic SCRIPTORIUM's English (and Arabic/German), CDLI's and eBL's ATF
      #tr lines, the German word glosses of the glossed Hittite corpus,
      CorPH, the UD treebanks' sentence translations, Tamilex, the Old Dutch
      corpus, St Gall Priscian, ACLT, DiCCAS, Guaman Poma, the Middle Korean
      shelf's modern rendering. Each hit is the ORIGINAL passage (its urn
      and language), with the matched rendering and the original text under
      it — `nabu show <urn>` opens the text itself. Words AND together,
      "double quotes" make a phrase, word* a prefix; matching is diacritic-
      and case-insensitive. --lang filters on the ORIGINAL's language.
      Composes with --lang/--source/--axis/--license/--limit only. Every
      render names the sources the index covers; the lane is built by the
      reference rebuild (or `bundle exec rake index:translations`).

      Examples:
        nabu search μηνιν                          # finds μῆνιν, accents optional
        nabu search '"ανδρα μοι εννεπε"'           # Odyssey 1.1 — including the
                                                   #   papyri that quote it
        nabu search sapientia --lang lat           # Latin corpus only
        nabu search μηνι* --lang grc               # every derivative of the stem
        nabu search αγαπη --license attribution    # only freely re-usable hits
        nabu search "rich-haired" --lang eng       # the ingested translations
        nabu search --translations "save my soul"  # the Coptic passages whose
                                                   #   English rendering says so
        nabu search --translations wettergott --source hittite-glossed
                                                   # Hittite lines glossed "storm-god"
        nabu search --lemma λέγω --lang grc        # every attestation in the Greek
                                                   #   treebank: λέγουσι, εἶπας, εἰπεῖν…
        nabu search --lemma tu --lang lat          # te, tibi, tu across PROIEL Cicero
        nabu search --lemma λόγος --morph case=dat,number=pl
                                                   # only the dative-plural λόγοις
        nabu search --lemma דבר --gloss word       # BHSA דבר as "word", not "speak"
        nabu search λόγος --near θεός --window 5    # λόγος within 5 words of θεός
                                                   #   (John 1:1 and its kin)
        nabu search --lemma λέγω --near κύριος      # every inflection of λέγω
                                                   #   near κύριος: τάδε λέγει κύριος
        nabu search --fuzzy ']μηνιν αει['           # a damaged scrap, brackets and
                                                   #   all — infix match, papyri+oracc
        nabu search --fuzzy στρατηγ --century 6     # mid-word fragment, 6th c. papyri
        nabu search --century 2 --axis epigraphy    # term-less browse: the 2nd-c.
                                                   #   inscriptions, corpus order
        nabu search "dis manibus" --type epitaph --province "Germania superior"
                                                   # the D M formula on epitaphs of
                                                   #   one province (EDH facets)
        nabu search 大王大妃 --facet subject=왕실-의식%   # Sillok articles on royal rites
        nabu search --fuzzy "votum solvit" --type "votive%" --material Sandstein
                                                   # V S L M on sandstone votives
        nabu search ⲡⲛⲟⲩⲧⲉ --loans grc --lang cop   # "God" in verses that carry
                                                   #   Greek loan tokens
        nabu search arma --meter H                  # hits restricted to scanned
                                                    #   hexameters (P44 meter layer:
                                                    #   pedecerto/hypotactic)
        nabu search --meter P --lang lat            # term-less browse: every scanned
                                                    #   pentameter line
        nabu search --lemma ⲕⲁϩ --loans grc         # a Coptic lemma's attestations
                                                   #   inside the Greek-contact zone

      Use cases: find a half-remembered line; concordance-style scans of a
      word across six corpora at once; checking which sources attest a term
      (and under what license) before an export.
    HELP
    option :lang, type: :string, desc: "Restrict to a passage language (e.g. grc, lat)"
    option :license, type: :string,
                     desc: "Restrict to an exact license class (open, attribution, nc, …)"
    option :source, type: :string, banner: "SLUG",
                    desc: "Restrict to one source (`nabu list` names the slugs)"
    option :axis, type: :string, banner: "NAME[,NAME...]",
                  desc: "Restrict to the members of one or more research axes (config/axes.yml) — the " \
                        "multi-source generalization of --source; composes with every path and filter"
    option :limit, type: :numeric, default: 20, desc: "Maximum number of hits"
    option :lemma, type: :string, banner: "FORM",
                   desc: "Exact-lemma search over the gold treebanks (replaces the text query)"
    option :morph, type: :string, banner: "FACETS",
                   desc: "Morphology facets (with --lemma), e.g. case=dat,number=pl"
    option :gloss, type: :string, banner: "WORD",
                   desc: "Token-gloss filter (with --lemma): keep attestations whose upstream gloss " \
                         "contains WORD (bhsa/aes/achemenet/tlhdig)"
    option :near, type: :string, banner: "TERM",
                  desc: "Proximity: keep only hits where TERM is within --window words of the query/lemma"
    option :window, type: :numeric, default: Nabu::Query::Proximity::DEFAULT_WINDOW,
                    desc: "Max words between the two --near terms (default " \
                          "#{Nabu::Query::Proximity::DEFAULT_WINDOW}; 0 = adjacent)"
    option :from, type: :numeric, banner: "YEAR",
                  desc: "Earliest date: signed historical year, negative = BCE (-300 = 300 BCE, no year 0)"
    option :to, type: :numeric, banner: "YEAR",
                desc: "Latest date: signed historical year (14 = 14 CE); composes with --from"
    option :century, type: :numeric, banner: "N",
                     desc: "Shorthand for one century's --from/--to (6 = 6th c. CE, -2 = 2nd c. BCE)"
    option :date_basis, type: :string, banner: "CLASS[,CLASS...]",
                        desc: "Date-basis filter: keep documents whose primary date is of this class " \
                              "(artifact, composition, edition, silver); with --from/--to the window " \
                              "reads that same date"
    option :place, type: :string, banner: "NAME|ns:id",
                   desc: "Provenance filter: a namespaced ref (tm:2810, cigs:GIR), a name resolved " \
                         "to its identities + name match, or a LIKE pattern (oxyrhynch%)"
    option :script, type: :string, banner: "TAG",
                    desc: "Script filter, ISO 15924-style registry tag (latn, xsux): the held text's " \
                          "~script lect axis OR the artifact-script axis (\"Latin-script Gaulish\")"
    option :sign, type: :string, banner: "GLYPH|NAME",
                  desc: "Search by cuneiform sign (the inverse of nabu signs): 𒀝 or AK expands to " \
                        "an OR over the sign's OSL reading values; IS the query — give no term"
    option :within, type: :string, banner: "LAT,LON,KM",
                    desc: "Geo-radius filter over the coordinates lane (source-asserted " \
                          "find-locations, e.g. rundata): 59.86,17.64,50 keeps documents found " \
                          "within 50 km; coordinate-less documents fall out"
    option :scan, type: :boolean, default: false,
                  desc: "Filter-first mode: walk the term's matches in corpus order intersected " \
                        "with the active filters — deterministic, never sampled (the mode for " \
                        "a common term + a selective filter); needs a term AND a filter"
    option :type, type: :string, banner: "PATTERN",
                  desc: "Inscription-type facet filter (epitaph, votive%, or the raw titsep code)"
    option :kind, type: :string, banner: "CLASS[/SUB[/SUB]]",
                  desc: "Document-kind filter over the ruled cross-corpus classes: any path " \
                        "prefix matches its whole family (funerary ⊇ funerary/epitaph, " \
                        "literary/narrative ⊇ literary/narrative/epic), a full path narrows; " \
                        "unmapped and unknown are first-class (`nabu kind census` lists all)"
    option :province, type: :string, banner: "PATTERN",
                      desc: "Roman-province facet filter (Germania inferior, pannonia%)"
    option :material, type: :string, banner: "PATTERN",
                      desc: "Material facet filter (Marmor, sandstein%)"
    option :facet, type: :string, repeatable: true, banner: "NAME=PATTERN",
                   desc: "Any facet by name, at either grain — document facets (collection, author …) " \
                         "and passage facets (sillok subject, itkc genre): --facet subject=왕실-% " \
                         "matches value or ref, LIKE patterns pass through; repeatable (AND)"
    option :loans, type: :string, banner: "CODE",
                   desc: "Loan-origin facet: only passages with ≥1 token borrowed from CODE " \
                         "(grc, hbo, arc, lat, egy — Coptic Scriptorium)"
    option :meter, type: :string, banner: "CODE",
                   desc: "Meter facet: only passages carrying a meter enrichment with this code " \
                         "(pedecerto codes H, P, …) or name (hypotactic 'dactylic hexameter'); " \
                         "case-insensitive; composes with a text query or stands alone as a browse"
    option :meter_pattern, type: :string, banner: "PATTERN",
                           desc: "Meter facet: exact foot/scansion pattern (pedecerto DSDS, " \
                                 "hypotactic '-u u -uu …'); composes with --meter or stands alone"
    option :radical, type: :numeric, banner: "N",
                     desc: "Character filter: KangXi radical number 1-214 (Unihan kRSUnicode); " \
                           "composes with --strokes/--char-component and a text query"
    option :strokes, type: :string, banner: "A-B",
                     desc: "Character filter: total-stroke range A-B (or a single N; Unihan kTotalStrokes)"
    option :char_component, type: :string, banner: "C",
                            desc: "Character filter: characters CONTAINING C anywhere in their " \
                                  "structure (KRADFILE ∪ BabelStone IDS transitive containment)"
    option :charset, type: :string, banner: "CHARS",
                     desc: "Graded-reading filter (P72-1): only passages whose distinct Han " \
                           "characters fall INSIDE this set (fold-aware; spaces ignored); " \
                           "composes with a text query and --lang/--license/--source"
    option :signset, type: :string, banner: "SIGNS",
                     desc: "Sign-coverage filter for the ATF corpora (P77-r16, sign-learning P-3): " \
                           "only passages whose resolved OSL sign inventory falls inside this " \
                           "comma-separated set of sign names/values; composes with --max-foreign"
    option :max_foreign, type: :numeric, default: 0, banner: "N",
                         desc: "With --charset/--signset: allow up to N characters/signs outside " \
                               "the set per passage (0-3); each hit names its strangers"
    option :min_chars, type: :numeric, default: 0, banner: "N",
                       desc: "With --charset: only passages with at least N distinct Han " \
                             "characters — floors the cleanest-first order above one-char fragments"
    option :fuzzy, type: :boolean, default: false,
                   desc: "Substring/fragment search over the documentary trigram index (]μηνιν αει[)"
    option :translations, type: :boolean, default: false,
                          desc: "Search the translations held in passage ANNOTATIONS (coptic, cdli/ebl #tr, " \
                                "hittite-glossed trans_de, corph, …); hits are the original passages — " \
                                "composes with --lang/--source/--axis/--license/--limit only"
    option :withdrawn, type: :boolean, default: false,
                       desc: "Attic inspection: search WITHDRAWN passages only (upstream-gone " \
                             "documents, revision-pruned passages) — substring match over the " \
                             "folded text, each hit labeled with its reason; composes with " \
                             "--limit only"
    option :similar, type: :string, banner: "URN",
                     desc: "Semantic neighbors of one embedded passage (P93-5): " \
                           "same-language cross-edition retrieval over the nabu-embed vectors, " \
                           "rendered in bands (close/near/loose), model named in the header — " \
                           "IS the query (give no term); composes with --limit only"
    option :long, type: :boolean, default: false,
                  desc: "With --fuzzy: print the full folded passage instead of the windowed snippet"
    option :gold_only, type: :boolean, default: false,
                       desc: "With --lemma: gold (verified) annotations only — exclude silver " \
                             "(automatic) lemmatization and equivalence (scholar-curated " \
                             "Classical-Latin equivalents on non-Latin passages)"
    option :exact, type: :boolean, default: false,
                   desc: "Glyph-literal match; the default fold matches modern reading habits " \
                         "(学 finds 學, 弁 finds 辨/瓣/辯) — --exact does not"
    option :word, type: :boolean, default: false,
                  desc: "Whole-word match: the query must land on a word boundary in the stored " \
                        "text (ἦ finds ἦ, not ἦμαρ); refuses spaceless CJK/kana"
    option :words, type: :boolean, default: false,
                   desc: "Tibetan word-grain match (P54-4): keep only hits whose matched span " \
                         "aligns with word boundaries (nabu-data xct/segmentation) — Tibetan is " \
                         "indexed at syllable grain, so a plain query also lands on accidental " \
                         "runs across word boundaries; non-Tibetan queries or an unsynced module " \
                         "degrade to plain search with a note"
    option :lect, type: :string, banner: "LECT-ID",
                  desc: "Lect filter (P57-4, nabu-lects module): keep only hits whose (language, " \
                        "source) resolves to this lect id or a more specific one under it " \
                        "(--lect lat matches lat:med; --lect lat:med matches lat:med and " \
                        "lat:med/xyz, not lat:cla). Text search or a term-less browse only, not " \
                        "--lemma/--near; errors if the nabu-lects module is not synced"
    display_option
    def search(query = nil)
      query = query.to_s.strip
      display_mode
      date_basis_filter
      return translations_search(query) if options[:translations]
      if (options[:from] || options[:to] || options[:century] || options[:place] || facet_filters ||
          options[:date_basis]) &&
         (options[:near] || options[:lemma])
        raise Thor::Error, "search: --from/--to/--century/--date-basis/--place/--type/--province/--material/--facet " \
                           "compose with text search only, not --lemma/--near (the dated/faceted corpus — " \
                           "papyri, inscriptions — is not lemmatized)"
      end
      if options[:fuzzy] && (options[:near] || options[:lemma] || options[:morph])
        raise Thor::Error, "search: --fuzzy is literal substring matching — it does not combine " \
                           "with --lemma/--near/--morph"
      end
      if (options[:meter] || options[:meter_pattern]) &&
         (options[:near] || options[:lemma] || options[:fuzzy] || char_filter_options?)
        raise Thor::Error, "search: --meter/--meter-pattern filter the meter enrichment layer and " \
                           "compose with plain text search or a term-less browse only — not " \
                           "--lemma/--near/--fuzzy or the character-structure filters"
      end
      if options[:gold_only] && (!options[:lemma] || options[:near])
        raise Thor::Error, "search: --gold-only filters the lemma tier — it requires --lemma " \
                           "(and does not compose with --near)"
      end
      if options[:gloss] && (!options[:lemma] || options[:near] || options[:gloss].strip.empty?)
        raise Thor::Error, "search: --gloss WORD filters lemma attestations by upstream's token gloss — " \
                           "it needs a word and requires --lemma (and does not compose with --near)"
      end
      if options[:exact] && (options[:fuzzy] || options[:near] || options[:lemma] || options[:morph])
        raise Thor::Error, "search: --exact is glyph-literal substring matching over the plain " \
                           "text query — it does not combine with --fuzzy/--near/--lemma/--morph"
      end
      if options[:exact] && char_filter_options?
        raise Thor::Error, "search: --exact is a word-level glyph-literal filter — it does not " \
                           "combine with the character-structure filters (--radical/--strokes/--char-component)"
      end
      if options[:word] && (options[:fuzzy] || options[:near] || options[:lemma] || options[:morph] ||
                            char_filter_options?)
        raise Thor::Error, "search: --word is a whole-word filter over the plain text query — it " \
                           "composes only with --exact, not --fuzzy/--near/--lemma/--morph or the " \
                           "character-structure filters"
      end
      if options[:word] && (msg = Nabu::Query::Search.word_refusal_for(query))
        raise Thor::Error, "search: #{msg}"
      end
      if options[:words] && (query.empty? || options[:fuzzy] || options[:near] || options[:lemma] ||
                             options[:morph] || options[:exact] || options[:word] || char_filter_options?)
        raise Thor::Error, "search: --words is the Tibetan word-grain filter over the plain text " \
                           "query — it needs a text query and does not combine with --exact/--word/" \
                           "--fuzzy/--near/--lemma/--morph or the character-structure filters"
      end
      if options[:lect] && (options[:near] || options[:lemma] || options[:fuzzy] || char_filter_options?)
        raise Thor::Error, "search: --lect filters the lect-resolution layer and composes with " \
                           "plain text search or a term-less browse only — not --lemma/--near/" \
                           "--fuzzy or the character-structure filters"
      end

      if options[:charset]
        if options[:fuzzy] || options[:near] || options[:lemma] || options[:morph] ||
           options[:exact] || options[:word] || options[:words] || char_filter_options? ||
           options[:signset]
          raise Thor::Error, "search: --charset is the coverage filter over whole passages — it " \
                             "composes with a plain text query and --lang/--license/--source only"
        end
        return graded_search(query)
      end
      if options[:signset]
        if query || options[:fuzzy] || options[:near] || options[:lemma] || options[:morph] ||
           options[:exact] || options[:word] || options[:words] || char_filter_options?
          raise Thor::Error, "search: --signset is the sign-coverage filter over whole ATF passages " \
                             "— it composes with --max-foreign and --lang/--license/--source only"
        end
        return sign_graded_search
      end
      if options[:max_foreign].to_i.positive?
        raise Thor::Error, "search: --max-foreign only accompanies --charset or --signset"
      end

      if char_filter_options?
        if options[:fuzzy] || options[:near] || options[:lemma] || options[:morph]
          raise Thor::Error, "search: the character filters (--radical/--strokes/--char-component) are " \
                             "character-level structure search — they do not combine with the word-level " \
                             "--lemma/--near/--fuzzy/--morph (they compose with a plain text query)"
        end
        return char_structured_search(query)
      end
      if options[:similar]
        unless query.empty? && !options[:fuzzy] && !options[:near] && !options[:lemma] &&
               !options[:morph] && !options[:exact] && !options[:word] && !options[:scan] &&
               !options[:withdrawn] && !char_filter_options? && !options[:sign]
          raise Thor::Error, "search: --similar URN is the semantic-neighbors page — the urn IS " \
                             "the query (give no term); it composes with --limit only"
        end
        return similar_search(options[:similar])
      end
      if options[:withdrawn]
        if query.empty? || options[:fuzzy] || options[:near] || options[:lemma] || options[:morph] ||
           options[:exact] || options[:word] || options[:words] || options[:scan] ||
           char_filter_options? || options[:sign]
          raise Thor::Error, "search: --withdrawn is the attic inspection — a plain text query " \
                             "plus --limit only (the withdrawn set is small; filters would " \
                             "overpromise)"
        end
        return withdrawn_search(query)
      end
      return sign_search(query) if options[:sign]
      return scan_search(query) if options[:scan]
      return fuzzy_search(query) if options[:fuzzy]
      return proximity_search(query) if options[:near]
      return lemma_search(query) if options[:lemma]
      raise Thor::Error, "search: --morph requires --lemma (bare morphology search is out of scope)" if options[:morph]
      return browse_search if query.empty?

      validate_license!(options[:license])
      from, to = date_window
      place = options[:place]
      facets = facet_filters
      loans = loans_filter
      config = Nabu::Config.load
      catalog = open_catalog(config)
      fulltext = open_fulltext(config)
      # Either half of the derived store missing means the corpus was never
      # built/indexed; a search cannot run.
      raise Thor::Error, "no index — run nabu sync or nabu rebuild" unless catalog && fulltext

      require_timeline!(catalog) if from || to || place || options[:date_basis]
      require_facets!(catalog) if facets
      validate_source!(catalog, options[:source])
      axis_names, axis_slugs = axis_membership(command: "search", config: config)
      lects = require_lects!(config, options[:lect])

      searcher = Nabu::Query::Search.new(catalog: catalog, fulltext: fulltext, lects: lects || :auto,
                                         places: Nabu::Places.load_default(canonical_dir: config.canonical_dir))
      results = searcher.run(query, lang: options[:lang], license: options[:license],
                                    limit: options[:limit].to_i, from: from, to: to, place: place,
                                    date_basis: date_basis_filter,
                                    facets: facets, source: options[:source], sources: axis_slugs,
                                    loans: loans, meter: options[:meter],
                                    meter_pattern: options[:meter_pattern],
                                    exact: options[:exact], word: options[:word], words: options[:words],
                                    lect: options[:lect], script: options[:script],
                                    within: within_filter)
      print_search_results(results, facets: facets, query: query, loans: loans, axis: axis_names,
                                    incomplete: searcher.incomplete_hint, exact: options[:exact],
                                    word: options[:word], rank_note: searcher.rank_note,
                                    meter_note: searcher.meter_note, words_note: searcher.words_note,
                                    place_note: searcher.place_note)
      print_display_footer
    rescue Nabu::Error => e
      # A malformed filter arg (--script shape) or a query-layer refusal —
      # a clean stderr message and exit 1, never a backtrace.
      raise Thor::Error, e.message
    ensure
      catalog&.disconnect
      fulltext&.disconnect
    end

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

    desc "show URN", "Show a passage or document by urn (withdrawn items shown, flagged)"
    long_desc <<~HELP, wrap: false
      Inspect one passage or one whole document by urn. Unlike search and
      export, show hides nothing: withdrawn and retired-upstream items
      appear too, honestly labeled — this is the "what does my collection
      actually hold" lens.

      A PASSAGE urn prints the pristine text, its document, effective
      license, revision, and the full provenance trail (loaded / revised /
      withdrawn / restored / retired events with timestamps) — the
      passage's complete life story.

      A DOCUMENT urn prints the header (title, language, source, license,
      revision, any withdrawn/retired flag) and every passage in citation
      order, listed as :suffixes relative to the document urn printed once
      above; --full-urn restores absolute urns for copy-paste. Long
      documents: pipe to less.

      urn shapes across the corpus:
        CTS editions   urn:cts:greekLit:tlg0012.tlg002.perseus-grc2       (document)
                       urn:cts:greekLit:tlg0012.tlg002.perseus-grc2:1.1   (book 1, line 1)
        papyri (DDbDP) urn:nabu:ddbdp:aegyptus:89:240:b2:5
                       (:b2 = implicit restart block — an unlabeled column/
                        fragment where the edition's line numbers restart)
        treebanks      urn:nabu:proiel:afnik:194690                     (sentence)
                       urn:nabu:ud:gothic-proiel:got_proiel-ud-dev:37589

      RANGES (URN:<start>-<end>): a document urn plus two citation suffixes
      joined by a hyphen prints an INCLUSIVE, sequence-ordered slice of that
      one document between the endpoints — both endpoints must resolve to
      existing passages of the same document (a clear error names whichever
      fails; a start after its end is refused, suggesting a swap). The slice
      is by STORED sequence, whatever citation shapes lie between: a papyri
      restart block (:b2, an implicit column/fragment) is sliced straight
      through. Precedence: a literal passage urn is resolved FIRST, so a urn
      that itself contains a hyphen is never misparsed as a range; the range
      split is on the LAST hyphen (citation suffixes never contain one, the
      version segment perseus-grc2 does). Ranges compose with --full-urn and
      with --parallel (the range slices the queried edition; pairing then
      applies to the sliced rows only).

      PARALLEL TRANSLATIONS (--parallel [LANG], default eng): for a CTS
      document or passage urn — or an ORACC tablet, whose translation is the
      -en sibling document (P13-4) — find the sibling edition of the SAME
      work in LANG (sources ingest translations only when their registry
      entry sets `translations: true`) and render the two SPAN-GROUPED by
      citation suffix. A verse-for-verse translation pairs line by line —
      :1.1 Greek next to :1.1 English. A card-cited prose translation (both
      English Homers) anchors one block of text at a card's first line: the
      original lines are listed, then the translation ONCE, labeled with its
      coverage in the original's numbering (`eng [:1.1 — covers :1.1–:1.43]`)
      plus a clip note when a range shows only part of a card. ORACC's
      paragraph-grained SAA units render as exactly such blocks over the
      tablet's o.1/r.5 lines. A suffix present in only one edition renders
      honestly one-sided, never fuzzed. Works with --full-urn. Where a
      kind=translation link edge joins documents across sources (the
      Kangyur↔84000 crosswalk), --parallel pairs them at Degé folio/page
      grain — no extra flag.

      Examples:
        nabu show urn:cts:greekLit:tlg0012.tlg002.perseus-grc2:1.1
        nabu show urn:cts:greekLit:tlg0012.tlg001.perseus-grc2:1.1-1.10
                                                  # Iliad 1.1–1.10, one slice
        nabu show urn:nabu:ddbdp:aegyptus:89:240:1-b2:2
                                                  # a papyrus slice across a restart block
        nabu show urn:nabu:ddbdp:aegyptus:89:240            # whole papyrus
        nabu show urn:nabu:ddbdp:aegyptus:89:240 --full-urn # absolute urns
        nabu show urn:cts:greekLit:tlg0013.tlg013.perseus-grc2 --parallel
                                                  # Greek + eng, line by line
        nabu show urn:cts:greekLit:tlg0012.tlg002.perseus-grc2:1.5-1.10 --parallel
                                                  # a mid-card slice: the eng block labeled
                                                  #   "covers :1.1–:1.43; range shows :1.5–:1.10"
        nabu show urn:cts:greekLit:tlg0013.tlg013.perseus-eng2:1 --parallel grc
                                                  # one translated line + its original
        nabu show urn:nabu:oshb:gen:1:1 --tokens  # + the stored token annotations,
                                                  #   verbatim (form, lemma, osm, …)
        nabu show urn:cts:greekLit:tlg0016.tlg001.perseus-grc2:1.6 --entities
                                                  # + the persons/places marked in it
        nabu show urn:nabu:dcs:5:3363:2612 --senses  # + each token's word senses

      TOKENS (--tokens): appends the passage's stored token annotations as
      one line per token — `form` first, then every key the store holds for
      that token, exactly as stored (the honest raw view; nothing decoded,
      nothing invented). A passage without token annotations, and a
      document/range urn, say so.

      ENTITIES (--entities): appends the names the edition marks INSIDE
      the text — Perseus persName/placeName/name spans, Coptic Scriptorium
      entity spans, DHARMA Deccan person/place tags — one line per record:
      upstream's type, the surface, then any key/identity/ref/subtype,
      verbatim. A document or range urn groups them under each passage's
      :suffix. Search by name across the corpus with `nabu entity NAME`.

      SENSES (--senses): appends the word senses the passage's gold tokens
      cite (DCS WordSem ids, the source's token_fields rule in
      config/facet_map.yml) — one line per citing token, form (lemma) then
      each sense id with its dcs-senses name and gloss; an id the shelf
      does not hold says so. A document or range urn groups them under each
      passage's :suffix. Search by sense with `nabu sense TERM`.

      SEGMENTED (--segmented): renders Tibetan-language rows (xct/bod/otb)
      with word boundaries — the stored text with a space inserted at each
      boundary (tokens verbatim, trailing tsheg kept), segmented through
      the published nabu-data xct/segmentation dataset. An off-language
      row, or a box that has not run `nabu sync nabu-data`, prints the
      plain text plus one honest note.

      Use cases: read the real edition text behind a search snippet; audit
      a document's revision/provenance history after a sync; eyeball what
      "withdrawn" or "retired upstream" actually holds; read a Greek work
      you can't sight-read next to its English translation; inspect the
      exact lemma/morphology evidence a treebank stored for one passage.
    HELP
    option :full_urn, type: :boolean, default: false,
                      desc: "List document passages with absolute urns instead of :suffixes"
    option :parallel, type: :string, lazy_default: "eng", banner: "[LANG]",
                      desc: "Align with the same work's LANG edition by citation suffix (default eng)"
    option :random, type: :boolean, default: false,
                    desc: "Show random passages instead of a urn (the eyeball ritual at a source flip)"
    option :source, type: :string, banner: "SLUG",
                    desc: "With --random: draw only from this source (default: the whole corpus)"
    option :lang, type: :string, banner: "CODE",
                  desc: "With --random: draw only passages in this language (grc, lat, … — the multi-lang eyeball)"
    option :count, type: :numeric, default: 1,
                   desc: "With --random: how many passages (default 1, cap #{Nabu::Query::Random::MAX_COUNT})"
    option :tokens, type: :boolean, default: false,
                    desc: "Append the passage's stored token annotations verbatim (form + every key present)"
    option :entities, type: :boolean, default: false,
                      desc: "Append the names the edition marks inside the text (persons, places …), verbatim"
    option :senses, type: :boolean, default: false,
                    desc: "Append the word senses the gold tokens cite (DCS WordSem), resolved against dcs-senses"
    option :segmented, type: :boolean, default: false,
                       desc: "Render Tibetan (xct/bod/otb) passages with word boundaries " \
                             "(needs the synced nabu-data module)"
    display_option
    def show(urn = nil)
      urn = urn.to_s.strip
      display_mode
      if options[:tokens] && (options[:random] || options[:parallel])
        raise Thor::Error, "show: --tokens does not compose with --random/--parallel"
      end
      if options[:segmented] && (options[:random] || options[:parallel])
        raise Thor::Error, "show: --segmented does not compose with --random/--parallel"
      end
      if options[:entities] && (options[:random] || options[:parallel])
        raise Thor::Error, "show: --entities does not compose with --random/--parallel"
      end
      if options[:senses] && (options[:random] || options[:parallel])
        raise Thor::Error, "show: --senses does not compose with --random/--parallel"
      end

      config = Nabu::Config.load
      catalog = open_catalog(config)
      raise Thor::Error, "no catalog — run nabu sync or nabu rebuild" unless catalog

      if options[:random]
        show_random(catalog, urn, config)
        return print_display_footer
      end
      raise Thor::Error, "show: --source requires --random" if options[:source]
      raise Thor::Error, "show: --lang restricts --random draws — give a urn, or add --random" if options[:lang]
      raise Thor::Error, "show: give a urn" if urn.empty?

      if options[:parallel]
        show_parallel(catalog, urn, options[:parallel], config)
        return print_display_footer
      end

      # pleiades: :auto — the findspot line (P44-2) feature-detects the
      # gazetteer dump lazily; nothing loads unless the shown document
      # carries a captured Pleiades id.
      show_query = Nabu::Query::Show.new(catalog: catalog, pleiades: :auto)
      result = show_query.run(urn)
      raise Thor::Error, "urn not found: #{urn}" if result.nil?

      # --segmented (P54-2): the word-broken Tibetan rendering. The
      # segmentation is Query::Show's (the one serializer MCP shares); here
      # we only swap texts on a copy of the result — or keep the plain
      # output plus the query layer's one honest note line.
      seg_note = nil
      if options[:segmented]
        seg_note = show_query.segmentation_note(result.respond_to?(:language) ? result.language : nil)
        result = segmented_show_result(show_query, result) if seg_note.nil?
      end

      print_show(result)
      say seg_note if seg_note
      print_show_tokens(result) if options[:tokens]
      print_show_entities(result) if options[:entities]
      print_show_senses(result, catalog: catalog, config: config) if options[:senses]
      print_linked_footer(config, result.urn)
      print_notes_footer(catalog, result)
      print_display_footer
    rescue Nabu::Query::Range::Error, Nabu::Query::Random::Error,
           Nabu::Query::Parallel::TranslationMismatch => e
      # A range urn that names two endpoints but can't be honoured (endpoint
      # missing, or reversed), an unknown --random --source, or a --parallel
      # LANG the translation link cannot serve: a clean stderr message + exit 1.
      raise Thor::Error, e.message
    ensure
      catalog&.disconnect
    end

    desc "note URN|CODE [TEXT]", "Annotate any urn the corpus knows, or a language code (→ local-notes/)"
    long_desc <<~HELP, wrap: false
      The owner's annotation lane (architecture §16) — scholia of one's own,
      keyed by ANY urn the corpus knows: a document, a passage, a range, a
      dictionary entry. A bare LANGUAGE CODE (chu, zle-ort — no colon) is a
      target too (P85): `nabu note chu "…"` files a PRIVATE per-language note
      that the `nabu language chu` card composes beneath the published overlay
      (it stays local/, never published — the urn:nabu:lang:<code> layer).
      Notes are canonical memory: they live as YAML files
      under canonical/local-notes/<topic>.yml (append-only through the
      Nabu::NoteShelf gateway; hand-edits welcome — the file is the record),
      and the catalog only indexes them (urn_notes, rebuilt at every
      sync/rebuild). Once noted, the urn's renders carry the note: `show`
      prints an "owner note (topic, date): …" footer (a document also counts
      its passage-note children), `define` prints entry notes after the
      body, `links` shows an owner-notes lane, and the MCP surface serves
      notes by default (withheld wherever the target document is withheld).

      Modes:
        nabu note URN "TEXT"    scripted append (TEXT may be several words)
        nabu note URN           existing notes? show them; none? prompt for
                                one (TTY only — a pipe without TEXT refuses
                                honestly BEFORE any write)
        nabu note --list        enumerate notes (bounded --limit; --topic
                                narrows)

      The urn must RESOLVE in the catalog — a note on a typo'd urn would sit
      unreachable forever, so a miss is an error naming it. --force records
      a note on a not-yet-held urn deliberately (notes on planned material);
      such notes read "(dangling)" at render until the urn arrives.

      --topic groups notes however you like (default "#{Nabu::NoteShelf::DEFAULT_TOPIC}";
      one file per topic); --tags rides a comma-separated tag list.

      Examples:
        nabu note urn:nabu:ccmh:mar:mt "Collate against Jagić 1883 before citing."
        nabu note urn:nabu:dict:lsj:logos "Anchor for the John 1.1 witness comparison." --topic lexicon
        nabu note urn:nabu:planned:vaillant --force "Order the reprint." --tags acquisitions
        nabu note urn:nabu:ccmh:mar:mt         # read what you said
        nabu note --list --topic lexicon
    HELP
    option :topic, type: :string, banner: "NAME",
                   desc: "Topic file under canonical/local-notes/ (default #{Nabu::NoteShelf::DEFAULT_TOPIC}; " \
                         "with --list: narrow to this topic)"
    option :tags, type: :string, banner: "collation,ocs", desc: "Tags, comma-separated"
    option :force, type: :boolean, default: false,
                   desc: "Record a note on a not-yet-held urn (flagged dangling at render)"
    option :list, type: :boolean, default: false,
                  desc: "Enumerate notes (bounded; --topic narrows, --limit lifts)"
    option :rm, type: :string, banner: "ID",
                desc: "Remove one note by its id (nabu note --list shows ids)"
    option :limit, type: :numeric, default: Nabu::Query::Notes::DEFAULT_LIMIT,
                   desc: "With --list: how many notes (default #{Nabu::Query::Notes::DEFAULT_LIMIT})"
    def note(urn = nil, *text_parts)
      config = Nabu::Config.load
      return note_list(config, urn) if options[:list]
      return note_remove(config, urn) if options[:rm]

      target = urn.to_s.strip
      raise Thor::Error, "note: give a urn or a language code (or --list)" if target.empty?

      # P85-A: a bare language code (chu, zle-ort — no colon) targets the
      # private language-note layer via its canonical pseudo-URN; anything
      # colon-bearing stays an ordinary corpus-URN note.
      code = Nabu::LanguageNote.code_for(target)
      urn = code ? Nabu::LanguageNote.urn(code) : target

      text = text_parts.join(" ").strip
      text = show_notes_or_prompt(config, urn) if text.empty?
      return if text.nil? # existing notes were shown — a read, not a write

      append_note(config, urn, text)
    rescue Nabu::Error => e
      raise Thor::Error, e.message
    end

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

    # Reading values shown on the `search --sign` header line before the
    # "… and N more" tail (P75 C-4, the same house render-cap rule).
    # const: a render cap, not a corpus census
    SIGN_SEARCH_VALUES_SHOWN = 12

    # RTL snippet highlight = SGR reverse video (P42-r4, strike 4 — the
    # matrix ruling on the owner's iTerm2). Every CHARACTER-based highlight
    # is at the mercy of the renderer's bidi treatment, and four attempts
    # measured four failure modes; a cell ATTRIBUTE rides the glyph wherever
    # reordering moves it and cannot be broken by any bidi algorithm.
    RTL_HIGHLIGHT_ON = "\e[7m"

    RTL_HIGHLIGHT_OFF = "\e[27m"

    # The no-silent-script-miss table (P27-2). A zero-hit query carrying
    # codepoints of a script NO fold neutralization covers gets ONE honest
    # hint naming what to try — the owner incident was exactly a silent
    # cross-script miss. Censused entries only: Glagolitic rides the OCS
    # dictionary shelf as variant forms (never passage text), and the
    # Gothic corpora are romanized (conventions §9). Devanagari and
    # Cyrillic do NOT hint — their neutralizations already fold them.
    SCRIPT_MISS_HINTS = {
      "Glagolitic" => [0x2C00..0x2C5F,
                       "no cross-script fold is registered for Glagolitic — the Slavic shelves " \
                       "index Cyrillic and Latin-diplomatic spellings (try въста or vъsta)"],
      "Gothic-script" => [0x10330..0x1034F,
                          "no cross-script fold is registered for Gothic script — the Gothic " \
                          "corpora are romanized (try guþ, jah)"]
    }.freeze

    # H9 (P35-6): the skip-with-note rule for a corrupt annotations_json —
    # Show marks the parse failure (ANNOTATIONS_UNREADABLE) and every
    # render that would have used the lane says so.
    ANNOTATIONS_UNREADABLE_NOTE = "stored annotations are unreadable (invalid JSON) — skipped"

    no_commands do
      # Render a SNIPPET — StoredSnippet output with the match in [brackets] —
      # for the terminal (P42-r4, four strikes deep). Square brackets inside
      # RTL text are unrenderable-portably: they are a bidi-mirrored pair,
      # and each character-based fix failed a different way on the owner's
      # iTerm2 (mirrorless reversal showed ]word[; brackets cut OUT of the
      # isolate were swept into the reversed segment anyway; the symmetric ‖
      # detached at passage-edge matches; RLM gluing was ignored — invisible
      # bidi controls do not extend that renderer's runs, though a VISIBLE
      # strong-R paseq does, matrix line 8). The ruling fix highlights with
      # a cell ATTRIBUTE instead of characters: SGR reverse video rides the
      # glyph wherever reordering moves it and no bidi algorithm can touch
      # it (matrix line 9 on the owner's screen). Gated by color_output?
      # (mode + NO_COLOR/NABU_COLOR/tty): piped or colorless output keeps
      # the logical [brackets] — no renderer, no bidi, and the documented
      # grep/MCP contract stays byte-identical. ANSI escapes are ASCII —
      # untouched by mark strips and NFC round-trips (the painted-tokens
      # precedent). Only PAIRED brackets convert (a stored lone Leiden
      # bracket stays literal); a stored [...] lacuna pair colors like a
      # match — the same ambiguity the bracket convention always had.
      def display_snippet(text, language)
        unless Nabu::Display.isolates?(language: language.to_s, mode: display_mode,
                                       policies: display_policies) && color_output?
          return display_text(text, language)
        end

        marked = text.to_s.gsub(/\[([^\[\]]*)\]/) { "#{RTL_HIGHLIGHT_ON}#{Regexp.last_match(1)}#{RTL_HIGHLIGHT_OFF}" }
        display_text(marked, language)
      end

      # Per-token language coloring (P27-2): the single-passage show view —
      # the one render where the stored P7-5 tokens annotation is at hand —
      # colorizes tokens tagged with a language OTHER than the passage's own
      # (corph's Latin glosses in Old Irish, OSHB's Aramaic verses). Gated
      # three ways: the mode's #colors? (mono/full say no), NO_COLOR /
      # NABU_COLOR / tty (Display.color?), and the honest-tagging rule
      # (untagged and base-language tokens stay uncolored). Painting wraps
      # PRISTINE token forms before the display transform — ANSI escapes are
      # ASCII, untouched by mark-class strips and NFC round-trips.
      def painted_passage_text(passage)
        return passage.text unless color_output?

        tokens = passage.annotations["tokens"]
        return passage.text unless tokens.is_a?(Array)

        painted, legend = Nabu::Display::TokenColors.paint(passage.text, tokens: tokens,
                                                                         language: passage.language)
        return passage.text if legend.empty?

        display_applied << "token colors: #{legend.map { |lang, color| "#{lang}=#{color}" }.join(' ')}"
        painted
      end

      def color_output?
        mode = display_mode
        (!mode.respond_to?(:colors?) || mode.colors?) && Nabu::Display.color?(tty: $stdout.tty?)
      end

      # Reject an unknown --license up front (before opening any db) with the
      # closed enum of valid classes, so the user sees the choices. Shared by
      # search and export.
      def validate_license!(license)
        return if license.nil?
        return if Nabu::SourceManifest::LICENSE_CLASSES.include?(license)

        raise Thor::Error,
              "unknown license #{license.inspect} " \
              "(choose from #{Nabu::SourceManifest::LICENSE_CLASSES.join(', ')})"
      end

      # Resolve --century (a whole century's bounds) OR --from/--to into a
      # [from, to] signed-historical-year window (P15-2). The reviewed guards:
      # no year 0 (1 BCE = -1, 1 CE = +1), a clear F>T message (not a silent
      # empty result), and --century is mutually exclusive with --from/--to.
      def date_window
        if options[:century]
          if options[:from] || options[:to]
            raise Thor::Error, "date filter: --century is shorthand for --from/--to — use one or the other"
          end

          idx = options[:century].to_i
          raise Thor::Error, "date filter: there is no century 0 (1st c. CE is 1, 1st c. BCE is -1)" if idx.zero?

          return Nabu::Timeline.century_bounds(idx)
        end

        from = coerce_year(options[:from], "--from")
        to = coerce_year(options[:to], "--to")
        if from && to && from > to
          raise Thor::Error, "date filter: --from #{from} is after --to #{to} " \
                             "(BCE years are negative — 300 BCE is -300, so -300 comes before -30)"
        end
        [from, to]
      end

      # The parsed --date-basis class list (P122-1, Nabu::Query::DateBasis), or
      # nil. Validated up front — before any db opens — so an unknown class
      # exits 1 naming the known set, the validate_license! stance.
      def date_basis_filter
        Nabu::Query::DateBasis.parse(options[:date_basis])
      rescue Nabu::Error => e
        raise Thor::Error, "search: #{e.message}"
      end

      def coerce_year(value, flag)
        return nil if value.nil?

        year = value.to_i
        raise Thor::Error, "date filter: there is no year 0 (#{flag}); 1 BCE is -1, 1 CE is 1" if year.zero?

        year
      end

      # A date/place filter needs document_axes; a catalog that predates
      # migration 008 (never rebuilt) hasn't got it. Fail with a clear pointer
      # rather than a Sequel "no such table".
      def require_timeline!(catalog)
        return if catalog.table_exists?(:document_axes)

        raise Thor::Error, "no timeline (this catalog predates it) — run nabu rebuild"
      end

      # A facet filter needs document_facets (migration 009) — same honest
      # pointer as the timeline guard.
      def require_facets!(catalog)
        return if catalog.table_exists?(:document_facets)

        raise Thor::Error, "no facet table (this catalog predates it) — run nabu rebuild"
      end

      # The active facet filters as {facet name => pattern}, or nil when none
      # (P17-2): --type → genre, --province → province, --material → material;
      # each --facet NAME=PATTERN adds its name (a repeat of a name wins last).
      def facet_filters
        filters = {}
        filters["genre"] = options[:type] if options[:type]
        filters["kind"] = options[:kind] if options[:kind]
        filters["province"] = options[:province] if options[:province]
        filters["material"] = options[:material] if options[:material]
        filters.merge!(facet_specs(command: "search", example: "subject=왕실-%"))
        filters.empty? ? nil : filters
      end

      # The repeatable --facet NAME=PATTERN specs as {name => pattern} (a
      # repeat of a name wins last) — search's and define's shared parse.
      def facet_specs(command:, example:)
        Array(options[:facet]).to_h do |spec|
          name, pattern = spec.to_s.split("=", 2).map(&:strip)
          if name.to_s.empty? || pattern.to_s.empty?
            raise Thor::Error, "#{command}: --facet takes NAME=PATTERN (#{example}) — got #{spec.inspect}"
          end

          [name, pattern]
        end
      end

      # The active loans code (P34-2), or nil. No validation beyond the strip:
      # the code rides as a bound value (never SQL or a JSON path), so any
      # string is safe and an unattested one is an honest no-match. Needs no
      # rebuild guard either — annotations_json is initial schema.
      def loans_filter
        code = options[:loans].to_s.strip
        code.empty? ? nil : code
      end

      # The content-narrowing filters that make a TERM-LESS browse legal
      # (P42-6): a date window (--from/--to/--century), a provenance --place, a
      # genre facet (--type/--province/--material), or the --loans facet — each
      # narrows WHICH passages, not merely which shelf. --lang/--license/
      # --source/--axis select whole shelves and are deliberately NOT sufficient
      # alone: a term-less listing of a whole language (or license, or source,
      # or axis) is a corpus DUMP, not a browse. The character-structure filters
      # are already a legal term-less path and return earlier (char_structured_search).
      def content_narrowing_filters?
        options[:from] || options[:to] || options[:century] || options[:date_basis] || options[:place] ||
          facet_filters || loans_filter || options[:meter] || options[:meter_pattern] ||
          options[:lect] || options[:script] || options[:within]
      end

      # Parse --within LAT,LON,KM into three floats (P75 C-9); range
      # validation lives in Search#within_spec, the shared enforcement
      # point.
      def within_filter
        spec = options[:within]
        return nil if spec.nil?

        parts = spec.split(",").map(&:strip)
        values = parts.map { |part| Float(part, exception: false) }
        if parts.size != 3 || values.any?(&:nil?)
          raise Thor::Error, "search: --within takes LAT,LON,KM (59.86,17.64,50) — got #{spec.inspect}"
        end

        values
      end

      # The refusal for a term-less `search` that carries no content-narrowing
      # filter — the old "give a query" message, extended (P42-6) to say exactly
      # what WOULD make a term-less browse legal, and why the shelf-selectors do not.
      def browse_refusal_message
        "search: give a query — or a content-narrowing filter to browse the corpus " \
          "term-less: a date window (--from/--to/--century), --date-basis, --place, a facet " \
          "(--type/--province/--material/--facet), --loans, --meter/--meter-pattern, --lect, --script, " \
          "or --within. " \
          "--lang/--license/--source/--axis " \
          "select whole shelves and cannot stand alone (that would dump the shelf, not browse it)."
      end

      # Term-less filtered browse (P42-6): a legal empty-query `search` — one
      # content-narrowing filter present — lists the corpus in corpus order
      # (Search#browse: passages.id ascending, no ranking) under the standard
      # filters and rendering. Reached only from #search on an empty query, and
      # only after the char/fuzzy/near/lemma paths have returned, so the sole
      # residual flags are the plain path's own; --exact/--word have no term to
      # match here and are refused rather than silently ignored.
      def browse_search
        if options[:exact] || options[:word]
          raise Thor::Error, "search: --exact/--word are glyph/word post-filters over a query term — " \
                             "they cannot run a term-less browse (drop them, or add a query)"
        end
        raise Thor::Error, browse_refusal_message unless content_narrowing_filters?

        validate_license!(options[:license])
        from, to = date_window
        place = options[:place]
        facets = facet_filters
        loans = loans_filter
        config = Nabu::Config.load
        catalog = open_catalog(config)
        fulltext = open_fulltext(config)
        raise Thor::Error, "no index — run nabu sync or nabu rebuild" unless catalog && fulltext

        require_timeline!(catalog) if from || to || place || options[:date_basis]
        require_facets!(catalog) if facets
        validate_source!(catalog, options[:source])
        axis_names, axis_slugs = axis_membership(command: "search", config: config)
        lects = require_lects!(config, options[:lect])

        searcher = Nabu::Query::Search.new(catalog: catalog, fulltext: fulltext, lects: lects || :auto,
                                           places: Nabu::Places.load_default(canonical_dir: config.canonical_dir))
        results = searcher.browse(lang: options[:lang], license: options[:license],
                                  limit: options[:limit].to_i, from: from, to: to, place: place,
                                  date_basis: date_basis_filter,
                                  facets: facets, source: options[:source], sources: axis_slugs,
                                  loans: loans, meter: options[:meter],
                                  meter_pattern: options[:meter_pattern], lect: options[:lect],
                                  script: options[:script], within: within_filter)
        print_search_results(results, facets: facets, query: "", loans: loans, axis: axis_names,
                                      browse: true, from: from, to: to, place: place,
                                      within: options[:within],
                                      meter_note: searcher.meter_note, place_note: searcher.place_note)
        print_display_footer
      rescue Nabu::Error => e
        raise Thor::Error, e.message
      ensure
        catalog&.disconnect
        fulltext&.disconnect
      end

      # search --sign (P75 C-4, the inverse of `nabu signs`): resolve one
      # cuneiform sign — glyph, OSL name/alias, or an UNAMBIGUOUS reading
      # value — and serve the standard filtered page over an FTS OR of the
      # sign's reading values (Query::Search#run_sign). --sign IS the
      # query: a term alongside it, or a text-mode modifier, is refused.
      def sign_search(query)
        term = options[:sign]
        unless query.to_s.strip.empty?
          raise Thor::Error, "search: --sign is itself the query — drop the term (#{query.inspect})"
        end

        %i[fuzzy near lemma exact word words meter meter_pattern scan].each do |flag|
          next unless options[flag]

          raise Thor::Error, "search: --sign does not compose with --#{flag.to_s.tr('_', '-')} " \
                             "(the page is an OR over the sign's reading values)"
        end

        validate_license!(options[:license])
        from, to = date_window
        facets = facet_filters
        loans = loans_filter
        config = Nabu::Config.load
        list = Nabu::SignList.load_default(config: config)
        raise Thor::Error, "search: --sign needs the Oracc Sign List — run `nabu sync osl`" if list.nil?

        record = resolve_search_sign(list, term)
        values = record.values.map(&:value).uniq
        raise Thor::Error, "search: sign #{record.name} carries no reading values" if values.empty?

        catalog = open_catalog(config)
        fulltext = open_fulltext(config)
        raise Thor::Error, "no index — run nabu sync or nabu rebuild" unless catalog && fulltext

        require_timeline!(catalog) if from || to || options[:place] || options[:date_basis]
        require_facets!(catalog) if facets
        validate_source!(catalog, options[:source])
        axis_names, axis_slugs = axis_membership(command: "search", config: config)
        lects = require_lects!(config, options[:lect])

        searcher = Nabu::Query::Search.new(catalog: catalog, fulltext: fulltext, lects: lects || :auto,
                                           places: Nabu::Places.load_default(canonical_dir: config.canonical_dir))
        results = searcher.run_sign(values, lang: options[:lang], license: options[:license],
                                            limit: options[:limit].to_i, from: from, to: to,
                                            date_basis: date_basis_filter,
                                            place: options[:place], facets: facets,
                                            source: options[:source], sources: axis_slugs,
                                            loans: loans, lect: options[:lect], script: options[:script])
        print_sign_search_header(record, values)
        print_search_results(results, facets: facets, query: values.first, loans: loans, axis: axis_names,
                                      incomplete: searcher.incomplete_hint, rank_note: searcher.rank_note,
                                      place_note: searcher.place_note)
        print_display_footer
      rescue Nabu::Error => e
        raise Thor::Error, e.message
      ensure
        catalog&.disconnect
        fulltext&.disconnect
      end

      # search --scan (P75 C-10, owner-ruled): the filter-first MODE —
      # distinct from plain search by contract, not a fallback it silently
      # becomes. Needs a term (else browse already serves corpus order) AND
      # at least one filter (else plain search already serves the page).
      def scan_search(query)
        %i[fuzzy near lemma exact word words].each do |flag|
          next unless options[flag]

          raise Thor::Error, "search: --scan does not compose with --#{flag} (one mode at a time)"
        end
        if query.to_s.strip.empty?
          raise Thor::Error, "search: --scan needs a query term (a term-less filtered walk is " \
                             "plain browse — drop --scan)"
        end
        unless content_narrowing_filters? || options[:lang] || options[:source] || options[:axis]
          raise Thor::Error, "search: --scan is the filter-first mode — give a filter " \
                             "(--place/--from/--lect/--script/--lang/--source/…); an unfiltered " \
                             "term is plain search's job"
        end

        validate_license!(options[:license])
        from, to = date_window
        facets = facet_filters
        loans = loans_filter
        config = Nabu::Config.load
        catalog = open_catalog(config)
        fulltext = open_fulltext(config)
        raise Thor::Error, "no index — run nabu sync or nabu rebuild" unless catalog && fulltext

        require_timeline!(catalog) if from || to || options[:place] || options[:date_basis]
        require_facets!(catalog) if facets
        validate_source!(catalog, options[:source])
        axis_names, axis_slugs = axis_membership(command: "search", config: config)
        lects = require_lects!(config, options[:lect])

        searcher = Nabu::Query::Search.new(catalog: catalog, fulltext: fulltext, lects: lects || :auto,
                                           places: Nabu::Places.load_default(canonical_dir: config.canonical_dir))
        results = searcher.run_scan(query, lang: options[:lang], license: options[:license],
                                           limit: options[:limit].to_i, from: from, to: to,
                                           date_basis: date_basis_filter,
                                           place: options[:place], facets: facets,
                                           source: options[:source], sources: axis_slugs,
                                           loans: loans, meter: options[:meter],
                                           meter_pattern: options[:meter_pattern],
                                           lect: options[:lect], script: options[:script],
                                           within: within_filter)
        print_search_results(results, facets: facets, query: query, loans: loans, axis: axis_names,
                                      incomplete: searcher.incomplete_hint,
                                      rank_note: searcher.rank_note,
                                      meter_note: searcher.meter_note,
                                      place_note: searcher.place_note)
        print_display_footer
      rescue Nabu::Error => e
        raise Thor::Error, e.message
      ensure
        catalog&.disconnect
        fulltext&.disconnect
      end

      # Glyph first, then OSL name/alias/form, then a reading VALUE when it
      # names exactly one sign (ambiguity lists the candidates, never picks
      # one silently — the sign-card rule).
      def resolve_search_sign(list, term)
        record = list.sign_for_glyph(term) || list.sign(term)
        return record if record

        candidates = list.lookup(term)
        return candidates.first if candidates.size == 1

        if candidates.size > 1
          raise Thor::Error, "search: value #{term.inspect} is ambiguous across " \
                             "#{candidates.map(&:name).join(' · ')} — give the sign name or glyph"
        end
        raise Thor::Error, "search: no OSL sign resolves #{term.inspect} " \
                           "(give a glyph 𒀝, a name AK / |ŠEŠ.AB|, or a reading value)"
      end

      def print_sign_search_header(record, values)
        shown = values.first(SIGN_SEARCH_VALUES_SHOWN)
        extra = values.size - shown.size
        list = shown.join(" ")
        list += " … and #{extra} more" if extra.positive?
        say "sign: #{[record.ucun, record.name].compact.join('  ')} — " \
            "#{values.size} reading #{values.size == 1 ? 'value' : 'values'}: #{list}"
      end

      # --source SLUG (P22-1, search/export): reject an unknown slug up front,
      # naming the valid slugs (the define-miss pattern). Validated against
      # the CATALOG — what is held is what can be filtered.
      def validate_source!(catalog, slug)
        return if slug.nil?
        return if catalog[:sources].where(slug: slug).any?

        known = catalog[:sources].order(:slug).select_map(:slug)
        raise Thor::Error, "unknown source #{slug.inspect} — the catalog holds: #{known.join(', ')}"
      end

      # P57-4: --lect needs the nabu-lects module. nil when +lect+ was not
      # given (no load attempted); the loaded Nabu::Lects when it was and
      # the module is synced; a clean Thor::Error naming the module
      # otherwise (the CLI half of Search's own Nabu::Error guard).
      def require_lects!(config, lect)
        return nil unless lect

        lects = Nabu::Lects.load_default(config: config)
        raise Thor::Error, "search: --lect needs the nabu-lects module — nabu-lects module not synced" unless lects

        lects
      end

      # --axis NAME[,NAME…] (P37-8, search/export): resolve the named research
      # axes to the union of their member slugs — the membership filter, the
      # multi-source generalization of --source. Returns [axis names in the
      # order asked, member slugs] or nil when --axis is absent. An unknown
      # axis is refused naming the known set (the P35-1 resolution guarantee),
      # and an empty registry says so; the slug/axis collision guarantee makes
      # a bare name unambiguous.
      def axis_membership(command:, config:)
        spec = options[:axis].to_s.strip
        return nil if spec.empty?

        registry = Nabu::SourceRegistry.load(config.sources_path)
        axes = registry.axes
        raise Thor::Error, "#{command}: no research axes are defined (config/axes.yml)" if axes.empty?

        names = spec.split(",").map(&:strip).reject(&:empty?).uniq
        names.each do |name|
          next if registry.functional_set?(name)

          axes[name] ||
            raise(Thor::Error, "#{command}: unknown axis #{name.inspect} — known axes: " \
                               "#{axes.names.join(', ')} · functional sets: " \
                               "#{Nabu::SourceRegistry::FUNCTIONAL_SETS.join(', ')}")
        end
        slugs = names.flat_map do |name|
          registry.functional_set?(name) ? registry.functional_set_members(name) : registry.axis_members(name)
        end
        [names, slugs.uniq]
      end

      # `show --random` (P11-9): N random visible passages, each in the standard
      # passage layout — the eyeball ritual at a source flip. A urn alongside
      # --random is contradictory (it picks passages for you); an empty result
      # is an honest note, not an error.
      def show_random(catalog, urn, config)
        raise Thor::Error, "show: --random takes no urn (it picks passages for you)" unless urn.empty?
        return show_random_parallel(catalog, config) if options[:parallel]

        results = Nabu::Query::Random.new(catalog: catalog)
                                     .run(source: options[:source], lang: options[:lang], count: options[:count].to_i)
        if results.empty?
          scope = +""
          scope << " in source #{options[:source]}" if options[:source]
          scope << " in #{options[:lang]}" if options[:lang]
          return say("no passages to show#{scope} (nothing visible — the corpus may be empty or all withdrawn)")
        end

        results.each_with_index do |result, index|
          say "" if index.positive?
          print_show_passage(result)
        end
      end

      # P47-r1 (owner: "elephantine is perfect for --parallel showcase!"):
      # --random composes with --parallel — draw ORIGINALS (the sampler
      # already excludes translation siblings) until one carries a parallel
      # in the requested language, render the paired view; a scope that
      # yields none in the attempt budget (12 draws per requested passage —
      # a retry bound, not a corpus claim) says so honestly.
      def show_random_parallel(catalog, config)
        random = Nabu::Query::Random.new(catalog: catalog)
        journal = Nabu::Store::LinksJournal.open_readonly(config.links_path)
        parallel = Nabu::Query::Parallel.new(catalog: catalog, journal: journal)
        wanted = options[:count].to_i.clamp(1, Nabu::Query::Random::MAX_COUNT)
        shown = []
        attempts = 0
        while shown.size < wanted && attempts < wanted * 12
          attempts += 1
          draw = random.run(source: options[:source], lang: options[:lang], count: 1).first
          break if draw.nil?
          next if shown.include?(draw.urn)

          # A draw whose translation edge cannot serve the requested lang is
          # simply not a parallel-bearing draw (P48-r2) — keep drawing.
          pair = begin
            parallel.run(draw.urn, lang: options[:parallel])
          rescue Nabu::Query::Parallel::TranslationMismatch
            nil
          end
          next if pair.nil? || pair.right.nil?

          say "" unless shown.empty?
          print_parallel(pair)
          shown << draw.urn
        end
        return unless shown.empty?

        scope = options[:source] ? " in source #{options[:source]}" : ""
        say "no parallel-bearing draw#{scope} after #{attempts} attempts — the scope may hold no " \
            "#{options[:parallel]} siblings (`show <urn> --parallel` pairs a known document; " \
            "`show --random` alone draws unpaired)"
      ensure
        journal&.disconnect
      end

      # Render `show`: a passage in the context of its document, or a document
      # header plus its passages in sequence. Withdrawn items ARE shown, tagged.
      def print_show(result)
        case result
        when Nabu::Query::Show::PassageResult then print_show_passage(result)
        when Nabu::Query::Show::DocumentResult then print_show_document(result)
        when Nabu::Query::Show::RangeResult then print_show_range(result)
        when Nabu::Query::Define::Result then print_define_entry(result)
        end
      end

      # `show --segmented` (P54-2): the result with every passage text
      # word-broken through Query::Show#segmented_text — a copy, so every
      # existing print path renders unchanged (tokens verbatim, spaces at
      # word boundaries). Only reached when the segmentation note is nil
      # (a Tibetan row with the nabu-data dataset synced).
      def segmented_show_result(query, result)
        case result
        when Nabu::Query::Show::PassageResult
          result.with(text: query.segmented_text(result.text))
        when Nabu::Query::Show::DocumentResult, Nabu::Query::Show::RangeResult
          result.with(passages: result.passages.map { |line| line.with(text: query.segmented_text(line.text)) })
        else
          result
        end
      end

      # The source-level credit line (P43-2, the grant's "clearly indicated
      # wherever displayed" duty), shown only when the source carries one — a
      # nil/blank credit (every ordinary source) prints nothing.
      def print_credit(result)
        credit = result.credit.to_s.strip
        say "  credit: #{credit}" unless credit.empty?
      end

      # P44-7: the meter line — shown only when the passage carries a scansion
      # enrichment (pedecerto over held Perseus-Latin verse), byte-identical
      # absence otherwise. "meter: H DSDS (pedecerto)": metrical code, foot
      # pattern (omitted when empty), producer.
      def print_meter(passage)
        meter = passage.meter
        return if meter.nil?

        pattern = meter.pattern.to_s.strip
        code = [meter.meter.to_s.strip, pattern].reject(&:empty?).join(" ")
        say "  meter: #{code} (#{meter.producer})"
      end

      # P44-2: the findspot line — shown only when the document's parse-
      # captured Pleiades id resolves through the local gazetteer dump
      # (title + place types; maps and coordinate math are out by design).
      # Absent dump, absent id, unknown id: no line, byte-identical output.
      def print_findspot(result)
        spot = result.findspot
        return if spot.nil?

        if spot.id.nil?
          # P69-1: the coordinates findspot — the source's own WGS84 pair,
          # no gazetteer (rundata's SRDB columns).
          pair = format("%<lat>.5f, %<lon>.5f", lat: spot.lat, lon: spot.lon)
          say "  findspot: #{[spot.title, pair].compact.join(' — ')}"
          return
        end
        types = spot.place_types.empty? ? "" : " (#{spot.place_types.join(' · ')})"
        say "  findspot: #{spot.title} — Pleiades #{spot.id}#{types}"
      end

      # P61-3 (D60-b): the artifact-script line — only where the original
      # artifact's script DIFFERS from the held surface (the lane is minted
      # on difference by construction). Tag + config note, honest and short.
      # P76 U-7: the upstream script_uncertain flag glosses "(script
      # uncertain)" — on the artifact line when one exists, else on its own
      # honest line (the flag can ride documents outside the differs-only
      # lane).
      def print_artifact(result)
        artifact = result.artifact
        return if artifact.nil?

        if artifact.script
          note = artifact.note ? " — #{artifact.note}" : ""
          flag = artifact.uncertain ? " (script uncertain)" : ""
          say "  artifact script: #{artifact.script}#{note}#{flag} (held surface differs; see the lect ~axis)"
        elsif artifact.uncertain
          say "  script: (script uncertain — upstream flag)"
        end
      end

      def print_show_passage(passage)
        say "#{passage.urn}#{" [#{passage.language}]" if passage.language}#{withdrawn_tag(passage.withdrawn)}"
        say "  #{display_text(painted_passage_text(passage), passage.language,
                              source: passage.source_slug, annotations: passage.annotations)}"
        say "  document: #{passage.document_urn}#{" — #{passage.document_title}" if passage.document_title}"
        say "  source: #{passage.source_slug}   license: #{passage.license_class}   " \
            "sequence: #{passage.sequence}   revision: #{passage.revision}"
        print_credit(passage)
        print_lect(passage)
        print_timeline(passage.timeline)
        print_findspot(passage)
        print_meter(passage)
        # H9 (P35-6): a corrupt annotation lane announces itself instead of
        # posing as an unannotated passage.
        say "  note: #{ANNOTATIONS_UNREADABLE_NOTE}" if annotations_unreadable?(passage)
        return if passage.provenance.empty?

        say "  provenance:"
        passage.provenance.each do |event|
          # P112-2: an implicit "loaded" (no per-passage breadcrumb) may
          # carry no timestamp at all — render the event without one.
          stamp = event.at ? "#{event.at}  " : ""
          say "    #{stamp}#{event.event}#{"  #{event.tool}" if event.tool}"
        end
      end

      # `show URN --tokens` (P35-6, the journaled gate find): the honest RAW
      # view of the stored token annotations — one line per token, `form`
      # first, then EVERY other key exactly as stored (lemma/gloss/osm/lang/
      # …, nested values as compact JSON). No display transforms, no
      # invention; a passage without tokens, and a non-passage grain, both
      # say so instead of rendering nothing.
      def print_show_tokens(result)
        unless result.is_a?(Nabu::Query::Show::PassageResult)
          return say "--tokens renders at passage grain — give a passage urn"
        end
        return say ANNOTATIONS_UNREADABLE_NOTE if annotations_unreadable?(result)

        tokens = result.annotations["tokens"]
        tokens = tokens.is_a?(Array) ? tokens.grep(Hash) : []
        return say "no token annotations stored for this passage" if tokens.empty?

        say "tokens (#{tokens.size}):"
        tokens.each { |token| say "  #{token_line(token)}" }
      end

      # One token as `form=… key=…` pairs, form first, stored key order after,
      # non-scalar values as compact JSON — verbatim, never interpreted.
      def token_line(token)
        keys = (["form"] + token.keys).uniq.select { |key| token.key?(key) }
        keys.map do |key|
          value = token[key]
          "#{key}=#{value.is_a?(String) ? value : JSON.generate(value)}"
        end.join("  ")
      end

      def annotations_unreadable?(result)
        result.annotations[Nabu::Query::Show::ANNOTATIONS_UNREADABLE] == true
      end

      def print_unreadable_annotations_count(lines)
        count = lines.count { |line| annotations_unreadable?(line) }
        return unless count.positive?

        say "  note: #{count} #{count == 1 ? 'passage carries' : 'passages carry'} " \
            "unreadable stored annotations (invalid JSON) — skipped"
      end

      def print_show_document(document)
        title = document.title ? " — #{document.title}" : ""
        lang = document.language ? " [#{document.language}]" : ""
        say "#{document.urn}#{title}#{lang}" \
            "#{withdrawn_tag(document.withdrawn, reason: document.withdrawn_reason,
                                                 at: document.withdrawn_at)}#{retired_tag(document)}"
        say "  source: #{document.source_slug}   license: #{document.license_class}   revision: #{document.revision}"
        print_credit(document)
        print_timeline(document.timeline)
        print_findspot(document)
        print_artifact(document)
        print_facets(document.facets, language: document.language)
        say "  passages (#{document.passages.size}):"
        document.passages.each do |line|
          say "    #{passage_label(document, line)}#{withdrawn_tag(line.withdrawn)}  " \
              "#{display_text(line.text, document.language,
                              source: document.source_slug, annotations: line.annotations)}"
        end
        print_unreadable_annotations_count(document.passages)
      end

      # Render a range (P7-6): the document header like a document listing, an
      # honest "[N of M passages]" note plus the two endpoint urns, then the
      # inclusive slice as :suffixes (--full-urn restores absolute urns).
      def print_show_range(range)
        title = range.title ? " — #{range.title}" : ""
        lang = range.language ? " [#{range.language}]" : ""
        say "#{range.urn}#{title}#{lang}#{withdrawn_tag(range.withdrawn)}#{retired_tag(range)}"
        say "  source: #{range.source_slug}   license: #{range.license_class}   revision: #{range.revision}"
        print_credit(range)
        print_timeline(range.timeline)
        say "  range: #{range.start_urn} … #{range.end_urn}  " \
            "[#{range.passages.size} of #{range.total} passages]"
        range.passages.each do |line|
          say "    #{passage_label(range, line)}#{withdrawn_tag(line.withdrawn)}  " \
              "#{display_text(line.text, range.language,
                              source: range.source_slug, annotations: line.annotations)}"
        end
        print_unreadable_annotations_count(range.passages)
      end

      # P81 U-5: the lect line — only when the document carries a
      # materialized lect facet row ("no row means identity", P58-4; a
      # bare-code passage prints nothing). The resolution's provenance
      # basis rides in parentheses; where the ruling behind the basis
      # STATES a tier (the rule's tier:, the override row's tier:) the
      # parenthetical glosses through Certainty's :lect_tier carrier
      # instead — certain stays provenance-only ink, deviation is labeled:
      # "lect: arc:mid (probable — rule sefaria-arc-subshelf, approximation)".
      def print_lect(passage)
        return unless passage.lect

        say "  lect: #{passage.lect}#{lect_facet_note(passage.lect_basis, code: passage.language)}"
      end

      # " (<gloss>)" when the basis's ruling states a tier, " (<basis>)"
      # as bare provenance otherwise, "" for a basis-less row (materialized
      # before the P81 basis lane) — shared by the passage lect line and
      # the document facets line.
      def lect_facet_note(basis, code:)
        return "" unless basis

        gloss = Nabu::LectGloss.gloss(basis, code: code, rules: cli_lect_rules,
                                             override_tiers: cli_lect_override_tiers)
        " (#{gloss || basis})"
      end

      # The config-stated tier carriers, memoized per command run (both are
      # small YAML reads; nil rules = no rules file, an honest untiered
      # render).
      def cli_lect_rules
        return @cli_lect_rules if defined?(@cli_lect_rules)

        @cli_lect_rules = Nabu::LectRules.load(Nabu::Config.load.lect_facet_rules_paths)
      end

      def cli_lect_override_tiers
        return @cli_lect_override_tiers if defined?(@cli_lect_override_tiers)

        @cli_lect_override_tiers = Nabu::Lects.override_tiers(Nabu::Config.load.lect_overrides_paths)
      end

      # The timeline line (P15-2), when the document has one. A date span
      # ("113 BCE", "501–700 CE", "≤ 257 BCE") with the informative precision
      # ("low"/"high", not the derived exact/range/year) and the provenance
      # place; place-only rows print as "place:". Undated documents print
      # nothing (an absence, never an error).
      def print_timeline(timeline)
        return if timeline.nil?

        span = Nabu::Timeline.format_span(timeline.not_before, timeline.not_after)
        place = timeline.place_name ? " · #{timeline.place_name}#{place_query_gloss(timeline.place_name)}" : ""
        if span && timeline.date_class == Nabu::Store::SilverDates::DATE_CLASS
          # P122-1: an estimate is never dressed as an upstream date.
          say "  date: #{span} [silver — #{timeline.date_raw}]#{place}"
        elsif span
          say "  date: #{span}#{precision_note(timeline.precision)}#{place}"
        elsif timeline.place_name
          say "  place: #{timeline.place_name}#{place_query_gloss(timeline.place_name)}"
        end
      end

      # P76 U-2 (conventions §12): a genuinely graded precision word routes
      # through Certainty — house tier plus the upstream word verbatim
      # ('(uncertain — hgv "low")'); "high" is certain and SILENT; width
      # words beyond the always-silent exact/range/year keep their plain
      # informative note ("(period)") — width, not doubt.
      def precision_note(precision)
        return "" if %w[exact range year].include?(precision)

        gloss = Nabu::Certainty.gloss(:hgv_precision, precision)
        return " (#{gloss})" if gloss
        return "" if Nabu::Certainty.tier(:hgv_precision, precision) == "certain"

        " (#{precision})"
      end

      # The facets line (P17-2), one compact line and only when faceted:
      # "facets: genre=epitaph (titsep) · province=Latium et Campania …". The
      # raw code rides in parentheses when it differs from the value (the `?`
      # certainty stays visible). P81 U-5: the lect facet's raw is its
      # provenance basis — it renders through the tier gloss (or as the bare
      # basis) exactly like the passage card's lect line.
      def print_facets(facets, language: nil)
        return if facets.nil? || facets.empty?

        kind_rows, rest = facets.partition { |facet| facet.facet == "kind" }
        rendered = rest.map do |facet|
          if facet.facet == "lect"
            "lect=#{facet.value}#{lect_facet_note(facet.raw, code: language)}"
          else
            raw = facet.raw && facet.raw != facet.value ? " (#{facet.raw})" : ""
            "#{facet.facet}=#{facet.value}#{raw}"
          end
        end
        say "  facets: #{rendered.join(' · ')}" unless rest.empty?
        print_kind_line(kind_rows)
      end

      # The kind axis' card line (P99-3, owner-ruled 2026-09-13): every class the
      # document carries on ONE line, multi-label joined with " + ",
      # the upstream claim(s) visible verbatim. A declaration-born row
      # (raw nil — okhc's source_kind) shows no upstream tail.
      def print_kind_line(kind_rows)
        return if kind_rows.empty?

        classes = kind_rows.map(&:value).uniq.join(" + ")
        raws = kind_rows.map(&:raw).compact.uniq
        upstream = raws.empty? ? "" : " — upstream: #{raws.map(&:inspect).join(', ')}"
        say "  kind: #{classes}#{upstream}"
      end

      # Print practice: the document urn appears once in the header, each
      # passage line carries only its changing :suffix (":b2:5"). --full-urn
      # restores absolute urns (copy-paste into `show`/scripts). A passage
      # whose urn doesn't extend the document urn (never minted by our
      # adapters, but data is data) falls back to the full urn.
      def passage_label(document, line)
        return line.urn if options[:full_urn]

        suffix = line.urn.delete_prefix(document.urn)
        suffix == line.urn || suffix.empty? ? line.urn : suffix
      end

      # -- show --parallel (P7-4) ------------------------------------------

      # Resolve + align + render, with the honest failure modes: unknown urn
      # (exit 1, same message as plain show), no LANG sibling or translation
      # edge in the catalog (exit 1, names the language), and a translation
      # edge that cannot serve LANG (exit 1 via TranslationMismatch, naming
      # the language that would work). The links journal rides along
      # read-only so the P48-r2 kind=translation edges (Kangyur↔84000) pair
      # cross-source with no extra flag.
      def show_parallel(catalog, urn, lang, config)
        journal = Nabu::Store::LinksJournal.open_readonly(config.links_path)
        result = Nabu::Query::Parallel.new(catalog: catalog, journal: journal).run(urn, lang: lang)
        raise Thor::Error, "urn not found: #{urn}" if result.nil?
        if result.right.nil?
          raise Thor::Error, "no #{lang} parallel edition of this work in the catalog for #{urn} " \
                             "(--parallel pairs sibling CTS editions within one source, or " \
                             "cross-source over a kind=translation link edge; is " \
                             "`translations: true` set and the source resynced?)#{align_hint(urn, config)}"
        end

        print_parallel(result)
      ensure
        journal&.disconnect
      end

      # Cosmetic rider (P11-8): --parallel's "is translations: true set" hint is
      # misleading for a CROSS-source text (Vulgate/LXX/WEB have no sibling CTS
      # edition to pair). When the urn is a registered alignment witness, point
      # at `nabu align` instead — the hub built for exactly this.
      def align_hint(urn, config)
        registry = Nabu::AlignmentRegistry.load(config.alignments_path)
        witnessed = registry.works.any? do |work|
          work.witnesses.any? do |witness|
            witness.document_urns.any? { |doc| urn == doc || urn.start_with?("#{doc}:") }
          end
        end
        witnessed ? " — this text is an alignment-hub witness; try `nabu align REF` for cross-source alignment" : ""
      rescue Nabu::ValidationError
        ""
      end

      # Render the alignment (P8-1b span-grouped): both document headers, the
      # paired/blocks/one-sided counts, then one span-group at a time. A verse
      # pair keeps the compact pair form (byte-identical to pre-P8-1b); a coarse
      # block prints the original lines first, then the translation once with
      # its full coverage (and a clip note when a slice shows only part of it);
      # one-sided rows dash the missing side. Withdrawn passages are shown,
      # tagged (show-family).
      def print_parallel(result)
        say format_parallel_side(result.left)
        say "  parallel: #{format_parallel_side(result.right)}"
        say "  #{parallel_counts(result)}"
        width = [result.left.language.to_s.length, result.right.language.to_s.length].max + 2
        result.groups.each { |group| print_parallel_group(group, result, width) }
      end

      def print_parallel_group(group, result, width)
        case group.kind
        when :pair        then print_parallel_pair(group, result, width)
        when :block       then print_parallel_block(group, result, width)
        when :original    then print_parallel_one_sided(group, result, width, side: :left)
        when :translation then print_parallel_one_sided(group, result, width, side: :right)
        end
      end

      # Verse pair / one-sided rows: the pre-P8-1b two-line form, the suffix (or
      # absolute urn under --full-urn) over one line per language, "—" for the
      # absent side. Kept byte-identical so verse-for-verse output never shifts.
      def print_parallel_pair(group, result, width)
        line = group.originals.first
        say "  #{options[:full_urn] ? line.urn : group.anchor}"
        say "    #{parallel_line(result.left.language, line, width)}"
        say "    #{parallel_line(result.right.language, group.translation, width)}"
      end

      def print_parallel_one_sided(group, result, width, side:)
        present = side == :left ? group.originals.first : group.translation
        say "  #{options[:full_urn] ? present.urn : present.suffix}"
        left = side == :left ? present : nil
        right = side == :right ? present : nil
        say "    #{parallel_line(result.left.language, left, width)}"
        say "    #{parallel_line(result.right.language, right, width)}"
      end

      # Coarse block: each owned original as a suffix-labeled left line, then
      # the translation once, labeled with its full coverage in the original's
      # numbering plus a clip note when the shown slice is only part of it.
      def print_parallel_block(group, result, width)
        group.originals.each do |line|
          say "  #{options[:full_urn] ? line.urn : line.suffix}"
          say "    #{parallel_line(result.left.language, line, width)}"
        end
        say "  #{result.right.language} #{block_coverage(group)}"
        say "    #{display_text(group.translation.text, result.right.language)}" \
            "#{withdrawn_tag(group.translation.withdrawn)}"
      end

      # `[:1.1 — covers :1.1–:1.43; range shows :1.5–:1.10]` — the anchor, the
      # full ownership span, and (only when clipped) the shown sub-range.
      def block_coverage(group)
        covers = "covers #{group.covers_first}–#{group.covers_last}"
        clip = group.clipped ? "; range shows #{group.shown_first}–#{group.shown_last}" : ""
        "[#{group.anchor} — #{covers}#{clip}]"
      end

      def format_parallel_side(side)
        "#{side.urn}#{" — #{side.title}" if side.title}#{" [#{side.language}]" if side.language}"
      end

      # Honest grouped arithmetic: paired counts 1:1 verse pairs; the blocks
      # clause (and its owned-line total) appears only when there ARE coarse
      # blocks, so verse-for-verse output stays byte-identical to pre-P8-1b.
      def parallel_counts(result)
        paired = result.groups.count { |group| group.kind == :pair }
        blocks = result.groups.select { |group| group.kind == :block }
        left_only = result.groups.count { |group| group.kind == :original }
        right_only = result.groups.count { |group| group.kind == :translation }
        block_lines = blocks.sum { |group| group.originals.size }
        blocks_clause = blocks_clause(blocks.size, block_lines)
        "aligned by citation: #{paired} paired, #{blocks_clause}" \
          "#{left_only} #{result.left.language} only, #{right_only} #{result.right.language} only"
      end

      # The blocks clause appears only when there ARE coarse blocks, so
      # verse-for-verse output stays byte-identical to the pre-P8-1b header.
      def blocks_clause(blocks, lines)
        return "" if blocks.zero?

        "#{plural(blocks, 'block')} covering #{plural(lines, 'line')}, "
      end

      def parallel_line(language, line, width)
        label = language.to_s.ljust(width)
        return "#{label}—" if line.nil?

        "#{label}#{display_text(line.text, language)}#{withdrawn_tag(line.withdrawn)}"
      end

      # +reason:+/+at:+ (P93-2): the document card names WHY and WHEN it
      # left when the loader recorded it; a bare flag stays the honest
      # render for pre-P93 withdrawals and passage lines.
      def withdrawn_tag(withdrawn, reason: nil, at: nil)
        return "" unless withdrawn

        detail = [reason, at.respond_to?(:strftime) ? at.strftime("%Y-%m-%d") : at].compact.join(", ")
        detail.empty? ? "  (withdrawn)" : "  (withdrawn: #{detail})"
      end

      # P5-2: upstream scrapped the file; the attic kept it. Live, labeled.
      def retired_tag(document)
        document.retired_upstream ? "  (retired upstream)" : ""
      end

      # One hint line per unregistered script present in the zero-hit query;
      # silent (zero-signal) otherwise.
      def print_script_miss_hints(query)
        return if query.nil?

        SCRIPT_MISS_HINTS.each_value do |(range, hint)|
          say "note: #{hint}" if query.each_char.any? { |char| range.cover?(char.ord) }
        end
      end

      # Render hits: urn + optional [language] header, then the snippet. Every
      # path's snippet is a window of the STORED text (P39-r3/P40-w,
      # StoredSnippet) — text_normalized, the folded skeleton, is NEVER shown (it
      # rendered 学 as 學 and だ as た). +proximity: true+ marks the two-term NEAR
      # snippet (both terms bracketed, on the stored glyphs since P40-w); +exact+
      # / +word+ annotate the glyph-literal / whole-word filters, so the footer
      # labels each path truthfully. Active facet filters (P17-2) are named in
      # one compact footer line — and only then. +incomplete+ (P35-6): the query
      # layer's honesty hint (the exhausted-inner-window note, or the
      # --exact/--word scan-ceiling note) — printed whenever present, so a short
      # page never masquerades as a complete answer.
      def print_search_results(results, facets: nil, query: nil, loans: nil, axis: nil, incomplete: nil,
                               exact: false, word: false, proximity: false, rank_note: nil,
                               browse: false, from: nil, to: nil, place: nil, within: nil,
                               meter_note: nil, words_note: nil, place_note: nil)
        if results.empty?
          say "no matches"
          # Empty-under-filter honesty (P35): --exact/--word suppressed the folded
          # candidates, so a "no matches" here must name the filter it applied.
          if exact
            say "note: --exact matched glyph-literally (the default fold would also find " \
                "reform variants, e.g. 学↔學, 弁↔辨/瓣/辯)"
          end
          say "note: --word required a whole-word match (a fragment inside a longer word does not count)" if word
          # The P42-2 guard served a corpus-wide sample (P42-r3) — an empty
          # page over a degraded path says so too, never a clean-looking silence.
          say "note: #{rank_note}" if rank_note
          # The meter facet's honesty line (P45-5): an empty page under
          # --meter says what layer it filtered on — or that the layer is
          # empty / the code unknown — never a silent zero.
          say "note: #{meter_note}" if meter_note
          # The word-grain degrade note (P54-4): --words could not filter
          # (non-Tibetan query / unsynced module) — plain search served.
          say "note: #{words_note}" if words_note
          # The --place lane note (P75 C-1): which lane an empty page
          # filtered on — identity refs or the name-LIKE fallback.
          say "note: #{place_note}" if place_note
          say "note: #{incomplete}" if incomplete
          return print_script_miss_hints(query)
        end

        results.each do |result|
          say "#{result.urn}#{" [#{result.language}]" if result.language}"
          say "  #{display_snippet(result.snippet, result.language)}"
        end
        say "#{results.size} #{results.size == 1 ? 'hit' : 'hits'} " \
            "(#{search_snippet_label(exact: exact, word: word, proximity: proximity,
                                     rank_note: rank_note, browse: browse)})" \
            "#{browse_window_footer(from: from, to: to, place: place, within: within) if browse}" \
            "#{facet_footer(facets, loans: loans, axis: axis)}"
        say "note: #{meter_note}" if meter_note
        say "note: #{words_note}" if words_note
        say "note: #{place_note}" if place_note
        say "note: #{incomplete}" if incomplete
        print_search_credits(results)
      end

      # The credit duty on the search surface (P43-2): the DISTINCT source
      # credits among the hits just shown, one line each — so a hit's text and
      # the attribution its grant requires appear on the same page. Nothing when
      # no shown source carries a credit (every ordinary search).
      def print_search_credits(results)
        results.filter_map { |r| r.credit&.strip }.reject(&:empty?).uniq.each do |credit|
          say "credit: #{credit}"
        end
      end

      # The date/place clause of a term-less browse footer (P42-6), naming the
      # content filters that made the browse legal (facets/loans/axis are named
      # by facet_footer); empty when neither is active (compact-footer rule).
      def browse_window_footer(from:, to:, place:, within: nil)
        parts = []
        parts << "dates: #{browse_year_window(from, to)}" if from || to
        parts << "place: #{place}" if place
        parts << "within: #{within}" if within
        parts.empty? ? "" : " · #{parts.join(' · ')}"
      end

      # A signed-year window as a compact footer string: "-300..-30", "from
      # 500", or "to 100" (BCE years negative — the --from/--to grammar).
      def browse_year_window(from, to)
        return "#{from}..#{to}" if from && to
        return "from #{from}" if from

        "to #{to}"
      end

      # The footer clause naming what the snippet shows, per path. All three
      # paths now show the STORED text (P40-w carried proximity off the folded
      # index form); --exact / --word / proximity annotate what the match means.
      # +rank_note+ (P42-2, plain path only) appends the skipped-rank honesty
      # clause: "…; term too common to rank — corpus-wide sample".
      def search_snippet_label(exact:, word: false, proximity: false, rank_note: nil, browse: false)
        return "filtered browse — corpus order, no ranking" if browse
        return "both terms bracketed; snippet shows the text as stored" if proximity

        stored = "snippet shows the text as stored"
        # A filtered path (--exact and/or --word) leads with what the match means;
        # plain search leads with the stored-text promise, then "fold-aware".
        return ["#{stored}; matching is fold-aware", rank_note].compact.join("; ") unless exact || word

        mode = if exact && word then "glyph-exact, whole-word"
               elsif exact then "glyph-exact"
               else "whole-word, fold-aware"
               end
        "#{mode}; #{stored}"
      end

      # " · facets: genre=epitaph province=pannonia% · loans: grc · axis: celtic"
      # — empty when no facet/loans/axis filter is active (zero-signal silence,
      # the compact rule). The axis names the desk(s) the membership filter
      # scoped to (P37-8).
      def facet_footer(facets, loans: nil, axis: nil)
        parts = []
        parts << "facets: #{facets.map { |facet, pattern| "#{facet}=#{pattern}" }.join(' ')}" if facets&.any?
        parts << "loans: #{loans}" if loans
        # The meter facet (P45-5) names its active filter in the footer like
        # every other facet; the source-layer note is a separate line.
        parts << "meter: #{[options[:meter], options[:meter_pattern]].compact.join(' ')}" if
          options[:meter] || options[:meter_pattern]
        parts << "axis: #{Array(axis).join(',')}" if axis && !Array(axis).empty?
        parts.empty? ? "" : " · #{parts.join(' · ')}"
      end

      # Render fuzzy hits (P16-4): the search-hit shape (urn + [language],
      # then the folded snippet with the fragment in [brackets]; --long lifts
      # the snippet window, house rule), plus ONE scope line — the fuzzy
      # index is documentary-only, so every render names what it covers (the
      # honest answer when --lang grc "finds nothing" in the literary corpus).
      def print_fuzzy_results(results, scope:, long: false, facets: nil, loans: nil, axis: nil, incomplete: nil)
        if results.empty?
          say "no matches"
        else
          results.each do |result|
            say "#{result.urn}#{" [#{result.language}]" if result.language}"
            say "  #{display_snippet(long ? result.folded_marked : result.snippet, result.language)}"
          end
          say "#{results.size} #{results.size == 1 ? 'hit' : 'hits'} " \
              "(fuzzy substring; highlights are diacritic-folded)#{facet_footer(facets, loans: loans, axis: axis)}"
        end
        say "note: #{incomplete}" if incomplete
        covered = scope&.any? ? scope.join(", ") : "no sources (flag fuzzy_index: true in config/sources.yml)"
        say "fuzzy index covers: #{covered}"
      end

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

      # The `show` footer (P16-1): one "linked:" line, ONLY when the links
      # journal holds edges touching this urn — zero-signal silence otherwise
      # (no journal, no edges, nothing printed). Read-only, absent-file-safe.
      def print_linked_footer(config, urn)
        journal = Nabu::Store::LinkLayers.open_readonly(config)
        return if journal.nil?

        counts = Nabu::Store::LinksJournal.kind_counts(journal, urn)
        return if counts.empty?

        say "  linked: #{counts.sort_by { |kind, _| kind }.map { |kind, count| "#{count} #{kind}" }.join(', ')}"
      ensure
        journal&.disconnect
      end

      # -- nabu note (P24-1) -------------------------------------------------

      # The `show`/`define` notes footer: one "owner note (topic, date): …"
      # line per note on the urn, and — on a document — the passage-note
      # children count. Zero-signal silence when unnoted (the linked-footer
      # stance); a catalog predating migration 015 has no lane at all.
      def print_notes_footer(catalog, result)
        reader = Nabu::Query::Notes.new(catalog: catalog)
        return unless reader.available?

        reader.for_urn(result.urn).each do |row|
          say "  owner note (#{row.topic}, #{row.added}): #{row.note}#{note_tags_fragment(row)}"
        end
        return unless result.is_a?(Nabu::Query::Show::DocumentResult)

        children = reader.child_count(result.urn)
        say "  passage notes: #{children}" if children.positive?
      end

      def note_line(row)
        id = Nabu::NoteFile.record_id(topic: row.topic, urn: row.urn, added: row.added, note: row.note)
        "[#{id}] (#{row.topic}, #{row.added}) #{row.note}#{note_tags_fragment(row)}"
      end

      def note_tags_fragment(row)
        row.tags.empty? ? "" : "  [#{row.tags.join(', ')}]"
      end

      # `nabu note --list`: the bounded enumeration, oldest first, each urn
      # resolution-checked so a --force note on a not-yet-held urn reads
      # honestly dangling.
      # note --rm ID: one removal through the gateway, then the same
      # surgical derived refresh the append uses (file rewritten) or a
      # topic teardown (last note removed the file): rows + pin dropped.
      def note_remove(config, urn_arg)
        raise Thor::Error, "note: --rm takes no urn argument (--topic scopes the id search)" \
          unless urn_arg.to_s.strip.empty?

        shelf = Nabu::NoteShelf.new(dir: Nabu::NoteShelf.dir(config), resolver: nil)
        removal = shelf.remove_note!(id: options[:rm], topic: options[:topic])
        say "  removed  [#{options[:rm].strip.downcase}] #{removal.record.urn} — " \
            "#{removal.record.note[0, 60]}#{'…' if removal.record.note.length > 60}"
        if removal.file_deleted
          drop_note_topic(config, removal.topic, removal.path)
        else
          refresh_note_topic(config, removal.path)
        end
      end

      # The last note of a topic left the shelf: its derived rows and its
      # ledger pin go with the file (millisecond ops, the fast-path rule).
      def drop_note_topic(config, topic, path)
        catalog = open_catalog(config)
        begin
          catalog[:urn_notes].where(topic: topic).delete if catalog&.table_exists?(:urn_notes)
        ensure
          catalog&.disconnect
        end
        ledger = open_ledger(config)
        begin
          if ledger
            Nabu::Store::Pin.where(source_slug: Nabu::NoteShelf::SLUG,
                                   repo_url: "local:#{File.basename(path)}").delete
          end
        ensure
          ledger&.disconnect
        end
      end

      def note_list(config, urn_arg)
        raise Thor::Error, "note: --list takes no urn (--topic narrows, --limit lifts)" \
          unless urn_arg.to_s.strip.empty?

        catalog = open_catalog(config)
        raise Thor::Error, "no catalog — run nabu sync or nabu rebuild" unless catalog

        page = Nabu::Query::Notes.new(catalog: catalog).list(topic: options[:topic], limit: options[:limit].to_i)
        return say(%(no notes yet — nabu note URN "TEXT" writes the first)) if page.total.zero?

        resolved = Nabu::NoteShelf.catalog_resolver(catalog)
        page.rows.each do |row|
          say "#{row.urn}#{' (dangling)' unless resolved.call(row.urn)} — #{note_line(row)}"
        end
        remaining = page.total - page.rows.size
        say "… and #{remaining} more (--limit lifts, --topic narrows)" if remaining.positive?
      ensure
        catalog&.disconnect
      end

      # `nabu note URN` without TEXT: existing notes are SHOWN (a read —
      # works piped or not); a bare urn with none prompts on a TTY and
      # refuses honestly otherwise, BEFORE any write (the ingest precedent).
      # Returns the text to append, or nil when notes were shown.
      def show_notes_or_prompt(config, urn)
        existing = existing_notes(config, urn)
        unless existing.empty?
          say "notes on #{urn} (#{existing.size}):"
          existing.each { |row| say "  #{note_line(row)}" }
          say %(add another: nabu note #{urn} "TEXT" · remove one: nabu note --rm ID)
          return nil
        end
        unless $stdin.tty?
          raise Thor::Error, "note: no TEXT and no TTY to prompt — pass the note as an argument " \
                             "(nabu note URN \"TEXT\"); nothing was written"
        end

        # Plain $stdin.gets, NOT Thor's ask: Thor routes ask through
        # LineEditor::Readline when the readline ext exists (CI's Ruby 3.3
        # bundles it; homebrew 4.0 dropped it), and Readline reads the real
        # fd — invisible to the suite's $stdin double and to piped input.
        # One prompt, one line; the say keeps the ingest prompt furniture.
        say "  note for #{urn} (type it, Enter saves, ^C aborts):"
        answer = $stdin.gets.to_s.strip
        raise Thor::Error, "note: refusing an empty note — nothing was written" if answer.empty?

        answer
      end

      def existing_notes(config, urn)
        catalog = open_catalog(config)
        return [] unless catalog

        Nabu::Query::Notes.new(catalog: catalog).for_urn(urn, topic: options[:topic])
      ensure
        catalog&.disconnect
      end

      # The note-resolution seam (P85-A): a language pseudo-URN resolves when
      # the library actually knows the code (a held corpus language OR a
      # curated/census-named one) — so a note on a typo'd code refuses like a
      # note on a typo'd corpus URN; everything else defers to the standard
      # corpus-URN resolver.
      def note_resolver(catalog)
        return nil unless catalog

        base = Nabu::NoteShelf.catalog_resolver(catalog)
        languages = Nabu::Languages.new(catalog: catalog)
        lambda do |urn|
          code = Nabu::LanguageNote.code_of(urn)
          code ? known_language?(catalog, languages, code) : base.call(urn)
        end
      end

      def known_language?(catalog, languages, code)
        return true if languages.name(code)

        catalog.table_exists?(:documents) && !catalog[:documents].where(language: code).empty?
      end

      # The write path: resolution-checked append through the NoteShelf
      # gateway, then a SURGICAL derived refresh — parse the one topic file,
      # replace its urn_notes rows, upsert its ledger pin. NEVER the shelf's
      # ordinary sync: that path runs LocalFetch discovery plus the corpus
      # indexer, minutes of machinery for a one-line append (owner defect
      # 2026-07-18: "notes supposed to be lightning fast"). The full sync/
      # rebuild replays the same rows from the same file — consistency is by
      # construction, speed is the feature.
      def append_note(config, urn, text)
        resolved = true
        catalog = open_catalog(config)
        begin
          resolver = note_resolver(catalog)
          resolved = resolver ? resolver.call(urn) : false if options[:force]
          shelf = Nabu::NoteShelf.new(dir: Nabu::NoteShelf.dir(config), resolver: resolver)
          path = shelf.append_note!(urn: urn, note: text,
                                    topic: options[:topic] || Nabu::NoteShelf::DEFAULT_TOPIC,
                                    tags: (options[:tags] || "").split(","), force: options[:force])
          say "  noted    #{urn} → #{path}"
        ensure
          catalog&.disconnect
        end
        refresh_note_topic(config, path)
        unless resolved
          say "  note: #{urn} is not in the catalog yet — it reads (dangling) until the urn arrives", :yellow
        end
        say "try: bin/nabu show #{urn}" if resolved
      end

      # The fast-append derived refresh (P26 hotfix): one topic file parsed,
      # its urn_notes rows replaced, its per-file ledger pin upserted — the
      # exact rows a full sync would produce for this file, in milliseconds.
      # Other topics' pins are untouched (the sync-time set-reconcile stays
      # the full pipeline's job). Absent db/ledger degrade honestly: the
      # note is canonical either way and the next sync/rebuild indexes it.
      def refresh_note_topic(config, path)
        note_file = Nabu::NoteFile.load(path)
        catalog = open_catalog(config)
        if catalog
          begin
            Nabu::Store::NoteLoader.replace_for_topic!(catalog, note_file)
          ensure
            catalog.disconnect
          end
        else
          say "  (no catalog yet — the note indexes at the next sync/rebuild)"
        end
        ledger = open_ledger(config)
        return unless ledger

        begin
          key = "local:#{File.basename(path)}"
          sha = Digest::SHA256.file(path).hexdigest
          row = Nabu::Store::Pin.first(source_slug: Nabu::NoteShelf::SLUG, repo_url: key)
          if row
            row.update(last_sync_sha: sha)
          else
            Nabu::Store::Pin.create(
              source_slug: Nabu::NoteShelf::SLUG, repo_url: key, last_sync_sha: sha
            )
          end
        ensure
          ledger.disconnect
        end
      end

      # search --lemma FORM (P7-5): exact-lemma lookup over the treebank lemma
      # index. Replaces the FTS query (simplest honest v1 — combining both is
      # future work); composes with --lang/--license/--limit. A fulltext file
      # predating P7-5 lacks the lemma table, so that gets its own honest hint.
      # search --fuzzy FRAGMENT (P16-4): substring/fragment search over the
      # documentary trigram index (Query::Fuzzy — candidates, then verify).
      # Same open/close discipline as the sibling search paths; the trigram
      # table missing means the fulltext index predates P16-4, an honest
      # reindex hint, exactly the lemma-index precedent.
      def char_filter_options?
        options[:radical] || options[:strokes] || options[:char_component]
      end

      # --strokes N or A-B → an inclusive [low, high] range, or nil.
      def parse_strokes_option
        raw = options[:strokes]&.strip or return nil
        if (m = raw.match(/\A(\d+)\z/))
          [m[1].to_i, m[1].to_i]
        elsif (m = raw.match(/\A(\d+)-(\d+)\z/))
          [m[1].to_i, m[2].to_i].minmax
        else
          raise Thor::Error, "search: --strokes takes N or A-B (e.g. --strokes 8 or --strokes 8-12)"
        end
      end

      # The graded-reading search (P72-1, Edubba FR-1): --charset coverage
      # over the P72 passage_chars index — quasi-instant by construction
      # (indexed rarest-char candidates + exact verify), honest hint when
      # the index predates P72.
      def graded_search(query)
        validate_license!(options[:license])
        config = Nabu::Config.load
        catalog = open_catalog(config)
        fulltext = open_fulltext(config)
        raise Thor::Error, "no index — run nabu sync or nabu rebuild" unless catalog && fulltext

        validate_source!(catalog, options[:source])
        outcome = Nabu::Query::Graded.new(catalog: catalog, fulltext: fulltext)
                                     .run(query, charset: options[:charset],
                                                 max_foreign: options[:max_foreign].to_i,
                                                 min_chars: options[:min_chars].to_i,
                                                 lang: options[:lang], license: options[:license],
                                                 source: options[:source], limit: options[:limit].to_i)
        print_graded_results(outcome, query: query)
        print_display_footer
      rescue Nabu::Error => e
        raise Thor::Error, e.message
      ensure
        catalog&.disconnect
        fulltext&.disconnect
      end

      def print_graded_results(outcome, query:)
        unless outcome.indexed
          return say("coverage not indexed yet — the passage_chars index arrives with the next " \
                     "`nabu rebuild` (or any sync's index refresh); no scan attempted")
        end
        if outcome.results.empty?
          tail = query.empty? ? "" : " that also match #{query.inspect}"
          return say("no passages read inside this #{outcome.charset_size}-character set" \
                     "#{" (±#{options[:max_foreign].to_i})" if options[:max_foreign].to_i.positive?}#{tail}")
        end

        outcome.results.each do |result|
          strangers = result.foreign.empty? ? "" : "  +{#{result.foreign.join(' ')}}"
          say "#{result.urn}  [#{result.language}]  #{result.nchars} chars#{strangers}"
          say "  #{result.text}"
        end
        say ""
        say "coverage: #{outcome.charset_size}-character set" \
            "#{" ± #{options[:max_foreign].to_i} strangers" if options[:max_foreign].to_i.positive?}" \
            "#{"; text query #{query.inspect}" unless query.empty?}" \
            "#{' — candidate window filled; narrow with --source/--lang for the rest' if outcome.capped}"
      end

      # The sign-coverage graded lane (P77-r16, sign-learning P-3): the
      # --charset architecture keyed on OSL sign names over the ATF
      # corpora. Needs the sign list (nabu sync osl) AND the passage_signs
      # index (a rebuild/refresh with the list present).
      def sign_graded_search
        validate_license!(options[:license])
        config = Nabu::Config.load
        list = Nabu::SignList.load_default(config: config)
        raise Thor::Error, "search: --signset needs the OSL sign list — run `nabu sync osl` first" unless list

        catalog = open_catalog(config)
        fulltext = open_fulltext(config)
        raise Thor::Error, "no index — run nabu sync or nabu rebuild" unless catalog && fulltext

        validate_source!(catalog, options[:source])
        outcome = Nabu::Query::SignGraded.new(catalog: catalog, fulltext: fulltext, sign_list: list)
                                         .run(signset: options[:signset],
                                              max_foreign: options[:max_foreign].to_i,
                                              lang: options[:lang], license: options[:license],
                                              source: options[:source], limit: options[:limit].to_i)
        print_sign_graded_results(outcome)
        print_display_footer
      rescue Nabu::Error => e
        raise Thor::Error, e.message
      ensure
        catalog&.disconnect
        fulltext&.disconnect
      end

      def print_sign_graded_results(outcome)
        unless outcome.indexed
          return say("sign coverage not indexed yet — the passage_signs index arrives with the " \
                     "next `nabu rebuild` (or a sign-source sync's refresh) once osl is synced; " \
                     "no scan attempted")
        end
        if outcome.results.empty?
          return say("no passages read inside this #{outcome.signset_size}-sign set" \
                     "#{" (±#{options[:max_foreign].to_i})" if options[:max_foreign].to_i.positive?}")
        end

        outcome.results.each do |result|
          strangers = result.foreign.empty? ? "" : "  +{#{result.foreign.join(' ')}}"
          say "#{result.urn}  [#{result.language}]  #{result.nsigns} signs#{strangers}"
          say "  #{result.text}"
        end
        say ""
        say "sign coverage: #{outcome.signset_size}-sign set" \
            "#{" ± #{options[:max_foreign].to_i} strangers" if options[:max_foreign].to_i.positive?}" \
            "#{' — candidate window filled; narrow with --source/--lang for the rest' if outcome.capped}"
      end

      # The explicit character-structure search (P37-4): --radical/--strokes/
      # --char-component resolve to a glyph set (CharFilter), which filters
      # Han-language passages by containment, composing with a plain text
      # query. Kept visibly distinct from FTS — the footer names the filters.
      def char_structured_search(query)
        validate_license!(options[:license])
        if options[:radical] && !options[:radical].to_i.between?(1, 214)
          raise Thor::Error, "search: --radical is a KangXi radical number 1-214 (got #{options[:radical]})"
        end

        strokes = parse_strokes_option
        config = Nabu::Config.load
        catalog = open_catalog(config)
        fulltext = open_fulltext(config)
        raise Thor::Error, "no index — run nabu sync or nabu rebuild" unless catalog && fulltext
        unless catalog.table_exists?(:dictionary_entries)
          raise Thor::Error, "no char shelf in this catalog — run nabu sync unihan (for --radical/" \
                             "--strokes) or babelstone-ids/kradfile (for --char-component)"
        end
        validate_source!(catalog, options[:source])

        outcome = Nabu::Query::CharSearch.new(catalog: catalog, fulltext: fulltext)
                                         .run(query, radical: options[:radical]&.to_i, strokes: strokes,
                                                     component: options[:char_component], lang: options[:lang],
                                                     license: options[:license], source: options[:source],
                                                     limit: options[:limit].to_i)
        print_char_search_results(outcome, query: query)
        print_display_footer
      ensure
        catalog&.disconnect
        fulltext&.disconnect
      end

      def print_char_search_results(outcome, query:)
        labels = outcome.labels.join(" AND ")
        if outcome.resolved_empty
          return say("no characters match [#{labels}] in the held char shelves — sync unihan " \
                     "(--radical/--strokes) or babelstone-ids/kradfile (--char-component)")
        end
        if outcome.results.empty?
          tail = query.empty? ? "" : " that also match #{query.inspect}"
          return say("no passages carry a character matching [#{labels}]#{tail} " \
                     "(#{outcome.char_count} characters resolved)")
        end

        outcome.results.each do |result|
          say "#{result.urn}  [#{result.language}]  {#{result.matched.join(' ')}}"
          say "  #{result.text}"
        end
        say ""
        text_note = query.empty? ? "" : "; text query #{query.inspect}"
        say "character filter: [#{labels}] — #{outcome.char_count} " \
            "#{outcome.char_count == 1 ? 'character' : 'characters'} resolved#{text_note}"
        say Nabu::Query::CatalogJoin::INCOMPLETE_PAGE_HINT if outcome.incomplete
      end

      # The semantic-neighbors page (P93-5): URN-anchored, no model
      # at query time — one sqlite-vec scan of the same-language subpool.
      # Every absent-machinery case surfaces as the query layer's honest
      # hint (store not built / anchor unembedded / extension missing).
      def similar_search(urn)
        config = Nabu::Config.load
        catalog = open_catalog(config)
        raise Thor::Error, "no catalog — run nabu sync or nabu rebuild" unless catalog

        vectors = Nabu::Store.connect(config.vectors_path)
        finder = Nabu::Query::Similar.new(catalog: catalog, vectors: vectors)
        page = finder.run(urn, limit: options[:limit].to_i)
        say "similar to #{page.anchor_urn} [#{page.language}] — model #{page.model}, " \
            "same-language only (cross-language is not served: the P79-5 measurement)"
        if page.results.empty?
          say "no neighbors in the store"
        else
          page.results.each do |result|
            say "#{result.urn}  (#{result.band})#{"  — #{result.document_title}" if result.document_title}"
            say "  #{display_snippet(result.snippet, result.language)}"
          end
          say "#{page.results.size} #{page.results.size == 1 ? 'neighbor' : 'neighbors'} " \
              "(banded semantic similarity — never a curated alignment; nabu align serves those)"
        end
        print_display_footer
      ensure
        catalog&.disconnect
        vectors&.disconnect
      end

      # The attic search (P93-2, first half of an owner ruling): scan the withdrawn set,
      # substring over folded text, reasons labeled. No fulltext file
      # needed — the scan is catalog-side by design (Search#run_withdrawn's
      # class note carries the measured argument).
      def withdrawn_search(query)
        config = Nabu::Config.load
        catalog = open_catalog(config)
        raise Thor::Error, "no catalog — run nabu sync or nabu rebuild" unless catalog

        fulltext = open_fulltext(config)
        searcher = Nabu::Query::Search.new(catalog: catalog, fulltext: fulltext)
        results = searcher.run_withdrawn(query, limit: options[:limit].to_i)
        if results.empty?
          say "no matches in the withdrawn set"
        else
          results.each do |result|
            say "#{result.urn}#{" [#{result.language}]" if result.language}  WITHDRAWN " \
                "(#{result.reason || 'reason unrecorded'}" \
                "#{", #{result.withdrawn_at.strftime('%Y-%m-%d')}" if result.withdrawn_at})"
            say "  #{display_snippet(result.snippet, result.language)}"
          end
          say "#{results.size} #{results.size == 1 ? 'hit' : 'hits'} in the withdrawn set " \
              "(substring over folded text; nothing here is served by default search)"
        end
        print_display_footer
      ensure
        catalog&.disconnect
        fulltext&.disconnect
      end

      # The options --translations does NOT compose with (it is its own
      # lane — no timeline, facets, morphology or glyph filters there).
      def translations_incompatible
        %i[fuzzy near lemma morph exact word words scan withdrawn similar sign charset signset
           from to century place date_basis within script type kind province material facet
           loans meter meter_pattern lect gold_only long radical strokes char_component]
      end

      # search --translations QUERY: the annotation-held translations
      # lane (Query::TranslationSearch). Desk rule: the precompiled lane or
      # the honest build hint — never a scan.
      def translations_search(query)
        clash = translations_incompatible.select { |key| options[key] }
        unless clash.empty?
          raise Thor::Error, "search: --translations searches the annotation-held translations lane and " \
                             "composes with --lang/--source/--axis/--license/--limit only (not " \
                             "#{clash.map { |key| "--#{key.to_s.tr('_', '-')}" }.join(', ')})"
        end
        raise Thor::Error, "search: --translations needs a query" if query.empty?

        validate_license!(options[:license])
        config = Nabu::Config.load
        catalog = open_catalog(config)
        fulltext = open_fulltext(config)
        raise Thor::Error, "no index — run nabu sync or nabu rebuild" unless catalog && fulltext

        validate_source!(catalog, options[:source])
        axis_names, axis_slugs = axis_membership(command: "search", config: config)
        searcher = Nabu::Query::TranslationSearch.new(catalog: catalog, fulltext: fulltext)
        results = searcher.run(query, lang: options[:lang], license: options[:license], source: options[:source],
                                      sources: axis_slugs, limit: options[:limit].to_i)
        print_translation_results(results, scope: searcher.scope, axis: axis_names,
                                           incomplete: searcher.incomplete_hint)
        print_display_footer
      rescue Nabu::Query::TranslationSearch::IndexMissing => e
        raise Thor::Error, "search: #{e.message}"
      ensure
        catalog&.disconnect
        fulltext&.disconnect
      end

      # Render translations hits: the ORIGINAL passage (urn + [language]),
      # the matched rendering under its annotation key with the term
      # bracketed, the original's leading text; then the footer, the
      # credits, and ONE scope line naming what the lane covers (the
      # fuzzy-lane honesty rule — a miss explains itself).
      def print_translation_results(results, scope:, axis: nil, incomplete: nil)
        if results.empty?
          say "no matches"
        else
          results.each do |result|
            say "#{result.urn}#{" [#{result.language}]" if result.language}" \
                "#{"  — #{result.document_title}" if result.document_title}"
            say "  #{result.layer}: #{display_snippet(result.snippet, nil)}"
            say "  original: #{display_snippet(truncate_line(result.text), result.language)}"
          end
          say "#{results.size} #{results.size == 1 ? 'hit' : 'hits'} in annotation-held translations " \
              "(the urn is the original passage — nabu show <urn>)#{facet_footer(nil, axis: axis)}"
          print_search_credits(results)
        end
        say "note: #{incomplete}" if incomplete
        covered = scope.map { |slug, passages| "#{slug} #{passages}" }.join(" · ")
        say "translations index covers: #{covered.empty? ? 'no sources' : covered}"
      end

      def fuzzy_search(query)
        raise Thor::Error, "search: --fuzzy needs a fragment" if query.empty?

        validate_license!(options[:license])
        from, to = date_window
        facets = facet_filters
        config = Nabu::Config.load
        catalog = open_catalog(config)
        fulltext = open_fulltext(config)
        raise Thor::Error, "no index — run nabu sync or nabu rebuild" unless catalog && fulltext
        unless fulltext.table_exists?(Nabu::Store::Indexer::TRIGRAM_TABLE)
          raise Thor::Error, "no fuzzy index (the fulltext index predates fragment search) — " \
                             "run nabu sync or nabu rebuild"
        end

        require_timeline!(catalog) if from || to || options[:place] || options[:date_basis]
        require_facets!(catalog) if facets
        validate_source!(catalog, options[:source])
        axis_names, axis_slugs = axis_membership(command: "search", config: config)
        fuzzy = Nabu::Query::Fuzzy.new(catalog: catalog, fulltext: fulltext)
        results = fuzzy.run(query, lang: options[:lang], license: options[:license],
                                   limit: options[:limit].to_i, from: from, to: to, place: options[:place],
                                   date_basis: date_basis_filter,
                                   facets: facets, source: options[:source], sources: axis_slugs,
                                   loans: loans_filter)
        print_fuzzy_results(results, scope: fuzzy.scope, long: options[:long], facets: facets,
                                     loans: loans_filter, axis: axis_names, incomplete: fuzzy.incomplete_hint)
        print_display_footer
      rescue Nabu::Query::Fuzzy::QueryTooShort => e
        raise Thor::Error, "search: --fuzzy needs at least 3 characters after folding " \
                           "(#{query.inspect} folds to #{e.folded.inspect}) — the trigram floor"
      ensure
        catalog&.disconnect
        fulltext&.disconnect
      end

      def lemma_search(positional_query)
        unless positional_query.empty?
          raise Thor::Error, "search: --lemma replaces the text query — give one or the other"
        end

        lemma = options[:lemma].strip
        raise Thor::Error, "search: --lemma needs a lemma" if lemma.empty?

        validate_license!(options[:license])
        config = Nabu::Config.load
        catalog = open_catalog(config)
        fulltext = open_fulltext(config)
        raise Thor::Error, "no index — run nabu sync or nabu rebuild" unless catalog && fulltext
        unless fulltext.table_exists?(Nabu::Store::Indexer::LEMMA_TABLE)
          raise Thor::Error, "no lemma index (the fulltext index predates lemma search) — " \
                             "run nabu sync or nabu rebuild"
        end

        validate_source!(catalog, options[:source])
        axis_names, axis_slugs = axis_membership(command: "search", config: config)
        searcher = Nabu::Query::LemmaSearch.new(catalog: catalog, fulltext: fulltext)
        results = searcher.run(lemma, lang: options[:lang], license: options[:license],
                                      limit: options[:limit].to_i, morph: options[:morph],
                                      source: options[:source], sources: axis_slugs,
                                      gold_only: options[:gold_only], loans: loans_filter,
                                      gloss: options[:gloss])
        print_lemma_results(results, query: lemma, axis: axis_names, incomplete: searcher.incomplete_hint)
        print_display_footer
      rescue Nabu::Query::MorphFacets::Error, Nabu::Query::TokenGlosses::Error => e
        raise Thor::Error, "search: #{e.message}"
      ensure
        catalog&.disconnect
        fulltext&.disconnect
      end

      # search A --near B [--window N] (P14-8): proximity search over the FTS
      # index via FTS5 NEAR. The anchor is the positional query OR --lemma
      # (expanded to attested surface forms); --near B is the second term;
      # --window N is the max folded tokens between them (default 10, 0 =
      # adjacent). Hits render exactly like plain search — the snippet brackets
      # BOTH terms. --morph does not compose (out of scope, said honestly).
      def proximity_search(positional_query)
        near = options[:near].strip
        raise Thor::Error, "search: --near needs a term" if near.empty?
        if options[:morph]
          raise Thor::Error, "search: --morph does not compose with --near " \
                             "(morphology-narrowed proximity is out of scope)"
        end
        window = options[:window].to_i
        raise Thor::Error, "search: --window must be 0 or more" if window.negative?

        lemma = options[:lemma]&.strip
        if options[:lemma]
          unless positional_query.empty?
            raise Thor::Error,
                  "search: --lemma replaces the text query — give one or the other"
          end
          raise Thor::Error, "search: --lemma needs a lemma" if lemma.empty?
        elsif positional_query.empty?
          raise Thor::Error, "search: --near needs an anchor term (a query, or --lemma)"
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

        validate_source!(catalog, options[:source])
        axis_names, axis_slugs = axis_membership(command: "search", config: config)
        searcher = Nabu::Query::Proximity.new(catalog: catalog, fulltext: fulltext)
        results = searcher.run(
          query: lemma ? nil : positional_query, lemma: lemma, near: near, window: window,
          lang: options[:lang], license: options[:license], limit: options[:limit].to_i,
          source: options[:source], sources: axis_slugs, loans: loans_filter
        )
        print_search_results(results, loans: loans_filter, axis: axis_names,
                                      incomplete: searcher.incomplete_hint, proximity: true)
        print_display_footer
      ensure
        catalog&.disconnect
        fulltext&.disconnect
      end

      # Render lemma hits: urn + language, the dictionary form with the surface
      # form(s) that attest it, then the PRISTINE passage line (truncated) —
      # the surface form already marks the match, so readability wins over a
      # folded snippet here. Non-gold hits are labeled per hit — gold stays
      # unlabeled, the pre-tier render exactly (P26-0 silver; P34-3
      # equivalence: a Latin key on a non-Latin passage, scholar-curated,
      # never attestation); the footer totals each non-gold share and names
      # the way out.
      def print_lemma_results(results, query: nil, axis: nil, incomplete: nil)
        if results.empty?
          say "no matches"
          say "note: #{incomplete}" if incomplete
          return print_script_miss_hints(query)
        end

        results.each do |result|
          forms = result.surface_forms.empty? ? "(no surface form)" : result.surface_forms
          gloss = result.gloss ? "  (#{result.gloss})" : ""
          token_gloss = result.token_gloss ? "  ‘#{result.token_gloss}’" : ""
          morph = result.morph ? "  {#{result.morph}}" : ""
          tier = result.tier == "gold" ? "" : " [#{result.tier}]"
          say "#{result.urn}#{" [#{result.language}]" if result.language}#{tier}  " \
              "#{result.lemma} → #{forms}#{gloss}#{token_gloss}#{morph}"
          say "  #{display_text(truncate_line(result.text), result.language)}"
        end
        silver = results.count { |result| result.tier == "silver" }
        footer = "#{results.size} #{results.size == 1 ? 'hit' : 'hits'} (exact lemma match; text is pristine)"
        footer += " — #{silver} silver (automatic lemmatization; --gold-only excludes)" if silver.positive?
        equivalence = results.count { |result| result.tier == "equivalence" }
        if equivalence.positive?
          footer += " — #{equivalence} equivalence (scholar-curated Classical-Latin equivalents; " \
                    "--gold-only excludes)"
        end
        footer += " · axis: #{Array(axis).join(',')}" if axis && !Array(axis).empty?
        say footer
        say "note: #{incomplete}" if incomplete
      end

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

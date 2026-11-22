# frozen_string_literal: true

# Nabu::CLI — `nabu search` and its lanes: filters, browse, sign/char/graded,
# fuzzy, lemma, proximity, translations/annotations/gloss, similar.
# A partial of lib/nabu/cli/query.rb, which loads it.
module Nabu
  class CLI < Thor
    # The options `search --similar` honors (mirroring the MCP similar_to
    # ruling): --lang pins the anchor's own language (Query::Similar refuses
    # any other, never widens), --limit bounds the page, --display renders.
    SIMILAR_OPTIONS = %w[similar limit lang display].freeze

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

      BETA CODE (--betacode): type Greek in TLG Beta Code — the query (and
      any --lemma/--near term) is transliterated to Greek before matching,
      and each decode is echoed (`beta code: mh=nin → μῆνιν`). Case-blind
      (MH=NIN works), * before a letter marks a capital, the FTS quotes and
      a trailing prefix * pass through. A deliberate flag: Latin-letter
      queries are never guessed to be Beta Code.

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
      OSHB, ReM/ReN/REF (CorA msd/morph), goo300k (IMP msd), Menota (msa), CEIPoM
      (AGDT pos_code, via its Latin-equivalent lemmas), HeliPaD (pos^morph), CorPH (analysis), AES and TraCES (their explicit fields), tla-hf (grammatical glossing) and Coptic
      Scriptorium (pos: polarity, prontype, definite, verbform) are
      decoded into the same names — Hebrew/Aramaic add state, stem and
      conjugation (e.g. --morph stem=piel,conjugation=wayq). Ambiguous
      analyses match when any reading fits. Each hit shows the matching
      surface form(s) and the decoded morph evidence. --morph REQUIRES --lemma (bare morphology search
      is out of scope); ORACC carries no inflectional morphology, so
      inflectional facets never match it (honest absence). See conventions §6.1.

      TOKEN GLOSSES (--gloss WORD): sources that store upstream's own word
      meaning on each token (bhsa, achemenet, ceipom: English; aes, tlhdig:
      German)
      show it on every lemma hit in ‘quotes’, beside any dictionary gloss.
      DSS hits show BHSA's English gloss, borrowed through the lex_etcbc
      lexeme crosswalk at read time (display only — not a --gloss filter).
      With --lemma, --gloss keeps only attestations whose token gloss
      contains WORD (whole word, case-insensitive) — e.g. BHSA's consonantal
      דבר as "word" vs "speak". Composes with --morph; not with --near.
      With NO query and no --lemma, --gloss WORD searches the glosses
      ACROSS lemmas: every word some source glosses WORD (BHSA's Hebrew and
      Aramaic מלך, achemenet's šarru for "king"), one line per word with its
      token count and first attestation. Words AND, "phrase", word* prefix;
      case- and diacritic-insensitive (konig finds König). Composes with
      --lang/--source/--axis/--license/--limit only; built by the reference
      rebuild (or `bundle exec rake index:glosses`).

      GLOSS LINES (--gloss-lines QUERY): the CONTENT search of those same
      token glosses, one hit per PASSAGE. Each passage's glosses are read
      in token order as its interlinear gloss line, so `--gloss-lines king`
      finds every verse, tablet or line with a word glossed king (BHSA's
      Daniel in Aramaic, achemenet's Akkadian, tlhdig's Hittite as König),
      words AND within the passage (king eternity is Dan 2:4), and a quoted
      phrase may run across tokens ("to the king"). Each hit shows the
      gloss line, the matching words with their glosses, and the passage
      text. Glosses fold by their own language (konig finds König); --lang
      names the TEXT language. Same grammar, filters and scope line as
      --annotations; built by the reference rebuild (or `bundle exec rake
      index:gloss_lines`).

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

      ANNOTATIONS (--annotations): search the passage-grain text layers a
      source keeps in its annotations, declared per source — Cantus'
      standardized spelling of each chant (so praesul finds the manuscript
      that writes presul) and Korpus 16's marginal notes (Dalmatin's
      loanword glosses, the scripture references). Each hit is the passage
      itself, with the matched layer and the passage text under it. The
      layers fold with their passage's own language, as the main search
      does (jam finds iam in Latin; ſ needs no typing in Slovene). Same
      grammar, filters and scope line as --translations; the lane is built
      by the reference rebuild (or `bundle exec rake index:annotations`).

      Examples:
        nabu search μηνιν                          # finds μῆνιν, accents optional
        nabu search mh=nin --betacode              # the same, typed in Beta Code
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
        nabu search --annotations praesul          # chants whose standardized text
                                                   #   says praesul (manuscript: presul)
        nabu search --lemma λέγω --lang grc        # every attestation in the Greek
                                                   #   treebank: λέγουσι, εἶπας, εἰπεῖν…
        nabu search --lemma tu --lang lat          # te, tibi, tu across PROIEL Cicero
        nabu search --lemma λόγος --morph case=dat,number=pl
                                                   # only the dative-plural λόγοις
        nabu search --lemma דבר --gloss word       # BHSA דבר as "word", not "speak"
        nabu search --gloss-lines "king eternity"  # every passage whose glosses say
                                                   #   both — Dan 2:4 in Aramaic
        nabu search --gloss king                   # every word glossed "king", across
                                                   #   lemmas and sources
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
                         "contains WORD (bhsa/aes/achemenet/tlhdig/ceipom); alone (no query): every word " \
                         "glossed WORD, across lemmas"
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
    option :annotations, type: :boolean, default: false,
                         desc: "Search the DECLARED annotation layers (standardized/regularized spellings, readings, " \
                               "margin notes, footnotes, editors' notes); hits are the passages themselves — " \
                               "composes with --lang/--source/--axis/--license/--limit only"
    option :gloss_lines, type: :boolean, default: false,
                         desc: "Content search of the upstream TOKEN GLOSSES (bhsa/achemenet English, " \
                               "aes/tlhdig German), one hit per passage — composes with " \
                               "--lang/--source/--axis/--license/--limit only"
    option :withdrawn, type: :boolean, default: false,
                       desc: "Attic inspection: search WITHDRAWN passages only (upstream-gone " \
                             "documents, revision-pruned passages) — substring match over the " \
                             "folded text, each hit labeled with its reason; composes with " \
                             "--limit only"
    option :similar, type: :string, banner: "URN",
                     desc: "Semantic neighbors of one embedded passage (P93-5): " \
                           "same-language cross-edition retrieval over the nabu-embed vectors, " \
                           "rendered in bands (close/near/loose), model named in the header — " \
                           "IS the query (give no term); composes with --lang/--limit only " \
                           "(--lang must be the anchor's own language; other filters are refused)"
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
    option :betacode, type: :boolean, default: false,
                      desc: "Beta Code input: the typed term (and any --lemma/--near) is " \
                            "transliterated to Greek before matching (mh=nin → μῆνιν; case-blind, " \
                            "FTS quotes and prefix* pass through) — a deliberate flag, never auto-detected"
    display_option
    def search(query = nil)
      query = query.to_s.strip
      if options[:similar]
        similar_lane_conflicts!(query)
        display_mode
        return similar_search(options[:similar])
      end
      query = betacode_input(query) if options[:betacode]
      display_mode
      date_basis_filter
      return gloss_search(options[:gloss]) if options[:gloss] && !options[:lemma] && query.empty?
      return translations_search(query) if options[:translations]
      return annotations_search(query) if options[:annotations]
      return gloss_lines_search(query) if options[:gloss_lines]
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
                           "it needs a word and requires --lemma (and does not compose with --near); " \
                           "--gloss WORD alone, with no query, searches the glosses across lemmas"
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

    # Reading values shown on the `search --sign` header line before the
    # "… and N more" tail (P75 C-4, the same house render-cap rule).
    # const: a render cap, not a corpus census
    SIGN_SEARCH_VALUES_SHOWN = 12

    # Matching words shown per `search --gloss-lines` hit before the
    # "(+N more)" tail (the same house render-cap rule).
    # const: a render cap, not a corpus census
    GLOSS_LINE_WORDS = 6

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

    no_commands do
      # The --betacode input flag: decode the typed Greek-bearing terms (the
      # query, --lemma, --near) from Beta Code before any path reads them,
      # and echo each decode so the reader sees what was actually searched.
      # Deliberate, never auto-detected — Latin letters are a legitimate
      # query in their own right. Returns the decoded query; the decoded
      # --lemma/--near replace their option values.
      def betacode_input(query)
        terms = { "query" => query, "lemma" => options[:lemma], "near" => options[:near] }
                .reject { |_key, value| value.to_s.strip.empty? }
        if terms.empty?
          raise Thor::Error, "search: --betacode decodes a typed Greek term — give a query, " \
                             "--lemma or --near to decode"
        end

        decoded = terms.transform_values { |raw| Nabu::Betacode.decode_query(raw.strip) }
        decoded.each { |key, greek| say "beta code: #{terms.fetch(key).strip} → #{greek}" }
        overrides = decoded.except("query")
        self.options = Thor::CoreExt::HashWithIndifferentAccess.new(options.merge(overrides)).freeze
        decoded.fetch("query", query)
      end

      # Reject an unknown --license up front (before opening any db) with the
      # closed enum of valid classes, so the user sees the choices. Shared by
      # search and export.
      # Split note: also used by concord, vocab, export, links and census; kept with its primary user.
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
      # Split note: also used by vocab --by-century and census; kept with its primary user.
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
      # Split note: also used by vocab --by-century and census; kept with its primary user.
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
      # Split note: also used by the lexicon commands; kept with its primary user.
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
      # the CATALOG — what is held is what can be filtered. The resolution
      # lives once in Query::SourceScope (the MCP nabu_search shares it).
      # Split note: also used by export; kept with its primary user.
      def validate_source!(catalog, slug)
        Nabu::Query::SourceScope.validate_source!(catalog, slug)
      rescue Nabu::Query::SourceScope::Error => e
        raise Thor::Error, e.message
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
      # a bare name unambiguous. The resolution lives once in
      # Query::SourceScope (the MCP nabu_search shares it).
      # Split note: also used by export; kept with its primary user.
      def axis_membership(command:, config:)
        spec = options[:axis].to_s.strip
        return nil if spec.empty?

        registry = Nabu::SourceRegistry.load(config.sources_path)
        Nabu::Query::SourceScope.axis_membership(registry, spec, command: command)
      rescue Nabu::Query::SourceScope::Error => e
        raise Thor::Error, e.message
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

      # Every option outside SIMILAR_OPTIONS set away from its default is a
      # filter the similar lane cannot honor — refused by name, never
      # silently dropped.
      def similar_lane_conflicts!(query)
        defaults = self.class.commands["search"].options.to_h { |name, opt| [name.to_s, opt.default] }
        clash = options.reject { |name, value| SIMILAR_OPTIONS.include?(name) || value.nil? || value == defaults[name] }
                       .keys.map { |name| "--#{name.tr('_', '-')}" }
        clash.unshift("a search term") unless query.empty?
        return if clash.empty?

        raise Thor::Error, "search: --similar URN is the semantic-neighbors page — the urn IS the query " \
                           "(give no term); --similar composes with --lang/--limit only (not #{clash.join(', ')})"
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
        page = finder.run(urn, limit: options[:limit].to_i, language: options[:lang])
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
        clash = (translations_incompatible + %i[annotations gloss_lines]).select { |key| options[key] }
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

      # search --annotations QUERY: the declared annotation layers lane
      # (Query::AnnotationSearch). Same composition set and desk rule as
      # --translations: the precompiled lane or the honest build hint.
      def annotations_search(query)
        clash = (translations_incompatible + %i[translations gloss_lines]).select { |key| options[key] }
        unless clash.empty?
          raise Thor::Error, "search: --annotations searches the declared annotation layers lane and " \
                             "composes with --lang/--source/--axis/--license/--limit only (not " \
                             "#{clash.map { |key| "--#{key.to_s.tr('_', '-')}" }.join(', ')})"
        end
        raise Thor::Error, "search: --annotations needs a query" if query.empty?

        validate_license!(options[:license])
        config = Nabu::Config.load
        catalog = open_catalog(config)
        fulltext = open_fulltext(config)
        raise Thor::Error, "no index — run nabu sync or nabu rebuild" unless catalog && fulltext

        validate_source!(catalog, options[:source])
        axis_names, axis_slugs = axis_membership(command: "search", config: config)
        searcher = Nabu::Query::AnnotationSearch.new(catalog: catalog, fulltext: fulltext)
        results = searcher.run(query, lang: options[:lang], license: options[:license], source: options[:source],
                                      sources: axis_slugs, limit: options[:limit].to_i)
        print_annotation_results(results, scope: searcher.scope, axis: axis_names,
                                          incomplete: searcher.incomplete_hint)
        print_display_footer
      rescue Nabu::Query::AnnotationSearch::IndexMissing => e
        raise Thor::Error, "search: #{e.message}"
      ensure
        catalog&.disconnect
        fulltext&.disconnect
      end

      # Render annotation hits: the passage (urn + [language]), the matched
      # layer under its annotation key with the term bracketed, the
      # passage's own leading text; then the footer, the credits, and ONE
      # scope line naming what the lane covers.
      def print_annotation_results(results, scope:, axis: nil, incomplete: nil)
        if results.empty?
          say "no matches"
        else
          results.each do |result|
            say "#{result.urn}#{" [#{result.language}]" if result.language}" \
                "#{"  — #{result.document_title}" if result.document_title}"
            say "  #{result.layer}: #{display_snippet(result.snippet, result.language)}"
            say "  text: #{display_snippet(truncate_line(result.text), result.language)}"
          end
          say "#{results.size} #{results.size == 1 ? 'hit' : 'hits'} in declared annotation layers " \
              "(the urn is the passage — nabu show <urn>)#{facet_footer(nil, axis: axis)}"
          print_search_credits(results)
        end
        say "note: #{incomplete}" if incomplete
        covered = scope.map { |slug, passages| "#{slug} #{passages}" }.join(" · ")
        say "annotations index covers: #{covered.empty? ? 'no sources' : covered}"
      end

      # search --gloss-lines QUERY: the passage-grain content search of
      # the token glosses (Query::GlossLineSearch). Same composition set
      # and desk rule as --annotations; --gloss (the word-grain lane and
      # the lemma filter) is a different question, refused.
      def gloss_lines_search(query)
        clash = (translations_incompatible + %i[translations annotations gloss]).select { |key| options[key] }
        unless clash.empty?
          raise Thor::Error, "search: --gloss-lines searches the passages' token-gloss lines and " \
                             "composes with --lang/--source/--axis/--license/--limit only (not " \
                             "#{clash.map { |key| "--#{key.to_s.tr('_', '-')}" }.join(', ')})"
        end
        raise Thor::Error, "search: --gloss-lines needs a query, e.g. --gloss-lines king" if query.empty?

        validate_license!(options[:license])
        config = Nabu::Config.load
        catalog = open_catalog(config)
        fulltext = open_fulltext(config)
        raise Thor::Error, "no index — run nabu sync or nabu rebuild" unless catalog && fulltext

        validate_source!(catalog, options[:source])
        axis_names, axis_slugs = axis_membership(command: "search", config: config)
        searcher = Nabu::Query::GlossLineSearch.new(catalog: catalog, fulltext: fulltext)
        results = searcher.run(query, lang: options[:lang], license: options[:license], source: options[:source],
                                      sources: axis_slugs, limit: options[:limit].to_i)
        print_gloss_line_results(results, scope: searcher.scope, axis: axis_names,
                                          incomplete: searcher.incomplete_hint)
        print_display_footer
      rescue Nabu::Query::GlossLineSearch::IndexMissing => e
        raise Thor::Error, "search: #{e.message}"
      ensure
        catalog&.disconnect
        fulltext&.disconnect
      end

      # Render gloss-line hits: the passage (urn + [language] + source),
      # its gloss line with the term bracketed, the matching words
      # (form ‘gloss’, capped and the tail announced), the passage's own
      # leading text; then the footer, the credits, and ONE scope line.
      def print_gloss_line_results(results, scope:, axis: nil, incomplete: nil)
        if results.empty?
          say "no matches"
        else
          results.each do |result|
            say "#{result.urn}#{" [#{result.language}]" if result.language} #{result.source}" \
                "#{"  — #{result.document_title}" if result.document_title}"
            say "  glosses: #{result.snippet}"
            say "  words: #{gloss_line_words(result)}" unless result.words.empty?
            say "  text: #{display_snippet(truncate_line(result.text), result.language)}"
          end
          say "#{results.size} #{results.size == 1 ? 'hit' : 'hits'} in token gloss lines " \
              "(the urn is the passage — nabu show <urn>)#{facet_footer(nil, axis: axis)}"
          print_search_credits(results)
        end
        say "note: #{incomplete}" if incomplete
        covered = scope.map { |slug, passages| "#{slug} #{passages}" }.join(" · ")
        say "gloss-lines index covers: #{covered.empty? ? 'no sources' : covered}"
      end

      # The matching words, form ‘gloss’, capped at GLOSS_LINE_WORDS with
      # the tail counted — never silently dropped.
      def gloss_line_words(result)
        shown = result.words.first(GLOSS_LINE_WORDS).map do |form, gloss|
          "#{display_text(form, result.language) unless form.empty?} ‘#{gloss}’".strip
        end
        rest = result.words.size - shown.size
        "#{shown.join(' · ')}#{" (+#{rest} more)" if rest.positive?}"
      end

      # search --gloss WORD with no --lemma and no query: the token-gloss
      # lane (Query::GlossSearch) — every word upstream glosses WORD,
      # across lemmas. Same composition set as --translations.
      def gloss_search(gloss)
        clash = (translations_incompatible + %i[translations annotations gloss_lines]).select { |key| options[key] }
        unless clash.empty?
          raise Thor::Error, "search: --gloss alone searches the token-gloss lane and composes with " \
                             "--lang/--source/--axis/--license/--limit only (not " \
                             "#{clash.map { |key| "--#{key.to_s.tr('_', '-')}" }.join(', ')})"
        end
        raise Thor::Error, "search: --gloss needs a word, e.g. --gloss king" if gloss.strip.empty?

        validate_license!(options[:license])
        config = Nabu::Config.load
        catalog = open_catalog(config)
        fulltext = open_fulltext(config)
        raise Thor::Error, "no index — run nabu sync or nabu rebuild" unless catalog && fulltext

        validate_source!(catalog, options[:source])
        axis_names, axis_slugs = axis_membership(command: "search", config: config)
        searcher = Nabu::Query::GlossSearch.new(catalog: catalog, fulltext: fulltext)
        results = searcher.run(gloss, lang: options[:lang], license: options[:license], source: options[:source],
                                      sources: axis_slugs, limit: options[:limit].to_i)
        print_gloss_results(results, gloss: gloss.strip, scope: searcher.scope, axis: axis_names,
                                     incomplete: searcher.incomplete_hint)
        print_display_footer
      rescue Nabu::Query::GlossSearch::IndexMissing => e
        raise Thor::Error, "search: #{e.message}"
      ensure
        catalog&.disconnect
        fulltext&.disconnect
      end

      # Render gloss hits: one line per WORD (lemma ‘gloss’ [language]
      # source — counts), its first attestation under it; the drill-down
      # footer (the lemma-anchored filter lists every attestation), the
      # credits, and ONE scope line naming what the lane covers.
      def print_gloss_results(results, gloss:, scope:, axis: nil, incomplete: nil)
        if results.empty?
          say "no matches"
        else
          results.each do |result|
            head = result.lemma.empty? ? result.form : result.lemma
            say "#{head} ‘#{result.gloss}’#{" [#{result.language}]" if result.language} #{result.source} — " \
                "#{result.tokens} #{result.tokens == 1 ? 'token' : 'tokens'} in " \
                "#{result.passages} #{result.passages == 1 ? 'passage' : 'passages'}"
            say "  e.g. #{result.urn}#{" (#{result.form})" unless result.form.empty?}"
          end
          say "#{results.size} #{results.size == 1 ? 'word' : 'words'} glossed ‘#{gloss}’ in upstream token " \
              "glosses (every attestation: nabu search --lemma <lemma> --gloss <word> --source <slug>)" \
              "#{facet_footer(nil, axis: axis)}"
          print_search_credits(results)
        end
        say "note: #{incomplete}" if incomplete
        covered = scope.map { |slug, words, _tokens| "#{slug} #{words} words" }.join(" · ")
        say "gloss index covers: #{covered.empty? ? 'no sources' : covered}"
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
    end
  end
end

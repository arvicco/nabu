# frozen_string_literal: true

require_relative "starling_dbf_parser"
require_relative "starling_lexstat"

module Nabu
  module Adapters
    # The StarLing / Tower of Babel adapter (P22-0 + P23-0;
    # .docs/surveys/pie-survey.md §3.1): the Indo-European package (IE.exe — a plain
    # zip despite the name, 6.2 MB) from starlingdb.org, ingesting its FIVE
    # etymological bases as dictionary shelves — Moscow-school witnesses
    # beside kaikki/LIV/IE-CoR:
    #
    #   starling-pokorny (ine-pro) — 2,222 IEW roots: J. Pokorny's
    #                    Indogermanisches Etymologisches Wörterbuch, scanned
    #                    and recognized by George Starostin, corrected by
    #                    A. Lubotsky (the in-package pokorny.inf DBINFO).
    #                    ROOT/MEANING/GER_MEAN/MATERIAL/PAGES + the PIET
    #                    crosslink into the second base.
    #   starling-piet   (ine-pro) — 3,291 etymologies: S. L. Nikolayev's
    #                    Walde-Pokorny-based PIE database, Hittite/Tocharian
    #                    reflexes added by S. Starostin (piet.inf DBINFO);
    #                    traditional laryngeal-free notation; per-branch
    #                    reflex columns HITT/IND/AVEST/IRAN/ARM/GREEK/SLAV/
    #                    BALT/GERM/LAT/ITAL/CELT/ALB/TOKH, plus the SLAVNUM/
    #                    BALTNUM/GERMNUM links into the subordinate bases —
    #                    live entry ids since P23-0 (censused: GERMNUM
    #                    1,965/1,965 and SLAVNUM 1,233/1,233 resolve; six
    #                    BALTNUM links dangle on baltet's own six
    #                    duplicate-NUMBER records, below).
    #   starling-vasmer (rus, P23-0) — 18,239 entries: M. Vasmer's
    #                    etymological dictionary of Russian (the Trubachev
    #                    Russian edition: TRUBACHEV = his bracketed
    #                    additions), scanned/OCR'd/database-converted by the
    #                    project; vasmer.inf is BLANK, so field labels come
    #                    from the live CGI (Word / Near etymology / Further
    #                    etymology / Trubachev's comments / Editorial
    #                    comments / Pages, web-verified 2026-07-15) and the
    #                    credit from the descrip.php roster. Prose fields
    #                    only — no reflex columns; the shelf is piet's
    #                    SLAVNUM target ("currently serving as a substitute
    #                    for the comparative Slavic database", roster).
    #   starling-germet (gem-pro, P23-0) — 1,994 Common Germanic
    #                    etymologies (S. Nikolayev, germet.inf DBINFO):
    #                    per-language columns GOT…HG, PRNUM → piet.
    #   starling-baltet (bat-pro, P23-0) — 1,651 Proto-Baltic etymologies
    #                    (S. Nikolayev, baltet.inf DBINFO): OLITH/LITH/LETT/
    #                    OPRUS columns, PRNUM → piet. Six records carry a
    #                    NUMBER another record already used (76/95/248/689/
    #                    1049/1394 — upstream defect, matching piet's six
    #                    dangling BALTNUM links): the first keeps the NUMBER
    #                    as entry id, a repeat gets a stable ".2" file-order
    #                    suffix (canonical bytes untouched).
    #   starling-kart   (ccs-pro, P46-6) — 1,310 Proto-Kartvelian etymologies
    #                    from a SECOND package (KART.exe, same site, same
    #                    grant): S. Starostin's database "on the basis of
    #                    G. Klimov's and Faehnrich-Sardhveladze's etymological
    #                    dictionaries of Kartvelian languages" (kartet.inf
    #                    DBINFO), Klimov's reconstruction preferred verbatim.
    #                    GRU/MEG/SVA/LAZ single-language columns (+ per-column
    #                    Rus./Engl. meaning fields), PRNUM → the unheld
    #                    Nostratic base (a body line, exactly piet's PRNUM).
    #                    Fetched into the kart/ subdir with its own ZipFetch
    #                    state; the root IE.exe fetch declares keep: so a
    #                    re-fetch of one package never attics the other.
    #                    Two records carry a duplicated NUMBER (48, 134 —
    #                    the second 134 sits at file position 1133, piet's
    #                    dropped-leading-digit shape): the -b suffix rule.
    #                    ccs-pro is minted by the family-code + -pro
    #                    convention (ISO 639-5 ccs; the bat-pro precedent).
    #
    # == The P104-3 packages (Q84: six further downloads, same shelf, same grant)
    #
    # ALTAIC / CAUC / SINTIB / DRAV / CHUKCHEE / YENISEY .exe — plain zips
    # like IE.exe/KART.exe, each fetched into its own subdir with its own
    # ZipFetch state (the kart posture, generalized). Nine further bases
    # ride as BASES configuration — the FAMILY-HEAD etymological base of
    # each package plus the branch bases that follow the head pattern
    # cheaply:
    #
    #   starling-altet  (tut-pro)     — 2,805 Proto-Altaic etymologies: the
    #                    database version of the Starostin-Dybo-Mudrak
    #                    "Altaic Etymological Dictionary" (Brill 2003;
    #                    altet.inf DBINFO). Five branch protoform columns
    #                    (piet's SLAV/BALT/GERM verdict: body-only) with
    #                    links into the five branch bases. ONE censused
    #                    junk cell: #1728's TURC slot holds whitespace
    #                    bytes where a var pointer belongs (the parser's
    #                    junk-pointer lane).
    #   starling-japet  (jpx-pro)     — 1,705 Proto-Japanese etymologies,
    #                    "the Japanese part" of the AED (japet.inf;
    #                    Starostin 1975 accent reconstruction). AJP (Old
    #                    Japanese, 8th c.) mints ojp rows; MJP has no
    #                    clean code and the seven modern dialect columns
    #                    are accent transcriptions — body-only.
    #   starling-caucet (ccn-pro)     — 2,327 Proto-North-Caucasian
    #                    etymologies: the published Nikolayev-Starostin
    #                    "A North Caucasian Etymological Dictionary"
    #                    (Moscow 1994; caucet.inf DBINFO). Six branch
    #                    protoform columns body-only; LAK/KHIN hold ACTUAL
    #                    Lak/Khinalug forms (the DBINFO's own words) and
    #                    mint lbe/kjj rows. 223 headword-less records
    #                    (censused) keep their slots as "#NUMBER".
    #   starling-stibet (sit-pro)     — 2,823 Proto-Sino-Tibetan
    #                    etymologies (Peiros-Starostin 1996 with improved
    #                    reconstructions; Lepcha data by Olga Mazo —
    #                    stibet.inf DBINFO). LEPCHA mints lep rows; TIB is
    #                    transliteration (script-mismatched against the
    #                    Tibetan-script gold — the piet GREEK treatment),
    #                    CHIN is Starostin's OC reconstruction led by a
    #                    Big5 character (honest U+FFFD under the StarLing
    #                    tables), BURM/LUSH mix in PLB/PKC protoforms,
    #                    KACH carries tone-digit notation — all body-only.
    #                    46 headword-less records; ONE truncated-var
    #                    record (#2785, the parser's truncated-var lane);
    #                    the unaliased STLSNUM lexstat link rides nowhere.
    #   starling-dravet (dra-pro)     — 2,171 Proto-Dravidian
    #                    reconstructions "as listed in A Dravidian
    #                    Etymological Dictionary by T. Burrow and M. B.
    #                    Emeneau, revised and significantly modified by
    #                    G. Starostin" (dravet.inf DBINFO). Five branch
    #                    protoform columns body-only; BRA (Brahui, an
    #                    actual language) mints brh rows. Four numeric
    #                    link cells carry dBase's "****" overflow sentinel
    #                    (censused) — no crosslink line without a number.
    #   starling-kamet  (qfa-cka-pro) — 1,099 Proto-Chukchee-Kamchatkan
    #                    reconstructions: O. Mudrak's family-head database
    #                    (kamet.inf DBINFO; Russian glosses — upstream:
    #                    "no English translation is available yet", the
    #                    vasmer precedent). CHUK/ITEL protoform columns
    #                    body-only, linking into the two subordinates.
    #                    One duplicate NUMBER (689 ×2 — the -b rule).
    #   starling-chuket (qfa-chk-pro) — 2,281 Chukchee-Koryak
    #                    reconstructions (O. Mudrak, subordinate). CHU/
    #                    KOR/ALU mint ckt/kpy/alr rows; PAL (Palana, a
    #                    Koryak variety without a code) body-only; the
    #                    unaliased STPRO/CHFUNC/KOFUNC/ALFUNC columns sit
    #                    outside the .inf field_list and ride nowhere.
    #                    Four duplicate NUMBERs (1206/1584/1657/1956 ×2).
    #   starling-itelet (itl-pro)     — 1,673 Proto-Itelmen reconstructions
    #                    (O. Mudrak, subordinate), with Napana/Kovran/
    #                    Stebnitski Itelmen columns (ITE mints itl rows)
    #                    and Dybowski's extinct Western/Southern Kamchadal
    #                    records (body-only — no codes exist). Four
    #                    duplicate NUMBERs (199/269/1119/1521 ×2).
    #   starling-yenet  (qfa-yen-pro) — 1,059 Proto-Yenisseian
    #                    reconstructions (published as Starostin 1995;
    #                    Russian glosses). All five columns are actual
    #                    single languages: KET/SYM/KOT/ARI/PUM mint
    #                    ket/yug/zko/xrn/xpm rows. One duplicate NUMBER
    #                    (904 ×2); two headword-less records.
    #
    # DECLARED DEFERRED (deliberate coarseness, censused 2026-09-26 —
    # each follows the head pattern and can ride as a later BASES row):
    # ALTAIC's four branch bases (turcet 2,017 / monget 2,174 / tunget
    # 2,435 / koret 1,206 — koret.inf carries no DBINFO credit, so its
    # credit needs the roster); CAUC's eight branch bases (nakhet 970 /
    # aandet 1,539 / cezet 1,108 / laket 955 / darget 924 / lezget 1,569 /
    # khinet 349 / abadet 817); DRAV's eleven branch bases (sdret 4,692 /
    # telet 2,774 / kogaet 1,509 / gndet 1,428 / gonet 1,475 / kuiet
    # 1,377 / konet 961 / ktet 1,665 / ndret 989 / pemet 740 / braet 269);
    # SINTIB's five Kiranti-lane bases (kiret 994 / dumet 1,517 / kulet
    # 1,466 / limet 2,354 / yamet 1,974). bigchina (9,093 Old Chinese
    # character entries, stibet's CHINNUM target) is deferred on a HARD
    # reason, not cost: its CHARACTER/FANQIE cells are Big5-encoded
    # (bigchina.inf: "characters in Big5 encoding") — a per-field second
    # encoding lane the starling-dbf family does not have; landing it
    # would also clean stibet's CHIN leads. doc.dbf is a support table
    # (per-character dialect readings), not an etymological base. The
    # follow-up packages' own LEXSTAT/ trees (51 wordlist tables + the
    # sinocalc glottochronology result) stay out: their column sigla need
    # their own language census (below covers IE.exe's LEXSTAT/ only).
    #
    # == The IE package's LEXSTAT/ tables (P113-2)
    #
    # IE.exe ships 13 lexicostatistical tables under LEXSTAT/ (inline-only
    # dBase III — no var-pointers): TEN wide WORDLISTS (balt celt dard germ
    # ind iran mix pi rom slav — one shelf each, one entry per form cell,
    # cognation numbers into the base the .inf names; the shape, grain and
    # language posture live in StarlingLexstat) and THREE Indo-Iranian
    # ETYMOLOGY TABLES — the cognation targets of dard/ind/iran — which
    # are the BASES shape and ride as BASES rows (dir: LEXSTAT):
    #
    #   starling-dardet (inc-dar-pro) — 426 Dardic etymologies (242
    #                    headword-less form-only stubs → "#NUMBER").
    #   starling-indet  (inc-pro)     — 520 Indo-Aryan etymologies.
    #   starling-iranet (ira-pro)     — 498 Iranian etymologies; 18 fully
    #                    empty NUMBER-0 slots mint nothing (the one blank-
    #                    slot rule: NUMBER 0 is no addressable id, and every
    #                    other base carries zero such records — measured).
    #
    # Their per-language cells pair the modern form with its etymon ("sab
    # sarva", "pōst Av. pãsta") — a two-part shape no reflex-minting base
    # has, so they stay body-only (no reflex verdict without a census).
    # PRNUM → piet ("IE etymology", the germet label; censused: 1,004 of
    # 1,004 non-zero links resolve). Column labels are pi.inf's aliases
    # (the three .inf files carry none); iranet's REF column has no alias
    # anywhere and keeps its siglum. None of the 13 .inf files carries a
    # DBINFO compiler credit — the license lane names the IE package's
    # compilers per the descrip.php roster (S. L. Nikolayev & S. A.
    # Starostin), keeping the project mention.
    #
    # P22-0 promised the follow-up bases as CONFIGURATION, not code: BASES
    # rows name every per-base policy (dbf file, headword/gloss/body fields,
    # crosslink labels, reflex columns). P23-0 held that promise with four
    # measured exceptions, each the minimum: the second vendored conversion
    # table (chslav.lst — vasmer's OCS font range; StarlingText loads a table
    # LIST now), the duplicate-NUMBER suffix above (which also unblocks
    # piet's own #574 collision — the owner's live quarantine), the
    # "#NUMBER" placeholder for headword-less records (piet 6 / germet 6 /
    # baltet 7, censused — the second whole-file quarantine class), and the
    # censused STOP_TOKENS gate below.
    #
    # == License (the 2026-07-15 grant — attribution is a hard condition)
    #
    # G. Starostin, e-mail 2026-07-15: "all etymological data are free for
    # anybody to use for any purposes as long as the source is properly
    # acknowledged" — with the EXPRESS condition that attribution name the
    # SPECIFIC compilers of each database (roster:
    # starlingdb.org/descrip.php?lan=en#bases), because the databases are
    # "individual reconstructions with the subjective input of their
    # original creators, and do not always represent the most up-to-date,
    # or the most 'consensus-approved' versions" — the non-consensus caveat
    # rides verbatim in docs/02-sources.md (the Larth-caveat treatment).
    # The per-base credits below quote the roster and the in-package .inf
    # DBINFO texts; they travel in MANIFEST.license, which is the string
    # every serving surface (define/etym/cognates/MCP) renders.
    #
    # == The reflex verdict (censused fixture-first; journaled P22-0/P23-0)
    #
    # piet's branch columns are scholarly prose, not word lists. The honest
    # split: SINGLE-LANGUAGE attested columns (HITT/IND/AVEST/ARM/LAT/ALB)
    # mint ONE DictionaryReflex per cell — the leading citation form only,
    # and only when it IS a clean form token (dialect-prefixed cells like
    # "Khow. yor" and ?-doubt cells mint nothing); lang_code = the RESOLVED
    # catalog tag (P57-5 — the upstream column siglum, ALB/OHG/MEG…, used
    # to leak through verbatim even though this table already resolves the
    # proper code; lang_code now equals language), lang_name = the
    # .inf field alias (feeds the language-names census). GREEK is Latin
    # TRANSCRIPTION (ǟ̂ri — script-mismatched against grc gold), SLAV/BALT/
    # GERM are Nikolayev-notation branch PROTOFORMS (their honest lane is
    # the body plus the SLAVNUM/BALTNUM/GERMNUM links into the subordinate
    # bases), IRAN/ITAL/CELT/TOKH mix languages per cell — none of these
    # mint rows; every column rides the body verbatim either way.
    #
    # P23-0 extends the same discipline: germet's per-language columns are
    # the piet single-language shape and 19 of 21 mint (GOT joins the got
    # gold, OENGL the ang gold; the rest speak the Wiktionary codes the
    # kaikki crosswalk speaks). Bare dialect/variety LABELS lead ~75 cells
    # (CrimGot ×7, NIsl ×20, OGutn ×13, OWFris ×15 …) without the period
    # that self-filtered piet's "Khow." — the censused STOP_TOKENS list
    # gates them (zero piet/pokorny drift, measured). EASTFRIS and OLFRANK
    # stay body-only: variety-ambiguous columns (Fris/WFris/ONFrank/
    # SalFrank label mixes; EASTFRIS is ~47% label-led) — minting would
    # invent language codes. baltet's OLITH/LITH/LETT/OPRUS all mint
    # (96%+ clean, measured); vasmer mints nothing (prose fields only).
    #
    # == Encoding
    #
    # dBase III tables + StarLing-encoded .var text (starling-dbf family:
    # StarlingDbfParser + the table-driven StarlingText decoder; byte
    # meanings come from the vendored unipro.lst + chslav.lst, never
    # guessed — see config/starling/README.md and the fixture README for
    # the live-web verification of every fixture record).
    class Starling < Nabu::Adapter
      MANIFEST = Nabu::SourceManifest.new(
        id: "starling",
        name: "StarLing / Tower of Babel — etymological databases " \
              "(Pokorny IEW + PIET + Vasmer + Germanic + Baltic + Kartvelian + Altaic + " \
              "North Caucasian + Sino-Tibetan + Dravidian + Chukchee-Kamchatkan + Yenisseian + " \
              "IE lexicostatistical wordlists)",
        license: "Free for any use with acknowledgment (G. Starostin, e-mail 2026-07-15: \"all " \
                 "etymological data are free for anybody to use for any purposes as long as the " \
                 "source is properly acknowledged\"); required per-base credit — Pokorny base: " \
                 "\"scanned and recognized by George Starostin (Moscow), who has also added the " \
                 "English meanings\", \"further refurnished and corrected by A. Lubotsky\"; PIE " \
                 "base: \"compiled on the basis of Walde-Pokorny's dictionary by S. L. Nikolayev\", " \
                 "Hittite and Tokharian reflexes added by S. Starostin; Vasmer base: \"scanned, " \
                 "OCR'd, and database-converted versions of M. Vasmer's etymological dictionary of " \
                 "Russian\" (project roster); Germanic base: \"The Common Germanic database, " \
                 "compiled by S. Nikolayev and subordinate to the Common Indo-European database\"; " \
                 "Baltic base: \"The Baltic database, compiled by S. Nikolayev and subordinate to " \
                 "the Proto-Indo-European database\"; Kartvelian base: \"compiled by S. Starostin " \
                 "on the basis of G. Klimov's and Faehnrich-Sardhveladze's etymological " \
                 "dictionaries of Kartvelian languages\" (kartet.inf DBINFO; roster: \"Compiled by " \
                 "Sergei Starostin on the basis of the best comparative Kartvelian dictionaries " \
                 "available (G. Klimov and H. Faehnrich-Z. Sardzhveladze), with notes ... added by " \
                 "Starostin\"); Altaic package: \"the database version of the 'Altaic Etymological " \
                 "Dictionary' by S. Starostin, A. Dybo and O. Mudrak (Brill publishers, 2003)\" " \
                 "(altet.inf DBINFO), the Japanese base being \"the Japanese part of the Altaic " \
                 "Etymological Dictionary\" (japet.inf DBINFO); North Caucasian package: \"the " \
                 "database published as S. L. Nikolayev, S. A. Starostin, 'A North Caucasian " \
                 "Etymological Dictionary', Moscow 1994\" (caucet.inf DBINFO); Sino-Tibetan " \
                 "package: \"based on Peiros-Starostin 1996, but containing improved " \
                 "reconstructions\", \"The Lepcha data were input, and are continued to be input, " \
                 "by Olga Mazo\" (stibet.inf DBINFO); Dravidian package: Proto-Dravidian " \
                 "reconstructions \"as listed in A Dravidian Etymological Dictionary by T. Burrow " \
                 "and M. B. Emeneau, revised and significantly modified by G. Starostin\" " \
                 "(dravet.inf DBINFO); Chukchee-Kamchatkan package: \"O. Mudrak's " \
                 "Chukchee-Kamchatkan database\" with his subordinate Chukchee-Koryak and Itelmen " \
                 "databases (kamet/chuket/itelet.inf DBINFO); Yenisseian package: \"Comparative " \
                 "vocabulary of the Yenisseian languages, published as Starostin 1995\" " \
                 "(yenet.inf DBINFO); IE package lexicostatistical tables (IE.exe LEXSTAT/: ten " \
                 "110-item wordlists with per-form cognation numbers into the PIE, Germanic and " \
                 "Baltic databases, and three Indo-Iranian etymology tables dardet/indet/iranet; " \
                 "their .inf files carry no DBINFO, so the credit is the package's — " \
                 "S. L. Nikolayev & S. A. Starostin — the StarLing Indo-European package " \
                 "(Tower of Babel / StarLing project), starlingdb.org; roster: \"Indo-European " \
                 "etymology: Compiled by Sergei Nikolayev on the basis of A. Walde and J. Pokorny's " \
                 "dictionary, with Anatolian (Hittite) and Tocharian material added in by S. Nikolayev " \
                 "and S. Starostin. Subordinate databases include Germanic and Baltic (also compiled " \
                 "by S. Nikolayev)\")",
        license_class: "attribution",
        upstream_url: "https://starlingdb.org/download/IE.exe",
        parser_family: "starling-dbf"
      )

      # The second package (P46-6): the Kartvelian etymological dictionary,
      # same starlingdb.org download shelf, same 2026-07-15 grant. A plain
      # zip despite the name, like IE.exe (206 KB; kartet.dbf/.var/.inf +
      # a LEXSTAT Swadesh table). Fetched into KART_SUBDIR with its own
      # ZipFetch state so each package's retention sweep sees only itself.
      KART_URL = "https://starlingdb.org/download/KART.exe"
      KART_SUBDIR = "kart"

      # Every follow-up package (P46-6 kart; P104-3 the six further
      # downloads), subdir => url. Each is a plain zip despite the .exe
      # name, fetched into its own subdir with its own ZipFetch state and
      # attic; the root IE.exe fetch declares keep: on all of them so a
      # re-fetch of one package never attics another. LEXSTAT/ trees ride
      # along inside each zip (out of scope here; their tables are a
      # separate lane).
      FOLLOW_UP_PACKAGES = {
        KART_SUBDIR => KART_URL,
        "altaic" => "https://starlingdb.org/download/ALTAIC.exe",
        "cauc" => "https://starlingdb.org/download/CAUC.exe",
        "sintib" => "https://starlingdb.org/download/SINTIB.exe",
        "drav" => "https://starlingdb.org/download/DRAV.exe",
        "chukchee" => "https://starlingdb.org/download/CHUKCHEE.exe",
        "yenisey" => "https://starlingdb.org/download/YENISEY.exe"
      }.freeze

      # Per-base ingestion policy (registry order = discover order). Labels
      # are the upstream .inf field aliases verbatim; :crosslinks maps a
      # numeric link column to its alias ("#%s" fills the target record
      # NUMBER — pokorny⇄piet numbers are the entry ids of these shelves);
      # :reflexes maps a branch column to [catalog language, .inf alias].
      BASES = {
        "starling-pokorny" => {
          dbf: "pokorny.dbf", language: "ine-pro",
          title: "Pokorny, Indogermanisches Etymologisches Wörterbuch " \
                 "(StarLing digitization: G. Starostin, corr. A. Lubotsky)",
          headword: "ROOT", gloss: "MEANING",
          body: {
            "GER_MEAN" => "German meaning", "GRAMMAR" => "Grammatical comments",
            "COMMENTS" => "General comments", "DERIVATIVE" => "Derivatives",
            "MATERIAL" => "Material", "REF" => "References",
            "SEEALSO" => "See also", "PAGES" => "Pages"
          }.freeze,
          crosslinks: { "PIET" => "PIE database" }.freeze,
          reflexes: {}.freeze
        }.freeze,
        "starling-piet" => {
          dbf: "piet.dbf", language: "ine-pro",
          title: "Indo-European etymology (PIET: S. L. Nikolayev, after Walde-Pokorny; " \
                 "Hitt./Tokh. by S. Starostin)",
          headword: "PROTO", gloss: "MEANING",
          body: {
            "RUSMEAN" => "Russ. meaning", "HITT" => "Hittite", "IND" => "Old Indian",
            "AVEST" => "Avestan", "IRAN" => "Other Iranian", "ARM" => "Armenian",
            "GREEK" => "Old Greek", "SLAV" => "Slavic", "BALT" => "Baltic",
            "GERM" => "Germanic", "LAT" => "Latin", "ITAL" => "Other Italic",
            "CELT" => "Celtic", "ALB" => "Albanian", "TOKH" => "Tokharian",
            "COMMENT" => "Comments", "REFER" => "References"
          }.freeze,
          crosslinks: {
            "REFERNUM" => "Pokorny", "PRNUM" => "Nostratic etymology", "SLAVNUM" => "Vasmer",
            "BALTNUM" => "Baltic etymology", "GERMNUM" => "Germanic etymology"
          }.freeze,
          reflexes: {
            "HITT" => %w[hit Hittite].freeze, "IND" => ["san", "Old Indian"].freeze,
            "AVEST" => %w[ae Avestan].freeze, "ARM" => %w[xcl Armenian].freeze,
            "LAT" => %w[lat Latin].freeze, "ALB" => %w[sq Albanian].freeze
          }.freeze
        }.freeze,
        # P23-0. vasmer.inf is BLANK: labels are the live CGI's own field
        # labels (web-verified on #20, 2026-07-15); prose fields, no reflex
        # columns, no numeric links (the shelf is piet's SLAVNUM target).
        "starling-vasmer" => {
          dbf: "vasmer.dbf", language: "rus",
          title: "Vasmer's dictionary (M. Vasmer, Russian etymological dictionary, Trubachev edition; " \
                 "StarLing scan/OCR digitization)",
          headword: "WORD", gloss: nil,
          body: {
            "GENERAL" => "Near etymology", "ORIGIN" => "Further etymology",
            "TRUBACHEV" => "Trubachev's comments", "EDITORIAL" => "Editorial comments",
            "PAGES" => "Pages"
          }.freeze,
          crosslinks: {}.freeze,
          reflexes: {}.freeze
        }.freeze,
        # P23-0. Labels/credit: germet.inf. Reflex codes: got/ang are this
        # catalog's gold tags; the rest are the Wiktionary codes the kaikki
        # crosswalk speaks. EASTFRIS/OLFRANK body-only (variety-ambiguous).
        "starling-germet" => {
          dbf: "germet.dbf", language: "gem-pro",
          title: "Germanic etymology (Common Germanic database: S. Nikolayev, " \
                 "subordinate to the PIE database)",
          headword: "PROTO", gloss: "MEANING",
          body: {
            "GOT" => "Gothic", "ONORD" => "Old Norse", "NORW" => "Norwegian",
            "OSWED" => "Old Swedish", "SWED" => "Swedish", "ODAN" => "Old Danish",
            "DAN" => "Danish", "OENGL" => "Old English", "MENGL" => "Middle English",
            "ENGL" => "English", "OFRIS" => "Old Frisian", "EASTFRIS" => "East Frisian",
            "OSAX" => "Old Saxon", "MDUTCH" => "Middle Dutch", "DUTCH" => "Dutch",
            "OLFRANK" => "Old Franconian", "MLG" => "Middle Low German",
            "LG" => "Low German", "OHG" => "Old High German",
            "MHG" => "Middle High German", "HG" => "German", "NOTES" => "Comments"
          }.freeze,
          crosslinks: { "PRNUM" => "IE etymology" }.freeze,
          reflexes: {
            "GOT" => %w[got Gothic].freeze, "ONORD" => ["non", "Old Norse"].freeze,
            "NORW" => %w[no Norwegian].freeze, "OSWED" => ["gmq-osw", "Old Swedish"].freeze,
            "SWED" => %w[sv Swedish].freeze, "ODAN" => ["gmq-oda", "Old Danish"].freeze,
            "DAN" => %w[da Danish].freeze, "OENGL" => ["ang", "Old English"].freeze,
            "MENGL" => ["enm", "Middle English"].freeze, "ENGL" => %w[en English].freeze,
            "OFRIS" => ["ofs", "Old Frisian"].freeze, "OSAX" => ["osx", "Old Saxon"].freeze,
            "MDUTCH" => ["dum", "Middle Dutch"].freeze, "DUTCH" => %w[nl Dutch].freeze,
            "MLG" => ["gml", "Middle Low German"].freeze, "LG" => ["nds", "Low German"].freeze,
            "OHG" => ["goh", "Old High German"].freeze,
            "MHG" => ["gmh", "Middle High German"].freeze, "HG" => %w[de German].freeze
          }.freeze
        }.freeze,
        # P23-0. Labels/credit: baltet.inf (PRNUM's alias there is the long
        # form, "Indo-European etymology" — the live CGI renders the same).
        "starling-baltet" => {
          dbf: "baltet.dbf", language: "bat-pro",
          title: "Baltic etymology (Baltic database: S. Nikolayev, subordinate to the PIE database)",
          headword: "PROTO", gloss: "MEANING",
          body: {
            "OLITH" => "Old Lithuanian", "LITH" => "Lithuanian", "LETT" => "Lettish",
            "OPRUS" => "Old Prussian", "NOTES" => "Comments"
          }.freeze,
          crosslinks: { "PRNUM" => "Indo-European etymology" }.freeze,
          reflexes: {
            "OLITH" => ["olt", "Old Lithuanian"].freeze, "LITH" => %w[lt Lithuanian].freeze,
            "LETT" => %w[lv Lettish].freeze, "OPRUS" => ["prg", "Old Prussian"].freeze
          }.freeze
        }.freeze,
        # P46-6. Labels: kartet.inf aliases verbatim. All four Kartvelian
        # columns are single-language attested columns and mint (censused on
        # the full base: GRU 1,241 / MEG 1,010 / SVA 659 / LAZ 722 non-empty
        # cells); the per-column Rus./Engl. meaning fields ride the body.
        # PRNUM points into the unheld Nostratic base — body line only.
        "starling-kart" => {
          dbf: "kartet.dbf", language: "ccs-pro",
          title: "Kartvelian etymology (S. Starostin, after G. Klimov and " \
                 "Faehnrich-Sardshveladze; StarLing database)",
          headword: "PROTO", gloss: "MEANING",
          body: {
            "RUSMEAN" => "Russian meaning", "GRU" => "Georgian",
            "GRMEAN" => "Georgian meaning (Rus.)", "EGRMEAN" => "Georgian meaning (Engl.)",
            "MEG" => "Megrel", "MGMEAN" => "Megrel meaning (Rus.)",
            "EMGMEAN" => "Megrel meaning (Eng.)", "SVA" => "Svan",
            "SVMEAN" => "Svan meaning (Rus.)", "ESVMEAN" => "Svan meaning (Eng.)",
            "LAZ" => "Laz", "LZMEAN" => "Laz meaning (Rus.)", "ELZMEAN" => "Laz meaning (Eng.)",
            "NOTES" => "Notes and references"
          }.freeze,
          crosslinks: { "PRNUM" => "Nostratic etymology" }.freeze,
          reflexes: {
            "GRU" => %w[ka Georgian].freeze, "MEG" => %w[xmf Megrel].freeze,
            "SVA" => %w[sva Svan].freeze, "LAZ" => %w[lzz Laz].freeze
          }.freeze
        }.freeze,
        # P104-3 (ALTAIC). Labels/credit: altet.inf. All five branch
        # columns are branch protoforms — body-only; the link aliases
        # ("Turk.->Turcet" …) are the .inf's own, verbatim. PRNUM points
        # into the unheld Nostratic base.
        "starling-altet" => {
          dbf: "altet.dbf", language: "tut-pro",
          title: "Altaic etymology (S. Starostin, A. Dybo, O. Mudrak, Altaic Etymological " \
                 "Dictionary, Brill 2003; StarLing database)",
          headword: "PROTO", gloss: "MEANING",
          body: {
            "RUSMEAN" => "Russian meaning", "TURC" => "Turkic", "MONG" => "Mongolian",
            "TUNG" => "Tungus-Manchu", "KOR" => "Korean", "JAP" => "Japanese",
            "REFERENCE" => "Comments"
          }.freeze,
          crosslinks: {
            "PRNUM" => "Nostratic", "TURCNUM" => "Turk.->Turcet", "MONGNUM" => "Mong.->Monget",
            "TUNGNUM" => "Tung.->Tunget", "KORNUM" => "Kor.->Koret", "JAPNUM" => "Jpn.->Japet"
          }.freeze,
          reflexes: {}.freeze
        }.freeze,
        # P104-3 (ALTAIC). Labels: japet.inf. AJP is the one ATTESTED
        # single-language column (Old Japanese, 8th c.) and mints ojp;
        # MJP has no clean code, the modern dialect columns are accent
        # transcriptions — body-only. PRNUM crosslinks into altet (held).
        "starling-japet" => {
          dbf: "japet.dbf", language: "jpx-pro",
          title: "Japanese etymology (the Japanese part of the Altaic Etymological Dictionary; " \
                 "Proto-Japanese after Starostin 1975)",
          headword: "PROTO", gloss: "MEANING",
          body: {
            "RUSMEAN" => "Russian meaning", "AJP" => "Old Japanese", "MJP" => "Middle Japanese",
            "TOK" => "Tokyo", "KYO" => "Kyoto", "KAG" => "Kagoshima", "NAS" => "Nase",
            "SHU" => "Shuri", "HAT" => "Hateruma", "YON" => "Yonakuni", "COMMENTS" => "Comments"
          }.freeze,
          crosslinks: { "PRNUM" => "Altaic etymology" }.freeze,
          reflexes: { "AJP" => ["ojp", "Old Japanese"].freeze }.freeze
        }.freeze,
        # P104-3 (CAUC). Labels/credit: caucet.inf. Six branch protoform
        # columns body-only; LAK/KHIN hold ACTUAL Lak/Khinalug forms
        # (caucet.inf DBINFO: "The actual Lak form (no Proto-Lak
        # reconstruction is presented)"; likewise Khinalug) — they mint,
        # under the DBINFO's honest names rather than the aliases'
        # "Proto-" labels. PRNUM points into the unheld sccet base.
        "starling-caucet" => {
          dbf: "caucet.dbf", language: "ccn-pro",
          title: "North Caucasian etymology (S. L. Nikolayev, S. A. Starostin, A North Caucasian " \
                 "Etymological Dictionary, Moscow 1994; StarLing database)",
          headword: "PROTO", gloss: "MEANING",
          body: {
            "NAKH" => "Proto-Nakh", "AAND" => "Proto-Avaro-Andian", "CEZ" => "Proto-Tsezian",
            "LAK" => "Proto-Lak", "DARG" => "Proto-Dargwa", "LEZG" => "Proto-Lezghian",
            "KHIN" => "Proto-Khinalug", "ABAD" => "Proto-West Caucasian", "COMMENT" => "Notes"
          }.freeze,
          crosslinks: {
            "PRNUM" => "Sino-Caucasian etymology", "NAKHNUM" => "> Nakh",
            "AANDNUM" => "> Avaro-Andian", "CEZNUM" => "> Tsezi", "LAKNUM" => "> Lak",
            "DARGNUM" => "> Dargwa", "LEZGNUM" => "> Lezghian", "KHINNUM" => "> Khinalug",
            "ABADNUM" => "> West Caucasian"
          }.freeze,
          reflexes: { "LAK" => %w[lbe Lak].freeze, "KHIN" => %w[kjj Khinalug].freeze }.freeze
        }.freeze,
        # P104-3 (SINTIB). Labels/credit: stibet.inf. LEPCHA mints lep;
        # TIB is transliteration (script-mismatched against the
        # Tibetan-script gold — the piet GREEK treatment), CHIN is the OC
        # reconstruction led by a Big5 character, BURM/LUSH mix in
        # PLB/PKC protoforms, KACH carries tone-digit notation, KIR is a
        # branch protoform — body-only. The unaliased STLSNUM (lexstat
        # link) rides nowhere; CHINNUM/KIRNUM point into the DEFERRED
        # bigchina/kiret bases, PRNUM into the unheld sccet base.
        "starling-stibet" => {
          dbf: "stibet.dbf", language: "sit-pro",
          title: "Sino-Tibetan etymology (Peiros-Starostin 1996 with improved reconstructions; " \
                 "Lepcha data by Olga Mazo; StarLing database)",
          headword: "PROTO", gloss: "MEANING",
          body: {
            "CHIN" => "Chinese", "TIB" => "Tibetan", "BURM" => "Burmese", "KACH" => "Kachin",
            "LUSH" => "Lushai", "LEPCHA" => "Lepcha", "KIR" => "Kiranti", "COMMENTS" => "Comments"
          }.freeze,
          crosslinks: {
            "PRNUM" => "Sino-Caucasian etymology", "CHINNUM" => "Old Chinese etymology",
            "KIRNUM" => "Kiranti etymology"
          }.freeze,
          reflexes: { "LEPCHA" => %w[lep Lepcha].freeze }.freeze
        }.freeze,
        # P104-3 (DRAV). Labels/credit: dravet.inf. Five branch protoform
        # columns body-only; BRA (Brahui, an actual language) mints brh.
        # PRNUM points into the unheld Nostratic base; the six branch
        # links point into the DEFERRED branch bases.
        "starling-dravet" => {
          dbf: "dravet.dbf", language: "dra-pro",
          title: "Dravidian etymology (Burrow-Emeneau DED reconstructions, revised and " \
                 "significantly modified by G. Starostin; StarLing database)",
          headword: "PROTO", gloss: "MEANING",
          body: {
            "SDR" => "Proto-South Dravidian", "TEL" => "Proto-Telugu",
            "KOGA" => "Proto-Kolami-Gadba", "GND" => "Proto-Gondi-Kui",
            "NDR" => "Proto-North Dravidian", "BRA" => "Brahui", "NOTES" => "Notes"
          }.freeze,
          crosslinks: {
            "PRNUM" => "Nostratic etymology", "SDRNUM" => "South Dravidian etymology",
            "TELNUM" => "Telugu etymology", "KOGANUM" => "Kolami-Gadba etymology",
            "GNDNUM" => "Gondi-Kui etymology", "NDRNUM" => "North Dravidian etymology",
            "BRANUM" => "Brahui etymology"
          }.freeze,
          reflexes: { "BRA" => %w[brh Brahui].freeze }.freeze
        }.freeze,
        # P104-3 (CHUKCHEE). Labels/credit: kamet.inf (O. Mudrak; Russian
        # glosses — upstream: "no English translation is available yet",
        # the vasmer precedent). CHUK/ITEL are branch protoforms linking
        # into the two held subordinates; PRNUM points into the unheld
        # Nostratic base, NIODNUM into the unheld Nivkh-Yukaghir base.
        "starling-kamet" => {
          dbf: "kamet.dbf", language: "qfa-cka-pro",
          title: "Chukchee-Kamchatkan etymology (O. Mudrak's Chukchee-Kamchatkan database; StarLing)",
          headword: "PROTO", gloss: "MEANING",
          body: {
            "CHUK" => "Proto-Chukchee-Koryak", "ITEL" => "Proto-Itelmen",
            "COMMENTS" => "Comments", "NIOD" => "Nivkh parallels"
          }.freeze,
          crosslinks: {
            "PRNUM" => "Nostratic etymology", "CHUKNUM" => "> Chukchee-Koryak",
            "ITELNUM" => "> Itelmen", "NIODNUM" => "> Nivkh-Yukaghir"
          }.freeze,
          reflexes: {}.freeze
        }.freeze,
        # P104-3 (CHUKCHEE). Labels: chuket.inf; body fields follow its
        # field_list (the unaliased STPRO/CHFUNC/KOFUNC/ALFUNC columns sit
        # outside it and ride nowhere). CHU/KOR/ALU are actual single
        # languages and mint; PAL (Palana, a Koryak variety without a
        # code of its own) stays body-only. PRNUM crosslinks into kamet.
        "starling-chuket" => {
          dbf: "chuket.dbf", language: "qfa-chk-pro",
          title: "Chukchee-Koryak etymology (O. Mudrak; subordinate to the Chukchee-Kamchatkan " \
                 "database; StarLing)",
          headword: "PROTO", gloss: "MEANING",
          body: {
            "CHU" => "Chukchee", "KOR" => "Koryak", "PAL" => "Palana", "ALU" => "Alutor",
            "IM" => "Muravyeva reference", "BOG" => "Bogoraz reference (LRS)",
            "RKS" => "Russian-Koryak dictionary (Zhukova)", "NRS" => "Korsakov reference (NRS)",
            "YFA" => "Language and Folklore of Alutors reference", "PAK" => "Zhukova reference (LPK)",
            "COMMENTS" => "Comments", "NIOD" => "Nivkh parallels", "EXT" => "External parallels"
          }.freeze,
          crosslinks: {
            "PRNUM" => "Chukchee-Kamchatkan etymology", "NIODNUM" => "Nivkh-Yukaghir etymology"
          }.freeze,
          reflexes: {
            "CHU" => %w[ckt Chukchee].freeze, "KOR" => %w[kpy Koryak].freeze,
            "ALU" => %w[alr Alutor].freeze
          }.freeze
        }.freeze,
        # P104-3 (CHUKCHEE). Labels: itelet.inf; body fields follow its
        # field_list (the unaliased ICOST/WCOST columns ride nowhere).
        # ITE (Napana Itelmen) mints itl; Kovran/Stebnitski variants and
        # Dybowski's extinct Western/Southern Kamchadal records stay
        # body-only (no codes exist). PRNUM crosslinks into kamet.
        "starling-itelet" => {
          dbf: "itelet.dbf", language: "itl-pro",
          title: "Itelmen etymology (O. Mudrak; subordinate to the Chukchee-Kamchatkan database; " \
                 "StarLing)",
          headword: "PROTO", gloss: "MEANING",
          body: {
            "ITE" => "Itelmen (Napana)", "ITRUSL" => "Itelmen (Kovran)",
            "STBIT" => "Itelmen (Stebnitski)", "ITEMEA" => "Itelmen meaning",
            "WIT" => "Western Kamchadal", "WITMEA" => "West Kamchadal meaning",
            "WITMEP" => "West Kamchadal meaning (Polish)", "SIT" => "Southern Kamchadal",
            "SITMEA" => "South Kamchadal meaning (Latin)",
            "SITMEP" => "South Kamchadal meaning (Polish)", "VOL" => "Volodin 1976 (IL)",
            "IRSLOV" => "Khaloymova (IRS)", "VZHU" => "Volodin-Zhukova reference",
            "STEB" => "Stebnitski reference", "WDYB" => "Number in Dybowsky (WK)",
            "SDYB" => "Number in Dybowsky (SK)", "COMMENTS" => "Comments",
            "NIOD" => "Nivkh parallels", "EXT" => "External parallels"
          }.freeze,
          crosslinks: {
            "PRNUM" => "Chukchee-Kamchatkan etymology", "NIODNUM" => "Nivkh-Yukaghir etymology"
          }.freeze,
          reflexes: { "ITE" => ["itl", "Itelmen (Napana)"].freeze }.freeze
        }.freeze,
        # P104-3 (YENISEY). Labels/credit: yenet.inf (Russian glosses).
        # All five columns are actual single languages and mint. PRNUM
        # points into the unheld sccet base.
        "starling-yenet" => {
          dbf: "yenet.dbf", language: "qfa-yen-pro",
          title: "Yenisseian etymology (Comparative vocabulary of the Yenisseian languages, " \
                 "Starostin 1995; StarLing database)",
          headword: "PROTO", gloss: "MEANING",
          body: {
            "KET" => "Ket", "SYM" => "Yug", "KOT" => "Kottish", "ARI" => "Arin",
            "PUM" => "Pumpokol", "NOTES" => "Comments"
          }.freeze,
          crosslinks: { "PRNUM" => "Sino-Caucasian etymology" }.freeze,
          reflexes: {
            "KET" => %w[ket Ket].freeze, "SYM" => %w[yug Yug].freeze,
            "KOT" => %w[zko Kottish].freeze, "ARI" => %w[xrn Arin].freeze,
            "PUM" => %w[xpm Pumpokol].freeze
          }.freeze
        }.freeze,
        # P113-2 (IE.exe LEXSTAT/). The three Indo-Iranian etymology tables
        # — the cognation targets of the dard/ind/iran wordlists. Labels:
        # pi.inf's aliases (their own .inf files carry none); body-only
        # (form + etymon cells); PRNUM → piet. inc-dar-pro follows the
        # family-code + -pro convention on Wiktionary's inc-dar.
        "starling-dardet" => {
          dbf: "dardet.dbf", dir: StarlingLexstat::DIR, language: "inc-dar-pro",
          title: "Dardic etymology (StarLing IE package LEXSTAT/dardet: the cognation base of " \
                 "the Dardic wordlist)",
          headword: "PROTO", gloss: "MEANING",
          body: StarlingLexstat.labels(%w[KSM BSK TOR MAY SHN PHL SAV TIR GAW SHU WOT PSH KHO KAL]),
          crosslinks: { "PRNUM" => "IE etymology" }.freeze,
          reflexes: {}.freeze
        }.freeze,
        "starling-indet" => {
          dbf: "indet.dbf", dir: StarlingLexstat::DIR, language: "inc-pro",
          title: "Indo-Aryan etymology (StarLing IE package LEXSTAT/indet: the cognation base of " \
                 "the Indo-Aryan wordlist)",
          headword: "PROTO", gloss: "MEANING",
          body: StarlingLexstat.labels(%w[HND PNJ LHD SND GUJ MAR BNG ASS NEP SNG WPH]),
          crosslinks: { "PRNUM" => "IE etymology" }.freeze,
          reflexes: {}.freeze
        }.freeze,
        "starling-iranet" => {
          dbf: "iranet.dbf", dir: StarlingLexstat::DIR, language: "ira-pro",
          title: "Iranian etymology (StarLing IE package LEXSTAT/iranet: the cognation base of " \
                 "the Iranian wordlist)",
          headword: "PROTO", gloss: "MEANING",
          body: StarlingLexstat.labels(%w[CPE TAT KRD BAL TAL AFG MNJ SHG WKH ISH OSS]).merge("REF" => "REF").freeze,
          crosslinks: { "PRNUM" => "IE etymology" }.freeze,
          reflexes: {}.freeze
        }.freeze
      }.freeze

      # A clean leading citation form: letters first, then letters/marks and
      # the notation the bases use inside forms (optional-segment parens,
      # morpheme hyphens/equals, variant slashes, apostrophe palatals) — and
      # never a trailing period (that is an abbreviation, not a form).
      CITATION_FORM = %r{\A\*?[\p{L}\p{M}][\p{L}\p{M}'’\-/=()\[\]]*\z}
      private_constant :CITATION_FORM

      # The censused dialect/variety LABELS that lead germet cells without
      # the abbreviating period (piet's "Khow." self-filtered; "CrimGot
      # marzus" would sail through CITATION_FORM). A cell led by one of
      # these mints nothing — the label is not a citation form. Every token
      # was censused over the full 2005 corpus (P23-0): Crimean Gothic /
      # Burgundian / Latin-attested leads in GOT; New Icelandic / North
      # Germanic / Old Norwegian in ONORD; Old Gutnish ("Outn" is its
      # upstream typo) / Middle Swedish / runic / personal-name leads in
      # OSWED-ODAN-SWED; West/East Old Frisian in OFRIS; Old Low German /
      # Middle Low German leads in MLG; Early Middle Dutch in MDUTCH;
      # Langobardic / "Lat-OHG" / name-label "N" in OHG; Early High German
      # in MHG; lowercase "dial" in SWED. Zero collisions with a legitimate
      # leading citation form anywhere in the package, and zero piet/pokorny
      # drift — both measured.
      STOP_TOKENS = %w[
        CrimGot Burg Burgund Lat NIsl NGerm ONorw OGutn Outn MSw Run PN ON
        dial OWFris OWFRis OFr OEFRis OEFris Fris OLG MLG EMDutch EaHG
        Langob Lat-OHG N
      ].to_set.freeze
      private_constant :STOP_TOKENS

      # The rider (P18 strategy): what this source witnesses about each
      # shelf language, accreted as dossier sections with per-record
      # provenance "starling".
      LANGUAGE_NOTES = [
        ["ine-pro", "witness:starling",
         "StarLing/Tower of Babel IE bases (G. Starostin's 2026-07-15 any-use-with-acknowledgment " \
         "grant): Pokorny's IEW complete (2,222 roots, the G. Starostin-scanned, Lubotsky-corrected " \
         "digitization) beside S. L. Nikolayev's Walde-Pokorny-based PIE database (3,291 " \
         "etymologies, traditional laryngeal-free notation, per-branch reflex columns with " \
         "S. Starostin's Hittite/Tocharian additions) — Moscow-school witnesses beside " \
         "kaikki/LIV/IE-CoR, expressly \"individual reconstructions\" that \"do not always " \
         "represent the most up-to-date, or the most 'consensus-approved' versions\" (Starostin)."].freeze,
        ["rus", "witness:starling",
         "StarLing/Tower of Babel Vasmer base (same grant): M. Vasmer's etymological dictionary " \
         "of Russian in the Trubachev Russian edition — 18,239 entries scanned, OCR'd and " \
         "database-converted by the project, with Trubachev's bracketed additions and editorial " \
         "comments as separate fields; the roster notes it \"currently serving as a substitute " \
         "for the comparative Slavic database\", and PIET's Slavic links point into it. Old " \
         "Cyrillic citations ride the Church Slavonic font range (decoded via chslav.lst)."].freeze,
        ["gem-pro", "witness:starling",
         "StarLing/Tower of Babel Common Germanic database (S. Nikolayev; same grant): 1,994 " \
         "Proto-Germanic etymologies in Nikolayev notation (*xálsa-z), subordinate to the PIE " \
         "database, with per-language columns from Gothic and Old Norse to modern German — a " \
         "Moscow-school gem-pro witness beside the kaikki Proto-Germanic shelf; Gothic and Old " \
         "English columns join this catalog's got/ang gold lemmas."].freeze,
        ["bat-pro", "witness:starling",
         "StarLing/Tower of Babel Baltic database (S. Nikolayev; same grant): 1,651 Proto-Baltic " \
         "etymologies subordinate to the PIE database, with Old Lithuanian/Lithuanian/Lettish/" \
         "Old Prussian reflex columns — this library's first Proto-Baltic shelf. The tag bat-pro " \
         "is minted by the family-code + -pro convention (Wiktionary reconstructs Balto-Slavic, " \
         "ine-bsl-pro, not Proto-Baltic — no upstream shelf to unify with)."].freeze,
        ["ccs-pro", "witness:starling",
         "StarLing/Tower of Babel Kartvelian database (S. Starostin; same grant, P46-6): 1,310 " \
         "Proto-Kartvelian etymologies compiled \"on the basis of G. Klimov's and " \
         "Faehnrich-Sardhveladze's etymological dictionaries of Kartvelian languages\" — Klimov's " \
         "reconstruction preferred verbatim, Fähnrich–Sardshveladze's where Klimov is silent, " \
         "with Georgian/Megrel/Svan/Laz reflex columns and Nostratic crosslinks (unheld base, " \
         "body lines). This library's first Kartvelian shelf; ccs-pro is minted by the " \
         "family-code + -pro convention (ISO 639-5 ccs — the bat-pro precedent)."].freeze,
        # P104-3: one honest witness note per new shelf language.
        ["tut-pro", "witness:starling",
         "StarLing/Tower of Babel Altaic database (same grant, P104-3): the database version of " \
         "the Starostin-Dybo-Mudrak Altaic Etymological Dictionary (Brill 2003) — 2,805 " \
         "Proto-Altaic etymologies with Turkic/Mongolian/Tungus-Manchu/Korean/Japanese branch " \
         "protoform columns and links into the five branch databases (this catalog holds the " \
         "Japanese one). The Altaic macro-family is the Moscow school's own hypothesis — " \
         "expressly an \"individual reconstruction\" under the grant's caveat; tut-pro is minted " \
         "by the family-code + -pro convention (ISO 639-5 tut — the bat-pro/ccs-pro precedent)."].freeze,
        ["jpx-pro", "witness:starling",
         "StarLing/Tower of Babel Japanese database (same grant, P104-3): \"the Japanese part of " \
         "the Altaic Etymological Dictionary\" — 1,705 Proto-Japanese etymologies, the accent " \
         "reconstruction based on Starostin 1975 (\"very similar to ... Martin 1987\", the .inf), " \
         "with Old Japanese (8th c.), Middle Japanese and seven modern dialect/Ryukyuan columns " \
         "(Tokyo/Kyoto/Kagoshima/Nase/Shuri/Hateruma/Yonakuni); the Old Japanese column joins " \
         "the ojp lane. jpx-pro is the Wiktionary Proto-Japonic code."].freeze,
        ["ccn-pro", "witness:starling",
         "StarLing/Tower of Babel North Caucasian database (same grant, P104-3): the published " \
         "Nikolayev-Starostin \"A North Caucasian Etymological Dictionary\" (Moscow 1994) — " \
         "2,327 Proto-North-Caucasian etymologies (often reconstructed at the Proto-East-" \
         "Caucasian level, the DBINFO notes) with Nakh/Avaro-Andian/Tsezian/Lak/Dargwa/Lezghian/" \
         "Khinalug/West-Caucasian columns; Lak and Khinalug are actual attested forms and mint " \
         "reflex rows. The North Caucasian unity is the Moscow school's own claim (the grant's " \
         "non-consensus caveat rides); ccn-pro is minted by the family-code + -pro convention " \
         "(ISO 639-5 ccn — the ccs-pro sibling)."].freeze,
        ["sit-pro", "witness:starling",
         "StarLing/Tower of Babel Sino-Tibetan database (same grant, P104-3): 2,823 " \
         "Proto-Sino-Tibetan etymologies \"based on Peiros-Starostin 1996, but containing " \
         "improved reconstructions\", with Old Chinese (Starostin 1989 reconstruction, " \
         "Big5-led cells), Classical Tibetan and Burmese transliterations, Kachin/Lushei/" \
         "Lepcha (Olga Mazo's input) columns and Kiranti + Old Chinese database links " \
         "(bigchina/kiret deferred). sit-pro is the Wiktionary Proto-Sino-Tibetan code."].freeze,
        ["dra-pro", "witness:starling",
         "StarLing/Tower of Babel Dravidian database (same grant, P104-3): 2,171 Proto-Dravidian " \
         "reconstructions \"generated according to the basic correspondence system as listed in " \
         "A Dravidian Etymological Dictionary by T. Burrow and M. B. Emeneau, revised and " \
         "significantly modified by G. Starostin\" (his comparative-Dravidian phonology rides " \
         "the .inf), with South-Dravidian/Telugu/Kolami-Gadba/Gondi-Kui/North-Dravidian branch " \
         "links and a minting Brahui column. dra-pro is the Wiktionary Proto-Dravidian code."].freeze,
        ["qfa-cka-pro", "witness:starling",
         "StarLing/Tower of Babel Chukchee-Kamchatkan database (same grant, P104-3): O. Mudrak's " \
         "family-head database — 1,099 Proto-Chukchee-Kamchatkan reconstructions with " \
         "Chukchee-Koryak and Itelmen branch protoform columns linking into the two subordinate " \
         "bases (both held), Nivkh parallels, and Russian glosses (upstream: \"no English " \
         "translation is available yet\"). qfa-cka-pro follows Wiktionary's qfa-cka family code " \
         "(Chukotko-Kamchatkan has no ISO 639-5 code)."].freeze,
        ["qfa-chk-pro", "witness:starling",
         "StarLing/Tower of Babel Chukchee-Koryak database (same grant, P104-3): O. Mudrak's " \
         "subordinate branch base — 2,281 Chukchee-Koryak (Chukotkan) reconstructions with " \
         "Chukchee/Koryak/Palana/Alutor columns (ckt/kpy/alr mint; Palana is a Koryak variety " \
         "without a code) and per-source reference columns (Muravyeva, Bogoraz, Zhukova …). " \
         "qfa-chk is coined in Wiktionary's qfa- style — neither ISO 639-5 nor Wiktionary names " \
         "the Chukotkan branch."].freeze,
        ["itl-pro", "witness:starling",
         "StarLing/Tower of Babel Itelmen database (same grant, P104-3): O. Mudrak's subordinate " \
         "branch base — 1,673 Proto-Itelmen reconstructions with Napana/Kovran/Stebnitski " \
         "Itelmen columns (itl mints) and Dybowski's records of the extinct Western and " \
         "Southern Kamchadal (with Latin and Polish glosses — body-only, no codes exist). " \
         "itl-pro is a pro stage on the itl anchor (the gmq:pro shape: the proto of the " \
         "Kamchatkan branch, whose sole survivor is Itelmen)."].freeze,
        ["qfa-yen-pro", "witness:starling",
         "StarLing/Tower of Babel Yenisseian database (same grant, P104-3): the comparative " \
         "vocabulary published as Starostin 1995 — 1,059 Proto-Yenisseian reconstructions with " \
         "Ket/Yug/Kottish/Arin/Pumpokol columns (all five mint; Yug is treated \"as a separate " \
         "language rather than just a Ket dialect\", the .inf) and Sino-Caucasian links (unheld " \
         "base, body lines); Russian glosses. qfa-yen-pro is the Wiktionary Proto-Yeniseian " \
         "code."].freeze,
        # P113-2: the IE package's three LEXSTAT etymology tables.
        ["inc-pro", "witness:starling",
         "StarLing/Tower of Babel IE package, LEXSTAT/indet (same grant, P113-2): 520 Indo-Aryan " \
         "etymologies — the cognation base of the package's Indo-Aryan lexicostatistical " \
         "wordlist, each reconstruction with Hindi/Panjabi/Lahnda/Sindhi/Gujarati/Marathi/" \
         "Bengali/Assamese/Nepali/Sinhalese/West Pahari forms paired with their Old Indian " \
         "etymon, linked into the PIE database. inc-pro is the Wiktionary Proto-Indo-Aryan code."].freeze,
        ["ira-pro", "witness:starling",
         "StarLing/Tower of Babel IE package, LEXSTAT/iranet (same grant, P113-2): 480 Iranian " \
         "etymologies — the cognation base of the package's Iranian lexicostatistical wordlist, " \
         "with Persian/Tat/Kurdish/Baluchi/Talysh/Pashto/Munji/Shughni/Wakhi/Ishkashimi/Ossetic " \
         "forms paired with their etymon, linked into the PIE database. ira-pro is the " \
         "Wiktionary Proto-Iranian code."].freeze,
        ["inc-dar-pro", "witness:starling",
         "StarLing/Tower of Babel IE package, LEXSTAT/dardet (same grant, P113-2): 426 Dardic " \
         "etymologies (242 of them form-only stubs without a reconstruction) — the cognation " \
         "base of the package's Dardic lexicostatistical wordlist (Kashmiri, Bashkarik, Torwali, " \
         "Maiya, Shina, Phalura, Savi, Tirahi, Gawar-Bati, Shumashti, Wotapuri, Pashai, Khowar, " \
         "Kalasha), linked into the PIE database. inc-dar-pro follows the family-code + -pro " \
         "convention on Wiktionary's inc-dar (the bat-pro precedent)."].freeze
      ].freeze

      def self.manifest
        MANIFEST
      end

      def self.content_kind = :dictionary

      # piet mints reflex rows (health checks the promise, P18-7).
      def self.reflex_bearing? = true

      def self.remote_probe_strategy = :http_zip

      def self.http_probe_targets
        [Nabu::Adapter::HttpProbeTarget.new(
          label: "IE.exe", zip_url: MANIFEST.upstream_url, metadata_url: nil,
          state_subdir: "", state_file: Nabu::ZipFetch::STATE_FILE
        )] + FOLLOW_UP_PACKAGES.map do |subdir, url|
          Nabu::Adapter::HttpProbeTarget.new(
            label: File.basename(url), zip_url: url, metadata_url: nil,
            state_subdir: subdir, state_file: Nabu::ZipFetch::STATE_FILE
          )
        end
      end

      # [lang_code, kind, body] rows for the language-notes rider.
      def self.language_notes = LANGUAGE_NOTES

      # One DocumentRef per base, BASES order, then one per IE LEXSTAT
      # wordlist (StarlingLexstat::TABLES order); a workdir without a
      # table's .dbf simply yields fewer refs (the day-one pre-fetch state).
      # A row with a :dir (the IE package's LEXSTAT/ tables) resolves at
      # exactly <workdir>/<dir>/<dbf> — the follow-up packages carry
      # LEXSTAT/ trees of their own, never these.
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        BASES.each do |slug, base|
          base_path(workdir, base).each { |path| yield ref_for(slug, base.fetch(:dbf), path) }
        end
        StarlingLexstat::TABLES.each do |slug, table|
          path = File.join(workdir, StarlingLexstat::DIR, table.fetch(:dbf))
          yield ref_for(slug, table.fetch(:dbf), path) if File.file?(path)
        end
      end

      def parse(document_ref)
        slug = document_ref.metadata.fetch("dictionary")
        return StarlingLexstat.new.parse(slug: slug, path: document_ref.path) if StarlingLexstat::TABLES.key?(slug)

        base = BASES.fetch(slug)
        document = Nabu::DictionaryDocument.new(
          slug: slug, language: base.fetch(:language),
          title: base.fetch(:title), canonical_path: document_ref.path
        )
        seen = Hash.new(0)
        StarlingDbfParser.new(dbf_path: document_ref.path).each_record do |record|
          next if blank_zero_slot?(record)

          document << build_entry(base, record, seen)
        end
        document
      rescue Nabu::ValidationError => e
        raise Nabu::ParseError, "starling: #{document_ref.id}: #{e.message}"
      end

      # Eight packages, eight ZipFetch states (P46-6, generalized P104-3):
      # IE.exe maps onto the workdir root exactly as before (existing live
      # trees keep their layout), declaring keep: on every follow-up
      # subdir so its sweep never reads a sibling package as an upstream
      # deletion; each follow-up lands in its own subdir with its own
      # state + attic (the sl-lexica subdir posture).
      def fetch(workdir, progress: nil, force: false)
        ie = Nabu::ZipFetch.sync!(
          url: manifest.upstream_url, dir: workdir, keep: FOLLOW_UP_PACKAGES.keys,
          attic_dir: File.join(workdir, ATTIC_DIRNAME), progress: progress,
          guard: ->(doomed) { guard_mass_deletion!(workdir, doomed, force: force) }
        )
        results = FOLLOW_UP_PACKAGES.to_h do |subdir, url|
          dir = File.join(workdir, subdir)
          [url, Nabu::ZipFetch.sync!(
            url: url, dir: dir,
            attic_dir: File.join(workdir, ATTIC_DIRNAME, subdir), progress: progress,
            guard: ->(doomed) { guard_mass_deletion!(dir, doomed, force: force) }
          )]
        end
        FetchReport.new(sha: ie.sha, fetched_at: Time.now,
                        notes: fetch_notes({ manifest.upstream_url => ie }.merge(results)),
                        repos: { manifest.upstream_url => ie.sha }
                          .merge(results.transform_values(&:sha)))
      rescue ZipFetch::Error, Nabu::Shell::Error => e
        raise Nabu::FetchError, "starling fetch failed into #{workdir}: #{e.message}"
      end

      private

      def base_path(workdir, base)
        return Dir.glob(File.join(workdir, "**", base.fetch(:dbf))).first(1) unless base[:dir]

        path = File.join(workdir, base.fetch(:dir), base.fetch(:dbf))
        File.file?(path) ? [path] : []
      end

      def ref_for(slug, dbf, path)
        Nabu::DocumentRef.new(
          source_id: manifest.id, id: "#{slug}:#{dbf}",
          path: File.expand_path(path), metadata: { "dictionary" => slug }
        )
      end

      # A fully-empty record under NUMBER 0 is a dBase blank slot, not an
      # upstream entry: 0 is no addressable id (crosslink cells read 0 as
      # absent), so it mints nothing (P113-2 census: iranet ×18; every
      # other base ×0 — measured, zero drift).
      def blank_zero_slot?(record)
        record.fetch("NUMBER").to_s.strip == "0" &&
          record.except("NUMBER").values.all? { |value| ["", "0"].include?(value.to_s.strip) }
      end

      def fetch_notes(results_by_url)
        notes = results_by_url.filter_map do |url, result|
          "#{File.basename(url)} unchanged (304)" if result.not_modified
        end
        notes << attic_notes(results_by_url.values.sum([], &:atticked))
        notes.compact!
        notes.empty? ? nil : notes.join("; ")
      end

      def build_entry(base, record, seen)
        number = record.fetch("NUMBER").to_s.strip
        raise Nabu::ParseError, "starling: #{base.fetch(:dbf)}: record without a NUMBER" if number.empty?

        entry_id = entry_id_for(base, number, seen[number] += 1)
        # Headword-less records are upstream reality (P23-0 census: piet 6 —
        # content-bearing Iranian stubs at the file tail the live CGI cannot
        # even serve — germet 6 / baltet 7 empty numbered slots; pokorny/
        # vasmer 0): they keep their slot under the mechanical "#NUMBER"
        # placeholder (the crosslink notation), so links pointing at those
        # numbers resolve and nothing upstream is hidden.
        key_raw = presence(record.fetch(base.fetch(:headword))) || "##{number}"
        headword = key_raw.delete_prefix("*").strip
        gloss = (field = base.fetch(:gloss)) && presence(record[field])
        Nabu::DictionaryEntry.new(
          entry_id: entry_id, key_raw: key_raw, language: base.fetch(:language),
          headword: Nabu::Normalize.nfc(headword),
          headword_folded: fold_root(headword, base.fetch(:language)) || number,
          gloss: gloss && Nabu::Normalize.nfc(gloss),
          body: body_text(base, record, key_raw, collision_note(base, number, entry_id)),
          reflexes: build_reflexes(base, record)
        )
      end

      # Upstream NUMBER collisions, kept honest (P23-0 census: piet ×1 —
      # the owner's live quarantine, #574 twice, the second sitting where
      # the vacant 1574 belongs; baltet ×6; pokorny/vasmer/germet ×0): the
      # first record in file order keeps the plain NUMBER as its entry id —
      # so upstream "#NUMBER" crosslinks resolve to the first occurrence —
      # and each later collision mints a stable file-order suffix (-b, -c…).
      # File order is frozen with the 2005 package, so urns stay frozen;
      # upstream bytes are never renumbered (canonical means canonical).
      def entry_id_for(base, number, occurrence)
        return number if occurrence == 1

        suffixed = "#{number}-#{('a'.ord + occurrence - 1).chr}"
        unless occurrence <= 26
          raise Nabu::ParseError, "starling: #{base.fetch(:dbf)}: NUMBER #{number} repeats #{occurrence} times"
        end

        suffixed
      end

      # The honest note a suffixed entry carries in its body (nil on the
      # plain-id record): the collision is upstream's, the disambiguation
      # mechanical, the bytes untouched.
      def collision_note(base, number, entry_id)
        return nil if entry_id == number

        "note: upstream NUMBER collision — this record shares NUMBER #{number} with an earlier " \
          "record in #{base.fetch(:dbf)}; entry id disambiguated mechanically as #{entry_id} " \
          "(upstream data never renumbered; \"##{number}\" crosslinks resolve to the first occurrence)."
      end

      # Labeled body lines, upstream .inf aliases, non-empty fields only,
      # crosslink lines last ("Pokorny: #1089" — the number IS the target
      # shelf's entry id), then the collision note when one applies. Every
      # branch column rides here verbatim, whether or not it also minted a
      # reflex row.
      def body_text(base, record, fallback, note)
        lines = base.fetch(:body).filter_map do |field, label|
          value = presence(record[field])
          "#{label}: #{value}" if value
        end
        lines += base.fetch(:crosslinks).filter_map do |field, label|
          number = record[field].to_s.strip
          # A crosslink line needs a real number: dBase numeric cells can
          # overflow to the "****" sentinel (P104-3 census: four dravet
          # link cells, three of them on #1) — those mint no line.
          "#{label}: ##{number}" if number.match?(/\A\d+\z/) && number != "0"
        end
        lines << note if note
        Nabu::Normalize.nfc(lines.empty? ? fallback : lines.join("\n"))
      end

      # The verdict's honest slice: one row per single-language branch cell
      # whose LEADING token is a clean citation form — and not one of the
      # censused bare dialect/variety labels (STOP_TOKENS); everything else
      # stays body-only (see the class comment).
      def build_reflexes(base, record)
        base.fetch(:reflexes).filter_map do |column, (language, name)|
          cell = presence(record[column]) or next
          word = cell.split(/[\s,]/).first.to_s
          next unless word.match?(CITATION_FORM)
          next if STOP_TOKENS.include?(word)

          nfc = Nabu::Normalize.nfc(word)
          Nabu::DictionaryReflex.new(
            lang_code: language, language: language, word: nfc,
            word_folded: reflex_fold(nfc, language),
            borrowed: false, lang_name: name
          )
        end
      end

      # Root fold (the iecor/kaikki convention): first comma-variant, ?/*
      # prefix and parens off, the IEW homonym digit off ("aig-2" → "aig-"),
      # trailing stem hyphen KEPT — cross-witness define/closure joins run
      # through this key.
      def fold_root(headword, language)
        first = headword.split(/,\s*/).first.to_s
        cleaned = first.sub(/\A[?*\s]+/, "").delete("()⁽⁾").sub(/(?<=-)\d+\z/, "")
        folded = Nabu::Normalize.search_form(cleaned, language: language)
        folded.strip.empty? ? nil : folded
      end

      # Member fold (the iecor member rule): parens and the trailing stem
      # hyphen off — gold lemmas carry neither.
      def reflex_fold(word, language)
        cleaned = word.sub(/\A[?*\s]+/, "").delete("()⁽⁾").sub(/-\z/, "")
        folded = Nabu::Normalize.search_form(cleaned, language: language)
        folded.strip.empty? ? nil : folded
      end

      def presence(value)
        text = value.to_s.strip
        text.empty? ? nil : text
      end
    end
  end
end

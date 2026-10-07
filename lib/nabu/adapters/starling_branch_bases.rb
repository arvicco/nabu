# frozen_string_literal: true

module Nabu
  module Adapters
    # The StarLing BRANCH-BASES wave: the 28 subordinate etymological bases
    # sitting unparsed inside the ALTAIC / CAUC / DRAV / SINTIB packages since
    # P104-3 (declared deferred there "each follows the head pattern and can
    # ride as a later BASES row"). G. Starostin's 2026-10-01 extension grant
    # covers every downloadable database under the 2026-07-15 conditions (any
    # use, per-base attribution). Pure configuration: every row is a
    # Starling::BASES row — same parse path, same shape (NUMBER / PROTO /
    # PRNUM / MEANING + per-language columns), merged after the head bases so
    # discover order stays head-first.
    #
    # Read from the files themselves, never guessed: field layouts are the
    # .dbf descriptors, labels the .inf `\1:` (English) field aliases
    # verbatim, credits the .inf DBINFO texts (koret.inf has none — its
    # credit is the Altaic package's, the AED; the P113-2 LEXSTAT precedent).
    # Body order is the .dbf field order. Columns OUTSIDE every lane (sdret's
    # logical CHECKED flag — an editorial checkbox, no alias) ride nowhere.
    # Labels the .inf lacks are adapter-supplied and DECLARED per row.
    #
    # == Shelf languages (DECLARED, conservative)
    #
    # A PROTO-shaped base files under its branch's proto code; a base whose
    # headword IS a single attested language (laket, khinet, braet, konet and
    # the four Leiden dictionaries) files under that language's code. Codes:
    # Wiktionary's where one exists — trk-pro / xgn-pro / tuw-pro /
    # qfa-kor-pro / cau-nkh-pro / cau-nwc-pro / sit-kir (all attested in the
    # held Wiktionary extracts), cau-ava / cau-tsz / cau-drg / cau-lzg (the
    # Wiktionary Avar-Andic / Tsezic / Dargwa / Lezgic family codes, +pro);
    # the itl-pro shape (a pro stage on a language anchor) for the
    # provisional Proto-Telugu (te-pro) and Proto-Gondi (gon-pro, the ISO
    # 639-3 Gondi macrolanguage); and — for the five Dravidian intermediate
    # branches with no code anywhere — CODES COINED in Wiktionary's
    # family-prefix style from dravet's own column sigla (dra-sdr / dra-kog /
    # dra-gnd / dra-ndr) or the base name (dra-kui Kui-Kuwi, dra-nil
    # Nilgiri, dra-pem Pengo-Manda), the qfa-chk precedent. Registry nodes
    # for these codes are a nabu-lects matter, minted separately.
    #
    # == The reflex verdict (the head bases' rule, censused per column)
    #
    # A column mints DictionaryReflex rows only when it is a SINGLE attested
    # language with an unambiguous code — the piet/germet/kart/chuket/yenet
    # rule — gated per cell by the shared CITATION_FORM + STOP_TOKENS lead
    # test. Body-only by verdict (censused 2026-10-07 over the full tables):
    # branch protoforms (sdret KT, gndet GON/PEM/KUI), mixed-source columns
    # (turcet ATU "Old Turkic (Orkhon and Old Uighur)" — 683 of 1,031 cells
    # tagged OUygh. against 72 Orkh., two registry lects in one column;
    # turcet CHG "Middle Turkic" — Chagatai mixed with Middle/Old Kypchak,
    # Khwarezmian and Codex Cumanicus sources), dialect/variety columns with
    # no code of their own (monget ORD Ordos, tunget SOL Solon, aandet AVC
    # Chadakolob, cezet INH Inkhokvari, darget CHR Chiragh, sdret KAS Kasaba,
    # telet's dialect/source columns, kogaet's Kolami/Naikri/Naiki/Salur/
    # Poya columns, gonet's seventeen Gondi dialect columns, kuiet's Kuttia
    # and second-source Kuwi columns, tunget SIB "Spoken Manchu"), and
    # monget MOGH (71.5% clean leads: the "ZM" manuscript label leads 43
    # cells). Single-language shelves (laket/khinet/konet) keep their own
    # form column in the body: the entry already IS that language's record
    # (the vasmer posture). The Caucasian and Kiranti columns gate harder
    # than the head bases' (51–89% clean: the ":" tense/length mark,
    # class-prefix "=" and affix-led cells are not CITATION_FORM leads) —
    # an unclean lead mints nothing and rides the body, never a guess.
    module StarlingBranchBases
      # ALTAIC — the Altaic Etymological Dictionary's four branch databases
      # (PRNUM → starling-altet, "Altaic etymology", the .inf alias).
      ALTAIC = {
        # turcet.inf DBINFO: "the Turkic part of the Altaic Etymological
        # Dictionary", Proto-Turkic "with O. Mudrak's modifications".
        "starling-turcet" => {
          dbf: "turcet.dbf", language: "trk-pro",
          title: "Turkic etymology (the Turkic part of the Altaic Etymological Dictionary; " \
                 "Proto-Turkic with O. Mudrak's modifications; StarLing database)",
          headword: "PROTO", gloss: "MEANING",
          body: {
            "RUSMEAN" => "Russian meaning", "ATU" => "Old Turkic", "KRH" => "Karakhanid",
            "TRK" => "Turkish", "TAT" => "Tatar", "CHG" => "Middle Turkic", "UZB" => "Uzbek",
            "UIG" => "Uighur", "SJG" => "Sary-Yughur", "AZB" => "Azerbaidzhan", "TRM" => "Turkmen",
            "HAK" => "Khakassian", "SHR" => "Shor", "ALT" => "Oyrat", "KHAL" => "Halaj",
            "CHV" => "Chuvash", "JAK" => "Yakut", "DOLG" => "Dolgan", "TUV" => "Tuva",
            "TOF" => "Tofalar", "KRG" => "Kirghiz", "KAZ" => "Kazakh", "NOGX" => "Noghai",
            "BAS" => "Bashkir", "BLKX" => "Balkar", "GAGX" => "Gagauz", "KRMX" => "Karaim",
            "KLPX" => "Karakalpak", "SAL" => "Salar", "QUM" => "Kumyk", "REFERENCE" => "Comments"
          }.freeze,
          crosslinks: { "PRNUM" => "Altaic etymology" }.freeze,
          # 27 of 29 language columns mint (95.4–99.5% clean leads). ALT
          # "Oyrat" is Southern Altai (alt); SJG "Sary-Yughur" Western Yugur.
          reflexes: {
            "KRH" => %w[xqa Karakhanid].freeze, "TRK" => %w[tr Turkish].freeze,
            "TAT" => %w[tt Tatar].freeze, "UZB" => %w[uz Uzbek].freeze, "UIG" => %w[ug Uighur].freeze,
            "SJG" => %w[ybe Sary-Yughur].freeze, "AZB" => %w[az Azerbaidzhan].freeze,
            "TRM" => %w[tk Turkmen].freeze, "HAK" => %w[kjh Khakassian].freeze,
            "SHR" => %w[cjs Shor].freeze, "ALT" => %w[alt Oyrat].freeze, "KHAL" => %w[klj Halaj].freeze,
            "CHV" => %w[cv Chuvash].freeze, "JAK" => %w[sah Yakut].freeze, "DOLG" => %w[dlg Dolgan].freeze,
            "TUV" => %w[tyv Tuva].freeze, "TOF" => %w[kim Tofalar].freeze, "KRG" => %w[ky Kirghiz].freeze,
            "KAZ" => %w[kk Kazakh].freeze, "NOGX" => %w[nog Noghai].freeze, "BAS" => %w[ba Bashkir].freeze,
            "BLKX" => %w[krc Balkar].freeze, "GAGX" => %w[gag Gagauz].freeze,
            "KRMX" => %w[kdr Karaim].freeze, "KLPX" => %w[kaa Karakalpak].freeze,
            "SAL" => %w[slr Salar].freeze, "QUM" => %w[kum Kumyk].freeze
          }.freeze
        }.freeze,
        # monget.inf DBINFO: "The Mongolian part of the Altaic Etymological
        # Dictionary". WMO is Classical (written) Mongolian, MMO Middle
        # Mongol (the registry's xng), HAL Khalkha (Wiktionary mn).
        "starling-monget" => {
          dbf: "monget.dbf", language: "xgn-pro",
          title: "Mongolian etymology (the Mongolian part of the Altaic Etymological Dictionary; " \
                 "StarLing database)",
          headword: "PROTO", gloss: "MEANING",
          body: {
            "RUSMEAN" => "Russian meaning", "WMO" => "Written Mongolian", "MMO" => "Middle Mongolian",
            "HAL" => "Khalkha", "BUR" => "Buriat", "KAL" => "Kalmuck", "ORD" => "Ordos",
            "DUN" => "Dongxian", "BAO" => "Baoan", "DAG" => "Dagur", "YUY" => "Shary-Yoghur",
            "MGR" => "Monguor", "MOGH" => "Mogol", "REFERENCE" => "Comments"
          }.freeze,
          crosslinks: { "PRNUM" => "Altaic etymology" }.freeze,
          reflexes: {
            "WMO" => ["cmg", "Written Mongolian"].freeze, "MMO" => ["xng", "Middle Mongolian"].freeze,
            "HAL" => %w[mn Khalkha].freeze, "BUR" => %w[bua Buriat].freeze,
            "KAL" => %w[xal Kalmuck].freeze, "DUN" => %w[sce Dongxian].freeze,
            "BAO" => %w[peh Baoan].freeze, "DAG" => %w[dta Dagur].freeze,
            "YUY" => %w[yuy Shary-Yoghur].freeze, "MGR" => %w[mjg Monguor].freeze
          }.freeze
        }.freeze,
        # tunget.inf DBINFO: "subordinate to the Common Altaic database. The
        # basic source is the TMC - the Comparative Dictionary of
        # Tungus-Manchu Languages compiled by Tsintsius et al."
        "starling-tunget" => {
          dbf: "tunget.dbf", language: "tuw-pro",
          title: "Tungus-Manchu etymology (subordinate to the Altaic database; after the TMC " \
                 "compiled by Tsintsius et al.; StarLing database)",
          headword: "PROTO", gloss: "MEANING",
          body: {
            "RUSMEAN" => "Russian meaning", "EVK" => "Evenki", "EVN" => "Even", "NEG" => "Negidal",
            "SIB" => "Spoken Manchu", "MAN" => "Literary Manchu", "CHU" => "Jurchen", "ULC" => "Ulcha",
            "ORK" => "Orok", "NAN" => "Nanai", "ORC" => "Oroch", "UDE" => "Udighe", "SOL" => "Solon",
            "REFERENCE" => "Comments"
          }.freeze,
          crosslinks: { "PRNUM" => "Altaic etymology" }.freeze,
          reflexes: {
            "EVK" => %w[evn Evenki].freeze, "EVN" => %w[eve Even].freeze, "NEG" => %w[neg Negidal].freeze,
            "MAN" => ["mnc", "Literary Manchu"].freeze, "CHU" => %w[juc Jurchen].freeze,
            "ULC" => %w[ulc Ulcha].freeze, "ORK" => %w[oaa Orok].freeze, "NAN" => %w[gld Nanai].freeze,
            "ORC" => %w[oac Oroch].freeze, "UDE" => %w[ude Udighe].freeze
          }.freeze
        }.freeze,
        # koret.inf carries NO DBINFO (aliases only): the credit is the
        # Altaic package's (the AED). Its "Proto-Korean" forms are, by
        # altet.inf's own account, essentially Middle Korean with a few
        # internal-reconstruction modifications — qfa-kor-pro (Wiktionary's
        # Proto-Koreanic) is the filing place, declared coarse.
        "starling-koret" => {
          dbf: "koret.dbf", language: "qfa-kor-pro",
          title: "Korean etymology (the Korean database of the Altaic Etymological Dictionary " \
                 "package; StarLing database)",
          headword: "PROTO", gloss: "MEANING",
          body: {
            "RUSMEAN" => "Russian meaning", "PHN" => "Modern Korean", "AKO" => "Middle Korean",
            "REFERENCE" => "Comments"
          }.freeze,
          crosslinks: { "PRNUM" => "Altaic etymology" }.freeze,
          reflexes: {
            "PHN" => ["ko", "Modern Korean"].freeze, "AKO" => ["okm", "Middle Korean"].freeze
          }.freeze
        }.freeze
      }.freeze

      # CAUC — the North Caucasian Etymological Dictionary's eight branch
      # databases (PRNUM → starling-caucet, "North Caucasian etymology").
      CAUC = {
        # nakhet.inf DBINFO: "The Nakh part of the North Caucasian
        # Etymological Dictionary", "in S. Nikolayev's reconstruction".
        # COMMENT carries no .inf alias — "Comments" is the DBINFO's item.
        "starling-nakhet" => {
          dbf: "nakhet.dbf", language: "cau-nkh-pro",
          title: "Nakh etymology (the Nakh part of the North Caucasian Etymological Dictionary; " \
                 "S. Nikolayev's reconstruction; StarLing database)",
          headword: "PROTO", gloss: "MEANING",
          body: { "CHE" => "Chechen", "ING" => "Ingush", "BCB" => "Batsbi", "COMMENT" => "Comments" }.freeze,
          crosslinks: { "PRNUM" => "North Caucasian etymology" }.freeze,
          reflexes: {
            "CHE" => %w[ce Chechen].freeze, "ING" => %w[inh Ingush].freeze, "BCB" => %w[bbl Batsbi].freeze
          }.freeze
        }.freeze,
        # aandet.inf DBINFO: "the Avaro-Andian part of the North Caucasian
        # comparative dictionary" — its protoforms are mostly Proto-Andian
        # (Gudava's, modified); filed at the Avar-Andic level, declared.
        "starling-aandet" => {
          dbf: "aandet.dbf", language: "cau-ava-pro",
          title: "Avaro-Andian etymology (the Avaro-Andian part of the North Caucasian " \
                 "comparative dictionary; StarLing database)",
          headword: "PROTO", gloss: "MEANING",
          body: {
            "AVA" => "Avar", "AVC" => "Chadakolob", "AND" => "Andian language", "AKV" => "Akhvakh",
            "CHM" => "Chamalal", "TND" => "Tindi", "KRT" => "Karata", "BTL" => "Botlikh",
            "BGV" => "Bagvalal", "GDB" => "Godoberi", "COMMENT" => "Comments"
          }.freeze,
          crosslinks: { "PRNUM" => "North Caucasian etymology" }.freeze,
          reflexes: {
            "AVA" => %w[av Avar].freeze, "AND" => ["ani", "Andian language"].freeze,
            "AKV" => %w[akv Akhvakh].freeze, "CHM" => %w[cji Chamalal].freeze,
            "TND" => %w[tin Tindi].freeze, "KRT" => %w[kpt Karata].freeze,
            "BTL" => %w[bph Botlikh].freeze, "BGV" => %w[kva Bagvalal].freeze,
            "GDB" => %w[gdo Godoberi].freeze
          }.freeze
        }.freeze,
        # cezet.inf DBINFO: "The Tsezian part of the North Caucasian
        # etymological dictionary", "in S. Nikolayev's reconstruction".
        "starling-cezet" => {
          dbf: "cezet.dbf", language: "cau-tsz-pro",
          title: "Tsezian etymology (the Tsezian part of the North Caucasian Etymological " \
                 "Dictionary; S. Nikolayev's reconstruction; StarLing database)",
          headword: "PROTO", gloss: "MEANING",
          body: {
            "CEZ" => "Tsezi", "GIN" => "Ginukh", "KHV" => "Khvarshi", "INH" => "Inkhokvari",
            "BZT" => "Bezhta", "GNZ" => "Gunzib", "COMMENT" => "Comments"
          }.freeze,
          crosslinks: { "PRNUM" => "North Caucasian etymology" }.freeze,
          reflexes: {
            "CEZ" => %w[ddo Tsezi].freeze, "GIN" => %w[gin Ginukh].freeze,
            "KHV" => %w[khv Khvarshi].freeze, "BZT" => %w[kap Bezhta].freeze,
            "GNZ" => %w[huz Gunzib].freeze
          }.freeze
        }.freeze,
        # laket.inf DBINFO: "The actual literary Lak form. No Proto-Lak
        # reconstruction is given" — a single-language shelf (lbe).
        "starling-laket" => {
          dbf: "laket.dbf", language: "lbe",
          title: "Lak etymology (the Lak part of the North Caucasian Etymological Dictionary; " \
                 "StarLing database)",
          headword: "PROTO", gloss: "MEANING",
          body: { "LAK" => "Lak form", "COMMENT" => "Comments" }.freeze,
          crosslinks: { "PRNUM" => "North Caucasian etymology" }.freeze,
          reflexes: {}.freeze
        }.freeze,
        # darget.inf DBINFO: "The Dargwa part of the North Caucasian
        # Etymological Dictionary", "in S. Nikolayev's reconstruction". DRG
        # "Akusha" is literary Dargwa (dar); Chiragh has no code.
        "starling-darget" => {
          dbf: "darget.dbf", language: "cau-drg-pro",
          title: "Dargwa etymology (the Dargwa part of the North Caucasian Etymological " \
                 "Dictionary; S. Nikolayev's reconstruction; StarLing database)",
          headword: "PROTO", gloss: "MEANING",
          body: { "DRG" => "Akusha", "CHR" => "Chiragh", "COMMENT" => "Comments" }.freeze,
          crosslinks: { "PRNUM" => "North Caucasian etymology" }.freeze,
          reflexes: { "DRG" => %w[dar Akusha].freeze }.freeze
        }.freeze,
        # lezget.inf DBINFO: "The Lezghian part of the North Caucasian
        # Etymological Dictionary", "in S. Starostin's reconstruction".
        # COMMENT carries no .inf alias — "Comments" is the DBINFO's item.
        "starling-lezget" => {
          dbf: "lezget.dbf", language: "cau-lzg-pro",
          title: "Lezghian etymology (the Lezghian part of the North Caucasian Etymological " \
                 "Dictionary; S. Starostin's reconstruction; StarLing database)",
          headword: "PROTO", gloss: "MEANING",
          body: {
            "LZG" => "Lezghian", "TAB" => "Tabasaran", "AGU" => "Agul", "RUT" => "Rutul",
            "CAK" => "Tsakhur", "KRZ" => "Kryz", "BUD" => "Budukh", "ARC" => "Archi", "UDI" => "Udi",
            "COMMENT" => "Comments"
          }.freeze,
          crosslinks: { "PRNUM" => "North Caucasian etymology" }.freeze,
          reflexes: {
            "LZG" => %w[lez Lezghian].freeze, "TAB" => %w[tab Tabasaran].freeze,
            "AGU" => %w[agx Agul].freeze, "RUT" => %w[rut Rutul].freeze, "CAK" => %w[tkr Tsakhur].freeze,
            "KRZ" => %w[kry Kryz].freeze, "BUD" => %w[bdk Budukh].freeze, "ARC" => %w[aqc Archi].freeze,
            "UDI" => %w[udi Udi].freeze
          }.freeze
        }.freeze,
        # khinet.inf DBINFO: "The actual Khinalug form. No reconstruction of
        # Proto-Khinalug is available" — a single-language shelf (kjj).
        "starling-khinet" => {
          dbf: "khinet.dbf", language: "kjj",
          title: "Khinalug etymology (the Khinalug part of the North Caucasian Etymological " \
                 "Dictionary; StarLing database)",
          headword: "PROTO", gloss: "MEANING",
          body: { "KHI" => "Khinalug form", "COMMENT" => "Comments" }.freeze,
          crosslinks: { "PRNUM" => "North Caucasian etymology" }.freeze,
          reflexes: {}.freeze
        }.freeze,
        # abadet.inf DBINFO: "the West Caucasian (Abkhazo-Adyghe) part of the
        # North Caucasian comparative dictionary", "the PWC form in S. A.
        # Starostin's reconstruction".
        "starling-abadet" => {
          dbf: "abadet.dbf", language: "cau-nwc-pro",
          title: "West Caucasian etymology (the Abkhazo-Adyghe part of the North Caucasian " \
                 "comparative dictionary; S. A. Starostin's reconstruction; StarLing database)",
          headword: "PROTO", gloss: "MEANING",
          body: {
            "ABK" => "Abkhaz", "ABA" => "Abaza", "ADG" => "Adyghe", "KAB" => "Kabardian",
            "UBK" => "Ubykh", "COMMENT" => "Comments"
          }.freeze,
          crosslinks: { "PRNUM" => "North Caucasian etymology" }.freeze,
          reflexes: {
            "ABK" => %w[ab Abkhaz].freeze, "ABA" => %w[abq Abaza].freeze, "ADG" => %w[ady Adyghe].freeze,
            "KAB" => %w[kbd Kabardian].freeze, "UBK" => %w[uby Ubykh].freeze
          }.freeze
        }.freeze
      }.freeze

      # DRAV — the eleven subordinate databases of G. Starostin's Dravidian
      # base. PRNUM → starling-dravet ("Dravidian etymology"), except the
      # Gondwan subordinates (→ gndet, "Gondwan etymology") and the Nilgiri
      # base (→ sdret, "South Dravidian etymology"). DEDNUM ("Number in
      # DED") is the Burrow-Emeneau number, an inline text cell.
      DRAV = {
        # sdret.inf DBINFO: "The South-Dravidian database", "the main
        # database for South Dravidian etymological data" (per-language
        # basic/meaning/derivates fields). 807 headword-less records (no
        # protoform yet — "not all the entries are accompanied by
        # protoforms") keep their slots as "#NUMBER". KT is the
        # Proto-Nilgiri protoform (body-only) with KTNUM → ktet.
        "starling-sdret" => {
          dbf: "sdret.dbf", language: "dra-sdr-pro",
          title: "South Dravidian etymology (subordinate to G. Starostin's Dravidian database; " \
                 "DED-based; StarLing database)",
          headword: "PROTO", gloss: "MEANING",
          body: {
            "STEMS" => "Stems", "TAM" => "Tamil", "TAMMEAN" => "Tamil meaning",
            "TAMDER" => "Tamil derivates", "MAL" => "Malayalam", "MALMEAN" => "Malayalam meaning",
            "MALDER" => "Malayalam derivates", "KAN" => "Kannada", "KANMEAN" => "Kannada meaning",
            "KANDER" => "Kannada derivates", "KOD" => "Kodagu", "KODMEAN" => "Kodagu meaning",
            "KODDER" => "Kodagu derivates", "TUL" => "Tulu", "TULMEAN" => "Tulu meaning",
            "TULDER" => "Tulu derivates", "KT" => "Proto-Nilgiri", "IRU" => "Irula",
            "IRUMEAN" => "Irula meaning", "IRUDER" => "Irula derivates", "KAS" => "Kasaba",
            "KASMEAN" => "Kasaba meaning", "KASDER" => "Kasaba derivates", "MISC" => "Miscellaneous",
            "NOTES" => "Notes", "DEDNUM" => "Number in DED"
          }.freeze,
          crosslinks: { "PRNUM" => "Dravidian etymology", "KTNUM" => "Nilgiri etymology" }.freeze,
          reflexes: {
            "TAM" => %w[ta Tamil].freeze, "MAL" => %w[ml Malayalam].freeze, "KAN" => %w[kn Kannada].freeze,
            "KOD" => %w[kfa Kodagu].freeze, "TUL" => %w[tcy Tulu].freeze, "IRU" => %w[iru Irula].freeze
          }.freeze
        }.freeze,
        # telet.inf DBINFO: "A database for Telugu dialects" — "a
        # provisional Proto-Telugu form" (te-pro, the itl-pro shape). Only
        # the basic standard form (TEL_1) mints; the dialect, Krishnamurti,
        # inscriptional and Merolu columns are variety/source columns.
        "starling-telet" => {
          dbf: "telet.dbf", language: "te-pro",
          title: "Telugu etymology (a database for Telugu dialects, subordinate to " \
                 "G. Starostin's Dravidian database; StarLing database)",
          headword: "PROTO", gloss: "MEANING",
          body: {
            "TEL_1" => "Telugu", "TEL_2" => "Dialectal forms (1)", "TEL_3" => "Dialectal forms (2)",
            "TEL_4" => "Dialectal forms (3)", "TEL_5" => "Dialectal forms (4)",
            "TEL_KR" => "Telugu (Krishnamurti)", "TEL_INSCR" => "Inscriptional Telugu",
            "MEROLU" => "Merolu Telugu", "ADDITION" => "Additional forms", "NOTES" => "Notes",
            "DEDNUM" => "Number in DED"
          }.freeze,
          crosslinks: { "PRNUM" => "Dravidian etymology" }.freeze,
          reflexes: { "TEL_1" => %w[te Telugu].freeze }.freeze
        }.freeze,
        # kogaet.inf DBINFO: "The Kolami-Gadba database, subordinate to the
        # Common Dravidian database". PARJI (Duruwa, pci), OLLARI (Ollari
        # Gadba, gdb) and S_3 (Kondekor Gadba = Mudhili Gadaba, gau) mint;
        # the Kolami columns (kfb/nit split unresolvable per column),
        # Naikri/Naiki and the Salur/Poya Gadba varieties are body-only.
        "starling-kogaet" => {
          dbf: "kogaet.dbf", language: "dra-kog-pro",
          title: "Kolami-Gadba etymology (subordinate to G. Starostin's Dravidian database; " \
                 "StarLing database)",
          headword: "PROTO", gloss: "MEANING",
          body: {
            "KOLAMI" => "Kolami", "KOL_KIN" => "Kinwat Kolami", "KOL_SR" => "Kolami (Setumadhava Rao)",
            "NAIKRI" => "Naikri", "NAIKI" => "Naiki", "PARJI" => "Parji", "OLLARI" => "Ollari Gadba",
            "SALUR" => "Salur Gadba", "POYA" => "Poya Gadba", "S_3" => "Kondekor Gadba",
            "ADDITION" => "Additional forms", "NOTES" => "Notes", "DEDNUM" => "Number in DED"
          }.freeze,
          crosslinks: { "PRNUM" => "Dravidian etymology" }.freeze,
          reflexes: {
            "PARJI" => %w[pci Parji].freeze, "OLLARI" => ["gdb", "Ollari Gadba"].freeze,
            "S_3" => ["gau", "Kondekor Gadba"].freeze
          }.freeze
        }.freeze,
        # gndet.inf DBINFO: "The Gondwan (Gondi-Kui) database, subordinate to
        # the Common Dravidian database" — "mostly intermediate
        # reconstructions": GON/PEM/KUI are protoforms (body-only), KON the
        # actual Konda reflex (mints kfc). The four sub-base link columns
        # carry NO .inf alias: their labels are adapter-supplied in the
        # dravet "<Branch> etymology" pattern (the DBINFO's own words: "a
        # link to the Gondi / Konda / Pengo-Manda / Kui-Kuwi database").
        "starling-gndet" => {
          dbf: "gndet.dbf", language: "dra-gnd-pro",
          title: "Gondi-Kui (Gondwan) etymology (subordinate to G. Starostin's Dravidian " \
                 "database; StarLing database)",
          headword: "PROTO", gloss: "MEANING",
          body: {
            "GON" => "Proto-Gondi", "KON" => "Konda", "PEM" => "Proto-Pengo-Manda",
            "KUI" => "Proto-Kui-Kuwi", "NOTES" => "Notes", "COR" => "Notes on correspondences"
          }.freeze,
          crosslinks: {
            "PRNUM" => "Dravidian etymology", "GONNUM" => "Gondi etymology",
            "KONNUM" => "Konda etymology", "PEMNUM" => "Pengo-Manda etymology",
            "KUINUM" => "Kui-Kuwi etymology"
          }.freeze,
          reflexes: { "KON" => %w[kfc Konda].freeze }.freeze
        }.freeze,
        # gonet.inf DBINFO: "The Gondi database, subordinate to the Gondwan
        # database" — seventeen dialect/source columns, none with a code of
        # its own (the ISO 639-3 Gondi split does not map per column):
        # body-only. Proto-Gondi files as gon-pro (the itl-pro shape on the
        # Gondi macrolanguage code).
        "starling-gonet" => {
          dbf: "gonet.dbf", language: "gon-pro",
          title: "Gondi etymology (subordinate to the Gondwan and Dravidian databases; " \
                 "StarLing database)",
          headword: "PROTO", gloss: "MEANING",
          body: {
            "GONDI_TR" => "Betul Gondi", "GONDI_W" => "Mandla Gondi (Williamson)",
            "GONDI_PH" => "Mandla Gondi (Phailbus)", "GONDI_G" => "Gommu Gondi",
            "GONDI_MU" => "Muria Gondi", "GONDI_MA" => "Maria Gondi", "GONDI_S" => "Seoni Gondi",
            "GONDI_KO" => "Koya Gondi", "GONDI_Y" => "Yeotmal Gondi",
            "GONDI_M" => "Maria Gondi (Mitchell)", "GONDI_L" => "Maria Gondi (Lind)",
            "GONDI_LU_S" => "Maria Gondi (Smith)", "GONDI_MND" => "Mandla Gondi",
            "GONDI_CH" => "Chindwara Gondi", "GONDI_A" => "Adilabad Gondi", "GONDI_D" => "Durg Gondi",
            "GONDI_CHD" => "Chanda Gondi", "ADDITION" => "Additional forms", "NOTES" => "Notes",
            "DEDNUM" => "Number in DED", "VOC_NUM" => "Number in CVOTGD"
          }.freeze,
          crosslinks: { "PRNUM" => "Gondwan etymology" }.freeze,
          reflexes: {}.freeze
        }.freeze,
        # kuiet.inf DBINFO: "The Kui-Kuwi database, subordinate to the
        # Gondwan database". KUI (kxu) and the first Kuwi source KUWI_F
        # (Fitzgerald, kxv) mint; Kuttia Kui and the eight further Kuwi
        # source/dialect columns ride the body (the itelet Kovran/Stebnitski
        # precedent: one minting column per language).
        "starling-kuiet" => {
          dbf: "kuiet.dbf", language: "dra-kui-pro",
          title: "Kui-Kuwi etymology (subordinate to the Gondwan and Dravidian databases; " \
                 "StarLing database)",
          headword: "PROTO", gloss: "MEANING",
          body: {
            "KUI" => "Kui", "KUTTIA" => "Khuttia Kui", "KUWI_F" => "Kuwi (Fitzgerald)",
            "KUWI_S" => "Kuwi (Schulze)", "KUWI_SU" => "Sunkarametta Kuwi", "KUWI_P" => "Parja Kuwi",
            "KUWI_T" => "Tekriya Kuwi", "KUWI_D" => "Dongriya Kuwi", "KUWI_MAH" => "Kuwi (Mahanti)",
            "KUWI_ISR" => "Kuwi (Israel)", "ADDITION" => "Additional forms", "NOTES" => "Notes",
            "DEDNUM" => "Number in DED"
          }.freeze,
          crosslinks: { "PRNUM" => "Gondwan etymology" }.freeze,
          reflexes: {
            "KUI" => %w[kxu Kui].freeze, "KUWI_F" => ["kxv", "Kuwi (Fitzgerald)"].freeze
          }.freeze
        }.freeze,
        # konet.inf DBINFO: "Konda form (a single language, so no
        # Proto-Konda reconstruction is provided)" — a single-language shelf
        # (kfc). konet.inf's MEANING alias is the bare "Meaning".
        "starling-konet" => {
          dbf: "konet.dbf", language: "kfc",
          title: "Konda etymology (subordinate to the Gondwan and Dravidian databases; " \
                 "StarLing database)",
          headword: "PROTO", gloss: "MEANING",
          body: {
            "KONDA_BB" => "Konda (Burrow/Bhattacharya)", "ADDITION" => "Additional forms",
            "NOTES" => "Notes", "DEDNUM" => "Number in DED"
          }.freeze,
          crosslinks: { "PRNUM" => "Gondwan etymology" }.freeze,
          reflexes: {}.freeze
        }.freeze,
        # ktet.inf DBINFO: "The Nilgiri (Kota-Toda) database, subordinate to
        # the South Dravidian database". PRNUM → sdret (both ways: sdret
        # KTNUM). Its select-correspondence table rides the .inf only.
        "starling-ktet" => {
          dbf: "ktet.dbf", language: "dra-nil-pro",
          title: "Nilgiri (Kota-Toda) etymology (subordinate to the South Dravidian and " \
                 "Dravidian databases; StarLing database)",
          headword: "PROTO", gloss: "MEANING",
          body: {
            "STEMS" => "Stems", "KOTA" => "Kota", "TODA" => "Toda", "ADDITION" => "Additional forms",
            "NOTES" => "Notes", "DEDNUM" => "Number in DED"
          }.freeze,
          crosslinks: { "PRNUM" => "South Dravidian etymology" }.freeze,
          reflexes: { "KOTA" => %w[kfe Kota].freeze, "TODA" => %w[tcx Toda].freeze }.freeze
        }.freeze,
        # ndret.inf DBINFO: "The North Dravidian database, subordinate to the
        # Common Dravidian database" (notes "occasionally in Russian"). MLT
        # is Malto (Sauria Paharia, mjt).
        "starling-ndret" => {
          dbf: "ndret.dbf", language: "dra-ndr-pro",
          title: "North Dravidian etymology (subordinate to G. Starostin's Dravidian database; " \
                 "StarLing database)",
          headword: "PROTO", gloss: "MEANING",
          body: {
            "KUR" => "Kurukh", "MLT" => "Malto", "NOTES" => "Notes", "ADDITION" => "Additional forms",
            "DEDNUM" => "Number in DED"
          }.freeze,
          crosslinks: { "PRNUM" => "Dravidian etymology" }.freeze,
          reflexes: { "KUR" => %w[kru Kurukh].freeze, "MLT" => %w[mjt Malto].freeze }.freeze
        }.freeze,
        # pemet.inf DBINFO: "The Pengo-Manda database, subordinate to the
        # Gondwan database".
        "starling-pemet" => {
          dbf: "pemet.dbf", language: "dra-pem-pro",
          title: "Pengo-Manda etymology (subordinate to the Gondwan and Dravidian databases; " \
                 "StarLing database)",
          headword: "PROTO", gloss: "MEANING",
          body: {
            "PENGO" => "Pengo", "MANDA" => "Manda", "ADDITION" => "Additional Forms",
            "NOTES" => "Notes", "DEDNUM" => "Number in DED"
          }.freeze,
          crosslinks: { "PRNUM" => "Gondwan etymology" }.freeze,
          reflexes: { "PENGO" => %w[peg Pengo].freeze, "MANDA" => %w[mha Manda].freeze }.freeze
        }.freeze,
        # braet.inf DBINFO: "The database on Brahui, subordinate to the
        # Common Dravidian database" — "A single language, so no
        # reconstruction is provided": a single-language shelf (brh).
        "starling-braet" => {
          dbf: "braet.dbf", language: "brh",
          title: "Brahui etymology (subordinate to G. Starostin's Dravidian database; " \
                 "StarLing database)",
          headword: "PROTO", gloss: "MEANING",
          body: { "ADDITION" => "Additional forms", "DEDNUM" => "Number in DED" }.freeze,
          crosslinks: { "PRNUM" => "Dravidian etymology" }.freeze,
          reflexes: {}.freeze
        }.freeze
      }.freeze

      # SINTIB — the Kiranti lane: kiret (S. Starostin's Proto-Kiranti,
      # PRNUM → starling-stibet) and the four Leiden dictionaries it links
      # into (PRNUM → kiret; their own .inf aliases say "Kiranti
      # etymology" — dumet.inf's alias carries a stray byte, "Kir\xB2nti",
      # normalized to its three siblings' spelling).
      SINTIB = {
        # kiret.inf DBINFO: "The Kiranti part of the Sino-Tibetan
        # Etymological dictionary", "S. Starostin's reconstruction (not
        # published separately, but presented on the Sino-Tibetan conference
        # in Paris, 1994)"; data "from published works of Allen, Hale, Toba,
        # Van Driem and Tolsma". All seven language columns mint.
        "starling-kiret" => {
          dbf: "kiret.dbf", language: "sit-kir-pro",
          title: "Kiranti etymology (the Kiranti part of the Sino-Tibetan etymological " \
                 "dictionary; S. Starostin's reconstruction; StarLing database)",
          headword: "PROTO", gloss: "MEANING",
          body: {
            "SUN" => "Sunwar", "TUL" => "Tulung", "KAL" => "Kaling", "LIM" => "Limbu",
            "DUM" => "Dumi", "KUL" => "Kulung", "YAM" => "Yamphu", "NOTES" => "Comments"
          }.freeze,
          crosslinks: {
            "PRNUM" => "Sino-Tibetan etymology", "LIMNUM" => "->Limet", "DUMNUM" => "->Dumet",
            "KULNUM" => "->Kulet", "YAMNUM" => "->Yamet"
          }.freeze,
          reflexes: {
            "SUN" => %w[suz Sunwar].freeze, "TUL" => %w[tdh Tulung].freeze,
            "KAL" => %w[klr Kaling].freeze, "LIM" => %w[lif Limbu].freeze, "DUM" => %w[dus Dumi].freeze,
            "KUL" => %w[kle Kulung].freeze, "YAM" => %w[ybi Yamphu].freeze
          }.freeze
        }.freeze,
        # dumet.inf DBINFO: "The Dumi dictionary provided by G. Van Driem,
        # published in Van Driem 1993" (original Leiden transcription).
        "starling-dumet" => {
          dbf: "dumet.dbf", language: "dus",
          title: "Dumi dictionary (G. van Driem 1993; Leiden database in the StarLing " \
                 "Sino-Tibetan package)",
          headword: "PROTO", gloss: "MEANING",
          body: {
            "PSPEECH" => "Grammar", "NEPALI" => "Nepali", "DERCOMM" => "Derivation", "COMMENTS" => "Comments"
          }.freeze,
          crosslinks: { "PRNUM" => "Kiranti etymology" }.freeze,
          reflexes: {}.freeze
        }.freeze,
        # kulet.inf DBINFO: "The Kulung dictionary provided by G. Tolsma,
        # published in Tolsma 1999".
        "starling-kulet" => {
          dbf: "kulet.dbf", language: "kle",
          title: "Kulung dictionary (G. Tolsma 1999; Leiden database in the StarLing " \
                 "Sino-Tibetan package)",
          headword: "PROTO", gloss: "MEANING",
          body: { "PSPEECH" => "Grammar", "NEPALI" => "Nepali", "COMMENTS" => "Comments" }.freeze,
          crosslinks: { "PRNUM" => "Kiranti etymology" }.freeze,
          reflexes: {}.freeze
        }.freeze,
        # limet.inf DBINFO: "The Limbu dictionary provided by G. Van Driem,
        # published in Van Driem 1987".
        "starling-limet" => {
          dbf: "limet.dbf", language: "lif",
          title: "Limbu dictionary (G. van Driem 1987; Leiden database in the StarLing " \
                 "Sino-Tibetan package)",
          headword: "PROTO", gloss: "MEANING",
          body: { "PSPEECH" => "Grammar", "DERCOMM" => "Derivation", "COMMENTS" => "Comments" }.freeze,
          crosslinks: { "PRNUM" => "Kiranti etymology" }.freeze,
          reflexes: {}.freeze
        }.freeze,
        # yamet.inf DBINFO: "The Yamphu dictionary provided by R. Rutgers,
        # published in Rutgers 2000".
        "starling-yamet" => {
          dbf: "yamet.dbf", language: "ybi",
          title: "Yamphu dictionary (R. Rutgers 2000; Leiden database in the StarLing " \
                 "Sino-Tibetan package)",
          headword: "PROTO", gloss: "MEANING",
          body: {
            "STEM" => "Stem", "PSPEECH" => "Grammar", "COMMENTS" => "Comments", "NEPALI" => "Nepali"
          }.freeze,
          crosslinks: { "PRNUM" => "Kiranti etymology" }.freeze,
          reflexes: {}.freeze
        }.freeze
      }.freeze

      # Registry order = discover order: package by package, each package's
      # bases in the head base's own link-column order.
      BASES = ALTAIC.merge(CAUC, DRAV, SINTIB).freeze

      # The license lane's per-base credits — each base's own DBINFO words
      # (the grant's express condition: name the compilers of each
      # database), appended to Starling::MANIFEST.license.
      CREDITS =
        "Altaic branch bases (2026-10-01 extension grant): Turkic — \"the Turkic part of the Altaic " \
        "Etymological Dictionary\", Proto-Turkic \"with O. Mudrak's modifications\" (turcet.inf " \
        "DBINFO); Mongolian — \"The Mongolian part of the Altaic Etymological Dictionary\" " \
        "(monget.inf DBINFO); Tungus-Manchu — \"subordinate to the Common Altaic database. The basic " \
        "source is the TMC - the Comparative Dictionary of Tungus-Manchu Languages compiled by " \
        "Tsintsius et al.\" (tunget.inf DBINFO); Korean — koret.inf carries no DBINFO, so the credit " \
        "is the package's: the Altaic Etymological Dictionary by S. Starostin, A. Dybo and O. Mudrak; " \
        "North Caucasian branch bases: \"The Nakh part\", \"The Tsezian part\" and \"The Dargwa part of " \
        "the North Caucasian Etymological Dictionary\" (protoforms \"in S. Nikolayev's " \
        "reconstruction\"), \"The Lezghian part\" (\"in S. Starostin's reconstruction\"), \"the West " \
        "Caucasian (Abkhazo-Adyghe) part\" (\"in S. A. Starostin's reconstruction\"), \"the " \
        "Avaro-Andian part\", \"The Lak part\" and \"The Khinalug part\" (nakhet/cezet/darget/lezget/" \
        "abadet/aandet/laket/khinet.inf DBINFO); Dravidian branch bases: the South Dravidian, Telugu, " \
        "Kolami-Gadba, Gondi-Kui (Gondwan), Gondi, Kui-Kuwi, Konda, Nilgiri (Kota-Toda), North " \
        "Dravidian, Pengo-Manda and Brahui databases, each \"subordinate to the Common Dravidian " \
        "database\" (sdret/telet/kogaet/gndet/gonet/kuiet/konet/ktet/ndret/pemet/braet.inf DBINFO) " \
        "— G. Starostin's Dravidian package; Kiranti base: \"The Kiranti part of the Sino-Tibetan " \
        "Etymological dictionary\", \"S. Starostin's reconstruction\", data \"taken from published " \
        "works of Allen, Hale, Toba, Van Driem and Tolsma\" (kiret.inf DBINFO); Leiden dictionaries: " \
        "\"The Dumi dictionary provided by G. Van Driem, published in Van Driem 1993\", \"The Kulung " \
        "dictionary provided by G. Tolsma, published in Tolsma 1999\", \"The Limbu dictionary " \
        "provided by G. Van Driem, published in Van Driem 1987\", \"The Yamphu dictionary provided " \
        "by R. Rutgers, published in Rutgers 2000\" (dumet/kulet/limet/yamet.inf DBINFO)"

      # One honest witness note per new shelf language (the rider, P18).
      WITNESS = "witness:starling"
      LANGUAGE_NOTES = [
        ["trk-pro", WITNESS,
         "StarLing/Tower of Babel Turkic database (2026-10-01 extension grant): the Turkic part of " \
         "the Altaic Etymological Dictionary — 2,017 Proto-Turkic etymologies with O. Mudrak's " \
         "vocalic modifications, attested meanings enumerated, 29 language columns from Old Turkic " \
         "and Karakhanid to Yakut and Chuvash (27 mint reflex rows; the mixed-source Old Turkic and " \
         "Middle Turkic columns stay in the body), linked up into the Altaic database."].freeze,
        ["xgn-pro", WITNESS,
         "StarLing/Tower of Babel Mongolian database (same grant): the Mongolian part of the Altaic " \
         "Etymological Dictionary — 2,174 Proto-Mongolian forms (mostly coinciding with attested " \
         "Middle Mongolian) with Written and Middle Mongolian, Khalkha, Buriat, Kalmuck, Ordos, " \
         "Dongxiang, Baoan, Dagur, Shira-Yughur, Monguor and Mogol columns."].freeze,
        ["tuw-pro", WITNESS,
         "StarLing/Tower of Babel Tungus-Manchu database (same grant): 2,435 Proto-Tungus forms in " \
         "Tsintsius's classical reconstruction, after the TMC (the Comparative Dictionary of " \
         "Tungus-Manchu Languages, Tsintsius et al.), with Evenki/Even/Negidal/Manchu/Jurchen/Ulcha/" \
         "Orok/Nanai/Oroch/Udihe/Solon columns, subordinate to the Altaic database."].freeze,
        ["qfa-kor-pro", WITNESS,
         "StarLing/Tower of Babel Korean database (same grant): 1,206 'Proto-Korean' entries of the " \
         "Altaic package — by the AED's own account essentially Middle Korean (15th c.) forms with a " \
         "few internal-reconstruction modifications — with Modern and Middle Korean columns. Filed " \
         "under Wiktionary's Proto-Koreanic code, declared coarse."].freeze,
        ["cau-nkh-pro", WITNESS,
         "StarLing/Tower of Babel Nakh database (same grant): the Nakh part of the North Caucasian " \
         "Etymological Dictionary — 970 Proto-Nakh forms in S. Nikolayev's reconstruction with " \
         "Chechen, Ingush and Batsbi columns."].freeze,
        ["cau-ava-pro", WITNESS,
         "StarLing/Tower of Babel Avaro-Andian database (same grant): 1,539 entries of the North " \
         "Caucasian dictionary's Avaro-Andian part — protoforms mostly Proto-Andian (Gudava's, " \
         "modified), sometimes constructs where only Avar attests — with Avar and nine Andian " \
         "language columns."].freeze,
        ["cau-tsz-pro", WITNESS,
         "StarLing/Tower of Babel Tsezian database (same grant): 1,108 Proto-Tsezian forms in " \
         "S. Nikolayev's reconstruction with Tsez, Hinukh, Khvarshi, Inkhokvari, Bezhta and Hunzib " \
         "columns; intermediate Tsez-Khvarshi and Bezhta-Hunzib protoforms ride the comments."].freeze,
        ["lbe", WITNESS,
         "StarLing/Tower of Babel Lak database (same grant): 955 literary Lak roots and forms of the " \
         "North Caucasian Etymological Dictionary (no Proto-Lak is reconstructed — the dialects are " \
         "too close), with Khosrekh dialect evidence in the comments, linked up into the North " \
         "Caucasian database."].freeze,
        ["cau-drg-pro", WITNESS,
         "StarLing/Tower of Babel Dargwa database (same grant): 924 Proto-Dargwa forms in " \
         "S. Nikolayev's reconstruction with Akusha (literary Dargwa) and Chiragh columns."].freeze,
        ["cau-lzg-pro", WITNESS,
         "StarLing/Tower of Babel Lezghian database (same grant): 1,569 Proto-Lezghian forms in " \
         "S. Starostin's reconstruction with Lezgian, Tabasaran, Agul, Rutul, Tsakhur, Kryts, Budukh, " \
         "Archi and Udi columns."].freeze,
        ["kjj", WITNESS,
         "StarLing/Tower of Babel Khinalug database (same grant): 349 Khinalug forms of the North " \
         "Caucasian Etymological Dictionary (a single dialect, no reconstruction), linked up into " \
         "the North Caucasian database."].freeze,
        ["cau-nwc-pro", WITNESS,
         "StarLing/Tower of Babel West Caucasian database (same grant): 817 Proto-West-Caucasian " \
         "forms in S. A. Starostin's reconstruction with Abkhaz, Abaza, Adyghe, Kabardian and Ubykh " \
         "columns; Proto-Abkhaz-Tapanta and Proto-Circassian forms ride the comments."].freeze,
        ["dra-sdr-pro", WITNESS,
         "StarLing/Tower of Babel South Dravidian database (same grant): 4,692 DED-based entries " \
         "(807 still without a protoform) with Tamil, Malayalam, Kannada, Kodagu, Tulu, Irula and " \
         "Kasaba form/meaning/derivate columns and Proto-Nilgiri links. dra-sdr-pro is a code coined " \
         "from dravet's SDR siglum (Wiktionary family-prefix style)."].freeze,
        ["te-pro", WITNESS,
         "StarLing/Tower of Babel Telugu database (same grant): 2,774 entries of 'a database for " \
         "Telugu dialects' — provisional Proto-Telugu forms with standard, dialectal, Krishnamurti, " \
         "inscriptional and Merolu Telugu columns, each with its DED number."].freeze,
        ["dra-kog-pro", WITNESS,
         "StarLing/Tower of Babel Kolami-Gadba database (same grant): 1,509 Proto-Kolami-Gadba " \
         "reconstructions with Kolami, Naikri, Naiki, Parji and Gadba (Ollari, Salur, Poya, " \
         "Kondekor) columns. dra-kog-pro is coined from dravet's KOGA siglum."].freeze,
        ["dra-gnd-pro", WITNESS,
         "StarLing/Tower of Babel Gondwan (Gondi-Kui) database (same grant): 1,428 Proto-Gondwan " \
         "reconstructions with Proto-Gondi, Konda, Proto-Pengo-Manda and Proto-Kui-Kuwi columns, " \
         "linked to the four sub-databases. dra-gnd-pro is coined from dravet's GND siglum."].freeze,
        ["gon-pro", WITNESS,
         "StarLing/Tower of Babel Gondi database (same grant): 1,475 Proto-Gondi reconstructions with " \
         "seventeen Gondi dialect/source columns (Betul, Mandla, Muria, Maria, Koya, Adilabad …), " \
         "DED and Gondi-vocabulary numbers."].freeze,
        ["dra-kui-pro", WITNESS,
         "StarLing/Tower of Babel Kui-Kuwi database (same grant): 1,377 Proto-Kui-Kuwi " \
         "reconstructions with Kui, Kuttia Kui and eight Kuwi source/dialect columns. dra-kui-pro " \
         "is a coined branch code."].freeze,
        ["kfc", WITNESS,
         "StarLing/Tower of Babel Konda database (same grant): 961 Konda forms (a single language, no " \
         "reconstruction) with Bhattacharya's variants and DED numbers, linked up into the Gondwan " \
         "database."].freeze,
        ["dra-nil-pro", WITNESS,
         "StarLing/Tower of Babel Nilgiri (Kota-Toda) database (same grant): 1,665 Proto-Kota-Toda " \
         "reconstructions with Kota and Toda columns, subordinate to the South Dravidian database. " \
         "dra-nil-pro is a coined branch code."].freeze,
        ["dra-ndr-pro", WITNESS,
         "StarLing/Tower of Babel North Dravidian database (same grant): 989 Proto-North-Dravidian " \
         "reconstructions with Kurukh and Malto columns (notes occasionally in Russian). " \
         "dra-ndr-pro is coined from dravet's NDR siglum."].freeze,
        ["dra-pem-pro", WITNESS,
         "StarLing/Tower of Babel Pengo-Manda database (same grant): 740 Proto-Pengo-Manda " \
         "reconstructions with Pengo and Manda columns. dra-pem-pro is a coined branch code."].freeze,
        ["brh", WITNESS,
         "StarLing/Tower of Babel Brahui database (same grant): 269 Brahui forms (a single language, " \
         "no reconstruction) with derivatives and DED numbers, linked up into the Dravidian " \
         "database."].freeze,
        ["sit-kir-pro", WITNESS,
         "StarLing/Tower of Babel Kiranti database (same grant): 994 Proto-Kiranti forms in " \
         "S. Starostin's reconstruction (presented at the 1994 Paris Sino-Tibetan conference, not " \
         "published separately) with Sunwar, Thulung, Khaling, Limbu, Dumi, Kulung and Yamphu " \
         "columns, linked down into the four Leiden dictionaries."].freeze,
        ["dus", WITNESS,
         "StarLing/Tower of Babel Dumi dictionary (same grant): G. van Driem's Dumi dictionary " \
         "(Van Driem 1993), 1,517 entries in the original Leiden transcription with grammar, Nepali " \
         "and derivation fields, linked up into the Kiranti database."].freeze,
        ["kle", WITNESS,
         "StarLing/Tower of Babel Kulung dictionary (same grant): G. Tolsma's Kulung dictionary " \
         "(Tolsma 1999), 1,466 entries in the original Leiden transcription, linked up into the " \
         "Kiranti database."].freeze,
        ["lif", WITNESS,
         "StarLing/Tower of Babel Limbu dictionary (same grant): G. van Driem's Limbu dictionary " \
         "(Van Driem 1987), 2,354 entries in the original Leiden transcription, linked up into the " \
         "Kiranti database."].freeze,
        ["ybi", WITNESS,
         "StarLing/Tower of Babel Yamphu dictionary (same grant): R. Rutgers's Yamphu dictionary " \
         "(Rutgers 2000), 1,974 entries in the original Leiden transcription with stem, grammar and " \
         "Nepali fields, linked up into the Kiranti database."].freeze
      ].freeze
    end
  end
end

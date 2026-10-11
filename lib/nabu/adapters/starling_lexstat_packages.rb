# frozen_string_literal: true

module Nabu
  module Adapters
    # The follow-up packages' LEXSTAT/ wordlists (Q116, P118): the 48
    # lexicostatistical tables shipped inside ALTAIC / CAUC / YENISEY /
    # SINTIB / DRAV / CHUKCHEE / KART.exe beside the etymological bases —
    # the same NUMBER / WORD / <COL> + <COL>NUM shape StarlingLexstat reads
    # for IE.exe (one entry per form cell, file position 0 the per-language
    # date row), configured here per PACKAGE. Read from the files
    # themselves: column sigla are the .dbf descriptors, labels the .inf
    # `\1:` (English) field aliases verbatim, cognation targets the .inf
    # `proto =` line. Census (2026-10-11, the held 2026-09-26 package
    # trees): 48 tables, 33,379 form entries (dry-parsed at full scale).
    #
    # == Why per-package maps (the collision census)
    #
    # A siglum is a column name local to ONE package, never a language id:
    # the same three letters name different languages across packages —
    # MAN is Spoken Manchu (altaic), Manipuri (sintib) and Manda (drav); KAN
    # Kanauri / Kannada; CHE Chechen / Chepang; KON Konyak / Konda; KOT
    # Kottish / Kota; PUM Pumpokol / Pumi; TAM Tamang / Tamil; HAK
    # Khakassian / Haka; KAB Kabardian / Kabui; LSH Lushai / Lashkh Svan;
    # UBA Upper-Bangni / Upper Bal Svan; and against IE.exe's map KAL
    # Kalmuck / Kalasha, TAT Tatar / Tat, SHU Shuri / Shumashti, MGR
    # Monguor / Modern Greek, GAL Gallong / Galician, KHO Khoirao / Khowar,
    # MAR Maram / Marathi, PAR Parji / Pahari (19 sigla, computed over the
    # maps). So every package carries its own LANGUAGES map and a table
    # reads only its package's.
    #
    # Within a package, a branch table's own .inf WINS over the union
    # table's (recorded upstream reality, never harmonized): altaic's
    # tung.inf calls MAN "Spoken Manchu" (beside LMA "Literary Manchu")
    # where alt.inf/tunget.inf say "Literary Manchu" for both; kor.inf
    # calls PHN "Phyenyang" where alt.inf/koret.inf say "Modern Korean";
    # turc.inf calls AZB "Azeri" where alt.inf says "Azerbaidzhan". The
    # union table alt.dbf therefore reads its MAN column as Spoken Manchu
    # too — the date row agrees (MAN 20, LMA 18).
    #
    # Labels a table's own .inf lacks come from a sibling .inf IN THE SAME
    # PACKAGE (all censused): mong AMO from alt.inf; abad's five columns
    # from abadet.inf; aand AVC from aandet.inf; yen's five from yenet.inf;
    # kir YAM from kiret.inf (kir.inf aliases the other five); drav
    # KAN/KOD/TUL from sdret.inf, KON from gndet.inf, KUI from kuiet.inf,
    # KUR/MLT from ndret.inf, BRA from dravet.inf; kam ALU from chuket.inf,
    # WIT/SIT from itelet.inf; kart MEG/LAZ from kartet.inf.
    #
    # == Inferred readings (wave C, ruled 2026-10-11)
    #
    # Twenty-one columns of drav / kam / kart carry NO alias anywhere
    # upstream (or only an alias naming a different column shape — dravet's
    # TEL "Proto-Telugu", gndet's GON "Proto-Gondi"). The ruling adopts the
    # standard reading of each siglum; every such row is flagged
    # :inferred and the parse carries "inferred, not documented upstream"
    # into the shelf title and the entry's Language line:
    # - drav (11): KOT Kota, TOD Toda, TEL Telugu, KOL Kolami, NAI Naikri,
    #   PAR Parji, GAD Gadba, GON Gondi, PEN Pengo, MAN Manda, KUW Kuwi —
    #   the Burrow–Emeneau DED abbreviations (Ko./To./Te./Kol./Nk./Pa./
    #   Ga./Go./Pe./Manḍ./Kuwi), in the DED's own column order.
    # - kam (6): CHQ Chukchee, KRQ Koryak, PLQ Palana, ITL Itelmen (the
    #   chuket/itelet column names with a Q/L suffix); KAR Karaga — the
    #   Kamchadal record of Krasheninnikov's era, which the table's own date
    #   row dates 17.5 (mid-18th century); IRS Itelmen after Khaloymova's
    #   Itelmen-Russian dictionary (itelet.inf's IRSLOV alias names that
    #   source "Khaloymova (IRS)").
    # - kart (4): GEO Georgian (kartet aliases GRU, not GEO); UBA Upper
    #   Bal, LSH Lashkh, LEN Lentekh — the standard Svan dialect names.
    #
    # == Codes (DECLARED, conservative — they drive only the fold)
    #
    # dictionary_entries persist no per-entry language, so a column's code
    # only picks the fold rules (the P113-2 posture). The branch bases'
    # codes are reused verbatim where a column recurs (StarlingBranchBases);
    # nil wherever no single unambiguous code exists — locality dialects
    # (the Japanese/Korean/Ryukyuan points, Ergong, the Angami villages…),
    # mixed-source columns (ATU Old Turkic, the turcet verdict), varieties
    # without a code (Spoken Manchu, Palana, Karaga, Chadakolob, Kasaba…)
    # and split languages (Gurung, Tamang, Magar, Kham, Pumi, Tujia) — the
    # entry then folds under its shelf code.
    #
    # Shelf languages: the branch code the registry already carries (tut
    # jpx qfa-kor xgn tuw trk cau-ava cau-nwc cau-tsz cau-drg cau-lzg
    # cau-nkh qfa-yen dra qfa-cka ccs; kjj and lbe for the two
    # single-language Caucasian lists). SINTIB: sit-kir for the Kiranti
    # table, tbq (Tibeto-Burman) for the other 29 — DECLARED COARSENESS:
    # their subgroups (Bodo-Garo, Lolo-Burmese, Karenic, Tani, Qiangic…)
    # have no registry node, and a subgroup code is a nabu-lects matter.
    #
    # == Cognation: resolve-or-verbatim
    #
    # A positive cognation number is a link ONLY if it resolves: the parse
    # reads the target base's NUMBER set (the .inf `proto =` table, held
    # beside the package's LEXSTAT/) and writes "<label>: #N" for a hit,
    # the verbatim "Cognation number: N" otherwise — never a dead link.
    # Census of positive cells: altaic/cauc/yenisey 100% (turc 2,177 of
    # 2,181: CHV/JAK point at #3334/#3335, past turcet's last record);
    # sintib 79.6–94.4% per table (the misses are numbers 4000+, past
    # stibet's 2,823 records — an unfinished numbering upstream); drav
    # 99.4%; kam 86.2% (2001+, past kamet's 1,099); kart has `proto = NONE`
    # — its numbers are table-internal cognate classes and ALL ride
    # verbatim.
    module StarlingLexstatPackages
      INFERRED = "inferred, not documented upstream"

      # [code or nil, label] — label is the in-package .inf alias verbatim;
      # a third element :inferred marks a ruled standard reading.
      ALTAIC = {
        # Turkic (turc.inf; alt.inf concurs except AZB "Azerbaidzhan")
        "TRK" => %w[tr Turkish], "TAT" => %w[tt Tatar], "UZB" => %w[uz Uzbek], "UIG" => %w[ug Uighur],
        "SJG" => %w[ybe Sary-Yughur], "AZB" => %w[az Azeri], "TRM" => %w[tk Turkmen],
        "HAK" => %w[kjh Khakassian], "CHV" => %w[cv Chuvash], "JAK" => %w[sah Yakut], "TUV" => %w[tyv Tuva],
        "KRG" => %w[ky Kirghiz], "NOG" => %w[nog Noghai], "BAS" => %w[ba Bashkir], "BLK" => %w[krc Balkar],
        "GAG" => %w[gag Gagauz], "KRM" => %w[kdr Karaim], "KLP" => %w[kaa Karakalpak],
        "ATU" => [nil, "Old Turkic"], "SAL" => %w[slr Salar],
        # Mongolian (mong.inf; AMO from alt.inf)
        "AMO" => ["xng", "Middle Mongolian"], "HAL" => %w[mn Khalkha], "KAL" => %w[xal Kalmuck],
        "DUN" => %w[sce Dongxian], "BAO" => %w[peh Baoan], "DAG" => %w[dta Dagur], "MGR" => %w[mjg Monguor],
        "YUY" => %w[yuy Shary-Yoghur],
        # Tungus-Manchu (tung.inf — MAN "Spoken Manchu" wins over alt.inf)
        "NEG" => %w[neg Negidal], "MAN" => [nil, "Spoken Manchu"], "LMA" => ["mnc", "Literary Manchu"],
        "NAN" => %w[gld Nanai], "ULC" => %w[ulc Ulcha], "ORK" => %w[oaa Orok], "CHU" => %w[juc Jurchen],
        "EVK" => %w[evn Evenki],
        # Korean (kor.inf — PHN "Phyenyang" wins over alt.inf "Modern Korean")
        "PHN" => %w[ko Phyenyang], "CHN" => [nil, "Chensando"], "PNM" => [nil, "Phyenyang-namdo"],
        "KJN" => [nil, "Kyensando"], "HMG" => [nil, "Hamgyengdo"], "CJD" => [nil, "Chejudo"],
        "SEU" => [nil, "Seoul"], "KNW" => [nil, "Kanwendo"], "AKO" => ["okm", "Middle Korean"],
        # Japanese + Ryukyuan (jap.inf; the japet verdict: only AJP is an attested language)
        "TOK" => [nil, "Tokyo"], "KAM" => [nil, "Kameyama"], "KYO" => [nil, "Kyoto"],
        "KAG" => [nil, "Kagoshima"], "AJP" => ["ojp", "Old Japanese"], "NAS" => [nil, "Nase"],
        "SHU" => [nil, "Shuri"], "HAT" => [nil, "Hateruma"], "YON" => [nil, "Yonakuni"]
      }.transform_values(&:freeze).freeze

      CAUC = {
        # aand.inf (AVC from aandet.inf)
        "AVA" => %w[av Avar], "AVC" => [nil, "Chadakolob"], "AND" => ["ani", "Andi language"],
        "AKV" => %w[akv Akhvakh], "CHM" => %w[cji Chamalal], "TND" => %w[tin Tindi],
        # abadet.inf (abad.inf carries no aliases)
        "ABK" => %w[ab Abkhaz], "ABA" => %w[abq Abaza], "ADG" => %w[ady Adyghe],
        "KAB" => %w[kbd Kabardian], "UBK" => %w[uby Ubykh],
        # cez.inf
        "CEZ" => %w[ddo Tsezi], "GIN" => %w[gin Ginukh], "KHV" => %w[khv Khvarshi],
        "INH" => [nil, "Inkhokvari"], "BZT" => %w[kap Bezhta], "GNZ" => %w[huz Gunzib],
        # darg.inf / khin.inf / lak.inf
        "DRG" => %w[dar Akusha], "CHR" => [nil, "Chiragh"], "KHI" => %w[kjj Khinalug], "LAK" => %w[lbe Lak],
        # lezg.inf
        "LZG" => %w[lez Lezghian], "TAB" => %w[tab Tabasaran], "AGU" => %w[agx Agul], "RUT" => %w[rut Rutul],
        "CAK" => %w[tkr Tsakhur], "KRZ" => %w[kry Kryz], "BUD" => %w[bdk Budukh], "ARC" => %w[aqc Archi],
        "UDI" => %w[udi Udi],
        # nakh.inf
        "CHE" => %w[ce Chechen], "ING" => %w[inh Ingush], "BCB" => %w[bbl Batsbi]
      }.transform_values(&:freeze).freeze

      # yen.inf carries no aliases; yenet.inf's (same columns, same package).
      YENISEY = {
        "KET" => %w[ket Ket], "SYM" => %w[yug Yug], "KOT" => %w[zko Kottish], "ARI" => %w[xrn Arin],
        "PUM" => %w[xpm Pumpokol]
      }.transform_values(&:freeze).freeze

      # Each table's own .inf (YAM from kiret.inf; YIM/LUS decoded from the
      # .inf's StarLing byte \xF2 = ü).
      SINTIB = {
        "AKA" => %w[hru Aka], "MJI" => %w[sjl Miji],
        "BOD" => %w[brx Bodo], "DIM" => %w[dis Dimasa], "GAR" => %w[grt Garo], "RAB" => %w[rah Rabha],
        "WRB" => %w[my Burmese], "LAN" => %w[mhx Langsu-Maru], "ZHA" => %w[atb Zhaiwa],
        "ACH" => %w[acn Achang], "XID" => %w[xia Xiandao], "BOL" => %w[bxd Bola], "LEQ" => [nil, "Leqi"],
        "LIJ" => %w[nxq Lijiang-Naxi], "NIN" => [nil, "Ninglang-Naxi"], "JIN" => [nil, "Jinuo"],
        "CHE" => %w[cdm Chepang],
        "LSH" => %w[lus Lushai], "HAK" => %w[cnh Haka], "HMA" => %w[hmr Hmar], "GAN" => %w[gnb Gangte],
        "TID" => %w[ctd Tiddim],
        "DHI" => %w[dhi Dhimal],
        "GUR" => [nil, "Gurung"], "TAM" => [nil, "Tamang"], "THA" => %w[ths Thakali],
        "TAR" => %w[mhu Taraon], "IDU" => %w[clk Idu],
        "JIA" => [nil, "Jiarung"], "JNP" => %w[kac Jingpo], "KAN" => %w[kfk Kanauri],
        "PAO" => %w[blk Pa'O], "GEB" => %w[kvq Geba], "KAP" => [nil, "Kayan-Pekon"], "YEI" => [nil, "Yeinbaw"],
        "PDN" => %w[pdu Padaung], "GEK" => [nil, "Geker"], "MNU" => [nil, "Manu"], "KYH" => %w[kyu W.Kayah],
        "YIN" => %w[kvy Yintale], "SGO" => %w[ksw Sgaw], "KEL" => [nil, "Kelun"], "PLC" => [nil, "Palaichi"],
        "KAY" => %w[kzq Kaike], "KHA" => [nil, "Kham"],
        "SUN" => %w[suz Sunwar], "KUL" => %w[kle Kulung], "KLN" => %w[klr Khaling], "DUM" => %w[dus Dumi],
        "LIM" => %w[lif Limbu], "YAM" => %w[ybi Yamphu],
        "KNN" => [nil, "Konyak-D"], "KON" => %w[nbe Konyak], "PHO" => %w[nph Phom], "CHA" => %w[nbc Chang],
        "YOG" => [nil, "Yogli"], "NOC" => %w[njb Nocte], "WAN" => %w[nnp Wancho],
        "LEP" => %w[lep Lepcha], "MAG" => [nil, "Magar"], "MAN" => %w[mni Manipuri],
        "MIJ" => %w[mxj Miju-Geman], "MIK" => %w[mjw Mikir], "MOT" => [nil, "Motuo-M"],
        "REN" => [nil, "Rengma"], "SEM" => %w[nsm Sema], "TAN" => %w[nmf Tangkul], "LHO" => %w[njh Lhota],
        "POC" => %w[npo Pochuri], "SAN" => %w[nsa Sangtam], "YIM" => %w[yim Yimchungrü],
        "AOC" => %w[njo Ao-Chungli], "AOM" => [nil, "Ao-Mongsen"], "MAO" => %w[nbi Mao],
        "KHE" => %w[nkh Khezhama], "CHO" => %w[nri Chokri], "KHN" => [nil, "Ang.-Khonoma"],
        "KHM" => [nil, "Ang.Kohima"], "MZI" => %w[nme Mzieme], "ZEM" => %w[nzm Zeme], "LIA" => %w[njn Liangmai],
        "MAR" => %w[nma Maram], "KHO" => [nil, "Khoirao"], "KAB" => %w[nbu Kabui],
        "ROU" => [nil, "Rourou"], "NUS" => %w[nuf Nusu],
        "SER" => %w[sdp Serdukpen], "SUL" => %w[suv Sulong], "BUG" => %w[bgg Bugun],
        "QIN" => %w[qxs S-Qiang], "QIA" => %w[cng N-Qiang], "MUY" => %w[mvm Muya], "PUM" => [nil, "Pumi1"],
        "PMI" => [nil, "Pumi2"], "ZHB" => %w[zhb Zhaba], "QUE" => %w[qvy Queyu], "ERG" => [nil, "Ergong"],
        "DAO" => [nil, "Daofu=Horpa"], "SHI" => %w[sxg Shixing], "NAM" => %w[nmy Namuzi],
        "GUI" => %w[gqi Guiqiong], "ERS" => %w[ers Ersu], "LUS" => [nil, "Lüsu"], "GAZ" => [nil, "Gazhuo"],
        "MIL" => [nil, "Milang"], "PAD" => [nil, "Padam"], "SHA" => [nil, "Shaiyang"], "APA" => %w[apt Apatani],
        "GAL" => %w[adl Gallong], "HIL" => [nil, "Hill-Miri"], "BOK" => [nil, "Bokar"], "NIS" => %w[njz Nishi],
        "TAG" => %w[tgj Tagin], "UBA" => [nil, "Upper-Bangni"],
        "WRT" => %w[xct Writ.Tib], "LHA" => %w[bo Lhasa], "BAT" => [nil, "Batang-T"], "XIA" => [nil, "Xiaxe-T"],
        "ALI" => [nil, "Alike-T"], "JIR" => %w[jul Jirel], "SHE" => %w[xsr Sherpa], "CUO" => [nil, "Cuona-M"],
        "ANO" => %w[nun Anong], "RAW" => %w[raw Rawang], "DUL" => %w[duu Dulong],
        "TUJ" => [nil, "Tujia"]
      }.transform_values(&:freeze).freeze

      DRAV = {
        # drav.inf
        "TAM" => %w[ta Tamil], "MUD" => %w[udg Muduva], "IRU" => %w[iru Irula], "MAL" => %w[ml Malayalam],
        "YER" => %w[yeu Yerukala], "KAS" => [nil, "Kasaba"],
        # sibling .infs of the package
        "KAN" => %w[kn Kannada], "KOD" => %w[kfa Kodagu], "TUL" => %w[tcy Tulu], "KON" => %w[kfc Konda],
        "KUI" => %w[kxu Kui], "KUR" => %w[kru Kurukh], "MLT" => %w[mjt Malto], "BRA" => %w[brh Brahui],
        # ruled standard readings (the DED abbreviations)
        "KOT" => %w[kfe Kota], "TOD" => %w[tcx Toda], "TEL" => %w[te Telugu],
        "KOL" => %w[kfb Kolami], "NAI" => [nil, "Naikri"], "PAR" => %w[pci Parji],
        "GAD" => [nil, "Gadba"], "GON" => %w[gon Gondi], "PEN" => %w[peg Pengo],
        "MAN" => %w[mha Manda], "KUW" => %w[kxv Kuwi]
      }.freeze

      CHUKCHEE = {
        "ALU" => %w[alr Alutor], "WIT" => [nil, "Western Kamchadal"], "SIT" => [nil, "Southern Kamchadal"],
        "CHQ" => %w[ckt Chukchee], "KRQ" => %w[kpy Koryak], "PLQ" => [nil, "Palana"],
        "KAR" => [nil, "Karaga"], "ITL" => %w[itl Itelmen], "IRS" => ["itl", "Itelmen (Khaloymova)"]
      }.freeze

      KART = {
        "MEG" => %w[xmf Megrel], "LAZ" => %w[lzz Laz],
        "GEO" => %w[ka Georgian], "UBA" => ["sva", "Upper Bal Svan"], "LSH" => ["sva", "Lashkh Svan"],
        "LEN" => ["sva", "Lentekh Svan"]
      }.freeze

      # The ruled standard readings above, per package — the flag that puts
      # "inferred, not documented upstream" on the shelf title and on every
      # entry of the column (a nil-code inferred row is still inferred).
      INFERRED_COLUMNS = {
        "drav" => %w[KOT TOD TEL KOL NAI PAR GAD GON PEN MAN KUW],
        "chukchee" => %w[CHQ KRQ PLQ KAR ITL IRS],
        "kart" => %w[GEO UBA LSH LEN]
      }.transform_values(&:freeze).freeze

      # package => { siglum => [code or nil, label, inferred?] }
      def self.normalize(package, map)
        inferred = INFERRED_COLUMNS.fetch(package, [])
        map.to_h do |siglum, (code, label)|
          [siglum, [code, label, inferred.include?(siglum)].freeze]
        end.freeze
      end

      LANGUAGES = {
        "altaic" => normalize("altaic", ALTAIC), "cauc" => normalize("cauc", CAUC),
        "yenisey" => normalize("yenisey", YENISEY), "sintib" => normalize("sintib", SINTIB),
        "drav" => normalize("drav", DRAV), "chukchee" => normalize("chukchee", CHUKCHEE),
        "kart" => normalize("kart", KART)
      }.freeze

      PACKAGE_NAMES = {
        "altaic" => "Altaic", "cauc" => "North Caucasian", "yenisey" => "Yenisseian",
        "sintib" => "Sino-Tibetan", "drav" => "Dravidian", "chukchee" => "Chukchee-Kamchatkan",
        "kart" => "Kartvelian"
      }.freeze

      # package => [[stem, shelf language, target .dbf (nil = none), cognation label, subject]]
      ROWS = {
        "altaic" => [
          ["alt", "tut", "altet.dbf", "Altaic etymology",
           "Altaic (all five branches: Turkic, Mongolian, Tungus-Manchu, Korean, Japanese — the package's " \
           "union table)"],
          ["jap", "jpx", "japet.dbf", "Japanese etymology", "Japanese and Ryukyuan dialect"],
          ["kor", "qfa-kor", "koret.dbf", "Korean etymology", "Korean dialect"],
          ["mong", "xgn", "monget.dbf", "Mongolian etymology", "Mongolian"],
          ["tung", "tuw", "tunget.dbf", "Tungus-Manchu etymology", "Tungus-Manchu"],
          ["turc", "trk", "turcet.dbf", "Turkic etymology", "Turkic"]
        ],
        "cauc" => [
          ["aand", "cau-ava", "aandet.dbf", "Avaro-Andian etymology", "Avaro-Andian"],
          ["abad", "cau-nwc", "abadet.dbf", "West Caucasian etymology", "Abkhaz-Adyghe (West Caucasian)"],
          ["cez", "cau-tsz", "cezet.dbf", "Tsezian etymology", "Tsezian"],
          ["darg", "cau-drg", "darget.dbf", "Dargwa etymology", "Dargwa"],
          ["khin", "kjj", "khinet.dbf", "Khinalug etymology", "Khinalug"],
          ["lak", "lbe", "laket.dbf", "Lak etymology", "Lak"],
          ["lezg", "cau-lzg", "lezget.dbf", "Lezghian etymology", "Lezghian"],
          ["nakh", "cau-nkh", "nakhet.dbf", "Nakh etymology", "Nakh"]
        ],
        "yenisey" => [
          ["yen", "qfa-yen", "yenet.dbf", "Yenisseian etymology", "Yenisseian"]
        ],
        "sintib" => [
          ["aka", "tbq", "stibet.dbf", "Sino-Tibetan etymology", "Aka and Miji"],
          ["bodo", "tbq", "stibet.dbf", "Sino-Tibetan etymology", "Bodo-Garo"],
          ["bur", "tbq", "stibet.dbf", "Sino-Tibetan etymology", "Burmish, Naxi and Jinuo"],
          ["che", "tbq", "stibet.dbf", "Sino-Tibetan etymology", "Chepang"],
          ["chin", "tbq", "stibet.dbf", "Sino-Tibetan etymology", "Kuki-Chin"],
          ["dhim", "tbq", "stibet.dbf", "Sino-Tibetan etymology", "Dhimal"],
          ["gur", "tbq", "stibet.dbf", "Sino-Tibetan etymology", "Gurung, Tamang and Thakali"],
          ["idu", "tbq", "stibet.dbf", "Sino-Tibetan etymology", "Taraon and Idu"],
          ["jar", "tbq", "stibet.dbf", "Sino-Tibetan etymology", "Jiarung"],
          ["jnp", "tbq", "stibet.dbf", "Sino-Tibetan etymology", "Jingpo"],
          ["kan", "tbq", "stibet.dbf", "Sino-Tibetan etymology", "Kanauri"],
          ["kar", "tbq", "stibet.dbf", "Sino-Tibetan etymology", "Karenic"],
          ["kay", "tbq", "stibet.dbf", "Sino-Tibetan etymology", "Kaike"],
          ["kha", "tbq", "stibet.dbf", "Sino-Tibetan etymology", "Kham"],
          ["kir", "sit-kir", "kiret.dbf", "Kiranti etymology", "Kiranti"],
          ["knyk", "tbq", "stibet.dbf", "Sino-Tibetan etymology", "Konyak"],
          ["lep", "tbq", "stibet.dbf", "Sino-Tibetan etymology", "Lepcha"],
          ["mag", "tbq", "stibet.dbf", "Sino-Tibetan etymology", "Magar"],
          ["man", "tbq", "stibet.dbf", "Sino-Tibetan etymology", "Manipuri"],
          ["miju", "tbq", "stibet.dbf", "Sino-Tibetan etymology", "Miju"],
          ["mik", "tbq", "stibet.dbf", "Sino-Tibetan etymology", "Mikir"],
          ["mot", "tbq", "stibet.dbf", "Sino-Tibetan etymology", "Motuo-M"],
          ["naga", "tbq", "stibet.dbf", "Sino-Tibetan etymology", "Naga"],
          ["nung", "tbq", "stibet.dbf", "Sino-Tibetan etymology", "Rourou and Nusu"],
          ["sul", "tbq", "stibet.dbf", "Sino-Tibetan etymology", "Serdukpen, Sulong and Bugun"],
          ["syc", "tbq", "stibet.dbf", "Sino-Tibetan etymology", "Qiangic"],
          ["tani", "tbq", "stibet.dbf", "Sino-Tibetan etymology", "Tani"],
          ["tib", "tbq", "stibet.dbf", "Sino-Tibetan etymology", "Tibetan"],
          ["trun", "tbq", "stibet.dbf", "Sino-Tibetan etymology", "Anong, Rawang and Dulong"],
          ["tuja", "tbq", "stibet.dbf", "Sino-Tibetan etymology", "Tujia"]
        ],
        "drav" => [
          ["drav", "dra", "dravet.dbf", "Dravidian etymology", "Dravidian"]
        ],
        "chukchee" => [
          ["kam", "qfa-cka", "kamet.dbf", "Chukchee-Kamchatkan etymology", "Chukchee-Kamchatkan"]
        ],
        "kart" => [
          ["kart", "ccs", nil, nil, "Kartvelian"]
        ]
      }.transform_values { |rows| rows.map(&:freeze).freeze }.freeze

      # slug => table row (the StarlingLexstat::TABLES shape + :package and
      # :target). A table without a target (kart: `proto = NONE`) rides
      # every cognation number verbatim.
      TABLES = ROWS.flat_map do |package, rows|
        rows.map do |stem, language, target, cognation, subject|
          into = if target
                   "cognation numbers into the #{cognation.delete_suffix(' etymology')} database " \
                     "#{File.basename(target, '.dbf')}"
                 else
                   "cognation numbers table-internal, proto = NONE"
                 end
          ["starling-lexstat-#{stem}", {
            dbf: "#{stem}.dbf", package: package, language: language, target: target, cognation: cognation,
            title: "#{subject} lexicostatistical wordlist (StarLing #{PACKAGE_NAMES.fetch(package)} package " \
                   "LEXSTAT/#{stem}; #{into})"
          }.freeze]
        end
      end.to_h.freeze

      # Held, deliberately: sino (Big5 CHARACTER cells — the bigchina
      # second-encoding lane), stls (a same-depth union of the 30 SINTIB
      # branch tables — declined as duplicate), sinocalc (a
      # glottochronology result matrix, not lexical).
      HELD = %w[sino stls sinocalc].freeze
    end
  end
end

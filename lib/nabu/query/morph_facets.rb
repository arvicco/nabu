# frozen_string_literal: true

require_relative "../errors"

module Nabu
  module Query
    # Morphology facets (P13-6): the `--morph case=dat,number=pl` filter that
    # rides on top of lemma search. A tiny query language (comma-joined
    # key=value pairs, ANDed) matched against the per-token morphology already
    # stored in annotations_json — no new index, no re-parse of canonical.
    #
    # == One façade over many tagsets (the vocabulary verdict)
    #
    # The treebank shelves speak several morphology dialects, and this module
    # folds the ones that HAVE inflectional morphology into ONE query
    # vocabulary — the Universal Dependencies feature names (case/number/
    # gender/person/tense/mood/voice/degree, values Nom/Plur/Aor…), because UD
    # is (a) a documented public standard a user can look up, and (b) already
    # the STORED form for the CoNLL-U family, so that family needs zero
    # translation. Each tagset is one row of DECODERS (token key → decode
    # method); a new tagset is one row + one decode method + its tests:
    #
    # - CoNLL-U / UD (grc-perseus, got, …): the token's `feats` string is
    #   `Case=Dat|Number=Plur|…` verbatim. Parsed as-is (lowercased). Any UD
    #   feature key is therefore queryable, not just the ones PROIEL decodes.
    # - PROIEL / TOROT (chu, orv, PROIEL grc/lat): the token's `morphology` is
    #   a 10-position positional tag (`-p---mgpwi` = plural masc genitive
    #   positive). DECODED here, position by position, into the SAME UD feature
    #   names. The decode table is the bounded, fiddly bit the design note flags
    #   — but it is a fixed 10×~8 code map, not open-ended.
    # - AGDT (GLAUx): the token's `postag` is the 9-slot AGDT positional tag
    #   (`v3saia---` = 3rd sing aorist indicative active). Slots 2-9 carry the
    #   same eight categories, in the same order and with the same code
    #   letters, as PROIEL positions 1-8, so they decode through PROIEL_FIELDS
    #   (see AGDT_FIELDS); slot 1 (pos) is not decoded.
    # - ORACC (akk, sux): tokens carry a NER-flavoured `pos` (N/PN/GN/DN/V…) and
    #   NO inflectional morphology (upstream `morph`/`base` is an un-ingested
    #   enrichment, conventions §6). So inflectional facets NEVER match ORACC —
    #   honest absence, not an error. A unified `pos` facet was deliberately
    #   left out of v1: ORACC's tagset is not UD upos, and welding a third
    #   incompatible pos scheme into the façade would be dishonest for the sake
    #   of one field. It is a clean follow-up.
    #
    # A query key that UD carries but the positional decodes do not (e.g.
    # `aspect`, `verbform`) simply matches UD passages and not PROIEL/AGDT ones
    # — the same honest, documented cross-family divergence: the vocabulary is
    # UD, and where a treebank encodes a category UD's way (grc-perseus writes
    # an aorist as Aspect=Perf|Tense=Past, not Tense=Aor) the query must follow
    # that treebank's convention.
    #
    # == Source-scoped rows (the key collisions)
    #
    # The treebank keys above are unambiguous library-wide. The later
    # tagsets' keys are NOT: "morph" is OSHB's code AND REF/coptic/vakk/
    # penn-psd tags, "msd" is CorA (ReM/ReN), IMP (goo300k), NKJP and RIIG,
    # "analyses" is Diorisis and aoxml. So a DECODERS row carries a source
    # scope (slug list; nil = any source) and decodes only its own sources'
    # tokens — the caller passes the passage's source slug (LemmaSearch
    # does). A token from a source outside every scope decodes nothing:
    # honest absence, never another tagset's misreading.
    #
    # == Readings (ambiguity, kept honest)
    #
    # A decoder returns one feature hash or a list of them — alternative
    # READINGS (Diorisis lists every candidate Morpheus analysis; Menota
    # "|"-joins whole analyses). A value may itself be a list of
    # alternatives within a reading (Diorisis "masc/neut", CorA
    # "Masc-Neut" / "Masc,Neut", Menota "gMFN", OSHB/Abegg gender "b").
    # match? is true when ANY reading satisfies EVERY facet (so cross-feature
    # correlation survives: "masc acc | neut nom" never matches masc+nom);
    # features keeps only what is CERTAIN (one value shared by every
    # reading); describe renders the readings that matched.
    #
    # == The later tagsets (one row + one decoder each)
    #
    # - Diorisis `analyses` (Morpheus prose strings, "aor ind act 3rd sg"):
    #   the 59-word inventory (censused over all 820 files) maps onto the
    #   PROIEL/AGDT spellings; dialect parentheticals and lexical flags
    #   (indeclform, proclitic, adverbial …) are skipped.
    # - BHSA (ETCBC word features gn/nu/ps/st/vs/vt, read off the token):
    #   person/number/gender + `state` (abs/cons/emph) + the Semitic verbal
    #   categories under their own keys — `stem` (vs, ETCBC spelling
    #   verbatim) and `conjugation` (vt verbatim: perf impf wayq impv infa
    #   infc ptca ptcp) — never forced into Greek tense values. The
    #   conjugations that ARE moods derive `mood` (impv → imp, inf* → inf,
    #   ptc* → part), the PROIEL/AGDT convention.
    # - DSS (Abegg's decomposed features): the same keys, with Abegg's stem/
    #   tense names recoded to the ETCBC spelling by upstream's OWN
    #   harmonization pairs (vs → vs_etcbc, vt → vt_etcbc, ABEGG_STEMS) so one
    #   query reaches bhsa and dss. The *_etcbc layer itself is silver
    #   ("additions based on BHSA and machine learning") and is NOT merged
    #   into Abegg's gold features (the adapter's label-or-omit discipline).
    # - OSHB `morph` (H/A + "/"-joined segments): the word is the last
    #   non-suffix segment; the table is upstream's read/Script/
    #   MorphologyParser.js. Stems keep OSHB's own names (niphal, hiphil …:
    #   the ETCBC and OSHB stem systems are not 1:1 — measured over the
    #   bridging osm alignment — so no crosswalk is claimed); aspects fold
    #   into the shared conjugation values where the alignment is 1:1
    #   (sequential forms and jussive/cohortative fold as ETCBC does, the
    #   latter two adding mood).
    # - CorA `msd` (ReM, ReN): dot-joined self-describing values decoded by
    #   identity; inflection classes and "*"/"_" placeholders skipped.
    # - IMP `msd` (goo300k): the coarse closed tagset of the corpus root's
    #   own fvLib — nominal gender, verbal aspect, adjectival/adverbial
    #   degree.
    # - Menota `msa` (menota): category-letter codes; word class,
    #   government, inflection class and species are skipped.
    # - Coptic Scriptorium `pos` (coptic-scriptorium): the Scriptorium
    #   tagset carries no inflection of its own — person/number/gender sit
    #   in the word form, and reach the façade only through the UD `feats`
    #   the CoNLL-U join puts on a token (that row outranks this one). The
    #   tag decodes exactly what the TAG fixes, measured against upstream's
    #   OWN UD conversion: over the release's 1,586 CoNLL-U files, the
    #   features every feature-bearing token of a tag carries (NEG/ANEG*/
    #   ANY Polarity=Neg 100%; the personal pronouns PronType=Prs +
    #   Definite=Def 99.9%+; PPOS adds Poss=Yes; PDEM PronType=Dem +
    #   Definite=Def; ART PronType=Art; NUM NumType=Card; VBD/VIMP/VSTAT
    #   VerbForm=Fin). VIMP also decodes Mood=Imp (the tagset's imperative;
    #   upstream's later conversions mark it, 25% of VIMP tokens). Not
    #   decoded: ART definiteness (ⲟⲩ vs ⲡ — the lemma, not the tag), V
    #   (finite 95.7% / infinitive 4.3%), PINT (Int/Ind split), EXIST and
    #   COP (lemma-dependent), the plain auxiliaries (no UD feature). A
    #   fused tag (ANEGPST_PPERS — a pronoun cliticized on its host)
    #   decodes every part.
    module MorphFacets
      # A malformed --morph string (empty, no `=`, blank key/value). Caller-
      # fixable, so CLI/MCP surface it as a plain usage error.
      class Error < Nabu::Error; end

      # Query-value abbreviations a user is likely to type → the canonical UD
      # value (lowercased). Deliberately tiny: most UD values ARE what you'd
      # type lowercased (dat, gen, aor, opt, masc, act), so only the number
      # abbreviations genuinely need help.
      VALUE_ALIASES = {
        "sg" => "sing", "pl" => "plur", "du" => "dual",
        # The Aramaic determined state IS the emphatic state (OSHB/Abegg say
        # "determined", ETCBC "emphatic"): one value, both spellings.
        "det" => "emph"
      }.freeze

      # PROIEL positional morphology decode, position (0-based) → [UD facet key,
      # {code => UD value}]. Ten positions in order: person, number, tense,
      # mood, voice, gender, case, degree, strength, inflection. The last two
      # (Germanic strong/weak; inflecting flag) have no clean UD facet and are
      # intentionally left undecoded — absence over a wrong mapping.
      PROIEL_FIELDS = [
        ["person", { "1" => "1", "2" => "2", "3" => "3" }],
        ["number", { "s" => "sing", "d" => "dual", "p" => "plur" }],
        ["tense",  { "p" => "pres", "i" => "impf", "a" => "aor", "r" => "perf",
                     "l" => "plup", "f" => "fut", "t" => "futperf", "u" => "past", "s" => "res" }],
        ["mood",   { "i" => "ind", "s" => "sub", "m" => "imp", "o" => "opt",
                     "n" => "inf", "p" => "part", "d" => "ger", "g" => "gdv", "u" => "sup" }],
        ["voice",  { "a" => "act", "m" => "mid", "p" => "pass", "e" => "mp", "d" => "dep" }],
        ["gender", { "m" => "masc", "f" => "fem", "n" => "neut" }],
        ["case",   { "n" => "nom", "a" => "acc", "g" => "gen", "d" => "dat",
                     "b" => "abl", "v" => "voc", "l" => "loc", "i" => "ins" }],
        ["degree", { "p" => "pos", "c" => "cmp", "s" => "sup" }]
      ].freeze

      # AGDT positional postag decode, slot (0-based) → [UD facet key, codes],
      # or nil for a slot left undecoded. Nine slots: pos, then person …
      # degree. The AGDT guidelines' code letters for those eight categories
      # coincide with PROIEL's, so the PROIEL rows are reused (one query
      # vocabulary, one spelling per value) — plus AGDT's one extra code:
      # gender `c` (common, on personal pronouns like σε), UD's Gender=Com.
      # Slot 1 (pos) stays undecoded: the façade has no pos facet (cf.
      # PROIEL's skipped strength/inflection positions).
      AGDT_GENDER = ["gender", PROIEL_FIELDS.assoc("gender").last.merge("c" => "com").freeze].freeze
      AGDT_FIELDS = [nil, *PROIEL_FIELDS].map { |field| field&.first == "gender" ? AGDT_GENDER : field }.freeze

      # Diorisis analysis words → [facet, value] (the full inventory,
      # censused over all 820 upstream files: 59 distinct words). Words not
      # listed — dialect labels (attic, epic, ionic, doric, aeolic, poetic,
      # homeric, contr), lexical flags (indeclform, proclitic, enclitic,
      # adverbial, nu_movable, a_priv, iota_intens, geog_name) — carry no
      # inflection and are skipped.
      DIORISIS_WORDS = {
        "masc" => %w[gender masc], "fem" => %w[gender fem], "neut" => %w[gender neut],
        "nom" => %w[case nom], "gen" => %w[case gen], "dat" => %w[case dat], "acc" => %w[case acc],
        "voc" => %w[case voc],
        "sg" => %w[number sing], "pl" => %w[number plur], "dual" => %w[number dual],
        "1st" => %w[person 1], "2nd" => %w[person 2], "3rd" => %w[person 3],
        "pres" => %w[tense pres], "imperf" => %w[tense impf], "fut" => %w[tense fut],
        "aor" => %w[tense aor], "perf" => %w[tense perf], "plup" => %w[tense plup],
        "futperf" => %w[tense futperf],
        "ind" => %w[mood ind], "subj" => %w[mood sub], "opt" => %w[mood opt], "imperat" => %w[mood imp],
        "inf" => %w[mood inf], "part" => %w[mood part],
        "act" => %w[voice act], "mid" => %w[voice mid], "pass" => %w[voice pass], "mp" => %w[voice mp],
        "comp" => %w[degree cmp], "superl" => %w[degree sup],
        "irreg_comp" => %w[degree cmp], "irreg_superl" => %w[degree sup]
      }.freeze

      # Values that mean "no value here" across the Semitic feature sets.
      BLANK_VALUES = ["NA", "unknown", "n/a", "absent", ""].freeze

      # ETCBC (bhsa) codes → facet values. vs/vt ride verbatim (the ETCBC
      # spelling IS the shared Hebrew vocabulary); st per st.tf's own
      # description "a (absolute); c (construct); e (emphatic)".
      ETCBC_PERSON = { "p1" => "1", "p2" => "2", "p3" => "3" }.freeze
      ETCBC_NUMBER = { "sg" => "sing", "du" => "dual", "pl" => "plur" }.freeze
      ETCBC_GENDER = { "m" => "masc", "f" => "fem" }.freeze
      ETCBC_STATE = { "a" => "abs", "c" => "cons", "e" => "emph" }.freeze

      # The conjugations that are moods (impv; the infinitives; the
      # participles) — the PROIEL/AGDT mood values.
      CONJUGATION_MOODS = {
        "impv" => "imp", "infa" => "inf", "infc" => "inf", "ptca" => "part", "ptcp" => "part"
      }.freeze

      # Abegg (dss) codes. gn "b" = both (OSHB's sibling code — its parser
      # names it "both"; upstream's etcbc layer resolves b to m OR f) is a
      # masc|fem alternative; "c" = common (AGDT's com). st "d" (determined)
      # is the emphatic state.
      ABEGG_GENDER = { "m" => "masc", "f" => "fem", "c" => "com", "b" => %w[masc fem] }.freeze
      ABEGG_NUMBER = { "s" => "sing", "p" => "plur", "d" => "dual" }.freeze
      ABEGG_PERSON = { "1" => "1", "2" => "2", "3" => "3" }.freeze
      ABEGG_STATE = { "a" => "abs", "c" => "cons", "d" => "emph" }.freeze
      # Abegg md: jussive / cohortative. "cons" (103 corpus-wide) is
      # undocumented in the held data — skipped.
      ABEGG_MOODS = { "juss" => "jus", "coho" => "coh" }.freeze

      # Abegg stem/tense names whose ETCBC spelling differs, from upstream's
      # OWN harmonization (vs → vs_etcbc / vt → vt_etcbc, censused over the
      # whole tf/2.0 pin). Every other Abegg name (qal, piel, peal, polel,
      # ithpeel …) is spelled identically in the etcbc layer.
      ABEGG_STEMS = {
        "hifil" => "hif", "nifal" => "nif", "hitpael" => "hit", "aphel" => "afel", "hofal" => "hof",
        "hophal" => "hof", "haphel" => "haf", "hishtafel" => "hsht", "hishtaphel" => "hsht",
        "passive" => "pasq", "hitpoel" => "htpo", "hithpeel" => "htpe", "hithpaal" => "htpa",
        "shaphel" => "shaf", "tifil" => "tif", "hotpaal" => "hotp", "nitpael" => "nit"
      }.freeze
      ABEGG_CONJUGATIONS = { "wayy" => "wayq" }.freeze

      # OSHB (upstream read/Script/MorphologyParser.js). Stem names verbatim
      # ("qal passive" hyphenated so it types as one query value).
      OSHB_STEMS = {
        "H" => {
          "q" => "qal", "N" => "niphal", "p" => "piel", "P" => "pual", "h" => "hiphil", "H" => "hophal",
          "t" => "hithpael", "o" => "polel", "O" => "polal", "r" => "hithpolel", "m" => "poel",
          "M" => "poal", "k" => "palel", "K" => "pulal", "Q" => "qal-passive", "l" => "pilpel",
          "L" => "polpal", "f" => "hithpalpel", "D" => "nithpael", "j" => "pealal", "i" => "pilel",
          "u" => "hothpaal", "c" => "tiphil", "v" => "hishtaphel", "w" => "nithpalel", "y" => "nithpoel",
          "z" => "hithpoel"
        }.freeze,
        "A" => {
          "q" => "peal", "Q" => "peil", "u" => "hithpeel", "N" => "niphal", "p" => "pael", "P" => "ithpaal",
          "M" => "hithpaal", "a" => "aphel", "h" => "haphel", "s" => "saphel", "e" => "shaphel",
          "H" => "hophal", "i" => "ithpeel", "t" => "hishtaphel", "v" => "ishtaphel", "w" => "hithaphel",
          "o" => "polel", "z" => "ithpoel", "r" => "hithpolel", "f" => "hithpalpel", "b" => "hephal",
          "c" => "tiphel", "m" => "poel", "l" => "palpel", "L" => "ithpalpel", "O" => "ithpolel",
          "G" => "ittaphal"
        }.freeze
      }.freeze
      # OSHB verb aspect → [conjugation, mood]. The conjugation values are
      # the shared ETCBC ones where the bridging osm↔vt alignment is 1:1;
      # the sequential perfect (q) is a perf and jussive/cohortative (j/h)
      # are impf forms in ETCBC's own coding (measured: q→perf 5,644,
      # j→impf 1,144, h→impf 569), so they fold the same way, j/h adding
      # their mood.
      OSHB_ASPECTS = {
        "p" => ["perf", nil], "q" => ["perf", nil], "i" => ["impf", nil], "w" => ["wayq", nil],
        "h" => %w[impf coh], "j" => %w[impf jus], "v" => %w[impv imp], "r" => %w[ptca part],
        "s" => %w[ptcp part], "a" => %w[infa inf], "c" => %w[infc inf]
      }.freeze
      OSHB_GENDER = ABEGG_GENDER
      OSHB_NUMBER = ABEGG_NUMBER
      OSHB_STATE = ABEGG_STATE

      # CorA msd values (ReM/ReN), decoded by identity — the values are
      # self-describing German grammatical abbreviations (censused over the
      # whole held ReM and ReN trees). Digits are person: ReM puts it last
      # on nominals and verbs ("Masc.Nom.Sg.3", "Ind.Pres.Sg.3"), ReN first
      # ("3.Sg.Masc.Nom", "Sw.3.Sg.Past.*"); "0" (no person) is skipped.
      # Skipped as no clean facet: inflection classes (st/wk, St/Sw/Irr/
      # Prpr), "*" (underspecified), "_" (not applicable), "(Ind)"-style
      # uncertain values, and the rare residue (FutI, S,P, editorial marks).
      CORA_VALUES = {
        "Masc" => %w[gender masc], "Fem" => %w[gender fem], "Neut" => %w[gender neut],
        "Nom" => %w[case nom], "Gen" => %w[case gen], "Dat" => %w[case dat], "Akk" => %w[case acc],
        "Instr" => %w[case ins], "Voc" => %w[case voc], "Abl" => %w[case abl],
        "Sg" => %w[number sing], "Pl" => %w[number plur],
        "1" => %w[person 1], "2" => %w[person 2], "3" => %w[person 3],
        "Pres" => %w[tense pres], "Past" => %w[tense past],
        "Ind" => %w[mood ind], "Subj" => %w[mood sub], "Konj" => %w[mood sub],
        "Pos" => %w[degree pos], "Comp" => %w[degree cmp], "Sup" => %w[degree sup]
      }.freeze

      # IMP msd (goo300k) — the closed coarse tagset of the corpus root's
      # own fvLib (goo300k.xml): Nc/Np + gender; Vm + Aspect (e perfective,
      # p "progressive" = sl "nedovršni", imperfective; b biaspectual = both
      # aspects); A?/Rg + Degree. Every other tag (Va, Rr, P, M?, S, C, Q, I,
      # Y, X?) carries no decodable inflection.
      IMP_TAGS = {
        "Ncm" => { "gender" => "masc" }, "Ncf" => { "gender" => "fem" }, "Ncn" => { "gender" => "neut" },
        "Npm" => { "gender" => "masc" }, "Npf" => { "gender" => "fem" }, "Npn" => { "gender" => "neut" },
        "Vme" => { "aspect" => "perf" }, "Vmp" => { "aspect" => "imp" }, "Vmb" => { "aspect" => %w[imp perf] },
        "Agp" => { "degree" => "pos" }, "Agc" => { "degree" => "cmp" }, "Ags" => { "degree" => "sup" },
        "App" => { "degree" => "pos" }, "Asp" => { "degree" => "pos" },
        "Rgp" => { "degree" => "pos" }, "Rgc" => { "degree" => "cmp" }, "Rgs" => { "degree" => "sup" }
      }.freeze

      # Menota msa category letter → [facet, {code => value}]. Codes within a
      # category share a length, so a concatenated value ("gMFN", "mINSU",
      # "cAD") splits into alternatives. vR (the -sk/-st forms) is the middle
      # voice: menotec, the PROIEL conversion of the same texts, codes them
      # voice m. Skipped: x (word class), y (case government), i (inflection
      # class), s (species — definiteness on nouns, strong/weak on
      # adjectives: no single facet), e, z, and every U (unspecified).
      MENOTA_CODES = {
        "c" => ["case", { "N" => "nom", "A" => "acc", "D" => "dat", "G" => "gen" }],
        "g" => ["gender", { "M" => "masc", "F" => "fem", "N" => "neut" }],
        "n" => ["number", { "S" => "sing", "P" => "plur", "D" => "dual" }],
        "p" => ["person", { "1" => "1", "2" => "2", "3" => "3" }],
        "t" => ["tense", { "PS" => "pres", "PT" => "past" }],
        "m" => ["mood", { "IN" => "ind", "SU" => "sub", "IP" => "imp" }],
        "f" => ["mood", { "I" => "inf", "P" => "part" }],
        "v" => ["voice", { "A" => "act", "R" => "mid" }],
        "r" => ["degree", { "P" => "pos", "C" => "cmp", "S" => "sup" }]
      }.freeze

      # Coptic Scriptorium tag → the UD features the tag fixes (class note;
      # censused against upstream's own CoNLL-U conversion).
      COPTIC_PRONOUN = { "prontype" => "prs", "definite" => "def" }.freeze
      COPTIC_NEGATIVE = { "polarity" => "neg" }.freeze
      COPTIC_FINITE = { "verbform" => "fin" }.freeze
      COPTIC_TAGS = {
        "PPERS" => COPTIC_PRONOUN, "PPERO" => COPTIC_PRONOUN, "PPERI" => COPTIC_PRONOUN,
        "PPOS" => COPTIC_PRONOUN.merge("poss" => "yes").freeze,
        "PDEM" => { "prontype" => "dem", "definite" => "def" }.freeze,
        "ART" => { "prontype" => "art" }.freeze,
        "NUM" => { "numtype" => "card" }.freeze,
        "NEG" => COPTIC_NEGATIVE, "ANEGPST" => COPTIC_NEGATIVE, "ANEGAOR" => COPTIC_NEGATIVE,
        "ANEGOPT" => COPTIC_NEGATIVE, "ANEGJUS" => COPTIC_NEGATIVE, "ANY" => COPTIC_NEGATIVE,
        "VBD" => COPTIC_FINITE, "VSTAT" => COPTIC_FINITE,
        "VIMP" => COPTIC_FINITE.merge("mood" => "imp").freeze
      }.freeze

      # The per-tagset decoder seam: [token key, decode method, source scope]
      # in precedence order (scope nil = any source; otherwise the slugs
      # whose tokens the row decodes — class note). The first APPLICABLE row
      # whose key the token carries decides — a token never falls through to
      # a later row, even when its tag decodes to nothing. Every decoder is
      # called as decoder(tag, token).
      DECODERS = [
        ["morphology", :proiel_features, nil],
        ["feats", :ud_features, nil],
        ["postag", :agdt_features, nil],
        ["analyses", :diorisis_features, %w[diorisis].freeze],
        ["vt", :etcbc_features, %w[bhsa].freeze],
        ["morpho", :abegg_features, %w[dss].freeze],
        ["morph", :oshb_features, %w[oshb].freeze],
        ["msd", :cora_features, %w[rem ren].freeze],
        ["msd", :imp_features, %w[goo300k].freeze],
        ["msa", :menota_features, %w[menota].freeze],
        ["pos", :coptic_features, %w[coptic-scriptorium].freeze]
      ].freeze

      # Canonical order for rendering a token's decoded features as evidence
      # (keys outside the list sort last, alphabetically stable enough).
      # const: display convention over the UD/PROIEL feature vocabulary; an
      # unlisted key still renders (sorts last), so growth cannot hide one
      DISPLAY_ORDER = %w[person number gender case state stem conjugation tense mood voice aspect
                         degree verbform polarity prontype definite poss numtype].freeze

      module_function

      # Parse "case=dat,number=pl" into [["case", "dat"], ["number", "plur"]] —
      # canonical (lowercased, aliases resolved), order preserved. Raises
      # MorphFacets::Error on anything malformed so the surfaces can report it.
      def parse(string)
        facets = string.to_s.split(",").filter_map do |chunk|
          chunk = chunk.strip
          next if chunk.empty?

          key, value = chunk.split("=", 2)
          key = key.to_s.strip.downcase
          value = value.to_s.strip.downcase
          if key.empty? || value.empty?
            raise Error, "malformed morph facet #{chunk.inspect} — expected key=value, e.g. case=dat"
          end

          [key, VALUE_ALIASES.fetch(value, value)]
        end
        raise Error, "empty --morph filter — give at least one facet, e.g. case=dat,number=pl" if facets.empty?

        facets
      end

      # Does +token+ satisfy every facet? True when ANY of its readings does
      # (class note). A token with no decodable morphology (ORACC, a token
      # whose features are all blank, a token from a source outside every
      # scoped row) matches nothing — honest absence.
      def match?(token, facets, source: nil)
        readings(token, source: source).any? { |reading| reading_matches?(reading, facets) }
      end

      # A token's CERTAIN morphology in the UD facet vocabulary: the features
      # whose single value every reading shares (class note). {} for ORACC
      # and for featureless tokens.
      def features(token, source: nil)
        all = readings(token, source: source)
        return {} if all.empty?

        all.first.each_with_object({}) do |(key, values), out|
          next unless values.size == 1 && all.all? { |reading| reading[key] == values }

          out[key] = values.first
        end
      end

      # The token's decoded readings: [{facet => [value, …]}, …], each value
      # list the alternatives within that reading. [] when nothing decodes.
      def readings(token, source: nil)
        return [] unless token.is_a?(Hash)

        DECODERS.each do |key, decoder, sources|
          next if sources && !sources.include?(source)

          tag = token[key]
          return normalize_readings(public_send(decoder, tag, token)) unless tag.nil?
        end
        []
      end

      # Render a token's decoded morphology as `case=dat|number=plur|…` in a
      # readable category order — the per-hit morph evidence. With +facets+,
      # only the readings that satisfy them; alternatives render "/"-joined.
      def describe(token, source: nil, facets: nil)
        all = readings(token, source: source)
        matching = facets ? all.select { |reading| reading_matches?(reading, facets) } : all
        merged = (matching.empty? ? all : matching).each_with_object({}) do |reading, out|
          reading.each { |key, values| out[key] = (out[key] || []) | values }
        end
        merged.sort_by { |key, _| [DISPLAY_ORDER.index(key) || DISPLAY_ORDER.size, key] }
              .map { |key, values| "#{key}=#{values.join('/')}" }
              .join("|")
      end

      # UD `feats`: "Case=Dat|Number=Plur" → {"case"=>"dat","number"=>"plur"}.
      def ud_features(feats, _token = nil)
        feats.to_s.split("|").each_with_object({}) do |pair, out|
          key, value = pair.split("=", 2)
          next if key.nil? || value.nil?

          out[key.strip.downcase] = value.strip.downcase
        end
      end

      # PROIEL `morphology`: positional string → UD-named facet hash.
      def proiel_features(morphology, _token = nil)
        positional_features(morphology, PROIEL_FIELDS)
      end

      # AGDT `postag` (GLAUx): 9-slot positional string → UD-named facet hash.
      def agdt_features(postag, _token = nil)
        positional_features(postag, AGDT_FIELDS)
      end

      # Diorisis `analyses`: every candidate analysis is one reading; a
      # "/"-joined word is a value alternative (decoded only when every
      # alternative is a known word of ONE category — never partially).
      def diorisis_features(analyses, _token = nil)
        Array(analyses).map do |analysis|
          analysis.to_s.gsub(/\([^)]*\)/, " ").split.each_with_object({}) do |word, out|
            pairs = word.split("/").map { |alternative| DIORISIS_WORDS[alternative] }
            next if pairs.include?(nil) || pairs.map(&:first).uniq.size != 1

            add_values(out, pairs.first.first, pairs.map(&:last))
          end
        end
      end

      # BHSA: the ETCBC word features read off the token (class note).
      def etcbc_features(_tag, token)
        out = {}
        add_coded(out, "person", token["ps"], ETCBC_PERSON)
        add_coded(out, "number", token["nu"], ETCBC_NUMBER)
        add_coded(out, "gender", token["gn"], ETCBC_GENDER)
        add_coded(out, "state", token["st"], ETCBC_STATE)
        add_verbal(out, stem: present(token["vs"]), conjugation: present(token["vt"]))
      end

      # DSS: Abegg's decomposed gold features, stems/tenses in the ETCBC
      # spelling (class note). The silver *_etcbc layer is never read.
      def abegg_features(_tag, token)
        out = {}
        add_coded(out, "person", token["ps"], ABEGG_PERSON)
        add_coded(out, "number", token["nu"], ABEGG_NUMBER)
        add_coded(out, "gender", token["gn"], ABEGG_GENDER)
        add_coded(out, "state", token["st"], ABEGG_STATE)
        stem = present(token["vs"])
        conjugation = present(token["vt"])
        add_verbal(out, stem: stem && ABEGG_STEMS.fetch(stem, stem),
                        conjugation: conjugation && ABEGG_CONJUGATIONS.fetch(conjugation, conjugation),
                        mood: ABEGG_MOODS[token["md"]])
      end

      # OSHB `morph`: "H|A" + "/"-joined segments; the word's own analysis is
      # the last non-suffix segment (prefixes are particles/prepositions, an
      # S segment describes the pronominal suffix, not the word).
      def oshb_features(morph, _token = nil)
        stems = OSHB_STEMS[morph.to_s[0]]
        return {} unless stems

        chars = morph.to_s[1..].split("/").reject { |segment| segment.start_with?("S") }.last.to_s.chars
        case chars.first
        when "N", "A" then oshb_nominal(chars[2], chars[3], chars[4])
        when "P" then oshb_person(chars[2], chars[3], chars[4])
        when "V" then oshb_verb(chars, stems)
        else {}
        end
      end

      # CorA msd (ReM, ReN): "."-joined values decoded by identity; a value
      # with ","/"-"-joined alternatives decodes only when every alternative
      # is a known value of ONE category.
      def cora_features(msd, _token = nil)
        msd.to_s.split(".").each_with_object({}) do |segment, out|
          pairs = segment.strip.split(/[,-]/).map { |alternative| CORA_VALUES[alternative] }
          next if pairs.empty? || pairs.include?(nil) || pairs.map(&:first).uniq.size != 1

          add_values(out, pairs.first.first, pairs.map(&:last))
        end
      end

      # IMP msd (goo300k): the closed coarse table, nothing guessed.
      def imp_features(msd, _token = nil)
        IMP_TAGS.fetch(msd.to_s, {})
      end

      # Menota msa: "|"-joined analyses are readings; each space-separated
      # code is category letter + value (concatenated codes = alternatives).
      def menota_features(msa, _token = nil)
        msa.to_s.split("|").map do |analysis|
          analysis.split.each_with_object({}) do |code, out|
            facet, codes = MENOTA_CODES[code[0]]
            next unless facet

            values = split_codes(code[1..], codes)
            add_values(out, facet, values) if values
          end
        end
      end

      # Coptic Scriptorium `pos`: the tag table, a fused tag decoding every
      # "_"-joined part (class note).
      def coptic_features(pos, _token = nil)
        pos.to_s.split("_").each_with_object({}) do |part, out|
          out.merge!(COPTIC_TAGS.fetch(part, {}))
        end
      end

      # Shared positional decode: `-` and unknown codes are skipped, never
      # guessed; a nil field row leaves that slot undecoded.
      def positional_features(tag, fields)
        chars = tag.to_s.chars
        out = {}
        fields.each_with_index do |field, index|
          next if field.nil?

          key, codes = field
          code = chars[index]
          next if code.nil? || code == "-"

          value = codes[code]
          out[key] = value if value
        end
        out
      end

      # -- reading plumbing ---------------------------------------------------

      # A decoder's result (one hash or a list; values a String or a list of
      # alternatives) → [{facet => [value, …]}, …], empty readings dropped.
      def normalize_readings(result)
        Array(result.is_a?(Hash) ? [result] : result).filter_map do |reading|
          next unless reading.is_a?(Hash)

          normalized = reading.each_with_object({}) do |(key, value), out|
            values = Array(value).compact.uniq
            out[key] = values unless values.empty?
          end
          normalized unless normalized.empty?
        end.uniq
      end

      def reading_matches?(reading, facets)
        facets.all? { |key, value| reading[key]&.include?(value) }
      end

      # Union +values+ into the reading's +facet+ (a code list spanning two
      # letters that both set one facet — Menota f/m → mood — accumulates).
      def add_values(out, facet, values)
        out[facet] = Array(out[facet]) | values
      end

      def add_coded(out, facet, code, table)
        value = table[code]
        add_values(out, facet, Array(value)) if value
      end

      # The Semitic verbal keys (class note): stem + conjugation verbatim,
      # mood from an explicit mood code or a mood-like conjugation.
      def add_verbal(out, stem:, conjugation:, mood: nil)
        out["stem"] = stem if stem
        out["conjugation"] = conjugation if conjugation
        mood ||= CONJUGATION_MOODS[conjugation]
        out["mood"] = mood if mood
        out
      end

      def present(value)
        value.is_a?(String) && !BLANK_VALUES.include?(value) ? value : nil
      end

      def oshb_nominal(gender, number, state)
        out = {}
        add_coded(out, "gender", gender, OSHB_GENDER)
        add_coded(out, "number", number, OSHB_NUMBER)
        add_coded(out, "state", state, OSHB_STATE)
        out
      end

      def oshb_person(person, gender, number)
        out = {}
        add_coded(out, "person", person, ABEGG_PERSON)
        add_coded(out, "gender", gender, OSHB_GENDER)
        add_coded(out, "number", number, OSHB_NUMBER)
        out
      end

      # V + stem + aspect, then gender/number/state (participles), nothing
      # (infinitives), or person/gender/number (finite forms) — the
      # MorphologyParser.js order.
      def oshb_verb(chars, stems)
        conjugation, mood = OSHB_ASPECTS[chars[2]]
        out = conjugation ? add_verbal({}, stem: stems[chars[1]], conjugation: conjugation, mood: mood) : {}
        case chars[2]
        when "r", "s" then out.merge(oshb_nominal(chars[3], chars[4], chars[5]))
        when "a", "c", nil then out
        else out.merge(oshb_person(chars[3], chars[4], chars[5]))
        end
      end

      # "MFN" with one-letter codes → %w[masc fem neut]; nil when any chunk
      # is unknown (an unspecified U, a stray letter) — never a partial read.
      def split_codes(value, codes)
        width = codes.keys.first.size
        return nil if value.empty? || (value.size % width).nonzero?

        values = value.scan(/.{#{width}}/).map { |chunk| codes[chunk] }
        values.include?(nil) ? nil : values
      end
    end
  end
end

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
    # The treebank keys above are unambiguous library-wide save one: AES's
    # "morphology" is an Egyptian morpheme label, so the AES-scoped row
    # precedes the treebank rows (see the AES note below). The later
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
    # - CorA `morph` (REF): the same identity scheme in German spellings
    #   (Mask/Akk/Präs/Prät/Konj/Komp), MN/MF/FN syncretic genders as
    #   alternatives; "*", Unr/St/Sw and Unflekt/Flekt skipped.
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
    # - CEIPoM `pos_code` (ceipom): the 9-slot AGDT tag, through the AGDT
    #   table. Censused over the whole deposit (36,859 of 37,041 tokens
    #   carry one; 36,874 analyses with the alternatives; 386 distinct, all
    #   9 slots wide): every slot code sits inside the AGDT/PROIEL code
    #   maps (tense p/i/r/l/f/t, mood i/s/m/o/n/p/g/u, voice a/p, case
    #   n/g/a/b/d/v, degree c/s), and the tag agrees 1:1 with the explicit
    #   Person/Number/Tense/Mood/Diathesis columns wherever both speak.
    #   Two lossy spots, refined from the explicit columns: case — slot 8
    #   is "-" on the 277 LOC and 15 INS tokens — and syncretism — the tag
    #   writes one gender for the 167 M/N, M/F, F/N tokens and one case for
    #   the 7 ACC/DAT-style pairs, decoded as value alternatives. Undecoded
    #   residue: 182 analysis-less tokens, 2,809 all-"-" tags (letters,
    #   unclear words), and the 12 multi-analysis tokens' alternatives (they
    #   can be other lexemes — the lemma anchor reads the first analysis's
    #   latin_equivalent). The explicit Tense column (simple/past/future) is
    #   coarser than the tag and is not read. CEIPoM is the EQUIVALENCE lemma
    #   tier, so the facets ride `--lemma <Latin equivalent>`.
    # - HeliPaD `pos` + `morph` (helipad): the Penn-psd tag split on its
    #   first "^" (PennPsdParser). Censused over the whole deposit (53,466
    #   real tokens; 93 distinct pos tags; 32,129 morph strings, 59
    #   distinct, exactly 15 atoms): the morph atoms are case (N 8,776,
    #   A 6,586, D 6,545, G 3,676, I 346 — instrumental), person (3 9,529,
    #   2 1,705, 1 1,041) and number (SG 22,893, PL 9,048, DU 16); the 5
    #   stray atoms (3PL ×2, SGL, SPL, RFL) are skipped, and the one
    #   G^D^SG decodes as a case alternative. The verb tag carries tense +
    #   mood in the YCOE family convention (head VB/BE/HV/MD/RD + PI/PS/
    #   DI/DS; bare head = infinitive; head+I = imperative); VG/VN (+I = the inflected forms, which
    #   carry case/number) are participles — mood only, no tense claimed
    #   (the upstream manual is not held). ADJR/ADVR/QR and ADJS/ADVS/QS
    #   give degree; GE+/NEG+ prefixes are stripped. Undecoded: RN, MG,
    #   VBG (10 tokens, unattested in the convention) and every tag that
    #   fixes nothing. 34,434 tokens decode at least one facet.
    # - CorPH `analysis` (corph): "."-joined self-describing atoms —
    #   censused over the whole deposit (85,397 analyses, 359 distinct):
    #   case nom/gen/dat/acc/voc/abl, number sg/pl/du, gender, fused
    #   person+number (3sg 11,911, 3pl 3,256 …), tense pres/pret/past/fut/
    #   impf (+ perf 7, plup 1), mood ind/subj/impv/cond (UD Cnd)/inf/
    #   supine, voice pass, aspect hab (UD Hab), degree comp/sup/equ (UD
    #   Equ, the Old Irish equative); a "/"-led segment continues the
    #   previous one as alternatives (dat./acc., masc./neut.). THE TRAP:
    #   the field carries no POS, and a bare case ("dat.", "dat./acc.",
    #   9,512 tokens on do/i/ó/di/fri/la …) is the case a PREPOSITION
    #   governs, as is the case beside a fused person-number (3sg.masc./
    #   neut.dat., 2,470 conjugated prepositions — the person/number/
    #   gender are the incorporated pronoun's and decode). So case decodes
    #   only beside a separate number atom (the nominal shape: 53,494
    #   tokens, ≤108 of them on a governing lemma). Skipped as flags:
    #   augm, rel, compos, conj, nas/len, obj, prep, A/B/C (infixed-pronoun
    #   classes). Voided whole: 479 upstream-uncertain ("(?)", "?", the
    #   secondary future "sec", free text "or") and 4 segments whose
    #   alternatives span categories (acc.sg./gen.pl.). 71,850 analyses
    #   decode at least one facet.
    # - AES explicit fields (aes): upstream's fine morphology rides verbatim
    #   under its own names, censused over the whole deposit (815,026
    #   tokens): numerus singular/plural/dual, genus masculine/feminine/
    #   commonGender, status st_absolutus/st_constructus/st_pronominalis
    #   (→ state abs/cons/pron — the Egyptian pronominal state, the noun
    #   form before a suffix pronoun), pronoun personal/demonstrative/
    #   relative/interrogative (→ prontype prs/dem/rel/int), inflection
    #   (suffixConjugation → verbform fin; infinitive/participle/
    #   imperative → mood), voice active/passive, number cardinal/ordinal
    #   (→ numtype). Skipped: inflection pseudoParticiple (8,941) and
    #   relativeform (5,279) — Egyptian-specific forms with no UD facet,
    #   their agreement still decodes; numerus substantive_masc/_fem
    #   (24,326 — the noun's lexical subtype leaking into the number slot,
    #   not a number); verbalClass, epitheton, name, adjective, particle,
    #   adverb (lexical classes); and "morphology" — Egyptian verb-morpheme
    #   labels (n-morpheme, t-morpheme, geminated …, 22,523 tokens). THAT
    #   key is why the AES row sits FIRST, keyed on "form" (every AES
    #   token): the unscoped PROIEL row reads "morphology", and read
    #   positionally "n-morpheme" is mood=opt — 19,309 AES tokens decoded
    #   to false moods before this row existed. 460,548 tokens decode.
    # - TraCES explicit features (traces, Gǝʿǝz): one upstream feature per
    #   category, censused over the whole deposit (113,978 tokens). Decoded:
    #   person First/Second/Third (23,031), case Nominative/Accusative/
    #   Vocative (27,605), state Absolute/Construct/Pronominal (23,419 —
    #   pron as for AES), and tam (10,725, plus the misspelled feature
    #   names tamp 20 / temp 13) under the Semitic keys: Perfect/Imperfect
    #   → conjugation perf/impf (the shared ETCBC values, never a Greek
    #   tense), Subjunctive/Imperative/Infinitive/Gerund → mood sub/imp/
    #   inf/ger. Number and gender decode only in their PLAIN values
    #   (Singular/Plural 28,479; Masculine/Feminine/Communis 28,043 — the
    #   verbs, pronouns, suffixes and numerals). Not decoded: the LAYERED
    #   values on nouns and names (number "SingularP UnmarkedS",
    #   "PluralIntP PluralS" … 23,490; gender "masculineNP", "feminineS" …
    #   ~11.4k) — the P/S/N layers are not defined in the held export, and
    #   which layer `number` should mean is a judgment, not a decode;
    #   "unmarked" (12,235), Collective (5), and the prepositions' "Nominal
    #   state" (11,808). Keyed on "form" (every token). 54,929 decode.
    # - TLA glossing `gloss` (tla-hf): the token "gloss" here is the TLA's
    #   GRAMMATICAL glossing (Leipzig-style labels), not a word meaning —
    #   so it belongs to this façade, never TokenGlosses. Censused over the
    #   whole deposit (212,018 tokens, 259 distinct labels): a head (V, N,
    #   PREP, ART …) plus atoms joined by . : - = ~ \ — gender m/f/c,
    #   number sg/pl/du, fused person-number (3sg, 1pl …), state stpr/stc
    #   (pron/cons), inf/imp/ptcp (mood), act/pass (voice), ipfv (aspect
    #   imp), art/ART/dem/REL/PRON.rel (prontype), poss, NUM ord/card. A
    #   head-less person label (-3sg.m, =3sg.c, 1sg) is a personal pronoun
    #   (prontype prs); a verb's (V\res-3sg.m) is its agreement. The
    #   possessive article's "-" segment is its POSSESSOR (ART.poss:pl-1sg,
    #   4 tokens) and is dropped. Flags with no facet (tam, ant, res, cnsv,
    #   oblv, compl, post, distr, dist, excl, nmlz, adjz, advz, adv, and
    #   "gen" — the genitival adjective, never the genitive case) and the
    #   head-only labels (V 18,478, PREP 23,947, PTCL, PERSN, DIVN, TITL,
    #   "(undefined)" 8,341 …) decode nothing. 109,181 tokens decode.
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

      # CorA morph (REF): the same "."-joined identity scheme in German
      # spellings — censused over all 190 held CorA-XML files (2,061,753
      # morph tags, 531 distinct, exactly 28 atoms): * 1,364,628; Sg
      # 1,246,091; Nom 491,621; Akk 341,573; Pl 333,995; 3 329,379; Dat
      # 319,479; Mask 292,490; Ind 270,900; Fem 224,291; Präs 212,827; Unr
      # 179,824; Neut 140,530; Pos 139,452; Gen 103,283; Prät 100,078; St
      # 88,066; Sw 44,766; 1 41,069; Konj 39,665; MN 39,106; Unflekt
      # 35,416; 2 31,130; Komp 6,595; Sup 4,375; MF 985; Flekt 159; FN 139.
      # Per pos: digits on finite verbs + PPER/PRF; Präs/Prät/Ind/Konj only
      # on *FIN; Pos/Komp/Sup only on ADJ*/AVD. MN/MF/FN are syncretic
      # gender alternatives (MN on wurm/theil/ort, MF on gewalt/zwiebel, FN
      # on glied/-nis nouns — the ReF manual sets a gender only where NP
      # agreement fixes it). Skipped as no clean facet: "*", the inflection
      # classes Unr/St/Sw, and Unflekt/Flekt (the (un)inflected infinitive).
      REF_VALUES = {
        "Mask" => %w[gender masc], "Fem" => %w[gender fem], "Neut" => %w[gender neut],
        "MN" => ["gender", %w[masc neut]], "MF" => ["gender", %w[masc fem]], "FN" => ["gender", %w[fem neut]],
        "Nom" => %w[case nom], "Gen" => %w[case gen], "Dat" => %w[case dat], "Akk" => %w[case acc],
        "Sg" => %w[number sing], "Pl" => %w[number plur],
        "1" => %w[person 1], "2" => %w[person 2], "3" => %w[person 3],
        "Präs" => %w[tense pres], "Prät" => %w[tense past],
        "Ind" => %w[mood ind], "Konj" => %w[mood sub],
        "Pos" => %w[degree pos], "Komp" => %w[degree cmp], "Sup" => %w[degree sup]
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

      # CEIPoM explicit Case/Gender column values (class note) → facet
      # values; "/"-joined pairs are alternatives. Anything else ("?",
      # "ABL?", the stray "da") is not a full decode and leaves the tag's
      # reading alone.
      CEIPOM_CASES = {
        "NOM" => "nom", "GEN" => "gen", "DAT" => "dat", "ACC" => "acc", "ABL" => "abl", "VOC" => "voc",
        "LOC" => "loc", "INS" => "ins"
      }.freeze
      CEIPOM_GENDERS = { "M" => "masc", "F" => "fem", "N" => "neut", "C" => "com" }.freeze

      # HeliPaD "^" morph atoms (class note; the full 15-atom inventory,
      # censused over the whole deposit). Not listed — skipped: SGL, SPL,
      # RFL, 3PL (one or two tags each, upstream typos).
      HELIPAD_ATOMS = {
        "N" => %w[case nom], "A" => %w[case acc], "D" => %w[case dat], "G" => %w[case gen], "I" => %w[case ins],
        "1" => %w[person 1], "2" => %w[person 2], "3" => %w[person 3],
        "SG" => %w[number sing], "PL" => %w[number plur], "DU" => %w[number dual]
      }.freeze
      # HeliPaD verb tags (the YCOE family convention): a verb head + the
      # tense/mood suffix; the participles (VG present, VN past; +I =
      # inflected, carrying case/number) decode mood only.
      HELIPAD_VERB = /\A(?:VB|BE|HV|MD|RD)(PI|PS|DI|DS|I)?\z/
      HELIPAD_VERB_SUFFIXES = {
        nil => { "mood" => "inf" }, "I" => { "mood" => "imp" },
        "PI" => { "tense" => "pres", "mood" => "ind" }, "PS" => { "tense" => "pres", "mood" => "sub" },
        "DI" => { "tense" => "past", "mood" => "ind" }, "DS" => { "tense" => "past", "mood" => "sub" }
      }.freeze
      HELIPAD_PARTICIPLE = /\AV[GN]I?\z/
      # CorPH analysis atoms (class note) → [facet, value]; person+number
      # fuse ("3sg") and match CORPH_PERSON_NUMBER. Atoms not listed (augm,
      # rel, compos, conj, A/B/C, …) are flags with no facet and skipped;
      # CORPH_VOIDING atoms make the whole analysis undecodable.
      CORPH_ATOMS = {
        "nom" => %w[case nom], "gen" => %w[case gen], "dat" => %w[case dat], "acc" => %w[case acc],
        "voc" => %w[case voc], "abl" => %w[case abl],
        "sg" => %w[number sing], "pl" => %w[number plur], "du" => %w[number dual],
        "masc" => %w[gender masc], "fem" => %w[gender fem], "neut" => %w[gender neut],
        "pres" => %w[tense pres], "pret" => %w[tense past], "past" => %w[tense past], "fut" => %w[tense fut],
        "impf" => %w[tense impf], "perf" => %w[tense perf], "plup" => %w[tense plup],
        "ind" => %w[mood ind], "subj" => %w[mood sub], "impv" => %w[mood imp], "cond" => %w[mood cnd],
        "inf" => %w[mood inf], "infinitive" => %w[mood inf], "supine" => %w[mood sup],
        "hab" => %w[aspect hab], "pass" => %w[voice pass],
        "comp" => %w[degree cmp], "sup" => %w[degree sup], "equ" => %w[degree equ]
      }.freeze
      CORPH_PERSON_NUMBER = /\A([123])(sg|pl|du)\z/
      CORPH_VOIDING = ["(?)", "?", "sec"].freeze
      # const: the separate number atoms of the closed CorPH inventory
      # above (the nominal shape that licenses a case decode)
      CORPH_NUMBERS = %w[sg pl du].freeze

      # AES explicit features: upstream field → {upstream value → [facet,
      # value]} (class note). Values not listed are skipped.
      AES_FIELDS = {
        "numerus" => { "singular" => %w[number sing], "plural" => %w[number plur], "dual" => %w[number dual] },
        "genus" => { "masculine" => %w[gender masc], "feminine" => %w[gender fem], "commonGender" => %w[gender com] },
        "status" => { "st_absolutus" => %w[state abs], "st_constructus" => %w[state cons],
                      "st_pronominalis" => %w[state pron] },
        "pronoun" => { "personal_pronoun" => %w[prontype prs], "demonstrative_pronoun" => %w[prontype dem],
                       "relative_pronoun" => %w[prontype rel], "interrogative_pronoun" => %w[prontype int] },
        "inflection" => { "suffixConjugation" => %w[verbform fin], "suffixConjugation;special" => %w[verbform fin],
                          "infinitive" => %w[mood inf], "participle" => %w[mood part], "imperative" => %w[mood imp] },
        "voice" => { "active" => %w[voice act], "passive" => %w[voice pass] },
        "number" => { "cardinal" => %w[numtype card], "ordinal" => %w[numtype ord] }
      }.freeze

      # TraCES explicit features (class note): upstream feature name →
      # {downcased value → [facet, value]}; tamp/temp are upstream's own
      # misspellings of tam. Layered noun values ("SingularP UnmarkedS",
      # "masculineNP"), "unmarked", "Collective" and "Nominal state" are
      # not listed — skipped.
      TRACES_TAM = {
        "perfect" => %w[conjugation perf], "imperfect" => %w[conjugation impf], "subjunctive" => %w[mood sub],
        "imperative" => %w[mood imp], "infinitive" => %w[mood inf], "gerund" => %w[mood ger]
      }.freeze
      TRACES_FIELDS = {
        "person" => { "first" => %w[person 1], "second" => %w[person 2], "third" => %w[person 3] },
        "number" => { "singular" => %w[number sing], "plural" => %w[number plur] },
        "gender" => { "masculine" => %w[gender masc], "feminine" => %w[gender fem], "communis" => %w[gender com] },
        "case" => { "nominative" => %w[case nom], "accusative" => %w[case acc], "vocative" => %w[case voc] },
        "state" => { "absolute state" => %w[state abs], "construct state" => %w[state cons],
                     "pronominal state" => %w[state pron] },
        "tam" => TRACES_TAM, "tamp" => TRACES_TAM, "temp" => TRACES_TAM
      }.freeze

      # TLA glossing atoms (tla-hf; class note) → [facet, value]; a fused
      # person-number atom matches CORPH_PERSON_NUMBER's shape. Heads (V,
      # N, PREP …) and flags (tam, ant, res, adjz, gen …) are not listed.
      TLA_ATOMS = {
        "m" => %w[gender masc], "f" => %w[gender fem], "c" => %w[gender com],
        "sg" => %w[number sing], "pl" => %w[number plur], "du" => %w[number dual],
        "stpr" => %w[state pron], "stc" => %w[state cons],
        "inf" => %w[mood inf], "imp" => %w[mood imp], "ptcp" => %w[mood part],
        "act" => %w[voice act], "pass" => %w[voice pass], "ipfv" => %w[aspect imp],
        "art" => %w[prontype art], "ART" => %w[prontype art], "dem" => %w[prontype dem], "REL" => %w[prontype rel],
        "poss" => %w[poss yes], "ord" => %w[numtype ord], "card" => %w[numtype card]
      }.freeze
      TLA_SEPARATORS = %r{[.:\-=~\\/()]}
      # Article heads whose "-" segment is the POSSESSOR (ART.poss:pl-1sg).
      # const: the glossing convention's two article heads, not a census
      TLA_ARTICLES = %w[ART art].freeze

      HELIPAD_DEGREES = {
        "ADJR" => "cmp", "ADVR" => "cmp", "QR" => "cmp", "ADJS" => "sup", "ADVS" => "sup", "QS" => "sup"
      }.freeze

      # The per-tagset decoder seam: [token key, decode method, source scope]
      # in precedence order (scope nil = any source; otherwise the slugs
      # whose tokens the row decodes — class note). The first APPLICABLE row
      # whose key the token carries decides — a token never falls through to
      # a later row, even when its tag decodes to nothing. Every decoder is
      # called as decoder(tag, token).
      DECODERS = [
        ["form", :aes_features, %w[aes].freeze],
        ["morphology", :proiel_features, nil],
        ["feats", :ud_features, nil],
        ["postag", :agdt_features, nil],
        ["analyses", :diorisis_features, %w[diorisis].freeze],
        ["vt", :etcbc_features, %w[bhsa].freeze],
        ["morpho", :abegg_features, %w[dss].freeze],
        ["morph", :oshb_features, %w[oshb].freeze],
        ["msd", :cora_features, %w[rem ren].freeze],
        ["morph", :ref_features, %w[ref].freeze],
        ["msd", :imp_features, %w[goo300k].freeze],
        ["msa", :menota_features, %w[menota].freeze],
        ["pos", :coptic_features, %w[coptic-scriptorium].freeze],
        ["pos_code", :ceipom_features, %w[ceipom].freeze],
        ["pos", :helipad_features, %w[helipad].freeze],
        ["analysis", :corph_features, %w[corph].freeze],
        ["form", :traces_features, %w[traces].freeze],
        ["gloss", :tla_features, %w[tla-hf].freeze]
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

      # CorA morph (REF): "."-joined values by identity off REF_VALUES (a
      # syncretic gender — MN/MF/FN — is one value-alternative list).
      def ref_features(morph, _token = nil)
        morph.to_s.split(".").each_with_object({}) do |segment, out|
          facet, value = REF_VALUES[segment.strip]
          add_values(out, facet, Array(value)) if facet
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

      # CEIPoM `pos_code`: the AGDT positional decode, its case/gender
      # refined by the explicit columns where those fully decode (class
      # note). Only the first analysis — "alternatives" can be other
      # lexemes than the one the lemma anchor reads.
      def ceipom_features(pos_code, token)
        out = agdt_features(pos_code)
        cases = ceipom_column(token["case"], CEIPOM_CASES)
        genders = ceipom_column(token["gender"], CEIPOM_GENDERS)
        out["case"] = cases if cases
        out["gender"] = genders if genders
        out
      end

      # "ACC/DAT" → %w[acc dat]; nil unless every part is a known value.
      def ceipom_column(value, table)
        return nil unless value.is_a?(String)

        values = value.split("/").map { |part| table[part.strip.upcase] }
        values.empty? || values.include?(nil) ? nil : values
      end

      # HeliPaD: the tag (minus GE+/NEG+ prefixes) gives tense/mood or
      # degree, the "^" morph atoms case/person/number (class note).
      def helipad_features(pos, token)
        out = helipad_tag(pos.to_s.split("+").last.to_s).dup
        token["morph"].to_s.split("^").each do |atom|
          facet, value = HELIPAD_ATOMS[atom]
          add_values(out, facet, [value]) if facet
        end
        out
      end

      def helipad_tag(tag)
        if (verb = HELIPAD_VERB.match(tag)) then HELIPAD_VERB_SUFFIXES.fetch(verb[1])
        elsif HELIPAD_PARTICIPLE.match?(tag) then { "mood" => "part" }
        elsif (degree = HELIPAD_DEGREES[tag]) then { "degree" => degree }
        else {}
        end
      end

      # AES: the explicit fine-morphology fields off the token (class
      # note); "morphology" (Egyptian morpheme labels) is never read.
      def aes_features(_form, token)
        AES_FIELDS.each_with_object({}) do |(field, table), out|
          facet, value = table[token[field]]
          out[facet] = value if facet
        end
      end

      # TraCES: the explicit Gǝʿǝz features off the token (class note).
      def traces_features(_form, token)
        TRACES_FIELDS.each_with_object({}) do |(field, table), out|
          facet, value = table[token[field].to_s.strip.downcase]
          out[facet] = value if facet
        end
      end

      # TLA glossing (tla-hf): the label's atoms (class note). A label with
      # no head (-3sg.m, =3sg.c, 1sg) is a personal pronoun; an article's
      # "-" segment names its possessor and is dropped.
      def tla_features(gloss, _token = nil)
        label = gloss.to_s.strip
        head = label[/\A[A-Za-z]+/]
        label = label.split("-").first.to_s if TLA_ARTICLES.include?(head)
        atoms = label.split(TLA_SEPARATORS).reject(&:empty?)
        out = {}
        atoms.each do |atom|
          if (fused = CORPH_PERSON_NUMBER.match(atom))
            add_values(out, "person", [fused[1]])
            add_values(out, "number", [CORPH_ATOMS.fetch(fused[2]).last])
          elsif (facet, value = TLA_ATOMS[atom])
            add_values(out, facet, [value])
          end
        end
        add_values(out, "prontype", ["rel"]) if head == "PRON" && atoms.include?("rel")
        add_values(out, "prontype", ["prs"]) if head.nil? && out.key?("person")
        out
      end

      # CorPH `analysis`: "."-joined atoms, a "/"-led segment continuing
      # the previous one as alternatives; case only beside a separate
      # number atom (class note — a bare case is prepositional government).
      def corph_features(analysis, _token = nil)
        segments = corph_segments(analysis.to_s)
        return {} if segments.nil?

        out = {}
        segments.each do |alternatives|
          pairs = corph_pairs(alternatives) or return {}
          pairs.each { |facet, values| add_values(out, facet, values) }
        end
        out.delete("case") unless segments.any? { |alternatives| alternatives.intersect?(CORPH_NUMBERS) }
        out
      end

      # "3sg.masc./neut.dat." → [["3sg"], ["masc", "neut"], ["dat"]]; nil
      # when a voiding atom (upstream uncertainty, the secondary future) or
      # free text ("or") is present.
      def corph_segments(analysis)
        segments = []
        analysis.split(".").each do |segment|
          segment = segment.strip
          next if segment.empty?
          return nil if CORPH_VOIDING.include?(segment) || segment.include?(" ") || segment.include?("(?)")

          if segment.start_with?("/") && segments.any? then segments.last.concat(segment.split("/").reject(&:empty?))
          else segments << segment.split("/").reject(&:empty?)
          end
        end
        segments
      end

      # One segment's alternatives → [[facet, values], …]: [] for a flag
      # segment (no atom decodes), nil when its alternatives span
      # categories (two readings run together — the analysis is voided).
      def corph_pairs(alternatives)
        fused = alternatives.map { |atom| CORPH_PERSON_NUMBER.match(atom) }
        if fused.all?
          return [["person", fused.map { |m| m[1] }], ["number", fused.map { |m| CORPH_ATOMS.fetch(m[2]).last }]]
        end

        pairs = alternatives.map { |atom| CORPH_ATOMS[atom] }
        return [] if pairs.all?(&:nil?) && alternatives.size == 1
        return nil if pairs.include?(nil) || pairs.map(&:first).uniq.size != 1

        [[pairs.first.first, pairs.map(&:last)]]
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

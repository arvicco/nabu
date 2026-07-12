# Conventions & Field Notes

Domain knowledge for working on Nabu without a classics or digital-humanities
background. Everything here is load-bearing: each section explains a
convention the codebase enforces, and the trap it exists to avoid.

## 1. Unicode and NFC — one text, one byte sequence

Unicode often provides more than one way to encode what looks like a single
character. The Greek ἄ (alpha + smooth breathing + acute accent) can be:

- **one codepoint** — `U+1F04`, a "precomposed" character, or
- **three codepoints** — plain `α` + combining breathing + combining accent,
  stacked by the font at render time.

They are pixel-identical on screen and completely different bytes underneath.
A byte-level search for one spelling will not find the other; a content hash
of one is not the hash of the other. Ancient-language corpora are the worst
case: polytonic Greek stacks up to three marks per vowel, and digitization
projects made different encoding choices decades apart.

**Normalization** converts all equivalent spellings to one canonical form.
**NFC** (Form C, "composed") prefers the precomposed codepoint — ἄ is always
`U+1F04`. The alternative, NFD ("decomposed"), is equally valid Unicode; NFC
is our pick because most modern sources ship composed and it keeps strings
shorter.

**Nabu's rule: normalize once, at the door.** Adapters call
`Nabu::Normalize.nfc` at the parse boundary; everything inside the system
*refuses* non-NFC text (a `Passage` won't construct with it). Downstream code
gets to assume one text = one byte sequence — which is what makes search,
deduplication, and the loader's changed-content detection trustworthy.

Related traps worth knowing:

- **Case-mapping can denormalize.** `"ΐ".downcase` and friends can produce
  non-NFC sequences in Greek; any transformation of text must re-normalize
  afterwards (our `text_normalized` does).
- **Homoglyphs.** Latin `o`, Greek `ο`, and Cyrillic `о` are three different
  codepoints that render identically. A corpus that mixed keyboards (common
  in older digitizations) can contain Latin letters inside Greek words. NFC
  does NOT fix this — it's a data-quality issue to watch for in fixtures.
- **The elision apostrophe.** Greek elision (τʼ for τε) appears variously as
  `U+02BC` MODIFIER LETTER APOSTROPHE, `U+2019` RIGHT SINGLE QUOTATION MARK,
  or `U+0027` ASCII apostrophe, depending on the digitizer. Perseus uses
  `U+02BC`. These are *not* unified by NFC either; treat them as upstream
  reality and never "fix" them in canonical data (see §3).
- **Final sigma.** Greek σ becomes ς word-finally — two codepoints for one
  letter, both legitimate. The search form normalizes them to one (§9);
  byte-level tools on the pristine text still see two.

## 2. Citations — how texts without page numbers are addressed

Classical texts predate print, so scholars never cite pages (every edition
paginates differently). Each work carries a traditional logical scheme,
stable for centuries: the *Iliad* by **book.line** ("Il. 1.1"), the New
Testament by **chapter:verse**, Plato by **Stephanus pages** (the page/section
layout of a 1578 print edition, e.g. "Republic 514a" — yes, a Renaissance
book's physical layout became the eternal address space), Aristotle by
**Bekker numbers** (same idea, 1831 edition).

**CTS URNs** (Canonical Text Services) turn those schemes into stable machine
identifiers:

```
urn:cts:greekLit:tlg0012.tlg001.perseus-grc2:1.1
        ───┬──── ───┬── ──┬─── ─────┬─────── ┬─
        namespace  group  work    version   passage
        (Greek lit) (Homer) (Iliad) (Perseus  (book 1,
                                    grc ed. 2) line 1)
```

- `tlg0012` — the *textgroup*, usually an author, numbered per the Thesaurus
  Linguae Graecae catalog (`phi` numbers for Latin, `stoa` for late antique).
- `tlg001` — the *work* within the group.
- `perseus-grc2` — the *version*: which edition of the work, in which
  language. The same line differs between editions; the URN pins exact text.
  The trailing digit is an edition version, **not** part of the language
  (`grc1` vs `grc2` are two Perseus digitizations; prefer the highest).
  Translations are separate versions (`perseus-eng2`) — never confuse a
  translation with its original just because they share group and work ids.
- `1.1` — the passage, in the work's traditional citation scheme.

Each TEI file *declares* its own scheme in the header (`refsDecl`): "cited by
line", or "by chapter, then verse". **Trust the declaration, not the XML
nesting** — files contain structural divisions that are not citation levels
(our Ausonius fixture wraps lines in a section div the scheme ignores).

In Nabu, the URN is a passage's permanent primary key. Sync idempotency,
withdrawal detection, and rebuilds all hinge on URNs never changing — which
is why the conformance suite asserts URN stability across two independent
parses, and why URN minting rules for ad-hoc content are frozen once used
(maintenance doc §5).

## 3. There is no "original text" — editions, witnesses, apparatus

No autograph manuscript of any classical author survives. What survives is
copies of copies (*witnesses*), which disagree. A modern *critical edition*
is one editor's reconstruction: a chosen main text plus a *critical
apparatus* — dense footnotes recording where important witnesses differ
("line 42: θεά in manuscript A, θεᾶς in B and C").

Consequences for Nabu:

- **"Canonical" means "the digitized edition, verbatim".** The canonical
  layer preserves what upstream published, including its typos and encoding
  oddities. Corrections, modernized orthography, "obvious" fixes — all are
  *enrichments*, layered on with provenance, never edits to canonical files
  (CLAUDE.md: "canonical means canonical").
- **Apparatus is preserved but not modeled** in v1 (explicit non-goal):
  TEI marks variants with `<app>`/`<lem>`/`<rdg>` (lemma = editor's choice,
  rdg = variant readings). Our parser currently drops `<note>` and carries a
  TODO for apparatus policy — the likely rule is keep `lem`, drop `rdg`.
- **Two editions of a work are two version URNs**, not a conflict. Never
  dedupe across editions; scholars need to know *whose* text they're reading.
- The ad-hoc pipeline keeps **source images forever** for the same reason:
  a transcription is an interpretation; the photograph is the witness.

## 4. Languages, codes, and scripts

- Language tags are BCP-47 with **ISO 639-3** subtags. The ancient languages
  mostly have their own codes, distinct from their modern descendants:
  `grc` ancient Greek (≠ `el` modern Greek), `lat` Latin, `chu` Old Church
  Slavonic, `got` Gothic, `hit` Hittite, `san` Sanskrit, `sux` Sumerian,
  `akk` Akkadian, `cop` Coptic, `orv` Old East Slavic, `ang` Old English.
  Using `el` for Homer is wrong in the way that matters to every filter.
- **Language ≠ script.** OCS survives in two alphabets (Cyrillic and
  Glagolitic); Sanskrit circulates in Devanagari and in IAST romanization
  (ā, ṛ, ś — Latin letters with diacritics); Gothic has its own script but
  corpora ship it romanized. When script matters, BCP-47 script subtags
  (`chu-Glag`, `san-Latn`) are the tool — our language validation already
  accepts them.
- **Transliteration is not translation.** Cuneiform corpora (ORACC, CDLI)
  ship *transliterations*: sign-by-sign Latin-alphabet renderings
  (`lugal-e`, with superscript determinatives), which are still Sumerian or
  Akkadian, just re-scripted. The ATF format encodes these conventions.
- **Reconstruction pseudo-languages (P14-1):** `sla-pro` (Proto-Slavic),
  `ine-pro` (Proto-Indo-European), `gem-pro` (Proto-Germanic) are NOT ISO
  639-3 — they are English Wiktionary's etymology-language codes, adopted
  verbatim because the reconstruction shelf's crosswalk (the kaikki
  `descendants` trees, architecture §12) speaks them; minting our own would
  break every join. They pass the shape-only tag validation unchanged
  (3-letter primary + `pro` subtag). Reconstructed forms are hypotheses,
  starred by scholarly convention: the store keeps headwords bare (upstream
  reality), display prefixes `*`, and `define *bogъ`/`etym *bogъ` strip a
  leading asterisk on the way in.
- **Word boundaries are editorial.** Ancient Greek was written in *scriptio
  continua* — no spaces, no lowercase, no punctuation. Every space in our
  passages is a modern editor's decision. For scripts where segmentation
  stays unreliable (classical Chinese), the FTS layer plans a trigram
  tokenizer instead of trusting "words" (architecture §5).

## 5. Damaged text — the bracket language of epigraphy

Inscriptions and papyri arrive broken. The **Leiden conventions** encode the
damage state in brackets, and TEI EpiDoc mirrors them; when the Papyri.info
adapter lands, its text will be full of these:

| Notation | TEI | Means |
|---|---|---|
| `[αβγ]` | `<supplied>` | letters lost to damage, restored by the editor |
| `α(βγ)` | `<expan>` | abbreviation in the original, expanded by the editor |
| `⟨αβγ⟩` | `<corr>`/`<supplied reason="omitted">` | editor's correction/insertion |
| `⟦αβγ⟧` | `<del>` | deliberately erased in antiquity (still legible) |
| `αβγ̣` (underdot) | `<unclear>` | traces visible, reading uncertain |
| `[...]` / `lacuna` | `<gap>` | lost text of known/unknown length |

The parser policy question these pose — is restored text "text"? — was
fixed when the Papyri.info adapter landed (P3-6), and it mirrors print
practice: a passage's `text` is what a print edition's main text would
read. Keep `<lem>`, `<reg>`, `<add>`, `<supplied>`, `<unclear>` and
`<expan>` (including its `<ex>` expansions); drop `<rdg>`, `<orig>` and
`<del>` (apparatus, not reading text); every `<gap>` becomes the single
marker `[…]` so a search hit can never match across a lacuna as if the
text were contiguous. Certainty data (gap extents, supplied/unclear letter
counts, hand shifts) lives in per-passage `"leiden"` annotations. The
authoritative, exhaustively documented version of the policy is the
`DdbdpParser` file header (`lib/nabu/adapters/ddbdp_parser.rb`).

**Cancelled documents and `⟦…⟧` (P6-2 amendment).** In print practice
Leiden double brackets `⟦αβγ⟧` mean *deleted in antiquity but legible*:
the scribe crossed the text out (cross-strokes, slashes, wash-out), yet
the editor can still read every letter — so the edition prints the text,
inside the brackets. Cancelled is not deleted, and for the historian the
distinction matters: a crossed-out receipt is still a receipt someone
wrote — the cancellation is itself a documented event (the debt was paid,
the draft was superseded), not an absence of text. About 40 DDbDP
documents are cancellations end to end (every line inside
`<del rend="cross-strokes"|"slashes"|"erasure">`; exemplar o.claud.3.457,
also cpr.6.3, bgu.1.179, apf.59.139); under the blanket drop-`<del>`
policy they extracted zero citable lines and quarantined — the parser
erased documents that print editions publish. The rule adopted:

- **When a document's edition extracts zero citable lines under the
  standard policy — and only then — it is re-read once with `<del>`
  content kept, wrapped in `⟦…⟧`** ("⟦" where the cancellation opens,
  "⟧" where it closes, gap-marker style, so a multi-line cancellation
  carries one opening and one closing bracket exactly as a print edition
  sets it). Everything else about the policy still applies inside the
  kept del; every line touched carries `"leiden": {"cancelled": true}`.
  A document still empty after the retry quarantines honestly.

The rule is document-scoped on purpose: it engages precisely for the class
the old policy erased, and provably never for a document that already
loaded (a loaded document has at least one passage, so the retry never
runs and its frozen urns/text stay byte-identical).

**Recorded future-work question (owner decision):** should `<del>`
*always* render in `⟦…⟧`, partial cancellations included? Papyrologically
that is the more faithful reading — Leiden treats `⟦⟧` as reading text,
not apparatus. But adopting it rewrites every already-loaded passage that
contains a partial del: a corpus-wide, journaled revision (bumped
revisions, provenance entries), to be scheduled deliberately — not
smuggled in through a parser patch.

## 6. Lemmas and morphology — why treebanks are precious

Ancient IE languages are heavily inflected: one Greek verb inflects into
hundreds of surface forms (λύω, λύεις, ἔλυσα, λελυκώς…), all "the same word"
(*lemma*: λύω). Searching surface forms misses almost everything; searching
by lemma finds a word across its whole paradigm. *Morphological annotation*
goes further, tagging each token with case/number/tense/mood etc.

A *treebank* (PROIEL, UD, TOROT in our source list) adds syntax: every word
lemmatized, tagged, and linked into a dependency tree — hand-verified by
scholars. That is why the source ranking calls them "highest linguistic
value per byte": a few megabytes of treebank beats gigabytes of raw text for
comparative-grammar questions. In Nabu, source-provided analyses ride in
`Passage#annotations` (canonical — the upstream published them); analyses we
compute later (CLTK/Stanza lemmatization) are enrichments with tool+version
provenance, kept strictly apart from upstream's.

### 6.1 Morphology facets — one façade over three tagsets (P13-6)

`search --lemma λόγος --morph case=dat,number=pl` narrows a lemma search to
attestations whose morphology matches the facets — "every dative plural of
λόγος", "every subjunctive of *sum*". The design note behind it:

**Tagset reality (measured against the live catalog).** The gold shelves store
three different morphology dialects per token in `annotations_json`:

| family | field | shape | example |
| --- | --- | --- | --- |
| CoNLL-U / UD (grc-perseus, got, …) | `feats` | UD `Key=Value` string, `\|`-joined | `Case=Dat\|Gender=Masc\|Number=Plur` |
| PROIEL / TOROT (chu, orv, PROIEL grc/lat) | `morphology` | 10-position positional tag | `-p---mgpwi` (plur masc gen pos) |
| ORACC (akk, sux) | `pos` | NER-flavoured tag, **no inflection** | `PN`, `N`, `GN`, `V` |

**Vocabulary verdict — unified, not per-family passthrough.** The query
vocabulary is the **Universal Dependencies feature names** (`case`, `number`,
`gender`, `person`, `tense`, `mood`, `voice`, `degree`; values `dat`, `pl`/`sg`,
`masc`, `aor`, `opt`, `sub`…), chosen because UD is (a) a documented public
standard and (b) already the stored form for the CoNLL-U family, which needs
zero translation. The two families with inflectional morphology fold into it:
UD `feats` is parsed as-is (lowercased); the PROIEL positional tag is **decoded
position-by-position into the same UD names** (a fixed 10×~8 code map in
`Query::MorphFacets::PROIEL_FIELDS` — the bounded-but-fiddly bit; positions 9–10,
Germanic strong/weak and the inflecting flag, have no clean UD facet and are
left undecoded rather than mapped wrongly). ORACC carries no inflectional
morphology (upstream `morph`/`base` is an un-ingested enrichment, §6 above), so
inflectional facets **never match ORACC** — honest absence, not error. A unified
`pos` facet was deliberately left out of v1: ORACC's tagset is not UD upos, and
welding a third incompatible scheme into the façade for one field would be
dishonest; it is a clean follow-up. Where a treebank itself encodes a category
UD's way (grc-perseus writes an aorist as `Aspect=Perf\|Tense=Past`, not
`Tense=Aor`), the query follows that treebank's convention — a documented
cross-family divergence, not a bug.

**Where filtering happens — SQL anchor, Ruby post-filter (no new index).**
Morphology is **not** indexed. Measured verdict against the 1.94M-row live lemma
index: a dedicated morph-facet table would multiply those rows by the features
per token *and* need a rebuild, while the lemma anchor already narrows the
search to just the passages attesting the lemma, so post-filtering their stored
`annotations_json` in Ruby is cheap. Timings (live db, cold):

| query | candidate passages | filter time (total) |
| --- | --- | --- |
| `λόγος` dat pl (a real content-word query) | 996 | **37 ms** (46 hits) |
| `sum` subjunctive (every subjunctive of *esse*) | 22 344 | 720 ms (4 129 hits) |
| PROIEL `и` (orv) dat pl | 18 019 | 471 ms (537 hits) |
| `ὁ` (the article — pathological worst case) dat pl | 25 558 | 757 ms (2 255 hits) |

The realistic case is tens of ms; even morph-filtering the single most common
lemma in the corpus stays sub-second. The morph test (a cheap string parse)
runs *before* the per-language fold, so a selective facet folds only the tokens
that already matched. **Bare morph search (no `--lemma`) is out of scope** — it
would scan every annotated passage, not a lemma-narrowed handful, and morphology
without a lemma anchor is rarely the question. Each hit's `surface_forms` and
its decoded `morph` evidence are restricted to the *matching* tokens, so a
passage attesting λόγος in two cases surfaces only its dative-plural form.

## 7. Licensing — old texts, new rights

The ancient *text* is public domain. What carries rights is modern labor: the
editor's reconstruction, the translation, the database and its metadata, the
photographs of manuscripts. Hence:

- Two editions of the same public-domain work can carry different licenses
  (Perseus CC BY-SA; a Brepols database, all-rights-reserved).
- **License is data, recorded per document** (`license_class`: open /
  attribution / nc / research_private / restricted), so queries and exports
  can answer "only material I may republish" mechanically.
- The "unlock by reconstruction" strategy (docs/03): when a restricted
  database and an out-of-copyright print edition contain the same text, HTR
  on the PD scan yields a legally clean copy — same words, your labor.
- **Local retention beats upstream retraction — the owner's deliberate
  policy** (architecture §8). When upstream scraps a document (deletion,
  license change, disagreement), the canonical file is preserved under
  `canonical/<slug>/.attic/` and the document stays live, flagged
  `retired_upstream`. A retained document keeps the license class it was
  *fetched* under — recorded per document, as above, so filters keep
  working — and the collection is a personal research corpus: retention is
  local use, never republication. Protecting the collection from
  degradation by upstream churn is the point.

## 8. Small print that saves future debugging

- **Counts differ between sources for the "same" work** — editions merge or
  split lines, verses, and sections. A passage-count mismatch against another
  database is usually both being right about different editions.
- **TLG/PHI numbers are catalog ids, not chronology** — `tlg0012` (Homer) is
  not "the 12th oldest author"; don't sort by them.
- **Upstream files lie occasionally**: citation declarations promise `@n`
  attributes that are missing (our 25 quarantined Perseus documents), regex
  patterns arrive double-escaped, metadata files are absent for whole
  authors. The loader's quarantine + provenance journal exists precisely so
  upstream imperfection is recorded, skipped, and recoverable — never
  silently "fixed" and never fatal.

## 9. Search folding — the per-language rule table (P6-4)

`text_normalized` is the *search form* of a passage: what the FTS index
carries and what queries are matched against. It is minted exactly once, at
the adapter boundary — `Passage.new` derives it from the pristine text via
`Normalize.search_form(text, language:)` — so the rule table below lives in
one place (`Normalize::LANGUAGE_FOLDS`), not in six adapters. The pristine
`text` is never touched: folding is a derived column, and byte-identical
canonical text remains the permanent asset.

**The generic fold (every language, the conservative baseline):** NFC →
downcase → NFD → strip every nonspacing mark (`\p{Mn}`) → NFC. This is what
makes "μηνιν" find "μῆνιν": polytonic accents, breathings, iota *subscript*
(U+0345 is Mn), dialytika, Latin accents, Cyrillic titla, and IAST dots and
macrons all fall to the same strip.

**Per-language extras, applied on top:**

| language | extra rule | rationale |
| --- | --- | --- |
| `grc` | final sigma ς→σ | σ/ς are one letter in two positional shapes; TLG Beta Code encodes both as a single `S`, i.e. the field's canonical searchable form does not distinguish them. Without this, a word-final match depends on where the word sits in the query. |
| `lat` | v→u, j→i | The classical Latin search convention: PHI's search "is not case-sensitive, nor does it distinguish i from j or u from v," and Perseus-lineage tooling treats the pairs as orthographic variants (editors disagree per edition: *virumque*/*uirumque*). Folding to the u/i base makes every edition findable by every spelling. |
| `akk`, `sux` (one shared rule) | sign-join `.` and `-` and determinative braces `{` `}` → space; subscript index digits `₀`–`₉`, `ₓ` → ASCII | The cuneiform-transliteration fold (P10-1). ORACC transliteration carries structural punctuation that is notation, not text: `-`/`.` join the signs of a word (`du-un-nu-um`), `{…}` marks unpronounced determinatives (`{d}EN.ZU`), subscript digits index homophonous sign values (`ZI₃`). Opening them to spaces makes every **bare sign reading its own searchable token** (`zi3`, `en`, `zu`, `gesbun` — š/ṣ/ṭ and macrons fall to the generic strip), and a query spelled with the notation (`a-na`, `ZI₃`) folds to the same shape via the query union. Strictly per-codepoint (no space collapsing) so the KWIC fold-map equality holds; FTS treats separator runs as one. Trade-off accepted: a determinative sits as its own token *between* the signs it classifies, so a phrase query spanning a mid-word determinative must spell it (`amar suen` does not match `{d}amar-{d}suen`; `amar` and `suen` individually do), and the normalized dictionary forms (`qēmu`, `Dunnum`) are lemma search's job — the ORACC adapter feeds every `cf` into the lemma index. |
| `ang` | æ→`ae`, þ→`th`, ð→`th` | The Old English fold (P12-3), argued from Bosworth-Toller's own practice, not assumed: B-T alphabetizes æ as "ae" (the dump files æppel between a-h- and a-l- words) and **interfiles þ and ð as ONE letter** after T — its dump's own `<sort>` field folds æðele → `aetþele` and þing → `tþing`, i.e. the dictionary itself folds æ→ae and buckets ð/þ identically. These are also the ASCII transliterations a user types (`define aethele`, `search thing`). ð→`d` was considered and REJECTED: it would split the þ/ð pair B-T unifies (OE scribes used them interchangeably for the same dental fricative; the dump has no ð-initial headwords at all — ð lives medially: ǽg-hwæðer). Wynn (ƿ) gets no rule deliberately: edited OE prints w. Vowel length (á, ǣ) falls to the generic mark strip, matching B-T's alphabetization of accented vowels as base letters. Implemented as `gsub`, not `tr` (1→2 expansions; `fold_with_map` handles non-length-preserving folds, and downcase runs first so Æ/Þ/Ð reach the rule lowercased). Query-union note: `þing` gains an ang variant `thing` that also matches English text — the same bounded cross-language tradeoff as lat v→u, harmless since æ/þ/ð barely occur outside the OE corpora. The rule landed BEFORE any ang corpus was synced (aspr/iswoc/bosworth-toller all `enabled: false` at the time), so the rebuild-storm caveat below was satisfied vacuously. |
| `sl` | Bohorič long s ſ→s | The historical-Slovene fold (P13-9). goo300k/IMP passage text is the pristine Early Modern print surface, where non-final s is set as ſ (U+017F): "ſvoje", "dvanajſt", "oblaſt". The generic fold does NOT touch it — ſ is already lowercase, carries no combining mark, and plain `downcase` leaves it alone (only Unicode FULL case folding maps ſ→s) — so without this rule every ſ-bearing word is unfindable by any modern query. Exactly the grc ς→σ situation: one letter, two positional glyphs; Unicode's own case-folding table agrees. `tr`, length-preserving. Bohorič digraphs (zh=č, ſh=š) are deliberately NOT rewritten — that is orthographic modernization (the corpora's own `<reg>` layer, an annotation), never a fold; haček letters (č/š/ž) fall to the generic mark strip on both sides. The rule landed BEFORE any sl corpus was synced (goo300k/imp both `enabled: false`), so the rebuild-storm caveat below was satisfied vacuously. |
| everything else (`chu`, `orv`, `got`, `san`, unknown) | none — generic fold only | See below. |

**Why the query can't just pick a rule:** queries carry no language, so
`Normalize.query_forms` returns the *union* — the generic form plus each
language rule's variant when it differs — and `Query::Search` ORs them in
the FTS MATCH. A passage in language L is indexed as
`extra_L(generic(text))`, and the union always contains
`extra_L(generic(query))`, so per-language documents are always findable;
and because the variants are ORed, the generic variant still matches
languages with no extra rule — Gothic "jah" stays findable even though the
lat variant of that query reads "iah".

**Lemmas fold by the same table (P7-5):** a lemma is a dictionary form in
its passage's language, so the lemma index stores
`Normalize.search_form(lemma, language)` and `Query::LemmaSearch` matches
the `query_forms` union — the whole argument above applies verbatim. Note
Greek dictionary forms routinely *end* in ς (λόγος → λογοσ): consistent
precisely because BOTH sides fold.

**Deliberately conservative decisions (the open questions):**

- **Greek adscript iota.** The combining subscript (ᾳ = α + U+0345) strips
  with the marks; adscript spelled as a full letter iota (αι) is *not*
  folded away. Folding it would require dictionary knowledge (real
  diphthongs vs adscript) — left alone.
- **OCS / Old East Slavic letterforms.** The zogr fixture's real titla
  (U+0483) and palatalization marks (U+0484) strip as Mn — verified against
  TOROT text (дх҃омь → дхомь). But letterform variants (ꙇ vs и vs і, ѡ vs о,
  оу vs у) are kept distinct: they are orthographically meaningful to Slavic
  editors and no established search-normalization practice was found to
  cite. If corpus experience shows misses, a letterform table is a
  one-place change here. Note one side effect: й folds to и (its breve is
  Mn) — acceptable, standard Russian search behavior.
- **Sanskrit (Vedic, IAST romanization).** IAST diacritics are *phonemic*
  (ā vs a distinguishes words), and the generic strip conflates them
  (kṛṣṇa → krsna). That is the accepted price of diacritic-insensitive
  search — same tradeoff as Greek accents — and the pristine text keeps the
  full IAST. No extra rules.
- **Gothic.** Romanized with j and þ as real letters; generic fold only
  (þ survives, j is protected from the lat rule by the query union — and,
  since P12-3, þ is protected from the *ang* rule the same way: "qiþands"
  still matches on the generic variant).
- **Elision apostrophes** (U+02BC vs U+2019 vs U+0027, §1) are *not*
  unified — upstream reality, and unicode61 treats them all as token
  separators anyway.
- **Reconstruction shelves (`sla-pro`/`ine-pro`/`gem-pro`, P14-1).**
  Generic fold only. Proto-Slavic works well (hačeks strip: *cěsařь →
  cesarь; jers are letters and stay). PIE headwords keep their laryngeal
  subscripts (h₂) and modifier letters (ʰ ʷ) — `define *h₃ebʰi` is not
  ASCII-typeable, an accepted gap: the primary entry path is `nabu etym`
  from an attested (typeable) lemma, and starred forms are copy-pasteable
  from its output. An ine-pro ASCII fold (₂→2, ʰ→h) is a possible future
  rule here if usage demands it.

**Diplomatic line-break rejoining (P14-5 — PARSER-SCOPED, not a language
rule).** CCMH's Suprasliensis txt is a diplomatic folio-line edition where
51% of lines wrap MID-WORD with a hyphen (`… ne dobr@ mOdrova-` / `ti na
…`). Line grain is the owner-chosen citation unit, but un-rejoined the
index would carry only fragments: `modrovati` unfindable, the orphan `ti`
a junk token. The rule: the pristine passage text keeps the line VERBATIM
(hyphen included — canonical means canonical); `text_normalized` is minted,
through the same one boundary (`Normalize.search_form`), over a REJOINED
derivation source — the hyphen line has its split word completed (hyphen
dropped, the next line's first token appended), the continuation line
drops its orphan leading fragment. The derivation is recorded per passage
in the `hyphen_join` annotation (`{"tail" => …}` / `{"orphan" => …}`, a
line can carry both) so it is **recomputable from the stored row alone** —
`CcmhTxtParser.search_source(text, annotations)` is the pure function, and
the adapter conformance suite pins `text_normalized` to the minted fold of
it (the `conformance_search_source` hook; every other adapter stays pinned
to the pristine text). Tools that read the annotation: `Query::Concord`
(KWIC) retries a missed keyword against the rejoined haystack with every
appended tail character mapped to the hyphen/EOL display position, so the
highlight is exactly the visible `mOdrova-` — honest, never fabricated
display text; `nabu show` displays the annotation as any other. Scope
argument: this is a property of ONE corpus's diplomatic layout, not of
`chu` — ASPR/Freising/GRETIL lines don't hyphenate, and the gospels' CES
XML doesn't either — so the rule lives in the parser, not in
`LANGUAGE_FOLDS`; a future diplomatic source may reuse the annotation
contract. Known limits, accepted: an UNMARKED wrap (upstream sometimes
splits without a hyphen: `(ot&ved` / `^jO`) is undetectable and left
alone; an EOL "missing" mark (`-` also means a lost letter in the
transliteration) would be mis-joined — the pristine text is untouched
either way. Content hashes cover `text_normalized` + annotations, and the
derivation is deterministic, so two parses and rebuilds agree.

Changing any rule here changes every `text_normalized` and therefore every
passage `content_sha256`: plan a full `nabu rebuild` (drop + re-derive), not
a parse-only sync, or the loader will read the change as a corpus-wide
revision storm.

References: PHI Latin search help (latin.packhum.org/help/search); TLG Beta
Code manual (S for all sigmas); Unicode TR#15 (NFC/NFD); verified fixture
behavior in test/normalize_test.rb.

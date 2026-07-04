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
  letter, both legitimate. Search folding (a later enrichment) has to know;
  byte-level tools don't.

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

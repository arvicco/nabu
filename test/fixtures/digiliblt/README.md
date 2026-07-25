# digilibLT fixture

Real bytes from CIRCSE's digilibLT repo (github.com/CIRCSE/digilibLT, `main`),
retrieved 2026-07-25. digilibLT = Biblioteca digitale di testi latini
tardoantichi (Vercelli / Università del Piemonte Orientale): 373 late-antique
secular Latin prose texts (2nd–7th c. AD), UDPipe-lemmatized and LiLa-linked
by CIRCSE (LiLa: Linking Latin, ERC 769994).

Upstream ships the CoNLL-U files INSIDE four archives
(`conllu/part{1..4}.tar.gz`, ~106 MB; ~700 MB extracted); the adapter's fetch
extracts them into `texts/part*/`. This fixture mirrors that POST-FETCH tree,
so the files below were taken from inside the archives — none is individually
raw-GETtable (see `manifest.yml`: every entry is `refetchable: false`).

## Layout

- `texts/part1/dlt000173.xml_linked.conllu` — a complete small work, WHOLE
  (Euantius, *De comoedia uel de fabula*; 55 sentences). Carries multi-IRI
  ambiguous LiLa links (`fructibus` → lemma/103879 + lemma/103880 — the
  README's "Bronze" linking) and the known snippet the adapter test pins
  ("Initium tragoediae et comoediae a rebus diuinis est incohatum…").
- `texts/part4/dlt000619.xml_linked.conllu` — the corpus's smallest work,
  WHOLE (*Decretum provinciae Africae*, an anonymous 1-sentence inscription
  text). Documents the `docAuthor=No author` sentinel, `SpaceAfter=No`,
  IRI-less tokens, and the machine-lemma damage that pins the silver tier
  ("rovinciae" → lemma "rovintia"; "defensaeque" → "defensaes").
- `texts/part2/dlt000340.xml_linked.conllu` — TRIMMED: the doc header + the
  first 2 of 662 sentence blocks (byte-verbatim lines; a terminating blank
  line restored). Kept for the wrapped-docTitle continuation line — one of 3
  files upstream whose `# docTitle` spills onto a raw un-prefixed line.
- `malformed/dlt000079-head.conllu` — TRIMMED: the REAL first 14 lines of the
  one damaged file upstream (Cassius Felix, *De medicina*): a stray `http`
  glued before the first header comment (deeper in the file: token lines with
  spaces for tabs, loose prose words). Lives OUTSIDE `texts/` so discover
  never yields it; the parser test pins that these bytes raise
  `Nabu::ParseError` (quarantine, never paper-over).

## The dialect (censused over all 373 files, 2026-07-25)

Token lines are 11–14 tab-separated columns: the 10 standard CoNLL-U columns
plus 1..4 LiLa lemma-bank IRI columns (empty when unlinked — 1,998,023 of
7,797,853 tokens; multiple when the linking is ambiguous — 397,689 tokens).
XPOS/FEATS/HEAD/DEPREL/DEPS are `_` corpus-wide (UDPipe lemma + PoS only).
Every file opens with a `# key=value` doc header (docId/docTitle/docAuthor/
description…) closed by a blank line; every sentence block carries an integer
`# sent_id` (1..n per document) and an authoritative `# text`. MISC carries
`CitationHierarchy=Paragraphus_N,Sentence_N` (verse texts: `Versus_N`) on
every token, plus `SpaceAfter=No`. No per-text date metadata exists in this
lane. NB: this is why the shared `ConlluParser` (strictly 10 columns, no doc
header) is NOT composed — see the `digiliblt-conllu` family class note.

## License

Repo README "Copyright", verbatim: "The *DigilibLT* texts are licensed under
a Creative Commons Attribution-ShareAlike 4.0 International License" (the
statement links by-sa/4.0). Recorded fork: the decorative badge beside it
still links CC BY-NC-SA 3.0 (the digilibLT SITE's own TEI license); the
repo's written BY-SA 4.0 grant governs this lane — see the adapter class
note and docs/02-sources.md #121.

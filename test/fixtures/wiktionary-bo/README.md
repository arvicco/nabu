# wiktionary-bo fixtures

Trimmed real sample of the kaikki.org (wiktextract) Tibetan extract for
the `wiktionary-bo` adapter tests.

- Retrieved: 2026-07-28
- URL: https://kaikki.org/dictionary/Tibetan/kaikki.org-dictionary-Tibetan.jsonl
  (linked from https://kaikki.org/dictionary/Tibetan/ — "3394 distinct
  words"; upstream Last-Modified 2026-07-25)
- Full-file census at retrieval: 4,547,518 B, 3,651 lines (one JSON
  record per line = one word × POS × etymology section), sha256
  `765f3eca244d9d0b0b89ec49b15d447cf5f2f9ff73331b403f729fea4f83ec41`
- License, verbatim from kaikki.org/dictionary/ "Copyright and license":
  "This data is made available under the same licenses as Wiktionary -
  both CC-BY-SA and GFDL." (+ wiktextract citation request: Ylönen,
  LREC 2022)
- NB the same DEPRECATION caveat as wiktionary-cu (wiktextract #1178):
  the per-language JSONL serves today; the fallback is filtering the
  full enwiktionary extract by `lang_code == "bo"`.
- The Classical Tibetan (xct) and Old Tibetan (otb) per-language
  extracts do NOT exist upstream — 404s verified 2026-07-28
  (kaikki.org-dictionary-ClassicalTibetan.jsonl,
  kaikki.org-dictionary-OldTibetan.jsonl). The bo extract is the one
  kaikki Tibetan artifact.

## Trim recipe (172 of 3,651 lines, every kept line byte-verbatim)

Stratified selection, in upstream file order:

- demo lemmas: སངས་རྒྱས (Buddha), བྱང་ཆུབ་སེམས་དཔའ (bodhisattva — the
  define golden, with its compound etymology), ཆོས (the noun/verb
  homograph pair), བླ་མ, རྡོ་རྗེ;
- ALL 18 entry-id collision groups (word:pos[:ety] bases that repeat →
  positional `:n` suffixes, the wiktionary-jsonl contract);
- both no-gloss records (the honest nil-gloss path);
- the first 15 descendant-bearing records + every record with a
  Sanskrit (`sa`) descendant — notably བོད "Tibet" (grc Βαῖται → la
  Baetae, pra *bhŏṭṭa → sa भोट/भौट्ट, borrowed-flagged; the crosswalk
  edges into held shelves) — fixture totals 18 reflex-bearing records /
  88 worded edges (full file: 134 / 307);
- every 32nd line for breadth.

Full-file distribution notes: lang_code uniformly "bo"; 19 POS values
(noun 2,386 · name 492 · verb 364 · adj 176 · num 70 …); 1,548 records
carry etymology_text.

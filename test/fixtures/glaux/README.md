# GLAUx fixture

Real bytes from the GLAUx corpus (github.com/alekkeersmaekers/glaux, `main`),
retrieved 2026-07-24. GLAUx = "the Greek Language Automated" — ~20M tokens of
Ancient Greek, automatically annotated for morphology, syntax, lemmas, animacy
and word senses (Keersmaekers 2021, doi:10.18653/v1/2021.lchange-1.6).

## Layout (mirrors the upstream sparse cone the adapter fetches)

- `xml/0003-002.xml` — a complete small work (the μνῆμα epigram; 4 sentences,
  36 tokens). Carries elliptic reconstruction tokens (`form="E"
  artificial="elliptic"`), `animacy` and `sense` semantic layers, and the
  citation attributes `div_book` / `div_chapter`. The whole file, untrimmed.
- `xml/0004-002.xml` — a larger single work (84 sentences), whole, for a
  broader parse and NFD-variety coverage.
- `metadata.txt` — the upstream per-text metadata table, TRIMMED to the header
  plus five real rows (kept byte-for-byte, tabs preserved):
  - `0003-002`, `0004-002` — the two fixture works (CC BY-SA 4.0, no manual
    treebank → inherit the source's `attribution` class, no override).
  - `0068-001` — CC BY-NC-SA 4.0 source text → `license_override: nc` (the
    NC-source slice of the D44-a census).
  - `0016-001` — CC BY-SA 4.0 source, but manual annotation from **PROIEL**
    (CC BY-NC-SA 3.0) → `nc` (the NC-annotation slice).
  - `0028-001` — CC BY-SA 4.0 source, but manual annotation from the **Gorman**
    trees (CC BY-NC-SA 4.0) → `nc` (the other NC-annotation slice).

## Encoding

GLAUx is encoded in **Unicode NFD** (the README states this explicitly:
diacritics are separate combining characters). The adapter NFC-normalizes at the
boundary (house rule). E.g. the first form `μνῆμα` arrives as
`μ ν η U+0342(perispomeni) μ α` and normalizes to `μ ν ῆ(U+1FC6) μ α`.

## License

"Most of the data is available under a CC BY-SA license but some texts are more
restrictive (e.g. CC BY-NC): the license of each source text is also specified
in the metadata file." Per-text license honored at parse; see the adapter's
census comment for the corpus-wide distribution.

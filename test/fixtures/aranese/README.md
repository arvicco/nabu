# aranese fixtures — ES-OC (Spanish–Aranese) Parallel Corpus (Hugging Face)

Retrieved 2026-08-19 from the Hugging Face dataset
`projecte-aina/ES-OC_Parallel_Corpus` (BSC Language Technologies Unit;
built for the WMT24 shared task "Translation into Low-Resource Languages
of Spain"), via the plain-HTTPS resolve URLs:

- `arn/es-arn_corpus.arn` — the Aranese side, trimmed from
  <https://huggingface.co/datasets/projecte-aina/ES-OC_Parallel_Corpus/resolve/main/es-arn_corpus.arn>
  (full artifact 2026-08-19: **51,087,360 bytes, 419,908 lines**, sha256
  `2c134f394e664fc0ec372e79da2b6c2254499b5cb7acda1122d24da4e9554112`).
- `es/es-arn_corpus.es` — the Spanish side, trimmed from
  <https://huggingface.co/datasets/projecte-aina/ES-OC_Parallel_Corpus/resolve/main/es-arn_corpus.es>
  (full artifact 2026-08-19: **51,463,705 bytes, 419,908 lines**, sha256
  `1978db8bc7d43e532571e56ffffce5e88c8e73398e809c5e93192579ec7a3b26`).

Both files are line-aligned (equal line counts censused — alignment IS
the format; the adapter treats a count mismatch as damage). Both fixtures
hold the SAME byte-verbatim lines — **1–5 plus 77,909** — so the trimmed
pair stays aligned. Line 77,909 is the first non-NFC line on BOTH sides
(the four non-NFC lines sit at identical positions 77909 / 234311 /
286783 / 317995 — mixed Cyrillic with a decomposed accent, "ДéHди"),
exercising the `Normalize.nfc` boundary. Zero blank lines, no BOM/CRLF.

No sentence ids — passage identity is the 1-based line number in the
local canonical file (the tla-hf precedent); the -es sibling cites the
same line numbers (the Query::Parallel suffix contract).

**Provenance honesty (the dataset card's own words): the corpus is
"mainly synthetic"**, generated with the rule-based translator Apertium —
synthetic Spanish from the authentic Aranese PILAR monolingual dataset,
synthetic Aranese from the Spanish side of OPUS pairs, plus pairs from
the shared-task Diccionari der Aranés. The card does not mark which rows
are which, and warns it "may contain poorly aligned sentences". The
Aranese side is stored as what it is: the largest openly licensed Aranese
text mass there is, part authentic, part machine-generated — recorded in
the source registry and docs, never presented as an attested corpus.

## License (verified 2026-08-19)

Dataset card YAML frontmatter, verbatim: `license: cc-by-sa-4.0`. Card
prose: "This work is licensed under an Attribution-Share Alike 4.0
International". → `license_class: attribution` (the house BY-SA class,
the trismegistos/tla-hf precedent).

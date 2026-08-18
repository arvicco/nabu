# Fornsvenska textbanken fixtures

Retrieved 2026-08-13 from Språkbanken Text
(spraakbanken.gu.se/resurser/meningsmangder/fsv-<part>.xml.bz2; the
per-part resource pages state CC-BY-4.0 and carry DOIs — fsv-aldrelagar
is doi.org/10.23695/6bcv-5386). Two parts trimmed to their first two
texts / two paragraphs each (content verbatim, re-bzipped):

- `fsv-aldrelagar` — Äldre Västgötalagen (1280–1290) + Bjärköarätten
  (1300–1350): the laws part, 28 texts upstream.
- `fsv-verser` — Erikskrönikan (1470–1479) + Karlskrönikan
  (1389–1452): the rhymed chronicles and Eufemiavisorna part.

The `<w>` attributes (posset/lemma/lex/variants) are AUTOMATIC fsvm
morphology-lexicon candidate SETS (pipe-bounded, often multi-valued,
mostly empty) — v1 deliberately does not ingest them: candidate sets
are not attestation, and a future lemma lane would need its own
ruling. Upstream frozen since 2013-10-08.

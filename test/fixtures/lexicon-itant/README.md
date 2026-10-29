# Lexicon ItAnt fixtures

Real upstream sample from **DigItAnt/Lexicon_ItAnt** — the OntoLex-Lemon
lexicon of the languages of ancient Italy (DigItAnt, PRIN 2017 "Languages
and Cultures of Ancient Italy", CNR-ILC Pisa + Università di Firenze),
the sibling of the Corpus ItAnt inscriptions (`test/fixtures/itant/`).

- **Upstream:** <https://github.com/DigItAnt/Lexicon_ItAnt>, branch
  `main`, commit `e8fe52a816` (2024-10-15, the last push).
- **Retrieved:** 2026-10-29 through the GitHub contents API.
  `lexicon_1_0.ttl` 5,187,573 bytes, sha256
  `021106384794fcc88630d9c920ff41270aeda7f6dae9dc07af69a2fd48d738d9`;
  `semanticFields_Buck_ItAnt_skos.ttl` 814,221 bytes, sha256
  `8e6a24e66203e7a40cd08d562250e05ec86b3a90a537a31767d486a60d767cb2`.
- **License (README.md, verbatim, the whole file):** "Lexicon_ItAnt  is
  licensed under CC-BY-NC-SA" — no version, no LICENSE file, the GitHub
  license field empty → license_class `nc`. The `cc:license` /
  `dct:rights` statements inside the TTL belong to the bundled
  vocabularies (lexinfo CC BY 4.0, OntoLex/lemon CC0), not the lexicon.

## Upstream's delivery grains

| grain | where | adapter |
|---|---|---|
| README.md | one line, the license | not data |
| `lexicon_1_0.ttl` | GraphDB export: 21 `lime:Lexicon` nodes (one per `lime:language`), 1,301 `lime:entry` memberships, the lexinfo/OntoLex/SKOS/OWL vocabularies, a 1,136-concept Buck semantic-field scheme | parsed |
| — the 16 ancient-Italy lexicons (osc 419 · xve 85 · xum 82 · xfa 75 · pgn 31 · xcg 27 · spx 23 · umc 17 · ett 16 · xvo 10 · ims 9 · xvs 8 · sbv 3 · snt 2 · xhr 1 · xca 1 = 809) | | ACCEPTED, one dictionary each (`itant-lexicon-<code>`) |
| — the auxiliary lexicons lat 157 · grc 22 (cognates/donors) and PIE 164 · PIT 148 · PUM 1 ("Language for etymology") = 492 | | REJECTED by rule (discovery_skips); their words ride the accepted entries as reflexes |
| `semanticFields_Buck_ItAnt_skos.ttl` | the same concept scheme standalone; not well-formed Turtle (`@base`, an undeclared `dcterms:` prefix, a missing `;`) | REJECTED by rule |

809 + 492 = the 1,301 memberships. One further typed Word
(`LexO_2024-10-1407_03_10_339`, labeled with its own id) belongs to no
lexicon — an unattached LexO stub, carried in this fixture as the
specimen the adapter never reaches.

## What the fixture holds

`lexicon_1_0.ttl` is a **block trim**: the export writes one
blank-line-separated block per (subject, predicate); the kept blocks are
byte-verbatim. Kept: the `@prefix` header; four ontology-noise specimens
pinning the parser widening (`rdfs:Class a owl:Class`, the
`_:node71 owl:hasValue true` bare boolean, an `owl:versionInfo 1.0` bare
number, a `"""…"""` SKOS comment); every block of the subjects below and
of their forms, senses, etymologies, EtyLinks, link sources and
bibliography nodes; the 8 lexicon nodes osc/umc/xfa/xve (accepted) and
lat/grc/PIE/PIT (rejected specimens) — their `lime:entry` lists verbatim,
so most members DANGLE (no statements; the adapter skips them); the Buck
concepts whose `ontolex:lexicalizedSense` reaches a kept sense.

| entry | lexicon | pins |
|---|---|---|
| `meddíss_noun_osc_entry` | osc | 17 forms incl. Greek-script μεδδειξ, attestation notes, two PIE etyma, four cognates (only umc medix kept — ims/pgn/xvo dangle), two bib nodes citing one book, semantic field |
| `senateís_noun_osc_entry` | osc | a borrowing whose source is a WORD of the rejected lat lexicon (senātus) |
| `seemuneís_properNoun_osc_entry` | osc | a non-NFC label with editorial marks (`seemuṇẹị́[s`) |
| `deívaí_noun_osc_entry` | osc | a `"""` multi-line sense definition ("subst.: dea; adj.: divina"); HTML notes with `&#237;` references; PIT + PIE etyma |
| `purasiaí_adjective_osc_entry` | osc | a second semantic field (Physical World) |
| `medix_noun_umc_entry` | umc | the reverse cognate edge |
| `LexO_2023-04-2713_34_08_678` (apolo) | xfa | a borrowing from the rejected grc lexicon (Ἀπόλλων) |
| `LexO_2023-03-3013_44_13_67` (med) | xfa | a LexO-minted id; Bakkum references |
| `LexO_2023-08-0413_33_51_854` (mego) | xve | `<div>`-wrapped attestation notes, `&#160;` |
| `LexO_2024-10-1407_03_10_339` | (none) | the lexicon-less stub |

`semanticFields_Buck_ItAnt_skos.ttl` keeps upstream lines 1–39 (the
header through the first concept) — the rejected-grain specimen.

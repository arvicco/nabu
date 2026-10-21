# VKS fixtures

Source: Vanhan kirjasuomen korpus — the Corpus of Old Literary Finnish,
Kotimaisten kielten keskus (Institute for the Languages of Finland, Kotus),
distributed by Kielipankki (the Language Bank of Finland) in Korp: Korp
version urn:nbn:fi:lb-201407166, metadata urn:nbn:fi:lb-201407165. Read
through the anonymous Korp JSON API, <https://www.kielipankki.fi/korp/api8/>
(korp.csc.fi/korp/api8 redirects there). Retrieved 2026-10-21.

License: EUPL v1.2 — Kielipankki's Korp configuration for the VKS folder,
verbatim: `licence: { name: "EUPL v. 1.2", description: "Euroopan unionin
yleinen lisenssi v. 1.2 (EUPL)", urn: "urn:nbn:fi:lb-2024082106" }`. The
licence page behind that URN was unreachable on 2026-10-21 (kielipankki.fi
down for maintenance; urn.fi behind a browser challenge) — re-read it at the
first harvest.

## Upstream grains

| Grain | Where | Taken? |
|---|---|---|
| corpus — 12 subcorpora VKS_AGRICOLA … VKS_VIRRET (4,133,202 tokens, 167,400 sentences) | corpus_info | the harvest unit (`texts/<CORPUS>/`) |
| text file — `text_filename`, 134 (struct_values census) | the `text` structure | **yes: the document** (`texts/<CORPUS>/<stem>.jsonl`) |
| text element — a dated `<text>` (the decree, sermon and almanac collections hold one per year) | `text_datefrom`/`text_dateto` | the passage `date` when a file holds several |
| sentence_code — the corpus's line / verse / paragraph key | the `sentence` structure | **yes: the passage** (a run of one code) |
| Korp sentence | the `sentence` structure | folded into its code's passage |
| token — `word`, `word_completed`, `word_tilde` | positional attributes | word is the text; completions ride as `expansions` |
| `foreign`, `error` spans | structural attributes without values | not carried by the kwic rows — declared coarse |
| a bulk download | — | none exists (the reason for the API route) |

## Files

- `korp/corpus_info.json` — the real `corpus_info` response for VKS_FROSTERUS
  + VKS_LPETRI, verbatim.
- `korp/query_frosterus_0-1.json`, `korp/query_frosterus_2-3.json`,
  `korp/query_lpetri_0-1.json` — real `query` responses (cqp
  `<sentence> []`, `default_context` "1 sentence", two sentences each),
  verbatim. The fetch tests serve them as recorded and RESTATE the corpus
  totals (corpus_info Sentences, the pages' hits: 967 / 778 recorded) to the
  four / two sentences served — the recorded totals would demand the whole
  corpus.
- `texts/<CORPUS>/<stem>.jsonl` — four texts in the KorpFetch landing shape
  (structs verbatim, tokens repacked `[word, completed|null, tilde|null]`),
  built from real kwic rows recorded the same day:
  - `VKS_AGRICOLA/agri1_abc1543.jsonl` — Agricola's Abckiria (1543), all 108
    sentences: headings, `sentence_cRef` scripture references, completed
    abbreviations (minu → minun, Amud → Amund marked Amun~d).
  - `VKS_FROSTERUS/jafro1791.jsonl` — the first 40 of 967 sentences (codes
    JAFro1791-1 … -8).
  - `VKS_BIBLIA/ut1_ev.jsonl` — 60 sentences from sentence 50,000 of
    VKS_BIBLIA (John 19:38 – 21:11 of the 1642 Bible; verse codes, the
    chapter summaries `Jh-20:0`, `Jh-20:00`).
  - `VKS_LAIT/as1800.jsonl` — a 40-sentence window of the 1800s decrees
    crossing the 1805 → 1806 text elements.

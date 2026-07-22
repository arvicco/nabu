# Menotec fixtures (Old Norwegian / Old Norse, PROIEL XML)

Real samples from the **Menotec** treebank — a corpus of 13th/early-14th-century
Old Norwegian manuscripts plus the Poetic Edda (Codex Regius), morphologically
and syntactically annotated in the **PROIEL** dependency scheme (CLAUDE.md
fixture rules). Two texts, each trimmed to its first 5 sentence blocks.

## Where Menotec actually lives (established live, P40-g)

The survey said Menotec is "published in the PROIEL treebank family." That is
true of the *annotation scheme and format*, but **the Menotec data is NOT in the
`proiel/proiel-treebank` GitHub repo** (that repo holds only the classical
Greek/Latin/Gothic/Armenian/OCS texts — checked live, all releases). Menotec is
served **only through the INESS portal** (`clarino.uib.no/iness`), a Vue.js SPA
backed by a session-based REST API. There is no GitHub raw GET and no bulk-file
download; INESS re-exports each treebank on demand.

### The real artifact and how it was acquired (for P40-2)

INESS exposes a corpus API at `https://clarino.uib.no/iness/rest?command=<cmd>&session-id=<id>`.
The acquisition flow, **anonymous — no login required** (userId came back
`null`; the CC BY-NC-SA licence is a portal label, not a download gate for
these dependency treebanks):

1. `command=get-session` → `{"sessionId": "<digits>"}` (ephemeral; expires).
   Envelope **evidenced** by a live capture 2026-07-22 (P40-i1), e.g.
   `{"sessionId": "261731751530541"}`.
2. `command=list-resources&details=true&project=iness` → the corpus list.
   Envelope **evidenced** by a real capture (see
   `iness-list-resources-trim.json` below; captured 2026-07-22 at the
   **P40-i1 incident** — the fetch tests' original reconstructed envelope
   keyed entries on `"id"`, but upstream keys them on **`"name"`**, and the
   owner's first live sync failed on exactly that divergence). Top-level keys
   `resources` / `languages` / `collections`; each of the 589 `resources`
   entries is shaped
   `{"name": …, "printName": …, "type": …, "languages": [...],
   "languageNames": [...], "collections": [...], "size": N, "license": {…}, …}`
   (no `"id"` field at all). The
   **Menotec collection has 7 dependency treebanks** (all `languages: ["non"]`,
   `type: dependency`):
   `non-edda-regius-dep` (Poetic Edda / Codex Regius, 3665 sentences),
   `non-homiliebok-dep` (Old Norwegian Homily Book, 3833),
   `non-konungs-skuggsia-dep` (Konungs skuggsjá / King's Mirror, 3059),
   `non-landslov-holmperg34-dep` (Landslov, Holm perg 34, 3266),
   `non-olavssaga-dep` (Óláfs saga, 3561),
   `non-pamphilus-dep` (Pamphilus, 434 — the smallest),
   `non-strengleikar-dep` (Strengleikar, 2490).
3. `command=get-treebank-documents&type=dependency&treebank=<id>` → the document
   list (the treebank's chapters / poems). Envelope **still
   reconstructed-from-flow** (no captured body); the fetcher's shape errors
   therefore dump the actual top-level keys + a truncated sample, so a live
   divergence here diagnoses itself from the error text (the P40-i1 lesson).
4. `command=get-sentences&mode=text&download-mode=tiger-xml&type=dependency&treebank=<id>&document-id=<doc>`
   → the annotated text. Despite `download-mode=tiger-xml`, the payload
   (`sentences.data`) is **native PROIEL XML** (see below).

Because the URL carries an ephemeral `session-id`, a plain raw GET cannot
reproduce it — so these entries are `refetchable: false` in the manifest
(provenance `iness-api`). **P40-2's adapter must implement the get-session →
get-sentences flow**, not a static fetch.

## Files

| File | Bytes | Treebank / document | Trim |
|---|---|---|---|
| `non-pamphilus-dep/ch1-head5.xml` | 6,332 | `non-pamphilus-dep`, document "Ch. 1" (65 sentence blocks in the full document) | first **5 sentence blocks**, whole blocks, in document order |
| `non-edda-regius-dep/alvissmal-head5.xml` | 6,325 | `non-edda-regius-dep`, document "Alvíssmál" (80 sentence blocks in the full poem) | first **5 sentence blocks**, whole blocks, in document order |
| `iness-list-resources-trim.json` | 5,712 | the REAL anonymous `list-resources&details=true` response (P40-i1 capture, 2026-07-22) | of 589 resources kept 9 entries **verbatim** (all 7 Menotec + `deu-pargram` (lfg) + `ang-aels-dep` (ISWOC dependency) as non-Menotec probes) + the first 2 and the `non`/`Menotec` entries of `languages`/`collections`; all three top-level keys and every kept object structurally intact; 258 KB → 5,712 B |

**Canonical layout (P40-2 decision).** The adapter treats **one treebank = one nabu
document** (the treebank-global `sentence/@id` keys the passages, so a treebank's
sentences are unique across its several upstream documents — Alvíssmál's blocks
start at `sent_id 3586`, continuing the Edda's earlier poems). `Nabu::InessFetch`
writes each upstream get-sentences export verbatim to
`canonical/menotec/<treebank>/<document>.xml`, so the fixture mirrors that shape:
one `<treebank>/` subdirectory per treebank, holding its document file(s). Here
each fixture treebank carries a single (trimmed) document; a real sync writes many
`<document>.xml` files per treebank subdir. `discover` yields one ref per treebank
subdirectory; `parse` reads every `*.xml` under it, in filename order.

Retrieved 2026-07-22 from INESS. The full per-document exports (119,901 B and
195,397 B) were held in a scratch dir and are **not** committed.

## Format note — CRITICAL for the P40-2 adapter

The INESS `get-sentences` export is **NOT** the single well-formed `<proiel>`
document that the `proiel/`, `iswoc/` and `torot/` fixtures are (those have one
`<?xml?>` declaration, a `<proiel>` root, a shared `<annotation>` vocabulary
block and a `<source>` metadata header). Instead INESS returns a **blank-line-
separated stream of per-sentence fragments**, each shaped:

```
# text = <surface text>
# sent_id = <n>
<?xml version="1.0" encoding="UTF-8"?>
<sentence id="…" status="reviewed" presentation-before="…">
 <token id="…" form="…" lemma="…" part-of-speech="…" morphology="…"
        head-id="…" relation="…" presentation-after="…"
        foreign-ids="menota-id=w00001"/>
 …
 <token …>
  <slash target-id="…" relation="xsub"/>   <!-- secondary edges -->
 </token>
</sentence>
```

So each block is a CoNLL-style `# text` / `# sent_id` header **plus its own
`<?xml?>` declaration and one `<sentence>` element** — the whole file is
therefore **not** a single parseable XML document. The adapter must split on
blank lines and parse one `<sentence>` at a time (or strip the repeated
declarations). The token annotation IS the real PROIEL vocabulary
(`part-of-speech` two-letter codes, positional `morphology` strings, `head-id`
/ `relation` dependency edges, `<slash>` secondary edges), matching the
`proiel/` fixture's per-token shape — only the document envelope differs.
`non-edda-regius-dep` tokens additionally carry `citation-part="Alvíssmál 1"`;
`foreign-ids` links back to Menota (`menota-id=…`) or the island-id register.

## License (recorded exactly)

Menotec is **CC BY-NC-SA 4.0**. The INESS resource metadata (`command=metadata`)
license block reads verbatim: *"This resource is licensed under the following
terms: Creative_Commons-BY-NC-SA (CC-BY-NC-SA)"*, linking
`http://creativecommons.org/licenses/by-nc-sa/4.0/`. The Språkbanken /
Nasjonalbiblioteket catalogue record for the Menotec collection
(`https://www.nb.no/sprakbanken/en/resource-catalogue/oai-clarino-uib-no-menotec/`)
agrees: *Creative Commons BY-NC-SA (CC-BY-NC-SA), 4.0*. Persistent identifier
(CLARINO handle): `http://hdl.handle.net/11495/E628-DBC4-82EE-1`. → license_class
`nc` (NonCommercial-ShareAlike — the PROIEL/ISWOC posture). Cite the Menotec
project (Odd Einar Haugen et al., University of Bergen / UiO).

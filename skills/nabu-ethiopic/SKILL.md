---
name: nabu-ethiopic
description: "Methodological guidance for the ethiopic desk of a Nabu library (Ethiopicist): what its sources hold, their license classes, and the cautions to observe when searching, reading and citing them through the nabu MCP tools."
license: MIT
compatibility: "Requires the nabu MCP server (`bin/nabu mcp`, read-only, stdio) over a locally built Nabu catalog; tool names are the nabu_* set (nabu_status, nabu_search, nabu_show, and the desk instruments)."
metadata:
  desk: ethiopic
  origin: generated
  sources: "betamasaheft-works dillmann traces"
---

# The Ethiopicist — the `ethiopic` desk

The Ethiopicist — Aksum to the scriptoria: Enoch, Jubilees, and the Geʿez Bible.

The Ethiopic (Gǝʿǝz) desk in the Oriental-Christian neighborhood: the Beta maṣāḥǝft transcriptions (the Geʿez Bible, 1 Enoch, Jubilees, the Kebra nagast, royal chronicles), Dillmann's Lexicon, and the TraCES analyzed corpus with its Aksumite inscriptions — riding beside the biblical hat by design.

## Sources on this desk

The class is the machine-actionable reading of each source's data license; the
verbatim upstream terms are in `docs/02-sources.md` of the Nabu repository.

<!-- nabu:skill-sources:begin — generated from config/sources.yml by `rake skills:scaffold`; edit outside this block -->
| Source | Upstream | License class |
| --- | --- | --- |
| `betamasaheft-works` | Beta maṣāḥǝft Works — Ethiopic literature (Hiob-Ludolf-Zentrum, Hamburg) | attribution |
| `dillmann` | Dillmann, Lexicon linguae aethiopicae (TraCES/Beta maṣāḥǝft digitization) | nc |
| `traces` | TraCES — TEI-Ling analyzed Gǝʿǝz corpus (ERC 338756, Hamburg) | nc |
<!-- nabu:skill-sources:end -->

## What the shelves hold

- `betamasaheft-works` — The Beta maṣāḥǝft Works collection (Hiob Ludolf Centre for Ethiopian and Eritrean Studies, Universität Hamburg) — 6,548 TEI records of Ethiopic (Gǝʿǝz) literature, one per work. Most are catalog records, but the text-bearing minority carries the Gǝʿǝz Bible (a near-complete Old Testament, all four Gospels, Acts, Epistles, Revelation), 1 Enoch, Jubilees, the Kebra nagast, royal chronicles of Susǝnyos and ʿAmda Ṣǝyon, and the Physiologus. CC BY-SA 4.0, granted in each file.
- `dillmann` — The Gǝʿǝz dictionary shelf: Dillmann, Lexicon linguae aethiopicae (1865) in the TraCES TEI digitization — 13,727 entry files, one <entry> each (github.com/BetaMasaheft/DillmannData; the sibling `Dillmann` repo is only the eXist-db app). content_kind:dictionary, language gez, urns urn:nabu:dict:dillmann:<L-id> — the ids the traces corpus's lemma links point at. LICENSE QUIRK (recorded): every file's licence target URL is MALFORMED ("…/licenses/by-sa-nc/4.0/", a slug CC does not serve; http x12,453 + https x1,274); the prose names Attribution-ShareAlike Non Commercial 4.0 -> CC BY-NC-SA 4.0, class nc (MCP default-excluded).
- `traces` — TraCES TEI-Ling export (ERC Advanced Grant 338756, Hamburg): 15 files / 75,440 morphologically analyzed Gǝʿǝz word tokens — Matthew 12,212, Kebra nagast prologue+25 chs 3,784, ʿAmda Ṣǝyon chronicle 10,704, Testamentum Domini 12,471, "MM" 18,685, "AK" 15,599, Gadla Libānos excerpts, seven Aksumite royal inscriptions (RIE 187-232). One passage per word token (fidäl text; translit + morphology + Dillmann-entry lemma link in annotations) — the gold lemma lane of the Geʿez shelf. LICENSE =: no in-repo license; the official archive deposit governs — CC BY-NC-ND 4.0 (fdr.uni-hamburg.de record 707, DOI 10.25592/uhhfdm.707) -> nc (MCP default-excluded).

## Working cautions

- **Data license is not code license.** This guidance text is MIT; every passage
  carries its own `license_class` (`open`, `attribution`, `nc`, `odbl`, and — excluded
  by default — `research_private` / `restricted`). `nc` forbids commercial reuse of the
  quoted text; `attribution` and `odbl` require naming the source edition (`odbl`
  also binds derived databases to share-alike). A `credit` key, when present, must
  travel with any quotation.
- **An empty result is not absence of evidence.** Call `nabu_status` before concluding
  a text, word or form is unattested: the shelf may be unsynced on this box, the
  language may be indexed at another grain, or the class may be excluded by default.
- **Search is folded, `nabu_show` is pristine.** Matching runs over a folded form
  (case, diacritics, and per-language rules); quote only the pristine text
  `nabu_show` returns, never a search snippet or a folded phrase.
- **Lemma tiers differ in evidential weight.** `gold` lemmas are verified annotation
  and the only tier that counts as attestation; `silver` lemmas are upstream-automatic
  and always labeled; `equivalence` rows are glosses, never attestation. A lemma
  search reaches only the lemmatized minority of the corpus.
- **Dates are typed.** A document's primary dated row has a class — `artifact` (the
  object's own dating), `composition` (an attributed author-era date), `edition` (a
  print year, never the text's date), or `silver` (a tool estimate, never an upstream
  claim). Years are signed, with no year 0. Use `date_basis` to keep the classes
  apart.

## Reproducibility

Record, per claim: the passage or document `urn`, the `source` slug, its
`license_class` (and `credit` when served), the exact tool call and arguments, and the
date of the `nabu_status` snapshot the catalog answered from. Upstream editions are
revised; the urn plus the catalog date is the citation, the snippet is not.

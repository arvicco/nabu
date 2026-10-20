---
name: nabu-iranian
description: "Methodological guidance for the iranian desk of a Nabu library (Iranologist): what its sources hold, their license classes, and the cautions to observe when searching, reading and citing them through the nabu MCP tools."
license: MIT
compatibility: "Requires the nabu MCP server (`bin/nabu mcp`, read-only, stdio) over a locally built Nabu catalog; tool names are the nabu_* set (nabu_status, nabu_search, nabu_show, and the desk instruments)."
metadata:
  desk: iranian
  origin: generated
  sources: "cdli iedc oracc perseus-farsilit shkz skjaervo-khotanese"
---

# The Iranologist — the `iranian` desk

The Iranologist — the Avesta to the Achaemenid inscriptions, Old Iranian liturgy toward Middle Persian.

The Iranian-language lane, Zoroastrian canon at its heart: the TITUS Avesta (Old Iranian liturgy — grant-gated private research, not a public holding) and the Old Persian of the Achaemenid royal inscriptions, which ride the ORACC and CDLI cuneiform shelves whole — their trilinguals' Old Persian column the desk's shared lane with the tablet world — classical Persian literature (Hafez's Divan with its aligned English, perseus-farsilit) — and,, the Middle Iranian east: Skjærvø's British Library Khotanese editions, the Invisible East catalog's Khotanese/Sogdian/Bactrian/Judeo-Persian documents, and the trilingual ŠKZ inscription with its Parthian and Middle Persian columns.

## Sources on this desk

The class is the machine-actionable reading of each source's data license; the
verbatim upstream terms are in `docs/02-sources.md` of the Nabu repository.

<!-- nabu:skill-sources:begin — generated from config/sources.yml by `rake skills:scaffold`; edit outside this block -->
| Source | Upstream | License class |
| --- | --- | --- |
| `cdli` | CDLI — Cuneiform Digital Library Initiative (2023-10 bulk-dump snapshot) | attribution |
| `iedc` | Invisible East Digital Corpus (Oxford) — documentary Islamicate East | open |
| `oracc` | ORACC — Open Richly Annotated Cuneiform Corpus | open |
| `perseus-farsilit` | Perseus Digital Library — canonical Persian literature (Hafez) | attribution |
| `shkz` | ŠKZ — the trilingual Kaʿba-ye Zartošt inscription (aligned) | open |
| `skjaervo-khotanese` | Skjaervø — Khotanese Manuscripts from Chinese Turkestan (BL records) | open |
<!-- nabu:skill-sources:end -->

## What the shelves hold

- `cdli` — The Cuneiform Digital Library Initiative — the field's universal catalog of cuneiform artifacts: 353,283 objects with curatorial metadata (period, genre, provenience, collection), of which 135,255 carry ATF transliterations totaling about 2.19 million lines, spanning proto-cuneiform and proto-Elamite through Sumerian, Akkadian and Eblaite, many lines with inline English translations, plus concordances to BDTNS and to composite texts. Freely reusable under CDLI's open terms, with attribution to CDLI requested for substantial reuse.
- `iedc` — The Invisible East Digital Corpus (University of Oxford): about 1,300 documentary items from the medieval Islamicate East, such as the Bamiyan and Firuzkuh papers, Khotan documents and Bactrian economic documents. Its languages are Khotanese, New Persian, Middle Persian, Sogdian, Arabic, Judeo-Persian and Bactrian, with a few others. Some 480 items carry line-by-line folio transcriptions. The rest, including nearly all the Khotanese, are catalogue records held for their typed dates, located toponyms, editorial grades and shelfmarks. The corpus's English translations are not yet included. CC BY 4.0.
- `oracc` — The founding dream: Nabu's own tablets. Fetched as per-project zips over HTTP (the first non-git source; full attic/retention parity, TLS chain vendor-fixed) from a menu of 144 public projects. The **English translation layer** ships 8,911 `-en` sibling documents, so `show <tablet> --parallel` renders SAA letters like the Homers — transliteration beside the running English, line-aligned.
- `perseus-farsilit` — The Perseus Digital Library's canonical-farsiLit repository: the Divan of Hafez, about 495 ghazals in 32 alphabetical chapters, cited by chapter, poem, line and half-line, with an aligned English translation that can be read side by side. A German translation in the repository is not included. CC BY-SA 3.0 US.
- `shkz` — The trilingual inscription of Šābuhr I on the Kaʿba-ye Zartošt (ŠKZ), the Sasanian king's res gestae, in Shamsian and Berti's aligned dataset (Zenodo). The Middle Persian, Parthian and Greek versions are held as three documents sharing the same line citations, about fifty lines each, so any line can be read across all three; the Parthian is given in transcription with its transliteration beside it. It is the first real Parthian document on the shelf. The word-by-word alignment table in the deposit is not yet served. CC BY 4.0.
- `skjaervo-khotanese` — Prods Oktor Skjærvø's Khotanese Manuscripts from Chinese Turkestan in the British Library, in its revised 2014 online edition (Zenodo): about 2,360 manuscript records, each under its current shelfmark, with some 14,600 lines of transliterated Khotanese text. Skjærvø's English notes on each item are kept as apparatus beside the text. It is the text counterpart to the Khotanese documents catalogued in the Invisible East corpus. Upstream's own caveat is carried on every record: the file is a draft, not yet proofed and checked against the physical holdings. CC BY 4.0.

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

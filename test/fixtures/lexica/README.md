# Lexica fixtures (P11-4 — dictionary shelf)

Real upstream samples from **PerseusDL/lexica** (CLAUDE.md fixture rules;
plan owner-approved 2026-07-09, docs/backlog.md P11-4). Every kept element is
a byte-identical slice of the upstream file; the trims are documented below.

- **Retrieved:** 2026-07-09, via raw.githubusercontent.com **pinned at commit
  `b5e707bdda2d6c8e0bb6c29657454996b4fb04d7`** (master HEAD, 2026-05-05),
  exact upstream paths mirrored under `CTS_XML_TEI/perseus/pdllex/`.
- **License:** CC BY-SA 4.0. Repo `license.md` is the full BY-SA 4.0
  legalcode; repo README (verbatim): "Unless otherwise indicated, all
  contents of this repository are licensed under a Creative Commons
  Attribution-ShareAlike 4.0 International License. You must offer Perseus
  any modifications you make." Per-lexicon READMEs (verbatim): "This text may
  be freely distributed under a CC BY-SA 4.0 license, subject to the
  following restrictions: You credit Perseus, as follows, whenever you use
  the document: 'Text provided under a CC BY-SA license by Perseus Digital
  Library, http://www.perseus.tufts.edu, with funding from The National
  Endowment for the Humanities. Data accessed from
  https://github.com/PerseusDL/lexica/ [date of access].'"
- **Attribution:** Perseus Digital Library / Trustees of Tufts University.

## Files (3) — chosen to cover the parser's hard cases

| File | Lexicon | Kept entries | Why these |
|---|---|---|---|
| `grc/lsj/grc.lsj.perseus-eng13.xml` | LSJ (mu, upstream 12.3 MB) | μῆνις (`key="mh=nis"`, id n67485), μηνίσκος (`mhni/skos`, its file-order successor) | μῆνις cites **Il. 1.1** as `<bibl n="urn:cts:greekLit:tlg0012.tlg001.perseus-grc1:1:1">` — the citation-resolution anchor (note the *edition token differs* from our catalog's perseus-grc2: resolution must match the work prefix) — alongside honestly URN-less bibls (AP 9.168, Alcaeus fr.); μηνίσκος is the small plain entry |
| `grc/lsj/grc.lsj.perseus-eng12.xml` | LSJ (lambda, upstream 6.7 MB) | λόγος (`lo/gos`), λογοσυλλεκτάδης (`logosullekta/dhs`) | λόγος is the flagship polysemous entry (~300 KB pretty-printed, sense tree nine levels of `n="A".."IX"` deep) — the output-bounds stress case; its neighbor is the two-line contrast |
| `lat/ls/lat.ls.perseus-eng2.xml` | Lewis & Short (upstream 77 MB, all letters in one file; eng2 = Unicode Greek variant per upstream README) | a2 (`key="a2"` homograph), Aaron (id n3), officium (id n32391), virtus (id n51108) | officium cites **Cic. Off.** as `<bibl n="urn:cts:latinLit:phi0474.phi055.perseus-lat1:1:2:4">` (+ `:1:9:28`) and is a lemma of the PROIEL cic-off fixture → lemma-gloss integration anchor; virtus cites Cic. Off. 1.15.46 and carries a malformed upstream urn (`…perseus-lat1:Orat::2:27:120`) for the robustness path; Aaron cites the Vulgate via a **greekLit** urn (cross-namespace edge); a2 is the minimal homograph-key entry |

## Trim documentation

Each fixture = upstream `teiHeader` **whole** + the containing
`div0[@type="alphabetic letter"]` opening tag + `<head>` + the kept
`entryFree` elements (byte-identical, natural indentation) + real closing
tags, all other entries removed:

- `grc.lsj.perseus-eng13.xml`: teiHeader + `div0 n="*m"`; kept 2 of the mu
  entries (upstream bytes ~7.85 MB into the file).
- `grc.lsj.perseus-eng12.xml`: teiHeader + `div0 n="*l"`; kept 2 of the
  lambda entries (~4.9 MB in).
- `lat.ls.perseus-eng2.xml`: teiHeader (incl. its `<availability>` CC BY-SA
  statement) + three of the letter div0s — `A` (kept a2 + Aaron; the giant
  letter-essay entry `A1` removed), `O` (kept officium), `V` (kept virtus) —
  each with its real `<div0…>`/`<head>`/`</div0>` frame (div0 openings sit at
  upstream bytes 46,894,792 and 74,675,963); `<pb>`/`<cb>` milestones inside
  kept material retained as-is.

## Upstream structure notes (verified at retrieval)

- TEI **P4** (`<TEI.2>` DOCTYPE + Perseus `PersDict` DTD — unfetchable
  offline, libxml2 Reader streams past it; same story as the P9-2 Perseus P4
  texts), UTF-8.
- Body: `div0[@type="alphabetic letter"]` per letter → `entryFree[@id @key
  @type]` → `orth`, nested `sense[@n @level]`, `tr` glosses, `etym`,
  `gramGrp/gram`, `cit`/`quote`, `xr/ref`, `hi`, `pb`/`cb` milestones.
- **LSJ Greek is betacode** (keys, orth, quotes: `key="mh=nis"`, `<quote
  lang="greek">mh/nios</quote>`); upstream already stripped vowel-length
  marks (`^`/`_`) from `@key` (2009 revision note). L&S keys are plain Latin
  with homograph digits (`a2`, `virtus` has none); L&S eng2 `foreign
  lang="greek"` content is Unicode.
- Citations: `<bibl>` with optional `@n`. When present, `@n` is usually a
  CTS urn (work-level `tlg0291.tlg001:23:6`, edition-level
  `phi0474.phi055.perseus-lat1:1:2:4`, or bare work `phi1236.phi001`;
  citation parts are **colon**-separated) — but non-CTS values exist
  (`n="Dig. 33.6.9"`, Trismegistos URLs in other letters) and some urns are
  malformed (`…:Orat::2:27:120` in virtus) or contextually wrong upstream
  ("ib."-expansion artifacts). Human-readable citation lives in the
  `<author>`/`<title>`/`<biblScope>` children.

# DDbDP + DCLP (Papyri.info) fixtures

Real, untrimmed EpiDoc documents from the Duke Databank of Documentary Papyri —
and, since P104-3, the Digital Corpus of Literary Papyri — via the Papyri.info
`idp.data` repo (CLAUDE.md fixture rules). All files are small and kept
**whole** — no trimming.

- **Layout:** mirrors upstream's **post-switchover** layout (see the Papyri
  adapter header): `DDbDP/<HGV-thousand>/<HGV>.xml` (curated, text-centric),
  `Historical/<collection>/(<volume>/)?<number>.xml` (archived,
  edition-centric) and `DCLP/<dclp-thousand>/<dclp>.xml`.
- **Retrieved:** re-cut 2026-10-14 from upstream commit
  `8f7ed7085c4ed9055c239800286d3a6c3bc2a79f` (master, 2026-10-13), extracted
  byte-verbatim from the git objects already fetched into the box's canonical
  clone; raw base `https://raw.githubusercontent.com/papyri/idp.data/master/`.
- **Original acquisition** (the old-layout copies, now under
  `pre-switchover/`): 2026-07-03 (DDbDP, raw GET from master) and 2026-09-26
  (DCLP, from the canonical clone); byte-identical to upstream commit
  `0eec6593ebfb2c0e2e9ae0c1a7988fb83538e9a7`.

## Files (whole)

| Path | Bytes | Identity idno | What it pins |
|---|---|---|---|
| `DDbDP/8/8875.xml` | 5,542 | ddb-hybrid `bgu;1;100` (HGV/TM 8875) | curated text; 12 lines |
| `DDbDP/8/8877.xml` | 7,592 | ddb-hybrid `bgu;1;102` (HGV/TM 8877) | curated text; app/lem, gap, hands |
| `DDbDP/78/78573.xml` | 2,159 | ddb-hybrid `c.epist.lat;;10` | curated **stub** ("This text has not been added to papyri.info yet." over an empty `<ab/>`, edition `grc`) sharing its hybrid with the Historical text: must be skipped at discover |
| `Historical/c.epist.lat/10.xml` | 8,127 | ddb-hybrid `c.epist.lat;;10` (HGV/TM 78573) | Latin text living ONLY in Historical/ (the fallback root); empty volume segment; r/v textparts |
| `Historical/bgu/1/100.xml` | 3,871 | ddb-hybrid `bgu;1;100` | historical **stub** ("This historical edition has not been added…") of a curated text: must be skipped |
| `DCLP/62/62952.xml` | 8,878 | dclp `62952` | Vergil, Aeneid I.1–3 on an ostracon (O.Claud. 1 190); duplicate `<lb n="1"/>` engages the P5-1 implicit restart block (`:b2:3`) |
| `DCLP/64/64388.xml` | 7,264 | dclp `64388` | P.Harris 1 98 medical recipe; two textpart divs with per-part line restarts; expan/ex + num |
| `DCLP/805/805566.xml` | 5,747 | dclp `805566` | Praxidicae curse text; the `tm;;`-hybrid file shape; `break="no"` line wraps |
| `DCLP/316/316777.xml` | 4,456 | dclp `316777` (skipped) | a metadata-only catalog stub — SELF-CLOSED edition div: pins the DCLP discover skip |

### Header mining (added 2026-10-18)

Copied byte-verbatim from the box's canonical clone (`canonical/papyri-ddbdp/`,
upstream commit `91611a190d29b584ca2df01712888ac843e8ef89`), whole:

| Path | Bytes | What it pins |
|---|---|---|
| `DDbDP/2/2416.xml` | 3,446 | ddb-hybrid `p.ryl;4;560` (HGV/TM 2416) — the text the HGV record below joins to by its HGV idno |
| `HGV_meta_EpiDoc/HGV3/2416.xml` | 5,859 | the HGV metadata record: leading keyword "Brief (privat)" then "Apollonios an Zenon" (sender→addressee persons), commentary "Gehört zum Zenon - Archiv." (archive membership), one `<date type="mentioned">` (Z. 5, 4 Oct 256 BCE — never the document's date) |
| `HGV_meta_EpiDoc/HGV9/8875.xml` | 5,115 | HGV record of `bgu;1;100` — carries none of the mined extras (adds nothing) |
| `HGV_meta_EpiDoc/HGV9/8877.xml` | 4,964 | HGV record of `bgu;1;102` — settlement (Soknopaiu Nesos) + nome (Arsinoites) provenance refs |

The DCLP header mining (origDate/origPlace/provenance/keywords) reads the
three text-bearing DCLP files already listed above.

### `pre-switchover/` — the layout-migration proof

The same six text documents as cut from the old layout, kept byte-identical
to upstream commit `0eec6593` (`DDB_EpiDoc_XML/bgu/bgu.1/bgu.1.100.xml`,
`…/bgu.1.102.xml`, `DDB_EpiDoc_XML/c.epist.lat/c.epist.lat.10.xml`,
`DCLP/63/62952.xml`, `DCLP/65/64388.xml`, `DCLP/806/805566.xml`). Every one
was rewritten upstream during the switchover (no blob survived), yet each
parses to the identical document urn AND identical passages from either
copy — `papyri_test.rb` asserts it. The adapter does not walk
`DDB_EpiDoc_XML/` any more (asserted too).

## License (recorded exactly)

- **Repo:** CC BY 3.0.
- **Per-document `<availability>`** (DDbDP / Historical):
  > © Duke Databank of Documentary Papyri. This work is licensed under a
  > Creative Commons Attribution 3.0 License.
- DCLP files: "© Digital Corpus of Literary Papyri. This work is licensed
  under a Creative Commons Attribution 3.0 License." — same class.
- license_class `attribution`.

## Structure notes (for the DDbDP parser, P3-6)

- **NOT CapiTainS:** no `__cts__.xml`, no `refsDecl`, no CTS URNs. A separate
  parser family, not `EpidocParser` reuse.
- **Identity** via `<idno>` elements — types seen: `filename`,
  `ddb-perseus-style`, `ddb-hybrid`, `HGV`, `TM` (`dclp`, `dclp-hybrid`,
  `LDAB` in DCLP). URN minting uses the `ddb-hybrid` value →
  `urn:nabu:ddbdp:<ddb-hybrid>` (frozen once used). Since the switchover the
  `filename` idno is path-shaped (`8875` in DDbDP/, `c.epist.lat/10` in
  Historical/) and is NOT an identity input.
- **Citation** via `<lb n="…"/>` line-begin markers inside `<ab>`.
- Post-switchover files also open `<body>` with a `<head><ref …><title>`
  edition list before the edition div, outside the parsed text.
- Heavy documentary/Leiden markup to expect: `app`/`lem`/`rdg`,
  `choice`/`reg`/`orig`, `subst`/`add`/`del`, `gap` (+quantity), `supplied`,
  `unclear`, `expan`/`ex`, `handShift`.
- **DCLP identity**: `<idno type="dclp">` (numeric; = TM = filename =
  papyri.info/dclp/<n>) mints `urn:nabu:dclp:<n>`. NOT the `dclp-hybrid`,
  which is non-unique upstream (TM 60467 and TM 61136 both carry
  `p.hal;;5`).

### Translations (added 2026-10-19)

Copied byte-verbatim and whole from the box's canonical clone
(`canonical/papyri-ddbdp/`, upstream commit
`91611a190d29b584ca2df01712888ac843e8ef89`). They pin the translation
siblings (`translations: true`): the walk, the edition resolution, the
skip census and the line-milestone passages.

| Path | Bytes | What it pins |
|---|---|---|
| `Translations/8/8875-1.xml` | 3,547 | German HGV translation of `bgu;1;100`: line milestones 1/2/6/9/10, `app`/`lem`, `term` |
| `Translations/8/8875-2.xml` | 3,428 | English translation of the same edition — several translations per edition |
| `Translations/8/8877-1.xml` | 3,956 | German translation of `bgu;1;102`: inline `<lb/>`, a lemma-wrapped term |
| `Translations/8/8877-2.xml` | 3,776 | English translation of `bgu;1;102` |
| `Translations/2/2416-1.xml` | 2,966 | ddb-hybrid idno `p.ryl;4;560 sb;5;7643` (two hybrids, space-separated); `r`/`v` textparts |
| `Translations/13/13581-1.xml` | 1,935 | an APIS-authority translation with NO hybrid: reaches `p.tebt;2;484v` by its HGV number; one block `<ab>` |
| `Translations/88/88604-1.xml` | 2,500 | misspelt `xml:lang="fe"` over French prose; its edition `o.krok;1;15` is not in the catalog (minted under its own hybrid) |
| `Translations/88/o.krok.1.15-1.xml` | 2,524 | the misnamed twin of 88604-1.xml — skipped by the naming rule |
| `DDbDP/13/13581.xml` | 3,865 | the `p.tebt;2;484v` edition (HGV 13581) the APIS translation above resolves to |
| `APIS/berkeley/xml/berkeley.apis.629.xml` | 4,345 | the APIS record of 13581-1: its translation yields to Translations/, its summary + keywords ride the translation |
| `APIS/berkeley/xml/berkeley.apis.253.xml` | 5,259 | an APIS-only translation (Sophocles, *Inachus*): no `xml:lang` on the div (langUsage → en), resolves by `dclp` idno 62767 |
| `APIS/berkeley/xml/berkeley.apis.9834.xml` | 2,814 | an APIS record naming no text (apisid/controlNo only) — skipped, censused |

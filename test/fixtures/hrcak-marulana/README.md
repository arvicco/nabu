# hrcak-marulana fixtures

Real samples of *Colloquia Maruliana* (the annual journal of Marulić
studies, Split Literary Circle — Marulianum) as served by Hrčak, the
Croatian journal portal (https://hrcak.srce.hr/colloquia-maruliana, OAI-PMH
base https://hrcak.srce.hr/oai/, set `journal:43`), retrieved 2026-11-25,
laid out as `canonical/hrcak-marulana/` holds them.

**License.** Every record's oai_dc `dc:rights` states, verbatim: "The
annual journal Colloquia Maruliana is published in open access. Its entire
content is freely available to users. Users may copy and distribute the
material, as well as modify, adapt, and build upon it, in accordance with
the terms of the Creative Commons Attribution 4.0 International License (CC
BY 4.0). Authors retain unrestricted copyright to their published works."
A record may carry its own `oaire:licenseCondition`, which governs it: record
277980 is CC BY-NC 4.0 (its PDF is redistributed here non-commercially
under that licence); record 277999 is rightsstatements.org InC — only its
metadata record is checked in, never its PDF. Credit: the articles'
authors, Colloquia Maruliana (Književni krug Split — Marulianum), via Hrčak
(Srce).

## Grains upstream serves (census 2026-11-25)

- **journal** — the OAI set `journal:43`; the portal page
  https://hrcak.srce.hr/colloquia-maruliana. Not a document.
- **volume / issue** — portal pages `https://hrcak.srce.hr/broj/<id>`; the
  OAI records carry only `oaire:citationVolume` / `citationIssue`. Not
  fetched (nothing beyond the records).
- **article record** — OAI-PMH `oai_openaire`, `oai_dc`, `mods` (all three
  advertised by ListMetadataFormats) and the landing page
  `https://hrcak.srce.hr/<id>`. **The document**: one per record, Hrčak's
  permanent article id. 681 records advertised (`completeListSize="681"`);
  the adapter holds oai_openaire + oai_dc, not mods or the landing page.
- **full-text PDF** — `https://hrcak.srce.hr/file/<id>`, 772 files (591
  records with one, 89 with two, 1 with three). The passage source: one
  passage per non-blank PDF page. A second/third PDF is the article in
  another language or its summary.
- **abstract** — `dc:description` per language (427 records). Document
  metadata, never a passage.

Rejected BY RULE: records whose own licence condition grants nothing — 37
carry rightsstatements.org InC (vols. 5, 11, 31–33); pinned specimen:
`records/277999.*`. 681 advertised = 644 documents + 37 skipped by rule.

## Files

- `records/<id>.oai_openaire.xml`, `records/<id>.oai_dc.xml` — each record's
  `<record>` element from the ListRecords responses
  (`https://hrcak.srce.hr/oai/?verb=ListRecords&metadataPrefix=<prefix>&set=journal:43`
  and its resumptionToken pages), re-rooted as a standalone document exactly
  as the fetch writes it; record content verbatim:
  - `9874` — Venantius Fortunatus, *Ad Felicem episcopum De pascha* (vol. 1,
    1992, type "other", Latin, one PDF of 3 pages): a Latin text edition;
    the PDF is a scan with an Acrobat Paper Capture OCR layer.
  - `8030` — Ivo Frangeš, "Utemeljenost metaforičkoga određenja" (vol. 11,
    2002, hrv + eng, TWO PDFs: the 8-page Croatian article and its 1-page
    English summary): the multi-file case and the PageMaker slot-font text
    layer (MaruliÊ, πto) the adapter re-decodes.
  - `23933` — Mirko Tomasović's review of the Hungarian Marulić translation
    (vol. 17, 2008, book review, hrv, 2 pages): a clean Unicode layer (with
    upstream's own "L™kös" glyph loss), creator affiliation.
  - `277980` — the Croatian culture minister's greeting (vol. 31, 2022,
    "journal article", CC BY-NC 4.0 licence condition): the nc override.
  - `277999` — vol. 31, rightsstatements.org InC: skipped by rule (no PDF).
  - `9875` — Marulić, *Od uskarsa Isusova* (vol. 1): its PDF (file 15233) is
    deliberately NOT checked in — the fetch-hole case (unrecognized).
- `files/<file-id>.pdf` — the five PDFs, WHOLE and byte-verbatim, from
  `https://hrcak.srce.hr/file/<file-id>` (15232, 12183, 12184, 37682, 402550).
- `textlayers/<file-id>.txt` — the RECORDED mutool 1.28 text layer of each
  PDF (`mutool draw -F text -o <txt> <pdf>`), so the suite never depends on
  mutool; a guarded live test pins agreement.
- `textlayers/4696-p1.txt` — the recorded mutool 1.28 layer of page 1 ONLY
  of `https://hrcak.srce.hr/file/4696` (vol. 14, 2005, Lujo Margetić,
  "Marulićeva oporuka"; journal CC BY 4.0, no record licence condition):
  a MIXED PDF — a Unicode body under a slot-font heading and footnotes —
  for the in-word repair test. The PDF itself is not checked in.
- `oai/<prefix>-1.xml`, `oai/<prefix>-2.xml` — the fetch test's harvest:
  the FIRST ListRecords response of each format trimmed to 2 of its 100
  records (641, 8030; its resumptionToken kept) and the LAST response
  trimmed to 2 of its 81 (277980, 277999; no token). Record content
  verbatim; the time-of-day in `responseDate` / `expirationDate` is zeroed
  (dates kept).

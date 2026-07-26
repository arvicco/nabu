# Elephantine fixtures

Real files from the Berlin ERC project "Localizing 4000 Years of Cultural
History" database (<https://elephantine.smb.museum>) — the island's
multilingual documentary corpus. Retrieved 2026-07-26. The upstream TEI
export is frozen (every sampled file Last-Modified 2022-11-24, the project
ended 2022).

## TEI records (whole, byte-for-byte uncut)

One file per object at
`https://elephantine.smb.museum/xml/elephantine_erc_db_<ID6>.tei.xml`
(ID6 = the object id ZERO-PADDED to 6 digits; the unpadded URL 404s).
Each is TEI P5 against the project's own DTD (`tei_erc_elephantine.dtd`)
— NOT EpiDoc — and carries ~25 KB of identical `<encodingDesc>` taxonomy
boilerplate; the files are checked in WHOLE (28–37 KB each) so the
`catRef` genre resolution stays testable against the real taxonomy.

- `elephantine_erc_db_002881.tei.xml` — Ostr. Berlin P. 10774, Greek
  (`grc-Grek`) marriage contract. The 4-digit object id 2881: the
  zero-padding exemplar (root `xml:id="elephantine_erc_db_002881"`).
  Whitespace-only first `<ab>`, in-text `<date notBefore="-246-02-12">`,
  `<lb break="no">`, persName spanning a line break, structured
  `origDate` bounds (`notBefore-custom="-246"`).
- `elephantine_erc_db_307762.tei.xml` — Pap. Brooklyn Museum 47.218.89,
  Imperial Aramaic (`arc-Armi`) in Hebrew script: the Document of
  Wifehood of Ananiah and Tamet (TAD B3.3). RTL `<lb rend="right-to-left">`,
  `vso 1` line numbers (space in @n), damage/supplied/del/add/`mod
  type="subst"`/choice(sic|corr)/handShift, persName@ref, Trismegistos
  link (quick=89454), title type="original" in Aramaic.
- `elephantine_erc_db_100007.tei.xml` — Pap. Berlin P. 23572, Demotic
  (`egy-x-demp-Egyd-x-Egydmd`). Two `<ab>` (recto/verso pb R|V), EMPTY
  `<lb n=""/>` label lines ("new text"/"old text"), `x+1`/`x+7ff.` line
  numbers, `rs type="title"`, damage@degree, inline editorial `<note>`.
- `elephantine_erc_db_100117.tei.xml` — Ostr. Berlin P. 12957, Demotic
  (`egy-x-demr-Egyd-x-Egydlt`) name list in Egyptological transliteration
  (ꜣ, ı͗). surname/surplus/self-closed `<unclear/>`/literal `///` damage
  notation/gap; translation `<ab xml:lang=" en">` (LEADING space) with
  `<pb n=""/>`.
- `elephantine_erc_db_100141.tei.xml` — Ostr. Berlin P. 12229, "ostracon
  with illegible text": the ALL-LACUNAE exemplar (the site's text flag is
  set, the edition is `<damage><unclear/></damage>` only — zero readable
  characters) AND the trailing-space taxonomy id
  (`mainLang="egy-x-dempr-Egyd-x-Egydmdlt "`, double space inside the ab
  xml:lang pair).
- `elephantine_erc_db_100009.tei.xml` — Pap. Berlin P. 23610: the
  CATALOG-ONLY exemplar — self-closed `<div type="edition"/>` and
  `<div type="translation"/>`, no text flag in the listing.
- `elephantine_erc_db_places.tei.xml` — one of the four authority files
  the sync fetches beside the records (places, modern_persons,
  literature, ancient_persons — same /xml/ dir); kept whole (58 KB) as
  the discovery skip-by-rule exemplar (an authority file is not a record)
  and the cross-file `@ref` fragment target.

Every record's `<licence target="http://creativecommons.org/licenses/by-sa/3.0/">`
reads "Licence for this TEI document: Creative Commons, Attribution-ShareAlike
3.0 Unported (CC BY-SA 3.0)" — zero deviations across the 2026-07-26 census's
76 sampled files. The site legal notice claims CC BY-NC-SA 3.0 DE for all site
text — the recorded discrepancy; the per-file grant governs (D46-a precedent,
owner pre-wire ruling flagged D47-d).

## Listing pages

The object manifest is ONE session-stateful POST
(`POST https://elephantine.smb.museum/objects/index.php`, body
`showresults=15000`) returning ~10.5 MB of HTML — "10744 Results" header,
10,744 unique `object.php?o=<id>` links, a `texts/view.php?t=<id>` icon on
the 5,223 transcription-flagged rows (all three counts re-verified
2026-07-26). Too big to check in, so:

- `objects-listing-marriage.html` — a REAL small listing: the same POST
  with `searchtext=marriage&showresults=15000` (23 Results header, 23
  rows, 15 text-flagged; includes objects 2881 and 307762 above). Kept
  byte-for-byte whole: the happy-path manifest fixture whose row count
  matches its own header.
- `objects-listing-truncated.html` — a documented TRIM of the marriage
  page: the 15 rows after the first 8 spliced out, header untouched
  ("23 Results" over 8 rows) — exactly the shape a stale session filter
  would produce, for the session-truncation defense test. Trim only;
  nothing was hand-written.

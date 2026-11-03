# Evans-TCP fixtures

Real upstream samples from the Text Creation Partnership's Evans Box
folder (`https://app.box.com/s/zj7pzfokxde4glrhebxsavbbxzyr3ogz` — the
TCP-readme's own Box mirror of its Evans bulk files, uniformly CC0),
retrieved 2026-11-03 via the per-file `box_v2_download_shared_file`
endpoint: `P4_XML_TCP/N3.zip` and `P4_XML_TCP/unedited.zip` whole, and the
`P5_XML_OXF/N3.zip` / `P3_SGML_TCP/N3.zip` twins for the rejected-grain
specimens. Every census claim below was taken on the full corpus the same
day (all five P4 zips, 5,012 members, parsed).

## Upstream's delivery grains

| grain | where | taken? |
|---|---|---|
| **P4 XML text** — one `<TCPID>.p4.xml` per text, flat inside each zip | `P4_XML_TCP/N0..N3.zip` (released, 4,864) + `unedited.zip` (148) | **accepted — the document** |
| Oxford P5 XML — the same texts re-encoded (`<TCPID>.p5.xml`) | `P5_XML_OXF/N0..N3.zip` | rejected: a derivative encoding of a held text; never walked |
| P3 SGML — the keyers' original files (`<TCPID>.sgm`) | `P3_SGML_TCP/N0..N3.zip` + `unedited.zip` | rejected: the pre-conversion encoding of a held text; never walked |
| catalogue sidecars — `evnsdat*.sgm`, `Evans_select*.mtxt` (MARC), char maps, css, readme | the share root | rejected: metadata about the texts, not texts; never fetched |
| `eebo2prf.xml.dtd` (the P4 schema), `evans_pub_dates.txt` (the TCP's 4,977-id roster) | the share root | landed beside `texts/` as sidecars, never documents |

The class of a P4 zip is its name: `unedited.zip` is the unedited class
(texts the TCP keyed but never formally released), every other zip is
released. Reconciliation (2026-11-03): released 4,864 + unedited 148 =
5,012 accepted; `evans_pub_dates.txt` names 4,977 = the 4,864 released +
113 unedited, its residue the 35 ids of `evnsdat_unfinished.sgm`. The
list's `PUBDATE` is the TCP's own release year (2004–2009), never a date
of the text.

## texts/ — three real P4 texts + two rejected-grain specimens

| path | what | why |
|---|---|---|
| `texts/released/N3/N31062.p4.xml` | Jupiter Hammon, *An evening thought. Salvation by Christ, with penetential cries* (broadside, imprint "1760?]"), whole file, 8 KB | the pinned snippet ("SALVATION comes by Jesus Christ alone,"); verse `<L>` grain; the `?`-uncertain imprint (raw-only dating); LCSH incl. the genre heading "Poems -- 1760." |
| `texts/released/N3/N33557.p4.xml` | *Sentence of death for high treason* (Frederick, Md., 1781), whole file, 7.6 KB | the conjectural imprint "[Frederick, Md.? :" → `imprint_place_conjecture`; "Trials (Treason) -- …" → legal/court |
| `texts/unedited/unedited/N00552.p4.xml` | John Phillips, *A paraphrastical exposition on a letter from a gentleman in Philadelphia* (1693), whole file, 13.5 KB | the unedited class; the American imprint statement "in the year 1693." (the later-print mold); acrostic verse |
| `texts/released/N3/N31062.p5.xml` | the Oxford P5 copy of N31062 — real member of `P5_XML_OXF/N3.zip` | rejected-grain specimen: discovery skips it by rule (counted, named) |
| `texts/released/N3/N31062.sgm` | the P3 SGML copy of N31062 — real member of `P3_SGML_TCP/N3.zip` | rejected-grain specimen: discovery skips it by rule (counted, named) |

Every P4 file: `<ETS>` P4 schema, `<IDG ID>` equal to the filename stem
(0 mismatches ×5,012), one LANGUSAGE entry (`eng` on 5,011 of 5,012 — the
one `pau`, N14218, is a cataloguing slip over an English novel),
AVAILABILITY carrying the CC0 1.0 waiver (×5,012).

## fetch/ — the acquisition fixtures

- `root.html`, `p4.html` — the Box shared-folder listing pages, TRIMMED
  real: the server-side `Box.postStreamData` JSON is the real payload
  (retrieved 2026-11-03) with the item arrays pruned to the fixture subset,
  each item reduced to the fields the fetch reads, and the zip `itemSize`
  values set to the fixture zips' sizes; page chrome reduced to a shell.
  Folder/file ids are upstream's real ids. The root listing keeps the P3/P5
  folders and two catalogue sidecars — the rejected grains the fetch must
  never request.
- `N3.zip`, `unedited.zip` — subset re-zips of the REAL members above,
  preserving the real flat layout (members at the zip root).
- `eebo2prf.xml.dtd` — the P4 schema, WHOLE real file (byte-identical to
  the EEBO and ECCO copies).
- `evans_pub_dates.txt` — the TCP id roster, trimmed real: first 6 rows +
  the three fixture texts' rows (CRLF as served).

# ECCO-TCP fixtures

Real upstream samples from the Text Creation Partnership's ECCO Box
folder (`https://app.box.com/s/6jbuf443i145f97c4t56z3garu3u2j09` — the
TCP-readme's own Box mirror of its ECCO bulk files, uniformly CC0),
retrieved 2026-11-02/03 via the per-file `box_v2_download_shared_file`
endpoint: `p4/ecco_p4_released.zip` and `p4/ecco_p4_unedited.zip` whole;
the rejected-grain specimens by HTTP Range from `p5/ecco_p5_released.zip`
and `p3/ecco_p3_released.zip` (central directory → the one member). Every
census claim below was taken on all 3,101 P4 members, parsed 2026-11-03.

## Upstream's delivery grains

| grain | where | taken? |
|---|---|---|
| **P4 XML text** — one `<TCPID>.p4.xml` per text (`K041165.000.p4.xml`), flat inside each zip | `p4/ecco_p4_released.zip` (2,473) + `p4/ecco_p4_unedited.zip` (628) | **accepted — the document** |
| Oxford P5 XML — the released texts re-encoded (`.p5.xml`) | `p5/ecco_p5_released.zip` | rejected: a derivative encoding of a held text; never walked |
| P3 SGML — the keyers' original files (`.sgm`) | `p3/ecco_p3_released.zip` + `ecco_p3_unedited.zip` | rejected: the pre-conversion encoding of a held text; never walked |
| catalogue sidecars — `ecco*dat*.sgm`, `ecco_select*.mtxt`/`.mrc` (MARC), char maps, css, readme | the share root | rejected: metadata about the texts, not texts; never fetched |
| `eebo2prf.xml.dtd` (the P4 schema) | the share root | landed beside `texts/` as a sidecar, never a document |

The class of a P4 zip is its name (`…unedited.zip` → unedited: texts the
TCP keyed but "never even minimally edited, much less formally
released"). Reconciliation (2026-11-03): released 2,473 + unedited 628 =
3,101 accepted, 0 id overlap — the TCP's own "2,473 released" is the
released zip's member count.

## texts/ — three real P4 texts + two rejected-grain specimens

| path | what | why |
|---|---|---|
| `texts/released/ecco_p4_released/K041165.000.p4.xml` | Thomas Gray, *An ode on a distant prospect of Eton College* (London, 1747), whole file, 9.4 KB | the pinned snippets ("YE distant Spires, ye antique Towers;" … "'Tis Folly to be wise."); verse grain; ContentSet ECLL → literary |
| `texts/released/ecco_p4_released/K021105.000.p4.xml` | *The report of the physicians and surgeons, commanded to assist at the dissecting the body of His late Majesty* (London, 1702), whole file, 9.5 KB | prose grain; ContentSet ECMS → scholarly |
| `texts/unedited/ecco_p4_unedited/K049384.000.p4.xml` | Tobias Smollett, *The tears of Scotland* (imprint "[Edinburgh?," "1746?]"), whole file, 7.2 KB | the unedited class; the `?`-uncertain year (raw-only) and the conjectural place |
| `texts/released/ecco_p4_released/K041165.000.p5.xml` | the Oxford P5 copy of the Gray ode — real member of `p5/ecco_p5_released.zip` | rejected-grain specimen: discovery skips it by rule (counted, named) |
| `texts/released/ecco_p4_released/K041165.000.sgm` | the P3 SGML copy of the Gray ode — real member of `p3/ecco_p3_released.zip` | rejected-grain specimen: discovery skips it by rule (counted, named) |

Every P4 file: `<ETS>` P4 schema, `<IDG ID>` equal to the filename stem
(0 mismatches ×3,101), one LANGUSAGE entry (`eng` on 3,099; one `fre`,
one `wel`), typed header IDNOs incl. `ESTC` and the Gale `ContentSet`
module, AVAILABILITY carrying the CC0 1.0 waiver (×3,101).

## fetch/ — the acquisition fixtures

- `root.html`, `p4.html` — the Box shared-folder listing pages, TRIMMED
  real: the server-side `Box.postStreamData` JSON is the real payload
  (retrieved 2026-11-03) with the item arrays pruned to the fixture subset,
  each item reduced to the fields the fetch reads, and the zip `itemSize`
  values set to the fixture zips' sizes; page chrome reduced to a shell.
  Folder/file ids are upstream's real ids. The root listing keeps the
  p3/p5 folders and two catalogue sidecars — the rejected grains the fetch
  must never request.
- `ecco_p4_released.zip`, `ecco_p4_unedited.zip` — subset re-zips of the
  REAL members above, preserving the real flat layout.
- `eebo2prf.xml.dtd` — the P4 schema, WHOLE real file (byte-identical to
  the EEBO and Evans copies).

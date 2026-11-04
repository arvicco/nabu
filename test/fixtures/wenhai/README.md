# wenhai fixture

Retrieved 2026-11-04 from Zenodo record 22817676 — *The Digital Wenhai:
A Unicode-Compliant Dataset of the Backbone of Tangut Linguistics and
Philology*, Version 1.1: Phonology (published 2026-09-17; Mathieu
Beaudouin, University of Cambridge; version DOI 10.5281/zenodo.22817676,
concept DOI 10.5281/zenodo.22256047; the record's `is_last` flag was
true at retrieval). Each file was fetched from
`https://zenodo.org/api/records/22817676/files/<name>/content`; the
md5 of each full download matched the record's own checksum.

The tree mirrors the adapter's fetch layout: one FileFetch per taken
file, each into its own subdirectory (FileFetch dooms any sibling it did
not serve, so files never share a directory — the fsv-lexica layout).

| fixture path | upstream file | full bytes | md5 (= record) | sha256 (the adapter's pin) |
|---|---|---|---|---|
| `01_wenhai/01_wenhai.csv` | `01_wenhai.csv` | 240,458 | 3b48ce8ae5b7cdf274eb223cd7475dae | 1f6741339bc2a6c83368a99747d3ba9d553ec69f5462d2d073477282d4dd204e |
| `02b_fanqie_groups/02b_fanqie_groups.csv` | `02b_fanqie_groups.csv` | 90,042 | c9c086cc935b7ba1cc9da9662e5fda63 | 8e0a3699b65dbb8fbab7561d0c64d5528064aaba085eaed504a7c71fa8487b01 |
| `README/README.md` | `README.md` | 37,266 | edd2dbf7101d118646a6708125812909 | 8c9556279775a2296e759db8ef42725b0f49f6b532487ce20becbdcb9f483adb |
| `LICENSE/LICENSE.txt` | `LICENSE.txt` | 2,391 | 15ba4c765b392a60fda64e752d382b59 | d839a7ba2069a397a7c0af9781ccfb20ef611215e4b50089b1907abcdfa3c5b9 |

`README/README.md` and `LICENSE/LICENSE.txt` are byte-identical copies
(they are the rejected-grain specimens). The two CSVs are cut (below).
Both CSVs are UTF-8 with a leading BOM and CRLF line ends; the cut keeps
both.

## Delivery grains (every file the deposit serves)

| grain | file(s) | taken? |
|---|---|---|
| Wenhai record (one row per source position) | `01_wenhai.csv` (3,085 rows, 15 columns) | TAKEN — one dictionary document, one entry per row |
| normalized fanqie statement (one row per statement, with the positions it governs) | `02b_fanqie_groups.csv` (1,507 rows) | TAKEN as the join table: each entry gets the statement that governs it (upper and lower speller) |
| documentation / licence | `README.md`, `LICENSE.txt` | fetched (licence of record), skipped by rule (pinned here) |
| spreadsheet twins | `01_wenhai.xlsx`, `02_fanqie.xlsx` | not fetched — the same tables as the CSVs; upstream names the CSVs as the preservation format |
| derived graph tables | `02c_fanqie_chains.csv`, `02d_fanqie_members.csv`, `02e_fanqie_links.csv`, `02f_fanqie_initial_cross.csv`, `02g_fanqie_rhyme_cross.csv`, `02h_fanqie_unresolved.csv` | not fetched — chain-grain products computed from 01 + 02b (upstream's script rebuilds them); every record's chain IDs already ride its 01 row |
| method notes | `02a_fanqie_notes.csv` | not fetched — a summary of README §8–§10 |
| software / citation | `build_fanqie_chains.py` (MIT), `CITATION.cff`, `CITATION.bib` | not fetched |

## Columns (01_wenhai.csv, README §5.2)

`Cycle, She, Subcycle, Grade, ToneRhyme, RhymeName, WenhaiPos, Tangut,
LiFanwen, Fanqie, InitialTYYJ, InitialClassID, RhymeClassID, GHC, MB`.
All are mined: `WenhaiPos` is the entry id, `Tangut` the headword, the
rest ride the entry body and annotations. No column is rejected. There
is no gloss column: v1.1 is the phonology release; the Wenhai's
definitions and character analyses are not in the deposit.

02b columns: `FanqieBase, Fanqie, Upper, Lower, Announced, Represented,
Governed positions, Members`.

## The cut

`01_wenhai/01_wenhai.csv` keeps the header and 22 real rows
(byte-identical lines, upstream order), chosen for their shapes:

- 05.131–05.142 — the first statement: fanqie 𗈽𗒿𘈖𗥃 written at 05.131,
  governing the three positions after it (blank `Fanqie` cells);
- 06.272, 07.111–07.113 — a statement with both spellers unreadable
  (□□𘈖𗥃): no chain IDs, one of upstream's unresolved sets;
- 16.262–16.271 — the pronunciation-split node `𘅇a` (README §6.2);
- 17.151*, 17.151a, 17.152a/b/c — suffixed variant positions (README
  §6.1), governed by the statement at 17.142 under their unsuffixed
  positions; 𗀛 heads both 17.152a and 17.152b (two Li Fanwen numbers);
- 45.2 ~ 47.1 — the one position written as a span (rhyme 𘟅, no fanqie,
  no chain IDs);
- 79.151 — `𗾌(𗣀)`, the one head given with a bracketed second form;
- 83.251 and 84.232 — 𗭹, the head restored in v1.1, one node at two
  positions with two fanqie;
- M09.111 — a mixed-tone (`3.xxx`) record outside the level-tone cycles
  (blank Cycle/She/Grade/RhymeName), governed by no statement;
- M11.222 — the deposit's one non-NFC value (GHC `lʰjụ¹`, u + U+0323).

`02b_fanqie_groups/02b_fanqie_groups.csv` keeps the header and the 8
statements governing those rows.

## Reconciliation (full files, 2026-11-04)

- 01: 3,085 data rows = the record description's and README §5.1's
  "3,085 records". `WenhaiPos` is unique over all 3,085; 3,077 distinct
  `Tangut` values (8 heads recur).
- 02b: 1,507 statements, governing 3,056 positions. Under the suffix rule
  (a trailing `*`/`a`/`b`/`c` names a variant of its unsuffixed position)
  3,077 of the 3,085 records are governed by exactly one statement (none
  by two); the 8 ungoverned are 45.2 ~ 47.1 and seven mixed-tone records
  (M09.111, M09.112, M09.151, M09.152, M17.212, M17.221, M22.172).
- 1,519 rows carry an explicit `Fanqie`; each equals its governing
  statement's string in 02b. 13 statements have no readable upper
  speller, 14 no readable lower speller.
- Spellers may themselves be split nodes: `𘅇a` is an upper speller (4
  statements), `𗼍b` a lower speller (3).

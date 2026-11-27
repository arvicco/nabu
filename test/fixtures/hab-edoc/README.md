# hab-edoc fixture

Real samples of the Herzog August Bibliothek Wolfenbüttel's digital editions
(<https://diglib.hab.de/edoc/>), retrieved 2026-11-27, laid out exactly as
the fetch mirrors upstream: `<edition id>/mets.xml` plus the transcripts the
METS lists, at the paths the METS gives.

## Files

| Path | Upstream URL | Copy | Pins |
|---|---|---|---|
| `ed000238/mets.xml` | https://diglib.hab.de/edoc/ed000238/mets.xml | whole | one transcript, no ADMID on its div; an invalid UTF-8 byte inside a comment |
| `ed000238/tei-transcript.xml` | https://diglib.hab.de/edoc/ed000238/tei-transcript.xml | trim | Hans Sachs, *Die Wittenbergisch Nachtigall* (Nürnberg: Georg Erlinger, 1523): TEI `<licence target=".../by/4.0/">` (text "CC BY SA 3.0"), choice orig/reg + abbr/expan, margin notes, pb `n="2r"` |
| `ed000226/mets.xml` | https://diglib.hab.de/edoc/ed000226/mets.xml | whole | no rights ADMID on the transcription div |
| `ed000226/tei-transcript.xml` | https://diglib.hab.de/edoc/ed000226/tei-transcript.xml | trim | Conring, *Musae errantes* (1708): only the "(c) Herzog August Bibliothek" availability line → the site default; a prose sourceDesc `<bibl>` "Helmstedt: Georg. Wolfg. Hammius, 1708."; facs-only pb; printed footnotes (`note type="footnote"`); `TEI/@xml:lang="deu"` on a Latin text |
| `ed000278/mets.xml` | https://diglib.hab.de/edoc/ed000278/mets.xml | whole | METS label "CC BY-SA 4.0" on the transcript |
| `ed000278/texts/tei-transcription.xml` | https://diglib.hab.de/edoc/ed000278/texts/tei-transcription.xml | trim | Sibylla Schwarz, *Deutsche Poëtische Gedichte* (Danzig: Anna Rhete, 1650), a DTA-basisformat header: TEI CC0 (wins over the METS label), surname/forename author, langUsage deu+lat, dwds classCode, pb `n="fol. a i r"` |
| `ed000248/mets.xml` | https://diglib.hab.de/edoc/ed000248/mets.xml | trim | the Lüne letters' METS with 1 of its 413 transcript `<mets:file>` lines kept |
| `ed000248/texts/Brief001-D_tei-transcript.xml` | https://diglib.hab.de/edoc/ed000248/texts/Brief001-D_tei-transcript.xml | whole | a Middle Low German letter: TEI CC BY-SA 3.0 DE, msDesc + `textLang mainLang="nds"`, correspDesc "undatiert", choice orig/reg, an editor's `note type="crit_app"`, `<del>` |
| `ed000020/mets.xml` | https://diglib.hab.de/edoc/ed000020/mets.xml | whole | REJECTED grain: a Theatrum repertory record — METS lists only `tei-introduction.xml` (no transcript) |
| `ed000132/mets.xml` | https://diglib.hab.de/edoc/ed000132/mets.xml | whole | held back: lists `tei-transcript-pnr.xml` (ed000145's file name), which upstream does not serve (404) |
| `ed000239/mets.xml` | https://diglib.hab.de/edoc/ed000239/mets.xml | whole | held back: the Arndt edition, whose transcripts' own headers title them "Arndt-Projekt Test2" |
| `ed000251/mets.xml` | https://diglib.hab.de/edoc/ed000251/mets.xml | trim | an OWN-NAME edition: the texts in `fileGrp USE="transcription"` under their own names (1 of 7 entries kept); METS label "CC BY-SA 3.0" |
| `ed000251/texts/München 1603.xml` | https://diglib.hab.de/edoc/ed000251/texts/M%C3%BCnchen%201603.xml | trim | Hainhofer's travel report (a manuscript): a non-ASCII, space-bearing file name (URN token `Munchen-1603`), TEI CC BY-SA 4.0 (wins over the METS label), pb `n="fol. 127v"`, editors' notes (`type="annotation"`), the title's year the only date |
| `ed000228/mets.xml` | https://diglib.hab.de/edoc/ed000228/mets.xml | trim | Christian II's diaries: the transcription group (1 of 338 months kept) beside per-year introductions; structMap `TYPE="transcript"` |
| `ed000228/1621_11.xml` | https://diglib.hab.de/edoc/ed000228/1621_11.xml | trim | a diary month: TEI CC BY-SA 4.0; the sourceDesc is the edition's person/place/gloss REGISTER (never an imprint); `<index>` regest/place/subject terms opening each entry (the editors', dropped); `div type="entry"`, pb `n="1r"` |
| `ed000233/mets.xml` | https://diglib.hab.de/edoc/ed000233/mets.xml | trim | Bahnsen's letters: one unnamed fileGrp mixing the letters (`briefe/NNNN.xml`, 1 of 21 kept) with introductions and registers |
| `ed000233/briefe/0001.xml` | https://diglib.hab.de/edoc/ed000233/briefe/0001.xml | whole | a letter: the "(c) Herzog August Bibliothek" line only (the site default), the editors' body-level `<head>` label (dropped), the title's date "vom 4. April 1660" |
| `ed000233/einleitung/editionsrichtlinien.xml` | https://diglib.hab.de/edoc/ed000233/einleitung/editionsrichtlinien.xml | whole | REJECTED grain: the editors' apparatus (editorial guidelines) in the same fileGrp — never selected by the edition's rule, never a document |
| `ed000146/mets.xml` | https://diglib.hab.de/edoc/ed000146/mets.xml | trim | Lessing's translations: `*_org.xml` / `*_ue.xml` pairs in one transcription group (1 of 77 pairs kept) |
| `ed000146/abauzit_offenbarung_ue.xml` | https://diglib.hab.de/edoc/ed000146/abauzit_offenbarung_ue.xml | whole | Lessing's German translation (accepted): print sourceDesc Berlin: Voss, 1784; pb `n="105"` |
| `ed000146/abauzit_offenbarung_org.xml` | https://diglib.hab.de/edoc/ed000146/abauzit_offenbarung_org.xml | whole | REJECTED by rule: the French original (`_org`), no file of the group stating its language — counted, held back |
| `ed000249/mets.xml` | https://diglib.hab.de/edoc/ed000249/mets.xml | trim | the FMG letters: transcription group (3 of 67 letters kept, one of them — orgeni-a-002-1 — with no description listed) + descriptions group (2 of 902 kept) |
| `ed000249/texts/h-fmg-rara-fmg-artot-de-padilla-d-001/…_tei-transcript.xml` | https://diglib.hab.de/edoc/ed000249/texts/h-fmg-rara-fmg-artot-de-padilla-d-001/h-fmg-rara-fmg-artot-de-padilla-d-001_tei-transcript.xml | whole | a French letter: TEI CC0, no language statement in the transcript |
| `ed000249/texts/h-fmg-rara-fmg-artot-de-padilla-d-001/…_tei-msDesc_fmg.xml` | https://diglib.hab.de/edoc/ed000249/texts/h-fmg-rara-fmg-artot-de-padilla-d-001/h-fmg-rara-fmg-artot-de-padilla-d-001_tei-msDesc_fmg.xml | whole | its description: `<text><body><msDesc>` with `textLang mainLang="fr"`; correspDesc sender/addressee |
| `ed000249/texts/h-fmg-rara-fmg-bahr-mildenburg-a-001/…_tei-transcript.xml` | https://diglib.hab.de/edoc/ed000249/texts/h-fmg-rara-fmg-bahr-mildenburg-a-001/h-fmg-rara-fmg-bahr-mildenburg-a-001_tei-transcript.xml | whole | a German letter (TEI CC0) |
| `ed000249/texts/h-fmg-rara-fmg-bahr-mildenburg-a-001/…_tei-msDesc_fmg.xml` | https://diglib.hab.de/edoc/ed000249/texts/h-fmg-rara-fmg-bahr-mildenburg-a-001/h-fmg-rara-fmg-bahr-mildenburg-a-001_tei-msDesc_fmg.xml | whole | its description: `textLang mainLang="de"`, correspDesc with settlement Hamburg and date 1898-02-27, msIdentifier idno |

## Trim recipe

Trims cut whole elements only, so every file stays well-formed (checked with
`xmllint --noout` at cut time); every kept line is upstream's byte for byte.

- `ed000238/tei-transcript.xml` (upstream 153,478 bytes, 1,021 lines): lines
  1–154 (header + pages 2r and 2v, ending on the page's `</lg>`) and
  upstream's closing lines 1017–1020 (`</div>`, `</body>`, `</text>`,
  `</TEI>`).
- `ed000226/tei-transcript.xml` (upstream 160,173 bytes): lines 1–328 (header,
  title page, preface with its footnotes, the first front poem), then lines
  392–434 (`</front>`, `<body>`, the book head and its first poem), closed by
  `</div></body></text></TEI>`.
- `ed000278/texts/tei-transcription.xml` (upstream 97,442 bytes): lines 1–294
  (header, front, the first two body divisions), closed by
  `</body></text></TEI>`.
- `ed000248/mets.xml` (upstream 119,420 bytes): upstream lines 331–742 (the
  `<mets:file>` lines of letters 2–413) removed — the fileGrp then lists the
  one held letter.

The per-edition review's samples (retrieved 2026-11-27), same rule — whole
elements only, `xmllint --noout` at cut time:

- `ed000251/mets.xml` (upstream 235 lines): lines 168–185 (the six other
  reports' `<mets:file>` entries) removed.
- `ed000251/texts/München 1603.xml` (upstream 136,617 bytes, 1,599 lines):
  lines 1–193 (header, folios 127v and 127ar) + 1596–1599 (`</div>`,
  `</body>`, `</text>`, `</TEI>`).
- `ed000228/mets.xml` (upstream 490,987 bytes, 3,192 lines): lines 258–656
  (the other months' facsimile links), 664–1062 (the other months'
  transcript entries), 1247 and 1249–2317 (the other months' structMap
  divs) removed.
- `ed000228/1621_11.xml` (upstream 81,538 bytes, 1,116 lines): lines 1–29
  (the header through the register's first person and the opening of the
  second, whose close is upstream line 669) + 669–958 (the rest of the
  register lists, `</teiHeader>`, the first diary entry, pages 1r–2v) +
  1115–1116 (the volume/year closes, `</body></text></TEI>`).
- `ed000233/mets.xml` (upstream 762 lines): lines 99–158 (letters 2–21)
  removed.
- `ed000146/mets.xml` (upstream 1,376 lines): lines 276–762 (every
  transcription entry after the Abauzit pair) removed.
- `ed000249/mets.xml` (upstream 2,168 lines): kept 1–150, 163, 887–892, 937,
  958–959, 990, 1005, 1862–2168 — i.e. two facsimile links beside the first
  fifteen, the artot / bahr-mildenburg / orgeni-a-002-1 letters, the artot and
  bahr-mildenburg descriptions, the rest of the fileSec and the structMap.

## Grain census (2026-11-27)

The edition list: upstream publishes none complete — `sitemap.xml` names
ed000001–ed000229 (230 entries incl. `ed000086_neu`, `ed000216test`), the
HAB's page <https://www.hab.de/digitale-editionen/> links 54 editions up to
ed000276. The census requested `mets.xml` for ed000001–ed000300 and the
suffixed two: 256 METS — 255 on the id walk (last ed000284; ed000285–300
all 404) plus `ed000086_neu`. robots.txt
(re-read 2026-11-27) disallows `/wdb/`, `/rights/`, `/rules/`, `/images/`,
`/temp/`, `/cache/`, `/download.php`, `/passwort/`, `/Report*/`,
`/diglib2004/` — never `/edoc/`.

Grains upstream serves per edition directory:

- **transcript** (ACCEPTED): a TEI file the METS lists under the WDB
  transcript name — 25 editions, 550 files.
- **own-name text** (ACCEPTED per edition, the review below): a TEI
  transcription an edition's METS keeps under its own name, selected by the
  edition's rule (`HabEdoc::EDITIONS` `:texts`: its fileGrp and/or a
  file-name pattern) — 12 editions, 517 files.
- **letter description** (`*_tei-msDesc_fmg.xml`, ed000249): held beside
  its letter and read for the letter's language and correspondents; never a
  document.
- **METS** `mets.xml`: the manifest; read, never a document.
- **introduction / commentary / translation / registers / bibliography**
  (`tei-introduction.xml`, `tei-translation.xml`, `tei-comment.xml`,
  `register-person.xml` …): the editors' modern apparatus — not the source
  text, never fetched.
- **project trees** with their own names (Rubens `archivalien/*.xml`, Lessing
  `*_org.xml`/`*_ue.xml`, Opitz `Band_I/*.xml`, Christian II `1621_11.xml` …):
  230 editions on the id walk without a transcript-named file (184 of them
  introduction-only records), skipped by rule (specimen: `ed000020/mets.xml`).
- **HTML-only editions** (ed000004, ed000005: `transcription.htm` pages, no
  METS) and the library's databases on edoc ids (Lutherdatenbank,
  Leichenpredigten …): no METS — not this shelf.
- **facsimiles**: images under `/drucke/`, `/mss/`, never fetched.

Licence census (the first transcript of each of the 25 editions, header read):
TEI `<licence>` on ed000001 (BY-SA 3.0 DE), 238 (BY 4.0), 245 / 248 / 258 /
266 / 279 (BY-SA 3.0 DE), 249 / 267 / 278 (CC0), 253 (BY-SA 4.0); METS label
"CC BY-SA 3.0" only on 008, 082, 145, 166, 223, 232; neither (the site
default) on 081, 226, 236, 241, 243, 247. No transcript carries a restricted
statement.

## The per-edition review (2026-11-27)

The held 255 METS name 30 editions whose texts keep their own file names
(no WDB transcript name), beside the held-back FMG letters (ed000249). The
review sampled 1–7 files of each (65 requests, robots.txt re-read: `/edoc/`
open) and decided per edition: ADMITTED by an own-name rule — ed000133
Grimmelshausen (32 listed; the 2 under the METS label "Benutzungsordnung"
skipped by the licence law), ed000146
Lessing's translations (the 71 `_ue` files; the 83 `_org` originals held
back by rule), ed000215 Serranus (24), ed000228 Christian II's diaries
(338), ed000233 Bahnsen's letters (21), ed000235 the Middle Low German
psalter (1), ed000244 Rist (14), ed000251 Hainhofer (7), ed000269 Duchess
Sibylla's letters (6), ed000271 Liber modorum (1), ed000275 Simon von Trient
(1), ed000276 Hartlieb (1); and ed000249's FMG letters, their language read
from each letter's description file. HELD BACK, each with its reason in
`HabEdoc::EDITIONS`: Rubens (ed000083), the Magdeburg Centuries' letters
(ed000086), Controversia et Confessio (ed000211, 234, 246), the Breslau
catalogue (ed000212), the Fruchtbringende Gesellschaft letters (ed000213,
214, 217, 218), Karlstadt (ed000216), the peace treaties (ed000227), Opitz
(ed000257), Burckhard's translation (ed000277), the Hainhofer Stammbuch
placeholders (ed000280, 282–284).

## Licence

The fixture files are excerpts of the editions under the licences above (the
Sachs transcript CC BY 4.0; Schwarz CC0; the Lüne letter CC BY-SA 3.0 DE;
Conring under the site's CC BY-SA default; Hainhofer and the Christian II
diary CC BY-SA 4.0 by their TEI; the FMG letters and descriptions CC0 1.0;
Lessing and Bahnsen under the site's CC BY-SA default); the METS files are
the library's manifests. Credit: Herzog August Bibliothek Wolfenbüttel and
each edition's editors.

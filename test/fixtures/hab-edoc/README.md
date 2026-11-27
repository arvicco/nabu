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

## Grain census (2026-11-27)

The edition list: upstream publishes none complete — `sitemap.xml` names
ed000001–ed000229 (230 entries incl. `ed000086_neu`, `ed000216test`), the
HAB's page <https://www.hab.de/digitale-editionen/> links 54 editions up to
ed000276. The census requested `mets.xml` for ed000001–ed000300 and the
suffixed two: 254 METS (last ed000284; ed000285–300 all 404). robots.txt
(re-read 2026-11-27) disallows `/wdb/`, `/rights/`, `/rules/`, `/images/`,
`/temp/`, `/cache/`, `/download.php`, `/passwort/`, `/Report*/`,
`/diglib2004/` — never `/edoc/`.

Grains upstream serves per edition directory:

- **transcript** (ACCEPTED): a TEI file the METS lists under the WDB
  transcript name — 25 editions, 550 files.
- **METS** `mets.xml`: the manifest; read, never a document.
- **introduction / commentary / translation / registers / bibliography**
  (`tei-introduction.xml`, `tei-translation.xml`, `tei-comment.xml`,
  `register-person.xml` …): the editors' modern apparatus — not the source
  text, never fetched.
- **project trees** with their own names (Rubens `archivalien/*.xml`, Lessing
  `*_org.xml`/`*_ue.xml`, Opitz `Band_I/*.xml`, Christian II `1621_11.xml` …):
  229 editions without a transcript-named file, skipped by rule (specimen:
  `ed000020/mets.xml`).
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

## Licence

The fixture files are excerpts of the editions under the licences above (the
Sachs transcript CC BY 4.0; Schwarz CC0; the Lüne letter CC BY-SA 3.0 DE;
Conring under the site's CC BY-SA default); the METS files are the library's
manifests. Credit: Herzog August Bibliothek Wolfenbüttel and each edition's
editors.

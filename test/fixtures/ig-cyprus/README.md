# IG XV 1,1 (Inscriptiones Cypri syllabicae) fixtures

Real EpiDoc records + a trimmed listing for the `ig-cyprus` adapter
(`Nabu::Adapters::IgCyprus` / `IgCyprusEpidocParser`). Retrieved
**2026-10-18** from the Berlin-Brandenburg academy's Inscriptiones Graecae
digital edition (`https://telota.bbaw.de/ig`) — a handful of GETs for
fixtures, not the 593-record crawl:

- each record from the record API `https://telota.bbaw.de/ig/api/xml/<id>`
  (spaces as `%20`, e.g. `.../api/xml/IG%20XV%201,%20237(I)`),
  **byte-identical**, saved under the adapter's file stem
  (`IG XV 1, 237(I)` → `documents/237-I.xml`);
- the listing `https://telota.bbaw.de/ig/api/inscriptions` — one JSON
  object for the whole digital edition (449 KB, 33 fascicle keys), here
  TRIMMED to the `IG XV 1, 1 || Zypern: Syllabarinschriften` key with the
  six fixture records' ids and the `IG XV 2, 1 || Zypern:
  Alphabetinschriften I` key with two ids (so the fascicle-key selection
  is tested); key and id strings byte-identical, upstream order and
  escaping.

Layout mirrors the canonical workdir: `documents/<stem>.xml`,
`map/inscriptions.json`.

## License (in-file, verbatim)

Every record's `<availability><licence
target="https://creativecommons.org/licenses/by/4.0/legalcode">`:
*"Creative Commons Attribution 4.0 International
(https://creativecommons.org/licenses/by/4.0/legalcode). All reuse or
distribution of this work must contain somewhere a link back to this
page."* → **CC BY 4.0**, class `attribution`. The link-back target is
each record's edition page (`<idno type="URI">`), e.g.
https://telota.bbaw.de/ig/digitale-edition/inschrift/IG%20XV%201,%201.

## Records (whole, byte-identical)

| File | Title (upstream) | Quirks it preserves |
|---|---|---|
| `documents/1.xml` | Weihinschrift, eteokyprisch und griechisch | The Amathus bilingual: fragment I Eteocypriot syllabic (`] ị-te-ọ-..-..-..-j̣ạ [  ←`, non-NFC underdots incl. `j̣`), fragment II alphabetic Greek (θησαυρὸν Κυπρίαι…); origDate `330-310` (unsigned BCE); German translation whose fragment I is the italic placeholder `[eteokyprisch]`. |
| `documents/5.xml` | Inschrift, eteokyprisch | Pure Eteocypriot, five lines, no fragments; `4.Jh.`; placeholder-only German div. |
| `documents/180.xml` | Grabinschrift, syllabisch | Unnumbered `<lb/>` + `<hi rend="smallit">linea</hi>` (ruled lines) between the numbered lines; `<hi rend="letterspacing">|</hi>`; GRC alphabetic transcription (Ἀρίστας ἠ[μί],) + German translation; `6.-4.Jh.`. |
| `documents/237-I.xml` | Grabinschrift, syllabisch | Suffixed roman id `237(I)`; a TAB before the direction arrow; `Anfang 4.Jh.`; GRC transcription with Latin `y` inside Greek (Ζωϝίyας). |
| `documents/254-1.xml` | Einzelbuchstaben, alphabetisch | Suffixed digit id `254(1)`; alphabetic `Ε` + private-use glyph U+F0011; German placeholder on an UNNUMBERED `<lb/>`; `5.-4.Jh.`. |
| `documents/410.xml` | Münzlegende des Königs Stasioikos II. | Twelve coin-legend fragments `(a)`–`(l)` alternating syllabic and alphabetic lines; `<hi rend="smallit">tit. evanidus</hi>` as a whole line; title without a script label. |

No record carries `xml:lang` on its edition or fragments (only the TEI
root's `en` and the translation divs' `DE`/`GRC`); the syllabic text is
held in Latin transliteration throughout — no Unicode Cypriot-block
characters.

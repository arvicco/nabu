# atmo fixtures

Retrieved 2026-09-28 from uyghur.linguistics.indiana.edu (ATMO —
Annotated Turki Manuscripts from the Jarring Collection Online;
license page verbatim: "Everything produced by the project … is
licensed under a Creative Commons Attribution-ShareAlike 4.0
International License.").

- `index.xhtml` — the manuscripts index (18 transcript.xml links —
  the fetch manifest; facsimile-only XMLs stay upstream by design).
- `Jarring_Prov_2.transcript.xml` / `Jarring_Prov_24.transcript.xml`
  — real TEI P5 transcripts trimmed to the header + first 3
  tei:surface elements (of 96 / 80). Shape: surface[@n = folio side
  "1a"] → atmo:page → zones (atmo:main body; atmo:top endorsements/
  folio numbers) → tei:line[@n] with atmo:lit (Perso-Arabic, the
  served text) + atmo:lat (Latin transliteration, annotation layer).

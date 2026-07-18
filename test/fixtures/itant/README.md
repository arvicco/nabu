# Corpus ItAnt fixtures — P29-2

Real EpiDoc TEI records for the `itant` adapter (`Nabu::Adapters::Itant` /
`ItantEpidocParser`). Retrieved **2026-07-18** from
`https://github.com/DigItAnt/Corpus_ItAnt` (raw files at upstream `main`,
commit **b60146fe7743ab14c8fd66f657ca218e172eb0f6**, committed 2024-10-14),
each file **byte-identical** (sha256 below). Layout mirrors the canonical
workdir the adapter's GitFetch clone produces: the two ingested corpus dirs
plus the repo-root `license.txt`.

Upstream census at that commit (the packet's fixture-time count): **501**
`Oscan_inscriptions_newEditions/*.xml` + **9**
`CelticOfItaly_inscriptions_newEditions/*.xml` = 510 records;
`Venetic_inscriptions_newEditions/` and `Faliscan_inscriptions_newEditions/`
hold a README each and NO records (the journaled re-sync watch);
`Drawings/` holds a README only.

## License (three layers, all agreeing — CC BY-NC-SA 4.0 → class `nc`)

- Repo `license.txt` (fixture copy, verbatim): "Corpus ItAnt is licensed
  under CC-BY-NC-SA 4.0 https://creativecommons.org/licenses/by-nc-sa/4.0/"
- Repo `README.md` (not vendored — same grant): "The Italia Antica Corpus is
  licensed under CC-BY-NC-SA 4.0" + the citation request (Murano, Francesca,
  Valeria Quochi, Angelo Mario Del Grosso, Luca Rigobianco, and Mariarosaria
  Zinzi. 2023. "Describing Inscriptions of Ancient Italy. The ItAnt Project
  and Its Information Encoding Process". JOCCH 16 (3). doi:10.1145/3606703).
- EVERY record's `<availability><licence target="…by-nc-sa/4.0/">`: "This
  file is licensed under the Creative Commons Attribution-NonCommercial-
  ShareAlike 4.0 International license – (CC BY-NC-SA 4.0)."
- One layered nuance, recorded not relied on: the `eng` translation divs
  carry their own `<ref type="licence">` naming CC BY-SA 4.0 — the sibling
  documents keep the source-level `nc` class (restrictive reading, the
  ogham posture).

## Records (whole, byte-identical)

| File | sha256 (first 12) | Quirks it preserves |
|---|---|---|
| `Oscan_inscriptions_newEditions/ItAnt_Oscan_2.xml` | `97c8939d8319` | Curse tablet, Monte Vairano: `<name>` word tokens (praenomen/gentilicium/patronymic) with `xml:lang="osc-Ital-x-oscetr"`, `<pc unit="word">` interpuncts, `expan/abbr/ex` (tre(bieís)), `<gap reason="lost">` inside a name, TWO textparts `face_a`/`face_b` with lb `n="1"`/`n="1b"`, `style="text-direction:r-to-l" rend="ductus:sinistrorse"`, TM 170774 + ImIt Bouianum 98 + ST Sa 36 + Murano 6 concordances, AAT tablet/lead, EAGLE defixio, GeoNames + Pleiades origPlace, non-empty ita+eng translation divs (the eng one carrying its own BY-SA ref — see License). |
| `Oscan_inscriptions_newEditions/ItAnt_Oscan_492.xml` | `a9e070e2bcf5` | The dense-markup case: `hi rend="ligature"` WRAPPING a `choice` (corr e / sic v) inside an `abbr`, an EMPTY `<ex/>`, `supplied reason="lost"` around a whole expansion AND around a `pc` interpunct. |
| `Oscan_inscriptions_newEditions/ItAnt_Oscan_576.xml` | `5ba160d81e8d` | Lost inscription: the edition div holds one SELF-CLOSED textpart and no text at all → the metadata-only document (ogham precedent); header still carries TM 170664, ImIt Aeclanum 13, AAT lid/pottery, GeoNames Fioccaglia di Flumeri. |
| `CelticOfItaly_inscriptions_newEditions/ItAnt_Lepontic_1.xml` | `42dc39d1349d` | Lepontic (upstream langUsage `xcg` / `xcg-Ital-x-xcglep` — Cisalpine Gaulish, NOT ISO `lep`, which is Lepcha): BOTH `subtype="diplomatic"` (raw lines, kuaśoni:pala:telialui) and `subtype="interpretative"` edition divs → the `-dipl` sibling; `supplied`/`unclear` mid-name; per-textpart ita+eng translation divs with `subtype="text_A"/"text_B"`. |

`Oscan_inscriptions_newEditions/README_Oscan_corpus.txt` (433 bytes,
verbatim) rides along to pin that non-XML files inside a corpus dir are
never discovered; `CelticOfItaly_inscriptions_newEditions/license.txt` is
the per-dir copy of the same grant.

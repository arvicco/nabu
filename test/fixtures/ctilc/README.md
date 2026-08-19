# CTILC public-domain works slice fixtures — P80-8

Real upstream samples for the `ctilc` adapter (`Nabu::Adapters::Ctilc`),
retrieved **2026-08-19** from the IEC's CTILC download endpoints
(spot-verified byte-identical to the 2026-08-19 scout snapshots):

- `works/<NNNNNN>_<Sanitized_Title>.out.txt` — per-work downloads from the
  stateless GET `https://ctilc.iec.cat/scripts/CTILCCorpus_DescarrF.asp?fitxer=<filename>`
  (text/plain, **UTF-8 WITH BOM** — the BOM is a real upstream quirk and the
  encoding-regression subject). Each file TRIMMED to the pseudo-XML header +
  the first few `<TEXT>` paragraphs + the closing `</TEXT>\n</DOCUMENT>\n`,
  byte-identical in the kept region:
  - `000041_Poemes_biblics.out.txt` — Alcover, *Poemes bíblics* (1918);
    LITERARI, gènere P, variant `baleàric`; 6 of 159 paragraphs (verse:
    note the trailing two-space soft line breaks, kept verbatim).
  - `003392_Els_salms_de_David.out.txt` — Febrer i Cardona, *Els sálms de
    David* (1840); LITERARI, `traducció="sí"`, variant `baleàric`; 5 of 174
    paragraphs. Its listing citation carries no publisher (`[Inèdit]`).
  - `001607_La_llibertat_en_la_lley_civil.out.txt` — Abadal i Calderó,
    *La llibertat en la lley civil* (1905); **NO LITERARI** (`llengua="NLIT"`,
    empty `gènere`, `tema="3"` `subtema="3.4"`), variant `central`; 4 of 128
    paragraphs.

- `listing/CTILCCorpus_Descarr.html` — the download listing
  `https://ctilc.iec.cat/scripts/CTILCCorpus_Descarr.asp` TRIMMED from
  318,774 bytes (967 `obredoc(...)` entries: LITERARI 348 + NO LITERARI 619)
  to the real page head, the **verbatim terms table** (Llei 21/2014 /
  "domini públic" / the mandatory IEC citation sentence — the license
  record), and both section frames with the three held works' entry divs
  byte-identical (the section `Resultat` counts are the full page's,
  untrimmed). CRLF line endings as served.

## License (verbatim on the listing page, captured here)

The terms table states the downloadable works "han passat a ser de
**domini públic**" under Llei 21/2014 and may be downloaded "per a ús privat
o de recerca amb llicència Creative Commons" — the CC variant is UNNAMED on
the page. Mandatory citation: *"Aquest text ha estat digitalitzat i
processat per l'Institut d'Estudis Catalans, com a part del projecte Corpus
Textual Informatitzat de la Llengua Catalana"*. → class `attribution`;
`dcc@iec.cat` is the published contact for a named variant.

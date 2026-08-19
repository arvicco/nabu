# lo-congres fixtures — Occitan Corpus from Lo Congrès news (Zenodo 8411197)

Retrieved 2026-08-19 from Zenodo record 8411197 ("Occitan Corpus from Lo
Congrès news v1.0" — Lo Congrès permanent de la lenga occitana), via the
stable per-file download URLs
`https://zenodo.org/records/8411197/files/<name>?download=1`.

The record ships SIX dialect CSVs (plus README.txt). One line per aligned
sentence pair, `§`-separated, NO header row, four fields:

    occitan sentence§occitan variety code§french translation§fr

Censused 2026-08-19 (full artifacts, every line exactly 3 `§`, zero blank
lines, no BOM/CRLF, trailing newline present):

| file | lines | sha256 |
|---|---:|---|
| oc-auvern-grclass_fr.csv | 17 | `740c2328c88c25b4dd46f791e46cebab58d8bbf83b727e828f610d1433c76212` |
| oc-gascon-grclass_fr.csv | 2,194 | `2f9e8e1ae19e23f9c4c97666de724b239a3c7cf358c1c0866a5c8bcf67a5c755` |
| oc-lemosin-grclass_fr.csv | 90 | `fbc3ba0f974610c592fae65c80b9fffaa4187e47c76a75724e385ed53ab1c16f` |
| oc-lengadoc-grclass_fr.csv | 2,658 | `3be39359398183fe43d038e093aa0bf67abd4aa029a8145459052262cac53c22` |
| oc-provenc-grclass_fr.csv | 157 | `96713e8101529d64c557f9b439dc251c2fb39eb07f39ae86394a9b96db1d62a5` |
| oc-vivaraup-grclass_fr.csv | 36 | `0437a923a697b5b5088418af62f3439bee9804a204acfbca2db5faa25e312d7a` |

5,152 pairs total. The variety-code field is constant per file
(`oc-<dialect>-grclass`) and the translation-language field is always `fr`
— both censused; the adapter treats a deviation as damage.

## Trimmed fixtures (byte-verbatim upstream lines)

- `auvern/oc-auvern-grclass_fr.csv` — lines **1–6** of the full artifact.
- `gascon/oc-gascon-grclass_fr.csv` — lines **1–4, 2132, 2161**. Line 2132
  is one of the two gascon lines whose FRENCH field is non-NFC (fr-side
  non-NFC: 2132, 2138); line 2161 is one of the two whose OCCITAN field is
  non-NFC (oc-side: 2161, 2162 — decomposed `é` = `e` + U+0301). The
  lengadoc file adds 6 more oc-side non-NFC lines (660–661, 1079–1082);
  both sides cross the `Normalize.nfc` boundary.
- `provenc/oc-provenc-grclass_fr.csv` — lines **1–5**.

Because passage identity is the 1-based line number in the LOCAL canonical
file (the tla-hf precedent — upstream ships no sentence ids), the trimmed
fixtures mint urns `:1`–`:6`; the upstream line provenance above is
documentation, not identity.

The lemosin / lengadoc / vivaraup dialects carry no fixture — the adapter
discovers whatever dialect subdirs are present (the tla-hf fewer-files
posture), so three fixture dialects exercise the whole registry walk.

## License (verified 2026-08-19)

Zenodo record API: `license: {id: cc-by-4.0}`. The record's own README.txt,
verbatim:

> The SoftwaresOccitanTranslations corpus is distributed under the
> Creative Commons Attribution 4.0 License
> (https://creativecommons.org/licenses/by/4.0).

→ `license_class: attribution`.

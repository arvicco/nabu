# bdcamoes fixtures

Trimmed REAL slices of BDCamões Part I — "BDCamões Corpus - Collection
of Portuguese Literary Documents from the Digital Library of Camões
I.P. (Part I)", PORTULAN CLARIN repository, version 20191128,
hdl:21.11129/0000-000D-F89B-D. Retrieved 2026-08-19 from
https://portulanclarin.net/repository/download/52f2b16412c411ea8a1302420a000005407eb504ccc045a4a0582ab53dfd43fd/
(archive sha256
c0511fbf5ece31eb7f03e012edc30e13f02df60dc320724a3036f9061806b9f7).
License: **"CC - BY"** verbatim on the record page (read 2026-08-19);
the download click-through was accepted on owner ruling №R-37
(2026-08-19). Part II is a DIFFERENT grant (MS NC-NoReD-ND 2.0) and is
not ingested.

The zip carries `BDCamões_Part_I/resource/*.xml` (127 one-work files)
plus `license.pdf`. Every member name is UTF-8-flagged in the central
directory (audited 2026-08-19 — the mojibake `unzip -l` prints is a
display artifact only).

- `resource/VicenteAutoBarcadoInferno.xml` — Auto da Barca do Inferno
  (Gil Vicente, YY: 1517, GG: Drama), header + the first 14 blank-line
  blocks (introdução + the opening of Cena I, "À barca, à barca,
  houlá!"); self-closing `<footer />`.
- `resource/QueirósUmPoetaLírico.xml` — Um Poeta Lírico (Eça de
  Queirós, YY: 1900, GG: Tale), header + the first 6 paragraphs. Pins
  the corpus's SECOND paragraph convention: no blank lines at all —
  paragraphs are marked by newline + a single tab — and the non-ASCII
  upstream filename (ó, í). Footer carries the edition citation.
- `resource/CastilhoPoesias.xml` — Poesias (António Feliciano de
  Castilho, YY: `18??`, GG: Poetry), header + title line + 6 stanzas.
  Pins blank-line stanza breaks with UNindented verse lines, and the
  unresolved `18??` year mark (raw-only dating — no bounds invented).
- `license.pdf` — the in-zip license file, whole (the one non-corpus
  member discovery must recognize).
- `fetch/licence-agree-page.html` — the WHOLE live Django
  licence-agree page the download URL serves to a plain GET (retrieved
  2026-08-19): csrfmiddlewaretoken input, `licence` hidden field
  (`value="CC-BY"`), `licence_agree` checkbox. The recorded shape
  behind `Nabu::LicenseAgreeFetch` (test/license_agree_fetch_test.rb).

Format quirks these fixtures pin: minimal one-work XML wrapper
(`document > header > title/author/other`, then `text`, then an
optional `footer`); the `<other>` blob carries `YY:` (publication
year — exact, range `1889-1894`, split `1876/77`, or unresolved
`18??`) and `GG:` (genre) lines; two paragraph conventions (blank
lines vs newline+single-tab); drama/verse continuation lines indented
with MULTIPLE tabs (never split); stanza lines in poetry unindented
within blank-line blocks.

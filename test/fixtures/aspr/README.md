# ASPR fixture (P12-2)

One trimmed real TEI-P5 file from the Oxford Text Archive: **OTA 3009**, the
complete Anglo-Saxon Poetic Records (Krapp & Dobbie, Columbia UP 1931–1953;
machine-readable version Gregory Ray Hidley, deposited O. D. Macrae-Gibson
1993) — the entire canonical Old English poetry corpus as a single 2.2 MB
TEI file.

## Provenance

- **URL (DSpace bitstream, no auth):**
  https://ota.bodleian.ox.ac.uk/repository/xmlui/bitstream/handle/20.500.12024/3009/3009.xml
- **Record page:** https://ota.bodleian.ox.ac.uk/repository/xmlui/handle/20.500.12024/3009
- **Retrieved:** 2026-07-10 (the P12-2 Phase A survey-sanctioned sample;
  server ignores Range requests, so the sample was the whole file).
- **Upstream sha256 (full 2,214,065-byte file):**
  `4cf370226d9329e846eceb78fdaa987735113a02ef998980d6070664775ceed5`
- **Upstream Last-Modified:** Fri, 19 Jul 2019 12:07:26 GMT (effectively
  frozen; header normalised 2010, deposit 1993).

## License (verbatim, from the file's own teiHeader availability element)

> `<licence target="http://creativecommons.org/licenses/by-sa/3.0/">
> Distributed by the University of Oxford under a Creative Commons
> Attribution-ShareAlike 3.0 Unported License</licence>`

→ `license_class: attribution`. The OTA record page agrees ("Attribution-
ShareAlike 3.0 Unported (CC BY-SA 3.0)", status "Publicly Available").

## Trim (owner-approved plan, backlog P12-2, approved 2026-07-10)

`3009.xml` here is the upstream file's **teiHeader verbatim** + `<text><body>`
holding **8 of the 349 poem divs, verbatim in upstream file order** (Beowulf
trimmed), + the closing tags. Upstream structure: flat
`<div rend="linenumber" xml:id="…">` per poem — the `xml:id` values are the
canonical Cameron/DOE record numbers — each `<head>` + optional `<bibl>` +
flat `<l>` verse lines (NO `l/@n`; the per-div `<l>` ordinal equals the
printed ASPR line number — Beowulf's div carries exactly 3,182 `<l>`).

| div (Cameron) | Poem | Lines kept | Why |
|---|---|---|---|
| `A3.34.15` | Riddles 75 (Exeter Book) | 2 (whole) | `<foreign xml:lang="rune">` runes |
| `A3.34.22` | Riddles 82 (Exeter Book) | 5 (whole) | `<gap/>` lacunae (incl. a div-level gap BETWEEN lines) |
| `A4.1` | **Beowulf** | **1–24 of 3182** (head+bibl+first 24 `<l>`, ordinals genuine) | the demo passage (`Hwæt! We Gardena…`) + `<caesura/>` + `<unclear>` |
| `A16` | A Proverb from Winfrid's Time | 2 (whole) | `<g ref="ecaudata">ę</g>` glyphs mid-word (no surrounding space) |
| `A32.1` | Cædmon's Hymn, Northumbrian | 9 (whole) | dialect witnesses are separate texts… |
| `A32.2` | Cædmon's Hymn, West-Saxon | 9 (whole) | …with distinct Cameron ids |
| `A43.5` | For Loss of Cattle (charm) | 16 (whole) | title collision pair — identical `<head>`… |
| `A43.10` | For Loss of Cattle (charm) | 13 (whole) | …distinct `xml:id` (why title-slugs were rejected) |

Extraction was mechanical (regex over div blocks keyed by `xml:id`, blocks
copied byte-verbatim; the Beowulf block cut after the 24th `</l>` with the
`</div>` re-closed at upstream indentation). Total 80 `<l>` / 12,015 bytes,
well-formed, NFC (upstream is already NFC throughout).

Corpus-wide facts verified on the full sample and relied on by the parser:
`<caesura/>` is always space-padded (never flush against text), `<l>` never
carries attributes, `<head>` is always plain text, divs never nest, and the
file is NFC.

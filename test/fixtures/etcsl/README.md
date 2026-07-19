# ETCSL fixtures — P31-5

Real TEI files for the `etcsl` adapter (`Nabu::Adapters::Etcsl` /
`EtcslTeiParser`), extracted **2026-07-19** from the one upstream delivery
unit, `etcsl.zip` (4,910,212 bytes, sha256
`d1a35b396399216deaeb483d5954ae603662e73c4e77f23e39f2e7b58466962b`),
downloaded from the Oxford Text Archive's current CLARIN-UK home
(the Language and Linguistic Data Service):

- Record: <https://llds.ling-phil.ox.ac.uk/llds/xmlui/handle/20.500.14106/2518>
  ("The Electronic Text Corpus of Sumerian Literature. Revised edition.",
  hdl `20.500.14106/2518`; the legacy record `ota.bodleian.ox.ac.uk` hdl
  `20.500.12024/2518` was 502/504 throughout 2026-07-18/19 — the Bodleian
  legacy OTA server is down after a major IT incident, and the OTA
  collections' current official home is the LLDS repository).
- Zip bitstream: `…/bitstream/handle/20.500.14106/2518/etcsl.zip?sequence=12&isAllowed=y`

Layout mirrors the canonical workdir after `Nabu::ZipFetch` unpacks the
zip (single top-level `etcsl/` dir, so its CONTENTS become the tree):
`transliterations/c.<num>.xml` (Sumerian composites), `translations/t.<num>.xml`
(English prose translations). All files are TEI P4 ("TEI.2") in "XML ASCII
Windows pc format" (upstream readme.txt) — **CRLF line endings, no XML
declaration, no DOCTYPE**, with named entities defined externally
(`etcsl-sux.ent`); trims preserve both byte conventions.

## The five files

| file | trim | exercises |
| --- | --- | --- |
| `transliterations/c.1.8.2.1.xml` | TRIMMED (see below) | Lugalbanda in the mountain cave: `div1` segments A+B, `l` lines with `w form/lemma/pos/label`, `supplied`/`damage` milestones, `unclear`, `corr` with `&damb;…&dame;` sic values, editorial `note` with `xref doc="c.0.2.01"` (reference-edge source), `&X;` illegible tokens, determinative entities |
| `translations/t.1.8.2.1.xml` | TRIMMED (see below) | paired `-en` sibling: `p id/n/corresp` prose paragraphs, proper-noun `w type="DN/RN/SN…"`, `q`, `ref`+`note` footnotes, mid-paragraph `gap`, ISO entities (`&eacute;`), and segment B's gap-only `p` (skipped honestly) |
| `transliterations/c.2.5.2.3.xml` | none — WHOLE file | adab to An for Šu-ilīšu: `lg` line-groups instead of `div1`, `trailer` with real `l` lines, `&X;`-only supplied tokens |
| `translations/t.2.5.2.3.xml` | none — WHOLE file | paired sibling with `lg` holding `p` paragraphs and a `trailer` `p`; ETCSL char entities in English prose (`&C;u-il&imacr;&c;u` → Šu-ilīšu) |
| `transliterations/c.0.2.01.xml` | none — WHOLE file | OB catalogue from Nibru (N2): flat `body` of `l` lines (no div1/lg), `&hr;` ruling text nodes inside and between lines, **no paired translation** (no `-en` sibling minted) |

## Trim procedure (documented, reproducible)

Both trims are line-range cuts of the CRLF originals — every kept region
is **byte-verbatim**, and the spliced regions are the file's own bytes:

- `c.1.8.2.1.xml` (227,844 B → 15,947 B): lines 1–230 (teiHeader +
  `div1` A opened + lines A.1–A.10) ++ lines 4019–4079 (`</div1>` closing
  A + the whole short `div1` B + `</body></text></TEI.2>`).
- `t.1.8.2.1.xml` (34,626 B → 5,468 B): lines 1–46 (teiHeader + `div1` A
  opened + paragraphs p1–p3) ++ lines 127–133 (`</div1>` closing A + the
  whole `div1` B, whose p35 is gap-only, + closers).

## License (verbatim, from the record — the artifact itself carries none)

The LLDS record page states: *"This item is Publicly Available and
licensed under: Attribution-NonCommercial-ShareAlike 3.0 Unported
(CC BY-NC-SA 3.0)"* (link target
`http://creativecommons.org/licenses/by-nc-sa/3.0/`; the record's DC
metadata repeats "Creative Commons Attribution-NonCommercial-ShareAlike
3.0 Unported License."). Nothing inside the zip (corpus header
`corphdr.xml`, file teiHeaders, `readme.txt`) carries any license or
availability statement — the record-level grant is the only one, hence
`license_class: "nc"`.

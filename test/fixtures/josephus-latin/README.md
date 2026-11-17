# josephus-latin fixtures

Trimmed real files from **The Latin Josephus Scholarly Corpus. XML Texts,
Historical Transcriptions and Scholarly Data**, version 3.0 (Richard
Matthew Pollard, latinjosephus.org), Zenodo record **24120761**, DOI
10.5281/zenodo.24120761, published 2026-11-10. Retrieved 2026-11-17 from

    https://zenodo.org/api/records/24120761/files/Latin_Josephus_v3.0_Corrected_XML_ZENODO_RC.zip/content

Record license field: `cc-by-4.0`. Per-file terms are those of the
deposit's own `FILE_LICENCE_MANIFEST.csv` (trimmed copy here, header +
the rows of the files below, otherwise verbatim).

## The record's delivery grains

| Record file | Bytes | Checksum | Taken |
|---|---:|---|---|
| `SHA256SUMS.txt` | 240 | md5 `ce9f4894193c66c7d02fc95036da548b` | no (its sha256 is the adapter's pin) |
| `Latin_Josephus_v3.0_Corrected_XML_ZENODO_RC.zip` (the core) | 8,359,339 | sha256 `cfaf269a6fcbd7eb61754573449304dc1ed9d59bd5c6c0a7f5e9c8ec44d67106`, md5 `ce4f8d782e727b1a1a259b5eac661980` | **yes** |
| `Latin_Josephus_v3.0_Supplementary_Scholarly_Data_ZENODO.zip` | 11,169,170 | sha256 `be93920247600593f834223e276e6bebd15909e13fdf098c449f239c0dee53e6`, md5 `df16db2130e6397fd60cae58876443cb` | no — offset-coordinate JSON (Froben 1524 Latin, Millet 1556 French, Lauro 1544 Italian), the manuscript and library catalogues, annotation and concordance tables, the EEBO-TCP A04680 source: a separate parser |

## Grains inside the core zip (under `assets/xml/`, 180 files)

| Grain | Upstream count | Verdict | Specimen here |
|---|---:|---|---|
| `<work>/Latin/<book>.xml` — the Latin texts | 35 (21 Antiquities + 7 Bellum + 2 Contra Apionem + 5 De excidio) | **document** | `antiquities/Latin/{preface,book-01,book-03,book-09,book-11}.xml`, `bellum/Latin/book-07.xml`, `contra-apionem/Latin/book-02.xml`, `deh/Latin/book-02.xml` |
| `<work>/Greek/*.xml` — Niese's Greek (Perseus) | 30 | skipped by rule: held by `perseus-greek` (tlg0526) | `antiquities/Greek/preface.xml` |
| `<work>/English/*.xml` — Whiston (Perseus) | 30 | skipped by rule: held by `perseus-greek` (eng2) | `antiquities/English/preface.xml` |
| `<work>/English/Lodge1602/*.xml` — Lodge 1602 (EEBO-TCP A04680) | 30 | skipped by rule: held by `eebo-tcp` | `antiquities/English/Lodge1602/preface.xml` |
| `deh/English/*.xml` — Pollard's English De excidio v1.2 | 5 | skipped by rule: **AI-drafted** — latinjosephus.org/texts: "The English DEH was drafted by AI from the Latin, under Richard Matthew Pollard's supervision and editorial direction" | `deh/English/book-02.xml` |
| `antiquities/paratext/{bamberg78,niese,whiston}/*.xml` — capitula | 34 (5 + 9 + 20) | skipped by rule: editorial paratext; the Bamberg capitula supply lost margins from Blatt (1958), quotations outside the open grant (the deposit's RIGHTS_RESOLUTION.md) | `antiquities/paratext/bamberg78/book-05-contents.xml` |
| `antiquities/niese/*.json` — Niese citation registries | 14 | skipped by rule: data, not text | `antiquities/niese/preface.json` |
| `antiquities/structure.xml`, `source-contents.xml` — registers | 2 | skipped by rule: structural registers | both, trimmed |

Reconciliation: the deposit README states 166 canonical XML + 14
citation registries = 180 = 35 accepted + 145 skipped by rule.

## Recipe

Cut by a Nokogiri pass over the extracted core (re-serialized UTF-8;
content otherwise untouched):

- text files: the first K reading units (`p`/`head`/`trailer` not nested in
  another unit, document order) plus every `trailer` are kept; the other
  units, and chapters left empty, are dropped; standOff `<app>` entries are
  kept only when their first `<rdg>` points at a kept unit. K = 3 for
  Antiquities I and IX, Bellum VII, Contra Apionem II, the De excidio
  English II and Lodge's proem; 4 for Antiquities XI and De excidio II;
  Antiquities III keeps the one unit `latin-book03-num239` (its `<gap>`).
- registers: the first 2 `<item>`s of every `<list>`.
- whole, byte-for-byte: `antiquities/Latin/preface.xml`, the Greek and
  Whiston proems, `paratext/bamberg78/book-05-contents.xml`,
  `niese/preface.json`.

Shapes the specimens pin: Antiquities I (inline witness `<note>`s,
`<del>`/`<add>`, `<num>`, Niese milestones, a standOff apparatus, an
id-less incipit, a trailer); IX (a break-only empty `<p>`); XI (the
running text nested in `<argument>`/`<floatingText>`); III (`<gap>`);
Bellum (Cardwell's in-text labels, no `<num>`); Contra Apionem (the
Boysen witness note, `@n` paragraphs); De excidio (the NC-licensed
digilibLT layer, word-internal `<pb>`).

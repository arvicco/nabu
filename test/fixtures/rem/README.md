# ReM fixtures (Middle High German, TEI P5 / CorA-token)

Real samples from the **Reference Corpus of Middle High German (1050–1350)**
(*Referenzkorpus Mittelhochdeutsch*, ReM), version **2.1**, in its **TEI P5**
serialisation (CLAUDE.md fixture rules). Two small complete texts, kept whole.

- **Retrieved:** 2026-07-22, from **Zenodo record 13982324**
  (`https://zenodo.org/records/13982324`).
- **Upstream artifact:** `ReM-v2.1_tei.zip`,
  `https://zenodo.org/api/records/13982324/files/ReM-v2.1_tei.zip/content`,
  27,899,230 B, sha256
  `a04e8ac60c87b24eadd7ff3155040c09fccbd359a229fec3fdebae53295351d1`. The zip
  holds a `README` + one `tei/M###.xml` file per corpus text. The full zip was
  fetched to a scratch dir and is **not** committed; ReM also ships the same
  data as CorA-XML, GraphML, JSON and PDF (separate, larger zips in the record).

## Files (zip members, kept whole)

| File | Bytes | Text | Tokens |
|---|---|---|---|
| `M058.xml` | 6,492 | *Sangspruchstrophe MF 'Namenlos IV'* (a lyric strophe) | 23 |
| `M218B.xml` | 7,211 | *St. Galler Schularbeit, Exzerpt* (a school-exercise excerpt) | 34 |

Both are among the **smallest complete texts** in the corpus, extracted from
`ReM-v2.1_tei/tei/` and kept **byte-for-byte whole** (each is a self-contained,
well-formed TEI document — verified with `xmllint --noout`). Because a raw GET
of the URL returns the 27 MB *zip*, not the member file, the manifest marks
these `whole: false` (fetched for URL-liveness only, never byte-compared); the
`trim:` note records that the member itself is uncut. Re-extract from the zip
after any refresh.

## The P40-r1 collision exemplars (structural trims)

The 46 first-sync quarantines (2026-07-22) were all one failure class —
duplicate `<folio>.<line>` passage refs — in two censused shapes, each
pinned by a **structurally trimmed** exemplar (teiHeader byte-for-byte,
body cut at a marker boundary, closing tags appended; well-formedness
verified):

| File | Bytes | Text | Shape |
|---|---|---|---|
| `M242.xml` | 44,148 | *Wiener Notker* | **Two-column codex**: `<cb n="a"/"b" ed="1">` restarts line numbers per column (1,863 collisions in the full file) → the column joins the folio in the ref (`5ra.1`/`5rb.1`). Cut before the third primary `<pb>`. |
| `M345.xml` | 51,528 | *Augsburger Urkunden* | **Entry-wise restarts**: `<lb n="1" ed="1">` recurs with NO container element (calendar-style entries) → residual collisions take the house `:b2` positional disambiguator. Cut before the third restart, keeping two colliding runs. |

## Structure notes (for the P40-5 parser)

- TEI P5 `version="4.6.0"`, namespace `http://www.tei-c.org/ns/1.0`; a full
  `<teiHeader>` (titleStmt, extent `<measure unit="tokens">`, publicationStmt
  with the `<licence>`, textClass taxonomy) then `<text><body>`.
- Tokens are `<w xml:id="t1_m1" norm="al" lemma="al">al</w>`: the element text is
  the **diplomatic form** (`grínme`, `ſtet`, `muͦzic` — real medieval graphemes,
  long-s and combining marks), `@norm` the normalised form, `@lemma` the lemma.
  `@join="right"`/`"left"` marks tokens written together. Punctuation is `<pc>`.
  Multi-part tokens share a base id with `_m1`/`_m2` suffixes (`t9_m1`, `t9_m2`).
- `<lb/>` marks manuscript line breaks; `<unclear>`, `<supplied>` carry
  editorial status. **Text is medieval — verify NFC handling** at the adapter
  boundary (combining marks over `u`/`o` appear, e.g. `muͦzic`).

## License (recorded exactly)

**CC BY-SA 4.0**, stated identically in two places:

- Zip `README`, verbatim: *"The Reference Corpus of Middle High German is
  licensed under the Creative Commons Attribution-ShareAlike 4.0 International
  License. To view a copy of this license, visit
  https://creativecommons.org/licenses/by-sa/4.0/ …"*
- Each TEI file's `<publicationStmt>`:
  `<licence target="https://creativecommons.org/licenses/by-sa/4.0/">Creative Commons Attribution-ShareAlike 4.0 International (CC-BY-SA)</licence>`

Zenodo record metadata agrees: `license: cc-by-sa-4.0`. license_class
`attribution`. Cite: Roussel, Klein, Dipper, Wegera, Wich-Reif (2024).
*Referenzkorpus Mittelhochdeutsch (1050–1350), Version 2.1*, ISLRN
937-948-254-174-0.

# AED fixtures

A trimmed, byte-verbatim slice of the TLA/BBAW **Ägyptische Wortliste**
(AED — Ancient Egyptian Dictionary): retrieved 2026-07-18 from
https://github.com/simondschweitzer/aed-tei at commit
`462c722e0323e05641aea2eee8cdf1e27303d939` (2025-05-18), file
`files/dictionary.xml` (18 MB, 35,052 entries upstream).

## License

In-file, verbatim from the file's own `<availability status="free">`
(publicationStmt): "Metadata and texts are released as Creative Commons,
Attribution-ShareAlike 4.0 (CC BY-SA 4.0)"
(`http://creativecommons.org/licenses/by-sa/4.0/`) → license_class
`attribution`. The repo carries no separate LICENSE file; the in-file grant
is the authoritative one and is quoted in the adapter manifest.

## Trim procedure

`files/dictionary.xml` here is the real teiHeader plus 31 upstream
`<entry>` elements copied byte-verbatim in file order, with the original
`</body></text></TEI>` closers (nothing rewrapped, nothing reindented).

## What the 31 entries cover

- **The join-contract cluster**: the `nfr` homographs tla400458 (adverb),
  tla550034 (adjective), tla550123 (particle), tla83460/83470/83500, and
  their root entries tla866216 / tla872102 — cross-shelf tests resolve
  `urn:nabu:dict:aed:tla550034` from an AES-shaped lemma reference, and
  `define nfr` exercises the homograph fan-out.
- **Root entries** (gramGrp `root/`, empty `<bibl/>`): tla863246,
  tla863258, tla866216, tla866258, tla867539, tla872102 — no bibl line,
  no citations, `rootOf` target lists (tla866216 lists 55).
- **Wb print citations**: page.line ("Wb 1, 1.1"), page-only
  ("Wb 1, 270", tla10010), ranges ("Wb 3, 5.14-20", tla100010;
  "Wb 2, 253.1-256.15"), the dot-after-volume quirk ("Wb 3. 293.2-6",
  tla118230; "Wb 4. 122.7-123.11", tla134370), multi-segment bibls whose
  non-Wb references (MedWb, KoptHWb, GDG, Meeks, LGG, FCD …) mint no
  citation rows (tla10, tla100, tla100000, tla851379).
- **Translation lanes**: German on every entry; English present and
  absent (tla10010, tla100150, tla863564 lack it); the two upstream
  oddballs — French (tla863564) and Italian (tla875429).
- **Cross-reference types**: root, rootOf, partOf, contains (multi-ref,
  tla83470), referencedBy (tla10130), referencing (tla101810),
  predecessor (tla106670, tla128690), successor (tla866258) — every type
  the 19,399-xr upstream census found.
- **Orthography quirks for the egy fold**: ꜣ (tla1), Ꜣ uppercase
  (tla100, tla103), ꜥ/ꜥꜣ (tla128690, tla866258), ʾ U+02BE (tla101340),
  the semivowel breve i̯ U+032F (tla100650), ṱ (tla867539), compound
  punctuation ḥw.t-kꜣ (tla100010), leading `=` clitic (tla10010), and
  the lone editorial 〈 〉 pair in the corpus (tla851379).

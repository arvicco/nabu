# CCL fixtures (P28-3 — the Coptic dictionary + the egy↔cop crosswalk)

Real upstream samples for the `ccl` source (CLAUDE.md fixture rules). Two
artifacts, mirroring the adapter's two-subdir canonical layout:

## lexicon/Comprehensive_Coptic_Lexicon-v1.2-2020.xml

Trimmed byte-verbatim slice of the **Comprehensive Coptic Lexicon v1.2**
TEI (BBAW "Strukturen und Transformationen des Wortschatzes der ägyptischen
Sprache" + FU Berlin DDGLC).

- **Record:** https://refubium.fu-berlin.de/handle/fub188/27813
  (handle fub188/27813, DOI 10.17169/refubium-27566, published 2020-07-16).
- **Retrieved:** 2026-07-18, from the bitstream URL
  `https://refubium.fu-berlin.de/bitstream/handle/fub188/27813/Comprehensive_Coptic_Lexicon-v1.2-2020.xml?sequence=1&isAllowed=y`
  (12,343,129 bytes, sha256
  `a6973c4f03116bce55efc4ad8e6ad1a3743d02f0bab2f23886a263a1dae8332b`).
- **License (record page, verbatim):** "Creative Commons: Namensnennung,
  Weitergabe unter gleichen Bedingungen", linked to
  `https://creativecommons.org/licenses/by-sa/4.0/`; DC meta
  `DC.rights = https://creativecommons.org/licenses/by-sa/4.0/` (DCTERMS.URI).
- **License (in-file, teiHeader availability, verbatim):** "Licence for this
  TEI document: Creative Commons, Attribution-ShareAlike 4.0 International
  (CC BY-SA 4.0)" (`<licence target="http://creativecommons.org/licenses/by-sa/4.0/">`).
- **Trim recipe:** the full prolog + teiHeader + `<text><body>` opening
  byte-verbatim, then these byte-verbatim blocks in upstream order, then the
  file's own `</body></text></TEI>` closing shape:
  - the first `<superEntry>` (entries C1–C5: `hom` homographs, `ⲁ⸗`
    U+2E17-marked pronominal forms, hyphenated prefix orths, an `<xr>`);
  - the C9+C10 `<superEntry>` (C9 is a demotic-only crosswalk id, plural
    inflected forms);
  - entry C16 (`type="foreign"`, `<etym>` note — a loanword entry;
    body-level upstream);
  - entry C74 (its crosswalk row carries a NEGATIVE demotic id;
    body-level upstream);
  - the C1494–C1500 `<superEntry>` (the ⲕⲁϩ homograph cluster — the e2e
    chain row C1494,159410,6439);
  - entry C11273 (the corpus's ONE `form[@type="lemma"]`-less entry,
    lifted out of its 27 KB 26-entry superEntry — both body-level and
    superEntry-nested entry shapes exist upstream; the entry's own bytes
    are verbatim).
  17 entries total; full census (2026-07-18): 11,284 entries, all with
  unique `xml:id="C<n>"`, 5,417 at body level + 5,867 inside 1,181
  id-less superEntries; exactly one entry lacks a lemma form; no orth
  folds to empty.

## crosswalk/digitizing_coptic_etymologies_coptic_list_entries.csv

Trimmed line-verbatim slice of ORAEC's Coptic-etymologies crosswalk.

- **Repo:** https://github.com/oraec/coptic_etymologies (HEAD
  `95d6316ab7bf65f8b594d94991f72125866ad843`, 2024-08-14).
- **Retrieved:** 2026-07-18, from
  `https://raw.githubusercontent.com/oraec/coptic_etymologies/main/digitizing_coptic_etymologies_coptic_list_entries.csv`
  (35,889 bytes, sha256
  `455bea27cc81b73f329235580e320514b67bf43e46bd9b936511cbfbf0e66f58`).
- **License (repo LICENSE file):** CC0 1.0 Universal (GitHub API spdx
  `CC0-1.0`). README, verbatim: "The mapping was created by the ORAEC
  project and is licensed under CC 0."
- **Columns (README):** CDO/CCL Coptic id, TLA hieroglyphic lemma id (as
  used in ORAEC), TLA demotic word id — either ancestor id may be empty,
  demotic ids may be negative. No header row; full census (2026-07-18):
  **2,177 data rows** (the survey's "2,176" was one short), all width 3,
  no duplicate C-ids, every C-id present in CCL v1.2; 1,345 rows carry
  both ancestors, 350 hieroglyphic-only, 482 demotic-only, 220 negative
  demotic ids.
- **Trim recipe:** the 6 rows (upstream order, bytes verbatim) whose C-id
  is one of C5 (hieroglyphic-only), C6 (its entry is NOT in the trimmed
  TEI — exercises the unused-row path), C9 (demotic-only), C74 (negative
  demotic id), C1494 and C1495 (both ancestors — the ⲕⲁϩ cluster).

## Attribution

Burns, Dylan Michael; Feder, Frank; John, Katrin; Kupreyev, Maxim:
*Comprehensive Coptic Lexicon: Including Loanwords from Ancient Greek*
(v1.2, 2020), BBAW / FU Berlin, DOI 10.17169/refubium-27566. Crosswalk:
ORAEC — Open Richly Annotated Egyptian Corpus, `coptic_etymologies`.

# sedra fixtures

A real, row-trimmed slice of the **Sedra V data release 5.0** — the Syriac
lexical database of Beth Mardutho: The Syriac Institute (edited by George A.
Kiraz and James Bennett), released 2026-10-24 "from the data of 2026-10-24",
retrieved 2026-11-22 from the release's one zip
`https://sedra.bethmardutho.org/releases/v5.0/sedra-2026-10-24.zip`
(13,604,317 B, sha256 `b1a0bca072f5766fbd44ac5368c1225f9a370957e7cdf9b025ea7e060dd7e89b`
— exactly the value `/releases/index.json` publishes). Every file is also
served singly under `https://sedra.bethmardutho.org/releases/v5.0/<name>`.
The layout mirrors `canonical/sedra/` after the fetch (ZipFetch strips the
zip's single `sedra-2026-10-24/` top directory); the release's own
`README.md` is quoted below rather than checked in (this file takes its
name).

## License (the release README, verbatim, read 2026-11-22)

> Copyright © 2011–2026 Beth Mardutho: The Syriac Institute. The data in this
> release is licensed under the Creative Commons Attribution-NonCommercial
> 4.0 International licence (CC BY-NC 4.0): you may share and adapt it for
> non-commercial purposes, giving credit to Sedra and Beth Mardutho.
> https://creativecommons.org/licenses/by-nc/4.0/

The README adds that "the resource partners require credit"; the release's
`CITATION.cff` says `license: "CC-BY-NC-4.0"`. → class `nc`. This small
attributed slice is redistributed for testing under those terms. Cite:
Sedra, edited by George A. Kiraz and James Bennett. Beth Mardutho: The Syriac
Institute. Data release 5.0 (2026), https://sedra.bethmardutho.org/releases/v5.0/.

## Delivery grains (the release README's own table)

| grain | files | taken? |
|---|---|---|
| Sedra V entry table | `lexemes.jsonl.gz` (35,892 rows) | **accepted** — one entry per lexeme, the one document ref |
| Sedra V joined tables | `roots` (3,465), `words` (65,000), `glosses` (67,692), `etymologies` (3,078) | **accepted** — joined into the lexeme entries |
| Sedra V lookups the rows reference | `sources`, `languages`, `category_types`, `kaylos`, `tenses`, `numbers`, `persons`, `genders`, `states` | **accepted** — names for the ids |
| the Sedra IV format | `sedra4/words`, `sedra4/lexemes`, `sedra4/roots` (.jsonl.gz), `sedra4/definitions.json`, `sedra4/semiticLanguages.xsd` | **skipped by rule** — the same rows "exactly as the Sedra IV API answered" |
| paradigm tables | `conjugation_templates` (2,559), `conjugations` (empty) | **skipped by rule** — patterns, not entries |
| unreferenced lookups | `stems` (no word row's `stem_id` is set), `vowels`, `authors`, `transliteration_schemes`, `transliteration_patterns` | **skipped by rule** |
| documentation | `README.md` | not content |

Every skipped grain is pinned here (12 files) and counted in
`discovery_skips` with its note. Not in the release at all (README "Not in
it"): the scans of printed lexicon entries, the Library texts, the generated
verb forms, unverified work.

## Census (the full release through the adapter, 2026-11-22)

1 document → **35,891 entries** (35,892 lexeme rows − row 28521, which has
an empty headword, one empty word form and no gloss — named in the
discovery notes, mints nothing); 66,451 glosses (1,241 of the 67,692 cells
hold no text — empty, spaces or a lone RLM), 3,078 etymology rows → 2,995
reflexes (83 name only a language), 64,999 word forms; 6,955 entries carry
no gloss. 0 errors.

## The slice (7 lexemes)

Lookup tables and the small rejected files are byte-identical copies. The
joined tables keep, verbatim, the rows belonging to these lexemes (each
re-gzipped; row order upstream's):

| lexeme | headword | why |
|---|---|---|
| 1 | ܐܐܪ "air" | English/French/Arabic glosses from three sources (Sedra III, Brock & Kiraz, Costaz), the Greek etymon ἀήρ, six word forms |
| 3 | ܐܒܗܘܬܐ "fatherhood" | a root (ܐܒ) with a single form |
| 225 | ܐܣܢ "store up" | a verb; French and Arabic gloss cells holding only a no-break space (absence) |
| 607 | ܓܢܣܐ "kind" | a `<span class="selectableFont">` gloss rendered to text; Greek γένος; the grammatical flag |
| 3469 | ܠܒܬܪܐ | a particle with no gloss rows; a suffixed form with suffix person/gender/number |
| 16413 | ܕܘܡܐ "Dumma" | a place name (Margoliouth Supplement) with an Arabic etymon |
| 28521 | (empty) | the headwordless row — the skip-by-rule specimen |

Roots kept: 1, 2, 169, 239, 389. `sedra4/lexemes` and `sedra4/roots` keep the
same lexemes' and roots' rows; `sedra4/words` and `conjugation_templates`
keep their first two rows.

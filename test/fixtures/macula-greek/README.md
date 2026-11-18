# macula-greek fixtures

Trimmed real excerpts of the MACULA Greek Linguistic Datasets
(github.com/Clear-Bible/macula-greek, © 2022-2024 Biblica, Inc, CC BY 4.0 —
"MACULA Greek Linguistic Datasets, available at
https://github.com/Clear-Bible/macula-greek/").

- Retrieved: 2026-11-18
- Pinned commit: `8423afe47b9e8f24b7772e808af45c7159a6fe7e` (main HEAD,
  2026-07-07). The TSV blob at that commit (`542e91a2`) was last regenerated
  at `076282a3` (2026-04-22).
- Source file: https://raw.githubusercontent.com/Clear-Bible/macula-greek/8423afe47b9e8f24b7772e808af45c7159a6fe7e/SBLGNT/tsv/macula-greek-SBLGNT.tsv
  (20,843,282 bytes, sha256 `7f71504fdee8659bdd9f85342e4103d645864c2851b8205915bb298f0c004cc5`;
  137,741 word rows, 27 books, 7,939 verses).

## Files

- `SBLGNT/tsv/macula-greek-SBLGNT.tsv` — the real 27-column header plus whole
  verse row-runs for Mark 1:1–3, John 1:1–2 and 21:23 (upstream's `ἀλλ’·`
  text-column quirk), and 3 John whole (315 word rows). Rows are byte-verbatim
  EXCEPT the `domain` and `ln` cells, blanked: they are the UBS MARBLE
  Louw-Nida data, which upstream's LICENSE.md marks "Used with permission"
  (a permission to MACULA, not a CC BY grant onward), so they are not
  republished here. The adapter excludes those columns at parse anyway; the
  exclusion test repopulates the cells in a tmp copy.
- `SBLGNT/tei/25-3john.xml` — upstream's TEI 3 John, whole (16,493 bytes):
  the pinned specimen of a REJECTED grain (counted skipped-by-rule).

## Column map (TSV header, in order)

| column | content | adapter |
|---|---|---|
| xml:id | word id `n<book 40–66><ch 3><v 3><word 3>` | token `id` |
| ref | `MRK 1:1!1` (book code, chapter:verse, !word) | passage urn + `citation` |
| role | clause role (s, v, o, p, vc, adv, io…) | token `role` |
| class / type | word class (noun, verb, det…) / subtype (common, proper, personal…) | token `class` / `type` |
| english / mandarin | Cherith glosses (CC BY 4.0, Andi Wu) | token `english` (the gloss-lane key) / `mandarin` |
| gloss | Berean interlinear contextual gloss (public domain) | token `gloss` |
| text / after | word text / following space or punctuation | token `form` / `trailer`; verse text = Σ(text + after) |
| lemma / normalized | lemma / normalized form | token `lemma` / `normalized` |
| strong | Strong's number | token `strong` |
| morph | Robinson-style code (`V-IAI-3S`) | token `morph` |
| person number gender case tense voice mood degree | spelled-out features | tokens, verbatim |
| domain / ln | UBS MARBLE Louw-Nida ("Used with permission") | **excluded at parse** |
| frame / subjref / referent | semantic frames, subject and participant referents (xml:id pointers) | tokens, verbatim |

## Upstream delivery grains

- `SBLGNT/tsv/` — one whole-NT word-level TSV. **Taken**; the document is the
  BOOK (cut by the ref column's book code), the passage the verse.
- `SBLGNT/lowfat/`, `SBLGNT/nodes/`, `SBLGNT/tei/` — per-book XML (syntax
  trees in two shapes; a flat TEI word list). **Rejected by rule**: the TSV
  carries the same words and the layers taken here. Fetch never downloads
  them; any `*.xml` found under the workdir counts in `discovery_skips` with
  a note. Specimen: `SBLGNT/tei/25-3john.xml`.
- `Nestle1904/` — the same layers over a different edition (Nestle 1904).
  Out of scope (a separate source if ever wanted).

# DCS fixture — Digital Corpus of Sanskrit (P26-0)

Trimmed, real samples of the DCS CoNLL-U dump: `OliverHellwig/sanskrit`,
path `dcs/data/conllu/` (NOT a separate "dcs-data" repo — docs/02-sources.md
row 7 was corrected under this packet).

- **Retrieved:** 2026-07-18, from commit `04e0778d3dc971030229179e25eea043d06ff397`
  (master), via a blobless sparse clone
  (`git clone --depth 1 --filter=blob:none --no-checkout` +
  `git sparse-checkout set --no-cone dcs/data/conllu/…`) — the same recipe the
  adapter's sparse fetch uses.
- **Layout:** the fixture mirrors the sparse workdir the adapter fetches:
  `dcs/data/conllu/{readme.md,lookup/chapter-info.xml,files/<Text>/<chapter>.conllu}`
  plus `dcs/data/readme.md` (the parent readme carrying the second license
  grant).

## Upstream census (at the pinned commit)

- `dcs/data/conllu/files/`: **270 text directories / 15,900 `.conllu` chapter
  files** (~844 MB), plus **7,227 `.conllu_parsed` siblings** — the AUTOMATIC
  annotation layers (`# layer=…` sentence comments), which the adapter must
  NEVER ingest — and one stray zero-byte extensionless file
  (`Skandapurāṇa (Revākhaṇḍa)-0229-…Chapter 230`, ignored by the `*.conllu`
  glob).
- `lookup/chapter-info.xml` (8.9 MB): 15,900 `<chapter>` entries. **Every one
  carries `<layer type="gold">lexicon</layer>` and
  `<layer type="gold">morpho-syntax</layer>`** (grep census at fixture time);
  1,780 additionally carry `<layer type="gold">syntax</layer>` (the Vedic
  Treebank subset, whose HEAD/DEPREL columns are filled — elsewhere `_`).
  This machine-readable declaration is what the adapter's gold gate reads.
- `dcs/data/conllu/readme.md` size claims: "Number of lines: 744,757 · Number
  of words: 5,464,818", and the gold statement: "The analysis of each string
  has been verified by one annotator."

## License (verbatim)

- `dcs/data/conllu/readme.md`: "The data in this directory are licensed under
  the Creative Commons BY 4.0 (CC BY 4.0) license."
- `dcs/data/readme.md`: "The data of the DCS and any data in child
  directories are licensed under the Creative Common BY 4.0 (CC BY 4.0)
  license."

Citation requested upstream: Oliver Hellwig, *The Digital Corpus of Sanskrit
(DCS)*, 2010–2024.

## Files and trims

| file | trim |
|---|---|
| `dcs/data/readme.md` | whole (byte-verbatim) |
| `dcs/data/conllu/readme.md` | whole (byte-verbatim) |
| `dcs/data/conllu/lookup/chapter-info.xml` | the three `<chapter>` entries for the fixture chapters, byte-verbatim, in the upstream `<info>` wrapper (8,858,624 B → 1.5 KB) |
| `files/Aitareyopaniṣad/Aitareyopaniṣad-0000-AU, 1, 1-8816.conllu` | whole, 35 sentence blocks (Vedic-Treebank chapter: gold syntax layer, filled HEAD/DEPREL, `<details>` metadata — register prose, veda RV, śākhā Āśvalāyana; sent_ids of the `NNNNNN_1` shape) |
| `files/Aitareyopaniṣad/…-8816.conllu_parsed` | first 2 sentence blocks (18 KB → 1.4 KB) — kept ONLY to pin that the adapter never discovers automatic-layer siblings |
| `files/Suśrutasaṃhitā/Suśrutasaṃhitā-0034-Su, Sū., 35-3363.conllu` | `##` header + first 3 blocks + the one block attesting lemma **aṃśa** (221,846 B → 38 KB, 4 of 107 blocks) — the MW headword-join witness (fold("aṃśa") = "amsa" = fold(SLP1 aMSa)) |
| `files/Suśrutasaṃhitā/Suśrutasaṃhitā-0115-Su, Ka., 4-3656.conllu` | `##` header + first 3 blocks + the 2 blocks attesting **kaṇṭha** + the 1 block attesting **śīghra** (189,133 B → 22 KB, 6 of 92 blocks) — the starling-piet IND-stem join witnesses (folds "kantha"/"sighra", scout-verified 7/7 2026-07-16/17); plain numeric sent_ids, MWT compound ranges (`5-6 kaṇṭhagrīvaṃ`), `_` HEAD/DEPREL (not in the Vedic Treebank), extra `# sent_counter`/`# sent_subcounter` comments |

Trims keep whole sentence blocks (header `##` lines ride in the first block)
— structurally intact for the streaming ConlluParser. Re-trim per this table
after any refresh.

## The lookup lane (dcs-lexicon / dcs-senses)

- **Retrieved:** 2026-10-17, cut from the held tree at upstream commit
  `8aeed5a1343d0e48b64eb32af8c00e8c6eb29359` (master) — the same sparse cone,
  same CC BY 4.0 grant. Exact LINES copied byte-verbatim (no edits); the
  cut is a line selection by upstream line number.
- **Upstream census (that commit):** `dictionary.csv` 180,458 lines (one
  newline-broken record: 39892 aiḍavi; 176 rows with an empty word);
  `word-senses.csv` 120,485 lines (header names 5 columns, rows carry 6; one
  newline-broken record: 127090 bāhyadruti); `sembank-relations.csv`
  194,529 lines, no header (17 pointer symbols + 5 junk codes, 11 rows);
  `sembank-attestations.xml` 14 MB / 22,474 concepts / 64,350
  lexicalizations — NOT well-formed XML (only the last `<concept>` closes;
  notes carry bare `<`), read line by line.

| file | trim |
|---|---|
| `lookup/dictionary.csv` | header + upstream lines 3217 (3562, the empty-word shape), 21997 (25207 bhūta), 34775–34778 (39891 aiḍaka, the broken 39892 aiḍavi pair, 39893 aiṇa), 44332 (50589 bhurij), 127327 (148105 bāhyadruti), 129599 (150748 prajā), 135216–135217 (157202 acchāgam: preverb + empty meanings; 157203 acchācar) and the 44242 nara / 87452 jana rows — every lemma the trimmed attestations cite |
| `lookup/word-senses.csv` | header + lines 2–6 (568 entity … 574 person, the WordNet-field-bearing row), 4993–4994 (5675 engagement / 5676 non-engagement), 109873–109874 (126807/126808, the junk-code pair), 110151–110152 (the broken 127090 bāhyadruti pair) |
| `lookup/sembank-relations.csv` | lines 1–3, 17–19, 50, 68, 75 (edges among the held senses + two to unheld 575/576), 296 (from unheld 575), 6679–6681 + 6685–6687 (the triplicated 5675⇄5676 antonym), 184751 (junk `77D15`), 185041 (103704 → 127090, from unheld) |
| `lookup/sembank-attestations.xml` | the `<corpus>` line + whole concept blocks 568, 569, 574, 127090 and the closing 147806 block (with upstream's only `</lexicalizations></concept>` and `</corpus>`); within 569/574 only the cited lexicalizations kept, each capped at its first 3 `<n>` lines (whole elements) |

Re-cut with the same line numbers after a refresh (re-census first: the
line numbers are commit-bound).

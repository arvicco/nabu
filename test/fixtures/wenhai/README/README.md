# The Digital Wenhai

*A Unicode-Compliant Dataset of Tangut Linguistics and Philology’s Backbone*

Version 1.1: Phonology  
Last updated: 2026-09-17

**Version 1.1 change:** restored the omitted *Wenhai* head `𗭹` at `83.251` with fanqie `𗪽𘂜`. Together with `84.232` (`𗪽𗰊`), the transitive lower-speller relations, shared `ToneRhyme` `1.80`, and shared upper speller `𗪽` support treating both occurrences as one phonological node. This merges the former rhyme chains `R-024` and `R-179` as `R-024`; the initial chain is unchanged, and later rhyme IDs are renumbered by anchor order.

## 1. Overview

This dataset provides a Unicode-compliant representation of:

1. the Tangut rhyme dictionary *Wenhai* 文海, whose precise compiler and date are unknown but which was already in existence during the second half of the eleventh century (see Hamada 2024).
2. its fanqie evidence and a graph-based reconstruction of the transitive equivalence chains implied by that evidence.

The first version of this dataset has two principal aims:

1. to make the *Wenhai* and its phonological evidence directly searchable, interoperable, and checkable in standard Unicode Tangut; and
2. to derive, independently of later phonological classifications, the connected sets of characters that the fanqie system treats as equivalent in initial and rhyme.

The graph-derived units are called **fanqie chains**. Some database field names use the term `ClassID`, which should be understood as a chain identifier (rather than as a phonological class).

The final validated dataset contains:

- **171 independent, non-overlapping identified initial fanqie chains**
- **321 independent, non-overlapping identified rhyme fanqie chains**
- **4 checked initial chains crossing TYYJ (Li 1986's 同音研究 *Tóngyīn yánjiū*) categories**
- **13 checked rhyme chains crossing distinct level-tone ToneRhymes**
- **6 unresolved equivalence dimensions**: 3 initial and 3 rhyme

The remaining cross-category chains have been individually checked against the document's facsimile and are intentionally preserved. They should not be interpreted as unresolved transcription errors, but instead as synchronic evidence.

---



## 2. Release contents

The release is designed to contain both convenient spreadsheet files and open, software-independent exports.

File layout:

```text
01_wenhai.xlsx
02_fanqie.xlsx
----
01_wenhai.csv
02a_fanqie_notes.csv
02b_fanqie_groups.csv
02c_fanqie_chains.csv
02d_fanqie_members.csv
02e_fanqie_links.csv
02f_fanqie_initial_cross.csv
02g_fanqie_rhyme_cross.csv
02h_fanqie_unresolved.csv
----
build_fanqie_chains.py
----
README.md
LICENSE.txt
CITATION.cff
CITATION.bib
```

The XLSX files are intended for convenient browsing in spreadsheet software. The CSV files are intended for programmatic reuse and long-term preservation. All CSV files should be stored as **UTF-8**. The supplied Python script accepts UTF-8 files with or without a byte-order mark.

The historical source facsimile and third-party fonts/resources are not redistributed as part of this dataset.

---



## 3. Sources and provenance

The database was constructed from the documentary structure and fanqie evidence of the *Wenhai* as given in Andrew West's BabelStone Tangut resources, themselves based on Shi Jinbo 史金波 et al., *Wenhai yanjiu* 文海研究 (1983). The evidence was repeatedly checked against the facsimile source materials using an app on my website (consultable [here](https://mbeaudouin.com/app_wenhai/appwenhai.html)), which greatly streamlined the process.

Legacy electronic Tangut material used Private Use Area (PUA) characters—except the heads, already available in Unicode. These were normalized to standard Unicode Tangut before the fanqie graph was constructed.

For characters embedded in fanqie spellings, the conversion procedure was:

```text
PUA code point
    ↓
WHYJIndex number
    ↓
Li Fanwen catalogue number
    ↓
Unicode Tangut code point
```

For the sequential WHYJIndex repertoire:

```text
WHYJIndex number = PUA code point − U+E000 + 1
```

No OCR or visual shape matching was used to determine Tangut character identity in this conversion process.

The original conversion and checking process was carried out in successive intermediate files; the present release contains the stabilized dataset rather than every intermediate workbook.

---



## 4. Tangut display requirements

The files contain standard Unicode Tangut characters.

To display them correctly, the operating system or application must have a font supporting Unicode Tangut. Suitable fonts are, for example, **[Tangut Yinchuan](https://www.babelstone.co.uk/Fonts/Yinchuan.html)** or **[Noto Serif Tangut](https://github.com/notofonts/tangut)**. The fonts themselves are not included in this repository.

A missing-glyph box in a user's software may not necessarily indicate missing data; it may simply indicate that the local font does not support Tangut. However, the square character `□`, when it occurs inside the dataset itself, represents an unreadable, missing, or unresolved character position in the source/fanqie and is therefore part of the data.

---



## 5. File `01_wenhai`



### 5.1 Purpose

`01_wenhai.xlsx` is the central row-based *Wenhai* database. It contains 3,085 records, with each row representing a database record tied to a *Wenhai* position. The table combines:

- source position and Unicode Tangut character;
- rhyme-system context;
- fanqie evidence where explicitly stated at that position;
- independent initial classification;
- graph-derived initial and rhyme chain IDs;
- phonological representations used in the project (GHC and MB).

A blank `Fanqie` cell does not necessarily mean that the character has no fanqie information. A fanqie statement may govern several successive positions and may be written only at the first position. The normalized inheritance of fanqie statements is made explicit in `02b_fanqie_groups`.

### 5.2 Columns


| Column           | Description                                                                                                                                                                                            | Possible values                   | References                                                                                        |
| ---------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | --------------------------------- | ------------------------------------------------------------------------------------------------- |
| `Cycle`          | Higher-order set in the rhyme-system organization used by the document and the database.                                                                                                               | Major, Minor1, Minor2, Minor3     | Sofronov (1968: 77)                                                                               |
| `She`            | Higher-order rhyme grouping used by the database, cross-cutting the cycles.                                                                                                                            | 1–9                               | Beaudouin (2023: 168, 177)                                                                        |
| `Subcycle`       | Subdivision within the rhyme organization of a She (usually the major cycle).                                                                                                                          | A, B                              | Gong Hwang-cherng (1994); Gong Xun (2021); Beaudouin (2023: 205–206)                              |
| `Grade`          | Grade category associated with the rhyme or, in a few cases, with a set of syllables within a rhyme.                                                                                                   | I, II, IIIa, IIIb                 | Hashimoto (1963); Gong Hwang-cherng (1994); Gong Xun (2020); Beaudouin & Honkasalo (under review) |
| `ToneRhyme`      | Numbered ToneRhyme assignment, e.g. `1.27`. The `1.xx` series is treated as level-tone evidence in the cross-rhyme analysis.                                                                           | `1.xx` (level); `3/4.xxx` (mixed) | Shi et al. (1983)                                                                                 |
| `RhymeName`      | Tangut character used as the rhyme label in the *Wenhai*.                                                                                                                                              | —                                 | —                                                                                                 |
| `WenhaiPos`      | Source position in the *Wenhai*. This is the principal key for returning from the database to the source.                                                                                              | —                                 | Shi et al. (1983); West (n.d.)                                                                    |
| `Tangut`         | Unicode Tangut head character / analytical node.                                                                                                                                                       | —                                 | —                                                                                                 |
| `LiFanwen`       | Catalogue number in Li Fanwen's *Xia-Han zidian* as used in the project.                                                                                                                               | —                                 | Li Fanwen (2008, 2012)                                                                            |
| `Fanqie`         | Unicode transcription of the fanqie statement explicitly written at that position. Full strings are preserved; the upper and lower phonological spellers are parsed separately in `02b_fanqie_groups`. | —                                 | Shi et al. (1983); West (n.d.)                                                                    |
| `InitialTYYJ`    | Independent TYYJ initial classification, I–IX, used to identify and test initial chains.                                                                                                               | I-IX                              | Li Fanwen (1986)                                                                                  |
| `InitialClassID` | Published identifier of the fanqie-derived initial chain.                                                                                                                                              | —                                 | —                                                                                                 |
| `RhymeClassID`   | Published identifier of the fanqie-derived rhyme chain.                                                                                                                                                | —                                 | —                                                                                                 |
| `GHC`            | Gong Hwang-cherng phonological representation as encoded in the project.                                                                                                                               | —                                 | Gong, Hwang-cherng (2002, 2003)                                                                   |
| `MB`             | Mathieu Beaudouin phonological representation used in the project.                                                                                                                                     | —                                 | Beaudouin (2023, 2025)                                                                            |




### 5.3 Source and analytical information

The evidential status of the columns is as follows:

- `RhymeName`, `WenhaiPos`, `Tangut`, and `Fanqie` represent the normalized documentary layer.
- `Cycle`, `She`, `Subcycle`, `Grade`, `ToneRhyme`, and `RhymeName` situate the entry within the rhyme organization of the document and the project.
- `InitialTYYJ` is independent classificatory evidence, and `LiFanwen` is independent identification notation.
- `InitialClassID` and `RhymeClassID` are derived from the fanqie graph.
- `GHC` and `MB` are phonological representations supplied for comparison and reuse.

Despite being used to assess cross-equivalences, `InitialTYYJ` and `ToneRhyme` do not determine graph connectivity.

---



## 6. Wenhai position and variant conventions



### 6.1 Suffixed WenhaiPos

Suffixed *Wenhai* positions such as:

```text
*
a
b
c
```

are treated as variants of a single announced underlying *Wenhai* position when they represent graphical variants. Letters distinguish separate `LiFanwen` entries for what appears to be the same character; `*` marks a genuine variant absent from the *Wenhai*.

Distinct graphical variants of the same announced position inherit the same initial and rhyme equivalence relations.

### 6.2 Pronunciation-specific nodes (suffixed Tangut)

Unicode character identity is not always identical to phonological reading identity.

Two pairs are deliberately kept separate:

- `𘅇a` = TYYJ III
- `𘅇b` = TYYJ V

and

- `𗼍a` = TYYJ VIII
- `𗼍b` = TYYJ VI

These are represented as distinct graph nodes.

### 6.3 Encoding decision for 𗾥

U+17FA5 is retained for `𗾥` in the *Wenhai*-documented TYYJ VII reading.

U+18D04 is not introduced merely to distinguish readings, because no corresponding separate *Wenhai* glyph could readily be established.

A further TYYJ VI reading of `𗾥` is known independently but is not documented in the *Wenhai* data represented here.

---



## 7. File `02_fanqie`

The second workbook contains the normalized fanqie groups, the derived graph structure, the final chains, and the checked exceptional cases.

The sheets are ordered conceptually as:

```text
Notes
→ Fanqie groups
→ Chains
→ Members
→ Links
→ Initial cross-class chains
→ Rhyme cross-class chains
→ Unresolved sets
```



### 7.1 `02a_fanqie_notes`

Summary of the methodological rules and final counts.

The Notes sheet is intended as a compact in-workbook reference. This README is the fuller documentation.

### 7.2 `02b_fanqie_groups`

One row per normalized fanqie statement/group.

Columns:


| Column               | Description                                                               |
| -------------------- | ------------------------------------------------------------------------- |
| `FanqieBase`         | Position at which the fanqie statement is explicitly written.             |
| `Fanqie`             | Full Unicode fanqie string.                                               |
| `Upper`              | Parsed upper fanqie speller, used in the initial graph when readable.     |
| `Lower`              | Parsed lower fanqie speller, used in the rhyme graph when readable.       |
| `Announced`          | Number of source positions announced as governed by the fanqie statement. |
| `Represented`        | Number of announced positions represented in the normalized database.     |
| `Governed positions` | Space-separated list of the *Wenhai* positions governed by the fanqie.    |
| `Members`            | Space-separated Unicode graph nodes governed by the fanqie.               |


`Members` and `Governed positions` are not necessarily one-to-one because graphical variants of a single announced position inherit the same fanqie relations and therefore receive the same initial and rhyme `ClassID`s.

This table is the principal normalized input for rebuilding the two graphs.

### 7.3 `02c_fanqie_chains`

One row per identified initial or rhyme chain.

Columns:


| Column                        | Description                                                                                                                                                  |
| ----------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `Graph`                       | `Initial` or `Rhyme`.                                                                                                                                        |
| `ClassID`                     | Published chain ID.                                                                                                                                          |
| `TYYJ`                        | TYYJ evidence associated with an initial chain. Mixed chains contain combined values such as `II+VIII`. Blank for rhyme chains.                              |
| `Status`                      | Identification basis. For initial chains this records the evidence used to anchor the component, notably upper-speller evidence. Blank where not applicable. |
| `Size`                        | Number of distinct nodes in the connected component.                                                                                                         |
| `Anchor`                      | Unicode-smallest node in the component.                                                                                                                      |
| `Members`                     | Space-separated list of all nodes in the chain.                                                                                                              |
| `UpperSpellers`               | Upper spellers occurring as identification evidence in an initial component. Blank for rhyme rows.                                                           |
| `Upper-speller TYYJ evidence` | Explicit `character=TYYJ` evidence for the upper spellers. Blank for rhyme rows.                                                                             |




### 7.4 `02d_fanqie_members`

Long-form chain membership table.

Columns:


| Column    | Description                             |
| --------- | --------------------------------------- |
| `Graph`   | `Initial` or `Rhyme`.                   |
| `ClassID` | Published chain ID.                     |
| `Member`  | One graph node belonging to that chain. |


This sheet is convenient for character-based lookup and joins.

### 7.5 `02e_fanqie_links`

The direct graph edges from which the connected components are obtained.

Columns:


| Column         | Description                                                                                      |
| -------------- | ------------------------------------------------------------------------------------------------ |
| `Graph`        | `Initial` or `Rhyme`.                                                                            |
| `Relation`     | Type of direct edge, including `co-governed`, `upper speller`, or `lower speller` as applicable. |
| `ClassID`      | Chain containing the edge.                                                                       |
| `Node`         | First endpoint of the edge.                                                                      |
| `LinkedTo`     | Second endpoint.                                                                                 |
| `FanqieBase`   | Position of the fanqie statement responsible for the relation.                                   |
| `GovernedBase` | Governed source position represented by the edge.                                                |


A chain is a **transitive connected component**. Two members of the same chain need not be linked directly. Use this sheet to inspect the actual topology of a chain.

For co-governed sets, a minimal star representation is sufficient to encode mutual equivalence for connected-component purposes and avoids storing every redundant pair in a clique.

### 7.6 `02f_fanqie_initial_cross`

The four checked initial chains that contain independent evidence from more than one TYYJ category.

Columns:


| Column              | Description                                                    |
| ------------------- | -------------------------------------------------------------- |
| `ClassID`           | Mixed initial-chain ID.                                        |
| `TYYJ`              | TYYJ categories represented in the chain.                      |
| `Size`              | Number of nodes.                                               |
| `Anchor`            | Unicode-smallest member.                                       |
| `Members`           | All nodes in the chain.                                        |
| `Evidence`          | TYYJ evidence within the chain.                                |
| `Chain junction(s)` | Direct fanqie edge(s) at which different TYYJ categories meet. |


The four final chains are:

- `II+VIII-01`
- `II+VIII-02`
- `II+VIII-03`
- `III+IV+VII-01`



### 7.7 `02g_fanqie_rhyme_cross`

The thirteen checked rhyme chains containing more than one distinct **level-tone** ToneRhyme.

Columns:


| Column              | Description                                                                                       |
| ------------------- | ------------------------------------------------------------------------------------------------- |
| `ClassID`           | Rhyme-chain ID.                                                                                   |
| `Level ToneRhymes`  | Distinct `1.xx` ToneRhymes represented in the chain.                                              |
| `Other ToneRhymes`  | Additional non-level ToneRhyme evidence (`3.xxx`, `4.xxx`, etc.) occurring in the same component. |
| `Size`              | Number of nodes.                                                                                  |
| `Anchor`            | Unicode-smallest member.                                                                          |
| `Members`           | All nodes in the chain.                                                                           |
| `Evidence`          | Distribution of members by ToneRhyme.                                                             |
| `Chain junction(s)` | Direct lower-speller edge(s) responsible for the cross-rhyme connection.                          |


Only differences between distinct `1.xx` ToneRhymes count as cross-rhyme cases in this dataset (a chain containing one `1.xx` rhyme plus one or more `3.xxx`/`4.xxx` values is not counted as a level-tone cross-rhyme case).

The thirteen final pairs are:

- R-001: 1.49 ↔ 1.89
- R-011: 1.10 ↔ 1.11
- R-024: 1.63 ↔ 1.80
- R-034: 1.30 ↔ 1.92
- R-036: 1.27 ↔ 1.68
- R-059: 1.57 ↔ 1.91
- R-069: 1.03 ↔ 1.59
- R-085: 1.36 ↔ 1.61
- R-092: 1.23 ↔ 1.83
- R-114: 1.34 ↔ 1.38
- R-138: 1.64 ↔ 1.82
- R-147: 1.09 ↔ 1.67
- R-233: 1.69 ↔ 1.92



### 7.8 `02h_fanqie_unresolved`

Equivalence sets whose connectivity is established by the source but for which the relevant dimension has no readable speller edge anchoring it to an identified chain.

Columns:


| Column       | Description                                                        |
| ------------ | ------------------------------------------------------------------ |
| `Graph`      | `Initial` or `Rhyme`.                                              |
| `FanqieBase` | Source fanqie position.                                            |
| `Fanqie`     | Fanqie string, including unreadable placeholders where applicable. |
| `Members`    | Co-governed members known to be equivalent.                        |
| `Status`     | Explanation of why the set remains unresolved.                     |


The final dataset contains **six unresolved equivalence dimensions**:

- 3 initial
- 3 rhyme

The absence of a `ClassID` does not mean that no equivalence is known at all. It means that the equivalence cannot presently be attached to an independently anchored transitive chain.

---



## 8. Graph construction

Two undirected graphs are constructed: an **initial graph** and a **rhyme graph**.

### 8.1 Core equivalence rule

All characters governed by the same fanqie statement are treated as equivalent in **both initial and rhyme**, even when one or both fanqie spellers are unreadable.

If a fanqie statement governs A, B, and C:

```text
A ≡ B ≡ C
```

in both dimensions.

### 8.2 Initial graph

When the upper speller X is readable, every governed character is connected to X:

```text
A — X
B — X
C — X
```



### 8.3 Rhyme graph

When the lower speller Y is readable, every governed character is connected to Y:

```text
A — Y
B — Y
C — Y
```



### 8.4 Connected components

The fanqie chains are the connected components of these graphs.

Connectivity is transitive. If:

```text
A — B
B — C
```

then A, B, and C belong to the same chain even if A and C never occur together in a single fanqie statement.

### 8.5 Independence from external classifications

The graph topology is determined **only** by fanqie relations.

TYYJ and ToneRhyme information are introduced afterwards to:

- identify components;
- compare graph structure with traditional/independent classifications;
- locate possible errors;
- isolate genuine cross-category equivalences.

No fanqie-derived connected component is split merely to force agreement with TYYJ or ToneRhyme.

---



## 9. Chain identification and numbering



### 9.1 Initial chains

Initial chains are identified preferentially through independently assigned TYYJ values of readable upper spellers.

Where a component contains verified evidence from more than one TYYJ category, the categories are preserved in the identifier, for example:

```text
II+VIII-01
III+IV+VII-01
```



### 9.2 Rhyme chains

Rhyme chains are labelled:

```text
R-001
R-002
...
```



### 9.3 Anchor and ordering

Each chain receives an `Anchor`, defined as the member with the smallest Unicode ordering.

`InitialClassID` and `RhymeClassID` numbering follows the Unicode order of these anchors.

This makes the IDs deterministic for a fixed graph.

---



## 10. Manual checking and intervention categories

Not every manual change made during the project has the same evidential status. 

### 10.1 Corrections to the transcribed Wenhai fanqie evidence

These are genuine corrections to the source transcription and alter graph topology.

**Upper-speller corrections**

1. **07.252 𗪞**: `𗿷 → 𗫔`
  Corrected fanqie: `𗫔𘄀𘈖𗍫`
2. **49.161 𘘅**: `𘐁 → 𗥊`
  Corrected fanqie: `𗥊𗒘`
3. **52.231 group**: `𗼞 → 𗣔`
  Corrected fanqie: `𗣔𘈩𘈖𘉋`
4. **55.113 𗆧**: `𗦖 → 𗦙`
  Corrected fanqie: `𗦙𗞌`
5. **91.212 group**: `𗦷 → 𗿀`
  Corrected fanqie: `𗿀𗈡𘈖𗍫`

**Lower-speller corrections**

1. **78.262 𗦩**: `𘏹 → 𘏆`
  Corrected fanqie: `𘓞𘏆`
2. **89.253 𗭡**: `𘊬 → 𘊭`
  Corrected fanqie: `𗊋𘊭𗨁`

**Speller-order correction**

1. **70.112 𘔢**:
  `𘏈𗝎 → 𗝎𘏈`

These eight changes are the project's genuine manual corrections to the fanqie transcription.

### 10.2 Corrections and additions to external TYYJ metadata

These do not change what the *Wenhai* says. They change the independent evidence used to identify or evaluate initial chains.

A dedicated review investigated **88 apparent upper-speller cases lacking an established TYYJ assignment**:

- **83** inferred assignments were independently confirmed;
- **5** cases instead proved to be the upper-speller transcription errors listed above.



### 10.3 Version 1.1 correction to the electronic structure

Version 1.1 restores a *Wenhai* head omitted from Version 1.0: `𗭹` at `83.251`, with fanqie `𗪽𘂜`. The same Unicode character also occurs as a head at `84.232`, with fanqie `𗪽𗰊`.

The two occurrences are treated as one phonological node. The transitivity of their lower-speller relations, their shared `ToneRhyme` `1.80`, and their shared upper speller `𗪽` jointly support a single syllable rather than distinct readings. Restoring `83.251` therefore merges the former rhyme chains `R-024` and `R-179`; the initial chain remains unchanged. Because rhyme-chain IDs are ordered by Unicode anchor, the former `R-180`--`R-322` are renumbered `R-179`--`R-321`.

---



## 11. Quality control

The graph itself was used as a diagnostic instrument.

Unexpected cross-TYYJ or cross-ToneRhyme components were localized to the particular fanqie edge responsible for joining the categories. The corresponding source passage or external phonological assignment was then checked.

After a genuine speller correction, the affected graph was recomputed rather than patched locally, as one corrected edge can change an entire transitive component.

The iterative checking process reduced earlier apparent discrepancies to the final validated structure:


| Measure                               | Final count |
| ------------------------------------- | ----------- |
| Identified initial chains             | 171         |
| Identified rhyme chains               | 321         |
| Checked cross-TYYJ initial chains     | 4           |
| Checked level-tone cross-rhyme chains | 13          |
| Unresolved equivalence dimensions     | 6           |


The reproducibility script independently reconstructs:


| Graph   | Total components | Identified | Unresolved |
| ------- | ---------------- | ---------- | ---------- |
| Initial | 174              | 171        | 3          |
| Rhyme   | 324              | 321        | 3          |


The difference between total and identified components consists exactly of the unresolved components.

---



## 12. Reproducing the graph computation

The release includes:

```text
build_fanqie_chains.py
```

The script requires only the **Python standard library**.

Recommended Python version:

```text
Python 3.10 or later
```

Inputs:

```text
01_wenhai.csv
02b_fanqie_groups.csv
```

Run:

```bash
python build_fanqie_chains.py \
  --wenhai 01_wenhai.csv \
  --groups 02b_fanqie_groups.csv \
  --outdir derived_graphs \
  --strict
```

`--strict` checks the output against the final published component counts.

Expected summary:

```text
Initial:
  total components = 174
  identified       = 171
  unresolved       = 3

Rhyme:
  total components = 324
  identified       = 321
  unresolved       = 3

validation problems = 0
```

Generated outputs:

```text
derived_graphs/
├── initial_edges.csv
├── rhyme_edges.csv
├── initial_components.csv
├── rhyme_components.csv
├── component_members.csv
├── unresolved_components.csv
└── summary.json
```

The script deliberately attaches the published `InitialClassID` and `RhymeClassID` after computing graph components. The IDs are validation annotations, not inputs determining topology.

The script uses a union-find/disjoint-set implementation and does not require NetworkX, pandas, Excel, or proprietary software.

---



## 13. Known limitations

1. **Source preservation**
  Despite the care taken in its construction, this dataset is a normalized analytical representation, not a replacement for consultation of the original *Wenhai* documents. The source can readily be consulted through the author's [app](https://mbeaudouin.com/app_wenhai/appwenhai.html).
2. **Unreadable fanqie material**
  Some fanqie spellers remain unreadable (`□`). Co-governed equivalence can still be established even when a speller is unavailable, but such sets may remain unanchored in one or both dimensions in the absence of co-governance.
3. **Chain ≠ direct statement**
  Members of one chain may be connected only transitively. Direct evidence must be checked in `02e_fanqie_links`.

---



## 14. Reuse

Potential uses include:

- reassessment of Tangut initial and rhyme systems;
- checking proposed Tangut phonological reconstructions against indigenous fanqie evidence;
- integration with Tangut lexical or pronunciation databases;
- comparison with transcriptional evidence from Chinese, Tibetan, Sanskrit, or other sources;
- reproducible testing of alternative analytical hypotheses without retranscribing the *Wenhai*;
- expansion into a complete digital dataset of the entire Wenhai evidence (including character construction and definitions).

---



## 15. Citation

Please cite the archived dataset using:

> Beaudouin, Mathieu. 2026. *The Digital Wenhai: A Unicode-Compliant Dataset of Tangut Linguistics and Philology’s Backbone*. Version 1.1: Phonology. Zenodo. [doi.org/10.5281/zenodo.22256047](https://doi.org/10.5281/zenodo.22256047)

If a peer-reviewed data paper is published, users may cite both the dataset DOI and the data paper.

---



## 16. Licence

The dataset and documentation are licensed under the **Creative Commons Attribution 4.0 International Licence (CC BY 4.0)**. The accompanying Python code is licensed under the **MIT License**. See `LICENSE.txt` for licensing information and scope.

Neither licence applies to third-party source editions, facsimiles, fonts, or external resources cited below; those materials remain subject to their respective rights and licensing terms.

---



## 17. References and external resources

Arakawa, Shintarō 荒川慎太郎. 1997. “西夏語通韻字典.” *Gengogaku Kenkyū* 16: 1–151.

Beaudouin, Mathieu. 2023. Grammaire du tangoute: Phonologie et morphologie. Doctoral dissertation, Institut national des langues et civilisations orientales (Inalco).

Beaudouin, Mathieu. 2025. “The Paths to Rhotacization in Tangut, with New Evidence from Qiangic.” In *New Discoveries in Tibeto-Burman Linguistics: Honoring the Legacy of Academician Jackson T.-S. Sun*, edited by Jonathan P. Evans, 143–184. Language and Linguistics Monograph Series 69. Taipei: Institute of Linguistics, Academia Sinica.

Beaudouin, Mathieu, and Sami Honkasalo. Under review. *Rhotics, Rhoticity, and Transphonologization in Trans-Himalayan Historical Phonology: Reconstructing Forward Tangut Grade II*. Manuscript.

Gong, Hwang-cherng 龔煌城. 1981. “西夏韻書《同音》第九類聲母的擬測.” *Bulletin of the Institute of History and Philology, Academia Sinica* 52(1): 17–36.

Gong, Hwang-cherng 龔煌城. 1994. “A Hypothesis of Three Grades and Vowel Length Distinction in Tangut.” *Journal of Asian and African Studies* 46–47: 305–314.

Gong, Hwang-cherng 龔煌城. 2002. 西夏語文研究論文集. Language and Linguistics Monograph Series C2-1. Taipei: Institute of Linguistics (Preparatory Office), Academia Sinica.

Gong, Hwang-cherng 龔煌城. 2003. “Tangut.” In *The Sino-Tibetan Languages*, edited by Graham Thurgood and Randy J. LaPolla, 602–620. London and New York: Routledge.

Gong, Xun 龔勳. 2020. “Uvulars and Uvularization in Tangut Phonology.” *Language and Linguistics* 21(2): 175–212.

Gong, Xun 龔勳. 2021. “Nasal Preinitials in Tangut Phonology.” *Archiv orientální* 89(3): 443–482.

Hamada, Takeshi 濱田武志. 2024. “『文海』の「偽平声」から見る西夏語音韻学の複層性――西夏文字の字音推定の限界の所在について――.” *Gengo Kenkyu* 165: 59–84.

Hashimoto, Mantarō 橋本萬太郎. 1963. “タングート語（西夏語）の「韻」の組織について.” *Tōhō Gaku* 25: 83–105.

Jacques, Guillaume. 2014. *Esquisse de phonologie et de morphologie historique du tangoute*. Languages of Asia 12. Leiden: Global Oriental.

Li Fanwen 李範文. 1986. 同音研究. Yinchuan: Ningxia Renmin Chubanshe.

Li Fanwen 李範文, with additions and revisions by Jia Changye 賈常業. 2008. 夏漢字典. Revised edition. Beijing: Zhongguo Shehui Kexue Chubanshe.

Li Fanwen 李範文. 2012. 簡明夏漢字典. Beijing: Zhongguo Shehui Kexue Chubanshe.

Shi Jinbo 史金波, Bai Bin 白濱, and Huang Zhenhua 黃振華. 1983. 文海研究. Beijing: Zhongguo Shehui Kexue Chubanshe.

Sofronov, Mikhail V. 1968. *Грамматика тангутского языка*. 2 vols. Moscow: Nauka.

The Unicode Consortium. 2025. *The Unicode Standard, Version 17.0.0*. South San Francisco: The Unicode Consortium. [https://www.unicode.org/versions/Unicode17.0.0/](https://www.unicode.org/versions/Unicode17.0.0/).

West, Andrew. n.d. “Sea of Characters (文海).” *BabelStone*. Accessed September 2, 2026. [https://www.babelstone.co.uk/Tangut/Wenhai.html](https://www.babelstone.co.uk/Tangut/Wenhai.html).

---



## 18. Contact

**Mathieu Beaudouin**

[mb2810@cam.ac.uk](mailto:mb2810@cam.ac.uk)

If you find needed corrections to the dataset, please report:

- the relevant `WenhaiPos`;
- the affected Tangut character;
- the relevant fanqie or chain ID;
- the proposed correction;
- the documentary or phonological evidence supporting it.

Suggestions of corrections should distinguish clearly between source transcription, external phonological metadata, electronic structure, and modelling/encoding convention.

Thank you!
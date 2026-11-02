---
license: cc0-1.0
task_categories:
- image-to-text
language:
- bo
tags:
- ocr
- tibetan
- pecha
- woodblock
pretty_name: "Tibetan OCR — ALL-BDRC-alignments (ACIP Sungbum, woodblock uchen)"
size_categories:
- 10K<n<100K
configs:
- config_name: default
  data_files:
  - split: train
    path: "data/train-*.parquet"
---

# Tibetan OCR — ALL-BDRC-alignments

<!-- DRAFT. Flagship training set (CC0-ready). Numbers measured 2026-09-01.
     Public release name: ALL-BDRC-alignments (Asian Legacy Library + BDRC). -->

**79,572 page images of Tibetan woodblock prints (uchen) aligned page-by-page with
hand-verified Unicode transcriptions, line breaks preserved.** Transcriptions come
from the Asian Classics Input Project (ACIP) *Sungbum* corpus via the
[Asian Legacy Library (ALL)](https://asianlegacylibrary.org/), normalized to Unicode
and manually matched to BDRC scans. This is the largest clean uchen woodblock set in
the BDRC Tibetan OCR release — released jointly by the **Asian Legacy Library (ALL)**
and **BDRC**, hence the name **ALL-BDRC**.

Part of the **BDRC Tibetan OCR** release; see the model
[`BDRC/tibetan-ocr`](https://huggingface.co/BDRC/tibetan-ocr) and the
[evaluation benchmark](https://huggingface.co/datasets/BDRC/tibetan-ocr-benchmark).

## At a glance

| | |
|---|---|
| Images (pages) | **79,572** aligned pages |
| Total size | **12.64 GiB** |
| Volumes | 232 image volumes · 1,118 transcription volumes / alignment records |
| Works | 119 collected-works sets (*gsung 'bum*) |
| Script | **uchen** (79,370) + a little u-med (202) |
| Technology | woodblock (72,571) · modern (4,565) · manuscript (2,436) |
| Line breaks preserved | **Yes** (all 79,572) |
| Source of images | BDRC + Asian Legacy Library scans |
| Source of transcriptions | ACIP Sungbum via Asian Legacy Library (TEI → Unicode) |
| License | **CC0-1.0** |

## How it was made

The transcriptions were made by ACIP mostly from blockprints and manuscripts that
also exist in the BDRC collection, but no link existed between the two databases.
This dataset is the result of three manual steps, carried out by multiple annotators
over roughly three months in a collaboration between **BDRC** and
[**Dharmaduta**](https://dharmaduta.in/):

1. **Transcription normalization** — the original ACIP files were converted to
   TEI/XML and then to plain Unicode strings representing the original transcription,
   with **no emendations or markup**.
2. **Identification** — each ACIP transcription was matched to a BDRC scan, mostly by
   manual search. Only matches of the **exact** version (block print / manuscript)
   were kept.
3. **Alignment** — transcription and images were aligned **page by page**, by hand.
   No changes were made to the transcriptions, and only **exact transcriptions of the
   full image** were kept.

## Sources & collections

The scans come from the following BDRC image collections:

| Collection | Images |
|---|---|
| [Gene Smith's Personal Collection](https://purl.bdrc.io/resource/PR3KG13) | 61,863 |
| [PL480 collection](https://purl.bdrc.io/resource/PR1PL480) | 34,048 (overlaps others) |
| [National Library of Mongolia](https://purl.bdrc.io/resource/PR1NLM00) | 5,525 |
| [Library of Tibetan Works and Archives (LTWA)](https://purl.bdrc.io/resource/PR1LTWA00) | 1,356 |
| [Collection of Dr Lokesh Chandra](https://purl.bdrc.io/resource/PR1LOKESH01) | 787 |
| [Sera Jey Rigzod Chenmo](https://purl.bdrc.io/resource/PR3KG1) | 673 |

## Contents & schema

One row per page. Columns:

| Column | Description |
|---|---|
| `image` | embedded page scan (HF `Image`) |
| `transcription` | Tibetan Unicode, original line breaks preserved |
| `id` | unique row id |
| `mw_id` | BDRC version id of the source volume (e.g. `MW635`) |
| `technology` | `woodblock` / `modern` / `manuscript` |
| `script` | `uchen` / `ume` |
| `script_4` | writing-style family (when available) |

```python
from datasets import load_dataset
ds = load_dataset("BDRC/ALL-BDRC-alignments", split="train")
print(ds[0]["transcription"]); ds[0]["image"]
```

> **Note:** some source scans are very high resolution. For training and inference we
> recommend capping the long side (e.g. ≤ 5000 × 2500 px).

## Splits

Single `train` split (this is a training resource). For held-out evaluation use the
separate [BDRC Tibetan OCR benchmark](https://huggingface.co/datasets/BDRC/tibetan-ocr-benchmark).

## How the images are packaged

Embedded image bytes in sharded Parquet (HF `datasets` `Image` feature); the viewer
renders them and `load_dataset` streams them.

## License, attribution & image rights

- **License: CC0-1.0** — use, modify, redistribute freely.
- **Attribution requested (not required):** please cite the **Buddhist Digital
  Resource Center (BDRC)** and the **Asian Legacy Library (ALL)**.
- **⚠ Image-rights disclaimer:** BDRC claims no copyright over the scans and ALL
  claims none over the transcriptions, but **verifying the copyright status of each
  underlying original book is the user's responsibility**. Neither BDRC nor ALL can be
  held liable for misuse of the data by third parties.

## Credits

Transcriptions by the Asian Classics Input Project (ACIP) via the Asian Legacy Library. 
Alignments produced for BDRC by Dharmaduta. Manuscript identification: Tenzin Rabten, Sonam Gyal,
Lhujam Gyal, Jampa Gonpo, Tsethar Dolma. Page-by-page alignment: Gade, Kunsang,
Lekshey Gyatso, Kaldhen, Choying Tenpa. Funded by the **Khyentse Foundation**
("The BDRC Etext Corpus").

## Citation

```bibtex
@misc{bdrc_all_bdrc_alignments_2026,
  title  = {Tibetan OCR --- ALL-BDRC-alignments (ACIP Sungbum, woodblock uchen)},
  author = {Buddhist Digital Resource Center and Asian Legacy Library},
  year   = {2026},
  howpublished = {Hugging Face},
  note   = {https://huggingface.co/datasets/BDRC/ALL-BDRC-alignments}
}
```

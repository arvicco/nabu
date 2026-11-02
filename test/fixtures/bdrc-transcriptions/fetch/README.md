---
license: cc0-1.0
task_categories:
- image-to-text
language:
- bo
tags:
- ocr
- tibetan
- manuscript
- dbu-med
- bon
pretty_name: "Tibetan OCR — Berkeley (dbu-med manuscripts)"
size_categories:
- 1K<n<10K
configs:
- config_name: default
  data_files:
  - split: train
    path: "data/train-*.parquet"
---

# Tibetan OCR — Berkeley

<!-- DRAFT. Kurt Keutzer (UC Berkeley) contributed transcriptions. Numbers measured 2026-08-18. -->

**8,866 page images of Tibetan text with page-level Unicode transcriptions**, mostly
dbu-med (u-med) manuscripts with a small woodblock (uchen) portion.

These works were transcribed by Geshe Dangsong Namgyal, from 2016 to 2026, in his role as a Data System Analyst at University of California, Berkeley. 
This work was initiated by Prof. Kurt Keutzer with the longstanding hope of producing training data for Handwritten Text Recognition for dbu med and OCR of blockprint of Tibetan.

The transcriptions focus on readability of the produced text rather than fidelity to the image. The orthographic shorthands are thus expanded to their full form, and some transcriptions might still contain some markup to represent emendations and inserts.

The data provided here is a modified version of the original files with the following changes:
- alignment image by image reviewed manually
- line breaks added manually
- manual filtering of transcriptions judged too distant from the enscribed text

These changes were implemented in a collaboration between BDRC and [Dharmaduta](https://dharmaduta.in) in the context of the project "The BDRC Etext Corpus", a grant by the Khyentse Foundation.

Part of the **BDRC Tibetan OCR** release; see the model
[`BDRC/tibetan-ocr`](https://huggingface.co/BDRC/tibetan-ocr) and the
[evaluation benchmark](https://huggingface.co/datasets/BDRC/tibetan-ocr-benchmark).

## At a glance

| | |
|---|---|
| Images (pages) | **8,866** |
| Total size | **1.88 GiB** |
| Script | **u-med** (8,547) + uchen (319) |
| Technology | manuscript (8,547) · woodblock (319) |
| Writing styles (`script_4`) | danyig/pedri (4,084) · druma (2,928) · gyuyig/tsugdri (899) · multi-script (552) · other/blank (78) |
| Source of images | BDRC scans |
| Source of transcriptions | contributed via Prof. Kurt Keutzer (UC Berkeley) |
| License | **CC0-1.0** |

## Contents & schema

One row per page. Columns:

| Column | Description |
|---|---|
| `image` | embedded page scan (HF `Image`) |
| `transcription` | Tibetan Unicode ground truth |
| `id` | unique row id |
| `mw_id` | BDRC version id of the source volume |
| `technology` | `manuscript` / `woodblock` |
| `script` | `ume` / `uchen` |
| `script_4` | writing-style family (when available) |

```python
from datasets import load_dataset
ds = load_dataset("BDRC/berkeley", split="train")
print(ds[0]["transcription"]); ds[0]["image"]
```

## Splits

Single `train` split (training resource). For held-out evaluation use the separate
[BDRC Tibetan OCR benchmark](https://huggingface.co/datasets/BDRC/tibetan-ocr-benchmark).

## License, attribution & image rights

- **License: CC0-1.0** — use, modify, redistribute freely.
- **Attribution requested (not required):** please cite the **Buddhist Digital
  Resource Center (BDRC)** and **Prof. Kurt Keutzer (UC Berkeley)**.
- **⚠ Image-rights disclaimer:** BDRC claims no copyright over the scans, but
  verifying the copyright status of each underlying original book is the user's
  responsibility.

## Citation

```bibtex
@misc{bdrc_berkeley_2026,
  title  = {Tibetan OCR --- Berkeley (dbu-med manuscripts)},
  author = {Kurt Keutzer, Geshe Dangsong Namgyal and Buddhist Digital Resource Center},
  year   = {2026},
  howpublished = {Hugging Face},
  note   = {https://huggingface.co/datasets/BDRC/berkeley}
}
```

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
pretty_name: "Tibetan OCR — Palri Parkhang (dbu-med manuscripts)"
size_categories:
- 10K<n<100K
configs:
- config_name: default
  data_files:
  - split: train
    path: "data/train-*.parquet"
---

# Tibetan OCR — Palri Parkhang

<!-- DRAFT. Transcriptions by Palri Parkhang. Numbers measured 2026-08-18. -->

**11,133 page images of Tibetan text with page-level Unicode transcriptions**, mostly
dbu-med (u-med) manuscripts with a small uchen portion. 

The transcriptions were
produced by **Palri Parkhang**, an input project led by Chris Tomlinson (former BDRC's CTO) in Nepal in 2006-2013 and aligned to BDRC scans; the material is largely
Nyingma collected works and *gter ma* cycles. The transcriptions prioritized legibility over fidelity to the enscribed text and all the orthographic shorthands in the original are expanded in the transcription.

The original etexts were already distributed by [BDRC](http://purl.bdrc.io/resource/PR0ET006), this is a version that includes the following changes:
- etext aligned page by page with the images, checked manually
- line breaks inserted manually
- manual filtering of pages that are deemed too distant from the original scans

These changes were implemented in a collaboration between BDRC and [Dharmaduta](https://dharmaduta.in) in the context of the project "The BDRC Etext Corpus", a grant by the Khyentse Foundation.

Part of the **BDRC Tibetan OCR** release; see the model
[`BDRC/tibetan-ocr`](https://huggingface.co/BDRC/tibetan-ocr) and the
[evaluation benchmark](https://huggingface.co/datasets/BDRC/tibetan-ocr-benchmark).

## At a glance

| | |
|---|---|
| Images (pages) | **11,133** |
| Total size | **1.79 GiB** |
| Script | **u-med** (10,341) + uchen (792) |
| Technology | manuscript (11,133) |
| Writing styles (`script_4`) | danyig/pedri (6,786) · multi-script (2,763) · gyuyig/tsugdri (586) · druma (176) · other/blank (27) |
| Source of images | BDRC scans |
| Source of transcriptions | Palri Parkhang |
| License | **CC0-1.0** |

## Contents & schema

One row per page. Columns:

| Column | Description |
|---|---|
| `image` | embedded page scan (HF `Image`) |
| `transcription` | Tibetan Unicode ground truth |
| `id` | unique row id |
| `mw_id` | BDRC version id of the source volume |
| `technology` | `manuscript` |
| `script` | `ume` / `uchen` |
| `script_4` | writing-style family (when available) |

```python
from datasets import load_dataset
ds = load_dataset("BDRC/palri-parkhang", split="train")
print(ds[0]["transcription"]); ds[0]["image"]
```

## Splits

Single `train` split (training resource). For held-out evaluation use the separate
[BDRC Tibetan OCR benchmark](https://huggingface.co/datasets/BDRC/tibetan-ocr-benchmark).

## License, attribution & image rights

- **License: CC0-1.0** — use, modify, redistribute freely.
- **Attribution requested (not required):** please cite the **Buddhist Digital
  Resource Center (BDRC)** and **Palri Parkhang**.
- **⚠ Image-rights disclaimer:** BDRC claims no copyright over the scans, but
  verifying the copyright status of each underlying original book is the user's
  responsibility.

## Citation

```bibtex
@misc{bdrc_palri_parkhang_2026,
  title  = {Tibetan OCR --- Palri Parkhang (dbu-med manuscripts)},
  author = {Palri Parkhang and Buddhist Digital Resource Center},
  year   = {2026},
  howpublished = {Hugging Face},
  note   = {https://huggingface.co/datasets/BDRC/palri-parkhang}
}
```

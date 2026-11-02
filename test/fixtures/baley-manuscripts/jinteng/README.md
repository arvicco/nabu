# Jinteng 金縢

This package contains a documented, versioned aligned-text dataset for
`jinteng`.

This package is version 1.0.0.

## Quick start

See [`QUICKSTART.md`](QUICKSTART.md) for instructions for opening the bundled
viewer.

## Dataset

The dataset manifest is at [`dataset/manifest.json`](dataset/manifest.json).
It describes the witnesses, alignment, viewer configuration, and manuscript
media. The release includes:

- `shangshu`: 傳本《尚書·金縢》
- `tsinghua`: 清華簡壹《金縢》

The scholarly scope, sources, editorial decisions, and known limitations are
documented in `docs/`.

## Licence and provenance

See [`LICENSE.md`](LICENSE.md), `CONTRIBUTORS.md`, and
`witness-images/RIGHTS.md` for reuse terms and provenance.

## Validation

From the extracted package directory:

```bash
python3 tools/validate.py
```

## Citation

Please cite the archived version described by [`CITATION.cff`](CITATION.cff).

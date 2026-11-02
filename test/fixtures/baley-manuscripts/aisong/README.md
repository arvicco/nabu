# Digital Āisòng 哀誦

This package contains a documented, versioned aligned-text dataset for
`aisong`.

It aligns the Chen Qi (陳琦) editorial text with the Anda (安大簡)
manuscript witness at graph, line, and character level, using IDS
transcriptions and documented source mappings.

## Quick start

See [`QUICKSTART.md`](QUICKSTART.md) for instructions for opening the bundled
viewer.

## Dataset

The dataset manifest is at [`dataset/manifest.json`](dataset/manifest.json).
It describes the witnesses, alignment, viewer configuration, and optional
media. The release includes:

- `chenqi`: 陳琦
- `anda`: 安大簡

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

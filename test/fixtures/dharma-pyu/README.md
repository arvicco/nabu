# dharma-pyu fixtures

One whole real file from github.com/erc-dharma/tfc-pyu-epigraphy
(master; flat layout — editions at the repo root), retrieved 2026-09-01
from raw.githubusercontent.com, unmodified:

- `DHARMA_INSPYU00020.xml` — Pyu (`pyx-Latn`); the survey's own sample
  file (its in-file `<licence>` CC BY-SA 4.0 is the repo's whole grant —
  no repo-level LICENSE exists).

## Delivery grains

Upstream serves one TEI file per inscription at the repo root (the
accepted grain). REJECTED by rule (counted in `discovery_skips`, never
quarantined): **skeletons**, records committed before their
transcription ("skeleton — no citable text yet (upstream placeholder)").
Added 2026-11-05, copied whole and unmodified from the synced canonical
tree (both in-file CC BY-SA 4.0):

- `DHARMA_INSPYU00011.xml` — the skeleton specimen: textparts A/B each
  holding only `<ab><!--Transcription here--></ab>`.
- `DHARMA_INSPYU00120.xml` — the contrast pin: NOT a skeleton. Its
  numerals sit in a `<choice>` of bare `<num>` alternatives the family
  walk does not read, so it mints no unit despite real text — a defect,
  and it stays a quarantine.

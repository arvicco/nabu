# shabados fixtures

A trimmed real tree of the Shabad OS database collections —
`database/collections/` of github.com/shabados/shabados (branch main, HEAD
`307ed9d1a451561378c16beca6604d6fea523e6e`), retrieved 2026-10-12 from a
blobless sparse clone, mirroring the canonical layout
`canonical/shabados/database/collections/`.

What was kept, and how it was trimmed (structure intact — every id a kept
record names resolves to a kept file):

| record | trim |
|---|---|
| `sources/ARDS.toml` + section `TVPK`, its 9 line groups, 17 lines | whole — the Ardās |
| `sources/SGGS.toml` | `sections` list cut to `1DSA` (Jap); `sections/1DSA.toml`'s `lineGroups` cut to the first group (`DMP`, the Mūl Mantar opening at ang 1) |
| `sources/SDGR.toml` | `sections` cut to `3HWM` (Jaap) and `546R` (Zafarnāmā); each section's `lineGroups` cut to its first group — `KKH` carries nine lines with a SECOND primary (the Damdami Taksāl gutkā reading beside the Das Granthī), `HY2` the Persian Zafarnāmā opening |
| `lines/**` | each line record keeps its `type = "primary"` `[[content]]` entries only — the translation/note entries riding the same upstream records are not redistributed (they carry no grant of their own; the adapter never reads them) |
| `line-groups/**`, `authors/**`, `assets/**` | whole, for every id the kept records reference |

License: the database README identifies "gurbani and panthic texts" as
public domain (Public Domain Mark 1.0, https://creativecommons.org/publicdomain/mark/1.0/);
the repository's code and records structure are MIT ("Copyright (c) Shabad OS
Organization and Contributors"). Credit the Shabad OS Database.

Recipe (re-cut): `git clone --depth 1 --filter=blob:none --sparse
https://github.com/shabados/shabados`, `git sparse-checkout set --no-cone
/database/collections/`, then copy the records above, cutting the lists as
described and dropping every non-primary `[[content]]` block from the line
records (or cut from `canonical/shabados/` once synced).

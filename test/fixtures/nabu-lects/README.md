# nabu-lects fixtures (P57-3 — the consume seam)

**Verbatim, whole-file copies** of the two data files nabu-lects ships
(github.com/arvicco/nabu-lects), not trimmed samples — both files are
already small (340 + 40 lines) and the module's read seam
(`Nabu::Lects`) needs the full anchor/stage/variety/ortho graph and the
full codemap to be exercised honestly (a trimmed slice would hide
referential-integrity gaps the drift guard exists to catch).

- **Retrieved 2026-10-27** — the Iron Age Hebrew package (the obm
  Moabite anchor, parent sem, with its Garr 1985 dialect-geography
  note, and the hbo:epi Epigraphic Hebrew stage, band [-1000, -586],
  Gogel 1998), copied verbatim from canonical/nabu-lects (commit
  `4efe41b800ba`, `main`). `lects.yml` 176,356 B, sha256
  `7b96c52eed90ac43a74451fe77920d88d5617c1e6c4826c092e1ff71d18c2071`;
  `codemap.yml` unchanged from the previous cut.
- Previously retrieved 2026-10-22 — the Linear A package (the parentless `lab`
  anchor under the no-classification discipline, plus the lina / linb /
  cprt rows in the global scripts table), copied verbatim from
  canonical/nabu-lects (commit `9aec64ea1db4`, `main`); the same tree
  carries the 2026-10-22 registry-merge package (the +8 epigraphy/SEA
  anchors, Jyotsnikā-era stage rows and +11 codemap aliases) whose
  re-cut rode the previous phase. `lects.yml` 174,737 B, sha256
  `e3d039ffaae5e2275cc125c9abaec81b2abf54e7800f1d8e3788be0d33e6da1d`;
  `codemap.yml` unchanged from the previous cut.
- Previously retrieved 2026-10-21 — the chu:ncs (New Church Slavonic) stage
  and the Korean ladder (oko/okm, kor → ko codemap row), copied
  verbatim from canonical/nabu-lects (commit `b3d53b871f71`, `main`).
  `lects.yml` 143,939 B, sha256
  `c78c0930a0577f6af52ab26e183ec4c4b0ad99e5b5510c4aa65996c77a38377d`;
  `codemap.yml` 8,411 B, sha256
  `791cbe16ba9b4b9dd2e8a27e897a059425a3e9ce5f5c6c212d3306fde4ee1fbd`.
- Previously retrieved 2026-10-18 — the epigraphic-belt refresh (xpg, ecy,
  xna + saf/his/dad/tay varieties, xsa, inm, the grc/cyp variety —
  the merged mint, copied verbatim from canonical/nabu-lects).
- Previously retrieved 2026-10-11 — the Slavic-package refresh (the zlw /
  zlw-lch / zls families with chu, sl and bul re-wired onto zls; the
  pl and cs anchors with their old/mid stages, whose cs:old override
  target the drift guard now validates; sr, hr, mk; the chu recension
  varieties), from the box's `canonical/nabu-lects` (commit
  `25ff8313eecf`, the repo's `main`).
  - `lects.yml` — the lect registry (anchors, stages, varieties,
    orthographies, the global scripts table, parent edges, Glottocode
    crosswalks). Full file, 98,155 B, sha256
    `9e3d163b61d220ac3b6390be1dc365df46c52cbfb9fb3f1ba5a5f97d8b270dad`.
  - `codemap.yml` — universal code → lect defaults (identity is the
    default rule; only non-identity mappings are listed). Full file,
    7,055 B, sha256
    `34cedb9126390892e7825858ac2d67fc900081e6da3b427dbe1405c9d1b09950`.
- **License:** CC BY 4.0 (repo `LICENSE`, verbatim: "This work — the
  lect registry (lects.yml), the code mapping (codemap.yml), the
  documentation, and the validation tooling in this repository — is
  licensed under the Creative Commons Attribution 4.0 International
  License").
- `lect_overrides.yml` — NOT an upstream file: a fixture mirror of
  Nabu's own `config/lect_overrides.yml` FROZEN at the P57-3 seed
  state (derom + rundata, the two D-ruled overrides). Tests point
  here, never at the live config file, so live curation rows (D57-f
  and later) cannot silently change test outcomes; likewise no test
  may construct a query with the `:auto` lects default (the P57-4
  hermeticity lesson — suite results must not depend on whether this
  box has canonical/nabu-lects synced).

## What the files are

`lects.yml`'s `anchors:` map keys each anchor code (ISO 639 or an
established Wiktionary code) to `{name, kind (family|absent),
glottocode, band, band_note, parent, note, stages:, varieties:,
orthos:}`; each stage/variety/ortho carries its own `name` plus
type-specific fields (`ord`, `mode: reconstructed`, `band`, `wikt`,
`iso`, `note`; orthos a `script:` scope). A top-level `scripts:` map
(P60-0) is the GLOBAL script table for the `~` axis — lowercased ISO
15924 keys, rows `{name, iso15924}`; the axis claims the script of
the text AS HELD, never the artifact's. `codemap.yml`'s `map:` lists ONLY non-identity code →
lect-id defaults — any code absent from the map resolves to itself as
a bare anchor (the identity default rule).

Both files are read straight by `Nabu::Lects.load` (test/lects_test.rb)
and pinned as the module's registry row by
`Nabu::Adapters::NabuLects` (test/adapters/nabu_lects_test.rb). The
drift guard (test/lects_drift_test.rb) validates every codemap key and
every `config/lect_overrides.yml` override target against this exact
graph — refresh the two files together, or the guard will (correctly)
flag a stale mismatch.

## Refresh recipe

Copy `lects.yml` and `codemap.yml` verbatim from a clean checkout of
the upstream repo's `main`; update the retrieval date, commit and
sha256s above. If the identifier grammar or referential shape changed
upstream (pre-1.0 instability window — see the repo's own README),
re-check `lib/nabu/lects.rb`'s `ID_PATTERN` and the drift guard against
`bin/validate`'s rules before trusting a refreshed copy.

# nabu-lects fixtures (P57-3 — the consume seam)

**Verbatim, whole-file copies** of the two data files nabu-lects ships
(github.com/arvicco/nabu-lects), not trimmed samples — both files are
already small (340 + 40 lines) and the module's read seam
(`Nabu::Lects`) needs the full anchor/stage/variety/ortho graph and the
full codemap to be exercised honestly (a trimmed slice would hide
referential-integrity gaps the drift guard exists to catch).

- **Retrieved 2026-09-26** — the v1.6.2 refresh (the elx Elamite
  anchor; 143 anchors · 76 stages · 19 varieties · 2 orthographies ·
  27 scripts · 82 codemap mappings, `bin/validate` green), from the
  owner's live checkout (`~/Dev/nabu-lects`, clean at commit
  `89efffafb58f5ace8aa777cffc9175240ec7bfce`, the repo's `main`,
  tag v1.6.2).
  - `lects.yml` — the lect registry (anchors, stages, varieties,
    orthographies, the global scripts table, parent edges, Glottocode
    crosswalks). Full file, 46,866 B, sha256
    `97ec894561f3182a712faee5245323971c1195f286d8769899f38b0fb3dded8c`.
  - `codemap.yml` — universal code → lect defaults (identity is the
    default rule; only non-identity mappings are listed). Full file,
    4,420 B, sha256
    `08ba8c397e3ed7f5fbb3e6254cb3c731762cfe1f28fb46de34c27aa25025cb4c`.
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

# derge-tengyur fixtures

Real trimmed volume files from the Digital Derge Tengyur — Esukhia/Barom
Theksum Choling's annotated faithful copy of the Derge Tengyur edition.

- Upstream: https://github.com/Esukhia/derge-tengyur (NOT archived — but
  dormant: last push 2021-10-20; the adapter pins the commit below and
  aborts loudly on drift).
- Pinned commit: `174653137d62af481f53c6ae3dc842bf8629323e`
  (master HEAD, 2021-10-20).
- Retrieved: 2026-07-28, via
  `https://raw.githubusercontent.com/Esukhia/derge-tengyur/17465313…/text/<name>`.
- License (README §License, VERBATIM — README-only declaration, NO LICENSE
  file): "This work is a mechanical reproduction of a Public domain work,
  and as such is also in the Public domain." → license_class `open`.

## Format facts these trims pin (inspected in the real bytes)

- Same line grammar as the Kangyur: `[1b]` / `[1b.1]` citation brackets,
  `{D<toh>}` Tohoku boundaries (Tengyur numbers start at 1109 — disjoint
  from the Kangyur's 1–1108 by Tohoku-catalog design), `(error,correction)`
  and `{archaic,modern}` pairs.
- Files carry a UTF-8 BOM (`﻿` before `[1a]`) — the README says
  "no BOM"; reality wins, the parser strips it.
- `#` peydurma diplomatic-edition note reinsertion points (line 85 here,
  right after `{D1113}`).
- `[X]` error candidates: one real occurrence in the whole sampled corpus —
  `[པུཥྦཱུ]`, vol 212 line 3803 upstream (line 32 here).
- One real precomposed U+0F75 (TIBETAN VOWEL SIGN VOCALIC UU) at vol 001
  line 4075 upstream (line 92 here, char offset 325): upstream is
  NFD-by-convention, and Tibetan precomposed characters are
  composition-excluded, so `Normalize.nfc` deterministically decomposes it
  to U+0F71 U+0F74 — the NFC-determinism regression rides this line.
- Volume 213 (dkar chag, the catalog) carries no markers at all upstream:
  its text rides the last open document, exactly like any other unmarked
  volume continuation.

## Files (trims are 1-based inclusive line ranges of the upstream file)

- `text/001_བསྟོད་ཚོགས།_ཀ.txt` — lines 1–80, 693–700, 4072–4078 of the
  4,105-line original. Covers: BOM, `{D1109}` (line 3 here), `{D1110}`
  (line 55), a suggestion pair (line 76), `{D1113}` followed by a `#`
  note anchor (line 85), the U+0F75 line (line 92).
- `text/212_སྣ་ཚོགས།_པོ.txt` — lines 1–12, 1100–1106, 2012–2020,
  3800–3806. Covers: BOM, `{D4452}` (line 3 here), `{D4453}` (line 16),
  a suggestion pair (line 24), the `[པུཥྦཱུ]` error candidate (line 32).

Trimmed-corpus documents: toh1109, toh1110, toh1113 (spanning both volume
files — the multi-volume ref rule), toh4452, toh4453.

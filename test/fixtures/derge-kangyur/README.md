# derge-kangyur fixtures

Real trimmed volume files from the Digital Derge Kangyur — Esukhia/Barom
Theksum Choling proofreading (2014–2018) of the UVA-SOAS 2013 eKangyur,
an exact representation of the Library of Congress Derge woodblocks.

- Upstream: https://github.com/Esukhia/derge-kangyur (ARCHIVED June 2022 —
  frozen; moved to OpenPecha/P000001, which this source deliberately does
  NOT follow: the archived repo is the license-clean, immutable asset).
- Pinned commit: `a582cf471b7c85a101035071078032f106a8e536`
  (master HEAD, 2022-06-24 — the archival state; the adapter pins it).
- Retrieved: 2026-07-28, via
  `https://raw.githubusercontent.com/Esukhia/derge-kangyur/a582cf47…/text/<name>`.
- License (README §License, VERBATIM — README-only declaration, NO LICENSE
  file): "This work is a mechanical reproduction of a Public Domain work,
  and as such is also in the Public Domain." → license_class `open`.

## Format facts these trims pin (inspected in the real bytes)

- Every line opens with its own citation bracket: `[1b]` page/folio or
  `[1b.1]` page.line — no cross-line citation state exists.
- `{D<toh>}` text-boundary markers carry Tohoku catalog numbers. NB the
  README documents `{TX}`, but the data at the pinned HEAD uses `D` —
  reality wins; the parser accepts both prefixes. Subindexes are
  dash-suffixed (`{D1-1}`…), Tohoku-gap texts letter-suffixed (`{D846a}`).
- `{D1}` is immediately followed by `{D1-1}` on the same line: the parent
  Toh 1 has no text of its own — a container document.
- Volumes 002/004 carry ZERO markers: a Toh text spans whole volume files
  (Toh 1 runs vols 1–4), and pagination restarts per volume — the reason
  multi-volume documents volume-prefix their passage refs.
- `(error,correction)` suggestion pairs, e.g. `(པུ,བུ)` (100 line 71 here).
- `{archaic,modern}` pairs, e.g. `{སྷོ,སོ}` — used in the Kangyur data
  although only the Tengyur README documents them.
- No BOM in Kangyur files (the Tengyur files DO carry one).

## Files (trims are 1-based inclusive line ranges of the upstream file)

- `text/001_འདུལ་བ།_ཀ.txt` — lines 1–60, 760–770, 2070–2085, 4418–4430,
  4950–4958 of the 4,958-line original. Covers: empty [1a]/[1b] preamble,
  `{D1}{D1-1}` (line 4 here), an archaic pair (line 50), a suggestion pair
  (line 66), `{D1-2}` mid-line after toh1-1's closing archaic pair
  (line 78), `{D1-6}` (line 92), a bare `[49a]` page line, and the volume
  tail (D1-6 continues into volume 2).
- `text/002_འདུལ་བ།_ཁ.txt` — lines 1–20. No markers: pure continuation of
  D1-6, restarted pagination ([1a]…), volume-title line absorbed by the
  spanning text (upstream's own export_works.py behaviour).
- `text/100_གཟུངས་འདུས།_ཨེ.txt` — lines 1–60, 855–860, 990–998. Covers:
  a volume title line before the first marker, `{D846}`, the
  letter-suffixed `{D846a}` preceded by an archaic pair, `{D847}` starting
  mid-line, `{D848}`, `{D852}` with an in-mantra `(པུ,བུ)` suggestion pair.

Because every line is self-cited, cutting line ranges preserves structural
validity; the trimmed corpus is its own small canon (documents toh1 —
container —, toh1-1, toh1-2, toh1-6 spanning three volume files, toh846,
toh846a, toh847, toh848, toh852).

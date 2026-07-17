# suttacentral fixtures — SuttaCentral bilara-data (published branch)

Real files from the SuttaCentral segmented-text repository, retrieved
**2026-07-18** by cloning

    https://github.com/suttacentral/bilara-data  (branch `published`)
    commit cebbf6181dafbbde155cce7f0357426cc65e5668 (2026-07-16)

Every data file below is **byte-verbatim upstream, whole** — no trims —
kept at its upstream-relative path so `discover` walks the real layout.
The one exception is `_publication.json`, a documented SLICE (see below)
whose retained entry blocks are byte-identical to upstream lines.

## License chain (verified 2026-07-18, from the repo's own metadata)

Per-publication licensing lives in `_publication.json` (140 publications
censused at the pinned commit): **138 CC0** ("Creative Commons Zero",
abbreviation "CC0"), **1 Public Domain**, **1 CC BY-SA 3.0**. Verbatim:

- **scpub64** (the Mahāsaṅgīti root text, `root/pli/ms`):
  `"license_type": "Public Domain"`, url
  creativecommons.org/publicdomain/mark/1.0, statement: "This work is an
  ancient sacred text that was created thousands of years ago and is
  maintained to the present day by its traditional custodians, the
  Buddhist monastic Sangha. It is free of known restrictions under
  copyright law, including all related and neighboring rights. We
  respectfully request that it is used in accordance with the values of
  the Buddhist tradition."
- **scpub69** (Ānandajoti's English Patna Dhammapada,
  `translation/en/anandajoti/sutta/pdhp` — THE outlier):
  `"license_type": "Creative Commons Attribution-ShareAlike 3.0
  Unported"`, `"license_abbreviation": "CC BY-SA 3.0"`, url
  creativecommons.org/licenses/by-sa/3.0/. Its `-en` documents carry
  `license_override: attribution` (P10-4) while the source stays `open`.
- Every other publication: CC0. Repo `LICENSE.md` blanket, verbatim:
  "All translations created in Bilara and supported by SuttaCentral are
  dedicated to the Public Domain by means of the [Creative Commons
  Public Domain (CC0) license]" — the grant covering the few translation
  trees without their own publication record (e.g. suddhaso's MN files).

**EXCLUDED by honesty:** SuttaCentral's LEGACY translations (`html_text`
layer served from the separate `sc-data` repo — Bodhi, Ñāṇamoli etc.)
are largely **CC BY-NC-ND** and are a different repo/layer entirely.
This adapter never touches them; only bilara-data's own segmented
translations (CC0 + the one BY-SA) are ingested.

## Files

| fixture | whole? | exercises |
|---|---|---|
| `root/pli/ms/sutta/sn/sn35/sn35.24_root-pli-ms.json` | whole | plain sutta (13 segments incl. heading block 0.1–0.3); **`sn35.24:1.5` is an empty-string segment** (upstream reality, one of 14 corpus-wide) → skipped by rule |
| `translation/en/sujato/sutta/sn/sn35/sn35.24_translation-en-sujato.json` | whole | `-en` sibling; 12 segments, keys a subset of the root's KEY SET — with the honest asymmetry both ways: en `1.5` translates the root's EMPTY ellipsis segment ("The ear … nose …"), and the root's closing `1.10` ("Dutiyaṁ.") is untranslated — suffix equality aligns the shared ids, one-sided rows stay one-sided |
| `root/pli/ms/sutta/kn/dhp/dhp21-32_root-pli-ms.json` | whole | RANGE-STEM file: stem `dhp21-32`, but segment ids carry per-verse prefixes (`dhp21:1` … `dhp32:…`) that do NOT start with the stem → citation = the full segment id |
| `translation/en/sujato/sutta/kn/dhp/dhp21-32_translation-en-sujato.json` | whole | the priority translator's file (wins) |
| `translation/en/suddhaso/sutta/kn/dhp/dhp21-32_translation-en-suddhaso.json` | whole | the ALTERNATE translation of the same stem (one of 104 double-covered stems corpus-wide, all sujato+other) → skipped by rule, censused |
| `root/pra/pts/sutta/pdhp/pdhp1-13_root-pra-pts.json` | whole | the Patna Dhammapada root — language `pra`, inline `<unclear>` markup kept verbatim; segment ids `pdhp1:1`… (per-verse prefixes) |
| `translation/en/anandajoti/sutta/pdhp/pdhp1-13_translation-en-anandajoti.json` | whole | the CC BY-SA 3.0 outlier → `license_override: attribution` on the `-en` document |
| `root/pli/ms/xplayground/xplayground1_root-pli-ms.json` | whole | upstream's own sandbox file ("Do not commit this file to the main data repository" — committed anyway) → skipped by rule |
| `_publication.json` | SLICE | 6 of 140 publication entries (scpub1, scpub4, scpub7, scpub53, scpub64, scpub69), entry blocks byte-identical to upstream; drives the per-publication license gate + override |

## Format notes (upstream reality, do not "fix")

- One JSON object per file: a flat ordered map of `"<segment-id>":
  "text"`. Segment ids ARE SuttaCentral's citation scheme (`mn1:1.1`);
  JSON object order is document order (Ruby's JSON preserves it).
- Filenames: `<stem>_root-pli-ms.json` / `<stem>_root-pra-pts.json` /
  `<stem>_translation-en-<translator>.json`. The stem before the first
  `_` is the upstream text uid — the document identity.
- MOST files' segment ids start `"<stem>:"`; RANGE-STEM files
  (`dhp21-32`, `sn23.23-33`, `pli-tv-bu-vb-as1-7`, `pdhp1-13`… — 6,707
  segments corpus-wide) carry per-item prefixes instead. Citation rule:
  strip the redundant `"<stem>:"` prefix when present, else keep the
  full segment id (colons intact).
- Census at the pinned commit: **7,289** root pli files (incl. the one
  xplayground sandbox) + **22** root pra (pdhp) = 445,635 root segments,
  **14** of them empty strings; 100% NFC; **4,995** English translation
  files across 8 translators (247,158 segments); en keys are always a
  SUBSET of the root's keys (mn1: 325/334); 179 en stems have no
  pli/pra root (sujato's `name/` glossaries, patton's Āgama
  translations from lzh roots) → orphan-skipped; 104 stems have two
  translators (30 suddhaso+sujato, 73 soma+sujato, 1 kovilo+sujato).
- Root trees in the published branch: `root/pli/ms` (Mahāsaṅgīti — the
  Tipiṭaka), `root/pra/pts` (Patna Dhammapada), plus out-of-scope
  `root/en` (site blurbs/UI strings, not canon), `root/misc/site`,
  `root/san` (Sanskrit fragments), `root/lzh` (Chinese Āgamas).
- Text carries trailing spaces (segment-join artifacts) and, in pdhp,
  inline editorial pseudo-markup (`<unclear>…</unclear>`) — kept
  upstream-verbatim in the file; the adapter strips only edge
  whitespace per segment.
- 33 translation languages exist under `translation/`; this adapter
  ingests `en` only (the ORACC `-en` sibling precedent). Others are
  future config/scope decisions.
- The sc-data parallels graph (8,221 relations / 49,685 refs, declared
  non-copyrightable by SuttaCentral) lives in the SEPARATE `sc-data`
  repo — future intertext-packet material, not fetched here.

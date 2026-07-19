# suttacentral fixtures — SuttaCentral bilara-data (published branch)

Real files from the SuttaCentral segmented-text repository, retrieved
**2026-07-18** by cloning

    https://github.com/suttacentral/bilara-data  (branch `published`)
    commit cebbf6181dafbbde155cce7f0357426cc65e5668 (2026-07-16)

Every data file below is **byte-verbatim upstream, whole** — no trims —
kept at its upstream-relative path so `discover` walks the real layout.
The one exception is `_publication.json`, a documented SLICE (see below)
whose retained entry blocks are byte-identical to upstream lines.

**lzh additions (P32-1, 2026-07-19):** the three `root/lzh/sct` /
`translation/en/patton` files below were copied byte-verbatim (whole
files, `cp`) from the SYNCED canonical tree —
`canonical/suttacentral/` at commit
`84d95601727121cb85f24a52cc918369cd9c9bb3` (branch `published`,
2026-07-18) — zero network, per the packet's zero-fetch rule. The
`_publication.json` slice gained the two lzh-relevant entries
(scpub39, scpub20) from the same tree, entry blocks byte-identical.

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
- **scpub39** (the Literary Chinese Āgama roots, `root/lzh/sct` —
  censused at the canonical commit for the P32-1 scope flip):
  `"root_title": "SuttaCentral Taisho"`, subtitle "Texts from the
  Taisho Tripitaka edited for SuttaCentral", `"license_type":
  "Creative Commons Zero"`, `"license_abbreviation": "CC0"`, url
  creativecommons.org/publicdomain/zero/1.0/ → plain CC0, no override.
- **scpub20** (Charles Patton's English Saṃyukta Āgama,
  `translation/en/patton/sutta/sa`): `"license_type": "Creative
  Commons Zero"`, `"license_abbreviation": "CC0"` → plain CC0, no
  override. Its siblings scpub35 (`…/patton/sutta/ma`), scpub36
  (`…/patton/sutta/ea/ea19`) and scpub37 (`…/patton/sutta/da`) carry
  the IDENTICAL CC0 license block (censused, not in the slice);
  scpub36/scpub37 point at trees the published branch does not yet
  carry (patton's published files today: 39 sa + 15 ma).
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
| `root/lzh/sct/sutta/sa/sa101-200/sa158_root-lzh-sct.json` | whole | Literary Chinese Āgama root (P32-1): language `lzh`, edition `sct`, basket `sutta` / collection `sa`; 10 segments, heading block `0.1`–`0.2` → title "雜阿含經 — (一五八)"; trailing spaces on every segment (upstream reality) |
| `translation/en/patton/sutta/sa/sa101-200/sa158_translation-en-patton.json` | whole | patton's `-en` sibling of an lzh root — an ex-orphan (paired the moment `root/lzh/sct` entered scope); SAME 10 segment ids as the root (exact 1:1 here); publication scpub20, CC0 → no override |
| `root/lzh/sct/abhidhamma/sg/t1536.12_root-lzh-sct.json` | whole | lzh abhidhamma root with a Taisho-number stem (`t1536.12`); basket `abhidhamma` / collection `sg`; NO English file → honestly sibling-less |
| `_publication.json` | SLICE | 8 of 140 publication entries (scpub1, scpub4, scpub7, scpub20, scpub39, scpub53, scpub64, scpub69), entry blocks byte-identical to upstream; drives the per-publication license gate + override |
| `parallels/parallels.json` | SLICE | the sc-data parallels graph (P32-6): 10 of 8,221 relation entries, value-identical to upstream, at the adapter's fetch-target path (`parallels/`, not upstream's `relationship/`) — see below |

## The parallels graph slice (P32-6)

Fetched FRESH **2026-07-19** from the commit-pinned raw URL

    https://raw.githubusercontent.com/suttacentral/sc-data/8b3bcaf61c3e4d4d80dc131df3d1b7fb8d1d1311/relationship/parallels.json

(sc-data commit `8b3bcaf6…`, 2026-07-13, "sc issue 3003 adding iti
parallels" — the latest commit touching the file; whole-file sha256
`cba7f314a32aeecc9cba9381b5f6b781567be75c5dc69d5d1d755b2cd6465f1e`,
1,509,922 bytes, byte-identical to the 2026-07-16 scout snapshot).
10 relation entries kept, value-identical to upstream, covering the FULL
censused shape vocabulary (8,221 entries: 5,646 `parallels` + 2,512
`mentions` + 63 `retells`; 49,685 uid refs, 17,006 `~`-prefixed, 17,662
`#`-suffixed, 1,132 free-text print citations):

- `mentions` star with the SAME counterpart document cited at two
  segments (`mnd9#57.1`, `mnd9#61.1` → one document-grain edge);
- `parallels` with a `~` resolved-by-inference uid (`~sag#sag13`) plus
  the REVERSE re-assertion from the sag side (`["sag#sag13", "~sn1.1"]`
  → the same unordered pair, first-seen detail wins);
- a 10-uid `parallels` clique containing the free-text print citation
  `"Manusmṛti 6.77"` (skipped by rule, censused);
- the pinned **an7.68 clique** (`ea39.1`/`ma1`/`t27`/`t1536.8`, all with
  `#a-#b` Taishō line ranges) — the an7.68 ↔ ma1 edge both ends minted
  in the live catalog;
- a `retells` pair (`dn19` ↔ `cp5`);
- a `parallels` entry with two segments of ONE document (`ja546#256…`,
  `ja546#280…` → same-doc pair skipped, censused);
- a partial-only fan (`an4.16#3.1` + two `~` uids — full×partial edges
  only, never partial×partial) including the corpus's one
  `uid:segment` COLON variant (`~t765.132:10.0`, censused twice);
- the thig11.1 ↔ thi-ap19 pair asserted under TWO kinds (`mentions` +
  `retells` → one edge, both kind clauses in the detail).

License: sc-data ships NO license file; SuttaCentral's licensing page
states verbatim: "In addition, the reference data, including information
on parallels, is not an "original creation" and as such does not fall
within the scope of copyright." — and all original SuttaCentral material
is CC0 1.0.

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
  SUBSET of the root's keys (mn1: 325/334); 104 stems have two
  translators (30 suddhaso+sujato, 73 soma+sujato, 1 kovilo+sujato).
- lzh census (P32-1, at canonical commit `84d9560`): **272** root lzh
  files under `root/lzh/sct` — sutta 205 (ma 15 / sa 49 / ea 1 /
  lzh-minor 140) + abhidhamma 67 (sag 33 / lzh-dk 22 / sg 12) —
  38,646 segments, **2** empty (`ma10:23.5`, `t1537.21:54.0`); stems
  disjoint from the 7,311 pli+pra stems (zero collisions); **54**
  patton en files (39 sa + 15 ma, 4,038 segments, 6 empty) pair with
  lzh roots, none double-covered. Orphan en stems: **179** pre-flip →
  **125** post-flip (sujato's `name/` glossaries + en files whose
  roots bilara has not published) → still orphan-skipped by rule.
- Root trees in the published branch: in scope `root/pli/ms`
  (Mahāsaṅgīti — the Tipiṭaka), `root/pra/pts` (Patna Dhammapada),
  `root/lzh/sct` (Chinese Āgamas — SuttaCentral Taisho, in scope since
  P32-1); out-of-scope `root/en` (site blurbs/UI strings, not canon),
  `root/misc/site`, `root/san` (Sanskrit fragments).
- Text carries trailing spaces (segment-join artifacts) and, in pdhp,
  inline editorial pseudo-markup (`<unclear>…</unclear>`) — kept
  upstream-verbatim in the file; the adapter strips only edge
  whitespace per segment.
- 33 translation languages exist under `translation/`; this adapter
  ingests `en` only (the ORACC `-en` sibling precedent). Others are
  future config/scope decisions.
- The sc-data parallels graph (8,221 relations / 49,685 refs, declared
  non-copyrightable by SuttaCentral) lives in the SEPARATE `sc-data`
  repo — future intertext-packet material, not fetched here. Measured
  at P32-1 (against the scout's 2026-07-16 snapshot of
  `sc-data/misc/parallels.json`): **237 relations pair a minted
  pli/pra text with a minted lzh text** (223 `parallels` + 14
  `mentions`), touching 129 of the 272 lzh stems; ~110 more pli
  relations point at `da*` (Dīrgha Āgama) uids whose roots bilara has
  not published — they resolve only if upstream publishes them.

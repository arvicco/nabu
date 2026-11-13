# nabu-lects fixtures (P57-3 — the consume seam)

**Verbatim, whole-file copies** of the two data files nabu-lects ships
(github.com/arvicco/nabu-lects), not trimmed samples — both files are
already small (340 + 40 lines) and the module's read seam
(`Nabu::Lects`) needs the full anchor/stage/variety/ortho graph and the
full codemap to be exercised honestly (a trimmed slice would hide
referential-integrity gaps the drift guard exists to catch).

- **Retrieved 2026-11-13 (eighth cut)** — the big registry sitting
  (nabu-lects PR #48, merged this day): the ancient epigraphic
  anchors (xrr, cms, xmr, xcr, xlc), amh, hu with anc/old, ota, the
  historical Romance/Germanic/Iranian set (xno, pcd, nrf, dlm, srd,
  frk, nrn, xco), sio + sio:pro, map:pro/poz:pro, the nine
  Micronesian/Oceanic daughters, the dum re-band to [1050, 1500],
  the 639-1 mirror wave and the script-suffix rows — plus the
  seventh cut's nl:early (PR #47, same day). Copied verbatim from
  canonical/nabu-lects (synced 2026-11-13). `lects.yml` 286,121 B,
  sha256
  `1ef7f8ea3e51977562eda1b902c4a513e4459b424efd3a34f435ec28f991231d`;
  `codemap.yml` 16,077 B, sha256
  `c33a2c3b6853f6538c454baf4a203fcf3b74a80195be5a67e343bd6a7b48bbbc`.
- **Retrieved 2026-11-12 (sixth cut)** — the Albanian package (the sqj
  Albanoid family with sqj-pro, the sq anchor with its sq:old stage, the
  sqi/alb → sq codemap rows) that the titus-old-albanian lect row targets,
  with the Latin and Persian (lat stage notes, fa:cls widened, la-cla /
  la-eme) and Sámi packages and the MARC aliases merged since the fifth
  cut. Copied verbatim from canonical/nabu-lects (synced 2026-11-12).
  `lects.yml` 263,428 B, sha256
  `fec69f4325cbc56e2b8089216cf2c834d27c7b6480e1969977463d2b7bb256ca`;
  `codemap.yml` 14,001 B, sha256
  `ec51174ba1e6909ed8ab5f3ee0994081986820aa1887cba9f5225464807d38b7`.
- Previously retrieved 2026-11-05 (fifth cut) — the New Persian staging
  (fa:early / fa:cls), Middle Georgian (ka:mid), the pt, lad, sco
  (with sco:old), gd and xeb anchors, en:late, fr:cls, de:new, sv:run,
  and the codemap rows for the held catalog's unrouted spellings and
  script surfaces (jpn-Latn among them). Copied verbatim from
  canonical/nabu-lects (commit `a6547ea`, `main`, 2026-11-04).
  `lects.yml` 248,456 B, sha256
  `7307b88d9423b8c0a943f8a79971f7afc14215f3e42e4b609f3893bc9ec10095`;
  `codemap.yml` 13,216 B, sha256
  `2e134f2afdd9b9579b02f81401d0a212d8bea70cfd781748abe0af0ab004c35c`.
- Previously retrieved 2026-11-02 (fourth cut) — the Pacific,
  Vietnamese–Tai, Mongolic, Tangut and Yiddish package plus the
  Romanian package: the Malayo-Polynesian spine (pqe > poz-oce >
  poz-pcc > poz-pol > poz-pnp > poz-pep, poz-mic) with twelve Pacific
  leaves (mi, haw, ty, rar, rap, sm, to, fj, rtm, kos, pon, ch); vi
  with vi:old / vi:mid under the new mkh-vie Vietic family; za and
  tyz; cmg and xwo under xng; txg; yi with yi:old / yi:mid / yi:mod
  and the yi/west / yi/east varieties; ro with ro:old; the hani, mong
  and tang script rows; and the matching codemap aliases (mri/smo/ton/
  tah/fij/cha, vie, zha, mkh-mvi, yid/ydd/yih, ron/rum, the new proto
  codes). Copied verbatim from canonical/nabu-lects (commit `631a0b8`,
  `main`). `lects.yml` 237,128 B, sha256
  `7afa347ae432917bdb34dc951369095cdecfaba3b3b73e1a9c5c7c5c687b7e60`;
  `codemap.yml` 11,113 B, sha256
  `11553878ec4626bfb1126709c807369287ee6d9d7f72658cc2bfc69d22b8fbe0`.
- Previously retrieved 2026-10-30 (third cut) — the Italic minor-languages
  package: eleven anchors (xfa Faliscan, xve Venetic, spx South
  Picene, pgn Paelignian, umc Marrucinian, ims Marsian, xvs
  Vestinian, xvo Volscian, xhr Hernican, and the local-use qps
  Pre-Samnite / qcp Capenate for upstream tags unassigned in ISO
  639-3); no codemap rows (the ISO anchors resolve by identity).
  Copied verbatim from canonical/nabu-lects (commit `47b4193`,
  `main`). `lects.yml` 206,002 B, sha256
  `2aae4dbdb2d4ef58e170bc5366283d63cb404fd457604d1c091fee93035bbcb3`;
  `codemap.yml` 10,059 B, unchanged by the mint, sha256
  `747472d66bd881629b54d61b629a5867399ec682338b2a303bedd678beef8356`.

- **Retrieved 2026-10-27 (second cut)** — the South Asia / Greek-dialect
  package: the ta:old and ta:mid (Old / Middle Tamil), te:old (Old
  Telugu) and mr:old (Old Marathi) stages; the pmh (Maharastri
  Prakrit) and psu (Sauraseni Prakrit) anchors; the grc att / ion /
  dor / aeo dialect varieties; the ca (Catalan) anchor; the sinh
  (Sinhala) row in the global scripts table; the ofs philology
  backfill; and +11 codemap rows (oty → ta:old, ta-mid → ta:mid,
  omr → mr:old, pra-mah → pmh, pra-sau → psu, pra-ard → pka,
  grc-att / grc-ion / grc-dor / grc-aeo → the grc varieties,
  cat → ca). Copied verbatim from canonical/nabu-lects (commit
  `be79260a4bd9`, `main`). `lects.yml` 193,229 B, sha256
  `bb44785480f63ffdf9ebf4780273199fff41ba610bf6745fc42add922e54aed2`;
  `codemap.yml` 10,059 B, sha256
  `747472d66bd881629b54d61b629a5867399ec682338b2a303bedd678beef8356`.
- Previously retrieved 2026-10-27 — the Iron Age Hebrew package (the obm
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

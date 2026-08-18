# edubba-overlay fixtures

Trimmed REAL files from github.com/arvicco/nabu-edubba (retrieved
2026-08-11, working tree at ~/Dev/nabu-edubba): the two curated sign
pools (headers intact; 4 + 1-unclear rows kept from hiero-101, 3 from
hiero-102) and two codex sign pages verbatim (a24.md, g43.md). The
extraction contract (STABLE fields, additive-only) is Edubba's
2026-08-11 inbox note; structure documents their actual conventions —
never hand-write these.

## The cuneiform lanes (P77-8, added 2026-08-13)

Cut from the live canonical/edubba-overlay snapshot (same repo, real
bytes): `site/_data/sign_teaching.yml` (header + the AŠ/DIŠ entries —
the C101 record: iconicity, tier, taught_in, multi-line rows),
`assets-src/data/pool-102.yml` (header + E/GA/NIN/EŠ2 — confusables,
NIN's `osl_name: |SAL.TUG2|`, EŠ2's `etcsl_value`),
`assets-src/data/pool-103.yml` (header + ŠA/U3 — the Akkadian course:
freq_akkob, certainty `unclear`, U3's `osl_name: |IGI.DIB|` which is
also in the OSL fixture — the sign-card join test rides it), and four
codex pages verbatim across BOTH addenda dirs (a.md/nin.md Sumerian,
ab.md/sza.md Akkadian — one with and one without a pool row per dir).
`pool-s101.yml` (sinographs) is a future lane, deliberately not
fixtured.

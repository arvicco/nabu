# TLS fixtures — Thesaurus Linguae Sericae (tls-kr/tls-data)

Retrieved 2026-07-20 from https://github.com/tls-kr/tls-data (master,
pushed 2026-07-09). All files are byte-verbatim upstream except the
trims noted below. Layout mirrors the sparse fetch cone (`concepts/` +
`words/<hex>/` + `notes/doc` + `notes/swl` since P34-4).

## concepts/

- `TWO.xml` — a full-featured concept: translations, old-/modern-chinese
  criteria notes, taxonymy + hypernymy pointers, source references.
- `ABANDON.xml` — hypernymy pointer + source reference + the EMPTY
  `<div type="words">` slot that is the norm upstream (3,018 of 3,019
  files) — membership is inverted from the words side.
- `CRONY.xml` — the uuid-collision partner of the stray below.
- `%E5%AC%96…%E5%85%B8.xml` (percent-encoded Chinese basename) — the ONE
  upstream stray: different content but the SAME `xml:id` as CRONY.xml.
  Loading both would flap the entry revision on every sync, so the
  adapter skips `%`-bearing basenames by rule (censused in
  `discovery_skips`).

## words/

- `0/uuid-0002ba3b-….xml` — 陪貳, one entry (concept TWO), the full
  pinyin/OC/MC pron row.
- `f/uuid-fbba1aa8-….xml` — 棄, six entries (DISCARD … ABANDON …),
  entry-level `<def>` discussion, usg currency/valuation marks.
- `f/uuid-f27c793b-….xml` — 舍, eleven entries incl. REJECT twice and the
  捨 variant orth on its own entry block.
- `a/uuid-a5cc024e-….xml` — 勑, a real word with NO entries (one of two
  upstream): mints a minimal entry, not a skip.
- `e/uuid-ea74382d-….xml` — **TRIMMED**: the upstream file is the ONE
  empty-orth superEntry aggregate (305,395 bytes, 477 orth-less entries);
  the fixture keeps the real bytes of the root element + first entry with
  a closing `</superEntry>` appended. The adapter skips empty-orth
  superEntries by rule (censused).

## notes/ (P34-4 — the attestation crosswalk)

One `<textid>-ann.xml` per attested text; upstream files reach 13 MB, so
each fixture is **TRIMMED**: teiHeader + selected real `<seg>` blocks
byte-verbatim, closing tags appended. Retrieved 2026-07-20.

- `swl/KR1h0004-ann.xml` — 論語, the swl default-namespace `<ann>` shape;
  5 segs (005-22a.4, 009-19a.1, 013-30a.1, 017-27a.1, 018-31a.5) whose
  anns attest the fixture words 棄 and 舍 (不舍晝夜). All five pages
  exist as `<pb:KR1h0004_CHANT_…>` anchors in the synced kanripo text —
  the page-grain resolution path.
- `doc/KR1h0001-ann.xml` — 孟子, the doc-side `<tls:ann>` PREFIXED shape;
  2 segs (001-6a.7 棄甲曳兵而走, 008-21a.4).
- `doc/CH1a0907-ann.xml` — 說苑 under a NON-KR text id (CH…): the
  display-only citation path (nil cts_work, never invented); 2 segs
  (010-21a.6, 016-27a.2).

## LICENSE.md

Byte-verbatim upstream (CC BY-SA 4.0; sha256
`00ce3c549534e5e26393c4310350b355d610c0295a32ba9cafc7420cbedd3194`,
identical in tls-kr/tls-texts and tls-kr/tls-data). Both repos' READMEs
carry a CC BY 4.0 badge instead — the discrepancy is recorded in the
manifest; the LICENSE.md grant governs.

## Refresh recipe

```
git clone --depth 1 --filter=blob:none --no-checkout https://github.com/tls-kr/tls-data.git
cd tls-data && git sparse-checkout set concepts words notes/doc notes/swl && git checkout master
cp concepts/{TWO,ABANDON,CRONY}.xml <fixtures>/concepts/
cp 'concepts/%E5%AC%96'*.xml <fixtures>/concepts/
cp words/0/uuid-0002ba3b-*.xml <fixtures>/words/0/
cp words/f/uuid-fbba1aa8-*.xml words/f/uuid-f27c793b-*.xml <fixtures>/words/f/
cp words/a/uuid-a5cc024e-*.xml <fixtures>/words/a/
# trim words/e/uuid-ea74382d-*.xml to root + first </entry>, append </superEntry>
# trim notes/swl/KR1h0004-ann.xml, notes/doc/KR1h0001-ann.xml and
# notes/doc/CH1a0907-ann.xml to teiHeader + the segs listed above, append closing tags
cp LICENSE.md <fixtures>/
```

## N-A.xml addendum (2026-07-20, owner's first real sync)

`concepts/N-A.xml` (475 bytes, byte-verbatim from the synced canonical at
faee21a2) joined the trim after the first real sync quarantined the whole
concepts shelf: it is a genuinely empty placeholder — head "N/A",
definition `<p/>`, empty notes/pointers/words. Content-empty concepts
skip by rule (censused via `TlsXmlParser#skipped_empty_concepts`, 1
upstream); a concept with ANY content that fails to render still raises.

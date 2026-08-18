# ko-wikisource-mk fixtures (P78-4 — the korean axis's vernacular leg)

Real upstream sample of the **용비어천가** (龍飛御天歌, Songs of the
Dragons Flying to Heaven, 1447 — the first work ever printed in hangul)
from Korean Wikisource, in the adapter's own fetch envelope
(`pages/<slug>.json`, the WikiFetch per-page shape: title / pageid / ns /
revid / timestamp / **wikitext byte-verbatim as api.php served it**).

- **Upstream:** https://ko.wikisource.org/wiki/용비어천가
  (pageid 1740, revid **454577**, revision timestamp 2026-06-26T07:35:34Z)
  via `https://ko.wikisource.org/w/api.php` —
  `action=query&prop=revisions&rvprop=content|ids|timestamp&rvslots=main`.
- **Retrieved:** 2026-08-18.
- **License:** the 1447 text is public domain — the page's own license
  section carries `{{PD-old-100}}`; the wiki's transcription layer is
  **"Creative Commons Attribution-Share Alike 4.0"**
  (api.php `meta=siteinfo&siprop=rightsinfo` verbatim, verified
  2026-08-18; https://creativecommons.org/licenses/by-sa/4.0/deed.ko)
  → `license_class: attribution`, credit Korean Wikisource contributors.

## Upstream format reality (what this member preserves)

ONE wikitext page carries the whole work: a `{{머리말}}` header template
(`연도 = 1447` — the machine date), a hanmun preface (`== 龍飛御天歌 序 ==`
with the `=== 進《龍飛御天歌》箋 ===` dedication), then **all 125 cantos**
as `== 제N장 ==` sections (census 2026-08-18: 1–125 complete, none
missing). Layer marking is TEMPLATE-driven:

- **Middle Korean** — `{{옛한글 인라인|…}}` ("old hangul inline"), one per
  verse line (250 lines; every canto has ≥1), archaic conjoining jamo
  (ㆍ U+119E, ㅸ, U+A960/U+D7B0 extension blocks) + 방점 tone marks
  U+302E/U+302F.
- **Hanmun** — `{{윗주|漢字…|한글 reading…}}` ruby pairs under
  `=== 한문 ===` (always 2-arg; canto 47 carries PLAIN hanmun lines with
  no `윗주` wrapper — the parser handles both).
- **Modern rendering** — plain hangul prose under `=== 현대어 ===`
  (canto 125 carries its modern rendering as bare plain lines after the
  MK templates, with no heading).

Layer completeness is per-canto community reality (census 2026-08-18,
CONTENT-based — cantos 32–34 carry empty `한문`/`현대어` heading
scaffolding, which claims nothing): 34 cantos carry hanmun content,
29 carry a modern rendering (28 filled `현대어` sections + canto 125's
headingless one); the MK layer alone is complete across all 125
(250 `옛한글 인라인` lines).

**NFC reality (verified on this revision):** all 250 MK lines are
byte-identical under NFC — upstream already stores composed modern
syllables + decomposed archaic-jamo stacks, and archaic jamo have no
compositions to apply. Hangul NFC is SAFE for Middle Korean; no
NFC-exemption. NFKC would destroy compatibility/conjoining distinctions
and is never used.

## The members

| File | Why |
|---|---|
| `pages/yongbieocheonga.json` | the WHOLE work in one envelope, wikitext byte-verbatim — all 125 cantos, the three template-marked layers, the hanmun preface, the `{{머리말}}` machine date, canto 47's plain-hanmun variant and canto 125's headingless-modern variant (every parser branch witnessed by the one real page) |

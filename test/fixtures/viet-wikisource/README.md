# Viet-wikisource fixtures (P78-5 — the Vietnamese classical shelf on the sinitic axis)

Real wikisource pages for the `viet-wikisource` adapter
(`Nabu::Adapters::VietWikisource` / `WikisourceHanParser`). Retrieved
**2026-08-18** from `https://zh.wikisource.org/w/api.php` and
`https://vi.wikisource.org/w/api.php` via the exact request shape the
fetcher uses (`action=query&prop=revisions&rvprop=content|ids|timestamp
&rvslots=main&titles=…`, batched).

- Layout mirrors the canonical workdir the fetch writes:
  `pages/<curated id>.json` — the fetcher's per-page envelope
  (title/pageid/ns/revid/timestamp/wiki + the **wikitext byte-verbatim as
  api.php served it**). Filenames are the CURATED ids (the adapter's
  `PAGES` table is the naming authority), not title manglings.
- Pages chosen for layout coverage (all three censused shapes):
  - `dvsktt-ngoai-ky-1` — 大越史記全書/外紀卷之一 (zh, revid 2770143):
    the prose quyển anchor — {{header2}}, the == 紀 == / === ruler ===
    section tree, `{{annotate|…}}` interlinear 原注, the 史臣吳士連曰
    commentary paragraphs, the 卷之一終 closer.
  - `hich-tuong-si` — 諭諸裨將檄文 (zh, revid 2345859): headings-free
    prose, `{{header}}` with `year=1284` (the one dated page),
    `{{Textquality|25%}}`, `<sub>…</sub>` fanqie reading glosses
    (䚟，多改切 — an Ext-B codepoint riding as-is), the PD-boilerplate
    comment block. NOTE: the original-script hịch lives on
    **zh**.wikisource — vi.wikisource's "bản gốc" link 諭諸裨將檄文 is a
    redlink (censused 2026-08-18); its vi pages carry only phiên âm and
    translations.
  - `binh-ngo-dai-cao` — Bình Ngô đại cáo (vi, revid 205842): the
    parallel-poem shape — two-column layout table, first `<poem>` = the
    chữ Hán (per-character spacing upstream's own), second `<poem>` = the
    Hán-Việt phiên âm (18/18 stanzas once the `<ref>` editorial footnotes,
    one containing a blank line, are stripped), `{{đầu đề}}` header.

## The censused DVSKTT tree (zh.wikisource, 2026-08-18)

Index page 大越史記全書 (pageid 44811, {{Textquality|50%}}) is a TOC of
subpages `大越史記全書/<part>`: 卷首 + 外紀卷之一…五 + 本紀卷之一…十九 +
續編卷之一…五 — 29 quyển + front matter, the complete 1697 Chính Hòa
edition tree as the 1984–86 Tokyo collation counts it. One legacy
no-slash page (大越史記全書外紀卷之一, pageid 44848) is a #REDIRECT —
excluded from the curated list.

## License (verbatim, verified 2026-08-18)

- Every curated work carries `{{PD-old}}` — texts of 1272–1697, public
  domain.
- Both wikis' api.php `meta=siteinfo&siprop=rightsinfo`:
  *"Creative Commons Attribution-Share Alike 4.0"*
  (zh: creativecommons.org/licenses/by-sa/4.0/deed.zh,
  vi: …/deed.vi) — the transcription layer's grant.
- → `license_class: attribution` (PD text + CC BY-SA 4.0 transcription,
  the P47-s4 survey ruling).

A raw re-GET returns upstream's CURRENT revid — living wikis — so every
entry is `refetchable: false`: `fixtures:check` skips them and
`fixtures:refresh` refuses to touch them; drift is caught by the
revid-pinned fetch itself at any real re-sync.

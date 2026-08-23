# Menota fixtures — the Medieval Nordic Text Archive (clarino.uib.no)

Real upstream responses snapshotted **2026-08-23** from the Corpuscle
(korpuskel) REST API behind the Menota catalogue SPA
(https://clarino.uib.no/menota/catalogue/menota) and from menota.org.
The API flow (all endpoints verified live that day):

    GET <base>/rest?command=get-session                       → {"sessionId": …}
    GET <base>/rest?command=list-catalogue-documents
        &session-id=<s>&corpus=menota&start=<a>&end=<b>       → {"documents": […], "documentCount": 91}
    GET <base>/rest?command=download-document
        &session-id=<s>&corpus=menota&document-id=<id>        → {"data": "<TEI …>"}

with `<base>` = https://clarino.uib.no/korpuskel-api. Every endpoint is
session-gated (ephemeral session-id), so no static raw GET reproduces those
bytes — the session-gated entries are `refetchable: false` (the menotec/
iness-api posture). NOTE: clarino.uib.no's robots.txt says `User-agent: *`
/ `Disallow: /`; the crawl is nonetheless upstream-blessed — Stegmann
(2026-08-20, the №77-1 grant): "we will not keep you from scraping 😉"
until their bulk endpoint lands.

## texts/ — three Menota-TEI documents (the landed form)

What `Nabu::MenotaFetch` lands: the download-document envelope's `data`
string, UTF-8, byte-verbatim (CRLF line ends included). Chosen to cover
the three structural shapes of the archive (91-document census 2026-08-23):

- `texts/AM-1056-IX-4to.xml` — WHOLE (242 words). A fragment of Konungs
  skuggsjá, Old Norwegian (`textLang mainLang="nor"`), c. 1300. The full
  three-level shape: every `<w>`/`<pc>` carries `<choice>` with
  `<me:facs>`/`<me:dipl>`/`<me:norm>`, lemma + `me:msa` morphology,
  `pb/cb/lb` milestones (folio 1r–2v, columns A/B), `<lb>` breaks INSIDE
  word levels (`þur<lb/>fu`), `<c type="littNot">` initials, MUFI entities
  (&inodot; &vins; &trot; …), structured `<origDate notBefore="1280"
  notAfter="1310">`.
- `texts/NRA-norrfragm-60-A.xml` — WHOLE (120 words). A fragment of
  Stjórn, Old Icelandic (`mainLang="isl"`), c. 1350. `xml:id` on every
  token (`w100`, `w200`, …), heavy `<supplied>`/`<gap>` damage markup,
  all three levels.
- `texts/Holm-A-80.xml` — DOCUMENTED TRIM (3,755,022 B → 133,382 B).
  Birgitta Andersdotters bönbok, Old Swedish (NO `textLang`; langUsage
  `<language ident="swe">`), c. 1518–1532. The FACS-ONLY shape: plain
  `<w><me:facs>…</me:facs></w>` without `<choice>`, no dipl/norm, no
  lemma, `<me:punct>` punctuation. Trim: teiHeader + `<body>` byte-intact
  up to the token before `<pb ed="ms" n="3r"/>` (pages 2r–2v, 414 `<w>`,
  49 lines), then a synthetic `</p></div></body></text></TEI>` tail.

Catalogue census pinned by the tests (2026-08-23): 91 documents, license
column `CC-BY-SA 4.0` on ALL 91; per-file `<availability status="free">
<licence target="http://creativecommons.org/licenses/by-sa/4.0/">CC-BY-SA
4.0</licence>` (all three fixtures). Languages: isl 57, nor 27, swe 4,
dan 2, non 1. 86/91 carry the dipl level; the 5 without (incl. Holm A 80)
are facs-only.

## menota-entities.txt — the MUFI entity table

https://www.menota.org/menota-entities.txt, WHOLE (156,805 B, version of
10 December 2025, ~1,977 entities). The DOCTYPE of every Menota-TEI file
pulls it as an external entity set; the fetch lands it beside `texts/` and
the parser resolves `&inodot;` → ı, `&slong;` → ſ, `&vins;` → ꝩ (many map
into the MUFI Private Use Area). Refetchable — a stable public URL.

## catalogue/ — the API envelopes

- `catalogue/get-session.json` — WHOLE. `{"sessionId":"261913323160349",
  "userId":null,"userName":null}` (the sessionId is minted per request —
  a refetch can never byte-match).
- `catalogue/list-page-0-2.json` — WHOLE: a real `start=0&end=2` page
  (3 document rows, `documentCount` 91) — the envelope-shape pin, incl.
  per-row documentId/signature/title/license/language/origDate/wordCount
  and the facs/dipl/norm availability flags.
- `catalogue/download-AM-1056-IX-4to.json` — WHOLE: one real
  download-document envelope (`{"data": …}`, \uXXXX-escaped), whose
  decoded data is byte-identical to `texts/AM-1056-IX-4to.xml`.

## License

The catalogue license column (the quotable record, per the №77-1 grant) and
every sampled teiHeader: **CC BY-SA 4.0** → source class `attribution`.
